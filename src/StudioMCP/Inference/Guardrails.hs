{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Inference.Guardrails
  ( advisoryOnlyRule,
  )
where

import Data.Text (Text)

advisoryOnlyRule :: Text
advisoryOnlyRule = "Inference output is advisory and must pass typed validation."
