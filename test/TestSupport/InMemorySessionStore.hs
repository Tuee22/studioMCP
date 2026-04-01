{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module TestSupport.InMemorySessionStore
  ( InMemorySessionStore,
    newInMemorySessionStore,
    newInMemorySessionStoreWithTtl,
  )
where

import Data.IORef
  ( IORef,
    atomicModifyIORef',
    modifyIORef',
    newIORef,
    readIORef,
  )
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Data.Time (addUTCTime, diffUTCTime, getCurrentTime)
import StudioMCP.MCP.Session.Store
  ( CursorPosition (..),
    SessionLock (..),
    SessionStore (..),
    SessionStoreError (..),
    SubscriptionRecord,
  )
import StudioMCP.MCP.Session.Types (Session (..), SessionId)

data InMemorySessionStore = InMemorySessionStore
  { imsSessions :: IORef (Map.Map SessionId Session),
    imsSubscriptions :: IORef (Map.Map SessionId (Map.Map Text SubscriptionRecord)),
    imsCursors :: IORef (Map.Map (SessionId, Text) CursorPosition),
    imsLocks :: IORef (Map.Map SessionId SessionLock),
    imsSessionTtlSeconds :: Int
  }

newInMemorySessionStore :: IO InMemorySessionStore
newInMemorySessionStore =
  newInMemorySessionStoreWithTtl 60

newInMemorySessionStoreWithTtl :: Int -> IO InMemorySessionStore
newInMemorySessionStoreWithTtl ttlSeconds = do
  sessionsRef <- newIORef Map.empty
  subscriptionsRef <- newIORef Map.empty
  cursorsRef <- newIORef Map.empty
  locksRef <- newIORef Map.empty
  pure
    InMemorySessionStore
      { imsSessions = sessionsRef,
        imsSubscriptions = subscriptionsRef,
        imsCursors = cursorsRef,
        imsLocks = locksRef,
        imsSessionTtlSeconds = ttlSeconds
      }

instance SessionStore InMemorySessionStore where
  storeCreateSession store session =
    atomicModifyIORef' (imsSessions store) $ \sessions ->
      if Map.member (sessionId session) sessions
        then (sessions, Left (SessionAlreadyExists (sessionId session)))
        else (Map.insert (sessionId session) session sessions, Right ())

  storeGetSession store sid = do
    sessions <- readIORef (imsSessions store)
    pure $
      maybe
        (Left (SessionNotFound sid))
        Right
        (Map.lookup sid sessions)

  storeUpdateSession store sid updateFn =
    atomicModifyIORef' (imsSessions store) $ \sessions ->
      case Map.lookup sid sessions of
        Nothing -> (sessions, Left (SessionNotFound sid))
        Just currentSession ->
          let updatedSession = updateFn currentSession
           in (Map.insert sid updatedSession sessions, Right updatedSession)

  storeDeleteSession store sid = do
    modifyIORef' (imsSessions store) (Map.delete sid)
    modifyIORef' (imsSubscriptions store) (Map.delete sid)
    modifyIORef' (imsLocks store) (Map.delete sid)
    modifyIORef' (imsCursors store) (Map.filterWithKey (\(sessionIdValue, _) _ -> sessionIdValue /= sid))
    pure (Right ())

  storeTouchSession store sid = do
    now <- getCurrentTime
    storeUpdateSession store sid (\session -> session {sessionLastActiveAt = now}) >>= \case
      Left err -> pure (Left err)
      Right _ -> pure (Right ())

  storeAddSubscription store sid resourceUri subscription = do
    sessionResult <- storeGetSession store sid
    case sessionResult of
      Left err -> pure (Left err)
      Right _ -> do
        modifyIORef'
          (imsSubscriptions store)
          (Map.insertWith Map.union sid (Map.singleton resourceUri subscription))
        pure (Right ())

  storeRemoveSubscription store sid resourceUri = do
    modifyIORef'
      (imsSubscriptions store)
      (Map.update (dropSubscription resourceUri) sid)
    pure (Right ())
    where
      dropSubscription uri subscriptions =
        let remaining = Map.delete uri subscriptions
         in if Map.null remaining then Nothing else Just remaining

  storeGetSubscriptions store sid = do
    subscriptions <- readIORef (imsSubscriptions store)
    pure $
      Right
        ( maybe
            []
            Map.elems
            (Map.lookup sid subscriptions)
        )

  storeSetCursor store sid cursor = do
    sessionResult <- storeGetSession store sid
    case sessionResult of
      Left err -> pure (Left err)
      Right _ -> do
        modifyIORef'
          (imsCursors store)
          (Map.insert (sid, cpStreamName cursor) cursor)
        pure (Right ())

  storeGetCursor store sid streamName = do
    cursors <- readIORef (imsCursors store)
    pure (Right (Map.lookup (sid, streamName) cursors))

  storeAcquireLock store sid podId ttlSeconds = do
    sessionResult <- storeGetSession store sid
    case sessionResult of
      Left err -> pure (Left err)
      Right _ -> do
        now <- getCurrentTime
        locks <- readIORef (imsLocks store)
        case Map.lookup sid locks of
          Just existingLock
            | slHolderPodId existingLock /= podId && slExpiresAt existingLock > now ->
                pure (Left (LockAcquisitionFailed sid))
          _ -> do
            let lock =
                  SessionLock
                    { slSessionId = sid,
                      slHolderPodId = podId,
                      slAcquiredAt = now,
                      slExpiresAt = addUTCTime (fromIntegral ttlSeconds) now
                    }
            modifyIORef' (imsLocks store) (Map.insert sid lock)
            pure (Right lock)

  storeReleaseLock store sid podId = do
    locks <- readIORef (imsLocks store)
    case Map.lookup sid locks of
      Just lock
        | slHolderPodId lock == podId -> do
            modifyIORef' (imsLocks store) (Map.delete sid)
            pure (Right ())
      _ ->
        pure (Left (LockNotHeld sid))

  storeListSessions store = do
    sessions <- readIORef (imsSessions store)
    pure (Right (Map.keys sessions))

  storeExpireSessions store = do
    now <- getCurrentTime
    sessions <- readIORef (imsSessions store)
    let staleSessionIds =
          [ sid
          | (sid, session) <- Map.toList sessions,
            diffUTCTime now (sessionLastActiveAt session) > fromIntegral (imsSessionTtlSeconds store)
          ]
    if null staleSessionIds
      then pure (Right 0)
      else do
        let staleSet = Map.fromList [(sid, ()) | sid <- staleSessionIds]
            keepSession sid _ = Map.notMember sid staleSet
            keepCursor (sid, _) _ = Map.notMember sid staleSet
        modifyIORef' (imsSessions store) (Map.filterWithKey keepSession)
        modifyIORef' (imsSubscriptions store) (Map.filterWithKey keepSession)
        modifyIORef' (imsLocks store) (Map.filterWithKey keepSession)
        modifyIORef' (imsCursors store) (Map.filterWithKey keepCursor)
        pure (Right (length staleSessionIds))
