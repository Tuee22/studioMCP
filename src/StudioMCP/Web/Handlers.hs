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
    handleLoginRequest,
    handleLogoutRequest,
    handleProfileRequest,
    handleUploadRequest,
    handleUploadConfirm,
    handleDownloadRequest,
    handleChatRequest,
    handleRunSubmit,
    handleRunStatus,
    handleRunList,
    handleRunCancel,
    handleArtifactHide,
    handleArtifactArchive,
  )
where

import Control.Concurrent (threadDelay)
import Control.Monad (forM_)
import Data.Aeson (FromJSON, ToJSON, decode, encode, object, (.=))
import Data.ByteString.Builder (Builder, byteString, lazyByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as LBS
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time (UTCTime, getCurrentTime)
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
    queryString,
    requestHeaders,
    requestMethod,
    responseLBS,
    responseStream,
    strictRequestBody,
  )
import StudioMCP.DAG.Summary (RunId (..))
import StudioMCP.Web.BFF
import StudioMCP.Web.Types

data BFFContext = BFFContext
  { bffCtxService :: BFFService,
    bffCtxConfig :: BFFConfig
  }

newBFFContext :: BFFConfig -> IO BFFContext
newBFFContext config = do
  service <- newBFFService config
  pure BFFContext {bffCtxService = service, bffCtxConfig = config}

newBFFContextWithService :: BFFConfig -> BFFService -> BFFContext
newBFFContextWithService config service =
  BFFContext {bffCtxService = service, bffCtxConfig = config}

bffApplication :: BFFContext -> Application
bffApplication ctx request respond =
  case (requestMethod request, pathInfo request) of
    ("GET", []) ->
      respond $ htmlResponse (browserShellHtml (bffCtxConfig ctx))
    ("GET", ["app"]) ->
      respond $ htmlResponse (browserShellHtml (bffCtxConfig ctx))
    ("GET", ["healthz"]) ->
      respond $ jsonResponse status200 (object ["status" .= ("healthy" :: Text)])
    ("GET", ["health", "live"]) ->
      respond $ jsonResponse status200 (object ["status" .= ("live" :: Text)])
    ("GET", ["health", "ready"]) ->
      respond $ jsonResponse status200 (object ["status" .= ("ready" :: Text)])
    ("POST", ["api", "v1", "auth", "login"]) ->
      handleLoginRoute ctx request respond
    ("POST", ["api", "v1", "auth", "logout"]) ->
      withSession ctx request respond $ \service sessionId ->
        handleLogoutRoute service sessionId respond
    ("GET", ["api", "v1", "profile"]) ->
      withSession ctx request respond $ \service sessionId ->
        respondBffResult status200 respond =<< handleProfileRequest service sessionId
    ("POST", ["api", "v1", "upload", "request"]) ->
      handleJsonRoute ctx request respond handleUploadRequest
    ("POST", ["api", "v1", "upload", "confirm", artifactId]) ->
      withSession ctx request respond $ \service sessionId ->
        respondBffResult status200 respond =<< confirmUpload service sessionId artifactId
    ("POST", ["api", "v1", "download"]) ->
      handleJsonRoute ctx request respond handleDownloadRequest
    ("POST", ["api", "v1", "chat"]) ->
      handleJsonRoute ctx request respond handleChatRequest
    ("POST", ["api", "v1", "chat", "stream"]) ->
      handleChatStreamRoute ctx request respond
    ("POST", ["api", "v1", "runs"]) ->
      handleJsonRoute ctx request respond handleRunSubmit
    ("GET", ["api", "v1", "runs"]) ->
      withSession ctx request respond $ \service sessionId ->
        respondBffResult status200 respond =<< handleRunList service sessionId (runListRequestFromQuery request)
    ("GET", ["api", "v1", "runs", runIdText, "events"]) ->
      handleRunEventsRoute ctx request respond (RunId runIdText)
    ("GET", ["api", "v1", "runs", runIdText, "status"]) ->
      withSession ctx request respond $ \service sessionId ->
        respondBffResult status200 respond =<< getRunStatus service sessionId (RunId runIdText)
    ("POST", ["api", "v1", "runs", runIdText, "cancel"]) ->
      withSession ctx request respond $ \service sessionId ->
        handleOptionalJsonRoute request respond $ \maybeBody ->
          respondBffResult status200 respond =<< handleRunCancel service sessionId (RunId runIdText) (maybeReason maybeBody)
    ("POST", ["api", "v1", "artifacts", artifactId, "hide"]) ->
      withSession ctx request respond $ \service sessionId ->
        handleOptionalJsonRoute request respond $ \maybeBody ->
          respondBffResult status200 respond =<< handleArtifactHide service sessionId artifactId (fromMaybe (ArtifactActionRequest Nothing) maybeBody)
    ("POST", ["api", "v1", "artifacts", artifactId, "archive"]) ->
      withSession ctx request respond $ \service sessionId ->
        handleOptionalJsonRoute request respond $ \maybeBody ->
          respondBffResult status200 respond =<< handleArtifactArchive service sessionId artifactId (fromMaybe (ArtifactActionRequest Nothing) maybeBody)
    _ ->
      respond $ jsonResponse status404 (object ["error" .= ("Not found" :: Text)])

handleLoginRoute ::
  BFFContext ->
  Request ->
  (Response -> IO ResponseReceived) ->
  IO ResponseReceived
handleLoginRoute ctx request respond = do
  maybePayload <- decode <$> strictRequestBody request
  case maybePayload of
    Nothing ->
      respond $
        jsonResponse status400 (object ["error" .= ("Invalid JSON request body" :: Text)])
    Just payload -> do
      loginResult <- loginWebSession (bffCtxService ctx) payload
      case loginResult of
        Left err ->
          respond $ jsonResponse (bffErrorToHttpStatus err) err
        Right session ->
          respond $
            jsonResponseWithHeaders
              status200
              [setCookieHeader session]
              (LoginResponse (profileFromSession session))

handleLogoutRoute ::
  BFFService ->
  WebSessionId ->
  (Response -> IO ResponseReceived) ->
  IO ResponseReceived
handleLogoutRoute service sessionId respond = do
  logoutResult <- handleLogoutRequest service sessionId
  case logoutResult of
    Left err ->
      respond $ jsonResponse (bffErrorToHttpStatus err) err
    Right payload ->
      respond $
        jsonResponseWithHeaders
          status200
          [("Set-Cookie", expiredCookieValue)]
          payload

