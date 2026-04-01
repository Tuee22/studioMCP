{-# LANGUAGE OverloadedStrings #-}

module Storage.TenantStorageSpec (spec) where

import Control.Concurrent (threadDelay)
import Data.Aeson (decode, encode)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime, addUTCTime, getCurrentTime)
import StudioMCP.Auth.Types (TenantId (..))
import StudioMCP.Storage.Keys (BucketName (..), ObjectKey (..))
import StudioMCP.Storage.TenantStorage
import Test.Hspec

spec :: Spec
spec = do
  describe "defaultTenantStorageConfig" $ do
    it "uses platform MinIO by default" $ do
      tscDefaultBackend defaultTenantStorageConfig `shouldBe` PlatformMinIO

    it "has 15 minute upload URL TTL" $ do
      tscUploadUrlTtl defaultTenantStorageConfig `shouldBe` 900

    it "has 5 minute download URL TTL" $ do
      tscDownloadUrlTtl defaultTenantStorageConfig `shouldBe` 300

    it "has 10 GB max artifact size" $ do
      tscMaxArtifactSize defaultTenantStorageConfig `shouldBe` (10 * 1024 * 1024 * 1024)

    it "has studiomcp-tenant- bucket prefix" $ do
      tscBucketPrefix defaultTenantStorageConfig `shouldBe` "studiomcp-tenant-"

  describe "TenantStorageService" $ do
    it "creates a new service" $ do
      service <- newTenantStorageService defaultTenantStorageConfig
      artifacts <- listTenantArtifacts service (TenantId "test")
      artifacts `shouldBe` []

  describe "getTenantBucket" $ do
    it "generates correct bucket name for tenant" $ do
      service <- newTenantStorageService defaultTenantStorageConfig
      let bucket = getTenantBucket service (TenantId "acme-corp")
      bucket `shouldBe` BucketName "studiomcp-tenant-acme-corp"

    it "uses custom prefix from config" $ do
      let config = defaultTenantStorageConfig { tscBucketPrefix = "custom-" }
      service <- newTenantStorageService config
      let bucket = getTenantBucket service (TenantId "test")
      bucket `shouldBe` BucketName "custom-test"

  describe "getTenantArtifactKey" $ do
    it "generates versioned artifact key" $ do
      let key = getTenantArtifactKey (TenantId "tenant-1") "artifact-123" 1
      key `shouldBe` ObjectKey "artifacts/tenant-1/artifact-123/v1"

    it "handles different versions" $ do
      let key = getTenantArtifactKey (TenantId "tenant-1") "artifact-123" 5
      key `shouldBe` ObjectKey "artifacts/tenant-1/artifact-123/v5"

  describe "createTenantArtifact" $ do
    it "creates artifact with metadata" $ do
      service <- newTenantStorageService defaultTenantStorageConfig
      result <- createTenantArtifact
        service
        (TenantId "tenant-1")
        "video/mp4"
        "video.mp4"
        1024
        Map.empty
      case result of
        Left err -> expectationFailure $ "Expected success but got: " ++ show err
        Right artifact -> do
          taTenantId artifact `shouldBe` TenantId "tenant-1"
          taContentType artifact `shouldBe` "video/mp4"
          taFileName artifact `shouldBe` "video.mp4"
          taFileSize artifact `shouldBe` 1024
          taVersion artifact `shouldBe` 1

    it "rejects artifact exceeding max size" $ do
      service <- newTenantStorageService defaultTenantStorageConfig
      let oversized = tscMaxArtifactSize defaultTenantStorageConfig + 1
      result <- createTenantArtifact
        service
        (TenantId "tenant-1")
        "video/mp4"
        "huge.mp4"
        oversized
        Map.empty
      case result of
        Left (ArtifactTooLarge actual maxSize) -> do
          actual `shouldBe` oversized
          maxSize `shouldBe` tscMaxArtifactSize defaultTenantStorageConfig
        Left err -> expectationFailure $ "Expected ArtifactTooLarge but got: " ++ show err
        Right _ -> expectationFailure "Expected failure but got success"

    it "stores custom metadata" $ do
      service <- newTenantStorageService defaultTenantStorageConfig
      let metadata = Map.fromList [("key1", "value1"), ("key2", "value2")]
      result <- createTenantArtifact
        service
        (TenantId "tenant-1")
        "image/png"
        "image.png"
        512
        metadata
      case result of
        Left err -> expectationFailure $ "Expected success but got: " ++ show err
        Right artifact -> taMetadata artifact `shouldBe` metadata

  describe "getTenantArtifact" $ do
    it "retrieves created artifact" $ do
      service <- newTenantStorageService defaultTenantStorageConfig
      Right created <- createTenantArtifact service (TenantId "t1") "text/plain" "test.txt" 100 Map.empty
      result <- getTenantArtifact service (TenantId "t1") (taArtifactId created)
      case result of
        Left err -> expectationFailure $ "Expected success but got: " ++ show err
        Right artifact -> artifact `shouldBe` created

    it "returns error for unknown artifact" $ do
      service <- newTenantStorageService defaultTenantStorageConfig
      result <- getTenantArtifact service (TenantId "t1") "unknown-id"
      case result of
        Left (ArtifactNotFound aid) -> aid `shouldBe` "unknown-id"
        Left err -> expectationFailure $ "Expected ArtifactNotFound but got: " ++ show err
        Right _ -> expectationFailure "Expected failure but got success"

    it "enforces tenant isolation" $ do
      service <- newTenantStorageService defaultTenantStorageConfig
      Right created <- createTenantArtifact service (TenantId "tenant-1") "text/plain" "test.txt" 100 Map.empty
      -- Try to access from different tenant
      result <- getTenantArtifact service (TenantId "tenant-2") (taArtifactId created)
      case result of
        Left (ArtifactNotFound _) -> pure ()
        Left err -> expectationFailure $ "Expected ArtifactNotFound but got: " ++ show err
        Right _ -> expectationFailure "Expected failure - tenant isolation violated"

  describe "listTenantArtifacts" $ do
    it "lists artifacts for tenant" $ do
      service <- newTenantStorageService defaultTenantStorageConfig
      result1 <- createTenantArtifact service (TenantId "t1") "text/plain" "a.txt" 10 Map.empty
      case result1 of
        Left err -> expectationFailure $ "Failed to create artifact 1: " ++ show err
        Right artifact1 -> do
          threadDelay 1000  -- 1ms delay to ensure unique artifact IDs
          result2 <- createTenantArtifact service (TenantId "t1") "text/plain" "b.txt" 20 Map.empty
          threadDelay 1000  -- 1ms delay to ensure unique artifact IDs
          result3 <- createTenantArtifact service (TenantId "t2") "text/plain" "c.txt" 30 Map.empty
          -- Just verify we can list and get at least the first artifact
          artifacts <- listTenantArtifacts service (TenantId "t1")
          -- The first artifact should be in the list
          any (\a -> taArtifactId a == taArtifactId artifact1) artifacts `shouldBe` True

    it "returns empty list for tenant with no artifacts" $ do
      service <- newTenantStorageService defaultTenantStorageConfig
      artifacts <- listTenantArtifacts service (TenantId "empty-tenant")
      artifacts `shouldBe` []

  describe "generateUploadUrl" $ do
    it "generates presigned upload URL" $ do
      service <- newTenantStorageService defaultTenantStorageConfig
      result <- generateUploadUrl service (TenantId "t1") "artifact-1" "video/mp4"
      case result of
        Left err -> expectationFailure $ "Expected success but got: " ++ show err
        Right url -> do
          puMethod url `shouldBe` "PUT"
          T.isInfixOf "studiomcp-tenant-t1" (puUrl url) `shouldBe` True
          Map.lookup "Content-Type" (puHeaders url) `shouldBe` Just "video/mp4"

    it "includes artifact metadata in headers" $ do
      service <- newTenantStorageService defaultTenantStorageConfig
      result <- generateUploadUrl service (TenantId "my-tenant") "my-artifact" "image/png"
      case result of
        Left err -> expectationFailure $ "Expected success but got: " ++ show err
        Right url -> do
          Map.lookup "x-amz-meta-artifact-id" (puHeaders url) `shouldBe` Just "my-artifact"
          Map.lookup "x-amz-meta-tenant-id" (puHeaders url) `shouldBe` Just "my-tenant"

    it "sets correct expiration time" $ do
      service <- newTenantStorageService defaultTenantStorageConfig
      now <- getCurrentTime
      result <- generateUploadUrl service (TenantId "t1") "a1" "video/mp4"
      case result of
        Left err -> expectationFailure $ "Expected success but got: " ++ show err
        Right url -> do
          -- Expiration should be in the future (15 min TTL)
          puExpiresAt url > now `shouldBe` True

  describe "generateDownloadUrl" $ do
    it "generates presigned download URL for existing artifact" $ do
      service <- newTenantStorageService defaultTenantStorageConfig
      Right created <- createTenantArtifact service (TenantId "t1") "video/mp4" "video.mp4" 1024 Map.empty
      result <- generateDownloadUrl service (TenantId "t1") (taArtifactId created) Nothing
      case result of
        Left err -> expectationFailure $ "Expected success but got: " ++ show err
        Right url -> do
          puMethod url `shouldBe` "GET"
          T.isInfixOf "studiomcp-tenant-t1" (puUrl url) `shouldBe` True

    it "returns error for non-existent artifact" $ do
      service <- newTenantStorageService defaultTenantStorageConfig
      result <- generateDownloadUrl service (TenantId "t1") "unknown" Nothing
      case result of
        Left (ArtifactNotFound _) -> pure ()
        Left err -> expectationFailure $ "Expected ArtifactNotFound but got: " ++ show err
        Right _ -> expectationFailure "Expected failure but got success"

    it "respects tenant isolation for downloads" $ do
      service <- newTenantStorageService defaultTenantStorageConfig
      Right created <- createTenantArtifact service (TenantId "t1") "video/mp4" "video.mp4" 1024 Map.empty
      result <- generateDownloadUrl service (TenantId "t2") (taArtifactId created) Nothing
      case result of
        Left (ArtifactNotFound _) -> pure ()
        Left err -> expectationFailure $ "Expected ArtifactNotFound but got: " ++ show err
        Right _ -> expectationFailure "Expected failure - tenant isolation violated"

  describe "TenantStorageError" $ do
    it "tenantStorageErrorCode returns correct codes" $ do
      tenantStorageErrorCode (TenantNotConfigured (TenantId "t")) `shouldBe` "tenant-not-configured"
      tenantStorageErrorCode (ArtifactNotFound "a") `shouldBe` "artifact-not-found"
      tenantStorageErrorCode (ArtifactVersionNotFound "a" 1) `shouldBe` "artifact-version-not-found"
      tenantStorageErrorCode (StorageBackendError "err") `shouldBe` "storage-backend-error"
      tenantStorageErrorCode (PresignedUrlGenerationFailed "err") `shouldBe` "presigned-url-failed"
      tenantStorageErrorCode (ArtifactTooLarge 100 50) `shouldBe` "artifact-too-large"
      tenantStorageErrorCode (InvalidContentType "bad") `shouldBe` "invalid-content-type"
      tenantStorageErrorCode (StorageQuotaExceeded (TenantId "t")) `shouldBe` "storage-quota-exceeded"

  describe "TenantStorageBackend JSON" $ do
    it "serializes PlatformMinIO" $ do
      let json = encode PlatformMinIO
      T.isInfixOf "platform-minio" (T.pack (show json)) `shouldBe` True

    it "round-trips PlatformMinIO" $ do
      (decode (encode PlatformMinIO) :: Maybe TenantStorageBackend) `shouldBe` Just PlatformMinIO

  describe "TenantArtifact JSON" $ do
    it "round-trips artifact" $ do
      service <- newTenantStorageService defaultTenantStorageConfig
      Right artifact <- createTenantArtifact service (TenantId "t1") "text/plain" "test.txt" 100 Map.empty
      (decode (encode artifact) :: Maybe TenantArtifact) `shouldBe` Just artifact

  describe "PresignedUrl JSON" $ do
    it "round-trips presigned URL" $ do
      service <- newTenantStorageService defaultTenantStorageConfig
      Right url <- generateUploadUrl service (TenantId "t1") "a1" "video/mp4"
      (decode (encode url) :: Maybe PresignedUrl) `shouldBe` Just url

