{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Tools.Whisper
  ( runWhisperCommand,
    seedWhisperDeterministicFixtures,
    validateWhisperAdapter,
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

runWhisperCommand :: Int -> [String] -> IO (Either FailureDetail BoundaryResult)
runWhisperCommand timeoutSecondsValue whisperArgs =
  runToolBoundaryCommand "whisper" timeoutSecondsValue whisperArgs

seedWhisperDeterministicFixtures :: IO (Either FailureDetail FilePath)
seedWhisperDeterministicFixtures = resolveFixturePath "speech-sample-10s"

validateWhisperAdapter :: IO (Either FailureDetail ())
validateWhisperAdapter = do
  helpResult <- validateHelpCommand "whisper" ["--help"]
  case helpResult of
    Left failureDetail -> pure (Left failureDetail)
    Right () -> do
      modelResult <- ensureCachedModelWhenEnabled "whisper-base-en"
      case modelResult of
        Left failureDetail -> pure (Left failureDetail)
        Right _ -> pure (Right ())