withSession ::
  BFFContext ->
  Request ->
  (Response -> IO ResponseReceived) ->
  (BFFService -> WebSessionId -> IO ResponseReceived) ->
  IO ResponseReceived
withSession ctx request respond handler = do
  let service = bffCtxService ctx
  case extractSessionId request of
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

handleOptionalJsonRoute ::
  FromJSON payload =>
  Request ->
  (Response -> IO ResponseReceived) ->
  (Maybe payload -> IO ResponseReceived) ->
  IO ResponseReceived
handleOptionalJsonRoute request respond handler = do
  requestBodyBytes <- strictRequestBody request
  if LBS.null requestBodyBytes
    then handler Nothing
    else
      case decode requestBodyBytes of
        Nothing ->
          respond $
            jsonResponse status400 (object ["error" .= ("Invalid JSON request body" :: Text)])
        Just payload ->
          handler (Just payload)

handleChatStreamRoute ::
  BFFContext ->
  Request ->
  (Response -> IO ResponseReceived) ->
  IO ResponseReceived
handleChatStreamRoute ctx request respond =
  withSession ctx request respond $ \service sessionId -> do
    maybePayload <- decode <$> strictRequestBody request
    case maybePayload of
      Nothing ->
        respond $
          jsonResponse status400 (object ["error" .= ("Invalid JSON request body" :: Text)])
      Just payload -> do
        chatResult <- handleChatRequest service sessionId payload
        case chatResult of
          Left err ->
            respond $ jsonResponse (bffErrorToHttpStatus err) err
          Right chatResponse ->
            respond $
              responseStream
                status200
                sseHeaders
                (\write flush -> streamChatResponse write flush chatResponse)

handleRunEventsRoute ::
  BFFContext ->
  Request ->
  (Response -> IO ResponseReceived) ->
  RunId ->
  IO ResponseReceived
handleRunEventsRoute ctx request respond runIdValue =
  withSession ctx request respond $ \service sessionId -> do
    statusResult <- handleRunStatus service sessionId runIdValue
    case statusResult of
      Left err ->
        respond $ jsonResponse (bffErrorToHttpStatus err) err
      Right initialStatus ->
        respond $
          responseStream
            status200
            sseHeaders
            (\write flush -> streamRunProgress service sessionId runIdValue initialStatus write flush)

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

extractSessionId :: Request -> Maybe WebSessionId
extractSessionId request =
  case extractSessionCookie request of
    Just sessionId -> Just sessionId
    Nothing -> extractAuthorizationSession request

extractAuthorizationSession :: Request -> Maybe WebSessionId
extractAuthorizationSession request =
  case lookup "Authorization" (requestHeaders request) of
    Just authHeader ->
      let headerText = TE.decodeUtf8 authHeader
       in if "Bearer " `T.isPrefixOf` headerText
            then Just $ WebSessionId $ T.drop 7 headerText
            else Nothing
    Nothing -> Nothing

extractSessionCookie :: Request -> Maybe WebSessionId
extractSessionCookie request = do
  cookieHeader <- lookup "Cookie" (requestHeaders request)
  lookup "studiomcp_session" (parseCookies cookieHeader)

parseCookies :: BS.ByteString -> [(BS.ByteString, WebSessionId)]
parseCookies rawCookieHeader =
  mapMaybe parseCookie (BS8.split ';' rawCookieHeader)
  where
    parseCookie entry =
      case BS8.break (== '=') (BS8.dropWhile (== ' ') entry) of
        (name, value)
          | BS.null value -> Nothing
          | otherwise ->
              Just
                ( name,
                  WebSessionId (TE.decodeUtf8 (BS.drop 1 value))
                )

runListRequestFromQuery :: Request -> RunListRequest
runListRequestFromQuery request =
  RunListRequest
    { rlrStatus = lookupQueryText "status" request,
      rlrLimit = lookupQueryInt "limit" request
    }

lookupQueryText :: BS.ByteString -> Request -> Maybe Text
lookupQueryText key request =
  lookup key (queryString request) >>= fmap TE.decodeUtf8

lookupQueryInt :: BS.ByteString -> Request -> Maybe Int
lookupQueryInt key request = do
  rawValue <- lookup key (queryString request) >>= fmap BS8.unpack
  case reads rawValue of
    [(value, "")] -> Just value
    _ -> Nothing

maybeReason :: Maybe ArtifactActionRequest -> Maybe Text
maybeReason = (>>= aarReason)

setCookieHeader :: WebSession -> Header
setCookieHeader session =
  ( "Set-Cookie",
    "studiomcp_session="
      <> TE.encodeUtf8
        ( case wsSessionId session of
            WebSessionId sessionIdText -> sessionIdText
        )
      <> "; Path=/; HttpOnly; SameSite=Lax"
  )

expiredCookieValue :: BS.ByteString
expiredCookieValue =
  "studiomcp_session=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"

handleLoginRequest ::
  BFFService ->
  LoginRequest ->
  IO (Either BFFError WebSession)
handleLoginRequest = loginWebSession

handleLogoutRequest ::
  BFFService ->
  WebSessionId ->
  IO (Either BFFError LogoutResponse)
handleLogoutRequest = logoutWebSession

handleProfileRequest ::
  BFFService ->
  WebSessionId ->
  IO (Either BFFError ProfileResponse)
handleProfileRequest = getProfile

handleUploadRequest ::
  BFFService ->
  WebSessionId ->
  UploadRequest ->
  IO (Either BFFError UploadResponse)
handleUploadRequest = requestUpload

handleUploadConfirm ::
  BFFService ->
  WebSessionId ->
  Text ->
  IO (Either BFFError ())
handleUploadConfirm = confirmUpload

handleDownloadRequest ::
  BFFService ->
  WebSessionId ->
  DownloadRequest ->
  IO (Either BFFError DownloadResponse)
handleDownloadRequest = requestDownload

handleChatRequest ::
  BFFService ->
  WebSessionId ->
  ChatRequest ->
  IO (Either BFFError ChatResponse)
handleChatRequest = sendChatMessage

handleRunSubmit ::
  BFFService ->
  WebSessionId ->
  RunSubmitRequest ->
  IO (Either BFFError RunStatusResponse)
handleRunSubmit = submitRun

handleRunStatus ::
  BFFService ->
  WebSessionId ->
  RunId ->
  IO (Either BFFError RunStatusResponse)
handleRunStatus = getRunStatus

