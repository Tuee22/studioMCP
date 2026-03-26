{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.MCP.JsonRpc
  ( -- * JSON-RPC 2.0 Types
    JsonRpcVersion (..),
    RequestId (..),
    JsonRpcRequest (..),
    JsonRpcResponse (..),
    JsonRpcError (..),
    JsonRpcErrorCode (..),
    JsonRpcNotification (..),
    JsonRpcMessage (..),

    -- * Error Code Constructors
    parseError,
    invalidRequest,
    methodNotFound,
    invalidParams,
    internalError,
    serverNotInitialized,
    unsupportedProtocolVersion,
    capabilityNotSupported,

    -- * Domain Error Codes
    authRequired,
    authDenied,
    tenantNotFound,
    dagValidationFailed,
    executionFailed,
    resourceNotFound,
    artifactAccessDenied,
    quotaExceeded,

    -- * Utilities
    isNotification,
    makeResponse,
    makeErrorResponse,
  )
where

import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    Value (..),
    object,
    withObject,
    withText,
    (.:),
    (.:?),
    (.=),
  )
import Data.Aeson.Types (Parser)
import Data.Text (Text)

-- | JSON-RPC version string (always "2.0")
newtype JsonRpcVersion = JsonRpcVersion Text
  deriving (Eq, Show)

instance ToJSON JsonRpcVersion where
  toJSON (JsonRpcVersion v) = toJSON v

instance FromJSON JsonRpcVersion where
  parseJSON = withText "JsonRpcVersion" $ \v ->
    if v == "2.0"
      then pure (JsonRpcVersion v)
      else fail "JSON-RPC version must be \"2.0\""

-- | Request ID (string or number)
data RequestId
  = RequestIdString Text
  | RequestIdNumber Integer
  deriving (Eq, Show)

instance ToJSON RequestId where
  toJSON (RequestIdString s) = toJSON s
  toJSON (RequestIdNumber n) = toJSON n

instance FromJSON RequestId where
  parseJSON (String s) = pure (RequestIdString s)
  parseJSON (Number n) = pure (RequestIdNumber (truncate n))
  parseJSON _ = fail "Request ID must be string or number"

-- | JSON-RPC 2.0 Request
data JsonRpcRequest = JsonRpcRequest
  { reqJsonRpc :: JsonRpcVersion,
    reqId :: RequestId,
    reqMethod :: Text,
    reqParams :: Maybe Value
  }
  deriving (Eq, Show)

instance ToJSON JsonRpcRequest where
  toJSON req =
    object $
      [ "jsonrpc" .= reqJsonRpc req,
        "id" .= reqId req,
        "method" .= reqMethod req
      ]
        ++ maybe [] (\p -> ["params" .= p]) (reqParams req)

instance FromJSON JsonRpcRequest where
  parseJSON = withObject "JsonRpcRequest" $ \obj ->
    JsonRpcRequest
      <$> obj .: "jsonrpc"
      <*> obj .: "id"
      <*> obj .: "method"
      <*> obj .:? "params"

-- | JSON-RPC 2.0 Notification (request without id)
data JsonRpcNotification = JsonRpcNotification
  { notifJsonRpc :: JsonRpcVersion,
    notifMethod :: Text,
    notifParams :: Maybe Value
  }
  deriving (Eq, Show)

instance ToJSON JsonRpcNotification where
  toJSON notif =
    object $
      [ "jsonrpc" .= notifJsonRpc notif,
        "method" .= notifMethod notif
      ]
        ++ maybe [] (\p -> ["params" .= p]) (notifParams notif)

instance FromJSON JsonRpcNotification where
  parseJSON = withObject "JsonRpcNotification" $ \obj ->
    JsonRpcNotification
      <$> obj .: "jsonrpc"
      <*> obj .: "method"
      <*> obj .:? "params"

