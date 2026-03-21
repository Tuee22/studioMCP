{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Tools.FFmpeg
  ( seedDeterministicFixtures,
    validateFFmpegAdapter,
  )
where

import qualified Data.ByteString as BS
import Data.Map.Strict qualified as Map
import qualified Data.Text as Text
import StudioMCP.Result.Failure
  ( FailureCategory (ToolProcessFailure),
    FailureDetail (..),
    failureCode,
  )
import StudioMCP.Tools.Boundary
  ( BoundaryCommand (..),
    BoundaryResult (..),
    runBoundaryCommand,
  )
import System.Directory
  ( createDirectoryIfMissing,
    doesFileExist,
    getTemporaryDirectory,
    removeFile,
  )
import System.FilePath ((</>))

seedDeterministicFixtures :: IO (Either FailureDetail FilePath)
seedDeterministicFixtures = do
  let fixturesDirectory = "examples/assets/audio"
      fixturePath = fixturesDirectory </> "tone.wav"
  createDirectoryIfMissing True fixturesDirectory
  seedResult <- runFFmpegCommand 10 fixtureArgs
  case seedResult of
    Left failureDetail -> pure (Left failureDetail)
    Right _ -> pure (Right fixturePath)
  where
    fixtureArgs =
      [ "-f",
        "lavfi",
        "-i",
        "sine=frequency=440:sample_rate=48000:duration=1",
        "-c:a",
        "pcm_s16le",
        "examples/assets/audio/tone.wav"
      ]

validateFFmpegAdapter :: IO (Either FailureDetail ())
validateFFmpegAdapter = do
  firstSeedResult <- seedDeterministicFixtures
  case firstSeedResult of
    Left failureDetail -> pure (Left failureDetail)
    Right fixturePath -> do
      firstBytes <- BS.readFile fixturePath
      secondSeedResult <- seedDeterministicFixtures
      case secondSeedResult of
        Left failureDetail -> pure (Left failureDetail)
        Right _ -> do
          secondBytes <- BS.readFile fixturePath
          if firstBytes /= secondBytes
            then pure (Left fixtureReseedMismatch)
            else do
              tempDirectory <- getTemporaryDirectory
              let outputPath = tempDirectory </> "studiomcp-ffmpeg-validate.wav"
              removeIfPresent outputPath
              successResult <-
                runFFmpegCommand
                  10
                  [ "-i",
                    fixturePath,
                    "-ac",
                    "1",
                    "-ar",
                    "22050",
                    "-c:a",
                    "pcm_s16le",
                    outputPath
                  ]
              case successResult of
                Left failureDetail -> pure (Left failureDetail)
                Right boundaryResult
                  | boundaryExitCode boundaryResult /= 0 ->
                      pure (Left ffmpegSuccessExitMismatch)
                  | otherwise -> do
                      outputExists <- doesFileExist outputPath
                      if not outputExists
                        then pure (Left ffmpegOutputMissing)
                        else do
                          outputBytes <- BS.readFile outputPath
                          removeIfPresent outputPath
                          if BS.null outputBytes
                            then pure (Left ffmpegOutputEmpty)
                            else do
                              failureResult <-
                                runFFmpegCommand
                                  10
                                  [ "-i",
                                    "examples/assets/audio/does-not-exist.wav",
                                    "-f",
                                    "null",
                                    "-"
                                  ]
                              pure (validateFailureProjection failureResult)

runFFmpegCommand :: Int -> [String] -> IO (Either FailureDetail BoundaryResult)
runFFmpegCommand timeoutSecondsValue ffmpegArgs =
  runBoundaryCommand
    BoundaryCommand
      { boundaryExecutable = "ffmpeg",
        boundaryArguments = ["-y", "-hide_banner", "-loglevel", "error"] <> ffmpegArgs,
        boundaryStdin = "",
        boundaryTimeoutSeconds = timeoutSecondsValue
      }

removeIfPresent :: FilePath -> IO ()
removeIfPresent path = do
  exists <- doesFileExist path
  if exists then removeFile path else pure ()

validateFailureProjection :: Either FailureDetail BoundaryResult -> Either FailureDetail ()
validateFailureProjection result =
  case result of
    Left failureDetail
      | failureCode failureDetail /= "boundary-process-failed" ->
          Left
            FailureDetail
              { failureCategory = ToolProcessFailure,
                failureCode = "ffmpeg-failure-code-mismatch",
                failureMessage = "The failing FFmpeg invocation did not map to the expected boundary-process failure code.",
                failureRetryable = False,
                failureContext =
                  Map.fromList
                    [ ("observedFailureCode", failureCode failureDetail) ]
              }
      | not (stderrMentionsMissingInput failureDetail) ->
          Left
            FailureDetail
              { failureCategory = ToolProcessFailure,
                failureCode = "ffmpeg-failure-stderr-mismatch",
                failureMessage = "The failing FFmpeg invocation did not preserve the missing-input error in stderr.",
                failureRetryable = False,
                failureContext = failureContext failureDetail
              }
      | otherwise -> Right ()
    Right boundaryResult ->
      Left
        FailureDetail
          { failureCategory = ToolProcessFailure,
            failureCode = "ffmpeg-failure-unexpected-success",
            failureMessage = "The failing FFmpeg invocation unexpectedly succeeded.",
            failureRetryable = False,
            failureContext =
              Map.fromList
                [ ("stdout", boundaryStdout boundaryResult),
                  ("stderr", boundaryStderr boundaryResult),
                  ("exitCode", Text.pack (show (boundaryExitCode boundaryResult)))
                ]
          }

stderrMentionsMissingInput :: FailureDetail -> Bool
stderrMentionsMissingInput failureDetail =
  case Map.lookup "stderrSnippet" (failureContext failureDetail) of
    Just stderrText ->
      let lowered = Text.toLower stderrText
       in "no such file or directory" `Text.isInfixOf` lowered
            || "does not exist" `Text.isInfixOf` lowered
    Nothing -> False

fixtureReseedMismatch :: FailureDetail
fixtureReseedMismatch =
  FailureDetail
    { failureCategory = ToolProcessFailure,
      failureCode = "ffmpeg-fixture-reseed-mismatch",
      failureMessage = "Regenerating the deterministic FFmpeg fixture produced different bytes.",
      failureRetryable = False,
      failureContext = Map.empty
    }

ffmpegSuccessExitMismatch :: FailureDetail
ffmpegSuccessExitMismatch =
  FailureDetail
    { failureCategory = ToolProcessFailure,
      failureCode = "ffmpeg-success-exit-mismatch",
      failureMessage = "The successful FFmpeg invocation returned a non-zero exit code.",
      failureRetryable = False,
      failureContext = Map.empty
    }

ffmpegOutputMissing :: FailureDetail
ffmpegOutputMissing =
  FailureDetail
    { failureCategory = ToolProcessFailure,
      failureCode = "ffmpeg-output-missing",
      failureMessage = "The successful FFmpeg invocation did not create the expected output file.",
      failureRetryable = False,
      failureContext = Map.empty
    }

ffmpegOutputEmpty :: FailureDetail
ffmpegOutputEmpty =
  FailureDetail
    { failureCategory = ToolProcessFailure,
      failureCode = "ffmpeg-output-empty",
      failureMessage = "The successful FFmpeg invocation created an empty output file.",
      failureRetryable = False,
      failureContext = Map.empty
    }
