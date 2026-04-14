{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Tools.Demucs
  ( runDemucsCommand,
    seedDemucsDeterministicFixtures,
    validateDemucsAdapter,
  )
where

import StudioMCP.Result.Failure (FailureDetail)
import StudioMCP.Tools.AdapterSupport
  ( outputPrefixFor,
    resolveFixturePath,
    runToolBoundaryCommand,
    validateFailureCode,
    validateHelpCommand,
  )
import StudioMCP.Tools.Boundary (BoundaryResult)

runDemucsCommand :: Int -> [String] -> IO (Either FailureDetail BoundaryResult)
runDemucsCommand timeoutSecondsValue demucsArgs =
  runToolBoundaryCommand "demucs" timeoutSecondsValue demucsArgs

seedDemucsDeterministicFixtures :: IO (Either FailureDetail FilePath)
seedDemucsDeterministicFixtures = resolveFixturePath "music-stems-30s"

validateDemucsAdapter :: IO (Either FailureDetail ())
validateDemucsAdapter = do
  helpResult <- validateHelpCommand "demucs" ["--help"]
  case helpResult of
    Left failureDetail -> pure (Left failureDetail)
    Right () -> do
      outputPrefix <- outputPrefixFor "demucs"
      failureResult <-
        runDemucsCommand
          15
          ["--two-stems", "vocals", "--out", outputPrefix, "examples/assets/audio/does-not-exist.wav"]
      pure (validateFailureCode "boundary-process-failed" failureResult)
