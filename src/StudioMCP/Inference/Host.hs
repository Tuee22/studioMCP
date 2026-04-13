{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Inference.Host
  ( runInferenceMode,
    runInferenceServer,
  )
where

import Data.Aeson (ToJSON, decode, encode, object, (.=))
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Network.HTTP.Client (Manager, defaultManagerSettings, newManager)
import Network.HTTP.Types
  ( hContentType,
    methodGet,
    methodPost,
    Status,
    status200,
    status400,
    status502,
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
import StudioMCP.API.Readiness
  ( ReadinessCheck,
    ReadinessReport (..),
    ReadinessStatus (..),
    buildReadinessReport,
    probeAnyHttpCheck,
    readinessHttpStatus,
    renderBlockingChecks,
  )
import StudioMCP.API.Version (versionInfoForMode)
import StudioMCP.Config.Load (loadAppConfig)
import StudioMCP.Config.Types (AppMode (InferenceMode))
import StudioMCP.Inference.Guardrails (applyGuardrails)
import StudioMCP.Inference.Prompts (renderPlanningPrompt)
import StudioMCP.Inference.ReferenceModel
  ( ReferenceModelConfig (..),
    requestReferenceAdvice,
  )
import StudioMCP.Inference.Types (InferenceResponse (..))
import StudioMCP.Util.Logging (configureProcessLogging, logInfo)
import System.Environment (lookupEnv)

data InferenceEnv = InferenceEnv
  { inferenceManager :: Manager,
    inferenceReferenceModelConfig :: ReferenceModelConfig,
    inferenceReadinessSummaryRef :: IORef (Maybe Text)
  }

runInferenceMode :: IO ()
runInferenceMode = do
  _ <- loadAppConfig
  modelUrl <- maybe "http://127.0.0.1:11434/api/generate" id <$> lookupEnv "STUDIO_MCP_REFERENCE_MODEL_URL"
  port <- resolveInferencePort
  runInferenceServer port (ReferenceModelConfig modelUrl)

runInferenceServer :: Int -> ReferenceModelConfig -> IO ()
runInferenceServer port referenceModelConfig = do
  configureProcessLogging
  manager <- newManager defaultManagerSettings
  readinessSummaryRef <- newIORef Nothing
  let inferenceEnv =
        InferenceEnv
          { inferenceManager = manager,
            inferenceReferenceModelConfig = referenceModelConfig,
            inferenceReadinessSummaryRef = readinessSummaryRef
          }
  putStrLn ("studioMCP inference listening on 0.0.0.0:" <> show port)
  runSettings
    (setHost "0.0.0.0" (setPort port (setTimeout 0 defaultSettings)))
    (application inferenceEnv)

application :: InferenceEnv -> Application
application inferenceEnv request respond =
  case pathInfo request of
    ["advice"] | requestMethod request == methodPost -> do
      requestBody <- strictRequestBody request
      case decode requestBody of
        Nothing ->
          respond (jsonResponse status400 (object ["error" .= ("invalid-request-body" :: String)]))
        Just inferenceRequest -> do
          adviceResult <-
            requestReferenceAdvice
              (inferenceManager inferenceEnv)
              (inferenceReferenceModelConfig inferenceEnv)
              (renderPlanningPrompt inferenceRequest)
          case adviceResult >>= applyGuardrails of
            Left failureDetail ->
              respond
                ( jsonResponse
                    status502
                    failureDetail
                )
            Right advisoryText ->
              respond (jsonResponse status200 (InferenceResponse advisoryText))
    ["healthz"] | requestMethod request == methodGet ->
      handleInferenceHealth inferenceEnv respond
    ["health", "live"] | requestMethod request == methodGet ->
      respond (jsonResponse status200 (object ["status" .= ("ok" :: String)]))
    ["health", "ready"] | requestMethod request == methodGet ->
      handleInferenceReadiness inferenceEnv respond
    ["version"] | requestMethod request == methodGet ->
      respond (jsonResponse status200 (versionInfoForMode InferenceMode))
    _ ->
      respond (jsonResponse status400 (object ["error" .= ("unsupported-inference-route" :: String)]))

handleInferenceHealth ::
  InferenceEnv ->
  (Response -> IO b) ->
  IO b
handleInferenceHealth inferenceEnv respond = do
  readinessReport <- inferenceReadinessReport inferenceEnv
  let statusValue =
        case readinessStatus readinessReport of
          ReadinessReady -> status200
          ReadinessBlocked -> status503
      healthStatusText =
        case readinessStatus readinessReport of
          ReadinessReady -> "healthy" :: Text
          ReadinessBlocked -> "degraded" :: Text
  respond $
    jsonResponse
      statusValue
      ( object
          [ "status" .= healthStatusText
          , "blocking" .= readinessBlockingChecks readinessReport
          ]
      )

handleInferenceReadiness ::
  InferenceEnv ->
  (Response -> IO b) ->
  IO b
handleInferenceReadiness inferenceEnv respond = do
  readinessReport <- inferenceReadinessReport inferenceEnv
  logReadinessTransition "studiomcp-inference" (inferenceReadinessSummaryRef inferenceEnv) readinessReport
  respond (jsonResponse (readinessHttpStatus readinessReport) readinessReport)

inferenceReadinessReport :: InferenceEnv -> IO ReadinessReport
inferenceReadinessReport inferenceEnv =
  buildReadinessReport "studiomcp-inference"
    <$> inferenceReadinessChecks inferenceEnv

inferenceReadinessChecks :: InferenceEnv -> IO [ReadinessCheck]
inferenceReadinessChecks inferenceEnv =
  pure . (: []) =<<
    probeAnyHttpCheck
      (inferenceManager inferenceEnv)
      "reference-model"
      (referenceModelHealthUrls (inferenceReferenceModelConfig inferenceEnv))
      [200]
      "reference-model-ready"
      "reference-model-unavailable"

referenceModelHealthUrls :: ReferenceModelConfig -> [Text]
referenceModelHealthUrls referenceModelConfig =
  let rawUrl = Text.pack (referenceModelUrl referenceModelConfig)
      rootUrl =
        case take 3 (Text.splitOn "/" rawUrl) of
          [scheme, "", authority] -> Text.intercalate "/" [scheme, "", authority]
          _ -> rawUrl
   in filter
        (not . Text.null)
        [rootUrl <> "/healthz", rootUrl <> "/api/tags", rootUrl <> "/api/version"]

logReadinessTransition :: Text -> IORef (Maybe Text) -> ReadinessReport -> IO ()
logReadinessTransition serviceName summaryRef readinessReport = do
  let summary =
        case readinessStatus readinessReport of
          ReadinessReady -> "ready"
          ReadinessBlocked -> renderBlockingChecks readinessReport
  previousSummary <- readIORef summaryRef
  if previousSummary == Just summary
    then pure ()
    else do
      writeIORef summaryRef (Just summary)
      logInfo
        ( "readiness["
            <> serviceName
            <> "] "
            <> case readinessStatus readinessReport of
              ReadinessReady -> "ready"
              ReadinessBlocked -> "blocked: " <> summary
        )

jsonResponse :: ToJSON a => Status -> a -> Response
jsonResponse statusValue payload =
  responseLBS
    statusValue
    [(hContentType, "application/json")]
    (encode payload)

resolveInferencePort :: IO Int
resolveInferencePort = do
  maybePortText <- lookupEnv "STUDIO_MCP_INFERENCE_PORT"
  pure $
    case maybePortText >>= readMaybeInt of
      Just port -> port
      Nothing -> 3001

readMaybeInt :: String -> Maybe Int
readMaybeInt rawValue =
  case reads rawValue of
    [(value, "")] -> Just value
    _ -> Nothing
