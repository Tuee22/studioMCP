{-# LANGUAGE OverloadedStrings #-}

module Session.RedisStoreSpec (spec) where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, try)
import Data.Text (pack)
import Data.Time (addUTCTime, getCurrentTime)
import StudioMCP.MCP.Session.RedisConfig
import StudioMCP.MCP.Session.RedisStore
import StudioMCP.MCP.Session.Store
import StudioMCP.MCP.Session.Types
import System.Directory (doesFileExist)
import System.Exit (ExitCode (..))
import System.Process (readProcessWithExitCode)
import Test.Hspec

spec :: Spec
spec = do
  redisFixture <- runIO startRedisFixture
  let (containerId, redisConfig) = redisFixture
  afterAll_ (stopRedisFixture redisFixture) $
    before_ (flushRedisFixture containerId) (specWith redisConfig)

specWith :: RedisConfig -> Spec
specWith redisConfig = do
  describe "newRedisSessionStore" $ do
    it "creates a new store with a live Redis backend" $ do
      store <- newRedisSessionStore redisConfig
      health <- checkRedisHealth store
      rhConnected health `shouldBe` True
      rhSessionCount health `shouldBe` 0
      closeRedisSessionStore store

  describe "closeRedisSessionStore" $ do
    it "marks store as disconnected" $ do
      store <- newRedisSessionStore redisConfig
      closeRedisSessionStore store
      health <- checkRedisHealth store
      rhConnected health `shouldBe` False

  describe "testConnection" $ do
    it "returns Right when connected" $ do
      store <- newRedisSessionStore redisConfig
      result <- testConnection store
      result `shouldBe` Right ()
      closeRedisSessionStore store

    it "returns Left when disconnected" $ do
      store <- newRedisSessionStore redisConfig
      closeRedisSessionStore store
      result <- testConnection store
      case result of
        Left (StoreUnavailable _) -> pure ()
        other -> expectationFailure $ "Expected StoreUnavailable, got: " ++ show other

  describe "withRedisConnection" $ do
    it "executes action when connected" $ do
      store <- newRedisSessionStore redisConfig
      result <- withRedisConnection store (pure (42 :: Int))
      result `shouldBe` Right 42
      closeRedisSessionStore store

    it "returns error when disconnected" $ do
      store <- newRedisSessionStore redisConfig
      closeRedisSessionStore store
      result <- withRedisConnection store (pure (42 :: Int))
      case result of
        Left (StoreUnavailable _) -> pure ()
        other -> expectationFailure $ "Expected StoreUnavailable, got: " ++ show other

  describe "session operations" $ do
    it "creates and retrieves a session" $ do
      store <- newRedisSessionStore redisConfig
      session <- newSession
      _ <- storeCreateSession store session
      result <- storeGetSession store (sessionId session)
      case result of
        Right retrieved -> sessionId retrieved `shouldBe` sessionId session
        Left err -> expectationFailure $ "Failed to get session: " ++ show err
      closeRedisSessionStore store

    it "fails to create duplicate session" $ do
      store <- newRedisSessionStore redisConfig
      session <- newSession
      _ <- storeCreateSession store session
      result <- storeCreateSession store session
      case result of
        Left (SessionAlreadyExists _) -> pure ()
        other -> expectationFailure $ "Expected SessionAlreadyExists, got: " ++ show other
      closeRedisSessionStore store

    it "returns error for non-existent session" $ do
      store <- newRedisSessionStore redisConfig
      result <- storeGetSession store (SessionId "nonexistent")
      case result of
        Left (SessionNotFound _) -> pure ()
        other -> expectationFailure $ "Expected SessionNotFound, got: " ++ show other
      closeRedisSessionStore store

    it "updates a session" $ do
      store <- newRedisSessionStore redisConfig
      session <- newSession
      _ <- storeCreateSession store session
      result <- storeUpdateSession store (sessionId session) (\s -> s {sessionState = SessionReady})
      case result of
        Right updated -> sessionState updated `shouldBe` SessionReady
        Left err -> expectationFailure $ "Failed to update session: " ++ show err
      closeRedisSessionStore store

    it "deletes a session" $ do
      store <- newRedisSessionStore redisConfig
      session <- newSession
      _ <- storeCreateSession store session
      _ <- storeDeleteSession store (sessionId session)
      result <- storeGetSession store (sessionId session)
      case result of
        Left (SessionNotFound _) -> pure ()
        other -> expectationFailure $ "Expected SessionNotFound, got: " ++ show other
      closeRedisSessionStore store

    it "touches a session" $ do
      store <- newRedisSessionStore redisConfig
      session <- newSession
      _ <- storeCreateSession store session
      result <- storeTouchSession store (sessionId session)
      result `shouldBe` Right ()
      closeRedisSessionStore store

  describe "subscription operations" $ do
    it "adds and retrieves subscriptions" $ do
      store <- newRedisSessionStore redisConfig
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
      closeRedisSessionStore store

    it "removes subscriptions" $ do
      store <- newRedisSessionStore redisConfig
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
      closeRedisSessionStore store

  describe "cursor operations" $ do
    it "sets and gets cursor" $ do
      store <- newRedisSessionStore redisConfig
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
      closeRedisSessionStore store

    it "returns Nothing for non-existent cursor" $ do
      store <- newRedisSessionStore redisConfig
      session <- newSession
      result <- storeGetCursor store (sessionId session) "nonexistent"
      result `shouldBe` Right Nothing
      closeRedisSessionStore store

  describe "lock operations" $ do
    it "acquires and releases lock" $ do
      store <- newRedisSessionStore redisConfig
      session <- newSession
      _ <- storeCreateSession store session
      lockResult <- storeAcquireLock store (sessionId session) "pod-1" 30
      case lockResult of
        Right lock -> do
          slHolderPodId lock `shouldBe` "pod-1"
          releaseResult <- storeReleaseLock store (sessionId session) "pod-1"
          releaseResult `shouldBe` Right ()
        Left err -> expectationFailure $ "Failed to acquire lock: " ++ show err
      closeRedisSessionStore store

    it "prevents duplicate lock acquisition by different pod" $ do
      store <- newRedisSessionStore redisConfig
      session <- newSession
      _ <- storeCreateSession store session
      _ <- storeAcquireLock store (sessionId session) "pod-1" 30
      result <- storeAcquireLock store (sessionId session) "pod-2" 30
      case result of
        Left (LockAcquisitionFailed _) -> pure ()
        other -> expectationFailure $ "Expected LockAcquisitionFailed, got: " ++ show other
      closeRedisSessionStore store

    it "allows same pod to re-acquire lock" $ do
      store <- newRedisSessionStore redisConfig
      session <- newSession
      _ <- storeCreateSession store session
      _ <- storeAcquireLock store (sessionId session) "pod-1" 30
      result <- storeAcquireLock store (sessionId session) "pod-1" 30
      case result of
        Right lock -> slHolderPodId lock `shouldBe` "pod-1"
        Left err -> expectationFailure $ "Failed to re-acquire lock: " ++ show err
      closeRedisSessionStore store

    it "prevents release by non-holder" $ do
      store <- newRedisSessionStore redisConfig
      session <- newSession
      _ <- storeCreateSession store session
      _ <- storeAcquireLock store (sessionId session) "pod-1" 30
      result <- storeReleaseLock store (sessionId session) "pod-2"
      case result of
        Left (LockNotHeld _) -> pure ()
        other -> expectationFailure $ "Expected LockNotHeld, got: " ++ show other
      closeRedisSessionStore store

  describe "bulk operations" $ do
    it "lists all sessions" $ do
      store <- newRedisSessionStore redisConfig
      session1 <- newSession
      session2 <- newSession
      _ <- storeCreateSession store session1
      _ <- storeCreateSession store session2
      result <- storeListSessions store
      case result of
        Right sessions -> length sessions `shouldBe` 2
        Left err -> expectationFailure $ "Failed to list sessions: " ++ show err
      closeRedisSessionStore store

    it "expires no sessions when none are stale" $ do
      store <- newRedisSessionStore redisConfig
      result <- storeExpireSessions store
      result `shouldBe` Right 0
      closeRedisSessionStore store

    it "shares session state across stores that point at the same Redis backend" $ do
      let sharedConfig = redisConfig {rcKeyPrefix = "shared:test-session-visibility:"}
      store1 <- newRedisSessionStore sharedConfig
      store2 <- newRedisSessionStore sharedConfig
      session <- newSession
      _ <- storeCreateSession store1 session
      result <- storeGetSession store2 (sessionId session)
      case result of
        Right retrieved -> sessionId retrieved `shouldBe` sessionId session
        Left err -> expectationFailure $ "Expected shared session visibility, got: " ++ show err
      closeRedisSessionStore store1
      closeRedisSessionStore store2

    it "expires stale sessions and removes associated state" $ do
      let expiryConfig =
            redisConfig
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
              , cpPosition = "99"
              , cpUpdatedAt = now
              }
      _ <- storeAddSubscription store (sessionId session) "file:///expired.txt" sub
      _ <- storeSetCursor store (sessionId session) cursor
      _ <- storeAcquireLock store (sessionId session) "expiry-pod" 30
      expiredCountResult <- storeExpireSessions store
      expiredCountResult `shouldBe` Right 1
      storeGetSession store (sessionId session) `shouldReturn` Left (SessionNotFound (sessionId session))
      storeGetSubscriptions store (sessionId session) `shouldReturn` Right []
      storeGetCursor store (sessionId session) "events" `shouldReturn` Right Nothing
      closeRedisSessionStore store

