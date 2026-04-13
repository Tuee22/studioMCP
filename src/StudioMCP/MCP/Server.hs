{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.MCP.Server
  ( runServer,
    runServerStdio,
  )
where

import Control.Concurrent.Async (mapConcurrently)
import Control.Concurrent.STM (atomically, readTVarIO, writeTVar)
import Data.Aeson (ToJSON, decode, encode, object, (.=))
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (IORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Text qualified as Textual
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
    healthReportFromChecks,
    HealthStatus (Degraded, Healthy),
  )
import StudioMCP.API.Readiness
  ( ReadinessCheck,
    ReadinessReport (..),
    ReadinessStatus (..),
    blockedCheck,
    buildReadinessReport,
    probeHttpCheck,
    readinessCheckName,
    readinessCheckReason,
    readinessHttpStatus,
    readyCheck,
    renderBlockingChecks,
  )
import StudioMCP.Auth.Config (AuthConfig (..), jwksEndpoint, loadAuthConfigFromEnv)
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
import StudioMCP.Config.Types (AppConfig (..))
import StudioMCP.MCP.Core
  ( McpServer (..),
    defaultServerConfig,
    handleMessageWithAuth,
    newMcpServerWithCatalogs,
    runMcpServer,
  )
import StudioMCP.MCP.Handlers
  ( ServerEnv (..),
    createServerEnv,
    currentVersionInfo,
  )
import StudioMCP.MCP.Prompts (newPromptCatalog)
import StudioMCP.MCP.Protocol.StateMachine (ProtocolState (ShuttingDown))
import StudioMCP.MCP.Session.Store (SessionStoreError (..), storeDeleteSession)
import StudioMCP.MCP.Session.Types (Session (sessionId), SessionData (..), SessionId (..))
import StudioMCP.MCP.Session.RedisStore (readSessionData, testConnection, writeSessionData)
import StudioMCP.MCP.Transport.Http (getMcpSessionId)
import StudioMCP.MCP.Transport.Stdio (createStdioTransport, defaultStdioConfig, runStdioTransport)
import qualified StudioMCP.Observability.McpMetrics as McpMetrics
import StudioMCP.Util.Logging (configureProcessLogging, logInfo)
import System.Environment (lookupEnv)

runServer :: IO ()
runServer = do
  configureProcessLogging
  (serverEnv, mcpServer, authConfig, authService) <- buildRuntime
  port <- resolveServerPort
  putStrLn ("studioMCP server listening on 0.0.0.0:" <> show port)
  putStrLn ("Auth enabled: " <> show (acEnabled authConfig))
  runSettings
    (setHost "0.0.0.0" (setPort port (setTimeout 0 defaultSettings)))
    (application serverEnv mcpServer authConfig authService)

runServerStdio :: IO ()
runServerStdio = do
  configureProcessLogging
  (_, mcpServer, _, _) <- buildRuntime
  stdioTransport <- createStdioTransport defaultStdioConfig
  putStrLn "studioMCP server listening on stdio"
  runMcpServer mcpServer (runStdioTransport stdioTransport)

buildRuntime :: IO (ServerEnv, McpServer, AuthConfig, AuthService)
buildRuntime = do
  appConfig <- loadAppConfig
  serverEnv <- createServerEnv appConfig
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
      (Just (serverSessionStore serverEnv))
  pure (serverEnv, mcpServer, authConfig, authService)

application :: ServerEnv -> McpServer -> AuthConfig -> AuthService -> Application
application serverEnv mcpServer authConfig authService request respond =
  case pathInfo request of
    -- MCP JSON-RPC endpoint - accessible at / or /mcp (for ingress prefix stripping)
    [] -> handleMcpEndpoint serverEnv mcpServer authConfig authService request respond
    ["mcp"] -> handleMcpEndpoint serverEnv mcpServer authConfig authService request respond
    -- Admin endpoints (no auth required for health/metrics)
    ["healthz"] | requestMethod request == methodGet ->
      handleHealth serverEnv mcpServer authConfig respond
    ["mcp", "healthz"] | requestMethod request == methodGet ->
      handleHealth serverEnv mcpServer authConfig respond
    ["health", "live"] | requestMethod request == methodGet ->
      respond (jsonResponse status200 (object ["status" .= ("ok" :: Text)]))
    ["mcp", "health", "live"] | requestMethod request == methodGet ->
      respond (jsonResponse status200 (object ["status" .= ("ok" :: Text)]))
    ["health", "ready"] | requestMethod request == methodGet ->
      handleReadiness serverEnv mcpServer authConfig respond
    ["mcp", "health", "ready"] | requestMethod request == methodGet ->
      handleReadiness serverEnv mcpServer authConfig respond
    ["version"] | requestMethod request == methodGet ->
      respond (jsonResponse status200 (currentVersionInfo serverEnv))
    ["metrics"] | requestMethod request == methodGet ->
      handleMetrics serverEnv mcpServer authConfig respond
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
        Left (errStatus, errText) ->
          respond (jsonResponse errStatus (object ["error" .= errText]))
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
                Left (errStatus, errText) ->
                  respond (jsonResponse errStatus (object ["error" .= errText]))
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
        Left (errStatus, errText) ->
          respond (jsonResponse errStatus (object ["error" .= errText]))
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
  McpServer ->
  AuthConfig ->
  (Response -> IO b) ->
  IO b
handleHealth serverEnv mcpServer authConfig respond = do
  readinessReport <- serverReadinessReport serverEnv mcpServer authConfig
  let healthReport = healthReportFromChecks (readinessChecks readinessReport)
      statusValue =
        case healthStatus healthReport of
          Healthy -> status200
          Degraded -> status503
  respond (jsonResponse statusValue healthReport)

handleReadiness ::
  ServerEnv ->
  McpServer ->
  AuthConfig ->
  (Response -> IO b) ->
  IO b
handleReadiness serverEnv mcpServer authConfig respond = do
  readinessReport <- serverReadinessReport serverEnv mcpServer authConfig
  logReadinessTransition "studiomcp-server" (serverReadinessSummaryRef serverEnv) readinessReport
  respond (jsonResponse (readinessHttpStatus readinessReport) readinessReport)

handleMetrics ::
  ServerEnv ->
  McpServer ->
  AuthConfig ->
  (Response -> IO b) ->
  IO b
handleMetrics serverEnv mcpServer authConfig respond = do
  metricsSnapshot <- McpMetrics.getMcpMetrics (serverMcpMetrics serverEnv)
  readinessReport <- serverReadinessReport serverEnv mcpServer authConfig
  respond
    ( responseLBS
        status200
        [(hContentType, "text/plain; version=0.0.4")]
        ( LBS.fromStrict
            ( Text.encodeUtf8
                ( McpMetrics.renderPrometheusMetrics metricsSnapshot
                    <> renderReadinessPrometheusMetrics readinessReport
                )
            )
        )
    )

serverReadinessReport :: ServerEnv -> McpServer -> AuthConfig -> IO ReadinessReport
serverReadinessReport serverEnv mcpServer authConfig = do
  checkGroups <-
    mapConcurrently
      id
      [ protocolStateCheck mcpServer,
        sessionStoreCheck serverEnv,
        authJwksCheck serverEnv authConfig,
        platformDependenciesCheck serverEnv
      ]
  pure (buildReadinessReport "studiomcp-server" (concat checkGroups))

protocolStateCheck :: McpServer -> IO [ReadinessCheck]
protocolStateCheck mcpServer = do
  protocolState <- readTVarIO (msProtocolState mcpServer)
  pure
    [ case protocolState of
        ShuttingDown ->
          blockedCheck
            "protocol-state"
            "protocol-shutting-down"
            "the MCP protocol state machine is shutting down"
        _ ->
          readyCheck
            "protocol-state"
            "protocol-ready"
            "the MCP protocol state machine accepts traffic"
    ]

sessionStoreCheck :: ServerEnv -> IO [ReadinessCheck]
sessionStoreCheck serverEnv = do
  pingResult <- testConnection (serverSessionStore serverEnv)
  pure
    [ case pingResult of
        Left sessionErr ->
          blockedCheck
            "redis-session-store"
            "session-store-unavailable"
            (Textual.pack (show sessionErr))
        Right () ->
          readyCheck
            "redis-session-store"
            "session-store-ready"
            "the shared MCP session store is reachable"
    ]

authJwksCheck :: ServerEnv -> AuthConfig -> IO [ReadinessCheck]
authJwksCheck serverEnv authConfig
  | not (acEnabled authConfig) =
      pure
        [ readyCheck
            "auth-jwks"
            "auth-disabled"
            "authentication is disabled for this server"
        ]
  | otherwise =
      (: [])
        <$> probeHttpCheck
          (serverHttpManager serverEnv)
          "auth-jwks"
          (jwksEndpoint (acKeycloak authConfig))
          [200]
          "auth-jwks-ready"
          "auth-jwks-unavailable"

platformDependenciesCheck :: ServerEnv -> IO [ReadinessCheck]
platformDependenciesCheck serverEnv = do
  dependencyChecks <-
    mapConcurrently
      id
      [ probeHttpCheck
          (serverHttpManager serverEnv)
          "pulsar"
          (pulsarHttpUrl (serverAppConfig serverEnv) <> "/admin/v2/clusters")
          [200]
          "dependency-ready"
          "dependency-unavailable",
        probeHttpCheck
          (serverHttpManager serverEnv)
          "minio"
          (minioEndpoint (serverAppConfig serverEnv) <> "/minio/health/ready")
          [200]
          "dependency-ready"
          "dependency-unavailable"
      ]
  pure dependencyChecks

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

renderReadinessPrometheusMetrics :: ReadinessReport -> Text
renderReadinessPrometheusMetrics readinessReport =
  Textual.unlines $
    [ "# HELP studiomcp_readiness Indicates whether the MCP server readiness contract is closed",
      "# TYPE studiomcp_readiness gauge",
      "studiomcp_readiness "
        <> case readinessStatus readinessReport of
          ReadinessReady -> "1"
          ReadinessBlocked -> "0",
      "# HELP studiomcp_readiness_blocking_total Number of blocking readiness checks",
      "# TYPE studiomcp_readiness_blocking_total gauge",
      "studiomcp_readiness_blocking_total "
        <> Textual.pack (show (length (readinessBlockingChecks readinessReport)))
    ]
      <> readinessBlockingMetricLines (readinessBlockingChecks readinessReport)

readinessBlockingMetricLines :: [ReadinessCheck] -> [Text]
readinessBlockingMetricLines [] = []
readinessBlockingMetricLines blockingChecks =
  [ "# HELP studiomcp_readiness_blocking Blocking readiness checks by reason",
    "# TYPE studiomcp_readiness_blocking gauge"
  ]
    <> map renderBlockingMetric blockingChecks
  where
    renderBlockingMetric readinessCheck =
      "studiomcp_readiness_blocking{check=\""
        <> escapePrometheusLabel (readinessCheckName readinessCheck)
        <> "\",reason=\""
        <> escapePrometheusLabel (readinessCheckReason readinessCheck)
        <> "\"} 1"

escapePrometheusLabel :: Text -> Text
escapePrometheusLabel =
  Textual.concatMap escapeCharacter
  where
    escapeCharacter '"' = "\\\""
    escapeCharacter '\\' = "\\\\"
    escapeCharacter character = Textual.singleton character

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
    (msSessionStore mcpServer)

hydrateRequestSession :: ServerEnv -> McpServer -> Request -> IO (Either (Status, Text) ())
hydrateRequestSession serverEnv scopedServer request =
  case getMcpSessionId request of
    Nothing -> pure (Right ())
    Just sidText -> do
      -- First verify Redis is reachable with an explicit ping, to detect outages
      -- that would otherwise hang on session reads
      pingResult <- testConnection (serverSessionStore serverEnv)
      case pingResult of
        Left sessionErr -> pure (Left (sessionStoreHttpError sessionErr))
        Right () -> do
          sessionDataResult <- readSessionData (serverSessionStore serverEnv) (SessionId sidText)
          case sessionDataResult of
            Left sessionErr -> pure (Left (sessionStoreHttpError sessionErr))
            Right sessionData ->
              persistScopedState scopedServer (sdSession sessionData) (sdProtocolState sessionData)

persistRequestSession :: ServerEnv -> McpServer -> IO (Either (Status, Text) (Maybe Text))
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
          Left sessionErr -> Left (sessionStoreHttpError sessionErr)
          Right () -> Right (Just (currentSessionIdText sessionValue))

sessionStoreHttpError :: SessionStoreError -> (Status, Text)
sessionStoreHttpError sessionErr =
  case sessionErr of
    SessionNotFound _ -> (status400, "Unknown or expired MCP session")
    StoreConnectionError _ -> (status503, "MCP session store unavailable")
    StoreUnavailable _ -> (status503, "MCP session store unavailable")
    StoreTimeoutError _ -> (status503, "MCP session store timed out")
    SessionSerializationError _ -> (status503, "Failed to persist MCP session state")
    SessionDeserializationError _ -> (status503, "Failed to read MCP session state")
    LockAcquisitionFailed _ -> (status503, "Failed to coordinate MCP session state")
    LockNotHeld _ -> (status503, "Failed to coordinate MCP session state")
    SessionAlreadyExists _ -> (status400, "MCP session already exists")

persistScopedState :: McpServer -> Session -> ProtocolState -> IO (Either (Status, Text) ())
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
