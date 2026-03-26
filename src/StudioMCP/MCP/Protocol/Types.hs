{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.MCP.Protocol.Types
  ( -- * Protocol Version
    ProtocolVersion (..),
    currentProtocolVersion,
    supportedVersions,

    -- * Capabilities
    ServerCapabilities (..),
    ClientCapabilities (..),
    ToolsCapability (..),
    ResourcesCapability (..),
    PromptsCapability (..),
    LoggingCapability (..),

    -- * Initialization
    InitializeParams (..),
    InitializeResult (..),
    ServerInfo (..),
    ClientInfo (..),

    -- * Tools
    ToolDefinition (..),
    ToolInputSchema (..),
    CallToolParams (..),
    CallToolResult (..),
    ToolContent (..),
    ContentType (..),

    -- * Resources
    ResourceDefinition (..),
    ReadResourceParams (..),
    ReadResourceResult (..),
    ResourceContent (..),

    -- * Prompts
    PromptDefinition (..),
    PromptArgument (..),
    GetPromptParams (..),
    GetPromptResult (..),
    PromptMessage (..),
    PromptRole (..),

    -- * Notifications
    ProgressToken (..),
    ProgressNotification (..),
    LogLevel (..),
    LogNotification (..),
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
import Data.Text (Text)
import GHC.Generics (Generic)

-- | MCP Protocol version
newtype ProtocolVersion = ProtocolVersion Text
  deriving (Eq, Show, Generic)

instance ToJSON ProtocolVersion where
  toJSON (ProtocolVersion v) = toJSON v

instance FromJSON ProtocolVersion where
  parseJSON = withText "ProtocolVersion" $ \v ->
    pure (ProtocolVersion v)

-- | Current protocol version supported by this server
currentProtocolVersion :: ProtocolVersion
currentProtocolVersion = ProtocolVersion "2024-11-05"

-- | All supported protocol versions
supportedVersions :: [ProtocolVersion]
supportedVersions = [ProtocolVersion "2024-11-05"]

-- | Server capabilities advertised during initialization
data ServerCapabilities = ServerCapabilities
  { scTools :: Maybe ToolsCapability,
    scResources :: Maybe ResourcesCapability,
    scPrompts :: Maybe PromptsCapability,
    scLogging :: Maybe LoggingCapability
  }
  deriving (Eq, Show, Generic)

instance ToJSON ServerCapabilities where
  toJSON caps =
    object $
      maybe [] (\t -> ["tools" .= t]) (scTools caps)
        ++ maybe [] (\r -> ["resources" .= r]) (scResources caps)
        ++ maybe [] (\p -> ["prompts" .= p]) (scPrompts caps)
        ++ maybe [] (\l -> ["logging" .= l]) (scLogging caps)

instance FromJSON ServerCapabilities where
  parseJSON = withObject "ServerCapabilities" $ \obj ->
    ServerCapabilities
      <$> obj .:? "tools"
      <*> obj .:? "resources"
      <*> obj .:? "prompts"
      <*> obj .:? "logging"

-- | Client capabilities sent during initialization
data ClientCapabilities = ClientCapabilities
  { ccRoots :: Maybe Value,
    ccSampling :: Maybe Value
  }
  deriving (Eq, Show, Generic)

instance ToJSON ClientCapabilities where
  toJSON caps =
    object $
      maybe [] (\r -> ["roots" .= r]) (ccRoots caps)
        ++ maybe [] (\s -> ["sampling" .= s]) (ccSampling caps)

instance FromJSON ClientCapabilities where
  parseJSON = withObject "ClientCapabilities" $ \obj ->
    ClientCapabilities
      <$> obj .:? "roots"
      <*> obj .:? "sampling"

-- | Tools capability with optional listChanged support
data ToolsCapability = ToolsCapability
  { tcListChanged :: Maybe Bool
  }
  deriving (Eq, Show, Generic)

instance ToJSON ToolsCapability where
  toJSON tc =
    object $ maybe [] (\lc -> ["listChanged" .= lc]) (tcListChanged tc)

instance FromJSON ToolsCapability where
  parseJSON = withObject "ToolsCapability" $ \obj ->
    ToolsCapability <$> obj .:? "listChanged"

-- | Resources capability with optional subscribe and listChanged
data ResourcesCapability = ResourcesCapability
  { rcSubscribe :: Maybe Bool,
    rcListChanged :: Maybe Bool
  }
  deriving (Eq, Show, Generic)

instance ToJSON ResourcesCapability where
  toJSON rc =
    object $
      maybe [] (\s -> ["subscribe" .= s]) (rcSubscribe rc)
        ++ maybe [] (\lc -> ["listChanged" .= lc]) (rcListChanged rc)

instance FromJSON ResourcesCapability where
  parseJSON = withObject "ResourcesCapability" $ \obj ->
    ResourcesCapability
      <$> obj .:? "subscribe"
      <*> obj .:? "listChanged"

-- | Prompts capability with optional listChanged
data PromptsCapability = PromptsCapability
  { pcListChanged :: Maybe Bool
  }
  deriving (Eq, Show, Generic)

instance ToJSON PromptsCapability where
  toJSON pc =
    object $ maybe [] (\lc -> ["listChanged" .= lc]) (pcListChanged pc)

instance FromJSON PromptsCapability where
  parseJSON = withObject "PromptsCapability" $ \obj ->
    PromptsCapability <$> obj .:? "listChanged"

-- | Logging capability
data LoggingCapability = LoggingCapability
  deriving (Eq, Show, Generic)

instance ToJSON LoggingCapability where
  toJSON _ = object []

instance FromJSON LoggingCapability where
  parseJSON = withObject "LoggingCapability" $ \_ ->
    pure LoggingCapability

-- | Server information
data ServerInfo = ServerInfo
  { siName :: Text,
    siVersion :: Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON ServerInfo where
  toJSON si =
    object
      [ "name" .= siName si,
        "version" .= siVersion si
      ]

instance FromJSON ServerInfo where
  parseJSON = withObject "ServerInfo" $ \obj ->
    ServerInfo
      <$> obj .: "name"
      <*> obj .: "version"

-- | Client information
data ClientInfo = ClientInfo
  { ciName :: Text,
    ciVersion :: Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON ClientInfo where
  toJSON ci =
    object
      [ "name" .= ciName ci,
        "version" .= ciVersion ci
      ]

instance FromJSON ClientInfo where
  parseJSON = withObject "ClientInfo" $ \obj ->
    ClientInfo
      <$> obj .: "name"
      <*> obj .: "version"

-- | Initialize request parameters
data InitializeParams = InitializeParams
  { ipProtocolVersion :: ProtocolVersion,
    ipCapabilities :: ClientCapabilities,
    ipClientInfo :: ClientInfo
  }
  deriving (Eq, Show, Generic)

instance ToJSON InitializeParams where
  toJSON ip =
    object
      [ "protocolVersion" .= ipProtocolVersion ip,
        "capabilities" .= ipCapabilities ip,
        "clientInfo" .= ipClientInfo ip
      ]

instance FromJSON InitializeParams where
  parseJSON = withObject "InitializeParams" $ \obj ->
    InitializeParams
      <$> obj .: "protocolVersion"
      <*> obj .: "capabilities"
      <*> obj .: "clientInfo"

-- | Initialize response result
data InitializeResult = InitializeResult
  { irProtocolVersion :: ProtocolVersion,
    irCapabilities :: ServerCapabilities,
    irServerInfo :: ServerInfo
  }
  deriving (Eq, Show, Generic)

instance ToJSON InitializeResult where
  toJSON ir =
    object
      [ "protocolVersion" .= irProtocolVersion ir,
        "capabilities" .= irCapabilities ir,
        "serverInfo" .= irServerInfo ir
      ]

instance FromJSON InitializeResult where
  parseJSON = withObject "InitializeResult" $ \obj ->
    InitializeResult
      <$> obj .: "protocolVersion"
      <*> obj .: "capabilities"
      <*> obj .: "serverInfo"

-- | Tool definition for tools/list response
data ToolDefinition = ToolDefinition
  { tdName :: Text,
    tdDescription :: Maybe Text,
    tdInputSchema :: ToolInputSchema
  }
  deriving (Eq, Show, Generic)

instance ToJSON ToolDefinition where
  toJSON td =
    object $
      [ "name" .= tdName td,
        "inputSchema" .= tdInputSchema td
      ]
        ++ maybe [] (\d -> ["description" .= d]) (tdDescription td)

instance FromJSON ToolDefinition where
  parseJSON = withObject "ToolDefinition" $ \obj ->
    ToolDefinition
      <$> obj .: "name"
      <*> obj .:? "description"
      <*> obj .: "inputSchema"

-- | JSON Schema for tool input
data ToolInputSchema = ToolInputSchema
  { tisType :: Text,
    tisProperties :: Maybe Value,
    tisRequired :: Maybe [Text]
  }
  deriving (Eq, Show, Generic)

instance ToJSON ToolInputSchema where
  toJSON tis =
    object $
      ["type" .= tisType tis]
        ++ maybe [] (\p -> ["properties" .= p]) (tisProperties tis)
        ++ maybe [] (\r -> ["required" .= r]) (tisRequired tis)

instance FromJSON ToolInputSchema where
  parseJSON = withObject "ToolInputSchema" $ \obj ->
    ToolInputSchema
      <$> obj .: "type"
      <*> obj .:? "properties"
      <*> obj .:? "required"

-- | Call tool request parameters
data CallToolParams = CallToolParams
  { ctpName :: Text,
    ctpArguments :: Maybe Value
  }
  deriving (Eq, Show, Generic)

instance ToJSON CallToolParams where
  toJSON ctp =
    object $
      ["name" .= ctpName ctp]
        ++ maybe [] (\a -> ["arguments" .= a]) (ctpArguments ctp)

instance FromJSON CallToolParams where
  parseJSON = withObject "CallToolParams" $ \obj ->
    CallToolParams
      <$> obj .: "name"
      <*> obj .:? "arguments"

-- | Content type for tool results
data ContentType = TextContent | ImageContent | EmbeddedResource
  deriving (Eq, Show, Generic)

instance ToJSON ContentType where
  toJSON TextContent = "text"
  toJSON ImageContent = "image"
  toJSON EmbeddedResource = "resource"

instance FromJSON ContentType where
  parseJSON = withText "ContentType" $ \case
    "text" -> pure TextContent
    "image" -> pure ImageContent
    "resource" -> pure EmbeddedResource
    other -> fail $ "Unknown content type: " <> show other

-- | Tool content item
data ToolContent = ToolContent
  { tcType :: ContentType,
    tcText :: Maybe Text,
    tcData :: Maybe Text,
    tcMimeType :: Maybe Text,
    tcUri :: Maybe Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON ToolContent where
  toJSON tc =
    object $
      ["type" .= tcType tc]
        ++ maybe [] (\t -> ["text" .= t]) (tcText tc)
        ++ maybe [] (\d -> ["data" .= d]) (tcData tc)
        ++ maybe [] (\m -> ["mimeType" .= m]) (tcMimeType tc)
        ++ maybe [] (\u -> ["uri" .= u]) (tcUri tc)

instance FromJSON ToolContent where
  parseJSON = withObject "ToolContent" $ \obj ->
    ToolContent
      <$> obj .: "type"
      <*> obj .:? "text"
      <*> obj .:? "data"
      <*> obj .:? "mimeType"
      <*> obj .:? "uri"

-- | Call tool result
data CallToolResult = CallToolResult
  { ctrContent :: [ToolContent],
    ctrIsError :: Maybe Bool
  }
  deriving (Eq, Show, Generic)

instance ToJSON CallToolResult where
  toJSON ctr =
    object $
      ["content" .= ctrContent ctr]
        ++ maybe [] (\e -> ["isError" .= e]) (ctrIsError ctr)

instance FromJSON CallToolResult where
  parseJSON = withObject "CallToolResult" $ \obj ->
    CallToolResult
      <$> obj .: "content"
      <*> obj .:? "isError"

-- | Resource definition
data ResourceDefinition = ResourceDefinition
  { rdUri :: Text,
    rdName :: Text,
    rdDescription :: Maybe Text,
    rdMimeType :: Maybe Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON ResourceDefinition where
  toJSON rd =
    object $
      [ "uri" .= rdUri rd,
        "name" .= rdName rd
      ]
        ++ maybe [] (\d -> ["description" .= d]) (rdDescription rd)
        ++ maybe [] (\m -> ["mimeType" .= m]) (rdMimeType rd)

instance FromJSON ResourceDefinition where
  parseJSON = withObject "ResourceDefinition" $ \obj ->
    ResourceDefinition
      <$> obj .: "uri"
      <*> obj .: "name"
      <*> obj .:? "description"
      <*> obj .:? "mimeType"

-- | Read resource request parameters
data ReadResourceParams = ReadResourceParams
  { rrpUri :: Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON ReadResourceParams where
  toJSON rrp = object ["uri" .= rrpUri rrp]

instance FromJSON ReadResourceParams where
  parseJSON = withObject "ReadResourceParams" $ \obj ->
    ReadResourceParams <$> obj .: "uri"

-- | Resource content
data ResourceContent = ResourceContent
  { rcUri :: Text,
    rcMimeType :: Maybe Text,
    rcText :: Maybe Text,
    rcBlob :: Maybe Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON ResourceContent where
  toJSON rc =
    object $
      ["uri" .= rcUri rc]
        ++ maybe [] (\m -> ["mimeType" .= m]) (rcMimeType rc)
        ++ maybe [] (\t -> ["text" .= t]) (rcText rc)
        ++ maybe [] (\b -> ["blob" .= b]) (rcBlob rc)

instance FromJSON ResourceContent where
  parseJSON = withObject "ResourceContent" $ \obj ->
    ResourceContent
      <$> obj .: "uri"
      <*> obj .:? "mimeType"
      <*> obj .:? "text"
      <*> obj .:? "blob"

-- | Read resource result
data ReadResourceResult = ReadResourceResult
  { rrrContents :: [ResourceContent]
  }
  deriving (Eq, Show, Generic)

instance ToJSON ReadResourceResult where
  toJSON rrr = object ["contents" .= rrrContents rrr]

instance FromJSON ReadResourceResult where
  parseJSON = withObject "ReadResourceResult" $ \obj ->
    ReadResourceResult <$> obj .: "contents"

-- | Prompt definition
data PromptDefinition = PromptDefinition
  { pdName :: Text,
    pdDescription :: Maybe Text,
    pdArguments :: Maybe [PromptArgument]
  }
  deriving (Eq, Show, Generic)

instance ToJSON PromptDefinition where
  toJSON pd =
    object $
      ["name" .= pdName pd]
        ++ maybe [] (\d -> ["description" .= d]) (pdDescription pd)
        ++ maybe [] (\a -> ["arguments" .= a]) (pdArguments pd)

instance FromJSON PromptDefinition where
  parseJSON = withObject "PromptDefinition" $ \obj ->
    PromptDefinition
      <$> obj .: "name"
      <*> obj .:? "description"
      <*> obj .:? "arguments"

-- | Prompt argument
data PromptArgument = PromptArgument
  { paName :: Text,
    paDescription :: Maybe Text,
    paRequired :: Maybe Bool
  }
  deriving (Eq, Show, Generic)

instance ToJSON PromptArgument where
  toJSON pa =
    object $
      ["name" .= paName pa]
        ++ maybe [] (\d -> ["description" .= d]) (paDescription pa)
        ++ maybe [] (\r -> ["required" .= r]) (paRequired pa)

instance FromJSON PromptArgument where
  parseJSON = withObject "PromptArgument" $ \obj ->
    PromptArgument
      <$> obj .: "name"
      <*> obj .:? "description"
      <*> obj .:? "required"

-- | Get prompt request parameters
data GetPromptParams = GetPromptParams
  { gppName :: Text,
    gppArguments :: Maybe Value
  }
  deriving (Eq, Show, Generic)

instance ToJSON GetPromptParams where
  toJSON gpp =
    object $
      ["name" .= gppName gpp]
        ++ maybe [] (\a -> ["arguments" .= a]) (gppArguments gpp)

instance FromJSON GetPromptParams where
  parseJSON = withObject "GetPromptParams" $ \obj ->
    GetPromptParams
      <$> obj .: "name"
      <*> obj .:? "arguments"

-- | Prompt role
data PromptRole = UserRole | AssistantRole
  deriving (Eq, Show, Generic)

instance ToJSON PromptRole where
  toJSON UserRole = "user"
  toJSON AssistantRole = "assistant"

instance FromJSON PromptRole where
  parseJSON = withText "PromptRole" $ \case
    "user" -> pure UserRole
    "assistant" -> pure AssistantRole
    other -> fail $ "Unknown role: " <> show other

-- | Prompt message
data PromptMessage = PromptMessage
  { pmRole :: PromptRole,
    pmContent :: ToolContent
  }
  deriving (Eq, Show, Generic)

instance ToJSON PromptMessage where
  toJSON pm =
    object
      [ "role" .= pmRole pm,
        "content" .= pmContent pm
      ]

instance FromJSON PromptMessage where
  parseJSON = withObject "PromptMessage" $ \obj ->
    PromptMessage
      <$> obj .: "role"
      <*> obj .: "content"

-- | Get prompt result
data GetPromptResult = GetPromptResult
  { gprDescription :: Maybe Text,
    gprMessages :: [PromptMessage]
  }
  deriving (Eq, Show, Generic)

instance ToJSON GetPromptResult where
  toJSON gpr =
    object $
      ["messages" .= gprMessages gpr]
        ++ maybe [] (\d -> ["description" .= d]) (gprDescription gpr)

instance FromJSON GetPromptResult where
  parseJSON = withObject "GetPromptResult" $ \obj ->
    GetPromptResult
      <$> obj .:? "description"
      <*> obj .: "messages"

-- | Progress token
data ProgressToken
  = ProgressTokenString Text
  | ProgressTokenNumber Integer
  deriving (Eq, Show, Generic)

instance ToJSON ProgressToken where
  toJSON (ProgressTokenString s) = toJSON s
  toJSON (ProgressTokenNumber n) = toJSON n

instance FromJSON ProgressToken where
  parseJSON (String s) = pure (ProgressTokenString s)
  parseJSON (Number n) = pure (ProgressTokenNumber (truncate n))
  parseJSON _ = fail "Progress token must be string or number"

-- | Progress notification
data ProgressNotification = ProgressNotification
  { pnProgressToken :: ProgressToken,
    pnProgress :: Double,
    pnTotal :: Maybe Double
  }
  deriving (Eq, Show, Generic)

instance ToJSON ProgressNotification where
  toJSON pn =
    object $
      [ "progressToken" .= pnProgressToken pn,
        "progress" .= pnProgress pn
      ]
        ++ maybe [] (\t -> ["total" .= t]) (pnTotal pn)

instance FromJSON ProgressNotification where
  parseJSON = withObject "ProgressNotification" $ \obj ->
    ProgressNotification
      <$> obj .: "progressToken"
      <*> obj .: "progress"
      <*> obj .:? "total"

-- | Log level
data LogLevel
  = LogDebug
  | LogInfo
  | LogNotice
  | LogWarning
  | LogError
  | LogCritical
  | LogAlert
  | LogEmergency
  deriving (Eq, Show, Generic, Ord)

instance ToJSON LogLevel where
  toJSON LogDebug = "debug"
  toJSON LogInfo = "info"
  toJSON LogNotice = "notice"
  toJSON LogWarning = "warning"
  toJSON LogError = "error"
  toJSON LogCritical = "critical"
  toJSON LogAlert = "alert"
  toJSON LogEmergency = "emergency"

instance FromJSON LogLevel where
  parseJSON = withText "LogLevel" $ \case
    "debug" -> pure LogDebug
    "info" -> pure LogInfo
    "notice" -> pure LogNotice
    "warning" -> pure LogWarning
    "error" -> pure LogError
    "critical" -> pure LogCritical
    "alert" -> pure LogAlert
    "emergency" -> pure LogEmergency
    other -> fail $ "Unknown log level: " <> show other

-- | Log notification
data LogNotification = LogNotification
  { lnLevel :: LogLevel,
    lnLogger :: Maybe Text,
    lnData :: Value
  }
  deriving (Eq, Show, Generic)

instance ToJSON LogNotification where
  toJSON ln =
    object $
      [ "level" .= lnLevel ln,
        "data" .= lnData ln
      ]
        ++ maybe [] (\l -> ["logger" .= l]) (lnLogger ln)

instance FromJSON LogNotification where
  parseJSON = withObject "LogNotification" $ \obj ->
    LogNotification
      <$> obj .: "level"
      <*> obj .:? "logger"
      <*> obj .: "data"
