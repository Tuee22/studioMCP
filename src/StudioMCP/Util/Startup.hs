{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Util.Startup
  ( StartupFailure (..),
    startupFailure,
    invalidEnvironmentVariable,
    invalidConfigurationFile,
    renderStartupFailure,
    runStartupPhase,
    resolvePortEnvWithDefault,
  )
where

import Control.Exception (Exception, SomeException, fromException, throwIO, try)
import Data.Text (Text)
import qualified Data.Text as Text
import GHC.Generics (Generic)
import StudioMCP.Observability.Redaction (redactForLogging)
import System.Environment (lookupEnv)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

data StartupFailure = StartupFailure
  { sfSummary :: Text,
    sfRemediation :: Maybe Text
  }
  deriving (Eq, Show, Generic)

instance Exception StartupFailure

startupFailure :: Text -> Maybe Text -> StartupFailure
startupFailure summary remediation =
  StartupFailure
    { sfSummary = summary,
      sfRemediation = remediation
    }

invalidEnvironmentVariable :: String -> Text -> Maybe Text -> StartupFailure
invalidEnvironmentVariable envName problem remediation =
  startupFailure
    ("Invalid environment variable " <> Text.pack envName <> ": " <> problem)
    remediation

invalidConfigurationFile :: Text -> FilePath -> Text -> Maybe Text -> StartupFailure
invalidConfigurationFile label path problem remediation =
  startupFailure
    ("Invalid " <> label <> " file at " <> Text.pack path <> ": " <> problem)
    remediation

renderStartupFailure :: StartupFailure -> Text
renderStartupFailure failure =
  let base = "startup failed: " <> sentenceCase (redactForLogging (Text.strip (sfSummary failure)))
   in maybe base (\hint -> base <> " " <> sentenceCase (redactForLogging (Text.strip hint))) (sfRemediation failure)
  where
    sentenceCase textValue
      | Text.null textValue = textValue
      | "." `Text.isSuffixOf` textValue = textValue
      | otherwise = textValue <> "."

runStartupPhase :: IO a -> IO a
runStartupPhase action = do
  result <- try action
  case result of
    Right value -> pure value
    Left err
      | Just failure <- fromException err -> emitAndExit (renderStartupFailure failure)
      | otherwise ->
          emitAndExit
            "startup failed: Unexpected internal error during startup. Check process logs and configuration, then retry."
  where
    emitAndExit :: Text -> IO b
    emitAndExit message = do
      hPutStrLn stderr (Text.unpack (redactForLogging message))
      exitFailure

resolvePortEnvWithDefault :: String -> Int -> IO Int
resolvePortEnvWithDefault envName def = do
  maybePortText <- lookupEnv envName
  case maybePortText of
    Nothing -> pure def
    Just rawValue ->
      case reads rawValue of
        [(port, "")]
          | port >= 1 && port <= 65535 -> pure port
        _ ->
          throwIO $
            invalidEnvironmentVariable
              envName
              "expected a TCP port between 1 and 65535"
              ( Just
                  ( "Set "
                      <> Text.pack envName
                      <> " to a valid port or unset it to use the default "
                      <> Text.pack (show def)
                  )
              )