-- | Container name for test Redis (fixed name for idempotent cleanup)
testRedisContainerName :: String
testRedisContainerName = "studiomcp-test-redis"

startRedisFixture :: IO (String, RedisConfig)
startRedisFixture = do
  -- Clean up any existing container with this name (idempotent)
  _ <- readProcessWithExitCode "docker" ["rm", "-f", testRedisContainerName] ""
  -- Start new container with fixed name
  (exitCode, stdoutText, stderrText) <-
    readProcessWithExitCode "docker" ["run", "-d", "-P", "--name", testRedisContainerName, "redis:7-alpine"] ""
  case exitCode of
    ExitFailure _ -> fail stderrText
    ExitSuccess -> do
      let containerId = trimLine stdoutText
      portNumber <- resolvePublishedPort containerId
      -- When running inside outer container with mounted Docker socket,
      -- 127.0.0.1 doesn't reach the host. Use host.docker.internal for
      -- Docker Desktop or resolve the host gateway IP.
      hostIp <- resolveDockerHost
      let redisConfig =
            defaultRedisConfig
              { rcHost = pack hostIp
              , rcPort = portNumber
              }
      waitForRedisReady redisConfig
      pure (containerId, redisConfig)

-- | Resolve the Docker host IP for connecting to containers
-- When running inside a container with mounted Docker socket, we need
-- to connect to the host machine where Docker is running.
resolveDockerHost :: IO String
resolveDockerHost = do
  -- Check if we're running in the outer container
  inContainer <- isRunningInContainer
  if inContainer
    then do
      -- Try host.docker.internal first (Docker Desktop)
      (exitCode, _, _) <- readProcessWithExitCode "getent" ["hosts", "host.docker.internal"] ""
      case exitCode of
        ExitSuccess -> pure "host.docker.internal"
        ExitFailure _ -> do
          -- Fall back to default gateway (Linux Docker)
          (gwExit, gwOut, _) <- readProcessWithExitCode "sh" ["-c", "ip route | awk '/default/ {print $3}'"] ""
          case gwExit of
            ExitSuccess -> pure (trimLine gwOut)
            ExitFailure _ -> pure "172.17.0.1"  -- Docker default gateway
    else pure "127.0.0.1"

