{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Web.Types
  ( -- * Upload Types
    UploadRequest (..),
    UploadResponse (..),
    PresignedUploadUrl (..),

    -- * Download Types
    DownloadRequest (..),
    DownloadResponse (..),
    PresignedDownloadUrl (..),

    -- * Chat Types
    ChatRequest (..),
    ChatResponse (..),
    ChatMessage (..),
    ChatRole (..),

    -- * Session Types
    WebSession (..),
    WebSessionId (..),
    newWebSessionId,

    -- * Run Types
    RunSubmitRequest (..),
    RunStatusResponse (..),
    RunProgressEvent (..),

    -- * Session Auth Types
    SessionSummary (..),
    sessionSummaryFromWebSession,
    SessionLoginRequest (..),
    SessionLoginResponse (..),
    SessionMeResponse (..),
    SessionLogoutResponse (..),
    SessionRefreshResponse (..),
  )
where

import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    object,
    withObject,
    withText,
    (.:),
    (.!=),
    (.:?),
    (.=),
  )
import Data.Text (Text)
import Data.Time (UTCTime)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import GHC.Generics (Generic)
import StudioMCP.DAG.Summary (RunId (..))
import StudioMCP.DAG.Types (DagSpec)

-- | Web session identifier
newtype WebSessionId = WebSessionId Text
  deriving (Eq, Show, Ord, Generic)

instance ToJSON WebSessionId where
  toJSON (WebSessionId s) = toJSON s

instance FromJSON WebSessionId where
  parseJSON v = WebSessionId <$> parseJSON v

-- | Generate a new web session ID
newWebSessionId :: IO WebSessionId
newWebSessionId = do
  uuid <- UUID.nextRandom
  pure $ WebSessionId $ "web-" <> UUID.toText uuid

-- | Web session state (stored in BFF session store)
data WebSession = WebSession
  { wsSessionId :: WebSessionId,
    wsSubjectId :: Text,
    wsTenantId :: Text,
    wsAccessToken :: Text,
    wsRefreshToken :: Maybe Text,
    wsExpiresAt :: UTCTime,
    wsCreatedAt :: UTCTime,
    wsLastActiveAt :: UTCTime
  }
  deriving (Eq, Show, Generic)

instance ToJSON WebSession where
  toJSON ws =
    object
      [ "sessionId" .= wsSessionId ws,
        "subjectId" .= wsSubjectId ws,
        "tenantId" .= wsTenantId ws,
        "expiresAt" .= wsExpiresAt ws,
        "createdAt" .= wsCreatedAt ws,
        "lastActiveAt" .= wsLastActiveAt ws
        -- Note: tokens intentionally not serialized to client
      ]

instance FromJSON WebSession where
  parseJSON = withObject "WebSession" $ \obj ->
    WebSession
      <$> obj .: "sessionId"
      <*> obj .: "subjectId"
      <*> obj .: "tenantId"
      <*> obj .:? "accessToken" .!= ""
      <*> obj .:? "refreshToken"
      <*> obj .: "expiresAt"
      <*> obj .: "createdAt"
      <*> obj .: "lastActiveAt"

data SessionSummary = SessionSummary
  { ssSubjectId :: Text,
    ssTenantId :: Text,
    ssExpiresAt :: UTCTime,
    ssCreatedAt :: UTCTime,
    ssLastActiveAt :: UTCTime
  }
  deriving (Eq, Show, Generic)

sessionSummaryFromWebSession :: WebSession -> SessionSummary
sessionSummaryFromWebSession session =
  SessionSummary
    { ssSubjectId = wsSubjectId session,
      ssTenantId = wsTenantId session,
      ssExpiresAt = wsExpiresAt session,
      ssCreatedAt = wsCreatedAt session,
      ssLastActiveAt = wsLastActiveAt session
    }

instance ToJSON SessionSummary where
  toJSON summary =
    object
      [ "subjectId" .= ssSubjectId summary,
        "tenantId" .= ssTenantId summary,
        "expiresAt" .= ssExpiresAt summary,
        "createdAt" .= ssCreatedAt summary,
        "lastActiveAt" .= ssLastActiveAt summary
      ]

