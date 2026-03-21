{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Inference.Guardrails
  ( advisoryOnlyRule,
    applyGuardrails,
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import StudioMCP.Result.Failure (FailureDetail, validationFailure)

advisoryOnlyRule :: Text
advisoryOnlyRule = "Inference output is advisory and must pass typed validation."

applyGuardrails :: Text -> Either FailureDetail Text
applyGuardrails rawAdvice
  | any (`Text.isInfixOf` loweredAdvice) forbiddenFragments =
      Left
        ( validationFailure
            "inference-guardrail-rejected"
            "Reference-model output attempted to cross the advisory-only boundary."
        )
  | "advisory:" `Text.isPrefixOf` loweredAdvice = Right rawAdvice
  | otherwise = Right ("ADVISORY: " <> rawAdvice)
  where
    loweredAdvice = Text.toLower rawAdvice
    forbiddenFragments =
      [ "mark the run succeeded",
        "persist the result directly",
        "skip validation",
        "write directly to minio",
        "publish directly to pulsar"
      ]
