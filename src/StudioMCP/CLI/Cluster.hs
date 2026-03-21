{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.CLI.Cluster
  ( runClusterCommand,
    runValidateCommand,
  )
where

import Control.Exception (bracket, bracket_, try)
import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Monad (forM_, unless, when)
import Data.Aeson (FromJSON, Value (..), decode, encode, object, (.=))
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import Data.ByteString.Char8 qualified as BS
import Data.ByteString.Lazy.Char8 qualified as LBS
import Data.Char (isSpace)
import Data.List (isInfixOf)
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Map.Strict as Map
import Network.HTTP.Client
  ( HttpException,
    Manager,
    Request (method, requestBody, requestHeaders),
    RequestBody (RequestBodyLBS),
    defaultManagerSettings,
    httpLbs,
    newManager,
    parseRequest,
    responseBody,
    responseStatus,
  )
import Network.HTTP.Types
  ( hContentType,
    methodGet,
    methodPost,
    status200,
  )
import Network.HTTP.Types.Status (statusCode)
import Network.Wai
  ( Application,
    pathInfo,
    requestMethod,
    responseLBS,
    strictRequestBody,
  )
import Network.Wai.Handler.Warp (defaultSettings, runSettings, setHost, setPort)
import StudioMCP.Config.Load (loadAppConfig)
import StudioMCP.Config.Types (AppConfig (..))
import Data.Yaml (decodeFileEither)
import StudioMCP.CLI.Command
  ( ClusterCommand (..),
    ClusterDeployTarget (..),
    ClusterStorageCommand (..),
    ValidateCommand (..),
  )
import StudioMCP.CLI.Docs (validateDocsCommand)
import StudioMCP.API.Health (DependencyHealth (..), HealthReport (..), HealthStatus (..))
import StudioMCP.API.Version (VersionInfo (..))
import StudioMCP.Inference.Host (runInferenceServer)
import StudioMCP.Inference.ReferenceModel (ReferenceModelConfig (..))
import StudioMCP.Inference.Types (InferenceRequest (..), InferenceResponse (..))
import StudioMCP.DAG.Runtime (validateEndToEndRuntime)
import StudioMCP.DAG.Parser (loadDagFile)
import StudioMCP.DAG.Summary (RunId (..), RunStatus (..), Summary (..))
import StudioMCP.DAG.Types
  ( DagSpec (..),
    NodeId (..),
    NodeKind (..),
    NodeSpec (..),
    OutputType (..),
    TimeoutPolicy (..),
  )
import StudioMCP.DAG.Validator (renderFailures, validateDag)
import StudioMCP.MCP.Protocol (SubmissionRequest (..), SubmissionResponse (..))
import StudioMCP.Messaging.Pulsar
  ( PulsarConfig (..),
    validatePulsarLifecycle,
  )
import StudioMCP.Result.Failure (FailureDetail (..))
import StudioMCP.Result.Types (Result (Failure, Success))
import StudioMCP.Storage.MinIO
  ( MinIOConfig (MinIOConfig),
    validateMinioRoundTrip,
  )
import StudioMCP.Tools.Boundary (validateBoundaryRuntime)
import StudioMCP.Tools.FFmpeg (validateFFmpegAdapter)
import StudioMCP.DAG.Executor (validateExecutorRuntime)
import StudioMCP.Worker.Protocol
  ( WorkerExecutionRequest (..),
    WorkerExecutionResponse (..),
  )
import StudioMCP.Worker.Server (runWorkerServer)
import System.Directory
  ( createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    findExecutable,
    getCurrentDirectory,
    getHomeDirectory,
    getTemporaryDirectory,
    removeFile,
  )
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (..), die)
import System.FilePath ((</>))
import System.IO (hClose, openTempFile)
import System.Process
  ( CreateProcess (std_err, std_out),
    StdStream (NoStream),
    callProcess,
    createProcess,
    proc,
    readProcessWithExitCode,
    terminateProcess,
    waitForProcess,
    ProcessHandle,
  )

runClusterCommand :: ClusterCommand -> IO ()
runClusterCommand command =
  case command of
    ClusterUpCommand -> clusterUp
    ClusterDownCommand -> clusterDown
    ClusterStatusCommand -> clusterStatus
    ClusterDeployCommand target -> clusterDeploy target
    ClusterStorageCommand ClusterStorageReconcile -> clusterStorageReconcile

runValidateCommand :: ValidateCommand -> IO ()
runValidateCommand command =
  case command of
    ValidateClusterCommand -> validateCluster
    ValidateDocsCommand -> validateDocsCommand
    ValidateE2ECommand -> validateE2E
    ValidateWorkerCommand -> validateWorker
    ValidatePulsarCommand -> validatePulsar
    ValidateMinioCommand -> validateMinio
    ValidateBoundaryCommand -> validateBoundary
    ValidateFFmpegAdapterCommand -> validateFFmpeg
    ValidateExecutorCommand -> validateExecutor
    ValidateMcpCommand -> validateMcp
    ValidateInferenceCommand -> validateInference
    ValidateObservabilityCommand -> validateObservability

