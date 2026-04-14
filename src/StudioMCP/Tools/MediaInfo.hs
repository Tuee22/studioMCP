{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Tools.MediaInfo
  ( runMediaInfoCommand,
    seedMediaInfoDeterministicFixtures,
    validateMediaInfoAdapter,
  )
where

import Data.Char (isSpace)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import StudioMCP.Result.Failure
  ( FailureCategory (ToolProcessFailure),
    FailureDetail (..),
  )
import StudioMCP.Tools.AdapterSupport
  ( resolveFixturePath,
    runToolBoundaryCommand,
    validateFailureCode,
  )
import StudioMCP.Tools.Boundary
  ( BoundaryResult (..),
  )

runMediaInfoCommand :: Int -> [String] -> IO (Either FailureDetail BoundaryResult)
runMediaInfoCommand timeoutSecondsValue mediaInfoArgs =
  runToolBoundaryCommand "mediainfo" timeoutSecondsValue mediaInfoArgs

seedMediaInfoDeterministicFixtures :: IO (Either FailureDetail FilePath)
seedMediaInfoDeterministicFixtures = resolveFixturePath "test-video-10s"

validateMediaInfoAdapter :: IO (Either FailureDetail ())
validateMediaInfoAdapter = do
  fixtureResult <- seedMediaInfoDeterministicFixtures
  case fixtureResult of
    Left failureDetail -> pure (Left failureDetail)
    Right inputPath -> do
      successResult <- runMediaInfoCommand 10 ["--Output=JSON", inputPath]
      case successResult of
        Left failureDetail -> pure (Left failureDetail)
        Right boundaryResult
          | boundaryExitCode boundaryResult /= 0 ->
              pure
                ( Left
                    FailureDetail
                      { failureCategory = ToolProcessFailure,
                        failureCode = "mediainfo-exit-mismatch",
                        failureMessage = "The MediaInfo command exited unsuccessfully.",
                        failureRetryable = False,
                        failureContext =
                          Map.fromList [("stderr", boundaryStderr boundaryResult)]
                      }
                )
          | not ("media" `Text.isInfixOf` Text.toLower (boundaryStdout boundaryResult)) ->
              pure
                ( Left
                    FailureDetail
                      { failureCategory = ToolProcessFailure,
                        failureCode = "mediainfo-output-mismatch",
                        failureMessage = "The MediaInfo output did not contain the expected JSON payload.",
                        failureRetryable = False,
                        failureContext =
                          Map.fromList [("stdout", Text.take 240 (boundaryStdout boundaryResult))]
                      }
                )
          | otherwise -> do
              failureResult <- runMediaInfoCommand 10 ["--Output=JSON", "examples/assets/audio/does-not-exist.wav"]
              pure (validateMissingInputProjection failureResult)

validateMissingInputProjection :: Either FailureDetail BoundaryResult -> Either FailureDetail ()
validateMissingInputProjection result =
  case result of
    Left failureDetail -> validateFailureCode "boundary-process-failed" (Left failureDetail)
    Right boundaryResult
      | boundaryExitCode boundaryResult == 0
          && "\"media\":null" `Text.isInfixOf` normalizedStdout boundaryResult ->
          Right ()
      | otherwise ->
          Left
            FailureDetail
              { failureCategory = ToolProcessFailure,
                failureCode = "mediainfo-missing-input-mismatch",
                failureMessage = "The MediaInfo missing-input probe did not match the expected adapter contract.",
                failureRetryable = False,
                failureContext =
                  Map.fromList
                    [ ("stdout", Text.take 240 (boundaryStdout boundaryResult)),
                      ("stderr", Text.take 240 (boundaryStderr boundaryResult)),
                      ("exitCode", Text.pack (show (boundaryExitCode boundaryResult)))
                    ]
              }

normalizedStdout :: BoundaryResult -> Text.Text
normalizedStdout =
  Text.toLower
    . Text.filter (not . isSpace)
    . boundaryStdout
