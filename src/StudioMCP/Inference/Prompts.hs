{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Inference.Prompts
  ( planningPromptHeader,
    renderPlanningPrompt,
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import StudioMCP.Inference.Guardrails (advisoryOnlyRule)
import StudioMCP.Inference.Types (InferenceRequest (..))

planningPromptHeader :: Text
planningPromptHeader = "studioMCP planning prompt"

renderPlanningPrompt :: InferenceRequest -> Text
renderPlanningPrompt inferenceRequest =
  Text.unlines
    [ planningPromptHeader,
      advisoryOnlyRule,
      "",
      "User request:",
      inferencePrompt inferenceRequest
    ]