-- | JSON-RPC 2.0 Error Codes
data JsonRpcErrorCode
  = -- Standard JSON-RPC errors
    ParseError -- -32700
  | InvalidRequest -- -32600
  | MethodNotFound -- -32601
  | InvalidParams -- -32602
  | InternalError -- -32603
  | -- MCP Protocol errors (-32000 to -32099)
    ServerNotInitialized -- -32002
  | UnsupportedProtocolVersion -- -32003
  | CapabilityNotSupported -- -32004
  | -- Domain errors (-31000 to -31999)
    AuthRequired -- -31001
  | AuthDenied -- -31002
  | TenantNotFound -- -31003
  | DagValidationFailed -- -31004
  | ExecutionFailed -- -31005
  | ResourceNotFound -- -31006
  | ArtifactAccessDenied -- -31007
  | QuotaExceeded -- -31008
  | -- Custom server error
    ServerError Int
  deriving (Eq, Show)

errorCodeToInt :: JsonRpcErrorCode -> Int
errorCodeToInt ParseError = -32700
errorCodeToInt InvalidRequest = -32600
errorCodeToInt MethodNotFound = -32601
errorCodeToInt InvalidParams = -32602
errorCodeToInt InternalError = -32603
errorCodeToInt ServerNotInitialized = -32002
errorCodeToInt UnsupportedProtocolVersion = -32003
errorCodeToInt CapabilityNotSupported = -32004
errorCodeToInt AuthRequired = -31001
errorCodeToInt AuthDenied = -31002
errorCodeToInt TenantNotFound = -31003
errorCodeToInt DagValidationFailed = -31004
errorCodeToInt ExecutionFailed = -31005
errorCodeToInt ResourceNotFound = -31006
errorCodeToInt ArtifactAccessDenied = -31007
errorCodeToInt QuotaExceeded = -31008
errorCodeToInt (ServerError n) = n

intToErrorCode :: Int -> JsonRpcErrorCode
intToErrorCode (-32700) = ParseError
intToErrorCode (-32600) = InvalidRequest
intToErrorCode (-32601) = MethodNotFound
intToErrorCode (-32602) = InvalidParams
intToErrorCode (-32603) = InternalError
intToErrorCode (-32002) = ServerNotInitialized
intToErrorCode (-32003) = UnsupportedProtocolVersion
intToErrorCode (-32004) = CapabilityNotSupported
intToErrorCode (-31001) = AuthRequired
intToErrorCode (-31002) = AuthDenied
intToErrorCode (-31003) = TenantNotFound
intToErrorCode (-31004) = DagValidationFailed
intToErrorCode (-31005) = ExecutionFailed
intToErrorCode (-31006) = ResourceNotFound
intToErrorCode (-31007) = ArtifactAccessDenied
intToErrorCode (-31008) = QuotaExceeded
intToErrorCode n = ServerError n

instance ToJSON JsonRpcErrorCode where
  toJSON = toJSON . errorCodeToInt

instance FromJSON JsonRpcErrorCode where
  parseJSON v = intToErrorCode <$> parseJSON v

-- | JSON-RPC 2.0 Error
data JsonRpcError = JsonRpcError
  { errCode :: JsonRpcErrorCode,
    errMessage :: Text,
    errData :: Maybe Value
  }
  deriving (Eq, Show)

instance ToJSON JsonRpcError where
  toJSON err =
    object $
      [ "code" .= errCode err,
        "message" .= errMessage err
      ]
        ++ maybe [] (\d -> ["data" .= d]) (errData err)

instance FromJSON JsonRpcError where
  parseJSON = withObject "JsonRpcError" $ \obj ->
    JsonRpcError
      <$> obj .: "code"
      <*> obj .: "message"
      <*> obj .:? "data"

-- | JSON-RPC 2.0 Response
data JsonRpcResponse = JsonRpcResponse
  { respJsonRpc :: JsonRpcVersion,
    respId :: RequestId,
    respResult :: Maybe Value,
    respError :: Maybe JsonRpcError
  }
  deriving (Eq, Show)

instance ToJSON JsonRpcResponse where
  toJSON resp =
    object $
      ["jsonrpc" .= respJsonRpc resp, "id" .= respId resp]
        ++ case (respResult resp, respError resp) of
          (Just r, Nothing) -> ["result" .= r]
          (Nothing, Just e) -> ["error" .= e]
          _ -> []

instance FromJSON JsonRpcResponse where
  parseJSON = withObject "JsonRpcResponse" $ \obj ->
    JsonRpcResponse
      <$> obj .: "jsonrpc"
      <*> obj .: "id"
      <*> obj .:? "result"
      <*> obj .:? "error"

