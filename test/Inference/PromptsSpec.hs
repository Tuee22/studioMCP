{-# LANGUAGE OverloadedStrings #-}

module Inference.PromptsSpec
  ( spec,
  )
where

import Data.Text qualified as Text
import StudioMCP.Inference.Guardrails (advisoryOnlyRule)
import StudioMCP.Inference.Prompts (planningPromptHeader, renderPlanningPrompt)
import StudioMCP.Inference.Types (InferenceRequest (..))
import Test.Hspec (Spec, describe, it, shouldSatisfy)

spec :: Spec
spec =
  describe "renderPlanningPrompt" $
    it "includes the planning header, guardrail, and user prompt" $ do
      let promptText = renderPlanningPrompt (InferenceRequest "Repair the missing summary node.")
      promptText `shouldSatisfy` Text.isInfixOf planningPromptHeader
      promptText `shouldSatisfy` Text.isInfixOf advisoryOnlyRule
      promptText `shouldSatisfy` Text.isInfixOf "Repair the missing summary node."
