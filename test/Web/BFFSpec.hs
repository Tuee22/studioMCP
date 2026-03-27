{-# LANGUAGE OverloadedStrings #-}

module Web.BFFSpec (spec) where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, try)
import StudioMCP.Auth.Types (TenantId (..))
import Network.HTTP.Types (status400, status401, status403, status404, status500, status502)
import qualified Data.Text as T
import StudioMCP.Inference.ReferenceModel (ReferenceModelConfig (..))
import StudioMCP.DAG.Types (DagSpec (..))
import StudioMCP.MCP.Session.RedisConfig
import StudioMCP.MCP.Session.RedisStore
import StudioMCP.Storage.TenantStorage (TenantArtifact (..), defaultTenantStorageConfig, getTenantArtifact, newTenantStorageService)
import StudioMCP.Web.BFF
import StudioMCP.Web.Types
import System.Exit (ExitCode (..))
import System.Process (readProcessWithExitCode)
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
              { urArtifactId = Nothing,
                urFileName = "video.mp4",
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
              { urArtifactId = Nothing,
                urFileName = "video.mp4",
                urContentType = "video/mp4",
                urFileSize = 1000,
                urMetadata = Nothing
              }
      result <- requestUpload service (wsSessionId session) req
      case result of
        Right resp -> urpArtifactId resp `shouldSatisfy` not . T.null
        Left err -> expectationFailure $ "Failed to create upload: " ++ show err

    it "creates a new version when upload targets an existing artifact" $ do
      service <- newBFFService defaultBFFConfig
      Right session <- createWebSession service "user-123" "tenant-456" "token" Nothing
      Right firstUpload <-
        requestUpload
          service
          (wsSessionId session)
          UploadRequest
            { urArtifactId = Nothing,
              urFileName = "video.mp4",
              urContentType = "video/mp4",
              urFileSize = 1000,
              urMetadata = Nothing
            }
      Right secondUpload <-
        requestUpload
          service
          (wsSessionId session)
          UploadRequest
            { urArtifactId = Just (urpArtifactId firstUpload),
              urFileName = "video-v2.mp4",
              urContentType = "video/mp4",
              urFileSize = 2000,
              urMetadata = Nothing
            }
      urpArtifactId secondUpload `shouldBe` urpArtifactId firstUpload
      Right latestArtifact <-
        getTenantArtifact
          (bffTenantStorage service)
          (TenantId "tenant-456")
          (urpArtifactId firstUpload)
      taVersion latestArtifact `shouldBe` 2

    it "rejects disallowed content types" $ do
      service <- newBFFService defaultBFFConfig
      Right session <- createWebSession service "user-123" "tenant-456" "token" Nothing
      let req =
            UploadRequest
              { urArtifactId = Nothing,
                urFileName = "file.exe",
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
              { urArtifactId = Nothing,
                urFileName = "huge.mp4",
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
            { urArtifactId = Nothing
            , urFileName = "video.mp4"
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

  redisFixture <- runIO startRedisFixture
  let (containerId, redisConfig) = redisFixture
  afterAll_ (stopRedisFixture redisFixture) $
    before_ (flushRedisFixture containerId) $
      describe "Redis-backed browser session state" $ do
        it "shares sessions, uploads, and invalidation across BFF services" $ do
          tenantStorage <- newTenantStorageService defaultTenantStorageConfig
          let referenceModelConfig = ReferenceModelConfig "http://127.0.0.1:11434/api/generate"
          service1 <-
            newBFFServiceWithMcpClientAndRedis
              defaultBFFConfig
              redisConfig
              tenantStorage
              Nothing
              referenceModelConfig
          service2 <-
            newBFFServiceWithMcpClientAndRedis
              defaultBFFConfig
              redisConfig
              tenantStorage
              Nothing
              referenceModelConfig

          Right createdSession <-
            createWebSession service1 "user-123" "tenant-456" "access-token" (Just "refresh-token")

          sharedSession <- getWebSession service2 (wsSessionId createdSession)
          case sharedSession of
            Right retrieved -> do
              wsSubjectId retrieved `shouldBe` "user-123"
              wsTenantId retrieved `shouldBe` "tenant-456"
            Left err -> expectationFailure $ "Failed to read session from second BFF service: " ++ show err

          refreshedSession <- refreshWebSession service2 (wsSessionId createdSession) "new-token" (Just "new-refresh-token")
          case refreshedSession of
            Right refreshed -> wsAccessToken refreshed `shouldBe` "new-token"
            Left err -> expectationFailure $ "Failed to refresh session from second BFF service: " ++ show err

          reloadedSession <- getWebSession service1 (wsSessionId createdSession)
          case reloadedSession of
            Right retrieved -> wsAccessToken retrieved `shouldBe` "new-token"
            Left err -> expectationFailure $ "Failed to reload refreshed session from first BFF service: " ++ show err

          Right uploadResponse <-
            requestUpload
              service1
              (wsSessionId createdSession)
              UploadRequest
                { urArtifactId = Nothing
                , urFileName = "shared-video.mp4"
                , urContentType = "video/mp4"
                , urFileSize = 2048
                , urMetadata = Nothing
                }

          confirmUpload service2 (wsSessionId createdSession) (urpArtifactId uploadResponse)
            `shouldReturn` Right ()
          confirmUpload service1 (wsSessionId createdSession) (urpArtifactId uploadResponse)
            `shouldReturn` Left (ArtifactNotFound (urpArtifactId uploadResponse))

          invalidateWebSession service2 (wsSessionId createdSession) `shouldReturn` Right ()
          getWebSession service1 (wsSessionId createdSession)
            `shouldReturn` Left (SessionNotFound (wsSessionId createdSession))

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

startRedisFixture :: IO (String, RedisConfig)
startRedisFixture = do
  (exitCode, stdoutText, stderrText) <-
    readProcessWithExitCode "docker" ["run", "-d", "-P", "redis:7-alpine"] ""
  case exitCode of
    ExitFailure _ -> fail stderrText
    ExitSuccess -> do
      let containerId = trimLine stdoutText
      portNumber <- resolvePublishedPort containerId
      let redisConfig =
            defaultRedisConfig
              { rcHost = "127.0.0.1"
              , rcPort = portNumber
              }
      waitForRedisReady redisConfig
      pure (containerId, redisConfig)

stopRedisFixture :: (String, RedisConfig) -> IO ()
stopRedisFixture (containerId, _) = do
  _ <- readProcessWithExitCode "docker" ["rm", "-f", containerId] ""
  pure ()

flushRedisFixture :: String -> IO ()
flushRedisFixture containerId = do
  (exitCode, _, stderrText) <-
    readProcessWithExitCode "docker" ["exec", containerId, "redis-cli", "FLUSHDB"] ""
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
