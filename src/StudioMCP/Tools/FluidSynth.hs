{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Tools.FluidSynth
  ( runFluidSynthCommand,
    seedFluidSynthDeterministicFixtures,
    validateFluidSynthAdapter,
  )
where

import qualified Data.Map.Strict as Map
import StudioMCP.Result.Failure
  ( FailureCategory (StorageFailure),
    FailureDetail (..),
  )
import StudioMCP.Tools.AdapterSupport
  ( ensureCachedModelWhenEnabled,
    ensureFileExistsAndNonEmpty,
    outputPrefixFor,
    removeIfPresent,
    resolveFixturePath,
    runToolBoundaryCommand,
    validateHelpCommand,
  )
import StudioMCP.Tools.Boundary (BoundaryResult)
import System.Environment (lookupEnv)

runFluidSynthCommand :: Int -> [String] -> IO (Either FailureDetail BoundaryResult)
runFluidSynthCommand timeoutSecondsValue fluidSynthArgs =
  runToolBoundaryCommand "fluidsynth" timeoutSecondsValue fluidSynthArgs

seedFluidSynthDeterministicFixtures :: IO (Either FailureDetail FilePath)
seedFluidSynthDeterministicFixtures = resolveFixturePath "simple-melody"

validateFluidSynthAdapter :: IO (Either FailureDetail ())
validateFluidSynthAdapter = do
  helpResult <- validateHelpCommand "fluidsynth" ["--help"]
  case helpResult of
    Left failureDetail -> pure (Left failureDetail)
    Right () -> do
      midiResult <- seedFluidSynthDeterministicFixtures
      case midiResult of
        Left failureDetail -> pure (Left failureDetail)
        Right midiPath -> do
          soundFontResult <- resolveSoundFontPath
          case soundFontResult of
            Left failureDetail -> pure (Left failureDetail)
            Right soundFontPath -> do
              outputPrefix <- outputPrefixFor "fluidsynth"
              let outputPath = outputPrefix <> ".wav"
              removeIfPresent outputPath
              successResult <-
                runFluidSynthCommand
                  20
                  ["-ni", soundFontPath, midiPath, "-F", outputPath, "-r", "44100"]
              case successResult of
                Left failureDetail -> pure (Left failureDetail)
                Right _ -> ensureFileExistsAndNonEmpty "fluidsynth-output" outputPath

resolveSoundFontPath :: IO (Either FailureDetail FilePath)
resolveSoundFontPath = do
  maybeEnvSoundFont <- lookupEnv "STUDIOMCP_FLUIDSYNTH_SOUNDFONT"
  case maybeEnvSoundFont of
    Just soundFontPath -> pure (Right soundFontPath)
    Nothing -> do
      cachedResult <- ensureCachedModelWhenEnabled "generaluser-gs"
      case cachedResult of
        Left failureDetail -> pure (Left failureDetail)
        Right (Just cachedPath) -> pure (Right cachedPath)
        Right Nothing -> pure (Left missingSoundFontFailure)

missingSoundFontFailure :: FailureDetail
missingSoundFontFailure =
  FailureDetail
    { failureCategory = StorageFailure,
      failureCode = "fluidsynth-soundfont-missing",
      failureMessage =
        "No usable SoundFont was available for FluidSynth validation. Set STUDIOMCP_FLUIDSYNTH_SOUNDFONT or provide the generaluser-gs model through MinIO-backed model storage.",
      failureRetryable = False,
      failureContext = Map.empty
    }
