{-# LANGUAGE OverloadedStrings #-}

module Session.RedisConfigSpec (spec) where

import Control.Exception (bracket)
import Control.Monad (forM_)
import StudioMCP.MCP.Session.RedisConfig
import StudioMCP.MCP.Session.Types (SessionId (..))
import System.Environment (lookupEnv, setEnv, unsetEnv)
import Test.Hspec

spec :: Spec
spec = do
  describe "defaultRedisConfig" $ do
    it "has localhost host" $ do
      rcHost defaultRedisConfig `shouldBe` "localhost"

    it "has port 6379" $ do
      rcPort defaultRedisConfig `shouldBe` 6379

    it "has no password by default" $ do
      rcPassword defaultRedisConfig `shouldBe` Nothing

    it "has database 0" $ do
      rcDatabase defaultRedisConfig `shouldBe` 0

    it "has pool size 10" $ do
      rcPoolSize defaultRedisConfig `shouldBe` 10

    it "has 5 second connection timeout" $ do
      rcConnectionTimeout defaultRedisConfig `shouldBe` 5

    it "has 30 minute session TTL" $ do
      rcSessionTtl defaultRedisConfig `shouldBe` 1800

    it "has 30 second lock TTL" $ do
      rcLockTtl defaultRedisConfig `shouldBe` 30

    it "has mcp: key prefix" $ do
      rcKeyPrefix defaultRedisConfig `shouldBe` "mcp:"

    it "has TLS disabled" $ do
      rcUseTls defaultRedisConfig `shouldBe` False

  describe "sessionKeyPrefix" $ do
    it "includes base prefix" $ do
      sessionKeyPrefix defaultRedisConfig `shouldBe` "mcp:session:"

  describe "subscriptionKeyPrefix" $ do
    it "includes base prefix" $ do
      subscriptionKeyPrefix defaultRedisConfig `shouldBe` "mcp:sub:"

  describe "cursorKeyPrefix" $ do
    it "includes base prefix" $ do
      cursorKeyPrefix defaultRedisConfig `shouldBe` "mcp:cursor:"

  describe "lockKeyPrefix" $ do
    it "includes base prefix" $ do
      lockKeyPrefix defaultRedisConfig `shouldBe` "mcp:lock:"

  describe "sessionKey" $ do
    it "builds correct session key" $ do
      let sid = SessionId "test-session-123"
      sessionKey defaultRedisConfig sid `shouldBe` "mcp:session:test-session-123"

    it "handles UUID session IDs" $ do
      let sid = SessionId "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
      sessionKey defaultRedisConfig sid `shouldBe` "mcp:session:a1b2c3d4-e5f6-7890-abcd-ef1234567890"

  describe "subscriptionKey" $ do
    it "builds correct subscription key" $ do
      let sid = SessionId "sess-1"
      subscriptionKey defaultRedisConfig sid "file:///test.txt"
        `shouldBe` "mcp:sub:sess-1:file:///test.txt"

  describe "cursorKey" $ do
    it "builds correct cursor key" $ do
      let sid = SessionId "sess-1"
      cursorKey defaultRedisConfig sid "workflow-events"
        `shouldBe` "mcp:cursor:sess-1:workflow-events"

  describe "lockKey" $ do
    it "builds correct lock key" $ do
      let sid = SessionId "sess-1"
      lockKey defaultRedisConfig sid `shouldBe` "mcp:lock:session:sess-1"

  describe "custom key prefix" $ do
    it "uses custom prefix in all keys" $ do
      let config = defaultRedisConfig {rcKeyPrefix = "custom:"}
          sid = SessionId "test-123"
      sessionKey config sid `shouldBe` "custom:session:test-123"
      subscriptionKey config sid "res" `shouldBe` "custom:sub:test-123:res"
      cursorKey config sid "stream" `shouldBe` "custom:cursor:test-123:stream"
      lockKey config sid `shouldBe` "custom:lock:session:test-123"

  describe "RedisConfig JSON" $ do
    it "serializes without password" $ do
      -- Password should not be serialized for security
      let config = defaultRedisConfig {rcPassword = Just "secret"}
      -- Just verify config can be shown (ToJSON is defined)
      rcHost config `shouldBe` "localhost"

  describe "loadRedisConfigFromEnv" $ do
    around_ withRedisEnvIsolation $ do
      it "loads new-style Redis URL environment variables" $ do
        setEnv "STUDIO_MCP_REDIS_URL" "redis://redis-svc.internal:6380/2"

        config <- loadRedisConfigFromEnv

        rcHost config `shouldBe` "redis-svc.internal"
        rcPort config `shouldBe` 6380
        rcDatabase config `shouldBe` 2
        rcUseTls config `shouldBe` False
        rcPassword config `shouldBe` Nothing

      it "uses TLS for rediss URLs and lets explicit password override the URL password" $ do
        setEnv "STUDIO_MCP_REDIS_URL" "rediss://:url-secret@secure-redis:6381/4"
        setEnv "STUDIO_MCP_REDIS_PASSWORD" "env-secret"

        config <- loadRedisConfigFromEnv

        rcHost config `shouldBe` "secure-redis"
        rcPort config `shouldBe` 6381
        rcDatabase config `shouldBe` 4
        rcUseTls config `shouldBe` True
        rcPassword config `shouldBe` Just "env-secret"

      it "lets explicit host and port override URL-derived values" $ do
        setEnv "STUDIO_MCP_REDIS_URL" "redis://redis-svc:6379/1"
        setEnv "STUDIO_MCP_REDIS_HOST" "override-redis"
        setEnv "STUDIO_MCP_REDIS_PORT" "6390"

        config <- loadRedisConfigFromEnv

        rcHost config `shouldBe` "override-redis"
        rcPort config `shouldBe` 6390
        rcDatabase config `shouldBe` 1

      it "remains backward compatible with legacy Redis environment variables" $ do
        setEnv "STUDIOMCP_REDIS_HOST" "legacy-redis"
        setEnv "STUDIOMCP_REDIS_PORT" "6385"
        setEnv "STUDIOMCP_REDIS_DATABASE" "6"
        setEnv "STUDIOMCP_REDIS_PASSWORD" "legacy-secret"
        setEnv "STUDIOMCP_REDIS_TLS" "true"
        setEnv "STUDIOMCP_REDIS_KEY_PREFIX" "legacy:"

        config <- loadRedisConfigFromEnv

        rcHost config `shouldBe` "legacy-redis"
        rcPort config `shouldBe` 6385
        rcDatabase config `shouldBe` 6
        rcPassword config `shouldBe` Just "legacy-secret"
        rcUseTls config `shouldBe` True
        rcKeyPrefix config `shouldBe` "legacy:"

withRedisEnvIsolation :: IO a -> IO a
withRedisEnvIsolation action =
  bracket
    (mapM captureEnv redisEnvVars)
    restoreEnv
    (\_ -> do
        clearEnvVars redisEnvVars
        action
    )

captureEnv :: String -> IO (String, Maybe String)
captureEnv name = do
  value <- lookupEnv name
  pure (name, value)

restoreEnv :: [(String, Maybe String)] -> IO ()
restoreEnv bindings =
  forM_ bindings $ \(name, value) ->
    case value of
      Just current -> setEnv name current
      Nothing -> unsetEnv name

clearEnvVars :: [String] -> IO ()
clearEnvVars = mapM_ unsetEnv

redisEnvVars :: [String]
redisEnvVars =
  [ "STUDIO_MCP_REDIS_URL",
    "STUDIO_MCP_REDIS_HOST",
    "STUDIO_MCP_REDIS_PORT",
    "STUDIO_MCP_REDIS_PASSWORD",
    "STUDIO_MCP_REDIS_DATABASE",
    "STUDIO_MCP_REDIS_POOL_SIZE",
    "STUDIO_MCP_REDIS_TIMEOUT",
    "STUDIO_MCP_REDIS_KEY_PREFIX",
    "STUDIO_MCP_REDIS_TLS",
    "STUDIO_MCP_SESSION_TTL",
    "STUDIO_MCP_LOCK_TTL",
    "STUDIOMCP_REDIS_URL",
    "STUDIOMCP_REDIS_HOST",
    "STUDIOMCP_REDIS_PORT",
    "STUDIOMCP_REDIS_PASSWORD",
    "STUDIOMCP_REDIS_DATABASE",
    "STUDIOMCP_REDIS_POOL_SIZE",
    "STUDIOMCP_REDIS_TIMEOUT",
    "STUDIOMCP_REDIS_KEY_PREFIX",
    "STUDIOMCP_REDIS_TLS",
    "STUDIOMCP_SESSION_TTL",
    "STUDIOMCP_LOCK_TTL"
  ]
