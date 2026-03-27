{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.MCP.Session.Store
  ( -- * Session Store Interface
    SessionStore (..),
    SessionStoreError (..),

    -- * Session Operations
    createSession,
    getSession,
    updateSession,
    deleteSession,
    touchSession,

    -- * Subscription Operations
    addSubscription,
    removeSubscription,
    getSubscriptions,

    -- * Subscription Types
    SubscriptionRecord (..),

    -- * Cursor Operations
    setCursor,
    getCursor,

    -- * Cursor Types
    CursorPosition (..),

    -- * Lock Operations
    acquireLock,
    releaseLock,
    withLock,

    -- * Lock Types
    SessionLock (..),

    -- * Bulk Operations
    listSessions,
    expireSessions,
  )
where

import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)
import StudioMCP.MCP.Session.Types (Session, SessionId)

-- | Session store errors
data SessionStoreError
  = -- | Session not found
    SessionNotFound SessionId
  | -- | Session already exists
    SessionAlreadyExists SessionId
  | -- | Store connection error
    StoreConnectionError Text
  | -- | Store operation timeout
    StoreTimeoutError Text
  | -- | Lock acquisition failed
    LockAcquisitionFailed SessionId
  | -- | Lock not held
    LockNotHeld SessionId
  | -- | Serialization error
    SessionSerializationError Text
  | -- | Deserialization error
    SessionDeserializationError Text
  | -- | Store is unavailable
    StoreUnavailable Text
  deriving (Eq, Show, Generic)

instance ToJSON SessionStoreError

-- | Subscription record
data SubscriptionRecord = SubscriptionRecord
  { srResourceUri :: Text,
    srSubscribedAt :: UTCTime,
    srLastEventId :: Maybe Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON SubscriptionRecord
instance FromJSON SubscriptionRecord

-- | Cursor position
data CursorPosition = CursorPosition
  { cpStreamName :: Text,
    cpPosition :: Text,
    cpUpdatedAt :: UTCTime
  }
  deriving (Eq, Show, Generic)

instance ToJSON CursorPosition
instance FromJSON CursorPosition

-- | Session lock
data SessionLock = SessionLock
  { slSessionId :: SessionId,
    slHolderPodId :: Text,
    slAcquiredAt :: UTCTime,
    slExpiresAt :: UTCTime
  }
  deriving (Eq, Show, Generic)

instance ToJSON SessionLock
instance FromJSON SessionLock

-- | Session store interface
class SessionStore s where
  -- | Create a new session in the store
  storeCreateSession :: s -> Session -> IO (Either SessionStoreError ())

  -- | Get a session by ID
  storeGetSession :: s -> SessionId -> IO (Either SessionStoreError Session)

  -- | Update a session
  storeUpdateSession :: s -> SessionId -> (Session -> Session) -> IO (Either SessionStoreError Session)

  -- | Delete a session
  storeDeleteSession :: s -> SessionId -> IO (Either SessionStoreError ())

  -- | Touch a session to refresh TTL
  storeTouchSession :: s -> SessionId -> IO (Either SessionStoreError ())

  -- | Add a subscription
  storeAddSubscription :: s -> SessionId -> Text -> SubscriptionRecord -> IO (Either SessionStoreError ())

  -- | Remove a subscription
  storeRemoveSubscription :: s -> SessionId -> Text -> IO (Either SessionStoreError ())

  -- | Get all subscriptions for a session
  storeGetSubscriptions :: s -> SessionId -> IO (Either SessionStoreError [SubscriptionRecord])

  -- | Set cursor position
  storeSetCursor :: s -> SessionId -> CursorPosition -> IO (Either SessionStoreError ())

  -- | Get cursor position
  storeGetCursor :: s -> SessionId -> Text -> IO (Either SessionStoreError (Maybe CursorPosition))

  -- | Acquire a lock on a session
  storeAcquireLock :: s -> SessionId -> Text -> Int -> IO (Either SessionStoreError SessionLock)

  -- | Release a lock on a session
  storeReleaseLock :: s -> SessionId -> Text -> IO (Either SessionStoreError ())

  -- | List all sessions (for admin)
  storeListSessions :: s -> IO (Either SessionStoreError [SessionId])

  -- | Expire stale sessions
  storeExpireSessions :: s -> IO (Either SessionStoreError Int)

-- | Helper: Create session
createSession :: SessionStore s => s -> Session -> IO (Either SessionStoreError ())
createSession = storeCreateSession

-- | Helper: Get session
getSession :: SessionStore s => s -> SessionId -> IO (Either SessionStoreError Session)
getSession = storeGetSession

-- | Helper: Update session
updateSession :: SessionStore s => s -> SessionId -> (Session -> Session) -> IO (Either SessionStoreError Session)
updateSession = storeUpdateSession

-- | Helper: Delete session
deleteSession :: SessionStore s => s -> SessionId -> IO (Either SessionStoreError ())
deleteSession = storeDeleteSession

-- | Helper: Touch session
touchSession :: SessionStore s => s -> SessionId -> IO (Either SessionStoreError ())
touchSession = storeTouchSession

-- | Helper: Add subscription
addSubscription :: SessionStore s => s -> SessionId -> Text -> SubscriptionRecord -> IO (Either SessionStoreError ())
addSubscription = storeAddSubscription

-- | Helper: Remove subscription
removeSubscription :: SessionStore s => s -> SessionId -> Text -> IO (Either SessionStoreError ())
removeSubscription = storeRemoveSubscription

-- | Helper: Get subscriptions
getSubscriptions :: SessionStore s => s -> SessionId -> IO (Either SessionStoreError [SubscriptionRecord])
getSubscriptions = storeGetSubscriptions

-- | Helper: Set cursor
setCursor :: SessionStore s => s -> SessionId -> CursorPosition -> IO (Either SessionStoreError ())
setCursor = storeSetCursor

-- | Helper: Get cursor
getCursor :: SessionStore s => s -> SessionId -> Text -> IO (Either SessionStoreError (Maybe CursorPosition))
getCursor = storeGetCursor

-- | Helper: Acquire lock
acquireLock :: SessionStore s => s -> SessionId -> Text -> Int -> IO (Either SessionStoreError SessionLock)
acquireLock = storeAcquireLock

-- | Helper: Release lock
releaseLock :: SessionStore s => s -> SessionId -> Text -> IO (Either SessionStoreError ())
releaseLock = storeReleaseLock

-- | Helper: Execute action with lock
withLock ::
  SessionStore s =>
  s ->
  SessionId ->
  Text ->
  Int ->
  IO a ->
  IO (Either SessionStoreError a)
withLock store sid podId ttl action = do
  lockResult <- acquireLock store sid podId ttl
  case lockResult of
    Left err -> pure (Left err)
    Right _ -> do
      result <- action
      _ <- releaseLock store sid podId
      pure (Right result)

-- | Helper: List sessions
listSessions :: SessionStore s => s -> IO (Either SessionStoreError [SessionId])
listSessions = storeListSessions

-- | Helper: Expire sessions
expireSessions :: SessionStore s => s -> IO (Either SessionStoreError Int)
expireSessions = storeExpireSessions
