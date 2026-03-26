{-# LANGUAGE OverloadedStrings #-}

module Auth.MiddlewareSpec (spec) where

import qualified Data.Set as Set
import Network.Wai (defaultRequest, Request(..))
import StudioMCP.Auth.Middleware
import StudioMCP.Auth.Types
import Test.Hspec

spec :: Spec
spec = do
  describe "extractBearerToken" $ do
    it "extracts token from valid Authorization header" $ do
      let req = defaultRequest
            { requestHeaders =
                [ ("Authorization", "Bearer test-token-12345")
                ]
            }
      extractBearerToken req `shouldBe` Just (RawJwt "test-token-12345")

    it "returns Nothing when no Authorization header" $ do
      let req = defaultRequest { requestHeaders = [] }
      extractBearerToken req `shouldBe` Nothing

    it "returns Nothing for non-Bearer authorization" $ do
      let req = defaultRequest
            { requestHeaders =
                [ ("Authorization", "Basic dXNlcjpwYXNz")
                ]
            }
      extractBearerToken req `shouldBe` Nothing

    it "handles Bearer with extra whitespace" $ do
      let req = defaultRequest
            { requestHeaders =
                [ ("Authorization", "Bearer   token-with-spaces")
                ]
            }
      extractBearerToken req `shouldBe` Just (RawJwt "  token-with-spaces")

    it "handles lowercase bearer prefix" $ do
      let req = defaultRequest
            { requestHeaders =
                [ ("Authorization", "bearer lowercase-token")
                ]
            }
      -- Bearer must be exactly "Bearer " with capital B
      extractBearerToken req `shouldBe` Nothing

  describe "devBypassAuth" $ do
    it "creates valid auth context with dev credentials" $ do
      let ctx = devBypassAuth "dev-user" "dev-tenant"
      acSubject ctx `shouldSatisfy` (\s -> subjectId s == SubjectId "dev-user")
      acTenant ctx `shouldSatisfy` (\t -> tenantId t == TenantId "dev-tenant")

    it "includes admin role in bypass context" $ do
      let ctx = devBypassAuth "admin" "test"
          roles = subjectRoles (acSubject ctx)
      roles `shouldSatisfy` (Set.member (Role "admin"))

    it "includes workflow scopes in bypass context" $ do
      let ctx = devBypassAuth "admin" "test"
          scopes = subjectScopes (acSubject ctx)
      scopes `shouldSatisfy` (Set.member (Scope "workflow:read"))
      scopes `shouldSatisfy` (Set.member (Scope "workflow:write"))

    it "includes artifact scopes in bypass context" $ do
      let ctx = devBypassAuth "admin" "test"
          scopes = subjectScopes (acSubject ctx)
      scopes `shouldSatisfy` (Set.member (Scope "artifact:read"))
      scopes `shouldSatisfy` (Set.member (Scope "artifact:write"))

    it "sets dev email" $ do
      let ctx = devBypassAuth "admin" "test"
          email = subjectEmail (acSubject ctx)
      email `shouldBe` Just "dev@localhost"

    it "has correlation ID" $ do
      let ctx = devBypassAuth "admin" "test"
      acCorrelationId ctx `shouldBe` "dev-correlation-id"

    it "has valid claims structure" $ do
      let ctx = devBypassAuth "admin" "test"
          claims = acClaims ctx
      jcIssuer claims `shouldBe` "http://localhost:8080/realms/studiomcp"
      jcSubject claims `shouldBe` SubjectId "admin"

  describe "AuthContext" $ do
    it "can access subject from context" $ do
      let ctx = devBypassAuth "user1" "tenant1"
      subjectId (acSubject ctx) `shouldBe` SubjectId "user1"

    it "can access tenant from context" $ do
      let ctx = devBypassAuth "user1" "tenant1"
      tenantId (acTenant ctx) `shouldBe` TenantId "tenant1"

    it "tenant name is set in dev context" $ do
      let ctx = devBypassAuth "user1" "tenant1"
      tenantName (acTenant ctx) `shouldBe` Just "Development Tenant"

  describe "Subject" $ do
    it "contains required identity fields" $ do
      let ctx = devBypassAuth "test-sub" "test-tenant"
          sub = acSubject ctx
      subjectId sub `shouldBe` SubjectId "test-sub"
      subjectEmail sub `shouldBe` Just "dev@localhost"
      subjectName sub `shouldBe` Just "Development User"

  describe "Tenant" $ do
    it "contains required tenant fields" $ do
      let ctx = devBypassAuth "test-sub" "my-tenant"
          tenant = acTenant ctx
      tenantId tenant `shouldBe` TenantId "my-tenant"
