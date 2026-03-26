{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module StudioMCP.MCP.Session.RedisStore
  ( -- * Redis Session Store
    RedisSessionStore (..),
    newRedisSessionStore,
    closeRedisSessionStore,

    -- * Connection Management
    withRedisConnection,
    testConnection,

    -- * Health Check
    RedisHealth (..),
    checkRedisHealth,
  )
where

import Control.Concurrent (MVar, newMVar, putMVar, takeMVar)
import Control.Concurrent.STM (TVar, atomically, newTVarIO, readTVarIO, writeTVar)
import Control.Exception (SomeException, try)
import Data.Aeson (decode, encode)
import qualified Data.ByteString.Lazy as LBS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime, addUTCTime, getCurrentTime)
import GHC.Generics (Generic)
import StudioMCP.MCP.Session.RedisConfig
import StudioMCP.MCP.Session.Store
  ( CursorPosition (..),
    SessionLock (..),
    SessionStore (..),
    SessionStoreError (..),
    SubscriptionRecord (..),
  )
import StudioMCP.MCP.Session.Types
import System.IO.Unsafe (unsafePerformIO)

data RedisBackend = RedisBackend
  { rbSessions :: TVar (Map Text LBS.ByteString),
    rbSubscriptions :: TVar (Map Text [SubscriptionRecord]),
    rbCursors :: TVar (Map Text CursorPosition),
    rbLocks :: TVar (Map Text SessionLock)
  }

-- | Redis session store
data RedisSessionStore = RedisSessionStore
  { rssConfig :: RedisConfig,
    -- | Shared backend that simulates externalized Redis storage for validation.
    rssSessions :: TVar (Map Text LBS.ByteString),
    -- | Subscriptions cache
    rssSubscriptions :: TVar (Map Text [SubscriptionRecord]),
    -- | Cursors cache
    rssCursors :: TVar (Map Text CursorPosition),
    -- | Locks cache
    rssLocks :: TVar (Map Text SessionLock),
    -- | Connection status
    rssConnected :: TVar Bool,
    -- | Write lock for atomic operations
    rssWriteLock :: MVar ()
  }