clusterUp :: IO ()
clusterUp = do
  requireExecutables ["kind", "kubectl", "helm"]
  clusterName <- getClusterName
  cliDataRoot <- resolveCliDataRoot
  kindHostDataRoot <- resolveKindHostDataRoot
  clusters <- kindClusters
  if clusterName `elem` clusters
    then do
      ensureContainerClusterAccess clusterName
      putStrLn ("kind cluster '" <> clusterName <> "' already exists.")
    else do
      createDirectoryIfMissing True cliDataRoot
      withKindConfig clusterName kindHostDataRoot $ \configPath ->
        callProcess "kind" ["create", "cluster", "--name", clusterName, "--config", configPath]
      ensureContainerClusterAccess clusterName

clusterDown :: IO ()
clusterDown = do
  requireExecutables ["kind"]
  clusterName <- getClusterName
  clusters <- kindClusters
  if clusterName `elem` clusters
    then callProcess "kind" ["delete", "cluster", "--name", clusterName]
    else putStrLn ("kind cluster '" <> clusterName <> "' does not exist.")

clusterStatus :: IO ()
clusterStatus = do
  requireExecutables ["kind", "kubectl"]
  clusterName <- getClusterName
  clusters <- kindClusters
  if clusterName `notElem` clusters
    then die ("kind cluster '" <> clusterName <> "' is not running.")
    else do
      ensureContainerClusterAccess clusterName
      let contextName = "kind-" <> clusterName
      callProcess "kubectl" ["cluster-info", "--context", contextName]

clusterDeploy :: ClusterDeployTarget -> IO ()
clusterDeploy target = do
  requireExecutables
    ( case target of
        DeploySidecars -> ["kind", "helm"]
        DeployServer -> ["docker", "kind", "helm", "kubectl"]
    )
  clusterUp
  clusterStorageReconcile
  clusterName <- getClusterName
  when (target == DeployServer) $ do
    buildServerImage
    callProcess "kind" ["load", "docker-image", "studiomcp:latest", "--name", clusterName]
  let baseArgs =
        [ "upgrade"
        , "--install"
        , "studiomcp"
        , "chart"
        , "-f"
        , "chart/values.yaml"
        , "-f"
        , "chart/values-kind.yaml"
        , "--wait"
        ]
      args =
        case target of
          DeploySidecars -> baseArgs <> ["--set", "studiomcp.replicas=0"]
          DeployServer -> baseArgs
  callProcess "helm" args
  when (target == DeployServer) $ do
    callProcess "kubectl" ["rollout", "restart", "deployment/studiomcp"]
    callProcess "kubectl" ["rollout", "status", "deployment/studiomcp", "--timeout=180s"]

clusterStorageReconcile :: IO ()
clusterStorageReconcile = do
  requireExecutables ["kubectl"]
  cliDataRoot <- resolveCliDataRoot
  createDirectoryIfMissing True cliDataRoot
  mergedValues <- loadMergedValues
  let volumeSpecs = desiredPersistentVolumes mergedValues
  if null volumeSpecs
    then putStrLn "No persistent volumes requested by the current chart values."
    else do
      forM_ volumeSpecs $ \volumeSpec -> do
        createDirectoryIfMissing True (cliDataRoot </> volumeDirectory volumeSpec)
        applyManifest (renderPersistentVolume volumeSpec)
      putStrLn "Persistent volume definitions applied."

validateCluster :: IO ()
validateCluster = do
  requireExecutables ["kind", "kubectl", "helm"]
  clusterName <- getClusterName
  clusters <- kindClusters
  unless (clusterName `elem` clusters) $
    die ("kind cluster '" <> clusterName <> "' is not running.")
  ensureContainerClusterAccess clusterName
  let contextName = "kind-" <> clusterName
  callProcess "kubectl" ["cluster-info", "--context", contextName]
  putStrLn "Cluster validation passed."

validateE2E :: IO ()
validateE2E = do
  requireExecutables ["ffmpeg", "kubectl", "helm", "kind"]
  validateCluster
  requirePulsarDeployment
  requireMinioDeployment
  appConfig <- loadAppConfig
  withMinioPortForwardConfig appConfig $ \runtimeConfig -> do
    result <- validateEndToEndRuntime runtimeConfig
    case result of
      Left failureDetail -> die (renderFailureDetail failureDetail)
      Right () -> putStrLn "End-to-end validation passed."

