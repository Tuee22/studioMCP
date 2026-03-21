{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Worker.Server
  ( runWorkerMode,
    runWorkerServer,
  )
where

import Data.Aeson (ToJSON, decode, encode, object, (.=))
import Data.Text qualified as Text
import Data.Time (getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Network.HTTP.Client (Manager, defaultManagerSettings, newManager)
import Network.HTTP.Types
  ( hContentType,
    methodGet,
    methodPost,
    Status,
    status200,
    status400,
    status404,
    status500,
    status503,
  )
import Network.Wai
  ( Application,
    pathInfo,
    requestMethod,
    Response,
    responseLBS,
    strictRequestBody,
  )
import Network.Wai.Handler.Warp (defaultSettings, runSettings, setHost, setPort, setTimeout)
import StudioMCP.API.Health
  ( HealthReport (healthStatus),
    HealthStatus (Degraded, Healthy),
    probeDependencies,
  )
import StudioMCP.API.Version (VersionInfo, versionInfoForMode)
import StudioMCP.Config.Load (loadAppConfig)
import StudioMCP.Config.Types (AppConfig (..), AppMode (WorkerMode))
import StudioMCP.DAG.Executor (ExecutionReport (reportSummary))
import StudioMCP.DAG.Runtime
  ( PersistedRun (..),
    RuntimeConfig (..),
    runDagSpecEndToEnd,
  )
import StudioMCP.DAG.Summary (RunId (..), summaryRunId, summaryStatus)
import StudioMCP.DAG.Types (DagSpec)
import StudioMCP.DAG.Validator (validateDag)
import StudioMCP.Messaging.Pulsar (PulsarConfig (..))
import StudioMCP.Messaging.Topics (defaultExecutionTopic)
import StudioMCP.Result.Failure (FailureDetail)
import StudioMCP.Result.Types (Result (Failure, Success))
import StudioMCP.Storage.MinIO (MinIOConfig (..))
import StudioMCP.Util.Logging (configureProcessLogging)
import StudioMCP.Worker.Protocol
  ( WorkerExecutionRequest (..),
    WorkerExecutionResponse (..),
  )
import System.Environment (lookupEnv)

data WorkerEnv = WorkerEnv
  { workerAppConfig :: AppConfig,
    workerRuntimeConfig :: RuntimeConfig,
    workerHttpManager :: Manager
  }

data WorkerExecutionResult
  = WorkerExecutionCompleted WorkerExecutionResponse
  | WorkerExecutionRejected [FailureDetail]
  | WorkerExecutionFailed FailureDetail

runWorkerMode :: IO ()
runWorkerMode = do
  configureProcessLogging
  appConfig <- loadAppConfig
  port <- resolveWorkerPort
  runWorkerServer port appConfig

runWorkerServer :: Int -> AppConfig -> IO ()
runWorkerServer port appConfig = do
  workerEnv <- createWorkerEnv appConfig {appMode = WorkerMode}
  putStrLn ("studioMCP worker listening on 0.0.0.0:" <> show port)
  runSettings
    (setHost "0.0.0.0" (setPort port (setTimeout 0 defaultSettings)))
    (application workerEnv)

application :: WorkerEnv -> Application
application workerEnv request respond =
  case pathInfo request of
    ["execute"] | requestMethod request == methodPost -> do
      requestBody <- strictRequestBody request
      case decode requestBody of
        Nothing ->
          respond
            ( jsonResponse
                status400
                (object ["error" .= ("invalid-request-body" :: String)])
            )
        Just executionRequest ->
          handleExecution workerEnv executionRequest respond
    ["healthz"] | requestMethod request == methodGet ->
      handleHealth workerEnv respond
    ["version"] | requestMethod request == methodGet ->
      respond (jsonResponse status200 (currentVersionInfo workerEnv))
    _ ->
      respond
        ( jsonResponse
            status404
            (object ["error" .= ("not-found" :: String)])
        )

handleExecution ::
  WorkerEnv ->
  WorkerExecutionRequest ->
  (Response -> IO b) ->
  IO b
handleExecution workerEnv executionRequest respond = do
  result <- executeDag workerEnv (workerExecutionDag executionRequest)
  case result of
    WorkerExecutionCompleted workerExecutionResponse ->
      respond (jsonResponse status200 workerExecutionResponse)
    WorkerExecutionRejected failures ->
      respond (jsonResponse status400 (object ["failures" .= failures]))
    WorkerExecutionFailed failureDetail ->
      respond (jsonResponse status500 failureDetail)

handleHealth ::
  WorkerEnv ->
  (Response -> IO b) ->
  IO b
handleHealth workerEnv respond = do
  healthReport <- currentHealthReport workerEnv
  let statusValue =
        case healthStatus healthReport of
          Healthy -> status200
          Degraded -> status503
  respond (jsonResponse statusValue healthReport)

createWorkerEnv :: AppConfig -> IO WorkerEnv
createWorkerEnv appConfig = do
  let AppConfig _ pulsarHttp pulsarBinary minioUrl minioAccess minioSecret = appConfig
  manager <- newManager defaultManagerSettings
  pure
    WorkerEnv
      { workerAppConfig = appConfig,
        workerRuntimeConfig =
          RuntimeConfig
            { runtimePulsarConfig = PulsarConfig pulsarHttp pulsarBinary,
              runtimeMinioConfig = MinIOConfig minioUrl minioAccess minioSecret,
              runtimeTopicName = defaultExecutionTopic
            },
        workerHttpManager = manager
      }

executeDag :: WorkerEnv -> DagSpec -> IO WorkerExecutionResult
executeDag workerEnv dagSpec =
  case validateDag dagSpec of
    Failure failures ->
      pure (WorkerExecutionRejected failures)
    Success validDag -> do
      runIdValue <- freshRunId "worker-run"
      runResult <- runDagSpecEndToEnd (workerRuntimeConfig workerEnv) runIdValue validDag
      pure $
        case runResult of
          Left failureDetail ->
            WorkerExecutionFailed failureDetail
          Right persistedRun ->
            WorkerExecutionCompleted (executionResponse persistedRun)

currentHealthReport :: WorkerEnv -> IO HealthReport
currentHealthReport workerEnv =
  probeDependencies (workerHttpManager workerEnv) (workerAppConfig workerEnv)

currentVersionInfo :: WorkerEnv -> VersionInfo
currentVersionInfo workerEnv =
  versionInfoForMode (appMode (workerAppConfig workerEnv))

executionResponse :: PersistedRun -> WorkerExecutionResponse
executionResponse persistedRun =
  WorkerExecutionResponse
    { workerExecutionRunId = summaryRunId summaryValue,
      workerExecutionStatus = summaryStatus summaryValue,
      workerExecutionSummaryRef = persistedSummaryRef persistedRun,
      workerExecutionManifestRef = persistedManifestRef persistedRun,
      workerExecutionSummary = summaryValue
    }
  where
    summaryValue = reportSummary (persistedReport persistedRun)

jsonResponse :: ToJSON a => Status -> a -> Response
jsonResponse statusValue payload =
  responseLBS
    statusValue
    [(hContentType, "application/json")]
    (encode payload)

resolveWorkerPort :: IO Int
resolveWorkerPort = do
  maybePortText <- lookupEnv "STUDIO_MCP_WORKER_PORT"
  pure $
    case maybePortText >>= readMaybeInt of
      Just port -> port
      Nothing -> 3002

readMaybeInt :: String -> Maybe Int
readMaybeInt rawValue =
  case reads rawValue of
    [(value, "")] -> Just value
    _ -> Nothing

freshRunId :: String -> IO RunId
freshRunId prefix = do
  currentTime <- getCurrentTime
  pure
    ( RunId
        ( Text.pack prefix
            <> "-"
            <> Text.pack (formatTime defaultTimeLocale "%Y%m%d%H%M%S%q" currentTime)
        )
    )
