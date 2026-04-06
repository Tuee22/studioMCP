{-# LANGUAGE OverloadedStrings #-}

module Web.TypesSpec (spec) where

import Data.Aeson (decode, encode)
import qualified Data.ByteString.Lazy.Char8 as LBS
import Data.Time (getCurrentTime)
import StudioMCP.DAG.Summary (RunId (..))
import StudioMCP.DAG.Types (DagSpec (..))
import StudioMCP.Web.Types
import Test.Hspec

spec :: Spec
spec = do
  describe "WebSessionId" $ do
    it "generates unique session IDs" $ do
      id1 <- newWebSessionId
      id2 <- newWebSessionId
      id1 `shouldNotBe` id2

    it "serializes to JSON" $ do
      let sid = WebSessionId "web-test-123"
      encode sid `shouldBe` "\"web-test-123\""

    it "deserializes from JSON" $ do
      let json = "\"web-session-456\""
      decode json `shouldBe` Just (WebSessionId "web-session-456")

  describe "ChatRole" $ do
    it "serializes ChatUser" $ do
      encode ChatUser `shouldBe` "\"user\""

    it "serializes ChatAssistant" $ do
      encode ChatAssistant `shouldBe` "\"assistant\""

    it "serializes ChatSystem" $ do
      encode ChatSystem `shouldBe` "\"system\""

    it "deserializes roles" $ do
      decode "\"user\"" `shouldBe` Just ChatUser
      decode "\"assistant\"" `shouldBe` Just ChatAssistant
      decode "\"system\"" `shouldBe` Just ChatSystem

  describe "ChatMessage" $ do
    it "round-trips through JSON" $ do
      now <- getCurrentTime
      let msg =
            ChatMessage
              { cmRole = ChatUser,
                cmContent = "Hello, world!",
                cmTimestamp = Just now
              }
          encoded = encode msg
          decoded = decode encoded :: Maybe ChatMessage
      fmap cmRole decoded `shouldBe` Just ChatUser
      fmap cmContent decoded `shouldBe` Just "Hello, world!"

    it "handles missing timestamp" $ do
      let msg =
            ChatMessage
              { cmRole = ChatAssistant,
                cmContent = "Response",
                cmTimestamp = Nothing
              }
          encoded = encode msg
          decoded = decode encoded :: Maybe ChatMessage
      fmap cmTimestamp decoded `shouldBe` Just Nothing

  describe "UploadRequest" $ do
    it "round-trips through JSON" $ do
      let req =
            UploadRequest
              { urFileName = "video.mp4",
                urContentType = "video/mp4",
                urFileSize = 1024000,
                urMetadata = Just [("key", "value")]
              }
          encoded = encode req
          decoded = decode encoded :: Maybe UploadRequest
      fmap urFileName decoded `shouldBe` Just "video.mp4"
      fmap urFileSize decoded `shouldBe` Just 1024000

    it "handles missing metadata" $ do
      let req =
            UploadRequest
              { urFileName = "audio.wav",
                urContentType = "audio/wav",
                urFileSize = 500000,
                urMetadata = Nothing
              }
          encoded = encode req
          decoded = decode encoded :: Maybe UploadRequest
      fmap urMetadata decoded `shouldBe` Just Nothing

  describe "DownloadRequest" $ do
    it "round-trips through JSON" $ do
      let req =
            DownloadRequest
              { drArtifactId = "artifact-123",
                drVersion = Just "v2"
              }
          encoded = encode req
          decoded = decode encoded :: Maybe DownloadRequest
      fmap drArtifactId decoded `shouldBe` Just "artifact-123"
      fmap drVersion decoded `shouldBe` Just (Just "v2")

  describe "SessionLoginRequest" $ do
    it "round-trips through JSON" $ do
      let req =
            SessionLoginRequest
              { slrUsername = "testuser1"
              , slrPassword = "testpassword1"
              }
          encoded = encode req
          decoded = decode encoded :: Maybe SessionLoginRequest
      fmap slrUsername decoded `shouldBe` Just "testuser1"
      fmap slrPassword decoded `shouldBe` Just "testpassword1"

  describe "SessionLoginResponse" $ do
    it "round-trips through JSON without exposing a session identifier" $ do
      now <- getCurrentTime
      let response =
            SessionLoginResponse
              { slresSession =
                  SessionSummary
                    { ssSubjectId = "subject-1"
                    , ssTenantId = "tenant-1"
                    , ssExpiresAt = now
                    , ssCreatedAt = now
                    , ssLastActiveAt = now
                    }
              }
          encoded = encode response
          decoded = decode encoded :: Maybe SessionLoginResponse
      fmap (ssSubjectId . slresSession) decoded `shouldBe` Just "subject-1"
      fmap (ssTenantId . slresSession) decoded `shouldBe` Just "tenant-1"
      LBS.unpack encoded `shouldNotContain` "sessionId"

  describe "ChatRequest" $ do
    it "round-trips through JSON" $ do
      let req =
            ChatRequest
              { crMessages =
                  [ ChatMessage ChatUser "Hello" Nothing,
                    ChatMessage ChatAssistant "Hi there!" Nothing
                  ],
                crContext = Just "media-workflow"
              }
          encoded = encode req
          decoded = decode encoded :: Maybe ChatRequest
      fmap (length . crMessages) decoded `shouldBe` Just 2
      fmap crContext decoded `shouldBe` Just (Just "media-workflow")

  describe "RunSubmitRequest" $ do
    it "round-trips through JSON with input artifacts" $ do
      let req =
            RunSubmitRequest
              { rsrDagSpec = sampleDagSpec,
                rsrInputArtifacts = [("input1", "artifact-a"), ("input2", "artifact-b")]
              }
          encoded = encode req
          decoded = decode encoded :: Maybe RunSubmitRequest
      fmap rsrDagSpec decoded `shouldBe` Just sampleDagSpec
      fmap rsrInputArtifacts decoded `shouldBe` Just [("input1", "artifact-a"), ("input2", "artifact-b")]

  describe "RunStatusResponse" $ do
    it "round-trips through JSON" $ do
      now <- getCurrentTime
      let resp =
            RunStatusResponse
              { rsrRunId = RunId "run-123",
                rsrStatus = "running",
                rsrProgress = Just 50,
                rsrStartedAt = Just now,
                rsrCompletedAt = Nothing
              }
          encoded = encode resp
          decoded = decode encoded :: Maybe RunStatusResponse
      fmap rsrStatus decoded `shouldBe` Just "running"
      fmap rsrProgress decoded `shouldBe` Just (Just 50)

  describe "RunProgressEvent" $ do
    it "round-trips through JSON" $ do
      now <- getCurrentTime
      let evt =
            RunProgressEvent
              { rpeRunId = RunId "run-456",
                rpeNodeId = Just "node-1",
                rpeEventType = "node_started",
                rpeMessage = "Processing input",
                rpeProgress = Just 25,
                rpeTimestamp = now
              }
          encoded = encode evt
          decoded = decode encoded :: Maybe RunProgressEvent
      fmap rpeEventType decoded `shouldBe` Just "node_started"
      fmap rpeNodeId decoded `shouldBe` Just (Just "node-1")

  describe "PresignedUploadUrl" $ do
    it "round-trips through JSON" $ do
      now <- getCurrentTime
      let url =
            PresignedUploadUrl
              { puuUrl = "https://minio.local/upload/123?X-Amz-Signature=test",
                puuMethod = "PUT",
                puuHeaders = [("Content-Type", "video/mp4")],
                puuExpiresAt = now,
                puuArtifactId = "artifact-123"
              }
          encoded = encode url
          decoded = decode encoded :: Maybe PresignedUploadUrl
      fmap puuMethod decoded `shouldBe` Just "PUT"
      fmap puuArtifactId decoded `shouldBe` Just "artifact-123"

  describe "PresignedDownloadUrl" $ do
    it "round-trips through JSON" $ do
      now <- getCurrentTime
      let url =
            PresignedDownloadUrl
              { pduUrl = "https://minio.local/download/123?X-Amz-Signature=test",
                pduExpiresAt = now,
                pduContentType = "video/mp4",
                pduFileSize = 1024000
              }
          encoded = encode url
          decoded = decode encoded :: Maybe PresignedDownloadUrl
      fmap pduContentType decoded `shouldBe` Just "video/mp4"
      fmap pduFileSize decoded `shouldBe` Just 1024000

  describe "SessionRefreshResponse" $ do
    it "round-trips through JSON" $ do
      now <- getCurrentTime
      let session =
            SessionSummary
              { ssSubjectId = "subject-1"
              , ssTenantId = "tenant-1"
              , ssExpiresAt = now
              , ssCreatedAt = now
              , ssLastActiveAt = now
              }
          response =
            SessionRefreshResponse
              { srrSession = session
              , srrSuccess = True
              }
          encoded = encode response
          decoded = decode encoded :: Maybe SessionRefreshResponse
      fmap (ssSubjectId . srrSession) decoded `shouldBe` Just "subject-1"
      fmap srrSuccess decoded `shouldBe` Just True
      LBS.unpack encoded `shouldNotContain` "sessionId"

  describe "SessionMeResponse" $ do
    it "round-trips through JSON" $ do
      now <- getCurrentTime
      let response =
            SessionMeResponse
              { smerSession =
                  SessionSummary
                    { ssSubjectId = "subject-2"
                    , ssTenantId = "tenant-2"
                    , ssExpiresAt = now
                    , ssCreatedAt = now
                    , ssLastActiveAt = now
                    }
              }
          encoded = encode response
          decoded = decode encoded :: Maybe SessionMeResponse
      fmap (ssTenantId . smerSession) decoded `shouldBe` Just "tenant-2"

sampleDagSpec :: DagSpec
sampleDagSpec =
  DagSpec
    { dagName = "web-types-dag"
    , dagDescription = Just "Minimal DAG used for JSON coverage"
    , dagNodes = []
    }
