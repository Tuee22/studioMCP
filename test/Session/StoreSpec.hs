{-# LANGUAGE OverloadedStrings #-}

module Session.StoreSpec (spec) where

import Data.Time (UTCTime, addUTCTime, getCurrentTime)
import StudioMCP.MCP.Session.Store
import StudioMCP.MCP.Session.Types (SessionId (..))
import Test.Hspec

spec :: Spec
spec = do
  describe "SessionStoreError" $ do
    it "can represent SessionNotFound" $ do
      let err = SessionNotFound (SessionId "test-123")
      show err `shouldContain` "SessionNotFound"

    it "can represent SessionAlreadyExists" $ do
      let err = SessionAlreadyExists (SessionId "test-123")
      show err `shouldContain` "SessionAlreadyExists"

    it "can represent StoreConnectionError" $ do
      let err = StoreConnectionError "connection failed"
      show err `shouldContain` "StoreConnectionError"

    it "can represent StoreTimeoutError" $ do
      let err = StoreTimeoutError "operation timed out"
      show err `shouldContain` "StoreTimeoutError"

    it "can represent LockAcquisitionFailed" $ do
      let err = LockAcquisitionFailed (SessionId "test-123")
      show err `shouldContain` "LockAcquisitionFailed"

    it "can represent LockNotHeld" $ do
      let err = LockNotHeld (SessionId "test-123")
      show err `shouldContain` "LockNotHeld"

    it "can represent SessionSerializationError" $ do
      let err = SessionSerializationError "invalid data"
      show err `shouldContain` "SessionSerializationError"

    it "can represent SessionDeserializationError" $ do
      let err = SessionDeserializationError "invalid data"
      show err `shouldContain` "SessionDeserializationError"

    it "can represent StoreUnavailable" $ do
      let err = StoreUnavailable "store offline"
      show err `shouldContain` "StoreUnavailable"

  describe "SubscriptionRecord" $ do
    it "can be created with required fields" $ do
      now <- getCurrentTime
      let sub =
            SubscriptionRecord
              { srResourceUri = "file:///test.txt",
                srSubscribedAt = now,
                srLastEventId = Nothing
              }
      srResourceUri sub `shouldBe` "file:///test.txt"
      srLastEventId sub `shouldBe` Nothing

    it "can include lastEventId" $ do
      now <- getCurrentTime
      let sub =
            SubscriptionRecord
              { srResourceUri = "file:///test.txt",
                srSubscribedAt = now,
                srLastEventId = Just "event-42"
              }
      srLastEventId sub `shouldBe` Just "event-42"

  describe "CursorPosition" $ do
    it "stores stream name and position" $ do
      now <- getCurrentTime
      let cursor =
            CursorPosition
              { cpStreamName = "workflow-events",
                cpPosition = "12345",
                cpUpdatedAt = now
              }
      cpStreamName cursor `shouldBe` "workflow-events"
      cpPosition cursor `shouldBe` "12345"

  describe "SessionLock" $ do
    it "tracks lock holder and expiration" $ do
      now <- getCurrentTime
      let expiresAt = addUTCTime 30 now
          lock =
            SessionLock
              { slSessionId = SessionId "session-123",
                slHolderPodId = "pod-abc",
                slAcquiredAt = now,
                slExpiresAt = expiresAt
              }
      slHolderPodId lock `shouldBe` "pod-abc"
      slExpiresAt lock `shouldSatisfy` (> now)