handleRunList ::
  BFFService ->
  WebSessionId ->
  RunListRequest ->
  IO (Either BFFError RunListResponse)
handleRunList = listRuns

handleRunCancel ::
  BFFService ->
  WebSessionId ->
  RunId ->
  Maybe Text ->
  IO (Either BFFError RunStatusResponse)
handleRunCancel = cancelRun

handleArtifactHide ::
  BFFService ->
  WebSessionId ->
  Text ->
  ArtifactActionRequest ->
  IO (Either BFFError ArtifactGovernanceResponse)
handleArtifactHide = hideArtifact

handleArtifactArchive ::
  BFFService ->
  WebSessionId ->
  Text ->
  ArtifactActionRequest ->
  IO (Either BFFError ArtifactGovernanceResponse)
handleArtifactArchive = archiveArtifact

jsonResponse :: ToJSON a => Status -> a -> Response
jsonResponse statusValue body =
  responseLBS statusValue [(hContentType, "application/json")] (encode body)

jsonResponseWithHeaders :: ToJSON a => Status -> [Header] -> a -> Response
jsonResponseWithHeaders statusValue headers body =
  responseLBS
    statusValue
    ((hContentType, "application/json") : headers)
    (encode body)

htmlResponse :: LBS.ByteString -> Response
htmlResponse body =
  responseLBS status200 [(hContentType, "text/html; charset=utf-8")] body

sseHeaders :: [Header]
sseHeaders =
  [ (hContentType, "text/event-stream")
  , ("Cache-Control", "no-cache")
  , ("Connection", "keep-alive")
  ]

streamChatResponse ::
  (Builder -> IO ()) ->
  IO () ->
  ChatResponse ->
  IO ()
streamChatResponse write flush chatResponse = do
  write $ byteString "retry: 1000\n\n"
  writeSseEvent
    write
    "conversation.started"
    ( object
        [ "conversationId" .= crpConversationId chatResponse
        , "timestamp" .= cmTimestamp (crpMessage chatResponse)
        ]
    )
  flush
  forM_ (zip [(0 :: Int) ..] (chunkChatMessage 14 (cmContent (crpMessage chatResponse)))) $ \(chunkIndex, chunkText) -> do
    writeSseEvent
      write
      "message.delta"
      ( object
          [ "conversationId" .= crpConversationId chatResponse
          , "index" .= chunkIndex
          , "delta" .= chunkText
          ]
      )
    flush
  writeSseEvent
    write
    "message.completed"
    ( object
        [ "conversationId" .= crpConversationId chatResponse
        , "message" .= crpMessage chatResponse
        ]
    )
  writeSseEvent
    write
    "done"
    ( object
        [ "conversationId" .= crpConversationId chatResponse
        ]
    )
  flush

streamRunProgress ::
  BFFService ->
  WebSessionId ->
  RunId ->
  RunStatusResponse ->
  (Builder -> IO ()) ->
  IO () ->
  IO ()
streamRunProgress service sessionId runIdValue initialStatus write flush = do
  write $ byteString "retry: 1000\n\n"
  emitStatusEvent "run.snapshot" initialStatus
  pollWindow 0 initialStatus
  where
    maxPolls = 6 :: Int
    pollDelayMicros = 250000

    emitStatusEvent eventName statusValue = do
      now <- getCurrentTime
      writeSseEvent write eventName (runProgressEvent eventName now statusValue)
      flush

    pollWindow pollIndex previousStatus
      | isTerminalRunStatus (rsrStatus previousStatus) =
          emitStatusEvent "run.completed" previousStatus
      | pollIndex >= maxPolls = do
          now <- getCurrentTime
          writeSseEvent
            write
            "run.window.closed"
            ( object
                [ "runId" .= runIdValue
                , "status" .= rsrStatus previousStatus
                , "reason" .= ("poll-window-complete" :: Text)
                , "timestamp" .= now
                ]
            )
          flush
      | otherwise = do
          threadDelay pollDelayMicros
          statusResult <- handleRunStatus service sessionId runIdValue
          case statusResult of
            Left err -> do
              writeSseEvent write "error" err
              flush
            Right nextStatus -> do
              if nextStatus /= previousStatus
                then emitStatusEvent "run.status" nextStatus
                else do
                  writeSseComment write ("run-status=" <> rsrStatus nextStatus)
                  flush
              pollWindow (pollIndex + 1) nextStatus

runProgressEvent :: Text -> UTCTime -> RunStatusResponse -> RunProgressEvent
runProgressEvent eventName timestamp statusValue =
  RunProgressEvent
    { rpeRunId = rsrRunId statusValue
    , rpeNodeId = Nothing
    , rpeEventType = eventName
    , rpeMessage = runStatusMessage statusValue
    , rpeProgress = rsrProgress statusValue
    , rpeTimestamp = timestamp
    }

runStatusMessage :: RunStatusResponse -> Text
runStatusMessage statusValue =
  "Run "
    <> unRunId (rsrRunId statusValue)
    <> " is "
    <> T.toLower (rsrStatus statusValue)
    <> maybe "" (\progressValue -> " (" <> T.pack (show progressValue) <> "%)") (rsrProgress statusValue)

isTerminalRunStatus :: Text -> Bool
isTerminalRunStatus statusValue =
  T.toLower statusValue `elem` ["completed", "succeeded", "failed", "cancelled", "runsucceeded", "runfailed"]

chunkChatMessage :: Int -> Text -> [Text]
chunkChatMessage chunkSize fullText =
  case T.words fullText of
    [] -> [fullText]
    wordsList -> chunkWords wordsList
  where
    chunkWords [] = []
    chunkWords remaining =
      let (currentChunk, rest) = splitAt chunkSize remaining
       in T.unwords currentChunk : chunkWords rest

writeSseEvent :: ToJSON a => (Builder -> IO ()) -> Text -> a -> IO ()
writeSseEvent write eventName payload =
  write $
    byteString "event: "
      <> byteString (TE.encodeUtf8 eventName)
      <> byteString "\n"
      <> byteString "data: "
      <> lazyByteString (encode payload)
      <> byteString "\n\n"

writeSseComment :: (Builder -> IO ()) -> Text -> IO ()
writeSseComment write commentText =
  write $
    byteString ": "
      <> byteString (TE.encodeUtf8 commentText)
      <> byteString "\n\n"

