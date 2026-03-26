{-# LANGUAGE OverloadedStrings #-}

module Session.RedisStoreSpec (spec) where

import Control.Concurrent (threadDelay)
import Data.Time (addUTCTime, getCurrentTime)
import StudioMCP.MCP.Session.RedisConfig
import StudioMCP.MCP.Session.RedisStore
import StudioMCP.MCP.Session.Store
import StudioMCP.MCP.Session.Types
import Test.Hspec

spec :: Spec
spec = do
  describe "newRedisSessionStore" $ do
    it "creates a new store with default config" $ do
      store <- newRedisSessionStore defaultRedisConfig
      health <- checkRedisHealth store
      rhConnected health `shouldBe` True
      rhSessionCount health `shouldBe` 0

  describe "closeRedisSessionStore" $ do
    it "marks store as disconnected" $ do
      store <- newRedisSessionStore defaultRedisConfig
      closeRedisSessionStore store
      health <- checkRedisHealth store
      rhConnected health `shouldBe` False

  describe "testConnection" $ do
    it "returns Right when connected" $ do
      store <- newRedisSessionStore defaultRedisConfig
      result <- testConnection store
      result `shouldBe` Right ()

    it "returns Left when disconnected" $ do
      store <- newRedisSessionStore defaultRedisConfig
      closeRedisSessionStore store
      result <- testConnection store
      case result of
        Left (StoreUnavailable _) -> pure ()
        other -> expectationFailure $ "Expected StoreUnavailable, got: " ++ show other

  describe "withRedisConnection" $ do
    it "executes action when connected" $ do
      store <- newRedisSessionStore defaultRedisConfig
      result <- withRedisConnection store (pure 42)
      result `shouldBe` Right 42

    it "returns error when disconnected" $ do
      store <- newRedisSessionStore defaultRedisConfig
      closeRedisSessionStore store
      result <- withRedisConnection store (pure 42)
      case result of
        Left (StoreUnavailable _) -> pure ()
        other -> expectationFailure $ "Expected StoreUnavailable, got: " ++ show other

  describe "session operations" $ do
    it "creates and retrieves a session" $ do
      store <- newRedisSessionStore defaultRedisConfig
      session <- newSession
      _ <- storeCreateSession store session
      result <- storeGetSession store (sessionId session)
      case result of
        Right retrieved -> sessionId retrieved `shouldBe` sessionId session
        Left err -> expectationFailure $ "Failed to get session: " ++ show err

    it "fails to create duplicate session" $ do
      store <- newRedisSessionStore defaultRedisConfig
      session <- newSession
      _ <- storeCreateSession store session
      result <- storeCreateSession store session
      case result of
        Left (SessionAlreadyExists _) -> pure ()
        other -> expectationFailure $ "Expected SessionAlreadyExists, got: " ++ show other

    it "returns error for non-existent session" $ do
      store <- newRedisSessionStore defaultRedisConfig
      result <- storeGetSession store (SessionId "nonexistent")
      case result of
        Left (SessionNotFound _) -> pure ()
        other -> expectationFailure $ "Expected SessionNotFound, got: " ++ show other

    it "updates a session" $ do
      store <- newRedisSessionStore defaultRedisConfig
      session <- newSession
      _ <- storeCreateSession store session
      result <- storeUpdateSession store (sessionId session) (\s -> s {sessionState = SessionReady})
      case result of
        Right updated -> sessionState updated `shouldBe` SessionReady
        Left err -> expectationFailure $ "Failed to update session: " ++ show err

    it "deletes a session" $ do
      store <- newRedisSessionStore defaultRedisConfig
      session <- newSession
      _ <- storeCreateSession store session
      _ <- storeDeleteSession store (sessionId session)
      result <- storeGetSession store (sessionId session)
      case result of
        Left (SessionNotFound _) -> pure ()
        other -> expectationFailure $ "Expected SessionNotFound, got: " ++ show other

    it "touches a session" $ do
      store <- newRedisSessionStore defaultRedisConfig
      session <- newSession
      _ <- storeCreateSession store session
      result <- storeTouchSession store (sessionId session)
      result `shouldBe` Right ()

  describe "subscription operations" $ do
    it "adds and retrieves subscriptions" $ do
      store <- newRedisSessionStore defaultRedisConfig
      session <- newSession
      _ <- storeCreateSession store session
      now <- getCurrentTime
      let sub =
            SubscriptionRecord
              { srResourceUri = "file:///test.txt",
                srSubscribedAt = now,
                srLastEventId = Nothing
              }
      _ <- storeAddSubscription store (sessionId session) "file:///test.txt" sub
      result <- storeGetSubscriptions store (sessionId session)
      case result of
        Right subs -> length subs `shouldBe` 1
        Left err -> expectationFailure $ "Failed to get subscriptions: " ++ show err

    it "removes subscriptions" $ do
      store <- newRedisSessionStore defaultRedisConfig
      session <- newSession
      _ <- storeCreateSession store session
      now <- getCurrentTime
      let sub =
            SubscriptionRecord
              { srResourceUri = "file:///test.txt",
                srSubscribedAt = now,
                srLastEventId = Nothing
              }
      _ <- storeAddSubscription store (sessionId session) "file:///test.txt" sub
      _ <- storeRemoveSubscription store (sessionId session) "file:///test.txt"
      result <- storeGetSubscriptions store (sessionId session)
      case result of
        Right subs -> length subs `shouldBe` 0
        Left err -> expectationFailure $ "Failed to get subscriptions: " ++ show err

  describe "cursor operations" $ do
    it "sets and gets cursor" $ do
      store <- newRedisSessionStore defaultRedisConfig
      session <- newSession
      _ <- storeCreateSession store session
      now <- getCurrentTime
      let cursor =
            CursorPosition
              { cpStreamName = "events",
                cpPosition = "12345",
                cpUpdatedAt = now
              }
      _ <- storeSetCursor store (sessionId session) cursor
      result <- storeGetCursor store (sessionId session) "events"
      case result of
        Right (Just c) -> cpPosition c `shouldBe` "12345"
        other -> expectationFailure $ "Expected cursor, got: " ++ show other

    it "returns Nothing for non-existent cursor" $ do
      store <- newRedisSessionStore defaultRedisConfig
      session <- newSession
      result <- storeGetCursor store (sessionId session) "nonexistent"
      result `shouldBe` Right Nothing

  describe "lock operations" $ do
    it "acquires and releases lock" $ do
      store <- newRedisSessionStore defaultRedisConfig
      session <- newSession
      _ <- storeCreateSession store session
      lockResult <- storeAcquireLock store (sessionId session) "pod-1" 30
      case lockResult of
        Right lock -> do
          slHolderPodId lock `shouldBe` "pod-1"
          releaseResult <- storeReleaseLock store (sessionId session) "pod-1"
          releaseResult `shouldBe` Right ()
        Left err -> expectationFailure $ "Failed to acquire lock: " ++ show err

    it "prevents duplicate lock acquisition by different pod" $ do
      store <- newRedisSessionStore defaultRedisConfig
      session <- newSession
      _ <- storeCreateSession store session
      _ <- storeAcquireLock store (sessionId session) "pod-1" 30
      result <- storeAcquireLock store (sessionId session) "pod-2" 30
      case result of
        Left (LockAcquisitionFailed _) -> pure ()
        other -> expectationFailure $ "Expected LockAcquisitionFailed, got: " ++ show other

    it "allows same pod to re-acquire lock" $ do
      store <- newRedisSessionStore defaultRedisConfig
      session <- newSession
      _ <- storeCreateSession store session
      _ <- storeAcquireLock store (sessionId session) "pod-1" 30
      result <- storeAcquireLock store (sessionId session) "pod-1" 30
      case result of
        Right lock -> slHolderPodId lock `shouldBe` "pod-1"
        Left err -> expectationFailure $ "Failed to re-acquire lock: " ++ show err

    it "prevents release by non-holder" $ do
      store <- newRedisSessionStore defaultRedisConfig
      session <- newSession
      _ <- storeCreateSession store session
      _ <- storeAcquireLock store (sessionId session) "pod-1" 30
      result <- storeReleaseLock store (sessionId session) "pod-2"
      case result of
        Left (LockNotHeld _) -> pure ()
        other -> expectationFailure $ "Expected LockNotHeld, got: " ++ show other

  describe "bulk operations" $ do
    it "lists all sessions" $ do
      store <- newRedisSessionStore defaultRedisConfig
      session1 <- newSession
      session2 <- newSession
      _ <- storeCreateSession store session1
      _ <- storeCreateSession store session2
      result <- storeListSessions store
      case result of
        Right sessions -> length sessions `shouldBe` 2
        Left err -> expectationFailure $ "Failed to list sessions: " ++ show err

    it "expires no sessions when none are stale" $ do
      store <- newRedisSessionStore defaultRedisConfig
      result <- storeExpireSessions store
      result `shouldBe` Right 0

    it "shares session state across stores with a shared backend prefix" $ do
      let sharedConfig = defaultRedisConfig {rcKeyPrefix = "shared:test-session-visibility:"}
      store1 <- newRedisSessionStore sharedConfig
      store2 <- newRedisSessionStore sharedConfig
      session <- newSession
      _ <- storeCreateSession store1 session
      result <- storeGetSession store2 (sessionId session)
      case result of
        Right retrieved -> sessionId retrieved `shouldBe` sessionId session
        Left err -> expectationFailure $ "Expected shared session visibility, got: " ++ show err

    it "expires stale sessions and removes associated state" $ do
      let expiryConfig =
            defaultRedisConfig
              { rcKeyPrefix = "test-session-expiration:"
              , rcSessionTtl = 1
              }
      store <- newRedisSessionStore expiryConfig
      session <- newSession
      _ <- storeCreateSession store session
      now <- getCurrentTime
      _ <-
        storeUpdateSession
          store
          (sessionId session)
          (\s -> s {sessionLastActiveAt = addUTCTime (-10) now})
      let sub =
            SubscriptionRecord
              { srResourceUri = "file:///expired.txt"
              , srSubscribedAt = now
              , srLastEventId = Nothing
              }
          cursor =
            CursorPosition
              { cpStreamName = "events"
              , cpPosition = "stale"
              , cpUpdatedAt = now
              }
      _ <- storeAddSubscription store (sessionId session) "file:///expired.txt" sub
      _ <- storeSetCursor store (sessionId session) cursor
      _ <- storeAcquireLock store (sessionId session) "pod-1" 30

      expireResult <- storeExpireSessions store
      expireResult `shouldBe` Right 1

      sessionResult <- storeGetSession store (sessionId session)
      case sessionResult of
        Left (SessionNotFound _) -> pure ()
        other -> expectationFailure $ "Expected expired session to be removed, got: " ++ show other

      subscriptionsResult <- storeGetSubscriptions store (sessionId session)
      subscriptionsResult `shouldBe` Right []

      cursorResult <- storeGetCursor store (sessionId session) "events"
      cursorResult `shouldBe` Right Nothing

  describe "RedisHealth" $ do
    it "reports session count" $ do
      store <- newRedisSessionStore defaultRedisConfig
      session <- newSession
      _ <- storeCreateSession store session
      health <- checkRedisHealth store
      rhSessionCount health `shouldBe` 1

    it "reports subscription count" $ do
      store <- newRedisSessionStore defaultRedisConfig
      session <- newSession
      _ <- storeCreateSession store session
      now <- getCurrentTime
      let sub =
            SubscriptionRecord
              { srResourceUri = "file:///test.txt",
                srSubscribedAt = now,
                srLastEventId = Nothing
              }
      _ <- storeAddSubscription store (sessionId session) "file:///test.txt" sub
      health <- checkRedisHealth store
      rhSubscriptionCount health `shouldBe` 1
