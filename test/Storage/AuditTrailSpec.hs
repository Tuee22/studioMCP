{-# LANGUAGE OverloadedStrings #-}

module Storage.AuditTrailSpec (spec) where

import Data.Aeson (decode, encode)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import Data.Time (addUTCTime, getCurrentTime)
import StudioMCP.Auth.Types (SubjectId (..), TenantId (..))
import StudioMCP.Storage.AuditTrail
import StudioMCP.Storage.Governance (ArtifactState (Active), GovernanceAction (..))
import Test.Hspec

spec :: Spec
spec = do
  describe "AuditTrailService" $ do
    it "creates a new service" $ do
      service <- newAuditTrailService
      entries <- queryAuditTrail service defaultAuditQuery
      entries `shouldBe` []

  describe "recordAuditEntry" $ do
    it "records a basic audit entry" $ do
      service <- newAuditTrailService
      entry <- recordAuditEntry
        service
        (TenantId "tenant-1")
        (SubjectId "user-1")
        "artifact-1"
        Nothing
        AuditCreate
        OutcomeSuccess
        Map.empty
      aeArtifactId entry `shouldBe` "artifact-1"
      aeTenantId entry `shouldBe` TenantId "tenant-1"
      aeSubjectId entry `shouldBe` SubjectId "user-1"
      aeAction entry `shouldBe` AuditCreate
      aeOutcome entry `shouldBe` OutcomeSuccess

    it "generates unique entry IDs" $ do
      service <- newAuditTrailService
      entry1 <- recordAuditEntry service (TenantId "t") (SubjectId "u") "a" Nothing AuditCreate OutcomeSuccess Map.empty
      entry2 <- recordAuditEntry service (TenantId "t") (SubjectId "u") "b" Nothing AuditCreate OutcomeSuccess Map.empty
      aeEntryId entry1 `shouldNotBe` aeEntryId entry2

    it "records with metadata details" $ do
      service <- newAuditTrailService
      let details = Map.fromList
            [ ("sourceIp", "192.168.1.1")
            , ("userAgent", "TestClient/1.0")
            , ("requestId", "req-123")
            ]
      entry <- recordAuditEntry
        service
        (TenantId "tenant-1")
        (SubjectId "user-1")
        "artifact-1"
        Nothing
        AuditRead
        OutcomeSuccess
        details
      aeSourceIp entry `shouldBe` Just "192.168.1.1"
      aeUserAgent entry `shouldBe` Just "TestClient/1.0"
      aeRequestId entry `shouldBe` Just "req-123"

  describe "recordAccessAttempt" $ do
    it "records successful access" $ do
      service <- newAuditTrailService
      entry <- recordAccessAttempt
        service
        (TenantId "tenant-1")
        (SubjectId "user-1")
        "artifact-1"
        True
        "granted"
      aeAction entry `shouldBe` AuditRead
      aeOutcome entry `shouldBe` OutcomeSuccess

    it "records denied access" $ do
      service <- newAuditTrailService
      entry <- recordAccessAttempt
        service
        (TenantId "tenant-1")
        (SubjectId "user-1")
        "artifact-1"
        False
        "insufficient permissions"
      aeAction entry `shouldBe` AuditAccessDenied
      aeOutcome entry `shouldBe` OutcomeDenied "insufficient permissions"

  describe "recordDeletionAttempt" $ do
    it "always records deletion as denied" $ do
      service <- newAuditTrailService
      entry <- recordDeletionAttempt
        service
        (TenantId "tenant-1")
        (SubjectId "user-1")
        "artifact-1"
        "hard delete is not allowed"
      aeAction entry `shouldBe` AuditDeleteAttempt
      case aeOutcome entry of
        OutcomeDenied reason -> T.isInfixOf "not allowed" reason `shouldBe` True
        _ -> expectationFailure "Expected OutcomeDenied"

    it "includes denial reason in details" $ do
      service <- newAuditTrailService
      entry <- recordDeletionAttempt
        service
        (TenantId "tenant-1")
        (SubjectId "user-1")
        "artifact-1"
        "policy violation"
      Map.lookup "denialReason" (aeDetails entry) `shouldBe` Just "policy violation"

  describe "recordStateChange" $ do
    it "records hide action" $ do
      service <- newAuditTrailService
      entry <- recordStateChange
        service
        (TenantId "tenant-1")
        (SubjectId "user-1")
        "artifact-1"
        ActionHide
        Active
      case aeAction entry of
        AuditStateChange ActionHide -> pure ()
        other -> expectationFailure $ "Expected AuditStateChange ActionHide but got: " ++ show other

    it "records archive action" $ do
      service <- newAuditTrailService
      entry <- recordStateChange
        service
        (TenantId "tenant-1")
        (SubjectId "user-1")
        "artifact-1"
        ActionArchive
        Active
      case aeAction entry of
        AuditStateChange ActionArchive -> pure ()
        other -> expectationFailure $ "Expected AuditStateChange ActionArchive but got: " ++ show other

  describe "getAuditEntry" $ do
    it "retrieves recorded entry by ID" $ do
      service <- newAuditTrailService
      recorded <- recordAuditEntry service (TenantId "t") (SubjectId "u") "a" Nothing AuditCreate OutcomeSuccess Map.empty
      retrieved <- getAuditEntry service (aeEntryId recorded)
      retrieved `shouldBe` Just recorded

    it "returns Nothing for unknown ID" $ do
      service <- newAuditTrailService
      result <- getAuditEntry service (AuditEntryId "unknown-id")
      result `shouldBe` Nothing

  describe "queryAuditTrail" $ do
    it "returns empty list for empty service" $ do
      service <- newAuditTrailService
      entries <- queryAuditTrail service defaultAuditQuery
      entries `shouldBe` []

    it "filters by tenant ID" $ do
      service <- newAuditTrailService
      _ <- recordAuditEntry service (TenantId "tenant-1") (SubjectId "u") "a" Nothing AuditCreate OutcomeSuccess Map.empty
      _ <- recordAuditEntry service (TenantId "tenant-2") (SubjectId "u") "b" Nothing AuditCreate OutcomeSuccess Map.empty
      entries <- queryAuditTrail service defaultAuditQuery { aqTenantId = Just (TenantId "tenant-1") }
      length entries `shouldBe` 1
      case entries of
        [entry] -> aeTenantId entry `shouldBe` TenantId "tenant-1"
        other -> expectationFailure $ "Expected a single entry, got: " ++ show other

    it "filters by subject ID" $ do
      service <- newAuditTrailService
      _ <- recordAuditEntry service (TenantId "t") (SubjectId "user-1") "a" Nothing AuditCreate OutcomeSuccess Map.empty
      _ <- recordAuditEntry service (TenantId "t") (SubjectId "user-2") "b" Nothing AuditCreate OutcomeSuccess Map.empty
      entries <- queryAuditTrail service defaultAuditQuery { aqSubjectId = Just (SubjectId "user-1") }
      length entries `shouldBe` 1
      case entries of
        [entry] -> aeSubjectId entry `shouldBe` SubjectId "user-1"
        other -> expectationFailure $ "Expected a single entry, got: " ++ show other

    it "filters by artifact ID" $ do
      service <- newAuditTrailService
      _ <- recordAuditEntry service (TenantId "t") (SubjectId "u") "artifact-1" Nothing AuditCreate OutcomeSuccess Map.empty
      _ <- recordAuditEntry service (TenantId "t") (SubjectId "u") "artifact-2" Nothing AuditCreate OutcomeSuccess Map.empty
      entries <- queryAuditTrail service defaultAuditQuery { aqArtifactId = Just "artifact-1" }
      length entries `shouldBe` 1
      case entries of
        [entry] -> aeArtifactId entry `shouldBe` "artifact-1"
        other -> expectationFailure $ "Expected a single entry, got: " ++ show other

    it "filters by action types" $ do
      service <- newAuditTrailService
      _ <- recordAuditEntry service (TenantId "t") (SubjectId "u") "a" Nothing AuditCreate OutcomeSuccess Map.empty
      _ <- recordAuditEntry service (TenantId "t") (SubjectId "u") "b" Nothing AuditRead OutcomeSuccess Map.empty
      _ <- recordAuditEntry service (TenantId "t") (SubjectId "u") "c" Nothing AuditDeleteAttempt (OutcomeDenied "no") Map.empty
      entries <- queryAuditTrail service defaultAuditQuery { aqActions = [AuditDeleteAttempt] }
      length entries `shouldBe` 1
      case entries of
        [entry] -> aeAction entry `shouldBe` AuditDeleteAttempt
        other -> expectationFailure $ "Expected a single entry, got: " ++ show other

    it "respects limit parameter" $ do
      service <- newAuditTrailService
      _ <- recordAuditEntry service (TenantId "t") (SubjectId "u") "a" Nothing AuditCreate OutcomeSuccess Map.empty
      _ <- recordAuditEntry service (TenantId "t") (SubjectId "u") "b" Nothing AuditCreate OutcomeSuccess Map.empty
      _ <- recordAuditEntry service (TenantId "t") (SubjectId "u") "c" Nothing AuditCreate OutcomeSuccess Map.empty
      entries <- queryAuditTrail service defaultAuditQuery { aqLimit = 2 }
      length entries `shouldBe` 2

    it "respects offset parameter" $ do
      service <- newAuditTrailService
      _ <- recordAuditEntry service (TenantId "t") (SubjectId "u") "a" Nothing AuditCreate OutcomeSuccess Map.empty
      _ <- recordAuditEntry service (TenantId "t") (SubjectId "u") "b" Nothing AuditCreate OutcomeSuccess Map.empty
      _ <- recordAuditEntry service (TenantId "t") (SubjectId "u") "c" Nothing AuditCreate OutcomeSuccess Map.empty
      entries <- queryAuditTrail service defaultAuditQuery { aqOffset = 1 }
      length entries `shouldBe` 2

  describe "generateAuditReport" $ do
    it "generates report for tenant" $ do
      service <- newAuditTrailService
      now <- getCurrentTime
      let past = addUTCTime (-3600) now
          future = addUTCTime 3600 now
      _ <- recordAuditEntry service (TenantId "t") (SubjectId "u1") "a" Nothing AuditCreate OutcomeSuccess Map.empty
      _ <- recordAuditEntry service (TenantId "t") (SubjectId "u2") "b" Nothing AuditRead OutcomeSuccess Map.empty
      _ <- recordDeletionAttempt service (TenantId "t") (SubjectId "u1") "a" "denied"
      report <- generateAuditReport service (TenantId "t") past future
      arTotalEntries report `shouldBe` 3
      arDeleteAttemptsCount report `shouldBe` 1
      arDeniedCount report `shouldBe` 1
      arUniqueSubjects report `shouldBe` 2
      arUniqueArtifacts report `shouldBe` 2

  describe "verifyAuditIntegrity" $ do
    it "returns valid for unmodified entries" $ do
      service <- newAuditTrailService
      _ <- recordAuditEntry service (TenantId "t") (SubjectId "u") "a" Nothing AuditCreate OutcomeSuccess Map.empty
      result <- verifyAuditIntegrity service (TenantId "t")
      result `shouldBe` IntegrityValid

  describe "AuditAction JSON" $ do
    it "serializes basic actions" $ do
      encode AuditCreate `shouldBe` "\"create\""
      encode AuditRead `shouldBe` "\"read\""
      encode AuditDeleteAttempt `shouldBe` "\"delete_attempt\""

    it "round-trips all actions" $ do
      (decode (encode AuditCreate) :: Maybe AuditAction) `shouldBe` Just AuditCreate
      (decode (encode AuditRead) :: Maybe AuditAction) `shouldBe` Just AuditRead
      (decode (encode AuditUpdate) :: Maybe AuditAction) `shouldBe` Just AuditUpdate
      (decode (encode AuditDeleteAttempt) :: Maybe AuditAction) `shouldBe` Just AuditDeleteAttempt
      (decode (encode AuditAccessDenied) :: Maybe AuditAction) `shouldBe` Just AuditAccessDenied

  describe "AuditOutcome JSON" $ do
    it "serializes success" $ do
      encode OutcomeSuccess `shouldBe` "\"success\""

    it "round-trips outcomes" $ do
      (decode (encode OutcomeSuccess) :: Maybe AuditOutcome) `shouldBe` Just OutcomeSuccess
      (decode (encode (OutcomeDenied "reason")) :: Maybe AuditOutcome) `shouldBe` Just (OutcomeDenied "reason")
      (decode (encode (OutcomeFailed "error")) :: Maybe AuditOutcome) `shouldBe` Just (OutcomeFailed "error")

  describe "AuditIntegrityResult JSON" $ do
    it "serializes valid result" $ do
      let json = encode IntegrityValid
      -- Verify it encodes to non-empty JSON
      LBS.length json > 0 `shouldBe` True
