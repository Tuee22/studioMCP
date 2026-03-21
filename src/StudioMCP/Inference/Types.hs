{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Inference.Types
  ( InferenceRequest (..),
    InferenceResponse (..),
  )
where

import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    object,
    withObject,
    (.:),
    (.=),
  )
import Data.Text (Text)

newtype InferenceRequest = InferenceRequest
  { inferencePrompt :: Text
  }
  deriving (Eq, Show)

instance FromJSON InferenceRequest where
  parseJSON = withObject "InferenceRequest" $ \obj ->
    InferenceRequest <$> obj .: "prompt"

instance ToJSON InferenceRequest where
  toJSON inferenceRequest =
    object
      [ "prompt" .= inferencePrompt inferenceRequest
      ]

newtype InferenceResponse = InferenceResponse
  { inferenceAdvice :: Text
  }
  deriving (Eq, Show)

instance ToJSON InferenceResponse where
  toJSON inferenceResponse =
    object
      [ "advice" .= inferenceAdvice inferenceResponse
      ]

instance FromJSON InferenceResponse where
  parseJSON = withObject "InferenceResponse" $ \obj ->
    InferenceResponse <$> obj .: "advice"
