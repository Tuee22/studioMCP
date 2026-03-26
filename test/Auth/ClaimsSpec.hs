{-# LANGUAGE OverloadedStrings #-}

module Auth.ClaimsSpec (spec) where

import Data.Aeson (Value (..))
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Set as Set
import qualified Data.Vector as V
import StudioMCP.Auth.Claims
import StudioMCP.Auth.Jwks (JwtPayload (..))
import StudioMCP.Auth.Types
import Test.Hspec

spec :: Spec
spec = do
  describe "extractScopes" $ do
    it "extracts scopes from space-separated scope claim" $ do
      let payload = emptyPayload {jpScope = Just "openid profile workflow:read"}
          scopes = extractScopes payload
      scopes `shouldBe` Set.fromList [Scope "openid", Scope "profile", Scope "workflow:read"]

    it "returns empty set when no scope claim" $ do
      let payload = emptyPayload {jpScope = Nothing}
          scopes = extractScopes payload
      scopes `shouldBe` Set.empty

  describe "extractRealmRoles" $ do
    it "extracts realm roles from realm_access.roles" $ do
      let rolesArray = Array $ V.fromList [String "user", String "admin"]
          realmAccess = Object $ KM.fromList [("roles", rolesArray)]
          payload = emptyPayload {jpRealmAccess = Just realmAccess}
          roles = extractRealmRoles payload
      roles `shouldBe` Set.fromList [Role "user", Role "admin"]

    it "returns empty set when no realm_access" $ do
      let payload = emptyPayload {jpRealmAccess = Nothing}
          roles = extractRealmRoles payload
      roles `shouldBe` Set.empty

  describe "extractResourceRoles" $ do
    it "extracts resource roles from resource_access.{client}.roles" $ do
      let clientRoles = Array $ V.fromList [String "workflow.submit", String "artifact.download"]
          clientAccess = Object $ KM.fromList [("roles", clientRoles)]
          resourceAccess = Object $ KM.fromList [("studiomcp-mcp", clientAccess)]
          payload = emptyPayload {jpResourceAccess = Just resourceAccess}
          roles = extractResourceRoles payload
      roles `shouldBe` Set.fromList [Role "workflow.submit", Role "artifact.download"]

    it "returns empty set when no resource_access" $ do
      let payload = emptyPayload {jpResourceAccess = Nothing}
          roles = extractResourceRoles payload
      roles `shouldBe` Set.empty

  describe "resolveTenant" $ do
    it "resolves tenant from explicit tenant_id claim" $ do
      let payload = emptyPayload {jpTenantId = Just "tenant-acme"}
          result = resolveTenant ExplicitTenantClaim payload
      case result of
        Right tenant -> tenantId tenant `shouldBe` TenantId "tenant-acme"
        Left _ -> expectationFailure "Expected Right"

    it "fails when no tenant_id claim with ExplicitTenantClaim strategy" $ do
      let payload = emptyPayload {jpTenantId = Nothing}
          result = resolveTenant ExplicitTenantClaim payload
      result `shouldBe` Left TenantResolutionFailed

    it "resolves tenant from role-based claim" $ do
      let clientRoles = Array $ V.fromList [String "tenant:acme-corp", String "user"]
          clientAccess = Object $ KM.fromList [("roles", clientRoles)]
          resourceAccess = Object $ KM.fromList [("studiomcp", clientAccess)]
          payload = emptyPayload {jpResourceAccess = Just resourceAccess}
          result = resolveTenant RoleBasedTenant payload
      case result of
        Right tenant -> tenantId tenant `shouldBe` TenantId "acme-corp"
        Left _ -> expectationFailure "Expected Right"

    it "uses combined strategy to try all methods" $ do
      let payload = emptyPayload {jpTenantId = Just "tenant-xyz"}
          result = resolveTenant CombinedStrategy payload
      case result of
        Right tenant -> tenantId tenant `shouldBe` TenantId "tenant-xyz"
        Left _ -> expectationFailure "Expected Right"

  describe "extractSubject" $ do
    it "extracts subject from claims" $ do
      let claims = testClaims
          subject = extractSubject claims
      subjectId subject `shouldBe` SubjectId "user-123"
      subjectEmail subject `shouldBe` Just "user@example.com"
      subjectName subject `shouldBe` Just "Test User"

  describe "getStringClaim" $ do
    it "extracts string claim from raw payload" $ do
      let rawPayload = Object $ KM.fromList [("custom_claim", String "custom_value")]
          payload = emptyPayload {jpRaw = rawPayload}
      getStringClaim "custom_claim" payload `shouldBe` Just "custom_value"

    it "returns Nothing for missing claim" $ do
      let payload = emptyPayload
      getStringClaim "nonexistent" payload `shouldBe` Nothing

  describe "getArrayClaim" $ do
    it "extracts array claim from raw payload" $ do
      let rawPayload =
            Object $
              KM.fromList
                [("custom_array", Array $ V.fromList [String "a", String "b"])]
          payload = emptyPayload {jpRaw = rawPayload}
      getArrayClaim "custom_array" payload `shouldBe` ["a", "b"]

    it "returns empty list for missing claim" $ do
      let payload = emptyPayload
      getArrayClaim "nonexistent" payload `shouldBe` []

  describe "getBoolClaim" $ do
    it "extracts boolean claim from raw payload" $ do
      let rawPayload = Object $ KM.fromList [("verified", Bool True)]
          payload = emptyPayload {jpRaw = rawPayload}
      getBoolClaim "verified" payload `shouldBe` Just True

    it "returns Nothing for missing claim" $ do
      let payload = emptyPayload
      getBoolClaim "nonexistent" payload `shouldBe` Nothing

-- Helper: empty payload for testing
emptyPayload :: JwtPayload
emptyPayload =
  JwtPayload
    { jpIss = Nothing,
      jpSub = Nothing,
      jpAud = Nothing,
      jpExp = Nothing,
      jpNbf = Nothing,
      jpIat = Nothing,
      jpAzp = Nothing,
      jpTenantId = Nothing,
      jpScope = Nothing,
      jpRealmAccess = Nothing,
      jpResourceAccess = Nothing,
      jpEmail = Nothing,
      jpEmailVerified = Nothing,
      jpName = Nothing,
      jpRaw = Object KM.empty
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
      jcScopes = Set.fromList [Scope "openid", Scope "workflow:read"],
      jcRealmRoles = Set.fromList [Role "user"],
      jcResourceRoles = Set.empty,
      jcEmail = Just "user@example.com",
      jcEmailVerified = Just True,
      jcName = Just "Test User"
    }
