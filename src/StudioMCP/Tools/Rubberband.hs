{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Tools.Rubberband
  ( runRubberbandCommand,
    seedRubberbandDeterministicFixtures,
    validateRubberbandAdapter,
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

runRubberbandCommand :: Int -> [String] -> IO (Either FailureDetail BoundaryResult)
runRubberbandCommand timeoutSecondsValue rubberbandArgs =
  runToolBoundaryCommand "rubberband" timeoutSecondsValue rubberbandArgs

seedRubberbandDeterministicFixtures :: IO (Either FailureDetail FilePath)
seedRubberbandDeterministicFixtures = resolveFixturePath "tone-440hz-1s"

validateRubberbandAdapter :: IO (Either FailureDetail ())
validateRubberbandAdapter = do
  fixtureResult <- seedRubberbandDeterministicFixtures
  case fixtureResult of
    Left failureDetail -> pure (Left failureDetail)
    Right inputPath -> do
      outputPrefix <- outputPrefixFor "rubberband"
      let outputPath = outputPrefix <> ".wav"
      removeIfPresent outputPath
      successResult <- runRubberbandCommand 15 ["-t", "1.25", inputPath, outputPath]
      case successResult of
        Left failureDetail -> pure (Left failureDetail)
        Right _ -> do
          outputValidation <- ensureFileExistsAndNonEmpty "rubberband-output" outputPath
          case outputValidation of
            Left failureDetail -> pure (Left failureDetail)
            Right () -> do
              failureResult <- runRubberbandCommand 10 ["-t", "1.25", "examples/assets/audio/does-not-exist.wav", outputPath]
              pure (validateFailureCode "boundary-process-failed" failureResult)