validateWorker :: IO ()
validateWorker = do
  requireExecutables ["ffmpeg", "kind", "kubectl", "helm", "mc"]
  validateCluster
  requirePulsarDeployment
  requireMinioDeployment
  appConfig <- loadAppConfig
  validDag <- loadSubmissionDag "examples/dags/transcode-basic.yaml"
  manager <- newManager defaultManagerSettings
  withLocalWorkerConfig appConfig $ \workerAppConfig ->
    withWorkerServer 39002 workerAppConfig $ \baseUrl -> do
      waitForHttpStatus manager (baseUrl <> "/version") [200]
      invalidResponse <-
        httpJsonRequest
          manager
          "POST"
          (baseUrl <> "/execute")
          (Just (encode (WorkerExecutionRequest invalidSubmissionDag)))
      unless (httpResponseStatus invalidResponse == 400) $
        die ("Expected worker invalid execution to return HTTP 400, got " <> show (httpResponseStatus invalidResponse))
      validResponse <-
        httpJsonRequest
          manager
          "POST"
          (baseUrl <> "/execute")
          (Just (encode (WorkerExecutionRequest validDag)))
      unless (httpResponseStatus validResponse == 200) $
        die ("Expected worker execution to return HTTP 200, got " <> show (httpResponseStatus validResponse))
      executionResponse <- decodeResponseBody "worker execution response" validResponse
      unless (workerExecutionStatus (executionResponse :: WorkerExecutionResponse) == RunSucceeded) $
        die "Worker execution did not report a successful terminal summary."
      unless (summaryRunId (workerExecutionSummary executionResponse) == workerExecutionRunId executionResponse) $
        die "Worker execution returned a summary whose run id did not match the top-level response."
      healthResponse <- httpJsonRequest manager "GET" (baseUrl <> "/healthz") Nothing
      unless (httpResponseStatus healthResponse == 200) $
        die ("Expected worker /healthz to return HTTP 200, got " <> show (httpResponseStatus healthResponse))
      _ :: HealthReport <- decodeResponseBody "worker health response" healthResponse
      versionResponse <- httpJsonRequest manager "GET" (baseUrl <> "/version") Nothing
      unless (httpResponseStatus versionResponse == 200) $
        die ("Expected worker /version to return HTTP 200, got " <> show (httpResponseStatus versionResponse))
      versionInfo <- decodeResponseBody "worker version response" versionResponse
      unless (versionMode (versionInfo :: VersionInfo) == "worker") $
        die "Expected worker /version to report worker mode."
      putStrLn "Worker validation passed."

validatePulsar :: IO ()
validatePulsar = do
  requireExecutables ["kind", "kubectl", "helm"]
  validateCluster
  requirePulsarDeployment
  appConfig <- loadAppConfig
  let pulsarConfig =
        PulsarConfig
          { pulsarHttpEndpoint = pulsarHttpUrl appConfig,
            pulsarBinaryEndpoint = pulsarBinaryUrl appConfig
          }
  result <- validatePulsarLifecycle pulsarConfig
  case result of
    Left failureDetail -> die (renderFailureDetail failureDetail)
    Right () -> putStrLn "Pulsar validation passed."

validateMinio :: IO ()
validateMinio = do
  requireExecutables ["kind", "kubectl", "helm", "mc"]
  validateCluster
  requireMinioDeployment
  appConfig <- loadAppConfig
  withMinioPortForwardConfig appConfig $ \minioAppConfig -> do
    let AppConfig
          { minioEndpoint = endpoint,
            minioAccessKey = accessKey,
            minioSecretKey = secretKey
          } = minioAppConfig
        minioConfig =
          MinIOConfig endpoint accessKey secretKey
    result <- validateMinioRoundTrip minioConfig
    case result of
      Left failureDetail -> die (renderFailureDetail failureDetail)
      Right () -> putStrLn "MinIO validation passed."

validateBoundary :: IO ()
validateBoundary = do
  requireExecutables ["sh"]
  result <- validateBoundaryRuntime
  case result of
    Left failureDetail -> die (renderFailureDetail failureDetail)
    Right () -> putStrLn "Boundary validation passed."

validateFFmpeg :: IO ()
validateFFmpeg = do
  requireExecutables ["ffmpeg"]
  result <- validateFFmpegAdapter
  case result of
    Left failureDetail -> die (renderFailureDetail failureDetail)
    Right () -> putStrLn "FFmpeg adapter validation passed."

validateExecutor :: IO ()
validateExecutor = do
  result <- validateExecutorRuntime
  case result of
    Left failureDetail -> die (renderFailureDetail failureDetail)
    Right () -> putStrLn "Executor validation passed."

validateMcp :: IO ()
validateMcp = do
  requireExecutables ["docker", "kubectl", "kind", "helm"]
  clusterDeploy DeployServer
  validDag <- loadSubmissionDag "examples/dags/transcode-basic.yaml"
  manager <- newManager defaultManagerSettings
  withPortForward "service/studiomcp" 39000 3000 $ \baseUrl -> do
    waitForHttpStatus manager (baseUrl <> "/version") [200]
    invalidResponse <-
      httpJsonRequest
        manager
        "POST"
        (baseUrl <> "/runs")
        (Just (encode (SubmissionRequest invalidSubmissionDag)))
    unless (httpResponseStatus invalidResponse == 400) $
      die ("Expected MCP invalid submission to return HTTP 400, got " <> show (httpResponseStatus invalidResponse))
    validResponse <-
      httpJsonRequest
        manager
        "POST"
        (baseUrl <> "/runs")
        (Just (encode (SubmissionRequest validDag)))
    unless (httpResponseStatus validResponse == 201) $
      die ("Expected MCP valid submission to return HTTP 201, got " <> show (httpResponseStatus validResponse))
    submissionResponse <- decodeResponseBody "submission response" validResponse
    unless (submissionStatus submissionResponse == RunRunning) $
      die "Expected MCP submission to return a running status before the summary is persisted."
    summary <- waitForSummary manager baseUrl (submissionRunId submissionResponse)
    unless (summaryRunId summary == submissionRunId submissionResponse) $
      die "Summary retrieval returned a run id that did not match the submission response."
    unless (summaryStatus summary == RunSucceeded) $
      die "Submitted DAG did not complete successfully through the MCP surface."
    healthResponse <- httpJsonRequest manager "GET" (baseUrl <> "/healthz") Nothing
    unless (httpResponseStatus healthResponse == 200) $
      die ("Expected /healthz to return HTTP 200, got " <> show (httpResponseStatus healthResponse))
    _ :: HealthReport <- decodeResponseBody "health response" healthResponse
    versionResponse <- httpJsonRequest manager "GET" (baseUrl <> "/version") Nothing
    unless (httpResponseStatus versionResponse == 200) $
      die ("Expected /version to return HTTP 200, got " <> show (httpResponseStatus versionResponse))
    _ :: VersionInfo <- decodeResponseBody "version response" versionResponse
    metricsResponse <- httpJsonRequest manager "GET" (baseUrl <> "/metrics") Nothing
    unless (httpResponseStatus metricsResponse == 200) $
      die ("Expected /metrics to return HTTP 200, got " <> show (httpResponseStatus metricsResponse))
    unless ("studiomcp_runs_total" `isInfixOf` LBS.unpack (httpResponseBody metricsResponse)) $
      die "Expected /metrics to expose the studiomcp run counters."
    putStrLn "MCP validation passed."

