{-# LANGUAGE OverloadedStrings #-}

module MCP.ToolsSpec (spec) where

import Data.Aeson (object, (.=))
import StudioMCP.Auth.Types (SubjectId (..), TenantId (..))
import StudioMCP.MCP.Protocol.Types (CallToolParams (..), ToolDefinition (..))
import StudioMCP.MCP.Tools
import Test.Hspec

spec :: Spec
spec = do
  describe "ToolName" $ do
    it "distinguishes all tool names" $ do
      WorkflowSubmit `shouldNotBe` WorkflowStatus
      ArtifactGet `shouldNotBe` ArtifactHide

    it "can be shown" $ do
      show WorkflowSubmit `shouldContain` "WorkflowSubmit"

  describe "allToolNames" $ do
    it "contains all tools" $ do
      length allToolNames `shouldBe` 10

  describe "ToolError" $ do
    it "has error codes" $ do
      toolErrorCode (ToolNotFound "test") `shouldBe` "tool-not-found"
      toolErrorCode (InvalidArguments "test") `shouldBe` "invalid-arguments"
      toolErrorCode (ExecutionFailed "test") `shouldBe` "execution-failed"
      toolErrorCode RateLimited `shouldBe` "rate-limited"

  describe "newToolCatalog" $ do
    it "creates catalog without error" $ do
      catalog <- newToolCatalog
      tools <- listTools catalog
      length tools `shouldSatisfy` (> 0)

  describe "listTools" $ do
    it "returns all tool definitions" $ do
      catalog <- newToolCatalog
      tools <- listTools catalog
      length tools `shouldBe` 10

  describe "callTool" $ do
    it "returns error for unknown tool" $ do
      catalog <- newToolCatalog
      let params = CallToolParams "unknown.tool" Nothing
      result <- callTool catalog (TenantId "tenant-1") (SubjectId "user-1") params
      case result of
        ToolFailure (ToolNotFound _) -> pure ()
        _ -> expectationFailure "Expected ToolNotFound"

    it "executes workflow.list successfully" $ do
      catalog <- newToolCatalog
      let params = CallToolParams "workflow.list" Nothing
      result <- callTool catalog (TenantId "tenant-1") (SubjectId "user-1") params
      case result of
        ToolSuccess _ -> pure ()
        ToolFailure err -> expectationFailure $ "Expected success but got: " ++ show err

    it "executes tenant.info successfully" $ do
      catalog <- newToolCatalog
      let params = CallToolParams "tenant.info" Nothing
      result <- callTool catalog (TenantId "tenant-1") (SubjectId "user-1") params
      case result of
        ToolSuccess _ -> pure ()
        ToolFailure err -> expectationFailure $ "Expected success but got: " ++ show err

    it "returns error for missing required args" $ do
      catalog <- newToolCatalog
      let params = CallToolParams "workflow.submit" Nothing
      result <- callTool catalog (TenantId "tenant-1") (SubjectId "user-1") params
      case result of
        ToolFailure (InvalidArguments _) -> pure ()
        _ -> expectationFailure "Expected InvalidArguments"

  describe "toolRequiredScopes" $ do
    it "returns scopes for WorkflowSubmit" $ do
      toolRequiredScopes WorkflowSubmit `shouldContain` ["workflow:write"]

    it "returns scopes for ArtifactGet" $ do
      toolRequiredScopes ArtifactGet `shouldContain` ["artifact:read"]

    it "returns scopes for ArtifactHide" $ do
      toolRequiredScopes ArtifactHide `shouldContain` ["artifact:manage"]

  describe "tool definitions" $ do
    it "workflowSubmitTool has name" $ do
      tdName workflowSubmitTool `shouldBe` "workflow.submit"

    it "artifactGetTool has name" $ do
      tdName artifactGetTool `shouldBe` "artifact.get"

    it "tenantInfoTool has name" $ do
      tdName tenantInfoTool `shouldBe` "tenant.info"