instance FromJSON SessionSummary where
  parseJSON = withObject "SessionSummary" $ \obj ->
    SessionSummary
      <$> obj .: "subjectId"
      <*> obj .: "tenantId"
      <*> obj .: "expiresAt"
      <*> obj .: "createdAt"
      <*> obj .: "lastActiveAt"

-- | Request to upload a file
data UploadRequest = UploadRequest
  { urFileName :: Text,
    urContentType :: Text,
    urFileSize :: Integer,
    urMetadata :: Maybe [(Text, Text)]
  }
  deriving (Eq, Show, Generic)

instance ToJSON UploadRequest where
  toJSON ur =
    object
      [ "fileName" .= urFileName ur,
        "contentType" .= urContentType ur,
        "fileSize" .= urFileSize ur,
        "metadata" .= urMetadata ur
      ]

instance FromJSON UploadRequest where
  parseJSON = withObject "UploadRequest" $ \obj ->
    UploadRequest
      <$> obj .: "fileName"
      <*> obj .: "contentType"
      <*> obj .: "fileSize"
      <*> obj .:? "metadata"

-- | Presigned URL for uploading
data PresignedUploadUrl = PresignedUploadUrl
  { puuUrl :: Text,
    puuMethod :: Text,
    puuHeaders :: [(Text, Text)],
    puuExpiresAt :: UTCTime,
    puuArtifactId :: Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON PresignedUploadUrl where
  toJSON p =
    object
      [ "url" .= puuUrl p,
        "method" .= puuMethod p,
        "headers" .= puuHeaders p,
        "expiresAt" .= puuExpiresAt p,
        "artifactId" .= puuArtifactId p
      ]

instance FromJSON PresignedUploadUrl where
  parseJSON = withObject "PresignedUploadUrl" $ \obj ->
    PresignedUploadUrl
      <$> obj .: "url"
      <*> obj .: "method"
      <*> obj .: "headers"
      <*> obj .: "expiresAt"
      <*> obj .: "artifactId"

-- | Response to upload request
data UploadResponse = UploadResponse
  { urpPresignedUrl :: PresignedUploadUrl,
    urpArtifactId :: Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON UploadResponse where
  toJSON ur =
    object
      [ "presignedUrl" .= urpPresignedUrl ur,
        "artifactId" .= urpArtifactId ur
      ]

instance FromJSON UploadResponse where
  parseJSON = withObject "UploadResponse" $ \obj ->
    UploadResponse
      <$> obj .: "presignedUrl"
      <*> obj .: "artifactId"

-- | Request to download a file
data DownloadRequest = DownloadRequest
  { drArtifactId :: Text,
    drVersion :: Maybe Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON DownloadRequest where
  toJSON dr =
    object
      [ "artifactId" .= drArtifactId dr,
        "version" .= drVersion dr
      ]

instance FromJSON DownloadRequest where
  parseJSON = withObject "DownloadRequest" $ \obj ->
    DownloadRequest
      <$> obj .: "artifactId"
      <*> obj .:? "version"

-- | Presigned URL for downloading
data PresignedDownloadUrl = PresignedDownloadUrl
  { pduUrl :: Text,
    pduExpiresAt :: UTCTime,
    pduContentType :: Text,
    pduFileSize :: Integer
  }
  deriving (Eq, Show, Generic)

instance ToJSON PresignedDownloadUrl where
  toJSON p =
    object
      [ "url" .= pduUrl p,
        "expiresAt" .= pduExpiresAt p,
        "contentType" .= pduContentType p,
        "fileSize" .= pduFileSize p
      ]

instance FromJSON PresignedDownloadUrl where
  parseJSON = withObject "PresignedDownloadUrl" $ \obj ->
    PresignedDownloadUrl
      <$> obj .: "url"
      <*> obj .: "expiresAt"
      <*> obj .: "contentType"
      <*> obj .: "fileSize"

-- | Response to download request
data DownloadResponse = DownloadResponse
  { drpPresignedUrl :: PresignedDownloadUrl,
    drpArtifactId :: Text,
    drpFileName :: Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON DownloadResponse where
  toJSON dr =
    object
      [ "presignedUrl" .= drpPresignedUrl dr,
        "artifactId" .= drpArtifactId dr,
        "fileName" .= drpFileName dr
      ]

instance FromJSON DownloadResponse where
  parseJSON = withObject "DownloadResponse" $ \obj ->
    DownloadResponse
      <$> obj .: "presignedUrl"
      <*> obj .: "artifactId"
      <*> obj .: "fileName"

-- | Chat role
data ChatRole
  = ChatUser
  | ChatAssistant
  | ChatSystem
  deriving (Eq, Show, Generic, Ord)

instance ToJSON ChatRole where
  toJSON ChatUser = "user"
  toJSON ChatAssistant = "assistant"
  toJSON ChatSystem = "system"

instance FromJSON ChatRole where
  parseJSON = withText "ChatRole" $ \t ->
    case t of
      "user" -> pure ChatUser
      "assistant" -> pure ChatAssistant
      "system" -> pure ChatSystem
      _ -> fail "Unknown chat role"

-- | Chat message
data ChatMessage = ChatMessage
  { cmRole :: ChatRole,
    cmContent :: Text,
    cmTimestamp :: Maybe UTCTime
  }
  deriving (Eq, Show, Generic)

instance ToJSON ChatMessage where
  toJSON cm =
    object
      [ "role" .= cmRole cm,
        "content" .= cmContent cm,
        "timestamp" .= cmTimestamp cm
      ]

instance FromJSON ChatMessage where
  parseJSON = withObject "ChatMessage" $ \obj ->
    ChatMessage
      <$> obj .: "role"
      <*> obj .: "content"
      <*> obj .:? "timestamp"

-- | Chat request
data ChatRequest = ChatRequest
  { crMessages :: [ChatMessage],
    crContext :: Maybe Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON ChatRequest where
  toJSON cr =
    object
      [ "messages" .= crMessages cr,
        "context" .= crContext cr
      ]

instance FromJSON ChatRequest where
  parseJSON = withObject "ChatRequest" $ \obj ->
    ChatRequest
      <$> obj .: "messages"
      <*> obj .:? "context"

-- | Chat response
data ChatResponse = ChatResponse
  { crpMessage :: ChatMessage,
    crpConversationId :: Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON ChatResponse where
  toJSON cr =
    object
      [ "message" .= crpMessage cr,
        "conversationId" .= crpConversationId cr
      ]

instance FromJSON ChatResponse where
  parseJSON = withObject "ChatResponse" $ \obj ->
    ChatResponse
      <$> obj .: "message"
      <*> obj .: "conversationId"

-- | Run submission request
data RunSubmitRequest = RunSubmitRequest
  { rsrDagSpec :: DagSpec,
    rsrInputArtifacts :: [(Text, Text)]
  }
  deriving (Eq, Show, Generic)

instance ToJSON RunSubmitRequest where
  toJSON rsr =
    object
      [ "dagSpec" .= rsrDagSpec rsr,
        "inputArtifacts" .= rsrInputArtifacts rsr
      ]

instance FromJSON RunSubmitRequest where
  parseJSON = withObject "RunSubmitRequest" $ \obj ->
    RunSubmitRequest
      <$> obj .: "dagSpec"
      <*> obj .: "inputArtifacts"

-- | Run status response
data RunStatusResponse = RunStatusResponse
  { rsrRunId :: RunId,
    rsrStatus :: Text,
    rsrProgress :: Maybe Int,
    rsrStartedAt :: Maybe UTCTime,
    rsrCompletedAt :: Maybe UTCTime
  }
  deriving (Eq, Show, Generic)

instance ToJSON RunStatusResponse where
  toJSON rsr =
    object
      [ "runId" .= rsrRunId rsr,
        "status" .= rsrStatus rsr,
        "progress" .= rsrProgress rsr,
        "startedAt" .= rsrStartedAt rsr,
        "completedAt" .= rsrCompletedAt rsr
      ]

instance FromJSON RunStatusResponse where
  parseJSON = withObject "RunStatusResponse" $ \obj ->
    RunStatusResponse
      <$> obj .: "runId"
      <*> obj .: "status"
      <*> obj .:? "progress"
      <*> obj .:? "startedAt"
      <*> obj .:? "completedAt"

-- | Run progress event (for SSE/WebSocket updates)
data RunProgressEvent = RunProgressEvent
  { rpeRunId :: RunId,
    rpeNodeId :: Maybe Text,
    rpeEventType :: Text,
    rpeMessage :: Text,
    rpeProgress :: Maybe Int,
    rpeTimestamp :: UTCTime
  }
  deriving (Eq, Show, Generic)

instance ToJSON RunProgressEvent where
  toJSON rpe =
    object
      [ "runId" .= rpeRunId rpe,
        "nodeId" .= rpeNodeId rpe,
        "eventType" .= rpeEventType rpe,
        "message" .= rpeMessage rpe,
        "progress" .= rpeProgress rpe,
        "timestamp" .= rpeTimestamp rpe
      ]

instance FromJSON RunProgressEvent where
  parseJSON = withObject "RunProgressEvent" $ \obj ->
    RunProgressEvent
      <$> obj .: "runId"
      <*> obj .:? "nodeId"
      <*> obj .: "eventType"
      <*> obj .: "message"
      <*> obj .:? "progress"
      <*> obj .: "timestamp"

-- | Username/password login request handled by the BFF.
data SessionLoginRequest = SessionLoginRequest
  { slrUsername :: Text,
    slrPassword :: Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON SessionLoginRequest where
  toJSON req =
    object
      [ "username" .= slrUsername req,
        "password" .= slrPassword req
      ]

instance FromJSON SessionLoginRequest where
  parseJSON = withObject "SessionLoginRequest" $ \obj ->
    SessionLoginRequest
      <$> obj .: "username"
      <*> obj .: "password"

-- | Response returned after a successful login.
data SessionLoginResponse = SessionLoginResponse
  { slresSession :: SessionSummary
  }
  deriving (Eq, Show, Generic)

instance ToJSON SessionLoginResponse where
  toJSON response =
    object
      [ "session" .= slresSession response
      ]

instance FromJSON SessionLoginResponse where
  parseJSON = withObject "SessionLoginResponse" $ \obj ->
    SessionLoginResponse
      <$> obj .: "session"

data SessionMeResponse = SessionMeResponse
  { smerSession :: SessionSummary
  }
  deriving (Eq, Show, Generic)

instance ToJSON SessionMeResponse where
  toJSON response =
    object
      [ "session" .= smerSession response
      ]

instance FromJSON SessionMeResponse where
  parseJSON = withObject "SessionMeResponse" $ \obj ->
    SessionMeResponse
      <$> obj .: "session"

-- | Response returned after a successful logout.
data SessionLogoutResponse = SessionLogoutResponse
  { slorsSuccess :: Bool
  }
  deriving (Eq, Show, Generic)

instance ToJSON SessionLogoutResponse where
  toJSON response =
    object
      [ "success" .= slorsSuccess response
      ]

instance FromJSON SessionLogoutResponse where
  parseJSON = withObject "SessionLogoutResponse" $ \obj ->
    SessionLogoutResponse
      <$> obj .: "success"

-- | Response returned after a successful refresh.
data SessionRefreshResponse = SessionRefreshResponse
  { srrSession :: SessionSummary,
    srrSuccess :: Bool
  }
  deriving (Eq, Show, Generic)

instance ToJSON SessionRefreshResponse where
  toJSON response =
    object
      [ "session" .= srrSession response,
        "success" .= srrSuccess response
      ]

instance FromJSON SessionRefreshResponse where
  parseJSON = withObject "SessionRefreshResponse" $ \obj ->
    SessionRefreshResponse
      <$> obj .: "session"
      <*> obj .: "success"