-- | Combined message type for parsing incoming messages
data JsonRpcMessage
  = MsgRequest JsonRpcRequest
  | MsgNotification JsonRpcNotification
  | MsgResponse JsonRpcResponse
  deriving (Eq, Show)

instance FromJSON JsonRpcMessage where
  parseJSON v = withObject "JsonRpcMessage" parseMessage v
    where
      parseMessage obj = do
        maybeId <- obj .:? "id" :: Parser (Maybe RequestId)
        maybeResult <- obj .:? "result" :: Parser (Maybe Value)
        maybeError <- obj .:? "error" :: Parser (Maybe JsonRpcError)

        case (maybeId, maybeResult, maybeError) of
          (Just _, Just _, _) -> MsgResponse <$> parseJSON v
          (Just _, _, Just _) -> MsgResponse <$> parseJSON v
          (Just _, Nothing, Nothing) -> MsgRequest <$> parseJSON v
          (Nothing, _, _) -> MsgNotification <$> parseJSON v

instance ToJSON JsonRpcMessage where
  toJSON (MsgRequest r) = toJSON r
  toJSON (MsgNotification n) = toJSON n
  toJSON (MsgResponse r) = toJSON r

-- | Check if a message is a notification
isNotification :: JsonRpcMessage -> Bool
isNotification (MsgNotification _) = True
isNotification _ = False

-- | Create a success response
makeResponse :: RequestId -> Value -> JsonRpcResponse
makeResponse reqId result =
  JsonRpcResponse
    { respJsonRpc = JsonRpcVersion "2.0",
      respId = reqId,
      respResult = Just result,
      respError = Nothing
    }

-- | Create an error response
makeErrorResponse :: RequestId -> JsonRpcError -> JsonRpcResponse
makeErrorResponse reqId err =
  JsonRpcResponse
    { respJsonRpc = JsonRpcVersion "2.0",
      respId = reqId,
      respResult = Nothing,
      respError = Just err
    }

-- Error constructors
parseError :: Text -> JsonRpcError
parseError msg = JsonRpcError ParseError msg Nothing

invalidRequest :: Text -> JsonRpcError
invalidRequest msg = JsonRpcError InvalidRequest msg Nothing

methodNotFound :: Text -> JsonRpcError
methodNotFound msg = JsonRpcError MethodNotFound msg Nothing

invalidParams :: Text -> JsonRpcError
invalidParams msg = JsonRpcError InvalidParams msg Nothing

internalError :: Text -> JsonRpcError
internalError msg = JsonRpcError InternalError msg Nothing

serverNotInitialized :: JsonRpcError
serverNotInitialized = JsonRpcError ServerNotInitialized "Server not initialized" Nothing

unsupportedProtocolVersion :: Text -> JsonRpcError
unsupportedProtocolVersion version =
  JsonRpcError UnsupportedProtocolVersion ("Unsupported protocol version: " <> version) Nothing

capabilityNotSupported :: Text -> JsonRpcError
capabilityNotSupported cap =
  JsonRpcError CapabilityNotSupported ("Capability not supported: " <> cap) Nothing

-- Domain error constructors
authRequired :: JsonRpcError
authRequired = JsonRpcError AuthRequired "Authentication required" Nothing

authDenied :: Text -> JsonRpcError
authDenied msg = JsonRpcError AuthDenied msg Nothing

tenantNotFound :: Text -> JsonRpcError
tenantNotFound tenantId =
  JsonRpcError TenantNotFound ("Tenant not found: " <> tenantId) Nothing

dagValidationFailed :: Value -> JsonRpcError
dagValidationFailed details =
  JsonRpcError DagValidationFailed "DAG validation failed" (Just details)

executionFailed :: Text -> JsonRpcError
executionFailed msg = JsonRpcError ExecutionFailed msg Nothing

resourceNotFound :: Text -> JsonRpcError
resourceNotFound uri =
  JsonRpcError ResourceNotFound ("Resource not found: " <> uri) Nothing

artifactAccessDenied :: Text -> JsonRpcError
artifactAccessDenied artifactId =
  JsonRpcError ArtifactAccessDenied ("Artifact access denied: " <> artifactId) Nothing

quotaExceeded :: Text -> JsonRpcError
quotaExceeded msg = JsonRpcError QuotaExceeded msg Nothing