validateInference :: IO ()
validateInference = do
  manager <- newManager defaultManagerSettings
  withFakeModelHost 38101 "Use typed validation before execution." $ do
    withInferenceServer
      38102
      (ReferenceModelConfig "http://127.0.0.1:38101/api/generate")
      $ do
        waitForHttpStatus manager "http://127.0.0.1:38102/healthz" [200]
        response <-
          httpJsonRequest
            manager
            "POST"
            "http://127.0.0.1:38102/advice"
            (Just (encode (InferenceRequest "Suggest a DAG repair for a missing summary node.")))
        unless (httpResponseStatus response == 200) $
          die ("Expected inference advice endpoint to return HTTP 200, got " <> show (httpResponseStatus response))
        inferenceResponse <- decodeResponseBody "inference response" response
        unless ("ADVISORY:" `Text.isPrefixOf` inferenceAdvice (inferenceResponse :: InferenceResponse)) $
          die "Inference advice did not preserve the advisory guardrail prefix."
  withInferenceServer
    38103
    (ReferenceModelConfig "http://127.0.0.1:39999/api/generate")
    $ do
      waitForHttpStatus manager "http://127.0.0.1:38103/healthz" [200]
      failureResponse <-
        httpJsonRequest
          manager
          "POST"
          "http://127.0.0.1:38103/advice"
          (Just (encode (InferenceRequest "Suggest a DAG repair for a missing summary node.")))
      unless (httpResponseStatus failureResponse == 502) $
        die ("Expected unavailable model host to return HTTP 502, got " <> show (httpResponseStatus failureResponse))
  putStrLn "Inference validation passed."

validateObservability :: IO ()
validateObservability = do
  requireExecutables ["docker", "kubectl", "kind", "helm"]
  clusterDeploy DeployServer
  validDag <- loadSubmissionDag "examples/dags/transcode-basic.yaml"
  manager <- newManager defaultManagerSettings
  withPortForward "service/studiomcp" 39001 3000 $ \baseUrl -> do
    waitForHttpStatus manager (baseUrl <> "/version") [200]
    submissionResponse <- submitDagOverHttp manager baseUrl validDag
    _ <- waitForSummary manager baseUrl (submissionRunId submissionResponse)
    metricsBody <- waitForMetricsBody manager baseUrl ["studiomcp_runs_total 1", "studiomcp_runs_succeeded_total 1"]
    unless ("studiomcp_runs_total 1" `isInfixOf` metricsBody) $
      die "Expected /metrics to show a completed run."
    unless ("studiomcp_runs_succeeded_total 1" `isInfixOf` metricsBody) $
      die "Expected /metrics to show a completed successful run."
    deploymentLogs <- waitForLogFragments "deployment/studiomcp" ["runId=", "nodeId="]
    unless ("runId=" `isInfixOf` deploymentLogs && "nodeId=" `isInfixOf` deploymentLogs) $
      die "Expected deployment logs to contain runId and nodeId correlation fields."
    withScaledDeployment "studiomcp-pulsar" 0 1 $ do
      waitForHttpStatus manager (baseUrl <> "/healthz") [503]
      healthResponse <- httpJsonRequest manager "GET" (baseUrl <> "/healthz") Nothing
      healthReport <- decodeResponseBody "degraded health response" healthResponse
      unless (healthStatus (healthReport :: HealthReport) == Degraded) $
        die "Expected /healthz to return a degraded health report when Pulsar is unavailable."
      unless (any ((== Degraded) . dependencyStatus) (healthDependencies healthReport)) $
        die "Expected /healthz to include at least one degraded dependency."
  putStrLn "Observability validation passed."

submitDagOverHttp :: Manager -> String -> DagSpec -> IO SubmissionResponse
submitDagOverHttp manager baseUrl dagSpec = do
  validResponse <-
    httpJsonRequest
      manager
      "POST"
      (baseUrl <> "/runs")
      (Just (encode (SubmissionRequest dagSpec)))
  unless (httpResponseStatus validResponse == 201) $
    die ("Expected DAG submission to return HTTP 201, got " <> show (httpResponseStatus validResponse))
  decodeResponseBody "submission response" validResponse

withInferenceServer :: Int -> ReferenceModelConfig -> IO a -> IO a
withInferenceServer port referenceModelConfig action =
  bracket
    (forkIO (runInferenceServer port referenceModelConfig))
    killThread
    (\_ -> action)

