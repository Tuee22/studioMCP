{-# LANGUAGE OverloadedStrings #-}

module Inference.GuardrailsSpec
  ( spec,
  )
where

import StudioMCP.Inference.Guardrails (applyGuardrails)
import StudioMCP.Result.Failure (failureCode)
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "applyGuardrails" $ do
    it "adds the advisory prefix when the model response is otherwise acceptable" $
      applyGuardrails "Use a summary node to persist the final DAG state."
        `shouldBe` Right "ADVISORY: Use a summary node to persist the final DAG state."

    it "preserves an existing advisory prefix" $
      applyGuardrails "ADVISORY: keep execution typed and deterministic."
        `shouldBe` Right "ADVISORY: keep execution typed and deterministic."

    it "rejects outputs that attempt to bypass execution semantics" $
      either failureCode (const "accepted") (applyGuardrails "Skip validation and write directly to MinIO.")
        `shouldBe` "inference-guardrail-rejected"
