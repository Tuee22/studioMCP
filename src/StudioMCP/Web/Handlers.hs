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

    -- * OAuth Handlers
    handleLoginInitiate,
    handleOAuthCallbackRoute,
    handleLogoutRoute,
    handleTokenRefreshRoute,
  )
where

import Data.Aeson (FromJSON, ToJSON, decode, encode, object, (.=))
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.HTTP.Types
  ( Status,
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
    requestMethod,
    responseLBS,
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
bffApplication :: BFFContext -> Application
bffApplication ctx request respond =
  case (requestMethod request, pathInfo request) of
    -- Health check
    ("GET", ["healthz"]) ->
      respond $ jsonResponse status200 (object ["status" .= ("healthy" :: Text)])

    ("GET", ["health", "live"]) ->
      respond $ jsonResponse status200 (object ["status" .= ("live" :: Text)])

    ("GET", ["health", "ready"]) ->
      respond $ jsonResponse status200 (object ["status" .= ("ready" :: Text)])

    -- Upload endpoints
    ("POST", ["api", "v1", "upload", "request"]) ->
      handleJsonRoute ctx request respond handleUploadRequest

    ("POST", ["api", "v1", "upload", "confirm", artifactId]) ->
      withSession ctx request respond $ \service sessionId ->
        respondBffResult status200 respond =<< confirmUpload service sessionId artifactId

    -- Download endpoint
    ("POST", ["api", "v1", "download"]) ->
      handleJsonRoute ctx request respond handleDownloadRequest

    -- Chat endpoint
    ("POST", ["api", "v1", "chat"]) ->
      handleJsonRoute ctx request respond handleChatRequest

    -- Run endpoints
    ("POST", ["api", "v1", "runs"]) ->
      handleJsonRoute ctx request respond handleRunSubmit

    ("GET", ["api", "v1", "runs", runIdText, "status"]) ->
      withSession ctx request respond $ \service sessionId ->
        respondBffResult status200 respond =<< getRunStatus service sessionId (RunId runIdText)

    -- OAuth endpoints
    ("GET", ["auth", "login"]) ->
      handleLoginInitiate ctx request respond

    ("POST", ["auth", "login"]) ->
      handleLoginInitiate ctx request respond

    ("GET", ["auth", "callback"]) ->
      handleOAuthCallbackRoute ctx request respond

    ("POST", ["auth", "callback"]) ->
      handleOAuthCallbackRoute ctx request respond

    ("POST", ["auth", "logout"]) ->
      withSession ctx request respond $ \service sessionId ->
        respondBffResult status200 respond =<< handleLogout service sessionId

    ("POST", ["auth", "refresh"]) ->
      withSession ctx request respond $ \service sessionId ->
        respondBffResult status200 respond =<< handleTokenRefresh service sessionId

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
extractSessionId :: Request -> Maybe WebSessionId
extractSessionId request =
  -- Look in Authorization header: "Bearer session-xxx"
  case lookup "Authorization" (requestHeaders request) of
    Just authHeader ->
      let headerText = TE.decodeUtf8 authHeader
       in if "Bearer " `T.isPrefixOf` headerText
            then Just $ WebSessionId $ T.drop 7 headerText
            else Nothing
    Nothing -> Nothing

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

-- | Create JSON response
jsonResponse :: ToJSON a => Status -> a -> Response
jsonResponse status body =
  responseLBS status [(hContentType, "application/json")] (encode body)

-- | Handle login initiation
handleLoginInitiate ::
  BFFContext ->
  Request ->
  (Response -> IO ResponseReceived) ->
  IO ResponseReceived
handleLoginInitiate ctx request respond = do
  let service = bffCtxService ctx
  -- Optional redirect_uri from query string
  let mRedirectUri = extractQueryParam "redirect_uri" request
  result <- initiateLogin service mRedirectUri
  respondBffResult status200 respond result

-- | Handle OAuth callback
handleOAuthCallbackRoute ::
  BFFContext ->
  Request ->
  (Response -> IO ResponseReceived) ->
  IO ResponseReceived
handleOAuthCallbackRoute ctx request respond = do
  let service = bffCtxService ctx
  -- Extract code and state from query params (GET) or body (POST)
  let method = requestMethod request
  (mCode, mState) <-
    if method == "GET"
      then pure (extractQueryParam "code" request, extractQueryParam "state" request)
      else do
        bodyResult <- decode <$> strictRequestBody request
        case bodyResult of
          Just req -> pure (Just (ocrCode req), Just (ocrState req))
          Nothing -> pure (extractQueryParam "code" request, extractQueryParam "state" request)

  case (mCode, mState) of
    (Just code, Just state) -> do
      let callbackReq = OAuthCallbackRequest {ocrCode = code, ocrState = state}
      result <- handleOAuthCallback service callbackReq
      respondBffResult status200 respond result
    _ ->
      respond $ jsonResponse status400 (object ["error" .= ("Missing code or state parameter" :: Text)])

-- | Handle logout route
handleLogoutRoute ::
  BFFService ->
  WebSessionId ->
  IO (Either BFFError LogoutResponse)
handleLogoutRoute = handleLogout

-- | Handle token refresh route
handleTokenRefreshRoute ::
  BFFService ->
  WebSessionId ->
  IO (Either BFFError TokenRefreshResponse)
handleTokenRefreshRoute = handleTokenRefresh

-- | Extract a query parameter from the request
extractQueryParam :: Text -> Request -> Maybe Text
extractQueryParam name request =
  case lookup (TE.encodeUtf8 name) (queryString request) of
    Just (Just value) -> Just (TE.decodeUtf8 value)
    _ -> Nothing
