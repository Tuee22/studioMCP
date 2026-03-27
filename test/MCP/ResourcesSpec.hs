{-# LANGUAGE OverloadedStrings #-}

module MCP.ResourcesSpec (spec) where

import qualified Data.Text as Text
import StudioMCP.Auth.Types (TenantId (..))
import StudioMCP.MCP.Protocol.Types (ReadResourceParams (..), ReadResourceResult (..), ResourceContent (..))
import StudioMCP.MCP.Resources
import StudioMCP.Storage.TenantStorage
  ( TenantStorageBackend (TenantOwnedS3),
    configureTenantBackend,
    defaultTenantStorageConfig,
    newTenantStorageService,
  )
import Test.Hspec

spec :: Spec
spec = do
  describe "ResourceType" $ do
    it "distinguishes all resource types" $ do
      SummaryResource `shouldNotBe` ManifestResource
      ManifestResource `shouldNotBe` TenantMetadataResource
      TenantMetadataResource `shouldNotBe` QuotaResource

    it "can be shown" $ do
      show SummaryResource `shouldContain` "SummaryResource"

  describe "allResourceTypes" $ do
    it "contains all types" $ do
      length allResourceTypes `shouldBe` 6

  describe "ResourceError" $ do
    it "has error codes" $ do
      resourceErrorCode (ResourceNotFound "test") `shouldBe` "resource-not-found"
      resourceErrorCode (InvalidResourceUri "test") `shouldBe` "invalid-resource-uri"
      resourceErrorCode (ResourceAccessDenied "test") `shouldBe` "access-denied"
      resourceErrorCode (ResourceReadFailed "test") `shouldBe` "read-failed"

  describe "parseResourceUri" $ do
    it "parses summary URI" $ do
      case parseResourceUri "studiomcp://summaries/run-123" of
        Just ru -> do
          ruResourceType ru `shouldBe` SummaryResource
          ruIdentifier ru `shouldBe` Just "run-123"
        Nothing -> expectationFailure "Expected to parse URI"

    it "parses manifest URI" $ do
      case parseResourceUri "studiomcp://manifests/run-456" of
        Just ru -> ruResourceType ru `shouldBe` ManifestResource
        Nothing -> expectationFailure "Expected to parse URI"

    it "parses quota URI" $ do
      case parseResourceUri "studiomcp://metadata/quotas" of
        Just ru -> ruResourceType ru `shouldBe` QuotaResource
        Nothing -> expectationFailure "Expected to parse URI"

    it "returns Nothing for invalid URI" $ do
      parseResourceUri "invalid://uri" `shouldBe` Nothing

  describe "buildResourceUri" $ do
    it "builds summary URI with ID" $ do
      buildResourceUri SummaryResource (Just "run-123") `shouldBe` "studiomcp://summaries/run-123"

    it "builds quota URI" $ do
      buildResourceUri QuotaResource Nothing `shouldBe` "studiomcp://metadata/quotas"

  describe "newResourceCatalog" $ do
    it "creates catalog without error" $ do
      catalog <- newResourceCatalog
      resources <- listResources catalog (TenantId "tenant-1")
      length resources `shouldSatisfy` (> 0)

  describe "listResources" $ do
    it "returns resource definitions" $ do
      catalog <- newResourceCatalog
      resources <- listResources catalog (TenantId "tenant-1")
      length resources `shouldBe` 6

  describe "readResource" $ do
    it "reads quota resource" $ do
      catalog <- newResourceCatalog
      let params = ReadResourceParams "studiomcp://metadata/quotas"
      result <- readResource catalog (TenantId "tenant-1") params
      case result of
        Right _ -> pure ()
        Left err -> expectationFailure $ "Expected success but got: " ++ show err

    it "reads tenant metadata with the configured storage backend" $ do
      catalog <- newResourceCatalog
      tenantStorage <- newTenantStorageService defaultTenantStorageConfig
      configureTenantBackend
        tenantStorage
        (TenantId "tenant-1")
        (TenantOwnedS3 "https://s3.example.com" "us-east-1" "access" "secret")
      let params = ReadResourceParams "studiomcp://metadata/tenant/tenant-1"
      result <- readResource (catalog {rcTenantStorage = Just tenantStorage}) (TenantId "tenant-1") params
      case result of
        Left err -> expectationFailure $ "Expected success but got: " ++ show err
        Right payload ->
          case rrrContents payload of
            content : _ ->
              maybe
                (expectationFailure "Expected JSON text payload")
                (`shouldSatisfy` Text.isInfixOf "\"storage_backend\":\"tenant-s3\"")
                (rcText content)
            [] -> expectationFailure "Expected tenant metadata content"

    it "returns error for invalid URI" $ do
      catalog <- newResourceCatalog
      let params = ReadResourceParams "invalid://uri"
      result <- readResource catalog (TenantId "tenant-1") params
      case result of
        Left (InvalidResourceUri _) -> pure ()
        _ -> expectationFailure "Expected InvalidResourceUri"

  describe "resourceRequiredScopes" $ do
    it "returns scopes for SummaryResource" $ do
      resourceRequiredScopes SummaryResource `shouldContain` ["workflow:read"]

    it "returns scopes for TenantMetadataResource" $ do
      resourceRequiredScopes TenantMetadataResource `shouldContain` ["tenant:read"]

  describe "resourceTemplates" $ do
    it "provides templates for all resources" $ do
      length resourceTemplates `shouldBe` 6
