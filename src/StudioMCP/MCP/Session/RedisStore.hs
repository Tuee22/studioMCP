{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

module StudioMCP.MCP.Session.RedisStore
  ( -- * Redis Session Store
    RedisSessionStore (..),
    newRedisSessionStore,
    closeRedisSessionStore,

    -- * Connection Management
    withRedisConnection,
    testConnection,

    -- * Session Data Persistence
    readSessionData,
    writeSessionData,

    -- * Health Check
    RedisHealth (..),
    checkRedisHealth,
  )
where

import Control.Concurrent.MVar (MVar, newMVar, putMVar, takeMVar)
import Control.Concurrent.STM (TVar, atomically, newTVarIO, readTVarIO, writeTVar)
import Control.Exception (SomeException, bracket_, try)
import System.Timeout (timeout)
import Control.Monad (forM, forM_, unless)
import Data.Aeson (FromJSON, ToJSON, decode, encode)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Text (Text)
import Data.Time (UTCTime, addUTCTime, getCurrentTime)
import Database.Redis
  ( Connection,
    checkedConnect,
    connectAuth,
    connectDatabase,
    connectMaxConnections,
    connectTimeout,
    del,
    disconnect,
    exists,
    parseConnectInfo,
    expire,
    get,
    keys,
    ping,
    runRedis,
    setex,
    setnx,
  )
import qualified Database.Redis as Redis
import GHC.Generics (Generic)
import StudioMCP.MCP.Protocol.StateMachine (ProtocolState (Uninitialized))
import StudioMCP.MCP.Session.RedisConfig
import StudioMCP.MCP.Session.Store
  ( CursorPosition (..),
    SessionLock (..),
    SessionStore (..),
    SessionStoreError (..),
    SubscriptionRecord (..),
  )
import StudioMCP.MCP.Session.Types
  ( Session,
    SessionData (..),
    SessionId (..),
    sessionId,
    sessionLastActiveAt,
    toSessionData,
  )

data RedisSessionStore = RedisSessionStore
  { rssConfig :: RedisConfig,
    rssConnection :: Connection,
    rssConnected :: TVar Bool,
    rssWriteLock :: MVar ()
  }

data RedisHealth = RedisHealth
  { rhConnected :: Bool,
    rhSessionCount :: Int,
    rhSubscriptionCount :: Int,
    rhLastChecked :: UTCTime
  }
  deriving (Eq, Show, Generic)

newRedisSessionStore :: RedisConfig -> IO RedisSessionStore
newRedisSessionStore config = do
  connection <- checkedConnect (buildConnectInfo config)
  connectedVar <- newTVarIO True
  writeLock <- newMVar ()
  pure
    RedisSessionStore
      { rssConfig = config,
        rssConnection = connection,
        rssConnected = connectedVar,
        rssWriteLock = writeLock
      }

closeRedisSessionStore :: RedisSessionStore -> IO ()
closeRedisSessionStore store = do
  atomically $ writeTVar (rssConnected store) False
  disconnect (rssConnection store)

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
        Right value ->
          pure (Right value)

-- | Test Redis connection with a short timeout to detect outages quickly.
-- Uses a 2-second timeout to fail fast when Redis is unreachable, avoiding
-- stale pooled connections that may not immediately detect backend failures.
testConnection :: RedisSessionStore -> IO (Either SessionStoreError ())
testConnection store = do
  -- 2 second timeout in microseconds (2,000,000 μs)
  pingResultOrTimeout <- timeout 2_000_000 (execRedis store ping)
  pure $
    case pingResultOrTimeout of
      Nothing -> Left $ StoreTimeoutError "Redis health check timed out"
      Just pingResult -> pingResult >> Right ()

readSessionData :: RedisSessionStore -> SessionId -> IO (Either SessionStoreError SessionData)
readSessionData store sid = do
  valueResult <- execRedis store (get (keyBytes (sessionKey (rssConfig store) sid)))
  case valueResult of
    Left err -> pure (Left err)
    Right Nothing -> pure $ Left $ SessionNotFound sid
    Right (Just payload) ->
      pure $
        case decodeStrictJson payload of
          Nothing -> Left $ SessionDeserializationError "Invalid session JSON"
          Just sessionData -> Right sessionData

writeSessionData :: RedisSessionStore -> SessionData -> IO (Either SessionStoreError ())
writeSessionData store sessionData =
  execRedis store $
    do
      result <-
        setex
          (keyBytes (sessionKey (rssConfig store) (sessionId (sdSession sessionData))))
          (fromIntegral (rcSessionTtl (rssConfig store)))
          (encodeStrictJson sessionData)
      pure (() <$ result)

checkRedisHealth :: RedisSessionStore -> IO RedisHealth
checkRedisHealth store = do
  connected <- readTVarIO (rssConnected store)
  sessionKeys <- execRedis store (keys (keyBytes (sessionKeyPrefix (rssConfig store) <> "*")))
  subscriptionKeys <- execRedis store (keys (keyBytes (subscriptionKeyPrefix (rssConfig store) <> "*")))
  now <- getCurrentTime
  pure
    RedisHealth
      { rhConnected = connected,
        rhSessionCount = either (const 0) length sessionKeys,
        rhSubscriptionCount = either (const 0) length subscriptionKeys,
        rhLastChecked = now
      }

instance SessionStore RedisSessionStore where
  storeCreateSession store session =
    withWriteLock store $ do
      let sid = sessionId session
          sessionPayload = encodeStrictJson (toSessionData session Uninitialized)
          sessionKeyBytes = keyBytes (sessionKey (rssConfig store) sid)
          ttlSeconds = fromIntegral (rcSessionTtl (rssConfig store))
      created <- execRedis store (setnx sessionKeyBytes sessionPayload)
      case created of
        Left err -> pure (Left err)
        Right False -> pure $ Left $ SessionAlreadyExists sid
        Right True -> do
          expireResult <- execRedis store (expire sessionKeyBytes ttlSeconds)
          case expireResult of
            Left err -> pure (Left err)
            Right _ -> pure (Right ())

  storeGetSession store sid = do
    sessionDataResult <- readSessionData store sid
    pure (fmap sdSession sessionDataResult)

  storeUpdateSession store sid updateFn =
    withWriteLock store $ do
      sessionDataResult <- readSessionData store sid
      case sessionDataResult of
        Left err -> pure (Left err)
        Right sessionData -> do
          let updatedSession = updateFn (sdSession sessionData)
              updatedData = sessionData {sdSession = updatedSession}
          writeResult <- writeSessionData store updatedData
          case writeResult of
            Left err -> pure (Left err)
            Right () -> do
              _ <- refreshAssociatedStateTtl store sid
              pure (Right updatedSession)

  storeDeleteSession store sid =
    withWriteLock store $ do
      existing <- execRedis store (exists (keyBytes (sessionKey (rssConfig store) sid)))
      case existing of
        Left err -> pure (Left err)
        Right False -> pure $ Left $ SessionNotFound sid
        Right True -> do
          deleteSessionFamily store sid
          pure (Right ())

  storeTouchSession store sid =
    withWriteLock store $ do
      sessionDataResult <- readSessionData store sid
      case sessionDataResult of
        Left err -> pure (Left err)
        Right sessionData -> do
          now <- getCurrentTime
          let touchedData =
                sessionData
                  { sdSession = (sdSession sessionData) {sessionLastActiveAt = now}
                  }
          writeResult <- writeSessionData store touchedData
          case writeResult of
            Left err -> pure (Left err)
            Right () -> do
              _ <- refreshAssociatedStateTtl store sid
              pure (Right ())

  storeAddSubscription store sid resourceUri sub =
    withWriteLock store $
      execRedis store
        ( do
            result <-
              setex
                (keyBytes (subscriptionKey (rssConfig store) sid resourceUri))
                (fromIntegral (rcSessionTtl (rssConfig store)))
                (encodeStrictJson [sub])
            pure (() <$ result)
        )

  storeRemoveSubscription store sid resourceUri =
    withWriteLock store $
      execRedis store
        ( do
            result <- del [keyBytes (subscriptionKey (rssConfig store) sid resourceUri)]
            pure (() <$ result)
        )

  storeGetSubscriptions store sid = do
    subscriptionKeys <- matchingKeys store (subscriptionKeyPrefix (rssConfig store) <> sessionIdText sid <> ":*")
    decodedLists <-
      forM
        subscriptionKeys
        (\subscriptionKeyBytes -> do
            valueResult <- execRedis store (get subscriptionKeyBytes)
            pure $
              case valueResult of
                Left err -> Left err
                Right Nothing -> Right []
                Right (Just payload) ->
                  maybe
                    (Left (SessionDeserializationError "Invalid subscription JSON"))
                    Right
                    (decodeStrictJson payload)
        )
    pure (concat <$> sequence decodedLists)

  storeSetCursor store sid cursor =
    withWriteLock store $
      execRedis store
        ( do
            result <-
              setex
                (keyBytes (cursorKey (rssConfig store) sid (cpStreamName cursor)))
                (fromIntegral (rcSessionTtl (rssConfig store)))
                (encodeStrictJson cursor)
            pure (() <$ result)
        )

  storeGetCursor store sid streamName = do
    cursorResult <- execRedis store (get (keyBytes (cursorKey (rssConfig store) sid streamName)))
    pure $
      case cursorResult of
        Left err -> Left err
        Right Nothing -> Right Nothing
        Right (Just payload) ->
          maybe
            (Left (SessionDeserializationError "Invalid cursor JSON"))
            (Right . Just)
            (decodeStrictJson payload)

  storeAcquireLock store sid podId ttlSeconds =
    withWriteLock store $ do
      now <- getCurrentTime
      let lockKeyBytes = keyBytes (lockKey (rssConfig store) sid)
      existingLockResult <- execRedis store (get lockKeyBytes)
      case existingLockResult of
        Left err -> pure (Left err)
        Right maybePayload ->
          case maybePayload >>= decodeStrictJson of
            Just existingLock
              | slExpiresAt existingLock > now && slHolderPodId existingLock /= podId ->
                  pure $ Left $ LockAcquisitionFailed sid
            _ -> do
              let expiresAt = addUTCTime (fromIntegral ttlSeconds) now
                  newLock =
                    SessionLock
                      { slSessionId = sid,
                        slHolderPodId = podId,
                        slAcquiredAt = now,
                        slExpiresAt = expiresAt
                      }
              setResult <-
                execRedis store $
                  do
                    result <-
                      setex
                        lockKeyBytes
                        (fromIntegral ttlSeconds)
                        (encodeStrictJson newLock)
                    pure (() <$ result)
              pure (setResult >> Right newLock)

  storeReleaseLock store sid podId =
    withWriteLock store $ do
      let lockKeyBytes = keyBytes (lockKey (rssConfig store) sid)
      existingLockResult <- execRedis store (get lockKeyBytes)
      case existingLockResult of
        Left err -> pure (Left err)
        Right Nothing -> pure (Right ())
        Right (Just payload) ->
          case decodeStrictJson payload of
            Nothing -> pure $ Left $ SessionDeserializationError "Invalid lock JSON"
            Just existingLock
              | slHolderPodId existingLock /= podId ->
                  pure $ Left $ LockNotHeld sid
              | otherwise -> do
                  _ <- execRedis store (del [lockKeyBytes])
                  pure (Right ())

  storeListSessions store = do
    keyNames <- matchingKeys store (sessionKeyPrefix (rssConfig store) <> "*")
    pure $
      Right
        [ SessionId stripped
        | keyName <- keyNames
        , let stripped = T.drop (T.length (sessionKeyPrefix (rssConfig store))) (decodeKey keyName)
        ]

  storeExpireSessions store =
    withWriteLock store $ do
      now <- getCurrentTime
      sessionKeys <- matchingKeys store (sessionKeyPrefix (rssConfig store) <> "*")
      expiredSessionIds <-
        fmap concat $
          forM sessionKeys $ \sessionKeyBytes -> do
            valueResult <- execRedis store (get sessionKeyBytes)
            pure $
              case valueResult of
                Right (Just payload)
                  | Just sessionData <- decodeStrictJson payload,
                    addUTCTime (fromIntegral (rcSessionTtl (rssConfig store))) (sessionLastActiveAt (sdSession sessionData)) <= now ->
                      [sessionId (sdSession sessionData)]
                _ -> []
      forM_ expiredSessionIds (deleteSessionFamily store)
      pure (Right (length expiredSessionIds))

execRedis :: RedisSessionStore -> Redis.Redis (Either Redis.Reply a) -> IO (Either SessionStoreError a)
execRedis store action = do
  result <- withRedisConnection store (runRedis (rssConnection store) action)
  pure $
    case result of
      Left err -> Left err
      Right (Left reply) -> Left $ StoreConnectionError (T.pack (show reply))
      Right (Right value) -> Right value

matchingKeys :: RedisSessionStore -> Text -> IO [BS.ByteString]
matchingKeys store patternText = do
  keyResult <- execRedis store (keys (keyBytes patternText))
  pure (either (const []) id keyResult)

deleteSessionFamily :: RedisSessionStore -> SessionId -> IO ()
deleteSessionFamily store sid = do
  let keyFamilies =
        [ keyBytes (sessionKey (rssConfig store) sid)
        ]
  subscriptionKeys <- matchingKeys store (subscriptionKeyPrefix (rssConfig store) <> sessionIdText sid <> ":*")
  cursorKeys <- matchingKeys store (cursorKeyPrefix (rssConfig store) <> sessionIdText sid <> ":*")
  let allKeys = keyFamilies <> subscriptionKeys <> cursorKeys <> [keyBytes (lockKey (rssConfig store) sid)]
  unless (null allKeys) $ do
    _ <- execRedis store (del allKeys)
    pure ()

refreshAssociatedStateTtl :: RedisSessionStore -> SessionId -> IO (Either SessionStoreError ())
refreshAssociatedStateTtl store sid = do
  let ttlSeconds = fromIntegral (rcSessionTtl (rssConfig store))
  subscriptionKeys <- matchingKeys store (subscriptionKeyPrefix (rssConfig store) <> sessionIdText sid <> ":*")
  cursorKeys <- matchingKeys store (cursorKeyPrefix (rssConfig store) <> sessionIdText sid <> ":*")
  touchResults <-
    sequence
      [ execRedis store (expire key ttlSeconds) | key <- subscriptionKeys <> cursorKeys ]
  pure (voidEithers touchResults)

buildConnectInfo :: RedisConfig -> Redis.ConnectInfo
buildConnectInfo config =
  case parseConnectInfo redisUrl of
    Left err -> error ("Invalid Redis connection info: " <> err)
    Right connectInfo ->
      connectInfo
        { connectAuth = TE.encodeUtf8 <$> rcPassword config,
          connectDatabase = fromIntegral (rcDatabase config),
          connectMaxConnections = rcPoolSize config,
          connectTimeout = Just (fromIntegral (rcConnectionTimeout config))
        }
  where
    scheme
      | rcUseTls config = "rediss://"
      | otherwise = "redis://"
    redisUrl =
      scheme
        <> maybe "" (\password -> ":" <> T.unpack password <> "@") (rcPassword config)
        <> T.unpack (rcHost config)
        <> ":"
        <> show (rcPort config)
        <> "/"
        <> show (rcDatabase config)

withWriteLock :: RedisSessionStore -> IO a -> IO a
withWriteLock store =
  bracket_
    (takeMVar (rssWriteLock store))
    (putMVar (rssWriteLock store) ())

encodeStrictJson :: ToJSON a => a -> BS.ByteString
encodeStrictJson = LBS.toStrict . encode

decodeStrictJson :: FromJSON a => BS.ByteString -> Maybe a
decodeStrictJson = decode . LBS.fromStrict

keyBytes :: Text -> BS.ByteString
keyBytes = TE.encodeUtf8

decodeKey :: BS.ByteString -> Text
decodeKey = TE.decodeUtf8

sessionIdText :: SessionId -> Text
sessionIdText (SessionId sid) = sid

voidEithers :: [Either e a] -> Either e ()
voidEithers [] = Right ()
voidEithers (Left err : _) = Left err
voidEithers (Right _ : remaining) = voidEithers remaining