withWorkerServer :: Int -> AppConfig -> (String -> IO a) -> IO a
withWorkerServer port appConfig action =
  bracket
    (forkIO (runWorkerServer port appConfig))
    killThread
    (\_ -> do
        manager <- newManager defaultManagerSettings
        waitForHttpStatus manager ("http://127.0.0.1:" <> show port <> "/version") [200]
        action ("http://127.0.0.1:" <> show port)
    )

withFakeModelHost :: Int -> Text -> IO a -> IO a
withFakeModelHost port adviceText action =
  bracket
    (forkIO (runSettings (setHost "127.0.0.1" (setPort port defaultSettings)) (fakeModelHostApplication adviceText)))
    killThread
    (\_ -> do
        manager <- newManager defaultManagerSettings
        waitForHttpStatus manager ("http://127.0.0.1:" <> show port <> "/healthz") [200]
        action
    )

fakeModelHostApplication :: Text -> Application
fakeModelHostApplication adviceText request respond =
  case pathInfo request of
    ["api", "generate"] | requestMethod request == methodPost -> do
      _ <- strictRequestBody request
      respond
        ( responseLBS
            status200
            [(hContentType, "application/json")]
            (encode (object ["response" .= adviceText]))
        )
    ["healthz"] | requestMethod request == methodGet ->
      respond
        ( responseLBS
            status200
            [(hContentType, "application/json")]
            (encode (object ["status" .= ("ready" :: String)]))
        )
    _ ->
      respond
        ( responseLBS
            status200
            [(hContentType, "application/json")]
            (encode (object ["status" .= ("ready" :: String)]))
        )

withScaledDeployment :: String -> Int -> Int -> IO a -> IO a
withScaledDeployment deploymentName scaledDownReplicas restoredReplicas =
  bracket_
    ( do
        callProcess "kubectl" ["scale", "deployment/" <> deploymentName, "--replicas", show scaledDownReplicas]
        callProcess "kubectl" ["rollout", "status", "deployment/" <> deploymentName, "--timeout=180s"]
    )
    ( do
        callProcess "kubectl" ["scale", "deployment/" <> deploymentName, "--replicas", show restoredReplicas]
        callProcess "kubectl" ["rollout", "status", "deployment/" <> deploymentName, "--timeout=180s"]
    )

withMinioPortForwardConfig :: AppConfig -> (AppConfig -> IO a) -> IO a
withMinioPortForwardConfig appConfig action =
  withPortForward "service/studiomcp-minio" 39010 9000 $ \baseUrl -> do
    manager <- newManager defaultManagerSettings
    waitForHttpStatus manager (baseUrl <> "/minio/health/live") [200]
    action appConfig {minioEndpoint = Text.pack baseUrl}

withLocalWorkerConfig :: AppConfig -> (AppConfig -> IO a) -> IO a
withLocalWorkerConfig appConfig action =
  withPortForward "service/studiomcp-pulsar" 39011 8080 $ \pulsarHttpBaseUrl -> do
    manager <- newManager defaultManagerSettings
    waitForHttpStatus manager (pulsarHttpBaseUrl <> "/admin/v2/clusters") [200]
    withMinioPortForwardConfig
      appConfig {pulsarHttpUrl = Text.pack pulsarHttpBaseUrl}
      action

requireExecutables :: [String] -> IO ()
requireExecutables commands =
  forM_ commands $ \command -> do
    executable <- findExecutable command
    when (executable == Nothing) $
      die ("Required executable is not available: " <> command)

buildServerImage :: IO ()
buildServerImage = do
  buildxConfigDir <- (</> "studiomcp-buildx") <$> getTemporaryDirectory
  createDirectoryIfMissing True buildxConfigDir
  previousBuildxConfig <- lookupEnv "BUILDX_CONFIG"
  bracket_
    (setEnv "BUILDX_CONFIG" buildxConfigDir)
    ( case previousBuildxConfig of
        Just value -> setEnv "BUILDX_CONFIG" value
        Nothing -> unsetEnv "BUILDX_CONFIG"
    )
    ( callProcess
        "docker"
        [ "buildx",
          "build",
          "--load",
          "--progress=plain",
          "-t",
          "studiomcp:latest",
          "-f",
          "docker/Dockerfile",
          "--target",
          "production",
          "."
        ]
    )

data HttpResponse = HttpResponse
  { httpResponseStatus :: Int,
    httpResponseBody :: LBS.ByteString
  }

httpJsonRequest :: Manager -> String -> String -> Maybe LBS.ByteString -> IO HttpResponse
httpJsonRequest manager methodValue url maybeBody = do
  request <- parseRequest url
  response <-
    httpLbs
      request
        { method = BS.pack methodValue,
          requestHeaders =
            case maybeBody of
              Just _ -> [("Content-Type", "application/json")]
              Nothing -> [],
          requestBody =
            case maybeBody of
              Just body -> RequestBodyLBS body
              Nothing -> requestBody request
        }
      manager
  pure
    HttpResponse
      { httpResponseStatus = statusCode (responseStatus response),
        httpResponseBody = responseBody response
      }

decodeResponseBody :: FromJSON a => String -> HttpResponse -> IO a
decodeResponseBody label httpResponse =
  case decode (httpResponseBody httpResponse) of
    Just value -> pure value
    Nothing ->
      die
        ( "Could not decode "
            <> label
            <> " from HTTP body:\n"
            <> LBS.unpack (httpResponseBody httpResponse)
        )