browserShellHtml :: BFFConfig -> LBS.ByteString
browserShellHtml _ =
  LBS.fromStrict . TE.encodeUtf8 $
    T.unlines
      [ "<!doctype html>"
      , "<html lang=\"en\">"
      , "<head>"
      , "  <meta charset=\"utf-8\">"
      , "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
      , "  <title>studioMCP Control Room</title>"
      , "  <style>"
      , "    :root {"
      , "      --sand: #f3eadc;"
      , "      --paper: rgba(255, 249, 240, 0.9);"
      , "      --ink: #123047;"
      , "      --muted: #5f7281;"
      , "      --teal: #0f766e;"
      , "      --copper: #c9693c;"
      , "      --line: rgba(18, 48, 71, 0.12);"
      , "      --shadow: 0 28px 72px rgba(18, 48, 71, 0.14);"
      , "      --radius: 22px;"
      , "    }"
      , "    * { box-sizing: border-box; }"
      , "    body {"
      , "      margin: 0;"
      , "      min-height: 100vh;"
      , "      font-family: \"IBM Plex Sans\", \"Avenir Next\", \"Segoe UI\", sans-serif;"
      , "      color: var(--ink);"
      , "      background:"
      , "        radial-gradient(circle at top left, rgba(15, 118, 110, 0.18), transparent 38%),"
      , "        radial-gradient(circle at top right, rgba(201, 105, 60, 0.22), transparent 34%),"
      , "        linear-gradient(180deg, #fcf7ef 0%, #efe3d1 100%);"
      , "    }"
      , "    body::before {"
      , "      content: \"\";"
      , "      position: fixed;"
      , "      inset: 0;"
      , "      pointer-events: none;"
      , "      background-image: linear-gradient(rgba(18, 48, 71, 0.035) 1px, transparent 1px), linear-gradient(90deg, rgba(18, 48, 71, 0.035) 1px, transparent 1px);"
      , "      background-size: 30px 30px;"
      , "      mask-image: linear-gradient(180deg, rgba(0,0,0,0.72), rgba(0,0,0,0.2));"
      , "    }"
      , "    main {"
      , "      position: relative;"
      , "      width: min(1240px, calc(100vw - 32px));"
      , "      margin: 24px auto 48px;"
      , "      display: grid;"
      , "      gap: 18px;"
      , "      grid-template-columns: repeat(12, minmax(0, 1fr));"
      , "    }"
      , "    .hero, .card {"
      , "      border: 1px solid var(--line);"
      , "      border-radius: var(--radius);"
      , "      background: var(--paper);"
      , "      box-shadow: var(--shadow);"
      , "      backdrop-filter: blur(14px);"
      , "    }"
      , "    .hero {"
      , "      grid-column: 1 / -1;"
      , "      padding: 28px;"
      , "      overflow: hidden;"
      , "      position: relative;"
      , "    }"
      , "    .hero::after {"
      , "      content: \"\";"
      , "      position: absolute;"
      , "      right: -56px;"
      , "      top: -36px;"
      , "      width: 240px;"
      , "      height: 240px;"
      , "      border-radius: 999px;"
      , "      background: radial-gradient(circle, rgba(15,118,110,0.22), transparent 68%);"
      , "    }"
      , "    .hero p { margin: 0; max-width: 64ch; color: var(--muted); line-height: 1.55; }"
      , "    .eyebrow { letter-spacing: 0.12em; text-transform: uppercase; font-size: 0.75rem; color: var(--teal); font-weight: 700; }"
      , "    h1, h2 { font-family: \"Iowan Old Style\", \"Palatino Linotype\", \"Book Antiqua\", serif; margin: 0 0 10px; }"
      , "    h1 { font-size: clamp(2.4rem, 5vw, 4.1rem); line-height: 0.98; max-width: 11ch; }"
      , "    .hero-meta { margin-top: 18px; display: flex; flex-wrap: wrap; gap: 12px; }"
      , "    .chip { display: inline-flex; align-items: center; gap: 8px; padding: 10px 14px; border-radius: 999px; background: rgba(255,255,255,0.72); border: 1px solid rgba(18, 48, 71, 0.08); font-size: 0.9rem; }"
      , "    .chip strong { color: var(--teal); }"
      , "    .card { padding: 22px; }"
      , "    .session { grid-column: span 4; }"
      , "    .storage { grid-column: span 4; }"
      , "    .workflow { grid-column: span 4; }"
      , "    .chat { grid-column: span 7; }"
      , "    .activity { grid-column: span 5; }"
      , "    .card-header { display: flex; justify-content: space-between; align-items: baseline; gap: 12px; margin-bottom: 16px; }"
      , "    .card-header p { margin: 0; color: var(--muted); font-size: 0.95rem; }"
      , "    form, .stack { display: grid; gap: 12px; }"
      , "    .row { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }"
      , "    label { display: grid; gap: 6px; font-size: 0.88rem; color: var(--muted); }"
      , "    input, textarea, select, button { font: inherit; }"
      , "    input, textarea, select {"
      , "      width: 100%;"
      , "      padding: 12px 14px;"
      , "      border-radius: 14px;"
      , "      border: 1px solid rgba(18, 48, 71, 0.14);"
      , "      background: rgba(255,255,255,0.84);"
      , "      color: var(--ink);"
      , "      resize: vertical;"
      , "    }"
      , "    textarea { min-height: 136px; }"
      , "    .tight textarea { min-height: 104px; }"
      , "    .actions { display: flex; flex-wrap: wrap; gap: 10px; }"
      , "    button {"
      , "      border: 0;"
      , "      border-radius: 999px;"
      , "      padding: 11px 16px;"
      , "      background: var(--teal);"
      , "      color: white;"
      , "      font-weight: 700;"
      , "      cursor: pointer;"
      , "      transition: transform 120ms ease, background 120ms ease;"
      , "    }"
      , "    button.secondary { background: #fff2e7; color: var(--copper); }"
      , "    button.ghost { background: rgba(18, 48, 71, 0.08); color: var(--ink); }"
      , "    button:hover { transform: translateY(-1px); }"
      , "    pre {"
      , "      margin: 0;"
      , "      padding: 16px;"
      , "      border-radius: 16px;"
      , "      background: #102a43;"
      , "      color: #f6f1e7;"
      , "      min-height: 140px;"
      , "      overflow: auto;"
      , "      font-family: \"IBM Plex Mono\", \"SFMono-Regular\", monospace;"
      , "      font-size: 0.85rem;"
      , "      line-height: 1.5;"
      , "    }"
      , "    .status-line { display: flex; flex-wrap: wrap; gap: 12px; color: var(--muted); font-size: 0.92rem; margin-top: 4px; }"
      , "    .status-dot { width: 10px; height: 10px; border-radius: 999px; background: var(--copper); display: inline-block; }"
      , "    .status-dot.live { background: var(--teal); box-shadow: 0 0 0 6px rgba(15, 118, 110, 0.12); }"
      , "    @media (max-width: 1080px) {"
      , "      .session, .storage, .workflow, .chat, .activity { grid-column: 1 / -1; }"
      , "    }"
      , "    @media (max-width: 720px) {"
      , "      main { width: min(100vw - 20px, 100%); margin-top: 12px; gap: 14px; }"
      , "      .hero, .card { padding: 18px; }"
      , "      .row { grid-template-columns: 1fr; }"
      , "      h1 { max-width: 100%; }"
      , "    }"
      , "  </style>"
      , "</head>"
      , "<body>"
      , "  <main>"
      , "    <section class=\"hero\">"
      , "      <div class=\"eyebrow\">Built-In Browser Workbench</div>"
      , "      <h1>studioMCP Control Room</h1>"
      , "      <p>The BFF now ships a browser UI, chat and run SSE streams, presigned upload and download flows, and direct workflow controls over the live MCP surface.</p>"
      , "      <div class=\"hero-meta\">"
      , "        <div class=\"chip\"><strong>Surface</strong><span>Same-origin browser shell</span></div>"
      , "        <div class=\"chip\"><strong>Streaming</strong><span>Chat + run events over SSE</span></div>"
      , "        <div class=\"chip\"><strong>Boundary</strong><span>Browser session to MCP session mediation</span></div>"
      , "      </div>"
      , "    </section>"
      , ""
      , "    <section class=\"card session\">"
      , "      <div class=\"card-header\">"
      , "        <div>"
      , "          <h2>Session</h2>"
      , "          <p>Issue and inspect the browser-side `studiomcp_session` cookie.</p>"
      , "        </div>"
      , "      </div>"
      , "      <form id=\"loginForm\">"
      , "        <label>Access Token<input id=\"accessToken\" value=\"browser-token\"></label>"
      , "        <div class=\"row\">"
      , "          <label>Subject Id<input id=\"subjectId\" placeholder=\"user-123\"></label>"
      , "          <label>Tenant Id<input id=\"tenantId\" placeholder=\"tenant-456\"></label>"
      , "        </div>"
      , "        <div class=\"actions\">"
      , "          <button type=\"submit\">Login</button>"
      , "          <button class=\"ghost\" type=\"button\" id=\"profileButton\">Profile</button>"
      , "          <button class=\"secondary\" type=\"button\" id=\"logoutButton\">Logout</button>"
      , "        </div>"
      , "      </form>"
      , "      <div class=\"status-line\"><span class=\"status-dot\" id=\"sessionDot\"></span><span id=\"sessionState\">No active browser session</span></div>"
      , "      <pre id=\"sessionOutput\">Login responses land here.</pre>"
      , "    </section>"
      , ""
      , "    <section class=\"card storage\">"
      , "      <div class=\"card-header\">"
      , "        <div>"
      , "          <h2>Artifacts</h2>"
      , "          <p>Request upload/download URLs and drive metadata-only hide/archive actions.</p>"
      , "        </div>"
      , "      </div>"
      , "      <div class=\"stack tight\">"
      , "        <div class=\"row\">"
      , "          <label>Artifact Id<input id=\"artifactId\" placeholder=\"artifact-xyz\"></label>"
      , "          <label>Version<input id=\"artifactVersion\" placeholder=\"2\"></label>"
      , "        </div>"
      , "        <div class=\"row\">"
      , "          <label>File Name<input id=\"fileName\" value=\"browser-demo.mp4\"></label>"
      , "          <label>Content Type<select id=\"contentType\"><option>video/mp4</option><option>audio/mpeg</option><option>image/jpeg</option></select></label>"
      , "        </div>"
      , "        <div class=\"row\">"
      , "          <label>File Size (bytes)<input id=\"fileSize\" type=\"number\" value=\"1048576\"></label>"
      , "          <label>Metadata JSON<textarea id=\"metadataJson\">[[\"source\",\"browser-ui\"]]</textarea></label>"
      , "        </div>"
      , "        <div class=\"actions\">"
      , "          <button type=\"button\" id=\"uploadButton\">Request Upload</button>"
      , "          <button class=\"ghost\" type=\"button\" id=\"confirmUploadButton\">Confirm Upload</button>"
      , "          <button class=\"ghost\" type=\"button\" id=\"downloadButton\">Request Download</button>"
      , "          <button class=\"secondary\" type=\"button\" id=\"hideArtifactButton\">Hide</button>"
      , "          <button class=\"secondary\" type=\"button\" id=\"archiveArtifactButton\">Archive</button>"
      , "        </div>"
      , "      </div>"
      , "      <pre id=\"artifactOutput\">Artifact responses land here.</pre>"
      , "    </section>"
      , ""
      , "    <section class=\"card workflow\">"
      , "      <div class=\"card-header\">"
      , "        <div>"
      , "          <h2>Workflow</h2>"
      , "          <p>Submit DAGs, inspect run state, and open the reconnectable SSE progress feed.</p>"
      , "        </div>"
      , "      </div>"
      , "      <div class=\"stack\">"
      , "        <label>DAG JSON<textarea id=\"dagSpecJson\">{\"name\":\"browser-demo\",\"description\":\"Submitted from the built-in BFF UI\",\"nodes\":[]}</textarea></label>"
      , "        <label>Input Artifacts JSON<textarea id=\"inputArtifactsJson\">[]</textarea></label>"
      , "        <div class=\"row\">"
      , "          <label>Run Id<input id=\"runId\" placeholder=\"run-abc\"></label>"
      , "          <label>Cancel Reason<input id=\"cancelReason\" value=\"browser-ui\"></label>"
      , "        </div>"
      , "        <div class=\"actions\">"
      , "          <button type=\"button\" id=\"submitRunButton\">Submit Run</button>"
      , "          <button class=\"ghost\" type=\"button\" id=\"statusRunButton\">Fetch Status</button>"
      , "          <button class=\"ghost\" type=\"button\" id=\"listRunsButton\">List Runs</button>"
      , "          <button class=\"secondary\" type=\"button\" id=\"cancelRunButton\">Cancel Run</button>"
      , "          <button class=\"ghost\" type=\"button\" id=\"watchRunButton\">Watch SSE</button>"
      , "          <button class=\"secondary\" type=\"button\" id=\"stopRunButton\">Stop SSE</button>"
      , "        </div>"
      , "      </div>"
      , "      <div class=\"status-line\"><span class=\"status-dot\" id=\"runDot\"></span><span id=\"runState\">Run stream idle</span></div>"
      , "      <pre id=\"runOutput\">Workflow responses land here.</pre>"
      , "    </section>"
      , ""
      , "    <section class=\"card chat\">"
      , "      <div class=\"card-header\">"
      , "        <div>"
      , "          <h2>Chat Stream</h2>"
      , "          <p>POST `/api/v1/chat/stream` emits chunked assistant messages over `text/event-stream`.</p>"
      , "        </div>"
      , "      </div>"
      , "      <div class=\"stack\">"
      , "        <label>Prompt<textarea id=\"chatMessage\">Help me plan a simple transcode workflow using the artifact tools and workflow.submit.</textarea></label>"
      , "        <label>Context<input id=\"chatContext\" value=\"Browser control room\"></label>"
      , "        <div class=\"actions\">"
      , "          <button type=\"button\" id=\"chatStreamButton\">Stream Reply</button>"
      , "        </div>"
      , "      </div>"
      , "      <pre id=\"chatOutput\">Chat stream output lands here.</pre>"
      , "    </section>"
      , ""
      , "    <section class=\"card activity\">"
      , "      <div class=\"card-header\">"
      , "        <div>"
      , "          <h2>Activity</h2>"
      , "          <p>High-signal request and stream events for quick inspection.</p>"
      , "        </div>"
      , "      </div>"
      , "      <pre id=\"activityOutput\">The browser shell is ready.</pre>"
      , "    </section>"
      , "  </main>"
      , "  <script>"
      , "    const state = { lastArtifactId: '', lastRunId: '', runStream: null };"
      , "    const decoder = new TextDecoder();"
      , "    const $ = (id) => document.getElementById(id);"
      , ""
      , "    function logActivity(label, payload) {"
      , "      const now = new Date().toLocaleTimeString();"
      , "      const current = $('activityOutput').textContent;"
      , "      const rendered = payload === undefined ? '' : '\\n' + formatPayload(payload);"
      , "      $('activityOutput').textContent = `[${now}] ${label}${rendered}\\n\\n${current}`.trim();"
      , "    }"
      , ""
      , "    function formatPayload(payload) {"
      , "      return typeof payload === 'string' ? payload : JSON.stringify(payload, null, 2);"
      , "    }"
      , ""
      , "    function setSessionState(text, live) {"
      , "      $('sessionState').textContent = text;"
      , "      $('sessionDot').classList.toggle('live', live);"
      , "    }"
      , ""
      , "    function setRunState(text, live) {"
      , "      $('runState').textContent = text;"
      , "      $('runDot').classList.toggle('live', live);"
      , "    }"
      , ""
      , "    function parseJsonInput(id, fallback) {"
      , "      const raw = $(id).value.trim();"
      , "      return raw ? JSON.parse(raw) : fallback;"
      , "    }"
      , ""
      , "    function optionalText(id) {"
      , "      const raw = $(id).value.trim();"
      , "      return raw === '' ? null : raw;"
      , "    }"
      , ""
      , "    async function readResponsePayload(response) {"
      , "      const text = await response.text();"
      , "      if (!text) {"
      , "        return null;"
      , "      }"
      , "      try {"
      , "        return JSON.parse(text);"
      , "      } catch (_err) {"
      , "        return text;"
      , "      }"
      , "    }"
      , ""
      , "    async function requestJson(path, options = {}) {"
      , "      const response = await fetch(path, {"
      , "        method: options.method || 'GET',"
      , "        credentials: 'same-origin',"
      , "        headers: {"
      , "          ...(options.body === undefined ? {} : { 'Content-Type': 'application/json' }),"
      , "          ...(options.headers || {})"
      , "        },"
      , "        body: options.body === undefined ? undefined : JSON.stringify(options.body)"
      , "      });"
      , "      const payload = await readResponsePayload(response);"
      , "      if (!response.ok) {"
      , "        throw new Error(formatPayload(payload || { status: response.status }));"
      , "      }"
      , "      return payload;"
      , "    }"
      , ""
      , "    function syncArtifactFields(artifactId) {"
      , "      if (!artifactId) return;"
      , "      state.lastArtifactId = artifactId;"
      , "      $('artifactId').value = artifactId;"
      , "      $('inputArtifactsJson').value = JSON.stringify([['input', artifactId]], null, 2);"
      , "    }"
      , ""
      , "    function syncRunField(runId) {"
      , "      if (!runId) return;"
      , "      state.lastRunId = runId;"
      , "      $('runId').value = runId;"
      , "    }"
      , ""
      , "    async function onLogin(event) {"
      , "      event.preventDefault();"
      , "      try {"
      , "        const payload = await requestJson('/api/v1/auth/login', {"
      , "          method: 'POST',"
      , "          body: {"
      , "            accessToken: $('accessToken').value.trim(),"
      , "            refreshToken: null,"
      , "            subjectId: optionalText('subjectId'),"
      , "            tenantId: optionalText('tenantId')"
      , "          }"
      , "        });"
      , "        setSessionState(`Session ready for ${payload.profile.subjectId} / ${payload.profile.tenantId}`, true);"
      , "        $('sessionOutput').textContent = formatPayload(payload);"
      , "        logActivity('Login succeeded', payload.profile);"
      , "      } catch (error) {"
      , "        $('sessionOutput').textContent = String(error);"
      , "        setSessionState('Login failed', false);"
      , "        logActivity('Login failed', String(error));"
      , "      }"
      , "    }"
      , ""
      , "    async function fetchProfile() {"
      , "      try {"
      , "        const payload = await requestJson('/api/v1/profile');"
      , "        $('sessionOutput').textContent = formatPayload(payload);"
      , "        setSessionState(`Session ready for ${payload.subjectId} / ${payload.tenantId}`, true);"
      , "        logActivity('Profile loaded', payload);"
      , "      } catch (error) {"
      , "        $('sessionOutput').textContent = String(error);"
      , "        setSessionState('No active browser session', false);"
      , "        logActivity('Profile lookup failed', String(error));"
      , "      }"
      , "    }"
      , ""
      , "    async function logout() {"
      , "      stopRunStream();"
      , "      try {"
      , "        const payload = await requestJson('/api/v1/auth/logout', { method: 'POST' });"
      , "        $('sessionOutput').textContent = formatPayload(payload);"
      , "        setSessionState('No active browser session', false);"
      , "        logActivity('Logout succeeded', payload);"
      , "      } catch (error) {"
      , "        $('sessionOutput').textContent = String(error);"
      , "        logActivity('Logout failed', String(error));"
      , "      }"
      , "    }"
      , ""
      , "    async function requestUpload() {"
      , "      try {"
      , "        const payload = await requestJson('/api/v1/upload/request', {"
      , "          method: 'POST',"
      , "          body: {"
      , "            artifactId: optionalText('artifactId'),"
      , "            fileName: $('fileName').value.trim(),"
      , "            contentType: $('contentType').value,"
      , "            fileSize: Number($('fileSize').value),"
      , "            metadata: parseJsonInput('metadataJson', [])"
      , "          }"
      , "        });"
      , "        syncArtifactFields(payload.artifactId);"
      , "        $('artifactOutput').textContent = formatPayload(payload);"
      , "        logActivity('Upload intent created', payload);"
      , "      } catch (error) {"
      , "        $('artifactOutput').textContent = String(error);"
      , "        logActivity('Upload intent failed', String(error));"
      , "      }"
      , "    }"
      , ""
      , "    async function confirmUpload() {"
      , "      const artifactId = optionalText('artifactId') || state.lastArtifactId;"
      , "      if (!artifactId) {"
      , "        $('artifactOutput').textContent = 'Artifact id required for confirmation.';"
      , "        return;"
      , "      }"
      , "      try {"
      , "        const payload = await requestJson(`/api/v1/upload/confirm/${encodeURIComponent(artifactId)}`, { method: 'POST' });"
      , "        $('artifactOutput').textContent = formatPayload(payload);"
      , "        logActivity('Upload confirmed', { artifactId });"
      , "      } catch (error) {"
      , "        $('artifactOutput').textContent = String(error);"
      , "        logActivity('Upload confirm failed', String(error));"
      , "      }"
      , "    }"
      , ""
      , "    async function requestDownload() {"
      , "      const artifactId = optionalText('artifactId') || state.lastArtifactId;"
      , "      if (!artifactId) {"
      , "        $('artifactOutput').textContent = 'Artifact id required for download.';"
      , "        return;"
      , "      }"
      , "      try {"
      , "        const payload = await requestJson('/api/v1/download', {"
      , "          method: 'POST',"
      , "          body: { artifactId, version: optionalText('artifactVersion') }"
      , "        });"
      , "        $('artifactOutput').textContent = formatPayload(payload);"
      , "        logActivity('Download intent created', payload);"
      , "      } catch (error) {"
      , "        $('artifactOutput').textContent = String(error);"
      , "        logActivity('Download intent failed', String(error));"
      , "      }"
      , "    }"
      , ""
      , "    async function artifactAction(action) {"
      , "      const artifactId = optionalText('artifactId') || state.lastArtifactId;"
      , "      if (!artifactId) {"
      , "        $('artifactOutput').textContent = 'Artifact id required for governance actions.';"
      , "        return;"
      , "      }"
      , "      try {"
      , "        const payload = await requestJson(`/api/v1/artifacts/${encodeURIComponent(artifactId)}/${action}`, {"
      , "          method: 'POST',"
      , "          body: { reason: 'browser-ui' }"
      , "        });"
      , "        $('artifactOutput').textContent = formatPayload(payload);"
      , "        logActivity(`Artifact ${action} succeeded`, payload);"
      , "      } catch (error) {"
      , "        $('artifactOutput').textContent = String(error);"
      , "        logActivity(`Artifact ${action} failed`, String(error));"
      , "      }"
      , "    }"
      , ""
      , "    async function readSseStream(stream, onEvent) {"
      , "      const reader = stream.getReader();"
      , "      let buffer = '';"
      , "      while (true) {"
      , "        const { value, done } = await reader.read();"
      , "        if (done) break;"
      , "        buffer += decoder.decode(value, { stream: true });"
      , "        let boundary = buffer.indexOf('\\n\\n');"
      , "        while (boundary !== -1) {"
      , "          const frame = buffer.slice(0, boundary);"
      , "          buffer = buffer.slice(boundary + 2);"
      , "          if (frame.trim() !== '') {"
      , "            onEvent(frame);"
      , "          }"
      , "          boundary = buffer.indexOf('\\n\\n');"
      , "        }"
      , "      }"
      , "    }"
      , ""
      , "    function parseSseFrame(frame) {"
      , "      const event = { event: 'message', data: '' };"
      , "      const dataLines = [];"
      , "      for (const line of frame.split('\\n')) {"
      , "        if (line.startsWith('event:')) event.event = line.slice(6).trim();"
      , "        if (line.startsWith('data:')) dataLines.push(line.slice(5).trim());"
      , "      }"
      , "      event.data = dataLines.join('\\n');"
      , "      try {"
      , "        event.payload = event.data ? JSON.parse(event.data) : null;"
      , "      } catch (_err) {"
      , "        event.payload = event.data;"
      , "      }"
      , "      return event;"
      , "    }"
      , ""
      , "    async function streamChat() {"
      , "      $('chatOutput').textContent = '';"
      , "      try {"
      , "        const response = await fetch('/api/v1/chat/stream', {"
      , "          method: 'POST',"
      , "          credentials: 'same-origin',"
      , "          headers: { 'Content-Type': 'application/json' },"
      , "          body: JSON.stringify({"
      , "            messages: [{ role: 'user', content: $('chatMessage').value, timestamp: null }],"
      , "            context: optionalText('chatContext')"
      , "          })"
      , "        });"
      , "        if (!response.ok || !response.body) {"
      , "          throw new Error(formatPayload(await readResponsePayload(response)));"
      , "        }"
      , "        let assembled = '';"
      , "        await readSseStream(response.body, (frame) => {"
      , "          const parsed = parseSseFrame(frame);"
      , "          if (parsed.event === 'message.delta' && parsed.payload) {"
      , "            assembled = [assembled, parsed.payload.delta].filter(Boolean).join(' ').trim();"
      , "            $('chatOutput').textContent = assembled;"
      , "          } else if (parsed.event === 'message.completed' && parsed.payload) {"
      , "            $('chatOutput').textContent = formatPayload(parsed.payload);"
      , "          }"
      , "          logActivity(`Chat stream ${parsed.event}`, parsed.payload);"
      , "        });"
      , "      } catch (error) {"
      , "        $('chatOutput').textContent = String(error);"
      , "        logActivity('Chat stream failed', String(error));"
      , "      }"
      , "    }"
      , ""
      , "    async function submitRun() {"
      , "      try {"
      , "        const payload = await requestJson('/api/v1/runs', {"
      , "          method: 'POST',"
      , "          body: {"
      , "            dagSpec: parseJsonInput('dagSpecJson', {}),"
      , "            inputArtifacts: parseJsonInput('inputArtifactsJson', [])"
      , "          }"
      , "        });"
      , "        syncRunField(payload.runId);"
      , "        $('runOutput').textContent = formatPayload(payload);"
      , "        logActivity('Run submitted', payload);"
      , "        startRunStream();"
      , "      } catch (error) {"
      , "        $('runOutput').textContent = String(error);"
      , "        logActivity('Run submit failed', String(error));"
      , "      }"
      , "    }"
      , ""
      , "    async function fetchRunStatus() {"
      , "      const runId = optionalText('runId') || state.lastRunId;"
      , "      if (!runId) {"
      , "        $('runOutput').textContent = 'Run id required.';"
      , "        return;"
      , "      }"
      , "      try {"
      , "        const payload = await requestJson(`/api/v1/runs/${encodeURIComponent(runId)}/status`);"
      , "        syncRunField(payload.runId);"
      , "        $('runOutput').textContent = formatPayload(payload);"
      , "        logActivity('Run status loaded', payload);"
      , "      } catch (error) {"
      , "        $('runOutput').textContent = String(error);"
      , "        logActivity('Run status failed', String(error));"
      , "      }"
      , "    }"
      , ""
      , "    async function listRuns() {"
      , "      try {"
      , "        const payload = await requestJson('/api/v1/runs?limit=10');"
      , "        $('runOutput').textContent = formatPayload(payload);"
      , "        if (payload && payload.runs && payload.runs[0]) syncRunField(payload.runs[0].runId);"
      , "        logActivity('Run list loaded', payload);"
      , "      } catch (error) {"
      , "        $('runOutput').textContent = String(error);"
      , "        logActivity('Run list failed', String(error));"
      , "      }"
      , "    }"
      , ""
      , "    async function cancelRun() {"
      , "      const runId = optionalText('runId') || state.lastRunId;"
      , "      if (!runId) {"
      , "        $('runOutput').textContent = 'Run id required.';"
      , "        return;"
      , "      }"
      , "      try {"
      , "        const payload = await requestJson(`/api/v1/runs/${encodeURIComponent(runId)}/cancel`, {"
      , "          method: 'POST',"
      , "          body: { reason: optionalText('cancelReason') || 'browser-ui' }"
      , "        });"
      , "        $('runOutput').textContent = formatPayload(payload);"
      , "        logActivity('Run cancelled', payload);"
      , "      } catch (error) {"
      , "        $('runOutput').textContent = String(error);"
      , "        logActivity('Run cancel failed', String(error));"
      , "      }"
      , "    }"
      , ""
      , "    function stopRunStream() {"
      , "      if (state.runStream) {"
      , "        state.runStream.close();"
      , "        state.runStream = null;"
      , "      }"
      , "      setRunState('Run stream idle', false);"
      , "    }"
      , ""
      , "    function startRunStream() {"
      , "      const runId = optionalText('runId') || state.lastRunId;"
      , "      if (!runId) {"
      , "        $('runOutput').textContent = 'Run id required.';"
      , "        return;"
      , "      }"
      , "      stopRunStream();"
      , "      const source = new EventSource(`/api/v1/runs/${encodeURIComponent(runId)}/events`);"
      , "      state.runStream = source;"
      , "      setRunState(`Watching ${runId}`, true);"
      , "      const handleEvent = (label) => (event) => {"
      , "        const payload = JSON.parse(event.data);"
      , "        $('runOutput').textContent = formatPayload(payload);"
      , "        logActivity(label, payload);"
      , "        if (label === 'run.completed') {"
      , "          setRunState(`Terminal status: ${payload.message}`, false);"
      , "        }"
      , "      };"
      , "      source.addEventListener('run.snapshot', handleEvent('run.snapshot'));"
      , "      source.addEventListener('run.status', handleEvent('run.status'));"
      , "      source.addEventListener('run.completed', handleEvent('run.completed'));"
      , "      source.addEventListener('run.window.closed', handleEvent('run.window.closed'));"
      , "      source.addEventListener('error', (event) => {"
      , "        if (event.data) {"
      , "          try {"
      , "            const payload = JSON.parse(event.data);"
      , "            $('runOutput').textContent = formatPayload(payload);"
      , "            logActivity('run.error', payload);"
      , "          } catch (_err) {"
      , "            logActivity('run.error', event.data);"
      , "          }"
      , "        }"
      , "      });"
      , "      source.onerror = () => {"
      , "        setRunState(`Waiting for ${runId} SSE reconnect`, true);"
      , "      };"
      , "    }"
      , ""
      , "    $('loginForm').addEventListener('submit', onLogin);"
      , "    $('profileButton').addEventListener('click', fetchProfile);"
      , "    $('logoutButton').addEventListener('click', logout);"
      , "    $('uploadButton').addEventListener('click', requestUpload);"
      , "    $('confirmUploadButton').addEventListener('click', confirmUpload);"
      , "    $('downloadButton').addEventListener('click', requestDownload);"
      , "    $('hideArtifactButton').addEventListener('click', () => artifactAction('hide'));"
      , "    $('archiveArtifactButton').addEventListener('click', () => artifactAction('archive'));"
      , "    $('chatStreamButton').addEventListener('click', streamChat);"
      , "    $('submitRunButton').addEventListener('click', submitRun);"
      , "    $('statusRunButton').addEventListener('click', fetchRunStatus);"
      , "    $('listRunsButton').addEventListener('click', listRuns);"
      , "    $('cancelRunButton').addEventListener('click', cancelRun);"
      , "    $('watchRunButton').addEventListener('click', startRunStream);"
      , "    $('stopRunButton').addEventListener('click', stopRunStream);"
      , "  </script>"
      , "</body>"
      , "</html>"
      ]
