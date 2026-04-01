{-# LANGUAGE OverloadedStrings #-}

module Web.BFFSpec (spec) where

import Network.HTTP.Types (status400, status401, status403, status404, status500, status502)
import qualified Data.Text as T
import StudioMCP.DAG.Types (DagSpec (..))
import StudioMCP.Web.BFF
import StudioMCP.Web.Types
import Test.Hspec

spec :: Spec
spec = do
  describe "defaultBFFConfig" $ do
    it "has sensible MCP endpoint" $ do
      bffMcpEndpoint defaultBFFConfig `shouldBe` "http://localhost:3000"

    it "has 1 hour session TTL" $ do
      bffSessionTtlSeconds defaultBFFConfig `shouldBe` 3600

    it "has 15 minute upload TTL" $ do
      bffUploadTtlSeconds defaultBFFConfig `shouldBe` 900

    it "has 5 minute download TTL" $ do
      bffDownloadTtlSeconds defaultBFFConfig `shouldBe` 300

    it "has 10 GB max upload size" $ do
      bffMaxUploadSize defaultBFFConfig `shouldBe` 10 * 1024 * 1024 * 1024

    it "allows video content types" $ do
      bffAllowedContentTypes defaultBFFConfig `shouldSatisfy` elem "video/mp4"
      bffAllowedContentTypes defaultBFFConfig `shouldSatisfy` elem "video/quicktime"

    it "allows audio content types" $ do
      bffAllowedContentTypes defaultBFFConfig `shouldSatisfy` elem "audio/mpeg"
      bffAllowedContentTypes defaultBFFConfig `shouldSatisfy` elem "audio/wav"

    it "allows image content types" $ do
      bffAllowedContentTypes defaultBFFConfig `shouldSatisfy` elem "image/jpeg"
      bffAllowedContentTypes defaultBFFConfig `shouldSatisfy` elem "image/png"

  describe "BFFError" $ do
    it "maps SessionNotFound to 401" $ do
      bffErrorToHttpStatus (SessionNotFound (WebSessionId "test")) `shouldBe` status401

    it "maps SessionExpired to 401" $ do
      bffErrorToHttpStatus (SessionExpired (WebSessionId "test")) `shouldBe` status401

    it "maps InvalidCredentials to 401" $ do
      bffErrorToHttpStatus (InvalidCredentials "bad password") `shouldBe` status401

    it "maps Unauthorized to 401" $ do
      bffErrorToHttpStatus (Unauthorized "not allowed") `shouldBe` status401

    it "maps Forbidden to 403" $ do
      bffErrorToHttpStatus (Forbidden "access denied") `shouldBe` status403

    it "maps ArtifactNotFound to 404" $ do
      bffErrorToHttpStatus (ArtifactNotFound "artifact-123") `shouldBe` status404

    it "maps InvalidRequest to 400" $ do
      bffErrorToHttpStatus (InvalidRequest "bad request") `shouldBe` status400

    it "maps McpServiceError to 502" $ do
      bffErrorToHttpStatus (McpServiceError "service error") `shouldBe` status502

    it "maps InternalError to 500" $ do
      bffErrorToHttpStatus (InternalError "internal error") `shouldBe` status500

  describe "newBFFService" $ do
    it "creates a new service" $ do
      service <- newBFFService defaultBFFConfig
      bffConfig service `shouldBe` defaultBFFConfig

  describe "Session Management" $ do
    it "creates a new session" $ do
      service <- newBFFService defaultBFFConfig
      result <- createWebSession service "user-123" "tenant-456" "access-token" (Just "refresh-token")
      case result of
        Right session -> do
          wsSubjectId session `shouldBe` "user-123"
          wsTenantId session `shouldBe` "tenant-456"
        Left err -> expectationFailure $ "Failed to create session: " ++ show err

    it "retrieves a created session" $ do
      service <- newBFFService defaultBFFConfig
      Right session <- createWebSession service "user-123" "tenant-456" "token" Nothing
      result <- getWebSession service (wsSessionId session)
      case result of
        Right retrieved -> wsSubjectId retrieved `shouldBe` "user-123"
        Left err -> expectationFailure $ "Failed to get session: " ++ show err

    it "returns error for non-existent session" $ do
      service <- newBFFService defaultBFFConfig
      result <- getWebSession service (WebSessionId "nonexistent")
      case result of
        Left (SessionNotFound _) -> pure ()
        other -> expectationFailure $ "Expected SessionNotFound, got: " ++ show other

    it "refreshes a session" $ do
      service <- newBFFService defaultBFFConfig
      Right session <- createWebSession service "user-123" "tenant-456" "old-token" Nothing
      result <- refreshWebSession service (wsSessionId session) "new-token" (Just "new-refresh")
      case result of
        Right refreshed -> wsAccessToken refreshed `shouldBe` "new-token"
        Left err -> expectationFailure $ "Failed to refresh session: " ++ show err

    it "invalidates a session" $ do
      service <- newBFFService defaultBFFConfig
      Right session <- createWebSession service "user-123" "tenant-456" "token" Nothing
      _ <- invalidateWebSession service (wsSessionId session)
      result <- getWebSession service (wsSessionId session)
      case result of
        Left (SessionNotFound _) -> pure ()
        other -> expectationFailure $ "Expected SessionNotFound, got: " ++ show other

  describe "Upload Operations" $ do
    it "rejects upload without session" $ do
      service <- newBFFService defaultBFFConfig
      let req =
            UploadRequest
              { urFileName = "video.mp4",
                urContentType = "video/mp4",
                urFileSize = 1000,
                urMetadata = Nothing
              }
      result <- requestUpload service (WebSessionId "nonexistent") req
      case result of
        Left (SessionNotFound _) -> pure ()
        other -> expectationFailure $ "Expected SessionNotFound, got: " ++ show other

    it "creates upload request for valid session" $ do
      service <- newBFFService defaultBFFConfig
      Right session <- createWebSession service "user-123" "tenant-456" "token" Nothing
      let req =
            UploadRequest
              { urFileName = "video.mp4",
                urContentType = "video/mp4",
                urFileSize = 1000,
                urMetadata = Nothing
              }
      result <- requestUpload service (wsSessionId session) req
      case result of
        Right resp -> urpArtifactId resp `shouldSatisfy` not . T.null
        Left err -> expectationFailure $ "Failed to create upload: " ++ show err

    it "rejects disallowed content types" $ do
      service <- newBFFService defaultBFFConfig
      Right session <- createWebSession service "user-123" "tenant-456" "token" Nothing
      let req =
            UploadRequest
              { urFileName = "file.exe",
                urContentType = "application/x-msdownload",
                urFileSize = 1000,
                urMetadata = Nothing
              }
      result <- requestUpload service (wsSessionId session) req
      case result of
        Left (InvalidRequest _) -> pure ()
        other -> expectationFailure $ "Expected InvalidRequest, got: " ++ show other

    it "rejects oversized uploads" $ do
      service <- newBFFService defaultBFFConfig
      Right session <- createWebSession service "user-123" "tenant-456" "token" Nothing
      let req =
            UploadRequest
              { urFileName = "huge.mp4",
                urContentType = "video/mp4",
                urFileSize = 100 * 1024 * 1024 * 1024, -- 100 GB
                urMetadata = Nothing
              }
      result <- requestUpload service (wsSessionId session) req
      case result of
        Left (InvalidRequest _) -> pure ()
        other -> expectationFailure $ "Expected InvalidRequest, got: " ++ show other

  describe "Download Operations" $ do
    it "rejects download without session" $ do
      service <- newBFFService defaultBFFConfig
      let req = DownloadRequest {drArtifactId = "artifact-123", drVersion = Nothing}
      result <- requestDownload service (WebSessionId "nonexistent") req
      case result of
        Left (SessionNotFound _) -> pure ()
        other -> expectationFailure $ "Expected SessionNotFound, got: " ++ show other

    it "creates download request for valid session" $ do
      service <- newBFFService defaultBFFConfig
      Right session <- createWebSession service "user-123" "tenant-456" "token" Nothing
      Right uploadResponse <-
        requestUpload
          service
          (wsSessionId session)
          UploadRequest
            { urFileName = "video.mp4"
            , urContentType = "video/mp4"
            , urFileSize = 1000
            , urMetadata = Nothing
            }
      let req =
            DownloadRequest
              { drArtifactId = urpArtifactId uploadResponse
              , drVersion = Nothing
              }
      result <- requestDownload service (wsSessionId session) req
      case result of
        Right resp -> drpArtifactId resp `shouldBe` urpArtifactId uploadResponse
        Left err -> expectationFailure $ "Failed to create download: " ++ show err

  describe "Chat Operations" $ do
    it "rejects chat without session" $ do
      service <- newBFFService defaultBFFConfig
      let req =
            ChatRequest
              { crMessages = [ChatMessage ChatUser "Hello" Nothing],
                crContext = Nothing
              }
      result <- sendChatMessage service (WebSessionId "nonexistent") req
      case result of
        Left (SessionNotFound _) -> pure ()
        other -> expectationFailure $ "Expected SessionNotFound, got: " ++ show other

    it "sends chat message for valid session" $ do
      service <- newBFFService defaultBFFConfig
      Right session <- createWebSession service "user-123" "tenant-456" "token" Nothing
      let req =
            ChatRequest
              { crMessages = [ChatMessage ChatUser "Hello" Nothing],
                crContext = Nothing
              }
      result <- sendChatMessage service (wsSessionId session) req
      case result of
        Right resp -> cmRole (crpMessage resp) `shouldBe` ChatAssistant
        Left err -> expectationFailure $ "Failed to send chat: " ++ show err

  describe "Run Operations" $ do
    it "rejects run submission without session" $ do
      service <- newBFFService defaultBFFConfig
      result <- submitRun service (WebSessionId "nonexistent") sampleRunSubmitRequest
      case result of
        Left (SessionNotFound _) -> pure ()
        other -> expectationFailure $ "Expected SessionNotFound, got: " ++ show other

    it "tracks run status" $ do
      service <- newBFFService defaultBFFConfig
      Right session <- createWebSession service "user-123" "tenant-456" "token" Nothing
      submission <- submitRun service (wsSessionId session) sampleRunSubmitRequest
      case submission of
        Left err -> expectationFailure $ "Failed to submit run: " ++ show err
        Right submitted -> do
          status <- getRunStatus service (wsSessionId session) (rsrRunId submitted)
          case status of
            Right tracked -> do
              rsrRunId tracked `shouldBe` rsrRunId submitted
              rsrStatus tracked `shouldBe` "submitted"
            Left err -> expectationFailure $ "Failed to fetch run status: " ++ show err

sampleDagSpec :: DagSpec
sampleDagSpec =
  DagSpec
    { dagName = "bff-test-dag"
    , dagDescription = Just "Minimal DAG used by BFF specs"
    , dagNodes = []
    }

sampleRunSubmitRequest :: RunSubmitRequest
sampleRunSubmitRequest =
  RunSubmitRequest
    { rsrDagSpec = sampleDagSpec
    , rsrInputArtifacts = []
    }
