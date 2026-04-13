{-# LANGUAGE OverloadedStrings #-}

module Storage.GovernanceSpec (spec) where

import Data.Time (getCurrentTime)
import StudioMCP.Auth.Types (SubjectId (..), TenantId (..))
import StudioMCP.Storage.Governance
import Test.Hspec

spec :: Spec
spec = do
  describe "ArtifactState" $ do
    it "Active artifacts are accessible" $ do
      isArtifactAccessible Active `shouldBe` True

    it "Hidden artifacts are accessible by ID" $ do
      isArtifactAccessible Hidden `shouldBe` True

    it "Archived artifacts are accessible (read-only)" $ do
      isArtifactAccessible Archived `shouldBe` True

    it "Superseded artifacts are accessible with redirect" $ do
      isArtifactAccessible (Superseded "new-artifact-id") `shouldBe` True

  describe "defaultGovernancePolicy" $ do
    it "allows restore from hidden" $ do
      gpAllowRestoreFromHidden defaultGovernancePolicy `shouldBe` True

    it "denies restore from archived by default" $ do
      gpAllowRestoreFromArchived defaultGovernancePolicy `shouldBe` False

    it "has 30 day minimum retention before archive" $ do
      gpMinRetentionBeforeArchive defaultGovernancePolicy `shouldBe` (86400 * 30)

    it "denies hard delete" $ do
      gpDenyHardDelete defaultGovernancePolicy `shouldBe` True

  describe "hideArtifact" $ do
    it "successfully hides an active artifact" $ do
      service <- newGovernanceService defaultGovernancePolicy
      metadata <- testMetadata
      result <- hideArtifact service "artifact-1" metadata
      case result of
        Left err -> expectationFailure $ "Expected success but got: " ++ show err
        Right record -> do
          asrState record `shouldBe` Hidden
          asrArtifactId record `shouldBe` "artifact-1"

    it "successfully hides an already hidden artifact (idempotent)" $ do
      service <- newGovernanceService defaultGovernancePolicy
      metadata <- testMetadata
      _ <- hideArtifact service "artifact-1" metadata
      result <- hideArtifact service "artifact-1" metadata
      case result of
        Left err -> expectationFailure $ "Expected success but got: " ++ show err
        Right record -> asrState record `shouldBe` Hidden

    it "cannot hide an archived artifact" $ do
      service <- newGovernanceService defaultGovernancePolicy
      metadata <- testMetadata
      _ <- archiveArtifact service "artifact-1" metadata
      result <- hideArtifact service "artifact-1" metadata
      case result of
        Left (TransitionNotAllowed Archived TransitionToHidden) -> pure ()
        Left err -> expectationFailure $ "Expected TransitionNotAllowed but got: " ++ show err
        Right _ -> expectationFailure "Expected failure but got success"

    it "cannot hide a superseded artifact" $ do
      service <- newGovernanceService defaultGovernancePolicy
      metadata <- testMetadata
      _ <- supersedeArtifact service "artifact-1" "artifact-2" metadata
      result <- hideArtifact service "artifact-1" metadata
      case result of
        Left (TransitionNotAllowed (Superseded _) TransitionToHidden) -> pure ()
        Left err -> expectationFailure $ "Expected TransitionNotAllowed but got: " ++ show err
        Right _ -> expectationFailure "Expected failure but got success"

  describe "archiveArtifact" $ do
    it "successfully archives an active artifact" $ do
      service <- newGovernanceService defaultGovernancePolicy
      metadata <- testMetadata
      result <- archiveArtifact service "artifact-1" metadata
      case result of
        Left err -> expectationFailure $ "Expected success but got: " ++ show err
        Right record -> do
          asrState record `shouldBe` Archived
          asrArtifactId record `shouldBe` "artifact-1"

    it "successfully archives a hidden artifact" $ do
      service <- newGovernanceService defaultGovernancePolicy
      metadata <- testMetadata
      _ <- hideArtifact service "artifact-1" metadata
      result <- archiveArtifact service "artifact-1" metadata
      case result of
        Left err -> expectationFailure $ "Expected success but got: " ++ show err
        Right record -> asrState record `shouldBe` Archived

    it "cannot archive an already archived artifact" $ do
      service <- newGovernanceService defaultGovernancePolicy
      metadata <- testMetadata
      _ <- archiveArtifact service "artifact-1" metadata
      result <- archiveArtifact service "artifact-1" metadata
      case result of
        Left (TransitionNotAllowed Archived TransitionToArchived) -> pure ()
        Left err -> expectationFailure $ "Expected TransitionNotAllowed but got: " ++ show err
        Right _ -> expectationFailure "Expected failure but got success"

  describe "supersedeArtifact" $ do
    it "successfully supersedes an active artifact" $ do
      service <- newGovernanceService defaultGovernancePolicy
      metadata <- testMetadata
      result <- supersedeArtifact service "artifact-1" "artifact-2" metadata
      case result of
        Left err -> expectationFailure $ "Expected success but got: " ++ show err
        Right record -> do
          asrState record `shouldBe` Superseded "artifact-2"
          asrArtifactId record `shouldBe` "artifact-1"

    it "cannot supersede an archived artifact" $ do
      service <- newGovernanceService defaultGovernancePolicy
      metadata <- testMetadata
      _ <- archiveArtifact service "artifact-1" metadata
      result <- supersedeArtifact service "artifact-1" "artifact-2" metadata
      case result of
        Left (TransitionNotAllowed Archived _) -> pure ()
        Left err -> expectationFailure $ "Expected TransitionNotAllowed but got: " ++ show err
        Right _ -> expectationFailure "Expected failure but got success"

    it "cannot supersede an already superseded artifact" $ do
      service <- newGovernanceService defaultGovernancePolicy
      metadata <- testMetadata
      _ <- supersedeArtifact service "artifact-1" "artifact-2" metadata
      result <- supersedeArtifact service "artifact-1" "artifact-3" metadata
      case result of
        Left (TransitionNotAllowed (Superseded _) _) -> pure ()
        Left err -> expectationFailure $ "Expected TransitionNotAllowed but got: " ++ show err
        Right _ -> expectationFailure "Expected failure but got success"

  describe "restoreArtifact" $ do
    it "successfully restores a hidden artifact" $ do
      service <- newGovernanceService defaultGovernancePolicy
      metadata <- testMetadata
      _ <- hideArtifact service "artifact-1" metadata
      result <- restoreArtifact service "artifact-1" metadata
      case result of
        Left err -> expectationFailure $ "Expected success but got: " ++ show err
        Right record -> do
          asrState record `shouldBe` Active
          asrArtifactId record `shouldBe` "artifact-1"

    it "cannot restore an already active artifact" $ do
      service <- newGovernanceService defaultGovernancePolicy
      metadata <- testMetadata
      result <- restoreArtifact service "artifact-1" metadata
      case result of
        Left (TransitionNotAllowed Active TransitionToActive) -> pure ()
        Left err -> expectationFailure $ "Expected TransitionNotAllowed but got: " ++ show err
        Right _ -> expectationFailure "Expected failure but got success"

    it "cannot restore an archived artifact with default policy" $ do
      service <- newGovernanceService defaultGovernancePolicy
      metadata <- testMetadata
      _ <- archiveArtifact service "artifact-1" metadata
      result <- restoreArtifact service "artifact-1" metadata
      case result of
        Left (TransitionNotAllowed Archived TransitionToActive) -> pure ()
        Left err -> expectationFailure $ "Expected TransitionNotAllowed but got: " ++ show err
        Right _ -> expectationFailure "Expected failure but got success"

    it "cannot restore a superseded artifact" $ do
      service <- newGovernanceService defaultGovernancePolicy
      metadata <- testMetadata
      _ <- supersedeArtifact service "artifact-1" "artifact-2" metadata
      result <- restoreArtifact service "artifact-1" metadata
      case result of
        Left (TransitionNotAllowed (Superseded _) TransitionToActive) -> pure ()
        Left err -> expectationFailure $ "Expected TransitionNotAllowed but got: " ++ show err
        Right _ -> expectationFailure "Expected failure but got success"

  describe "denyHardDelete" $ do
    it "always denies hard delete with default policy" $ do
      service <- newGovernanceService defaultGovernancePolicy
      metadata <- testMetadata
      result <- denyHardDelete service "artifact-1" metadata
      case result of
        Left (HardDeleteForbidden "artifact-1") -> pure ()
        Left err -> expectationFailure $ "Expected HardDeleteForbidden but got: " ++ show err
        Right _ -> expectationFailure "Expected failure but got success"

    it "denies hard delete even when policy flag is false" $ do
      let policy = defaultGovernancePolicy {gpDenyHardDelete = False}
      service <- newGovernanceService policy
      metadata <- testMetadata
      result <- denyHardDelete service "artifact-1" metadata
      -- denyHardDelete always denies regardless of policy
      case result of
        Left (HardDeleteForbidden _) -> pure ()
        Left err -> expectationFailure $ "Expected HardDeleteForbidden but got: " ++ show err
        Right _ -> expectationFailure "Expected failure but got success"

  describe "getArtifactState" $ do
    it "returns Active for unknown artifacts" $ do
      service <- newGovernanceService defaultGovernancePolicy
      state <- getArtifactState service "unknown-artifact"
      state `shouldBe` Active

    it "returns current state after transitions" $ do
      service <- newGovernanceService defaultGovernancePolicy
      metadata <- testMetadata
      _ <- hideArtifact service "artifact-1" metadata
      state <- getArtifactState service "artifact-1"
      state `shouldBe` Hidden

  describe "getArtifactHistory" $ do
    it "returns empty history for new artifacts" $ do
      service <- newGovernanceService defaultGovernancePolicy
      history <- getArtifactHistory service "unknown-artifact"
      history `shouldBe` []

    it "tracks state transitions in history" $ do
      service <- newGovernanceService defaultGovernancePolicy
      metadata <- testMetadata
      _ <- hideArtifact service "artifact-1" metadata
      _ <- archiveArtifact service "artifact-1" metadata
      history <- getArtifactHistory service "artifact-1"
      length history `shouldBe` 2

  describe "governanceErrorCode" $ do
    it "returns hard-delete-forbidden for HardDeleteForbidden" $ do
      governanceErrorCode (HardDeleteForbidden "test") `shouldBe` "hard-delete-forbidden"

    it "returns transition-not-allowed for TransitionNotAllowed" $ do
      governanceErrorCode (TransitionNotAllowed Active TransitionToActive) `shouldBe` "transition-not-allowed"

    it "returns missing-scope for MissingScopeForAction" $ do
      governanceErrorCode (MissingScopeForAction ActionHide "scope") `shouldBe` "missing-scope"

    it "returns artifact-not-in-governance for ArtifactNotInGovernance" $ do
      governanceErrorCode (ArtifactNotInGovernance "id") `shouldBe` "artifact-not-in-governance"

-- Helper to create test metadata
testMetadata :: IO GovernanceMetadata
testMetadata = do
  now <- getCurrentTime
  pure
    GovernanceMetadata
      { gmReason = "Test operation",
        gmRequestedBy = SubjectId "test-user",
        gmTenantId = TenantId "test-tenant",
        gmTimestamp = now,
        gmRelatedArtifacts = []
      }
