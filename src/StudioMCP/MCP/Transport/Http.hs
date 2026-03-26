{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module StudioMCP.MCP.Transport.Http
  ( -- * HTTP Transport Types
    HttpTransportConfig (..),
    defaultHttpTransportConfig,

    -- * Server-Side Handling
    HttpRequestContext (..),
    handleMcpRequest,
    handleMcpSse,

    -- * Response Building
    McpHttpResponse (..),
    responseToWai,

    -- * Session Header
    mcpSessionHeader,
    getMcpSessionId,
  )
where

import Control.Concurrent (Chan, newChan, readChan, writeChan)
import Control.Concurrent.Async (async, cancel)
import Control.Exception (SomeException, try)
import Data.Aeson (Value, decode, encode, object, (.=))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.CaseInsensitive (CI)
import qualified Data.CaseInsensitive as CI
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.HTTP.Types
  ( Header,
    Status,
    hContentType,
    status200,
    status400,
    status401,
    status403,
    status404,
    status405,
    status413,
    status500,
  )
import Network.Wai (Request, Response, requestHeaders, requestMethod, responseLBS, strictRequestBody)
import StudioMCP.MCP.JsonRpc
import StudioMCP.MCP.Transport.Types

-- | HTTP transport configuration
data HttpTransportConfig = HttpTransportConfig
  { htcMaxMessageSize :: Int,
    htcSseKeepAliveSeconds :: Int,
    htcSessionTimeoutSeconds :: Int
  }
  deriving (Eq, Show)

-- | Default HTTP transport configuration
defaultHttpTransportConfig :: HttpTransportConfig
defaultHttpTransportConfig =
  HttpTransportConfig
    { htcMaxMessageSize = 10 * 1024 * 1024, -- 10MB
      htcSseKeepAliveSeconds = 30,
      htcSessionTimeoutSeconds = 1800 -- 30 minutes
    }

-- | MCP session header name
mcpSessionHeader :: CI BS.ByteString
mcpSessionHeader = CI.mk "Mcp-Session-Id"

-- | Extract session ID from request headers
getMcpSessionId :: Request -> Maybe Text
getMcpSessionId req =
  TE.decodeUtf8' <$> lookup mcpSessionHeader (requestHeaders req) >>= either (const Nothing) Just

-- | HTTP request context for MCP handling
data HttpRequestContext = HttpRequestContext
  { hrcSessionId :: Maybe Text,
    hrcCorrelationId :: Text,
    hrcAuthHeader :: Maybe Text
  }
  deriving (Eq, Show)

-- | MCP HTTP response types
data McpHttpResponse
  = -- | Standard JSON response
    McpJsonResponse Status Value
  | -- | Error response with JSON-RPC error
    McpErrorResponse Status JsonRpcError
  | -- | SSE stream initiation
    McpSseResponse (Chan Value)
  deriving ()

-- | Handle incoming MCP HTTP request
handleMcpRequest ::
  HttpTransportConfig ->
  Request ->
  (Value -> IO (Either JsonRpcError Value)) ->
  IO McpHttpResponse
handleMcpRequest config req handler = do
  -- Check method
  case requestMethod req of
    "POST" -> handlePost config req handler
    "GET" -> handleGet config req
    "DELETE" -> handleDelete config req
    _ -> pure $ McpErrorResponse status405 (invalidRequest "Method not allowed")

-- | Handle POST request (main MCP request/response)
handlePost ::
  HttpTransportConfig ->
  Request ->
  (Value -> IO (Either JsonRpcError Value)) ->
  IO McpHttpResponse
handlePost config req handler = do
  -- Read body
  bodyResult <- try $ strictRequestBody req
  case bodyResult of
    Left (e :: SomeException) ->
      pure $ McpErrorResponse status400 (parseError (T.pack (show e)))
    Right body -> do
      -- Check size
      let size = LBS.length body
      if size > fromIntegral (htcMaxMessageSize config)
        then
          pure $
            McpErrorResponse
              status413
              (invalidRequest "Request body too large")
        else case decode body of
          Nothing ->
            pure $ McpErrorResponse status400 (parseError "Invalid JSON")
          Just value -> do
            -- Handle the request
            result <- handler value
            case result of
              Left err ->
                pure $ McpErrorResponse status200 err -- JSON-RPC errors return 200
              Right response ->
                pure $ McpJsonResponse status200 response

-- | Handle GET request (SSE stream establishment)
handleGet ::
  HttpTransportConfig ->
  Request ->
  IO McpHttpResponse
handleGet config req = do
  -- GET is used for SSE streaming
  -- The actual SSE handling happens in handleMcpSse
  chan <- newChan
  pure $ McpSseResponse chan

-- | Handle DELETE request (session termination)
handleDelete ::
  HttpTransportConfig ->
  Request ->
  IO McpHttpResponse
handleDelete config req = do
  let sessionId = getMcpSessionId req
  case sessionId of
    Nothing ->
      pure $ McpErrorResponse status400 (invalidRequest "Missing Mcp-Session-Id header")
    Just _ ->
      -- Session termination is handled by the caller
      pure $ McpJsonResponse status200 (object ["terminated" .= True])

-- | Handle SSE stream for server-to-client notifications
handleMcpSse ::
  HttpTransportConfig ->
  HttpRequestContext ->
  Chan Value ->
  (Value -> IO ()) ->
  IO ()
handleMcpSse config ctx chan onMessage = do
  -- This runs in a streaming context
  -- The caller is responsible for setting up the SSE response
  let loop = do
        msg <- readChan chan
        onMessage msg
        loop
  loop

-- | Convert MCP response to WAI Response
responseToWai :: McpHttpResponse -> Maybe Text -> Response
responseToWai resp maybeSessionId =
  let sessionHeaders = case maybeSessionId of
        Just sid -> [(mcpSessionHeader, TE.encodeUtf8 sid)]
        Nothing -> []
   in case resp of
        McpJsonResponse status value ->
          responseLBS
            status
            ([(hContentType, "application/json")] ++ sessionHeaders)
            (encode value)
        McpErrorResponse status err ->
          let errorValue =
                object
                  [ "jsonrpc" .= ("2.0" :: Text),
                    "error" .= err,
                    "id" .= (Nothing :: Maybe Value)
                  ]
           in responseLBS
                status
                ([(hContentType, "application/json")] ++ sessionHeaders)
                (encode errorValue)
        McpSseResponse _ ->
          -- SSE responses: headers only; streaming body handled by WAI streaming
          responseLBS
            status200
            [ (hContentType, "text/event-stream"),
              ("Cache-Control", "no-cache"),
              ("Connection", "keep-alive")
            ]
            ""
