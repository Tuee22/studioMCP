{-# LANGUAGE OverloadedStrings #-}

module Auth.TypesSpec (spec) where

import Data.Aeson (decode, encode)
import qualified Data.ByteString.Lazy.Char8 as LBS
import Data.List (isInfixOf)
import qualified Data.Set as Set
import Network.HTTP.Types (status401, status403, status500)
import StudioMCP.Auth.Types
import Test.Hspec

spec :: Spec
spec = do
  describe "AuthError" $ do
    it "maps MissingToken to 401" $ do
      authErrorToHttpStatus MissingToken `shouldBe` status401

    it "maps TokenExpired to 401" $ do
      authErrorToHttpStatus TokenExpired `shouldBe` status401

    it "maps InvalidSignature to 401" $ do
      authErrorToHttpStatus InvalidSignature `shouldBe` status401

    it "maps TenantResolutionFailed to 403" $ do
      authErrorToHttpStatus TenantResolutionFailed `shouldBe` status403

    it "maps InsufficientScopes to 403" $ do
      let required = Set.singleton (Scope "workflow:write")
          present = Set.singleton (Scope "workflow:read")
      authErrorToHttpStatus (InsufficientScopes required present) `shouldBe` status403

    it "maps JwksFetchError to 500" $ do
      authErrorToHttpStatus (JwksFetchError "timeout") `shouldBe` status500

    it "maps InternalAuthError to 500" $ do
      authErrorToHttpStatus (InternalAuthError "internal") `shouldBe` status500

  describe "SubjectId" $ do
    it "serializes to JSON" $ do
      let sid = SubjectId "user-123"
      encode sid `shouldBe` "\"user-123\""

    it "deserializes from JSON" $ do
      let json = "\"user-456\""
      decode json `shouldBe` Just (SubjectId "user-456")

  describe "TenantId" $ do
    it "serializes to JSON" $ do
      let tid = TenantId "tenant-acme"
      encode tid `shouldBe` "\"tenant-acme\""

    it "deserializes from JSON" $ do
      let json = "\"tenant-xyz\""
      decode json `shouldBe` Just (TenantId "tenant-xyz")

  describe "Scope" $ do
    it "serializes to JSON" $ do
      let scope = Scope "workflow:read"
      encode scope `shouldBe` "\"workflow:read\""

    it "can be compared" $ do
      Scope "a" < Scope "b" `shouldBe` True

  describe "Role" $ do
    it "serializes to JSON" $ do
      let role = Role "admin"
      encode role `shouldBe` "\"admin\""

    it "can be compared" $ do
      Role "admin" < Role "user" `shouldBe` True

  describe "Permission" $ do
    it "serializes to JSON" $ do
      encode WorkflowRead `shouldBe` "\"workflow:read\""
      encode WorkflowWrite `shouldBe` "\"workflow:write\""
      encode ArtifactRead `shouldBe` "\"artifact:read\""
      encode ArtifactManage `shouldBe` "\"artifact:manage\""

    it "deserializes from JSON" $ do
      decode "\"workflow:read\"" `shouldBe` Just WorkflowRead
      decode "\"artifact:manage\"" `shouldBe` Just ArtifactManage

  describe "AuthDecision" $ do
    it "serializes Allowed" $ do
      let json = encode Allowed
          jsonStr = LBS.unpack json
      jsonStr `shouldSatisfy` ("\"allowed\"" `isInfixOf`)

    it "serializes Denied with reason" $ do
      let decision = Denied MissingToken
          json = encode decision
          jsonStr = LBS.unpack json
      jsonStr `shouldSatisfy` ("\"denied\"" `isInfixOf`)
