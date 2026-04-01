{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.MCP.Server
  ( runServer,
  )
where

import Control.Concurrent.STM (atomically, readTVarIO, writeTVar)
import Data.Aeson (ToJSON, decode, encode, object, (.=))
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text.Encoding qualified as Text
import Network.HTTP.Client (newManager, defaultManagerSettings)
import Network.HTTP.Types
  ( hContentType,
    methodDelete,
    methodGet,
    methodPost,
    Status,
    status200,
    status400,
    status404,
    status405,
    status503,
  )
import Network.Wai
  ( Application,
    Request,
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
import StudioMCP.Auth.Config (AuthConfig (..), loadAuthConfigFromEnv)
import StudioMCP.Auth.Middleware
  ( AuthService,
    authenticateWaiRequest,
    devBypassAuth,
    newAuthService,
  )
import StudioMCP.Auth.Types
  ( AuthContext (..),
    AuthError,
    authErrorToHttpStatus,
    authErrorToText,
    subjectId,
    tenantId,
  )
import StudioMCP.Config.Load (loadAppConfig)
import StudioMCP.MCP.Core
  ( McpServer (..),
    defaultServerConfig,
    handleMessageWithAuth,
    newMcpServerWithCatalogs,
  )
import StudioMCP.MCP.Handlers
  ( ServerEnv (..),
    createServerEnv,
    currentHealthReport,
    currentVersionInfo,
  )
import StudioMCP.MCP.Prompts (newPromptCatalog)
import StudioMCP.MCP.Protocol.StateMachine (ProtocolState (ShuttingDown))
import StudioMCP.MCP.Session.Store (storeDeleteSession)
import StudioMCP.MCP.Session.Types (Session (sessionId), SessionData (..), SessionId (..))
import StudioMCP.MCP.Session.RedisStore (readSessionData, writeSessionData)
import StudioMCP.MCP.Transport.Http (getMcpSessionId)
import qualified StudioMCP.Observability.McpMetrics as McpMetrics
import StudioMCP.Util.Logging (configureProcessLogging)
import System.Environment (lookupEnv)

runServer :: IO ()
runServer = do
  configureProcessLogging
  appConfig <- loadAppConfig
  serverEnv <- createServerEnv appConfig

  -- Initialize auth service
  authConfig <- loadAuthConfigFromEnv
  httpManager <- newManager defaultManagerSettings
  authService <- newAuthService authConfig httpManager

  promptCatalog <- newPromptCatalog
  mcpServer <-
    newMcpServerWithCatalogs
      defaultServerConfig
      (serverToolCatalog serverEnv)
      (serverResourceCatalog serverEnv)
      promptCatalog
      (Just (serverRateLimiter serverEnv))
      (Just (serverMcpMetrics serverEnv))
  port <- resolveServerPort
  putStrLn ("studioMCP server listening on 0.0.0.0:" <> show port)
  putStrLn ("Auth enabled: " <> show (acEnabled authConfig))
  runSettings
    (setHost "0.0.0.0" (setPort port (setTimeout 0 defaultSettings)))
    (application serverEnv mcpServer authConfig authService)

application :: ServerEnv -> McpServer -> AuthConfig -> AuthService -> Application
application serverEnv mcpServer authConfig authService request respond =
  case pathInfo request of
    -- MCP JSON-RPC endpoint (new in Phase 13) - requires auth in production
    ["mcp"] -> handleMcpEndpoint serverEnv mcpServer authConfig authService request respond
    -- Admin endpoints (no auth required for health/metrics)
    ["healthz"] | requestMethod request == methodGet ->
      handleHealth serverEnv respond
    ["health", "live"] | requestMethod request == methodGet ->
      respond (jsonResponse status200 (object ["status" .= ("ok" :: Text)]))
    ["health", "ready"] | requestMethod request == methodGet ->
      handleReadiness mcpServer respond
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

-- | Handle MCP JSON-RPC endpoint with authentication
handleMcpEndpoint :: ServerEnv -> McpServer -> AuthConfig -> AuthService -> Application
handleMcpEndpoint serverEnv mcpServer authConfig authService request respond = do
  -- Authenticate the request (or use dev bypass if auth disabled)
  authResult <- authenticateMcpRequest authConfig authService request
  case authResult of
    Left authErr ->
      respond
        ( jsonResponse
            (authErrorToHttpStatus authErr)
            (object
              [ "jsonrpc" .= ("2.0" :: Text)
              , "error" .= object
                  [ "code" .= (-32001 :: Int)
                  , "message" .= authErrorToText authErr
                  ]
              , "id" .= (Nothing :: Maybe ())
              ])
        )
    Right authContext ->
      handleAuthenticatedMcpRequest serverEnv mcpServer authContext request respond

-- | Authenticate MCP request or return dev bypass
authenticateMcpRequest ::
  AuthConfig ->
  AuthService ->
  Request ->
  IO (Either AuthError AuthContext)
authenticateMcpRequest authConfig authService request =
  if acEnabled authConfig
    then authenticateWaiRequest authService request
    else pure $ Right devAuthContext
  where
    -- Development bypass auth context
    devAuthContext = devBypassAuth "dev-user" "dev-tenant"

-- | Handle authenticated MCP request
handleAuthenticatedMcpRequest :: ServerEnv -> McpServer -> AuthContext -> Application
handleAuthenticatedMcpRequest serverEnv mcpServer authContext request respond =
  case requestMethod request of
    method | method == methodPost -> do
      scopedServer <- newRequestScopedServer mcpServer
      hydrateResult <- hydrateRequestSession serverEnv scopedServer request
      case hydrateResult of
        Left errText ->
          respond (jsonResponse status400 (object ["error" .= errText]))
        Right () -> do
          -- Standard MCP request/response
          requestBody <- strictRequestBody request
          case decode requestBody of
            Nothing ->
              respond
                ( jsonResponse
                    status400
                    (object
                      [ "jsonrpc" .= ("2.0" :: Text)
                      , "error" .= object
                          [ "code" .= (-32700 :: Int)
                          , "message" .= ("Parse error" :: Text)
                          ]
                      , "id" .= (Nothing :: Maybe ())
                      ])
                )
            Just jsonValue -> do
              maybeResponse <- handleMessageWithAuth scopedServer (Just authContext) jsonValue
              persistResult <- persistRequestSession serverEnv scopedServer
              case persistResult of
                Left errText ->
                  respond (jsonResponse status400 (object ["error" .= errText]))
                Right maybeSessionId ->
                  case maybeResponse of
                    Just respValue ->
                      respond (jsonResponseWithSession status200 respValue maybeSessionId)
                    Nothing ->
                      respond
                        ( responseLBS
                            status200
                            ([(hContentType, "application/json")] <> maybe [] (\sid -> [("Mcp-Session-Id", Text.encodeUtf8 sid)]) maybeSessionId)
                            ""
                        )
    method | method == methodGet -> do
      scopedServer <- newRequestScopedServer mcpServer
      hydrateResult <- hydrateRequestSession serverEnv scopedServer request
      case hydrateResult of
        Left errText ->
          respond (jsonResponse status400 (object ["error" .= errText]))
        Right () -> do
          sessionId <- resolveResponseSessionId scopedServer request
          let bootstrap =
                object
                  [ "tenantId" .= tenantId (acTenant authContext)
                  , "subjectId" .= subjectId (acSubject authContext)
                  , "sessionId" .= sessionId
                  , "status" .= ("ready" :: Text)
                  ]
          respond
            ( responseLBS
                status200
                ( [ (hContentType, "text/event-stream")
                , ("Cache-Control", "no-cache")
                , ("Connection", "keep-alive")
                ]
                    <> maybe [] (\sid -> [("Mcp-Session-Id", Text.encodeUtf8 sid)]) sessionId
                )
                (LBS.concat ["event: ready\ndata: ", encode bootstrap, "\n\n"])
            )
    method | method == methodDelete -> do
      -- Session termination
      let sessionId = getMcpSessionId request
      case sessionId of
        Nothing ->
          respond
            ( jsonResponse
                status400
                (object ["error" .= ("Missing Mcp-Session-Id header" :: Text)])
            )
        Just sid -> do
          _ <- storeDeleteSession (serverSessionStore serverEnv) (SessionId sid)
          respond
            ( jsonResponse
                status200
                (object ["terminated" .= True])
            )
    _ ->
      respond
        ( jsonResponse
            status405
            (object ["error" .= ("Method not allowed" :: Text)])
        )

-- | JSON response with optional session header
jsonResponseWithSession :: ToJSON a => Status -> a -> Maybe Text -> Response
jsonResponseWithSession statusValue payload maybeSessionId =
  let sessionHeaders = case maybeSessionId of
        Just sid -> [("Mcp-Session-Id", Text.encodeUtf8 sid)]
        Nothing -> []
  in responseLBS
       statusValue
       ((hContentType, "application/json") : sessionHeaders)
       (encode payload)

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

handleReadiness ::
  McpServer ->
  (Response -> IO b) ->
  IO b
handleReadiness mcpServer respond = do
  protocolState <- readTVarIO (msProtocolState mcpServer)
  let (statusValue, readinessStatus) =
        case protocolState of
          ShuttingDown -> (status503, "shutting-down" :: Text)
          _ -> (status200, "ready" :: Text)
  respond (jsonResponse statusValue (object ["status" .= readinessStatus]))

handleMetrics ::
  ServerEnv ->
  (Response -> IO b) ->
  IO b
handleMetrics serverEnv respond = do
  metricsSnapshot <- McpMetrics.getMcpMetrics (serverMcpMetrics serverEnv)
  respond
    ( responseLBS
        status200
        [(hContentType, "text/plain; version=0.0.4")]
        (LBS.fromStrict (Text.encodeUtf8 (McpMetrics.renderPrometheusMetrics metricsSnapshot)))
    )

jsonResponse :: ToJSON a => Status -> a -> Response
jsonResponse statusValue payload =
  responseLBS
    statusValue
    [(hContentType, "application/json")]
    (encode payload)

resolveResponseSessionId :: McpServer -> Request -> IO (Maybe Text)
resolveResponseSessionId mcpServer request = do
  let requestSessionId = getMcpSessionId request
  case requestSessionId of
    Just _ -> pure requestSessionId
    Nothing -> do
      currentSession <- readTVarIO (msSession mcpServer)
      pure (currentSessionIdText <$> currentSession)

currentSessionIdText :: Session -> Text
currentSessionIdText session =
  case sessionId session of
    SessionId sid -> sid

newRequestScopedServer :: McpServer -> IO McpServer
newRequestScopedServer mcpServer =
  newMcpServerWithCatalogs
    (msConfig mcpServer)
    (msToolCatalog mcpServer)
    (msResourceCatalog mcpServer)
    (msPromptCatalog mcpServer)
    (msRateLimiter mcpServer)
    (msMetrics mcpServer)

hydrateRequestSession :: ServerEnv -> McpServer -> Request -> IO (Either Text ())
hydrateRequestSession serverEnv scopedServer request =
  case getMcpSessionId request of
    Nothing -> pure (Right ())
    Just sidText -> do
      sessionDataResult <- readSessionData (serverSessionStore serverEnv) (SessionId sidText)
      case sessionDataResult of
        Left _ -> pure (Left "Unknown or expired MCP session")
        Right sessionData ->
          persistScopedState scopedServer (sdSession sessionData) (sdProtocolState sessionData)

persistRequestSession :: ServerEnv -> McpServer -> IO (Either Text (Maybe Text))
persistRequestSession serverEnv scopedServer = do
  currentSession <- readTVarIO (msSession scopedServer)
  currentProtocolState <- readTVarIO (msProtocolState scopedServer)
  case currentSession of
    Nothing -> pure (Right Nothing)
    Just sessionValue -> do
      let sessionData =
            SessionData
              { sdSession = sessionValue,
                sdProtocolState = currentProtocolState
              }
      writeResult <- writeSessionData (serverSessionStore serverEnv) sessionData
      pure $
        case writeResult of
          Left _ -> Left "Failed to persist MCP session state"
          Right () -> Right (Just (currentSessionIdText sessionValue))

persistScopedState :: McpServer -> Session -> ProtocolState -> IO (Either Text ())
persistScopedState scopedServer sessionValue protocolState = do
  atomically $ do
    writeTVar (msSession scopedServer) (Just sessionValue)
    writeTVar (msProtocolState scopedServer) protocolState
  pure (Right ())

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
