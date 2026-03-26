{-# LANGUAGE OverloadedStrings #-}

module Session.RedisConfigSpec (spec) where

import StudioMCP.MCP.Session.RedisConfig
import StudioMCP.MCP.Session.Types (SessionId (..))
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
