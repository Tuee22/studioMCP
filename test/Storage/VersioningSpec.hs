{-# LANGUAGE OverloadedStrings #-}

module Storage.VersioningSpec (spec) where

import qualified Data.Map.Strict as Map
import Control.Concurrent (threadDelay)
import StudioMCP.Auth.Types (SubjectId (..), TenantId (..))
import StudioMCP.Storage.ContentAddressed (ContentAddress (..))
import StudioMCP.Storage.Versioning
import Test.Hspec

spec :: Spec
spec = do
  describe "VersionId" $ do
    it "can be created from text" $ do
      let vid = VersionId "v1"
      unVersionId vid `shouldBe` "v1"

    it "can be compared for equality" $ do
      VersionId "v1" `shouldBe` VersionId "v1"
      VersionId "v1" `shouldNotBe` VersionId "v2"

  describe "VersioningPolicy" $ do
    it "has default policy with ImmutableVersions" $ do
      vpRule defaultVersioningPolicy `shouldBe` ImmutableVersions

    it "has no max versions by default" $ do
      vpMaxVersions defaultVersioningPolicy `shouldBe` Nothing

    it "requires content address verification by default" $ do
      vpRequireContentAddressVerification defaultVersioningPolicy `shouldBe` True

  describe "ImmutabilityError" $ do
    it "has error codes for each type" $ do
      immutabilityErrorCode (VersionIsImmutable (VersionId "v1")) `shouldBe` "version-immutable"
      immutabilityErrorCode (VersionNotFound (VersionId "v1")) `shouldBe` "version-not-found"
      immutabilityErrorCode (VersionAlreadyExists (VersionId "v1")) `shouldBe` "version-exists"
      immutabilityErrorCode (ArtifactVersionsNotFound "art1") `shouldBe` "artifact-versions-not-found"
      immutabilityErrorCode (InvalidVersionChain "a" "b") `shouldBe` "invalid-version-chain"
      immutabilityErrorCode (ContentAddressMismatch (VersionId "v1") (ContentAddress "a") (ContentAddress "b")) `shouldBe` "content-address-mismatch"

  describe "VersioningService" $ do
    it "can be created with default policy" $ do
      service <- newVersioningService defaultVersioningPolicy
      vsPolicy service `shouldBe` defaultVersioningPolicy

  describe "createInitialVersion" $ do
    it "creates version 1 for new artifact" $ do
      service <- newVersioningService defaultVersioningPolicy
      result <- createInitialVersion service "artifact-1"
        (ContentAddress "sha256:abc") 1000 "text/plain"
        (SubjectId "user-1") (TenantId "tenant-1") Map.empty
      case result of
        Right version -> do
          avVersionNumber version `shouldBe` 1
          avArtifactId version `shouldBe` "artifact-1"
        Left err -> expectationFailure $ "Expected success but got: " ++ show err

    it "returns error for duplicate artifact" $ do
      service <- newVersioningService defaultVersioningPolicy
      _ <- createInitialVersion service "artifact-1"
        (ContentAddress "sha256:abc") 1000 "text/plain"
        (SubjectId "user-1") (TenantId "tenant-1") Map.empty
      result <- createInitialVersion service "artifact-1"
        (ContentAddress "sha256:def") 2000 "text/plain"
        (SubjectId "user-1") (TenantId "tenant-1") Map.empty
      case result of
        Left (VersionAlreadyExists _) -> pure ()
        _ -> expectationFailure "Expected VersionAlreadyExists error"

  describe "createNewVersion" $ do
    it "increments version number" $ do
      service <- newVersioningService defaultVersioningPolicy
      _ <- createInitialVersion service "artifact-1"
        (ContentAddress "sha256:abc") 1000 "text/plain"
        (SubjectId "user-1") (TenantId "tenant-1") Map.empty
      result <- createNewVersion service "artifact-1"
        (ContentAddress "sha256:def") 2000 "text/plain"
        (SubjectId "user-1") Map.empty
      case result of
        Right version -> avVersionNumber version `shouldBe` 2
        Left err -> expectationFailure $ "Expected success but got: " ++ show err

    it "returns error for non-existent artifact" $ do
      service <- newVersioningService defaultVersioningPolicy
      result <- createNewVersion service "nonexistent"
        (ContentAddress "sha256:abc") 1000 "text/plain"
        (SubjectId "user-1") Map.empty
      case result of
        Left (ArtifactVersionsNotFound _) -> pure ()
        _ -> expectationFailure "Expected ArtifactVersionsNotFound error"

  describe "getVersion" $ do
    it "retrieves created version" $ do
      service <- newVersioningService defaultVersioningPolicy
      Right created <- createInitialVersion service "artifact-1"
        (ContentAddress "sha256:abc") 1000 "text/plain"
        (SubjectId "user-1") (TenantId "tenant-1") Map.empty
      result <- getVersion service (avVersionId created)
      case result of
        Right version -> version `shouldBe` created
        Left err -> expectationFailure $ "Expected success but got: " ++ show err

    it "returns error for non-existent version" $ do
      service <- newVersioningService defaultVersioningPolicy
      result <- getVersion service (VersionId "nonexistent")
      case result of
        Left (VersionNotFound _) -> pure ()
        _ -> expectationFailure "Expected VersionNotFound error"

  describe "getLatestVersion" $ do
    it "returns most recent version" $ do
      service <- newVersioningService defaultVersioningPolicy
      _ <- createInitialVersion service "artifact-1"
        (ContentAddress "sha256:abc") 1000 "text/plain"
        (SubjectId "user-1") (TenantId "tenant-1") Map.empty
      _ <- createNewVersion service "artifact-1"
        (ContentAddress "sha256:def") 2000 "text/plain"
        (SubjectId "user-1") Map.empty
      result <- getLatestVersion service "artifact-1"
      case result of
        Right version -> avVersionNumber version `shouldBe` 2
        Left err -> expectationFailure $ "Expected success but got: " ++ show err

  describe "listVersions" $ do
    it "returns all versions for artifact" $ do
      service <- newVersioningService defaultVersioningPolicy
      _ <- createInitialVersion service "artifact-1"
        (ContentAddress "sha256:abc") 1000 "text/plain"
        (SubjectId "user-1") (TenantId "tenant-1") Map.empty
      _ <- createNewVersion service "artifact-1"
        (ContentAddress "sha256:def") 2000 "text/plain"
        (SubjectId "user-1") Map.empty
      result <- listVersions service "artifact-1"
      case result of
        Right versions -> length versions `shouldBe` 2
        Left err -> expectationFailure $ "Expected success but got: " ++ show err

  describe "validateImmutability" $ do
    it "passes for matching content address" $ do
      service <- newVersioningService defaultVersioningPolicy
      Right created <- createInitialVersion service "artifact-1"
        (ContentAddress "sha256:abc") 1000 "text/plain"
        (SubjectId "user-1") (TenantId "tenant-1") Map.empty
      result <- validateImmutability service (avVersionId created) (ContentAddress "sha256:abc")
      result `shouldBe` Right ()

    it "fails for mismatched content address" $ do
      service <- newVersioningService defaultVersioningPolicy
      Right created <- createInitialVersion service "artifact-1"
        (ContentAddress "sha256:abc") 1000 "text/plain"
        (SubjectId "user-1") (TenantId "tenant-1") Map.empty
      result <- validateImmutability service (avVersionId created) (ContentAddress "sha256:different")
      case result of
        Left (ContentAddressMismatch _ _ _) -> pure ()
        _ -> expectationFailure "Expected ContentAddressMismatch error"

  describe "compareVersions" $ do
    it "reports the elapsed time between versions" $ do
      service <- newVersioningService defaultVersioningPolicy
      Right initial <- createInitialVersion service "artifact-1"
        (ContentAddress "sha256:abc") 1000 "text/plain"
        (SubjectId "user-1") (TenantId "tenant-1") Map.empty
      threadDelay 1100000
      Right newer <- createNewVersion service "artifact-1"
        (ContentAddress "sha256:def") 2000 "text/plain"
        (SubjectId "user-1") Map.empty
      result <- compareVersions service (avVersionId initial) (avVersionId newer)
      case result of
        Right comparison -> do
          vcContentChanged comparison `shouldBe` True
          vcSizeChange comparison `shouldBe` 1000
          vcTimeDelta comparison `shouldSatisfy` (>= 1)
        Left err -> expectationFailure $ "Expected success but got: " ++ show err