withPortForward :: String -> Int -> Int -> (String -> IO a) -> IO a
withPortForward target localPort remotePort action =
  bracket
    ( do
        (_, _, _, processHandle) <-
          createProcess
            (proc "kubectl" ["port-forward", target, show localPort <> ":" <> show remotePort])
              { std_out = NoStream,
                std_err = NoStream
              }
        pure processHandle
    )
    (\processHandle -> terminateProcess processHandle >> voidWait processHandle)
    (\_ -> action ("http://127.0.0.1:" <> show localPort))

waitForHttpStatus :: Manager -> String -> [Int] -> IO ()
waitForHttpStatus manager url expectedStatuses =
  go (30 :: Int)
  where
    go 0 =
      die ("Timed out waiting for HTTP readiness at " <> url)
    go remainingAttempts = do
      responseOrException <- tryHttp (httpJsonRequest manager "GET" url Nothing)
      case responseOrException of
        Right response
          | httpResponseStatus response `elem` expectedStatuses ->
              pure ()
        _ -> do
          threadDelay 1000000
          go (remainingAttempts - 1)

waitForSummary :: Manager -> String -> RunId -> IO Summary
waitForSummary manager baseUrl runIdValue =
  go (60 :: Int)
  where
    summaryUrl = baseUrl <> "/runs/" <> Text.unpack (unRunId runIdValue) <> "/summary"

    go 0 =
      die ("Timed out waiting for a persisted summary at " <> summaryUrl)
    go remainingAttempts = do
      responseOrException <- tryHttp (httpJsonRequest manager "GET" summaryUrl Nothing)
      case responseOrException of
        Right response
          | httpResponseStatus response == 200 ->
              decodeResponseBody "summary response" response
          | httpResponseStatus response == 404 -> retry remainingAttempts
          | otherwise ->
              die ("Expected summary retrieval to return HTTP 200 or 404 while pending, got " <> show (httpResponseStatus response))
        Left _ -> retry remainingAttempts

    retry remainingAttempts = do
      threadDelay 1000000
      go (remainingAttempts - 1)

waitForMetricsBody :: Manager -> String -> [String] -> IO String
waitForMetricsBody manager baseUrl expectedFragments =
  go (60 :: Int)
  where
    metricsUrl = baseUrl <> "/metrics"

    go 0 =
      die ("Timed out waiting for metrics at " <> metricsUrl)
    go remainingAttempts = do
      responseOrException <- tryHttp (httpJsonRequest manager "GET" metricsUrl Nothing)
      case responseOrException of
        Right response
          | httpResponseStatus response == 200 ->
              let metricsBody = LBS.unpack (httpResponseBody response)
               in if all (`isInfixOf` metricsBody) expectedFragments
                    then pure metricsBody
                    else retry remainingAttempts
          | otherwise ->
              retry remainingAttempts
        Left _ -> retry remainingAttempts

    retry remainingAttempts = do
      threadDelay 1000000
      go (remainingAttempts - 1)

waitForLogFragments :: String -> [String] -> IO String
waitForLogFragments target expectedFragments =
  go (60 :: Int)
  where
    go 0 =
      die ("Timed out waiting for log output from " <> target)
    go remainingAttempts = do
      (exitCode, stdoutText, _) <- readProcessWithExitCode "kubectl" ["logs", target, "--tail=200"] ""
      case exitCode of
        ExitSuccess
          | all (`isInfixOf` stdoutText) expectedFragments -> pure stdoutText
          | otherwise -> retry remainingAttempts
        ExitFailure _ -> retry remainingAttempts

    retry remainingAttempts = do
      threadDelay 1000000
      go (remainingAttempts - 1)

loadSubmissionDag :: FilePath -> IO DagSpec
loadSubmissionDag dagPath = do
  decoded <- loadDagFile dagPath
  case decoded of
    Left parseFailure ->
      die ("Could not parse DAG fixture " <> dagPath <> ": " <> parseFailure)
    Right dagSpec ->
      case validateDag dagSpec of
        Success validDag -> pure validDag
        Failure failures ->
          die ("DAG fixture did not validate: " <> renderFailures failures)

invalidSubmissionDag :: DagSpec
invalidSubmissionDag =
  DagSpec
    { dagName = "invalid-mcp-submission",
      dagDescription = Just "DAG without a required summary node.",
      dagNodes =
        [ NodeSpec
            { nodeId = NodeId "ingest",
              nodeKind = PureNode,
              nodeTool = Nothing,
              nodeInputs = [],
              nodeOutputType = OutputType "text/plain",
              nodeTimeout = TimeoutPolicy 5,
              nodeMemoization = "memoize"
            }
        ]
    }

tryHttp :: IO a -> IO (Either HttpException a)
tryHttp = try

voidWait :: ProcessHandle -> IO ()
voidWait processHandle = do
  _ <- waitForProcess processHandle
  pure ()

requirePulsarDeployment :: IO ()
requirePulsarDeployment = do
  (exitCode, _, stderrText) <-
    readProcessWithExitCode "kubectl" ["get", "deployment/studiomcp-pulsar", "-o", "name"] ""
  case exitCode of
    ExitSuccess -> pure ()
    ExitFailure _ ->
      die
        ( "Pulsar deployment is not available in the cluster. "
            <> "Deploy sidecars first with `studiomcp cluster deploy sidecars`.\n"
            <> stderrText
        )