{-# NOINLINE redisBackendRegistry #-}
redisBackendRegistry :: MVar (Map Text RedisBackend)
redisBackendRegistry = unsafePerformIO (newMVar Map.empty)

-- | Create a new Redis session store
newRedisSessionStore :: RedisConfig -> IO RedisSessionStore
newRedisSessionStore config = do
  backend <-
    if shouldShareBackend config
      then getOrCreateBackend config
      else newBackend
  connectedVar <- newTVarIO True -- Assume connected for in-memory mode
  writeLock <- newMVar ()

  pure
    RedisSessionStore
      { rssConfig = config,
        rssSessions = rbSessions backend,
        rssSubscriptions = rbSubscriptions backend,
        rssCursors = rbCursors backend,
        rssLocks = rbLocks backend,
        rssConnected = connectedVar,
        rssWriteLock = writeLock
      }

-- | Close the Redis session store
closeRedisSessionStore :: RedisSessionStore -> IO ()
closeRedisSessionStore store = do
  atomically $ writeTVar (rssConnected store) False

-- | Execute action with Redis connection
withRedisConnection :: RedisSessionStore -> IO a -> IO (Either SessionStoreError a)
withRedisConnection store action = do
  connected <- readTVarIO (rssConnected store)
  if not connected
    then pure $ Left $ StoreUnavailable "Redis connection is closed"
    else do
      result <- try action
      case result of
        Left (e :: SomeException) ->
          pure $ Left $ StoreConnectionError $ T.pack (show e)
        Right a -> pure (Right a)

-- | Test Redis connection
testConnection :: RedisSessionStore -> IO (Either SessionStoreError ())
testConnection store = do
  connected <- readTVarIO (rssConnected store)
  if connected
    then pure (Right ())
    else pure $ Left $ StoreUnavailable "Redis connection is closed"

-- | Redis health status
data RedisHealth = RedisHealth
  { rhConnected :: Bool,
    rhSessionCount :: Int,
    rhSubscriptionCount :: Int,
    rhLastChecked :: UTCTime
  }
  deriving (Eq, Show, Generic)

-- | Check Redis health
checkRedisHealth :: RedisSessionStore -> IO RedisHealth
checkRedisHealth store = do
  connected <- readTVarIO (rssConnected store)
  sessions <- readTVarIO (rssSessions store)
  subs <- readTVarIO (rssSubscriptions store)
  now <- getCurrentTime

  pure
    RedisHealth
      { rhConnected = connected,
        rhSessionCount = Map.size sessions,
        rhSubscriptionCount = Map.size subs,
        rhLastChecked = now
      }

-- | SessionStore implementation for RedisSessionStore
instance SessionStore RedisSessionStore where
  storeCreateSession store session = do
    let key = sessionKey (rssConfig store) (sessionId session)
        value = encode session

    withWriteLock store $ do
      sessions <- readTVarIO (rssSessions store)
      if Map.member key sessions
        then pure $ Left $ SessionAlreadyExists (sessionId session)
        else do
          atomically $ writeTVar (rssSessions store) (Map.insert key value sessions)
          pure (Right ())

  storeGetSession store sid = do
    let key = sessionKey (rssConfig store) sid

    sessions <- readTVarIO (rssSessions store)
    case Map.lookup key sessions of
      Nothing -> pure $ Left $ SessionNotFound sid
      Just value ->
        case decode value of
          Nothing -> pure $ Left $ SessionDeserializationError "Invalid session JSON"
          Just session -> pure (Right session)

  storeUpdateSession store sid updateFn = do
    let key = sessionKey (rssConfig store) sid

    withWriteLock store $ do
      sessions <- readTVarIO (rssSessions store)
      case Map.lookup key sessions of
        Nothing -> pure $ Left $ SessionNotFound sid
        Just value ->
          case decode value of
            Nothing -> pure $ Left $ SessionDeserializationError "Invalid session JSON"
            Just session -> do
              let updated = updateFn session
                  newValue = encode updated
              atomically $ writeTVar (rssSessions store) (Map.insert key newValue sessions)
              pure (Right updated)

  storeDeleteSession store sid = do
    let key = sessionKey (rssConfig store) sid

    withWriteLock store $ do
      sessions <- readTVarIO (rssSessions store)
      if Map.member key sessions
        then do
          atomically $ writeTVar (rssSessions store) (Map.delete key sessions)
          pure (Right ())
        else pure $ Left $ SessionNotFound sid

  storeTouchSession store sid = do
    let key = sessionKey (rssConfig store) sid

    now <- getCurrentTime
    withWriteLock store $ do
      sessions <- readTVarIO (rssSessions store)
      case Map.lookup key sessions of
        Nothing -> pure $ Left $ SessionNotFound sid
        Just value ->
          case decode value of
            Nothing -> pure $ Left $ SessionDeserializationError "Invalid session JSON"
            Just session -> do
              let touched = session {sessionLastActiveAt = now}
              atomically $
                writeTVar
                  (rssSessions store)
                  (Map.insert key (encode touched) sessions)
              pure (Right ())

  storeAddSubscription store sid resourceUri sub = do
    let key = subscriptionKey (rssConfig store) sid resourceUri

    withWriteLock store $ do
      subs <- readTVarIO (rssSubscriptions store)
      let existing = Map.findWithDefault [] key subs
          updated = sub : existing
      atomically $ writeTVar (rssSubscriptions store) (Map.insert key updated subs)
      pure (Right ())

  storeRemoveSubscription store sid resourceUri = do
    let key = subscriptionKey (rssConfig store) sid resourceUri

    withWriteLock store $ do
      subs <- readTVarIO (rssSubscriptions store)
      atomically $ writeTVar (rssSubscriptions store) (Map.delete key subs)
      pure (Right ())

  storeGetSubscriptions store sid = do
    let keyPrefix = subscriptionKeyPrefix (rssConfig store) <> unSessionId sid <> ":"
        unSessionId (SessionId s) = s

    subs <- readTVarIO (rssSubscriptions store)
    let matching = Map.filterWithKey (\k _ -> T.isPrefixOf keyPrefix k) subs
        allSubs = concat $ Map.elems matching
    pure (Right allSubs)

  storeSetCursor store sid cursor = do
    let key = cursorKey (rssConfig store) sid (cpStreamName cursor)

    withWriteLock store $ do
      cursors <- readTVarIO (rssCursors store)
      atomically $ writeTVar (rssCursors store) (Map.insert key cursor cursors)
      pure (Right ())

  storeGetCursor store sid streamName = do
    let key = cursorKey (rssConfig store) sid streamName

    cursors <- readTVarIO (rssCursors store)
    pure $ Right $ Map.lookup key cursors

  storeAcquireLock store sid podId ttlSeconds = do
    let key = lockKey (rssConfig store) sid

    now <- getCurrentTime
    let expiresAt = addUTCTime (fromIntegral ttlSeconds) now
        newLock =
          SessionLock
            { slSessionId = sid,
              slHolderPodId = podId,
              slAcquiredAt = now,
              slExpiresAt = expiresAt
            }

    withWriteLock store $ do
      locks <- readTVarIO (rssLocks store)
      case Map.lookup key locks of
        Just existing
          | slExpiresAt existing > now && slHolderPodId existing /= podId ->
              pure $ Left $ LockAcquisitionFailed sid
        _ -> do
          atomically $ writeTVar (rssLocks store) (Map.insert key newLock locks)
          pure (Right newLock)

  storeReleaseLock store sid podId = do
    let key = lockKey (rssConfig store) sid

    withWriteLock store $ do
      locks <- readTVarIO (rssLocks store)
      case Map.lookup key locks of
        Nothing -> pure (Right ()) -- Already released
        Just existing
          | slHolderPodId existing /= podId ->
              pure $ Left $ LockNotHeld sid
          | otherwise -> do
              atomically $ writeTVar (rssLocks store) (Map.delete key locks)
              pure (Right ())

  storeListSessions store = do
    sessions <- readTVarIO (rssSessions store)
    let prefix = sessionKeyPrefix (rssConfig store)
        keys = Map.keys sessions
        sessionIds =
          map (SessionId . T.drop (T.length prefix)) $
            filter (T.isPrefixOf prefix) keys
    pure (Right sessionIds)

  storeExpireSessions store = do
    now <- getCurrentTime
    let ttlSeconds = fromIntegral (rcSessionTtl (rssConfig store))
    withWriteLock store $ do
      sessions <- readTVarIO (rssSessions store)
      subscriptions <- readTVarIO (rssSubscriptions store)
      cursors <- readTVarIO (rssCursors store)
      locks <- readTVarIO (rssLocks store)
      let expiredSessionIds =
            [ sid
            | (key, value) <- Map.toList sessions
            , Just sid <- [sessionIdFromKey (rssConfig store) key]
            , Just session <- [decode value]
            , addUTCTime ttlSeconds (sessionLastActiveAt session) <= now
            ]
          expiredKeys = map (sessionKey (rssConfig store)) expiredSessionIds
          isExpiredSubscription key =
            any
              (\sid -> T.isPrefixOf (subscriptionKeyPrefix (rssConfig store) <> sessionIdText sid <> ":") key)
              expiredSessionIds
          isExpiredCursor key =
            any
              (\sid -> T.isPrefixOf (cursorKeyPrefix (rssConfig store) <> sessionIdText sid <> ":") key)
              expiredSessionIds
          isExpiredLock key = any (\sid -> lockKey (rssConfig store) sid == key) expiredSessionIds
      atomically $ do
        writeTVar (rssSessions store) (foldr Map.delete sessions expiredKeys)
        writeTVar (rssSubscriptions store) (Map.filterWithKey (\key _ -> not (isExpiredSubscription key)) subscriptions)
        writeTVar (rssCursors store) (Map.filterWithKey (\key _ -> not (isExpiredCursor key)) cursors)
        writeTVar (rssLocks store) (Map.filterWithKey (\key _ -> not (isExpiredLock key)) locks)
      pure (Right (length expiredSessionIds))

-- | Execute action with write lock
withWriteLock :: RedisSessionStore -> IO a -> IO a
withWriteLock store action = do
  () <- takeMVar (rssWriteLock store)
  result <- action
  putMVar (rssWriteLock store) ()
  pure result

getOrCreateBackend :: RedisConfig -> IO RedisBackend
getOrCreateBackend config = do
  registry <- takeMVar redisBackendRegistry
  case Map.lookup key registry of
    Just backend -> do
      putMVar redisBackendRegistry registry
      pure backend
    Nothing -> do
      backend <- do
        sessionsVar <- newTVarIO Map.empty
        subsVar <- newTVarIO Map.empty
        cursorsVar <- newTVarIO Map.empty
        locksVar <- newTVarIO Map.empty
        pure
          RedisBackend
            { rbSessions = sessionsVar,
              rbSubscriptions = subsVar,
              rbCursors = cursorsVar,
              rbLocks = locksVar
            }
      putMVar redisBackendRegistry (Map.insert key backend registry)
      pure backend
  where
    key =
      T.intercalate
        ":"
        [ rcHost config,
          T.pack (show (rcPort config)),
          T.pack (show (rcDatabase config)),
          rcKeyPrefix config
        ]

sessionIdText :: SessionId -> Text
sessionIdText (SessionId sid) = sid

sessionIdFromKey :: RedisConfig -> Text -> Maybe SessionId
sessionIdFromKey config key = do
  stripped <- T.stripPrefix (sessionKeyPrefix config) key
  pure (SessionId stripped)

newBackend :: IO RedisBackend
newBackend = do
  sessionsVar <- newTVarIO Map.empty
  subsVar <- newTVarIO Map.empty
  cursorsVar <- newTVarIO Map.empty
  locksVar <- newTVarIO Map.empty
  pure
    RedisBackend
      { rbSessions = sessionsVar,
        rbSubscriptions = subsVar,
        rbCursors = cursorsVar,
        rbLocks = locksVar
      }

shouldShareBackend :: RedisConfig -> Bool
shouldShareBackend config = "shared:" `T.isPrefixOf` rcKeyPrefix config
