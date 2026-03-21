{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.MCP.Handlers
  ( ServerEnv (..),
    SubmissionResult (..),
    createServerEnv,
    currentHealthReport,
    currentMetricsSnapshot,
    currentVersionInfo,
    fetchSummary,
    submitDag,
  )
where

import Control.Concurrent (forkIO)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Network.HTTP.Client (Manager, defaultManagerSettings, newManager)
import StudioMCP.DAG.Executor (ExecutionReport (..))
import StudioMCP.API.Health (HealthReport, probeDependencies)
import StudioMCP.API.Metrics
  ( MetricsSnapshot,
    emptyMetricsSnapshot,
    recordRunCompletion,
    recordRunFailure,
  )
import StudioMCP.API.Version (VersionInfo, versionInfoForMode)
import StudioMCP.Config.Types (AppConfig (..))
import StudioMCP.DAG.Runtime
  ( PersistedRun (..),
    RuntimeConfig (..),
    runDagSpecEndToEnd,
  )
import StudioMCP.DAG.Summary (RunId (..), RunStatus (RunRunning), Summary, summaryStatus)
import StudioMCP.DAG.Types (DagSpec)
import StudioMCP.DAG.Validator (validateDag)
import StudioMCP.MCP.Protocol (SubmissionResponse (..))
import StudioMCP.Messaging.Topics (defaultExecutionTopic)
import StudioMCP.Result.Failure (FailureDetail)
import StudioMCP.Result.Types (Result (Failure, Success))
import StudioMCP.Storage.MinIO (MinIOConfig (..), readSummary)
import StudioMCP.Storage.Keys (summaryRefForRun)
import StudioMCP.Messaging.Pulsar (PulsarConfig (..))

data ServerEnv = ServerEnv
  { serverAppConfig :: AppConfig,
    serverRuntimeConfig :: RuntimeConfig,
    serverMetricsRef :: IORef MetricsSnapshot,
    serverHttpManager :: Manager
  }

data SubmissionResult
  = SubmissionAccepted SubmissionResponse
  | SubmissionRejected [FailureDetail]
  | SubmissionFailed FailureDetail

createServerEnv :: AppConfig -> IO ServerEnv
createServerEnv appConfig = do
  let AppConfig _ pulsarHttp pulsarBinary minioUrl minioAccess minioSecret = appConfig
  metricsRef <- newIORef emptyMetricsSnapshot
  manager <- newManager defaultManagerSettings
  pure
    ServerEnv
      { serverAppConfig = appConfig,
        serverRuntimeConfig =
          RuntimeConfig
            { runtimePulsarConfig = PulsarConfig pulsarHttp pulsarBinary,
              runtimeMinioConfig = MinIOConfig minioUrl minioAccess minioSecret,
              runtimeTopicName = defaultExecutionTopic
            },
        serverMetricsRef = metricsRef,
        serverHttpManager = manager
      }

submitDag :: ServerEnv -> DagSpec -> IO SubmissionResult
submitDag serverEnv dagSpec =
  case validateDag dagSpec of
    Failure failures ->
      pure (SubmissionRejected failures)
    Success validDag -> do
      runIdValue <- freshRunId "mcp-run"
      modifyIORef'
        (serverMetricsRef serverEnv)
        (recordRunCompletion runIdValue RunRunning)
      _ <-
        forkIO $ do
          runResult <- runDagSpecEndToEnd (serverRuntimeConfig serverEnv) runIdValue validDag
          case runResult of
            Left _failureDetail ->
              modifyIORef' (serverMetricsRef serverEnv) (recordRunFailure runIdValue)
            Right persistedRun ->
              modifyIORef'
                (serverMetricsRef serverEnv)
                (recordRunCompletion runIdValue (summaryStatus (reportSummary (persistedReport persistedRun))))
      pure
        ( SubmissionAccepted
            SubmissionResponse
              { submissionRunId = runIdValue,
                submissionStatus = RunRunning,
                submissionSummaryRef = summaryRefForRun runIdValue
              }
        )

fetchSummary :: ServerEnv -> RunId -> IO (Either FailureDetail Summary)
fetchSummary serverEnv runIdValue =
  readSummary
    (runtimeMinioConfig (serverRuntimeConfig serverEnv))
    (summaryRefForRun runIdValue)

currentHealthReport :: ServerEnv -> IO HealthReport
currentHealthReport serverEnv =
  probeDependencies (serverHttpManager serverEnv) (serverAppConfig serverEnv)

currentMetricsSnapshot :: ServerEnv -> IO MetricsSnapshot
currentMetricsSnapshot = readIORef . serverMetricsRef

currentVersionInfo :: ServerEnv -> VersionInfo
currentVersionInfo serverEnv =
  versionInfoForMode (appMode (serverAppConfig serverEnv))

freshRunId :: Text -> IO RunId
freshRunId prefix = do
  currentTime <- getCurrentTime
  pure
    ( RunId
        ( prefix
            <> "-"
            <> Text.pack (formatTime defaultTimeLocale "%Y%m%d%H%M%S%q" currentTime)
        )
    )
