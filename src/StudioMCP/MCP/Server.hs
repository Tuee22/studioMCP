{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.MCP.Server
  ( runServer,
  )
where

import Data.Aeson (ToJSON, decode, encode, object, (.=))
import Data.ByteString.Lazy qualified as LBS
import Data.Text.Encoding qualified as Text
import Network.HTTP.Types
  ( hContentType,
    methodGet,
    methodPost,
    Status,
    status200,
    status201,
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
  )
import StudioMCP.API.Metrics (renderPrometheusMetrics)
import StudioMCP.Config.Load (loadAppConfig)
import StudioMCP.DAG.Summary (RunId (..))
import StudioMCP.MCP.Handlers
  ( ServerEnv,
    SubmissionResult (..),
    createServerEnv,
    currentHealthReport,
    currentMetricsSnapshot,
    currentVersionInfo,
    fetchSummary,
    submitDag,
  )
import StudioMCP.MCP.Protocol (SubmissionRequest (..))
import StudioMCP.Result.Failure (failureCode)
import StudioMCP.Util.Logging (configureProcessLogging)
import System.Environment (lookupEnv)

runServer :: IO ()
runServer = do
  configureProcessLogging
  appConfig <- loadAppConfig
  serverEnv <- createServerEnv appConfig
  port <- resolveServerPort
  putStrLn ("studioMCP server listening on 0.0.0.0:" <> show port)
  runSettings
    (setHost "0.0.0.0" (setPort port (setTimeout 0 defaultSettings)))
    (application serverEnv)

application :: ServerEnv -> Application
application serverEnv request respond =
  case pathInfo request of
    ["runs"] | requestMethod request == methodPost -> do
      requestBody <- strictRequestBody request
      case decode requestBody of
        Nothing ->
          respond
            ( jsonResponse
                status400
                (object ["error" .= ("invalid-request-body" :: String)])
            )
        Just submissionRequest ->
          handleSubmission serverEnv submissionRequest respond
    ["runs", runIdText, "summary"] | requestMethod request == methodGet ->
      handleSummaryFetch serverEnv (RunId runIdText) respond
    ["healthz"] | requestMethod request == methodGet ->
      handleHealth serverEnv respond
    ["version"] | requestMethod request == methodGet ->
      respond (jsonResponse status200 (currentVersionInfo serverEnv))
    ["metrics"] | requestMethod request == methodGet ->
      handleMetrics serverEnv respond
    _ ->
      respond
        ( jsonResponse
            status404
            (object ["error" .= ("not-found" :: String)])
        )

handleSubmission ::
  ServerEnv ->
  SubmissionRequest ->
  (Response -> IO b) ->
  IO b
handleSubmission serverEnv submissionRequest respond = do
  result <- submitDag serverEnv (submissionDag submissionRequest)
  case result of
    SubmissionAccepted submissionResponse ->
      respond (jsonResponse status201 submissionResponse)
    SubmissionRejected failures ->
      respond (jsonResponse status400 (object ["failures" .= failures]))
    SubmissionFailed failureDetail ->
      respond (jsonResponse status500 failureDetail)

handleSummaryFetch ::
  ServerEnv ->
  RunId ->
  (Response -> IO b) ->
  IO b
handleSummaryFetch serverEnv runIdValue respond = do
  result <- fetchSummary serverEnv runIdValue
  case result of
    Left failureDetail
      | failureCode failureDetail == "minio-object-not-found" ->
          respond (jsonResponse status404 failureDetail)
      | otherwise ->
          respond (jsonResponse status500 failureDetail)
    Right summary ->
      respond (jsonResponse status200 summary)

handleHealth ::
  ServerEnv ->
  (Response -> IO b) ->
  IO b
handleHealth serverEnv respond = do
  healthReport <- currentHealthReport serverEnv
  let statusValue =
        case healthStatus healthReport of
          Healthy -> status200
          Degraded -> status503
  respond (jsonResponse statusValue healthReport)

handleMetrics ::
  ServerEnv ->
  (Response -> IO b) ->
  IO b
handleMetrics serverEnv respond = do
  metricsSnapshot <- currentMetricsSnapshot serverEnv
  respond
    ( responseLBS
        status200
        [(hContentType, "text/plain; version=0.0.4")]
        (LBS.fromStrict (Text.encodeUtf8 (renderPrometheusMetrics metricsSnapshot)))
    )

jsonResponse :: ToJSON a => Status -> a -> Response
jsonResponse statusValue payload =
  responseLBS
    statusValue
    [(hContentType, "application/json")]
    (encode payload)

resolveServerPort :: IO Int
resolveServerPort = do
  maybePortText <- lookupEnv "STUDIO_MCP_PORT"
  pure $
    case maybePortText >>= readMaybeInt of
      Just port -> port
      Nothing -> 3000

readMaybeInt :: String -> Maybe Int
readMaybeInt rawValue =
  case reads rawValue of
    [(value, "")] -> Just value
    _ -> Nothing
