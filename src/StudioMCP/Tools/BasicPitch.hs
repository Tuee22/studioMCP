{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Tools.BasicPitch
  ( runBasicPitchCommand,
    seedBasicPitchDeterministicFixtures,
    validateBasicPitchAdapter,
  )
where

import StudioMCP.Result.Failure (FailureDetail)
import StudioMCP.Tools.AdapterSupport
  ( ensureCachedModelWhenEnabled,
    resolveFixturePath,
    runToolBoundaryCommand,
    validateHelpCommand,
  )
import StudioMCP.Tools.Boundary (BoundaryResult)

runBasicPitchCommand :: Int -> [String] -> IO (Either FailureDetail BoundaryResult)
runBasicPitchCommand timeoutSecondsValue basicPitchArgs =
  runToolBoundaryCommand "basic-pitch" timeoutSecondsValue basicPitchArgs

seedBasicPitchDeterministicFixtures :: IO (Either FailureDetail FilePath)
seedBasicPitchDeterministicFixtures = resolveFixturePath "tone-440hz-1s"

validateBasicPitchAdapter :: IO (Either FailureDetail ())
validateBasicPitchAdapter = do
  helpResult <- validateHelpCommand "basic-pitch" ["--help"]
  case helpResult of
    Left failureDetail -> pure (Left failureDetail)
    Right () -> do
      modelResult <- ensureCachedModelWhenEnabled "basic-pitch"
      case modelResult of
        Left failureDetail -> pure (Left failureDetail)
        Right _ -> pure (Right ())
