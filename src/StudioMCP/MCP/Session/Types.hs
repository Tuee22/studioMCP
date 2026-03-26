{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.MCP.Session.Types
  ( -- * Session Types
    SessionId (..),
    Session (..),
    SessionState (..),

    -- * Negotiated Capabilities
    NegotiatedCapabilities (..),

    -- * Subject and Tenant Context (Phase 14: OAuth-Protected Multi-Tenant Auth)
    SubjectContext (..),
    TenantContext (..),
    TenantId (..),

    -- * Session Creation
    newSession,
    newSessionId,

    -- * Session Queries
    isSessionReady,
    sessionAge,

    -- * Serialization for Redis (Phase 15)
    SessionData (..),
    toSessionData,
    fromSessionData,
  )
where

import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    object,
    withObject,
    (.:),
    (.:?),
    (.=),
  )
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (NominalDiffTime, UTCTime, diffUTCTime, getCurrentTime)
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import GHC.Generics (Generic)
import StudioMCP.MCP.Protocol.StateMachine (ProtocolState (..))
import StudioMCP.MCP.Protocol.Types (ClientCapabilities, ClientInfo, ServerCapabilities)

-- | Unique session identifier
newtype SessionId = SessionId Text
  deriving (Eq, Show, Ord, Generic)

instance ToJSON SessionId where
  toJSON (SessionId s) = toJSON s

instance FromJSON SessionId where
  parseJSON v = SessionId <$> parseJSON v

-- | Generate a new random session ID
newSessionId :: IO SessionId
newSessionId = do
  uuid <- UUID.nextRandom
  pure $ SessionId $ UUID.toText uuid

-- | Tenant identifier (Phase 14)
newtype TenantId = TenantId Text
  deriving (Eq, Show, Ord, Generic)

instance ToJSON TenantId where
  toJSON (TenantId t) = toJSON t

instance FromJSON TenantId where
  parseJSON v = TenantId <$> parseJSON v

-- | Subject context - represents the authenticated user (Phase 14)
data SubjectContext = SubjectContext
  { scSubjectId :: Text,
    scEmail :: Maybe Text,
    scScopes :: [Text]
  }
  deriving (Eq, Show, Generic)

instance ToJSON SubjectContext where
  toJSON sc =
    object
      [ "subjectId" .= scSubjectId sc,
        "email" .= scEmail sc,
        "scopes" .= scScopes sc
      ]

instance FromJSON SubjectContext where
  parseJSON = withObject "SubjectContext" $ \obj ->
    SubjectContext
      <$> obj .: "subjectId"
      <*> obj .:? "email"
      <*> obj .: "scopes"

-- | Tenant context - represents the tenant scope (Phase 14)
data TenantContext = TenantContext
  { tcTenantId :: TenantId,
    tcTenantName :: Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON TenantContext where
  toJSON tc =
    object
      [ "tenantId" .= tcTenantId tc,
        "tenantName" .= tcTenantName tc
      ]

instance FromJSON TenantContext where
  parseJSON = withObject "TenantContext" $ \obj ->
    TenantContext
      <$> obj .: "tenantId"
      <*> obj .: "tenantName"

-- | Negotiated capabilities after initialization
data NegotiatedCapabilities = NegotiatedCapabilities
  { ncServerCapabilities :: ServerCapabilities,
    ncClientCapabilities :: ClientCapabilities,
    ncClientInfo :: ClientInfo
  }
  deriving (Eq, Show, Generic)

instance ToJSON NegotiatedCapabilities where
  toJSON nc =
    object
      [ "serverCapabilities" .= ncServerCapabilities nc,
        "clientCapabilities" .= ncClientCapabilities nc,
        "clientInfo" .= ncClientInfo nc
      ]

instance FromJSON NegotiatedCapabilities where
  parseJSON = withObject "NegotiatedCapabilities" $ \obj ->
    NegotiatedCapabilities
      <$> obj .: "serverCapabilities"
      <*> obj .: "clientCapabilities"
      <*> obj .: "clientInfo"

-- | Session state enumeration
data SessionState
  = SessionCreated
  | SessionInitializing
  | SessionReady
  | SessionClosing
  | SessionClosed
  deriving (Eq, Show, Generic, Ord)

instance ToJSON SessionState where
  toJSON SessionCreated = "created"
  toJSON SessionInitializing = "initializing"
  toJSON SessionReady = "ready"
  toJSON SessionClosing = "closing"
  toJSON SessionClosed = "closed"

instance FromJSON SessionState where
  parseJSON v = do
    t <- parseJSON v
    case t :: Text of
      "created" -> pure SessionCreated
      "initializing" -> pure SessionInitializing
      "ready" -> pure SessionReady
      "closing" -> pure SessionClosing
      "closed" -> pure SessionClosed
      _ -> fail "Unknown session state"

-- | MCP Session
data Session = Session
  { sessionId :: SessionId,
    sessionState :: SessionState,
    sessionCapabilities :: Maybe NegotiatedCapabilities,
    sessionSubject :: Maybe SubjectContext, -- Populated in Phase 14
    sessionTenant :: Maybe TenantContext, -- Populated in Phase 14
    sessionCreatedAt :: UTCTime,
    sessionLastActiveAt :: UTCTime
  }
  deriving (Eq, Show, Generic)

instance ToJSON Session where
  toJSON s =
    object
      [ "sessionId" .= sessionId s,
        "sessionState" .= sessionState s,
        "sessionCapabilities" .= sessionCapabilities s,
        "sessionSubject" .= sessionSubject s,
        "sessionTenant" .= sessionTenant s,
        "sessionCreatedAt" .= sessionCreatedAt s,
        "sessionLastActiveAt" .= sessionLastActiveAt s
      ]

instance FromJSON Session where
  parseJSON = withObject "Session" $ \obj ->
    Session
      <$> obj .: "sessionId"
      <*> obj .: "sessionState"
      <*> obj .:? "sessionCapabilities"
      <*> obj .:? "sessionSubject"
      <*> obj .:? "sessionTenant"
      <*> obj .: "sessionCreatedAt"
      <*> obj .: "sessionLastActiveAt"

-- | Create a new session
newSession :: IO Session
newSession = do
  sid <- newSessionId
  now <- getCurrentTime
  pure
    Session
      { sessionId = sid,
        sessionState = SessionCreated,
        sessionCapabilities = Nothing,
        sessionSubject = Nothing,
        sessionTenant = Nothing,
        sessionCreatedAt = now,
        sessionLastActiveAt = now
      }

-- | Check if session is in ready state
isSessionReady :: Session -> Bool
isSessionReady s = sessionState s == SessionReady

-- | Get session age in seconds
sessionAge :: Session -> IO NominalDiffTime
sessionAge s = do
  now <- getCurrentTime
  pure $ diffUTCTime now (sessionCreatedAt s)

-- | Session data for serialization (Phase 15 Redis storage)
data SessionData = SessionData
  { sdSession :: Session,
    sdProtocolState :: ProtocolState
  }
  deriving (Eq, Show, Generic)

instance ToJSON SessionData where
  toJSON sd =
    object
      [ "session" .= sdSession sd,
        "protocolState" .= sdProtocolState sd
      ]

instance FromJSON SessionData where
  parseJSON = withObject "SessionData" $ \obj ->
    SessionData
      <$> obj .: "session"
      <*> obj .: "protocolState"

-- | Convert session to serializable data
toSessionData :: Session -> ProtocolState -> SessionData
toSessionData = SessionData

-- | Extract session from serialized data
fromSessionData :: SessionData -> (Session, ProtocolState)
fromSessionData sd = (sdSession sd, sdProtocolState sd)
