{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module StudioMCP.Web.Handlers
  ( -- * BFF Application
    bffApplication,

    -- * Handler Types
    BFFContext (..),
    newBFFContext,
    newBFFContextWithService,

    -- * Route Handlers
    handleUploadRequest,
    handleUploadConfirm,
    handleDownloadRequest,
    handleChatRequest,
    handleRunSubmit,
    handleRunStatus,
    handleRunEventsRoute,

    -- * Session Handlers
    extractSessionId,
    handleSessionLoginRoute,
    handleSessionMeRoute,
    handleSessionLogoutRoute,
    handleSessionRefreshRoute,
  )
where

import Control.Applicative ((<|>))
import Control.Concurrent (threadDelay)
import Data.Aeson (FromJSON, ToJSON, decode, encode, object, (.=))
import qualified Data.ByteString.Builder as Builder
import Data.List (find)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time (getCurrentTime)
import Network.HTTP.Types
  ( Header,
    Status,
    hContentType,
    status200,
    status400,
    status401,
    status404,
  )
import Network.Wai
  ( Application,
    Request,
    Response,
    ResponseReceived,
    pathInfo,
    requestMethod,
    responseLBS,
    responseStream,
    strictRequestBody,
    requestHeaders,
  )
import StudioMCP.DAG.Summary (RunId (..))
import StudioMCP.Web.BFF
import StudioMCP.Web.Types

-- | BFF context containing service and configuration
data BFFContext = BFFContext
  { bffCtxService :: BFFService,
    bffCtxConfig :: BFFConfig
  }

-- | Create a new BFF context
newBFFContext :: BFFConfig -> IO BFFContext
newBFFContext config = do
  service <- newBFFService config
  pure BFFContext {bffCtxService = service, bffCtxConfig = config}

newBFFContextWithService :: BFFConfig -> BFFService -> BFFContext
newBFFContextWithService config service =
  BFFContext {bffCtxService = service, bffCtxConfig = config}

-- | BFF WAI application
-- Routes are duplicated to support both direct access (/api/v1/...) and
-- ingress-stripped paths (/v1/...) where the /api prefix is removed.
bffApplication :: BFFContext -> Application
bffApplication ctx request respond =
  case (requestMethod request, pathInfo request) of
    -- Health check endpoints (accessible at root for ingress liveness/readiness probes)
    ("GET", ["healthz"]) ->
      respond $ jsonResponse status200 (object ["status" .= ("healthy" :: Text)])
    ("GET", ["health", "live"]) ->
      respond $ jsonResponse status200 (object ["status" .= ("live" :: Text)])
    ("GET", ["health", "ready"]) ->
      respond $ jsonResponse status200 (object ["status" .= ("ready" :: Text)])

    -- Upload endpoints (with /api prefix)
    ("POST", ["api", "v1", "upload", "request"]) ->
      handleJsonRoute ctx request respond handleUploadRequest
    ("POST", ["api", "v1", "upload", "confirm", artifactId]) ->
      withSession ctx request respond $ \service sessionId ->
        respondBffResult status200 respond =<< confirmUpload service sessionId artifactId

    -- Upload endpoints (without /api prefix - for ingress-stripped paths)
    ("POST", ["v1", "upload", "request"]) ->
      handleJsonRoute ctx request respond handleUploadRequest
    ("POST", ["v1", "upload", "confirm", artifactId]) ->
      withSession ctx request respond $ \service sessionId ->
        respondBffResult status200 respond =<< confirmUpload service sessionId artifactId

    -- Download endpoint (with /api prefix)
    ("POST", ["api", "v1", "download"]) ->
      handleJsonRoute ctx request respond handleDownloadRequest
    -- Download endpoint (without /api prefix)
    ("POST", ["v1", "download"]) ->
      handleJsonRoute ctx request respond handleDownloadRequest

    -- Chat endpoint (with /api prefix)
    ("POST", ["api", "v1", "chat"]) ->
      handleJsonRoute ctx request respond handleChatRequest
    -- Chat endpoint (without /api prefix)
    ("POST", ["v1", "chat"]) ->
      handleJsonRoute ctx request respond handleChatRequest

    -- Run endpoints (with /api prefix)
    ("POST", ["api", "v1", "runs"]) ->
      handleJsonRoute ctx request respond handleRunSubmit
    ("GET", ["api", "v1", "runs", runIdText, "status"]) ->
      withSession ctx request respond $ \service sessionId ->
        respondBffResult status200 respond =<< getRunStatus service sessionId (RunId runIdText)
    ("GET", ["api", "v1", "runs", runIdText, "events"]) ->
      withSession ctx request respond $ \service sessionId ->
        handleRunEventsRoute service sessionId (RunId runIdText) respond

    -- Run endpoints (without /api prefix)
    ("POST", ["v1", "runs"]) ->
      handleJsonRoute ctx request respond handleRunSubmit
    ("GET", ["v1", "runs", runIdText, "status"]) ->
      withSession ctx request respond $ \service sessionId ->
        respondBffResult status200 respond =<< getRunStatus service sessionId (RunId runIdText)
    ("GET", ["v1", "runs", runIdText, "events"]) ->
      withSession ctx request respond $ \service sessionId ->
        handleRunEventsRoute service sessionId (RunId runIdText) respond

    -- Session auth endpoints (with /api prefix)
    ("POST", ["api", "v1", "session", "login"]) ->
      handleSessionLoginRoute ctx request respond
    ("GET", ["api", "v1", "session", "me"]) ->
      withSession ctx request respond $ \service sessionId ->
        handleSessionMeRoute service sessionId respond
    ("POST", ["api", "v1", "session", "logout"]) ->
      withSession ctx request respond $ \service sessionId ->
        handleSessionLogoutRoute ctx service sessionId respond
    ("POST", ["api", "v1", "session", "refresh"]) ->
      withSession ctx request respond $ \service sessionId ->
        handleSessionRefreshRoute ctx service sessionId respond

    -- Session auth endpoints (without /api prefix)
    ("POST", ["v1", "session", "login"]) ->
      handleSessionLoginRoute ctx request respond
    ("GET", ["v1", "session", "me"]) ->
      withSession ctx request respond $ \service sessionId ->
        handleSessionMeRoute service sessionId respond
    ("POST", ["v1", "session", "logout"]) ->
      withSession ctx request respond $ \service sessionId ->
        handleSessionLogoutRoute ctx service sessionId respond
    ("POST", ["v1", "session", "refresh"]) ->
      withSession ctx request respond $ \service sessionId ->
        handleSessionRefreshRoute ctx service sessionId respond

    -- 404 for unknown routes
    _ ->
      respond $ jsonResponse status404 (object ["error" .= ("Not found" :: Text)])

withSession ::
  BFFContext ->
  Request ->
  (Response -> IO ResponseReceived) ->
  (BFFService -> WebSessionId -> IO ResponseReceived) ->
  IO ResponseReceived
withSession ctx request respond handler = do
  let service = bffCtxService ctx
      config = bffCtxConfig ctx
  case extractSessionId config request of
    Nothing ->
      respond $ jsonResponse status401 (object ["error" .= ("Session required" :: Text)])
    Just sessionId ->
      handler service sessionId

handleJsonRoute ::
  (FromJSON payload, ToJSON result) =>
  BFFContext ->
  Request ->
  (Response -> IO ResponseReceived) ->
  (BFFService -> WebSessionId -> payload -> IO (Either BFFError result)) ->
  IO ResponseReceived
handleJsonRoute ctx request respond handler =
  withSession ctx request respond $ \service sessionId -> do
    maybePayload <- decode <$> strictRequestBody request
    case maybePayload of
      Nothing ->
        respond $
          jsonResponse status400 (object ["error" .= ("Invalid JSON request body" :: Text)])
      Just payload ->
        respondBffResult status200 respond =<< handler service sessionId payload

respondBffResult ::
  ToJSON a =>
  Status ->
  (Response -> IO ResponseReceived) ->
  Either BFFError a ->
  IO ResponseReceived
respondBffResult successStatus respond result =
  case result of
    Left err ->
      respond $ jsonResponse (bffErrorToHttpStatus err) err
    Right payload ->
      respond $ jsonResponse successStatus payload

-- | Extract session ID from request
extractSessionId :: BFFConfig -> Request -> Maybe WebSessionId
extractSessionId config request =
  extractCookieSessionId config request <|> extractBearerSessionId request

extractBearerSessionId :: Request -> Maybe WebSessionId
extractBearerSessionId request =
  case lookup "Authorization" (requestHeaders request) of
    Just authHeader ->
      let headerText = TE.decodeUtf8 authHeader
       in if "Bearer " `T.isPrefixOf` headerText
            then Just $ WebSessionId $ T.drop 7 headerText
            else Nothing
    Nothing -> Nothing

extractCookieSessionId :: BFFConfig -> Request -> Maybe WebSessionId
extractCookieSessionId config request = do
  rawCookieHeader <- lookup "Cookie" (requestHeaders request)
  let cookieHeader = TE.decodeUtf8 rawCookieHeader
      cookieName = bffSessionCookieName config <> "="
      cookieParts = map T.strip (T.splitOn ";" cookieHeader)
      matchedCookie = find (T.isPrefixOf cookieName) cookieParts
      cookieValue = fmap (T.drop (T.length cookieName)) matchedCookie
  case cookieValue of
    Just value | not (T.null value) -> Just (WebSessionId value)
    _ -> Nothing

-- | Handle upload request
handleUploadRequest ::
  BFFService ->
  WebSessionId ->
  UploadRequest ->
  IO (Either BFFError UploadResponse)
handleUploadRequest = requestUpload

-- | Handle upload confirmation
handleUploadConfirm ::
  BFFService ->
  WebSessionId ->
  Text ->
  IO (Either BFFError ())
handleUploadConfirm = confirmUpload

-- | Handle download request
handleDownloadRequest ::
  BFFService ->
  WebSessionId ->
  DownloadRequest ->
  IO (Either BFFError DownloadResponse)
handleDownloadRequest = requestDownload

-- | Handle chat request
handleChatRequest ::
  BFFService ->
  WebSessionId ->
  ChatRequest ->
  IO (Either BFFError ChatResponse)
handleChatRequest = sendChatMessage

-- | Handle run submission
handleRunSubmit ::
  BFFService ->
  WebSessionId ->
  RunSubmitRequest ->
  IO (Either BFFError RunStatusResponse)
handleRunSubmit = submitRun

-- | Handle run status
handleRunStatus ::
  BFFService ->
  WebSessionId ->
  RunId ->
  IO (Either BFFError RunStatusResponse)
handleRunStatus = getRunStatus

handleRunEventsRoute ::
  BFFService ->
  WebSessionId ->
  RunId ->
  (Response -> IO ResponseReceived) ->
  IO ResponseReceived
handleRunEventsRoute service sessionId runId respond = do
  initialStatusResult <- getRunStatus service sessionId runId
  case initialStatusResult of
    Left err ->
      respond $ jsonResponse (bffErrorToHttpStatus err) err
    Right initialStatus ->
      respond $
        responseStream
          status200
          [ (hContentType, "text/event-stream")
          , ("Cache-Control", "no-cache")
          , ("Connection", "keep-alive")
          ]
          (\write flush -> streamRunProgressEvents service sessionId initialStatus write flush)

streamRunProgressEvents ::
  BFFService ->
  WebSessionId ->
  RunStatusResponse ->
  (Builder.Builder -> IO ()) ->
  IO () ->
  IO ()
streamRunProgressEvents service sessionId initialStatus write flush = do
  emitReadyEvent initialStatus write flush
  emitRunStatusEvent initialStatus write flush
  streamLoop 3 (runStatusFingerprint initialStatus)
  where
    runId = rsrRunId initialStatus

    streamLoop :: Int -> (Text, Maybe Int) -> IO ()
    streamLoop remainingPolls lastFingerprint
      | remainingPolls <= 0 = do
          emitSseEvent write flush "complete" (object ["runId" .= runId, "streamClosed" .= True])
      | isTerminalRunStatus (fst lastFingerprint) = do
          emitSseEvent write flush "complete" (object ["runId" .= runId, "streamClosed" .= True])
      | otherwise = do
          threadDelay 500000
          polledStatusResult <- getRunStatus service sessionId runId
          case polledStatusResult of
            Left err ->
              emitSseEvent write flush "error" err
            Right polledStatus -> do
              let currentFingerprint = runStatusFingerprint polledStatus
              if currentFingerprint == lastFingerprint
                then emitSseEvent write flush "heartbeat" (object ["runId" .= runId, "status" .= rsrStatus polledStatus])
                else emitRunStatusEvent polledStatus write flush
              if isTerminalRunStatus (rsrStatus polledStatus)
                then emitSseEvent write flush "complete" (object ["runId" .= runId, "streamClosed" .= True])
                else streamLoop (remainingPolls - 1) currentFingerprint

emitReadyEvent :: RunStatusResponse -> (Builder.Builder -> IO ()) -> IO () -> IO ()
emitReadyEvent status write flush =
  emitSseEvent
    write
    flush
    "ready"
    ( object
        [ "runId" .= rsrRunId status
        , "status" .= rsrStatus status
        ]
    )

emitRunStatusEvent :: RunStatusResponse -> (Builder.Builder -> IO ()) -> IO () -> IO ()
emitRunStatusEvent status write flush = do
  now <- getCurrentTime
  emitSseEvent
    write
    flush
    "status"
    RunProgressEvent
      { rpeRunId = rsrRunId status
      , rpeNodeId = Nothing
      , rpeEventType = rsrStatus status
      , rpeMessage = "Run status updated"
      , rpeProgress = rsrProgress status
      , rpeTimestamp = now
      }

emitSseEvent ::
  ToJSON payload =>
  (Builder.Builder -> IO ()) ->
  IO () ->
  Text ->
  payload ->
  IO ()
emitSseEvent write flush eventName payload = do
  write (Builder.byteString "event: ")
  write (Builder.byteString (TE.encodeUtf8 eventName))
  write (Builder.byteString "\n")
  write (Builder.byteString "data: ")
  write (Builder.lazyByteString (encode payload))
  write (Builder.byteString "\n\n")
  flush

runStatusFingerprint :: RunStatusResponse -> (Text, Maybe Int)
runStatusFingerprint status =
  (rsrStatus status, rsrProgress status)

isTerminalRunStatus :: Text -> Bool
isTerminalRunStatus rawStatus =
  T.toLower rawStatus `elem` ["completed", "complete", "failed", "cancelled", "canceled", "succeeded", "error"]

-- | Create JSON response
jsonResponse :: ToJSON a => Status -> a -> Response
jsonResponse status body =
  responseLBS status [(hContentType, "application/json")] (encode body)

jsonResponseWithHeaders :: ToJSON a => Status -> [Header] -> a -> Response
jsonResponseWithHeaders status headers body =
  responseLBS status ((hContentType, "application/json") : headers) (encode body)

-- | Handle password login
handleSessionLoginRoute ::
  BFFContext ->
  Request ->
  (Response -> IO ResponseReceived) ->
  IO ResponseReceived
handleSessionLoginRoute ctx request respond = do
  let service = bffCtxService ctx
      config = bffCtxConfig ctx
  maybePayload <- decode <$> strictRequestBody request
  case maybePayload of
    Nothing ->
      respond $
        jsonResponse status400 (object ["error" .= ("Invalid JSON request body" :: Text)])
    Just payload -> do
      result <- loginWithPassword service payload
      case result of
        Left err ->
          respond $ jsonResponse (bffErrorToHttpStatus err) err
        Right session ->
          respond $
            jsonResponseWithHeaders
              status200
              (sessionCookieHeaders config session)
              SessionLoginResponse
                { slresSession = sessionSummaryFromWebSession session
                }

handleSessionMeRoute ::
  BFFService ->
  WebSessionId ->
  (Response -> IO ResponseReceived) ->
  IO ResponseReceived
handleSessionMeRoute service sessionId respond = do
  result <- getSessionSummary service sessionId
  case result of
    Left err ->
      respond $ jsonResponse (bffErrorToHttpStatus err) err
    Right payload ->
      respond $ jsonResponse status200 payload

-- | Handle logout route
handleSessionLogoutRoute ::
  BFFContext ->
  BFFService ->
  WebSessionId ->
  (Response -> IO ResponseReceived) ->
  IO ResponseReceived
handleSessionLogoutRoute ctx service sessionId respond = do
  let config = bffCtxConfig ctx
  result <- logoutSession service sessionId
  case result of
    Left err ->
      respond $ jsonResponse (bffErrorToHttpStatus err) err
    Right payload ->
      respond $
        jsonResponseWithHeaders
          status200
          (clearSessionCookieHeaders config)
          payload

-- | Handle token refresh route
handleSessionRefreshRoute ::
  BFFContext ->
  BFFService ->
  WebSessionId ->
  (Response -> IO ResponseReceived) ->
  IO ResponseReceived
handleSessionRefreshRoute ctx service sessionId respond = do
  let config = bffCtxConfig ctx
  result <- refreshSessionTokens service sessionId
  case result of
    Left err ->
      respond $ jsonResponse (bffErrorToHttpStatus err) err
    Right session ->
      respond $
        jsonResponseWithHeaders
          status200
          (sessionCookieHeaders config session)
          SessionRefreshResponse
            { srrSession = sessionSummaryFromWebSession session
            , srrSuccess = True
            }

sessionCookieHeaders :: BFFConfig -> WebSession -> [Header]
sessionCookieHeaders config session =
  [("Set-Cookie", TE.encodeUtf8 (renderSessionCookie config session))]

clearSessionCookieHeaders :: BFFConfig -> [Header]
clearSessionCookieHeaders config =
  [("Set-Cookie", TE.encodeUtf8 (renderExpiredSessionCookie config))]

renderSessionCookie :: BFFConfig -> WebSession -> Text
renderSessionCookie config session =
  let WebSessionId sessionValue = wsSessionId session
      secureFlag =
        if bffSessionCookieSecure config
          then "; Secure"
          else ""
   in bffSessionCookieName config
        <> "="
        <> sessionValue
        <> "; Path="
        <> bffSessionCookiePath config
        <> "; HttpOnly; SameSite=Lax; Max-Age="
        <> T.pack (show (bffSessionTtlSeconds config))
        <> secureFlag

renderExpiredSessionCookie :: BFFConfig -> Text
renderExpiredSessionCookie config =
  let secureFlag =
        if bffSessionCookieSecure config
          then "; Secure"
          else ""
   in bffSessionCookieName config
        <> "=; Path="
        <> bffSessionCookiePath config
        <> "; HttpOnly; SameSite=Lax; Max-Age=0"
        <> secureFlag
