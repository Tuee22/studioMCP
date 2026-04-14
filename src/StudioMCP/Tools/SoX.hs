{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Tools.SoX
  ( runSoXCommand,
    seedSoXDeterministicFixtures,
    validateSoXAdapter,
  )
where

import StudioMCP.Result.Failure (FailureDetail)
import StudioMCP.Tools.AdapterSupport
  ( ensureFileExistsAndNonEmpty,
    outputPrefixFor,
    removeIfPresent,
    resolveFixturePath,
    runToolBoundaryCommand,
    validateFailureCode,
  )
import StudioMCP.Tools.Boundary (BoundaryResult)

runSoXCommand :: Int -> [String] -> IO (Either FailureDetail BoundaryResult)
runSoXCommand timeoutSecondsValue soxArgs =
  runToolBoundaryCommand "sox" timeoutSecondsValue soxArgs

seedSoXDeterministicFixtures :: IO (Either FailureDetail FilePath)
seedSoXDeterministicFixtures = resolveFixturePath "tone-440hz-1s"

validateSoXAdapter :: IO (Either FailureDetail ())
validateSoXAdapter = do
  fixtureResult <- seedSoXDeterministicFixtures
  case fixtureResult of
    Left failureDetail -> pure (Left failureDetail)
    Right inputPath -> do
      outputPrefix <- outputPrefixFor "sox"
      let outputPath = outputPrefix <> ".wav"
      removeIfPresent outputPath
      successResult <-
        runSoXCommand
          15
          [ inputPath,
            outputPath,
            "trim",
            "0",
            "0.50",
            "norm",
            "-1",
            "fade",
            "t",
            "0.05",
            "0.50",
            "0.05"
          ]
      case successResult of
        Left failureDetail -> pure (Left failureDetail)
        Right _ -> do
          outputValidation <- ensureFileExistsAndNonEmpty "sox-output" outputPath
          case outputValidation of
            Left failureDetail -> pure (Left failureDetail)
            Right () -> do
              failureResult <- runSoXCommand 10 ["examples/assets/audio/does-not-exist.wav", outputPath]
              pure (validateFailureCode "boundary-process-failed" failureResult)
