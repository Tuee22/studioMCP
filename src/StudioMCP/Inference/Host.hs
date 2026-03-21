{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Inference.Host
  ( runInferenceMode,
    runInferenceServer,
  )
where

import Data.Aeson (ToJSON, decode, encode, object, (.=))
import Network.HTTP.Client (Manager, defaultManagerSettings, newManager)
import Network.HTTP.Types
  ( hContentType,
    methodGet,
    methodPost,
    Status,
    status200,
    status400,
    status502,
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
import StudioMCP.Util.Logging (configureProcessLogging)
import System.Environment (lookupEnv)

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
  putStrLn ("studioMCP inference listening on 0.0.0.0:" <> show port)
  runSettings
    (setHost "0.0.0.0" (setPort port (setTimeout 0 defaultSettings)))
    (application manager referenceModelConfig)

application :: Manager -> ReferenceModelConfig -> Application
application manager referenceModelConfig request respond =
  case pathInfo request of
    ["advice"] | requestMethod request == methodPost -> do
      requestBody <- strictRequestBody request
      case decode requestBody of
        Nothing ->
          respond (jsonResponse status400 (object ["error" .= ("invalid-request-body" :: String)]))
        Just inferenceRequest -> do
          adviceResult <- requestReferenceAdvice manager referenceModelConfig (renderPlanningPrompt inferenceRequest)
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
      respond (jsonResponse status200 (object ["status" .= ("ready" :: String)]))
    ["version"] | requestMethod request == methodGet ->
      respond (jsonResponse status200 (versionInfoForMode InferenceMode))
    _ ->
      respond (jsonResponse status400 (object ["error" .= ("unsupported-inference-route" :: String)]))

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
