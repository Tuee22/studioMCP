{-# LANGUAGE OverloadedStrings #-}

module MCP.PromptsSpec (spec) where

import StudioMCP.Auth.Types (TenantId (..))
import StudioMCP.MCP.Prompts
import StudioMCP.MCP.Protocol.Types (GetPromptParams (..), PromptDefinition (..))
import Test.Hspec

spec :: Spec
spec = do
  describe "PromptName" $ do
    it "distinguishes all prompt names" $ do
      DagPlanning `shouldNotBe` DagRepair
      DagRepair `shouldNotBe` WorkflowAnalysis
      WorkflowAnalysis `shouldNotBe` ArtifactNaming
      ArtifactNaming `shouldNotBe` ErrorDiagnosis

    it "can be shown" $ do
      show DagPlanning `shouldContain` "DagPlanning"

  describe "allPromptNames" $ do
    it "contains all prompts" $ do
      length allPromptNames `shouldBe` 5
      allPromptNames `shouldContain` [DagPlanning]
      allPromptNames `shouldContain` [ErrorDiagnosis]

  describe "parsePromptName" $ do
    it "parses dag-planning" $ do
      parsePromptName "dag-planning" `shouldBe` Just DagPlanning

    it "parses dag-repair" $ do
      parsePromptName "dag-repair" `shouldBe` Just DagRepair

    it "returns Nothing for unknown" $ do
      parsePromptName "unknown" `shouldBe` Nothing

  describe "PromptError" $ do
    it "has error codes" $ do
      promptErrorCode (PromptNotFound "test") `shouldBe` "prompt-not-found"
      promptErrorCode (InvalidPromptArguments "test") `shouldBe` "invalid-arguments"
      promptErrorCode (PromptRenderFailed "test") `shouldBe` "render-failed"

  describe "newPromptCatalog" $ do
    it "creates catalog without error" $ do
      catalog <- newPromptCatalog
      -- Just verify it creates
      prompts <- listPrompts catalog
      length prompts `shouldSatisfy` (> 0)

  describe "listPrompts" $ do
    it "returns all prompt definitions" $ do
      catalog <- newPromptCatalog
      prompts <- listPrompts catalog
      length prompts `shouldBe` 5

  describe "getPrompt" $ do
    it "returns prompt for valid name" $ do
      catalog <- newPromptCatalog
      let params = GetPromptParams "dag-planning" Nothing
      result <- getPrompt catalog (TenantId "tenant-1") params
      case result of
        Right _ -> pure ()
        Left err -> expectationFailure $ "Expected success but got: " ++ show err

    it "returns error for invalid name" $ do
      catalog <- newPromptCatalog
      let params = GetPromptParams "invalid-name" Nothing
      result <- getPrompt catalog (TenantId "tenant-1") params
      case result of
        Left (PromptNotFound _) -> pure ()
        _ -> expectationFailure "Expected PromptNotFound"

  describe "promptRequiredScopes" $ do
    it "returns scopes for DagPlanning" $ do
      promptRequiredScopes DagPlanning `shouldContain` ["prompt:read"]

    it "returns scopes for WorkflowAnalysis" $ do
      let scopes = promptRequiredScopes WorkflowAnalysis
      scopes `shouldContain` ["prompt:read"]
      scopes `shouldContain` ["workflow:read"]

  describe "prompt definitions" $ do
    it "dagPlanningPrompt has name" $ do
      pdName dagPlanningPrompt `shouldBe` "dag-planning"

    it "dagRepairPrompt has name" $ do
      pdName dagRepairPrompt `shouldBe` "dag-repair"

    it "workflowAnalysisPrompt has name" $ do
      pdName workflowAnalysisPrompt `shouldBe` "workflow-analysis"
