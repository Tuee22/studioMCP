{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Models.Registry
  ( ModelArtifact (..),
    allModelArtifacts,
    lookupModelArtifact,
    modelsBucket,
    resolveModelSourceUrl,
  )
where

import Control.Applicative ((<|>))
import Data.Char (isAlphaNum, toUpper)
import Data.List (find)
import Data.Text (Text)
import qualified Data.Text as Text
import StudioMCP.Storage.Keys (BucketName (..), ObjectKey (..))
import System.Environment (lookupEnv)

data ModelArtifact = ModelArtifact
  { modelId :: Text,
    modelDisplayName :: Text,
    modelDescription :: Text,
    modelObjectKey :: ObjectKey,
    modelDefaultSourceUrl :: Maybe Text
  }
  deriving (Eq, Show)

modelsBucket :: BucketName
modelsBucket = BucketName "studiomcp-models"

allModelArtifacts :: [ModelArtifact]
allModelArtifacts =
  [ ModelArtifact
      { modelId = "demucs-htdemucs",
        modelDisplayName = "Demucs HTDemucs",
        modelDescription = "Stem separation checkpoint for the demucs CLI.",
        modelObjectKey = ObjectKey "models/demucs/htdemucs.th",
        modelDefaultSourceUrl = Just "https://dl.fbaipublicfiles.com/demucs/hybrid_transformer/955717e8-8726e21a.th"
      },
    ModelArtifact
      { modelId = "whisper-base-en",
        modelDisplayName = "Whisper Base English",
        modelDescription = "English transcription model used by the whisper CLI.",
        modelObjectKey = ObjectKey "models/whisper/base.en.bin",
        modelDefaultSourceUrl = Just "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
      },
    ModelArtifact
      { modelId = "whisper-small-en",
        modelDisplayName = "Whisper Small English",
        modelDescription = "Larger English transcription model used by the whisper CLI.",
        modelObjectKey = ObjectKey "models/whisper/small.en.bin",
        modelDefaultSourceUrl = Just "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin"
      },
    ModelArtifact
      { modelId = "basic-pitch",
        modelDisplayName = "Basic Pitch",
        modelDescription = "Audio-to-MIDI model used by the basic-pitch adapter.",
        modelObjectKey = ObjectKey "models/basicpitch/model.npz",
        modelDefaultSourceUrl = Nothing
      },
    ModelArtifact
      { modelId = "generaluser-gs",
        modelDisplayName = "GeneralUser GS SoundFont",
        modelDescription = "General MIDI SoundFont used by FluidSynth rendering.",
        modelObjectKey = ObjectKey "models/soundfonts/GeneralUser-GS.sf2",
        modelDefaultSourceUrl = Nothing
      }
  ]

lookupModelArtifact :: Text -> Maybe ModelArtifact
lookupModelArtifact requestedId =
  find ((== normalizedRequestedId) . Text.toLower . modelId) allModelArtifacts
  where
    normalizedRequestedId = Text.toLower requestedId

resolveModelSourceUrl :: ModelArtifact -> IO (Either Text Text)
resolveModelSourceUrl modelArtifact = do
  override <- lookupEnv (modelSourceOverrideEnvVar modelArtifact)
  pure $
    case fmap Text.pack override <|> modelDefaultSourceUrl modelArtifact of
      Just sourceUrl -> Right sourceUrl
      Nothing ->
        Left
          ( "No source URL configured for model "
              <> modelId modelArtifact
              <> ". Set "
              <> Text.pack (modelSourceOverrideEnvVar modelArtifact)
              <> "."
          )

modelSourceOverrideEnvVar :: ModelArtifact -> String
modelSourceOverrideEnvVar =
  ("STUDIOMCP_MODEL_SOURCE_" <>) . Text.unpack . Text.map normalizeChar . modelId
  where
    normalizeChar character
      | isAlphaNum character = toUpper character
      | otherwise = '_'
