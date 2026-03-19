module StudioMCP.Inference.Types
  ( InferenceRequest (..),
  )
where

import Data.Text (Text)

newtype InferenceRequest = InferenceRequest
  { inferencePrompt :: Text
  }
  deriving (Eq, Show)