-- | Check if we're running inside the outer development container
isRunningInContainer :: IO Bool
isRunningInContainer = do
  dockerenvResult <- try (doesFileExist "/.dockerenv") :: IO (Either SomeException Bool)
  pure (either (const False) id dockerenvResult)

stopRedisFixture :: (String, RedisConfig) -> IO ()
stopRedisFixture _ = do
  _ <- readProcessWithExitCode "docker" ["rm", "-f", testRedisContainerName] ""
  pure ()

flushRedisFixture :: String -> IO ()
flushRedisFixture _ = do
  (exitCode, _, stderrText) <-
    readProcessWithExitCode "docker" ["exec", testRedisContainerName, "redis-cli", "FLUSHDB"] ""
  case exitCode of
    ExitSuccess -> pure ()
    ExitFailure _ -> fail stderrText

resolvePublishedPort :: String -> IO Int
resolvePublishedPort containerId = do
  (exitCode, stdoutText, stderrText) <-
    readProcessWithExitCode "docker" ["port", containerId, "6379/tcp"] ""
  case exitCode of
    ExitFailure _ -> fail stderrText
    ExitSuccess ->
      case reads (reverse (takeWhile (/= ':') (reverse (trimLine stdoutText)))) of
        [(portNumber, "")] -> pure portNumber
        _ -> fail ("Unable to parse Docker Redis port from: " <> stdoutText)

waitForRedisReady :: RedisConfig -> IO ()
waitForRedisReady redisConfig = loop (20 :: Int)
  where
    loop attemptsRemaining
      | attemptsRemaining <= 0 =
          fail "Timed out waiting for temporary Redis container to become ready"
      | otherwise = do
          storeResult <- (try (newRedisSessionStore redisConfig) :: IO (Either SomeException RedisSessionStore))
          case storeResult of
            Right store -> do
              connectionResult <- testConnection store
              closeRedisSessionStore store
              case connectionResult of
                Right () -> pure ()
                Left _ -> retry
            Left _ -> retry
      where
        retry = do
          threadDelay 500000
          loop (attemptsRemaining - 1)

trimLine :: String -> String
trimLine = reverse . dropWhile (`elem` ['\n', '\r']) . reverse
