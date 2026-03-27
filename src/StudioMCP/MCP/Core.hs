{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module StudioMCP.MCP.Core
  ( -- * MCP Server
    McpServer (..),
    McpServerConfig (..),
    defaultServerConfig,

    -- * Server Lifecycle
    newMcpServer,
    newMcpServerWithObservability,
    newMcpServerWithCatalogs,
    runMcpServer,
    stopMcpServer,

    -- * Request Handling
    handleMessage,
    handleMessageWithAuth,
    dispatchMethod,

    -- * Server Capabilities
    buildServerCapabilities,
    serverInfo,
  )
where

import Control.Concurrent (MVar, newMVar, putMVar, takeMVar)
import Control.Concurrent.STM (TVar, atomically, newTVarIO, readTVar, readTVarIO, writeTVar)
import Control.Exception (SomeException, catch, try)
import Control.Monad (forever, unless, void, when)
import Data.Aeson
  ( FromJSON,
    Result (..),
    ToJSON,
    Value (..),
    decode,
    encode,
    fromJSON,
    object,
    toJSON,
    (.=),
  )
import qualified Data.Aeson.KeyMap as KM
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (getCurrentTime)
import StudioMCP.Auth.Scopes
  ( authorizePromptGet,
    authorizeResourceRead,
    authorizeToolCall,
  )
import StudioMCP.Auth.Types
  ( AuthContext (..),
    AuthDecision (..),
    SubjectId (..),
    Tenant (..),
    TenantId (..),
    authErrorToText,
    subjectId,
    tenantId,
  )
import StudioMCP.MCP.Context
import StudioMCP.MCP.JsonRpc
import StudioMCP.MCP.Prompts
  ( PromptCatalog,
    PromptError (..),
    getPrompt,
    listPrompts,
    newPromptCatalog,
  )
import StudioMCP.MCP.Protocol.StateMachine
import StudioMCP.MCP.Protocol.Types
import StudioMCP.MCP.Resources
  ( ResourceCatalog,
    ResourceError (..),
    listResources,
    newResourceCatalog,
    readResource,
  )
import qualified StudioMCP.MCP.Resources as McpResources
import StudioMCP.MCP.Session.Types (Session, newSession)
import StudioMCP.MCP.Tools
  ( ToolCatalog,
    ToolError (..),
    ToolResult (..),
    callTool,
    listTools,
    newToolCatalog,
  )
import qualified StudioMCP.MCP.Tools as McpTools
import StudioMCP.MCP.Transport.Types
import qualified StudioMCP.MCP.Transport.Types as Transport
import StudioMCP.Observability.McpMetrics
  ( McpMetricsService,
    recordMethodCall,
    recordPromptGet,
    recordResourceRead,
  )
import StudioMCP.Observability.RateLimiting
  ( RateLimiterService,
    RateLimitKey (..),
    RateLimitResult (..),
    RateLimitWindow (..),
    checkRateLimit,
    recordRequest,
  )

-- | MCP Server configuration
data McpServerConfig = McpServerConfig
  { mscServerName :: Text,
    mscServerVersion :: Text,
    mscCapabilities :: ServerCapabilities
  }
  deriving (Eq, Show)

-- | Default server configuration
defaultServerConfig :: McpServerConfig
defaultServerConfig =
  McpServerConfig
    { mscServerName = "studioMCP",
      mscServerVersion = "0.1.0",
      mscCapabilities = defaultCapabilities
    }

-- | Default server capabilities
defaultCapabilities :: ServerCapabilities
defaultCapabilities =
  ServerCapabilities
    { scTools = Just (ToolsCapability {tcListChanged = Just True}),
      scResources = Just (ResourcesCapability {rcSubscribe = Just False, rcListChanged = Just True}),
      scPrompts = Just (PromptsCapability {pcListChanged = Just True}),
      scLogging = Just LoggingCapability
    }

-- | MCP Server state
data McpServer = McpServer
  { msConfig :: McpServerConfig,
    msSession :: TVar (Maybe Session),
    msProtocolState :: TVar ProtocolState,
    msIsRunning :: TVar Bool,
    msToolCatalog :: ToolCatalog,
    msResourceCatalog :: ResourceCatalog,
    msPromptCatalog :: PromptCatalog,
    msRateLimiter :: Maybe RateLimiterService,
    msMetrics :: Maybe McpMetricsService
  }

-- | Create a new MCP server
newMcpServer :: McpServerConfig -> IO McpServer
newMcpServer config = do
  toolCatalog <- newToolCatalog
  resourceCatalog <- newResourceCatalog
  promptCatalog <- newPromptCatalog
  newMcpServerWithCatalogs config toolCatalog resourceCatalog promptCatalog Nothing Nothing

-- | Create a new MCP server with observability services
newMcpServerWithObservability :: McpServerConfig -> RateLimiterService -> McpMetricsService -> IO McpServer
newMcpServerWithObservability config rateLimiter metrics = do
  toolCatalog <- newToolCatalog
  resourceCatalog <- newResourceCatalog
  promptCatalog <- newPromptCatalog
  newMcpServerWithCatalogs config toolCatalog resourceCatalog promptCatalog (Just rateLimiter) (Just metrics)

newMcpServerWithCatalogs ::
  McpServerConfig ->
  ToolCatalog ->
  ResourceCatalog ->
  PromptCatalog ->
  Maybe RateLimiterService ->
  Maybe McpMetricsService ->
  IO McpServer
newMcpServerWithCatalogs config toolCatalog resourceCatalog promptCatalog maybeRateLimiter maybeMetrics = do
  sessionVar <- newTVarIO Nothing
  stateVar <- newTVarIO Uninitialized
  runningVar <- newTVarIO False
  pure
    McpServer
      { msConfig = config,
        msSession = sessionVar,
        msProtocolState = stateVar,
        msIsRunning = runningVar,
        msToolCatalog = toolCatalog,
        msResourceCatalog = resourceCatalog,
        msPromptCatalog = promptCatalog,
        msRateLimiter = maybeRateLimiter,
        msMetrics = maybeMetrics
      }

-- | Run MCP server with a transport
runMcpServer :: McpServer -> Transport -> IO ()
runMcpServer server transport = do
  atomically $ writeTVar (msIsRunning server) True

  let loop = do
        isRunning <- readTVarIO (msIsRunning server)
        isOpen <- transportIsOpen transport
        when (isRunning && isOpen) $ do
          result <- transportReceive transport
          case result of
            Left Transport.ConnectionClosed -> do
              atomically $ writeTVar (msIsRunning server) False
            Left err -> do
              -- Send error response and continue
              let errResp = makeErrorResponse (RequestIdNumber 0) (parseError (transportErrorToText err))
              void $ transportSend transport (toJSON errResp)
              loop
            Right msg -> do
              response <- handleMessage server msg
              case response of
                Just resp -> void $ transportSend transport resp
                Nothing -> pure () -- Notification, no response
              loop

  loop `catch` \(e :: SomeException) -> do
    atomically $ writeTVar (msIsRunning server) False

-- | Stop the MCP server
stopMcpServer :: McpServer -> IO ()
stopMcpServer server = do
  atomically $ writeTVar (msIsRunning server) False

-- | Handle incoming JSON-RPC message
handleMessage :: McpServer -> Value -> IO (Maybe Value)
handleMessage server msg = handleMessageWithAuth server Nothing msg

-- | Handle incoming JSON-RPC message with authentication context
handleMessageWithAuth :: McpServer -> Maybe AuthContext -> Value -> IO (Maybe Value)
handleMessageWithAuth server maybeAuth msg = do
  -- Parse the message
  case fromJSON msg of
    Error err ->
      pure $ Just $ toJSON $ makeErrorResponse (RequestIdNumber 0) (parseError (T.pack err))
    Success jsonRpcMsg ->
      case jsonRpcMsg of
        MsgRequest req -> do
          resp <- handleRequestWithAuth server maybeAuth req
          pure $ Just $ toJSON resp
        MsgNotification notif -> do
          handleNotification server notif
          pure Nothing -- Notifications don't get responses
        MsgResponse _ ->
          -- Server shouldn't receive responses
          pure $ Just $ toJSON $ makeErrorResponse (RequestIdNumber 0) (invalidRequest "Unexpected response message")

-- | Handle JSON-RPC request (legacy, without auth)
handleRequest :: McpServer -> JsonRpcRequest -> IO JsonRpcResponse
handleRequest server = handleRequestWithAuth server Nothing

-- | Handle JSON-RPC request with authentication context
handleRequestWithAuth :: McpServer -> Maybe AuthContext -> JsonRpcRequest -> IO JsonRpcResponse
handleRequestWithAuth server maybeAuth req = do
  let method = reqMethod req
      requestId = reqId req
      params = reqParams req

  -- Check rate limiting first (if enabled and auth context available)
  rateLimitResult <- case (msRateLimiter server, maybeAuth) of
    (Just rateLimiter, Just authCtx) -> do
      let key = TenantKey (tenantId (acTenant authCtx))
      result <- checkRateLimit rateLimiter key PerMinute
      case result of
        RateLimitAllowed _ _ -> do
          recordRequest rateLimiter key PerMinute
          pure Nothing -- No rate limit error
        RateLimitDenied retryAfter _ ->
          pure $ Just $ makeErrorResponse requestId $
            invalidRequest ("Rate limit exceeded. Retry after " <> T.pack (show retryAfter) <> " seconds")
    _ -> pure Nothing -- No rate limiting

  case rateLimitResult of
    Just errorResp -> pure errorResp
    Nothing -> do
      -- Create request context with auth if available
      ctx <- case maybeAuth of
        Just authCtx -> newRequestContextWithAuth method (Just $ toJSON requestId) authCtx
        Nothing -> newRequestContext method (Just $ toJSON requestId)

      -- Record method call metrics (with 0 latency for now - timing added in Phase 20+)
      case msMetrics server of
        Just metrics -> recordMethodCall metrics method 0.0 True
        Nothing -> pure ()

      -- Check protocol state
      state <- readTVarIO (msProtocolState server)

      case method of
        "initialize" -> handleInitialize server requestId params
        _ ->
          -- Check if method is allowed in current state
          if stateAllowsMethod state method
            then dispatchMethod server ctx requestId method params
            else
              pure $
                makeErrorResponse requestId $
                  if state == Uninitialized
                    then serverNotInitialized
                    else invalidRequest "Method not allowed in current state"

-- | Handle JSON-RPC notification
handleNotification :: McpServer -> JsonRpcNotification -> IO ()
handleNotification server notif = do
  let method = notifMethod notif
      params = notifParams notif

  case method of
    "notifications/initialized" -> do
      -- Transition from Initializing to Ready
      atomically $ do
        state <- readTVar (msProtocolState server)
        when (state == Initializing) $
          writeTVar (msProtocolState server) Ready
    "notifications/cancelled" -> do
      -- Handle cancellation (Phase 18+)
      pure ()
    _ -> do
      -- Unknown notification, ignore
      pure ()

-- | Handle initialize request
handleInitialize :: McpServer -> RequestId -> Maybe Value -> IO JsonRpcResponse
handleInitialize server reqId params = do
  -- Check current state
  state <- readTVarIO (msProtocolState server)

  case state of
    Uninitialized -> do
      -- Parse initialization params
      case params >>= \p -> case fromJSON p of Success v -> Just v; _ -> Nothing of
        Nothing ->
          pure $ makeErrorResponse reqId (invalidParams "Invalid or missing initialization parameters")
        Just (initParams :: InitializeParams) -> do
          -- Check protocol version
          let clientVersion = ipProtocolVersion initParams
          if clientVersion `elem` supportedVersions
            then do
              -- Create session
              session <- newSession

              -- Update state
              atomically $ do
                writeTVar (msProtocolState server) Initializing
                writeTVar (msSession server) (Just session)

              -- Build response
              let result =
                    InitializeResult
                      { irProtocolVersion = currentProtocolVersion,
                        irCapabilities = mscCapabilities (msConfig server),
                        irServerInfo = serverInfo (msConfig server)
                      }

              pure $ makeResponse reqId (toJSON result)
            else do
              let ProtocolVersion v = clientVersion
              pure $ makeErrorResponse reqId (unsupportedProtocolVersion v)
    Initializing ->
      pure $ makeErrorResponse reqId (invalidRequest "Already initializing")
    Ready ->
      pure $ makeErrorResponse reqId (invalidRequest "Already initialized")
    _ ->
      pure $ makeErrorResponse reqId (invalidRequest "Cannot initialize in current state")

-- | Dispatch method to handler
dispatchMethod :: McpServer -> RequestContext -> RequestId -> Text -> Maybe Value -> IO JsonRpcResponse
dispatchMethod server ctx reqId method params =
  case method of
    -- Tool methods
    "tools/list" -> handleToolsList server reqId params
    "tools/call" -> handleToolsCall server ctx reqId params
    -- Resource methods
    "resources/list" -> handleResourcesList server ctx reqId params
    "resources/read" -> handleResourcesRead server ctx reqId params
    -- Prompt methods
    "prompts/list" -> handlePromptsList server reqId params
    "prompts/get" -> handlePromptsGet server ctx reqId params
    -- Completion methods
    "completion/complete" -> handleCompletionComplete server ctx reqId params
    -- Logging methods
    "logging/setLevel" -> handleLoggingSetLevel server reqId params
    -- Ping
    "ping" -> handlePing reqId
    -- Unknown method
    _ -> pure $ makeErrorResponse reqId (methodNotFound method)

-- | Handle tools/list
handleToolsList :: McpServer -> RequestId -> Maybe Value -> IO JsonRpcResponse
handleToolsList server reqId _ = do
  tools <- listTools (msToolCatalog server)
  let result = object ["tools" .= tools]
  pure $ makeResponse reqId result

-- | Handle tools/call
handleToolsCall :: McpServer -> RequestContext -> RequestId -> Maybe Value -> IO JsonRpcResponse
handleToolsCall server ctx reqId params = do
  case params >>= \p -> case fromJSON p of Success v -> Just v; _ -> Nothing of
    Nothing ->
      pure $ makeErrorResponse reqId (invalidParams "Invalid tool call parameters")
    Just (callParams :: CallToolParams) -> do
      case authorizeIfPresent (ctxAuthContext ctx) (authorizeToolCall (ctpName callParams)) of
        Just authErr ->
          pure $ makeErrorResponse reqId authErr
        Nothing -> do
          let (tenant, subject) = requestIdentity ctx
          result <- callTool (msToolCatalog server) tenant subject callParams
          pure $
            case result of
              ToolSuccess toolResult -> makeResponse reqId (toJSON toolResult)
              ToolFailure toolErr ->
                makeErrorResponse reqId (toolErrorToJsonRpcError toolErr)

-- | Handle resources/list
handleResourcesList :: McpServer -> RequestContext -> RequestId -> Maybe Value -> IO JsonRpcResponse
handleResourcesList server ctx reqId _ = do
  let tenant = requestTenant (ctxAuthContext ctx)
  resources <- listResources (msResourceCatalog server) tenant
  let result = object ["resources" .= resources]
  pure $ makeResponse reqId result

-- | Handle resources/read
handleResourcesRead :: McpServer -> RequestContext -> RequestId -> Maybe Value -> IO JsonRpcResponse
handleResourcesRead server ctx reqId params = do
  case params >>= \p -> case fromJSON p of Success v -> Just v; _ -> Nothing of
    Nothing ->
      pure $ makeErrorResponse reqId (invalidParams "Invalid resource read parameters")
    Just (readParams :: ReadResourceParams) ->
      case authorizeIfPresent (ctxAuthContext ctx) (authorizeResourceRead (rrpUri readParams)) of
        Just authErr ->
          pure $ makeErrorResponse reqId authErr
        Nothing -> do
          let tenant = requestTenant (ctxAuthContext ctx)
          result <- readResource (msResourceCatalog server) tenant readParams
          case msMetrics server of
            Just metrics ->
              recordResourceRead metrics (rrpUri readParams) tenant (either (const False) (const True) result) False
            Nothing -> pure ()
          pure $
            case result of
              Right resourceResult -> makeResponse reqId (toJSON resourceResult)
              Left resourceErr -> makeErrorResponse reqId (resourceErrorToJsonRpcError resourceErr)

-- | Handle prompts/list
handlePromptsList :: McpServer -> RequestId -> Maybe Value -> IO JsonRpcResponse
handlePromptsList server reqId _ = do
  prompts <- listPrompts (msPromptCatalog server)
  let result = object ["prompts" .= prompts]
  pure $ makeResponse reqId result

-- | Handle prompts/get
handlePromptsGet :: McpServer -> RequestContext -> RequestId -> Maybe Value -> IO JsonRpcResponse
handlePromptsGet server ctx reqId params = do
  case params >>= \p -> case fromJSON p of Success v -> Just v; _ -> Nothing of
    Nothing ->
      pure $ makeErrorResponse reqId (invalidParams "Invalid prompt parameters")
    Just (getParams :: GetPromptParams) ->
      case authorizeIfPresent (ctxAuthContext ctx) (authorizePromptGet (gppName getParams)) of
        Just authErr ->
          pure $ makeErrorResponse reqId authErr
        Nothing -> do
          let tenant = requestTenant (ctxAuthContext ctx)
          result <- getPrompt (msPromptCatalog server) tenant getParams
          case msMetrics server of
            Just metrics ->
              recordPromptGet metrics (gppName getParams) tenant (either (const False) (const True) result)
            Nothing -> pure ()
          pure $
            case result of
              Right promptResult -> makeResponse reqId (toJSON promptResult)
              Left promptErr -> makeErrorResponse reqId (promptErrorToJsonRpcError promptErr)

-- | Handle completion/complete
handleCompletionComplete :: McpServer -> RequestContext -> RequestId -> Maybe Value -> IO JsonRpcResponse
handleCompletionComplete server ctx reqId params = do
  -- Return empty completion for now
  let result = object ["completion" .= object ["values" .= ([] :: [Text])]]
  pure $ makeResponse reqId result

-- | Handle logging/setLevel
handleLoggingSetLevel :: McpServer -> RequestId -> Maybe Value -> IO JsonRpcResponse
handleLoggingSetLevel server reqId params = do
  -- Acknowledge log level change
  pure $ makeResponse reqId (object [])

-- | Handle ping
handlePing :: RequestId -> IO JsonRpcResponse
handlePing reqId = pure $ makeResponse reqId (object [])

requestIdentity :: RequestContext -> (TenantId, SubjectId)
requestIdentity ctx =
  (requestTenant (ctxAuthContext ctx), requestSubject (ctxAuthContext ctx))

requestTenant :: Maybe AuthContext -> TenantId
requestTenant maybeAuth =
  maybe (TenantId "local") (tenantId . acTenant) maybeAuth

requestSubject :: Maybe AuthContext -> SubjectId
requestSubject maybeAuth =
  maybe (SubjectId "anonymous") (subjectId . acSubject) maybeAuth

authorizeIfPresent :: Maybe AuthContext -> (AuthContext -> AuthDecision) -> Maybe JsonRpcError
authorizeIfPresent Nothing _ = Nothing
authorizeIfPresent (Just authCtx) authorize =
  case authorize authCtx of
    Allowed -> Nothing
    Denied err -> Just (authDenied (authErrorToText err))

toolErrorToJsonRpcError :: ToolError -> JsonRpcError
toolErrorToJsonRpcError toolErr =
  case toolErr of
    ToolNotFound name -> methodNotFound ("Tool not found: " <> name)
    InvalidArguments message -> invalidParams message
    McpTools.ExecutionFailed message -> executionFailed message
    AuthorizationFailed message -> authDenied message
    McpTools.ResourceNotFound resourceUri -> resourceNotFound resourceUri
    RateLimited -> quotaExceeded "Rate limit exceeded"

resourceErrorToJsonRpcError :: ResourceError -> JsonRpcError
resourceErrorToJsonRpcError resourceErr =
  case resourceErr of
    McpResources.ResourceNotFound resourceUri -> resourceNotFound resourceUri
    InvalidResourceUri message -> invalidParams message
    ResourceAccessDenied message -> artifactAccessDenied message
    ResourceReadFailed message -> internalError message

promptErrorToJsonRpcError :: PromptError -> JsonRpcError
promptErrorToJsonRpcError promptErr =
  case promptErr of
    PromptNotFound name -> methodNotFound ("Prompt not found: " <> name)
    InvalidPromptArguments message -> invalidParams message
    PromptRenderFailed message -> internalError message

-- | Build server capabilities
buildServerCapabilities :: McpServerConfig -> ServerCapabilities
buildServerCapabilities = mscCapabilities

-- | Build server info
serverInfo :: McpServerConfig -> ServerInfo
serverInfo config =
  ServerInfo
    { siName = mscServerName config,
      siVersion = mscServerVersion config
    }
