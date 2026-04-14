{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Tools.ImageMagick
  ( runImageMagickCommand,
    seedImageMagickDeterministicFixtures,
    validateImageMagickAdapter,
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

runImageMagickCommand :: Int -> [String] -> IO (Either FailureDetail BoundaryResult)
runImageMagickCommand timeoutSecondsValue imageMagickArgs =
  runToolBoundaryCommand "convert" timeoutSecondsValue imageMagickArgs

seedImageMagickDeterministicFixtures :: IO (Either FailureDetail FilePath)
seedImageMagickDeterministicFixtures = resolveFixturePath "test-pattern-1080p"

validateImageMagickAdapter :: IO (Either FailureDetail ())
validateImageMagickAdapter = do
  fixtureResult <- seedImageMagickDeterministicFixtures
  case fixtureResult of
    Left failureDetail -> pure (Left failureDetail)
    Right inputPath -> do
      outputPrefix <- outputPrefixFor "imagemagick"
      let outputPath = outputPrefix <> ".jpg"
      removeIfPresent outputPath
      successResult <-
        runImageMagickCommand
          15
          [ inputPath,
            "-resize",
            "640x360^",
            "-gravity",
            "center",
            "-extent",
            "640x360",
            outputPath
          ]
      case successResult of
        Left failureDetail -> pure (Left failureDetail)
        Right _ -> do
          outputValidation <- ensureFileExistsAndNonEmpty "imagemagick-output" outputPath
          case outputValidation of
            Left failureDetail -> pure (Left failureDetail)
            Right () -> do
              failureResult <- runImageMagickCommand 10 ["examples/assets/audio/does-not-exist.wav", outputPath]
              pure (validateFailureCode "boundary-process-failed" failureResult)