requireMinioDeployment :: IO ()
requireMinioDeployment = do
  (exitCode, _, stderrText) <-
    readProcessWithExitCode "kubectl" ["get", "deployment/studiomcp-minio", "-o", "name"] ""
  case exitCode of
    ExitSuccess -> pure ()
    ExitFailure _ ->
      die
        ( "MinIO deployment is not available in the cluster. "
            <> "Deploy sidecars first with `studiomcp cluster deploy sidecars`.\n"
            <> stderrText
        )

kindClusters :: IO [String]
kindClusters = do
  (exitCode, stdoutText, stderrText) <- readProcessWithExitCode "kind" ["get", "clusters"] ""
  case exitCode of
    ExitSuccess -> pure (filter (not . null) (lines stdoutText))
    ExitFailure _ -> die stderrText

getClusterName :: IO String
getClusterName = fromMaybe "studiomcp" <$> lookupEnv "STUDIOMCP_KIND_CLUSTER"

resolveCliDataRoot :: IO FilePath
resolveCliDataRoot = do
  containerDataRootExists <- doesDirectoryExist "/.data"
  if containerDataRootExists
    then pure "/.data"
    else do
      cwd <- getCurrentDirectory
      pure (cwd </> ".data")

resolveKindHostDataRoot :: IO FilePath
resolveKindHostDataRoot = do
  explicitHostPath <- fmap normalizeOptionalPath (lookupEnv "STUDIOMCP_KIND_HOST_DATA_PATH")
  runningInContainer <- doesFileExist "/.dockerenv"
  case explicitHostPath of
    Just hostPath -> pure hostPath
    Nothing
      | runningInContainer -> do
          currentContainerName <- readCurrentContainerName
          maybeMountedSource <- readMountedHostPath currentContainerName "/.data"
          case maybeMountedSource of
            Just mountedSource -> pure mountedSource
            Nothing ->
              die
                "Could not resolve the host-visible .data mount from the outer container. Set STUDIOMCP_KIND_HOST_DATA_PATH explicitly."
      | otherwise -> do
          cwd <- getCurrentDirectory
          pure (cwd </> ".data")

withKindConfig :: String -> FilePath -> (FilePath -> IO a) -> IO a
withKindConfig clusterName dataRoot action = do
  tempDir <- getTemporaryDirectory
  bracket
    (openTempFile tempDir "studiomcp-kind-config.yaml")
    (\(configPath, handle) -> hClose handle >> removeFile configPath)
    (\(configPath, handle) -> do
        LBS.hPutStr handle (renderKindConfig clusterName dataRoot)
        hClose handle
        action configPath
    )

ensureContainerKubeconfig :: String -> IO ()
ensureContainerKubeconfig clusterName = do
  runningInContainer <- doesFileExist "/.dockerenv"
  when runningInContainer $ do
    kubeconfigText <- readKindKubeconfig clusterName
    homeDirectory <- getHomeDirectory
    let kubeDirectory = homeDirectory </> ".kube"
        kubeconfigPath = kubeDirectory </> "config"
    createDirectoryIfMissing True kubeDirectory
    writeFile kubeconfigPath kubeconfigText

ensureContainerClusterAccess :: String -> IO ()
ensureContainerClusterAccess clusterName = do
  ensureContainerOnKindNetwork
  ensureContainerKubeconfig clusterName

readKindKubeconfig :: String -> IO String
readKindKubeconfig clusterName = do
  (exitCode, stdoutText, stderrText) <-
    readProcessWithExitCode
      "kind"
      ["get", "kubeconfig", "--name", clusterName, "--internal"]
      ""
  case exitCode of
    ExitSuccess -> pure stdoutText
    ExitFailure _ -> die stderrText

ensureContainerOnKindNetwork :: IO ()
ensureContainerOnKindNetwork = do
  runningInContainer <- doesFileExist "/.dockerenv"
  when runningInContainer $ do
    currentContainerName <- readCurrentContainerName
    alreadyConnected <- containerOnKindNetwork currentContainerName
    unless alreadyConnected $
      callProcess "docker" ["network", "connect", "kind", currentContainerName]

readCurrentContainerName :: IO String
readCurrentContainerName = do
  currentContainerId <- trimLine <$> readFile "/etc/hostname"
  (exitCode, stdoutText, stderrText) <-
    readProcessWithExitCode "docker" ["inspect", "--format", "{{.Name}}", currentContainerId] ""
  case exitCode of
    ExitSuccess -> pure (dropWhile (== '/') (trimLine stdoutText))
    ExitFailure _ -> die stderrText

containerOnKindNetwork :: String -> IO Bool
containerOnKindNetwork containerName = do
  (exitCode, stdoutText, stderrText) <-
    readProcessWithExitCode "docker" ["network", "inspect", "kind", "--format", "{{json .Containers}}"] ""
  case exitCode of
    ExitSuccess ->
      pure (("\"Name\":\"" <> containerName <> "\"") `isInfixOf` stdoutText)
    ExitFailure _ -> die stderrText

trimLine :: String -> String
trimLine = reverse . dropWhile (`elem` ['\n', '\r']) . reverse

normalizeOptionalPath :: Maybe String -> Maybe String
normalizeOptionalPath maybeValue =
  case fmap trimWhitespace maybeValue of
    Just value
      | null value -> Nothing
      | otherwise -> Just value
    Nothing -> Nothing

