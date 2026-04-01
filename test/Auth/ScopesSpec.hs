{-# LANGUAGE OverloadedStrings #-}

module Auth.ScopesSpec (spec) where

import qualified Data.Set as Set
import StudioMCP.Auth.Scopes
import StudioMCP.Auth.Types
import Test.Hspec

spec :: Spec
spec = do
  describe "checkScopes" $ do
    it "allows when subject has all required scopes" $ do
      let required = Set.fromList [scopeWorkflowRead]
          subject = testSubject {subjectScopes = Set.fromList [scopeWorkflowRead, scopeWorkflowWrite]}
      checkScopes required subject `shouldBe` Allowed

    it "denies when subject is missing required scopes" $ do
      let required = Set.fromList [scopeWorkflowRead, scopeWorkflowWrite]
          subject = testSubject {subjectScopes = Set.fromList [scopeWorkflowRead]}
      case checkScopes required subject of
        Denied (InsufficientScopes _ _) -> pure ()
        _ -> expectationFailure "Expected Denied with InsufficientScopes"

    it "allows empty required scopes" $ do
      let required = Set.empty
          subject = testSubject
      checkScopes required subject `shouldBe` Allowed

  describe "checkRoles" $ do
    it "allows when subject has any required role" $ do
      let required = Set.fromList [roleUser, roleAdmin]
          subject = testSubject {subjectRoles = Set.fromList [roleUser]}
      checkRoles required subject `shouldBe` Allowed

    it "denies when subject has no required roles" $ do
      let required = Set.fromList [roleAdmin]
          subject = testSubject {subjectRoles = Set.fromList [roleUser]}
      case checkRoles required subject of
        Denied (InsufficientRoles _ _) -> pure ()
        _ -> expectationFailure "Expected Denied with InsufficientRoles"

  describe "checkPermission" $ do
    it "allows WorkflowRead with workflow:read scope" $ do
      let subject =
            testSubject
              { subjectScopes = Set.fromList [scopeWorkflowRead]
              }
      checkPermission WorkflowRead subject `shouldBe` Allowed

    it "denies WorkflowWrite without workflow:write scope" $ do
      let subject =
            testSubject
              { subjectScopes = Set.fromList [scopeWorkflowRead]
              }
      case checkPermission WorkflowWrite subject of
        Denied _ -> pure ()
        Allowed -> expectationFailure "Expected Denied"

  describe "checkPermissions" $ do
    it "allows when all permissions are satisfied" $ do
      let subject =
            testSubject
              { subjectScopes = Set.fromList [scopeWorkflowRead, scopeArtifactRead]
              }
      checkPermissions [WorkflowRead, ArtifactRead] subject `shouldBe` Allowed

    it "denies when any permission is missing" $ do
      let subject =
            testSubject
              { subjectScopes = Set.fromList [scopeWorkflowRead]
              }
      case checkPermissions [WorkflowRead, ArtifactRead] subject of
        Denied _ -> pure ()
        Allowed -> expectationFailure "Expected Denied"

  describe "permissionToScopes" $ do
    it "maps WorkflowRead to workflow:read" $ do
      permissionToScopes WorkflowRead `shouldBe` Set.singleton scopeWorkflowRead

    it "maps WorkflowWrite to workflow:write" $ do
      permissionToScopes WorkflowWrite `shouldBe` Set.singleton scopeWorkflowWrite

    it "maps ArtifactRead to artifact:read" $ do
      permissionToScopes ArtifactRead `shouldBe` Set.singleton scopeArtifactRead

    it "maps AdminAccess to all scopes" $ do
      let adminScopes = permissionToScopes AdminAccess
      adminScopes `shouldSatisfy` Set.member scopeWorkflowRead
      adminScopes `shouldSatisfy` Set.member scopeWorkflowWrite
      adminScopes `shouldSatisfy` Set.member scopeArtifactRead
      adminScopes `shouldSatisfy` Set.member scopeArtifactWrite
      adminScopes `shouldSatisfy` Set.member scopeArtifactManage

  describe "roleToPermissions" $ do
    it "maps user role to basic permissions" $ do
      let perms = roleToPermissions roleUser
      perms `shouldSatisfy` Set.member WorkflowRead
      perms `shouldSatisfy` Set.member WorkflowWrite
      perms `shouldSatisfy` Set.member ArtifactRead
      perms `shouldSatisfy` Set.member ArtifactWrite
      perms `shouldSatisfy` Set.notMember AdminAccess

    it "maps operator role to extended permissions" $ do
      let perms = roleToPermissions roleOperator
      perms `shouldSatisfy` Set.member WorkflowRead
      perms `shouldSatisfy` Set.member ArtifactManage
      perms `shouldSatisfy` Set.member PromptRead
      perms `shouldSatisfy` Set.notMember AdminAccess

    it "maps admin role to all permissions" $ do
      let perms = roleToPermissions roleAdmin
      perms `shouldSatisfy` Set.member AdminAccess
      perms `shouldSatisfy` Set.member ArtifactManage
      perms `shouldSatisfy` Set.member PromptRead

    it "maps unknown role to empty permissions" $ do
      let perms = roleToPermissions (Role "unknown")
      perms `shouldBe` Set.empty

  describe "authorizeToolCall" $ do
    it "authorizes workflow.submit_dag with workflow:write" $ do
      let ctx = testAuthContext {acSubject = testSubject {subjectScopes = Set.fromList [scopeWorkflowWrite]}}
      authorizeToolCall "workflow.submit_dag" ctx `shouldBe` Allowed

    it "denies workflow.submit_dag without workflow:write" $ do
      let ctx = testAuthContext {acSubject = testSubject {subjectScopes = Set.fromList [scopeWorkflowRead]}}
      case authorizeToolCall "workflow.submit_dag" ctx of
        Denied _ -> pure ()
        Allowed -> expectationFailure "Expected Denied"

    it "authorizes workflow.list_runs with workflow:read" $ do
      let ctx = testAuthContext {acSubject = testSubject {subjectScopes = Set.fromList [scopeWorkflowRead]}}
      authorizeToolCall "workflow.list_runs" ctx `shouldBe` Allowed

    it "authorizes artifact.download with artifact:read" $ do
      let ctx = testAuthContext {acSubject = testSubject {subjectScopes = Set.fromList [scopeArtifactRead]}}
      authorizeToolCall "artifact.download_presigned" ctx `shouldBe` Allowed

    it "authorizes artifact.hide with artifact:manage" $ do
      let ctx = testAuthContext {acSubject = testSubject {subjectScopes = Set.fromList [scopeArtifactManage]}}
      authorizeToolCall "artifact.hide" ctx `shouldBe` Allowed

  describe "authorizeResourceRead" $ do
    it "authorizes workflow resource with workflow:read" $ do
      let ctx = testAuthContext {acSubject = testSubject {subjectScopes = Set.fromList [scopeWorkflowRead]}}
      authorizeResourceRead "studiomcp://workflow/123" ctx `shouldBe` Allowed

    it "authorizes artifact resource with artifact:read" $ do
      let ctx = testAuthContext {acSubject = testSubject {subjectScopes = Set.fromList [scopeArtifactRead]}}
      authorizeResourceRead "studiomcp://artifact/abc" ctx `shouldBe` Allowed

  describe "authorizePromptGet" $ do
    it "authorizes with prompt:read" $ do
      let ctx = testAuthContext {acSubject = testSubject {subjectScopes = Set.fromList [scopePromptRead]}}
      authorizePromptGet "dag-planner" ctx `shouldBe` Allowed

    it "denies without prompt:read" $ do
      let ctx = testAuthContext {acSubject = testSubject {subjectScopes = Set.fromList [scopeWorkflowRead]}}
      case authorizePromptGet "dag-planner" ctx of
        Denied _ -> pure ()
        Allowed -> expectationFailure "Expected Denied"

-- Helper: test subject
testSubject :: Subject
testSubject =
  Subject
    { subjectId = SubjectId "user-123",
      subjectEmail = Just "user@example.com",
      subjectName = Just "Test User",
      subjectRoles = Set.fromList [roleUser],
      subjectScopes = Set.empty
    }

-- Helper: test auth context
testAuthContext :: AuthContext
testAuthContext =
  AuthContext
    { acSubject = testSubject,
      acTenant =
        Tenant
          { tenantId = TenantId "tenant-test",
            tenantName = Just "Test Tenant"
          },
      acClaims = testClaims,
      acCorrelationId = "test-correlation-id"
    }

-- Helper: test claims
testClaims :: JwtClaims
testClaims =
  JwtClaims
    { jcIssuer = "https://auth.example.com/realms/test",
      jcSubject = SubjectId "user-123",
      jcAudience = ["studiomcp-mcp"],
      jcExpiration = read "2099-12-31 23:59:59 UTC",
      jcIssuedAt = read "2024-01-01 00:00:00 UTC",
      jcNotBefore = Nothing,
      jcAuthorizedParty = Just "studiomcp-cli",
      jcTenantId = Just (TenantId "tenant-test"),
      jcScopes = Set.empty,
      jcRealmRoles = Set.empty,
      jcResourceRoles = Set.empty,
      jcEmail = Just "user@example.com",
      jcEmailVerified = Just True,
      jcName = Just "Test User"
    }