trimWhitespace :: String -> String
trimWhitespace = dropWhileEndSpace . dropWhile isSpace
  where
    dropWhileEndSpace = reverse . dropWhile isSpace . reverse

renderFailureDetail :: FailureDetail -> String
renderFailureDetail failureDetail =
  unlines $
    [ Text.unpack (failureCode failureDetail <> ": " <> failureMessage failureDetail)
    ]
      <> map renderContextEntry (Map.toList (failureContext failureDetail))
  where
    renderContextEntry (keyText, valueText) =
      "  " <> Text.unpack keyText <> ": " <> Text.unpack valueText

readMountedHostPath :: String -> FilePath -> IO (Maybe FilePath)
readMountedHostPath containerName mountDestination = do
  (exitCode, stdoutText, stderrText) <-
    readProcessWithExitCode
      "docker"
      ["inspect", "--format", "{{range .Mounts}}{{println .Destination \"=>\" .Source}}{{end}}", containerName]
      ""
  case exitCode of
    ExitSuccess -> pure (parseMountedHostPath mountDestination stdoutText)
    ExitFailure _ -> die stderrText

parseMountedHostPath :: FilePath -> String -> Maybe FilePath
parseMountedHostPath mountDestination stdoutText =
  listToMaybe (mapMaybe parseLine (lines stdoutText))
  where
    parseLine line =
      case Text.splitOn " => " (Text.pack line) of
        [destination, source]
          | Text.unpack destination == mountDestination ->
              Just (Text.unpack source)
        _ -> Nothing

renderKindConfig :: String -> FilePath -> LBS.ByteString
renderKindConfig clusterName dataRoot =
  LBS.unlines
    [ "kind: Cluster"
    , "apiVersion: kind.x-k8s.io/v1alpha4"
    , "name: " <> LBS.pack clusterName
    , "nodes:"
    , "  - role: control-plane"
    , "    extraMounts:"
    , "      - hostPath: " <> LBS.pack dataRoot
    , "        containerPath: /.data"
    ]

data PersistentVolumeSpec = PersistentVolumeSpec
  { volumeName :: String,
    volumeDirectory :: FilePath,
    claimName :: String,
    requestedSize :: String
  }
  deriving (Eq, Show)

desiredPersistentVolumes :: Value -> [PersistentVolumeSpec]
desiredPersistentVolumes values =
  concat
    [ maybe [] pure (persistentVolumeFor "minio" values)
    , maybe [] pure (persistentVolumeFor "pulsar" values)
    ]

persistentVolumeFor :: String -> Value -> Maybe PersistentVolumeSpec
persistentVolumeFor component values = do
  enabled <- lookupBool [component, "persistence", "enabled"] values
  if not enabled
    then Nothing
    else do
      size <- lookupString [component, "persistence", "size"] values
      pure
        PersistentVolumeSpec
          { volumeName = "studiomcp-" <> component <> "-pv",
            volumeDirectory = component,
            claimName = "studiomcp-" <> component,
            requestedSize = size
          }

renderPersistentVolume :: PersistentVolumeSpec -> String
renderPersistentVolume spec =
  unlines
    [ "apiVersion: v1"
    , "kind: PersistentVolume"
    , "metadata:"
    , "  name: " <> volumeName spec
    , "spec:"
    , "  storageClassName: \"\""
    , "  capacity:"
    , "    storage: " <> requestedSize spec
    , "  accessModes:"
    , "    - ReadWriteOnce"
    , "  persistentVolumeReclaimPolicy: Retain"
    , "  hostPath:"
    , "    path: /.data/" <> volumeDirectory spec
    , "    type: DirectoryOrCreate"
    , "  claimRef:"
    , "    namespace: default"
    , "    name: " <> claimName spec
    ]

applyManifest :: String -> IO ()
applyManifest manifest = do
  (exitCode, _, stderrText) <- readProcessWithExitCode "kubectl" ["apply", "-f", "-"] manifest
  case exitCode of
    ExitSuccess -> pure ()
    ExitFailure _ -> die stderrText

loadMergedValues :: IO Value
loadMergedValues = do
  baseValues <- loadYamlValue "chart/values.yaml"
  kindValues <- loadYamlValue "chart/values-kind.yaml"
  pure (mergeValues baseValues kindValues)

loadYamlValue :: FilePath -> IO Value
loadYamlValue path = do
  decoded <- decodeFileEither path
  case decoded of
    Left err -> die (show err)
    Right value -> pure value

mergeValues :: Value -> Value -> Value
mergeValues (Object leftObject) (Object rightObject) =
  Object (KeyMap.unionWith mergeValues leftObject rightObject)
mergeValues _ rightValue = rightValue

lookupBool :: [String] -> Value -> Maybe Bool
lookupBool path value =
  case lookupPath path value of
    Just (Bool boolValue) -> Just boolValue
    _ -> Nothing

lookupString :: [String] -> Value -> Maybe String
lookupString path value =
  case lookupPath path value of
    Just (String textValue) -> Just (Text.unpack textValue)
    _ -> Nothing

lookupPath :: [String] -> Value -> Maybe Value
lookupPath [] currentValue = Just currentValue
lookupPath (segment : remainingPath) (Object objectValue) =
  KeyMap.lookup (Key.fromString segment) objectValue >>= lookupPath remainingPath
lookupPath _ _ = Nothing
