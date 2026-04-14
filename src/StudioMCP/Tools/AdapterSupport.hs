{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Tools.AdapterSupport
  ( adapterFixturesRoot,
    ensureCachedModelWhenEnabled,
    ensureFileExistsAndNonEmpty,
    loadMinioConfigFromEnvMaybe,
    outputPrefixFor,
    removeIfPresent,
    resolveFixturePath,
    runToolBoundaryCommand,
    validateFailureCode,
    validateHelpCommand,
  )
where

import qualified Data.ByteString as BS
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import StudioMCP.Models.Loader (ensureModelCached)
import StudioMCP.Models.Registry (lookupModelArtifact)
import StudioMCP.Result.Failure
  ( FailureCategory (StorageFailure, ToolProcessFailure),
    FailureDetail (..),
    failureCode,
  )
import StudioMCP.Storage.MinIO (MinIOConfig (..))
import StudioMCP.Test.Fixtures
  ( generateAllLocalFixtures,
    lookupFixtureArtifact,
    resolveLocalFixturePath,
  )
import StudioMCP.Tools.Boundary
  ( BoundaryCommand (..),
    BoundaryResult (..),
    runBoundaryCommand,
  )
import System.Directory
  ( createDirectoryIfMissing,
    doesFileExist,
    removeFile,
  )
import System.Environment (lookupEnv)
import System.FilePath ((</>))

adapterFixturesRoot :: FilePath
adapterFixturesRoot = ".data/studiomcp/generated-fixtures"

runToolBoundaryCommand :: FilePath -> Int -> [String] -> IO (Either FailureDetail BoundaryResult)
runToolBoundaryCommand executable timeoutSecondsValue arguments =
  runBoundaryCommand
    BoundaryCommand
      { boundaryExecutable = executable,
        boundaryArguments = arguments,
        boundaryStdin = "",
        boundaryTimeoutSeconds = timeoutSecondsValue
      }

validateHelpCommand :: FilePath -> [String] -> IO (Either FailureDetail ())
validateHelpCommand executable helpArgs = do
  result <- runToolBoundaryCommand executable 10 helpArgs
  pure $
    case result of
      Left failureDetail -> Left failureDetail
      Right boundaryResult
        | boundaryExitCode boundaryResult /= 0 ->
            Left
              FailureDetail
                { failureCategory = ToolProcessFailure,
                  failureCode = "adapter-help-exit-mismatch",
                  failureMessage = "The tool help command exited unsuccessfully.",
                  failureRetryable = False,
                  failureContext =
                    Map.fromList
                      [ ("executable", Text.pack executable),
                        ("exitCode", Text.pack (show (boundaryExitCode boundaryResult)))
                      ]
                }
        | otherwise -> Right ()

validateFailureCode :: Text -> Either FailureDetail BoundaryResult -> Either FailureDetail ()
validateFailureCode expectedCode result =
  case result of
    Left failureDetail
      | failureCode failureDetail == expectedCode -> Right ()
      | otherwise ->
          Left
            FailureDetail
              { failureCategory = ToolProcessFailure,
                failureCode = "adapter-failure-code-mismatch",
                failureMessage = "The adapter failure did not project the expected failure code.",
                failureRetryable = False,
                failureContext =
                  Map.fromList
                    [ ("expected", expectedCode),
                      ("observed", failureCode failureDetail)
                    ]
              }
    Right boundaryResult ->
      Left
        FailureDetail
          { failureCategory = ToolProcessFailure,
            failureCode = "adapter-failure-unexpected-success",
            failureMessage = "The failing adapter invocation unexpectedly succeeded.",
            failureRetryable = False,
            failureContext =
              Map.fromList
                [ ("stdout", boundaryStdout boundaryResult),
                  ("stderr", boundaryStderr boundaryResult),
                  ("exitCode", Text.pack (show (boundaryExitCode boundaryResult)))
                ]
        }

resolveFixturePath :: Text -> IO (Either FailureDetail FilePath)
resolveFixturePath fixtureId = do
  generatedFixtures <- generateAllLocalFixtures adapterFixturesRoot
  pure $
    case generatedFixtures of
      Left failureDetail -> Left failureDetail
      Right _ ->
        case lookupFixtureArtifact fixtureId of
          Nothing ->
            Left
              FailureDetail
                { failureCategory = StorageFailure,
                  failureCode = "adapter-fixture-missing",
                  failureMessage = "The requested deterministic fixture is not registered.",
                  failureRetryable = False,
                  failureContext = Map.fromList [("fixtureId", fixtureId)]
                }
          Just fixtureArtifact ->
            Right (resolveLocalFixturePath adapterFixturesRoot fixtureArtifact)

ensureFileExistsAndNonEmpty :: Text -> FilePath -> IO (Either FailureDetail ())
ensureFileExistsAndNonEmpty label outputPath = do
  fileExists <- doesFileExist outputPath
  if not fileExists
    then
      pure
        ( Left
            FailureDetail
              { failureCategory = StorageFailure,
                failureCode = "adapter-output-missing",
                failureMessage = "The adapter did not create the expected output file.",
                failureRetryable = False,
                failureContext =
                  Map.fromList
                    [ ("label", label),
                      ("outputPath", Text.pack outputPath)
                    ]
              }
        )
    else do
      fileBytes <- BS.readFile outputPath
      pure $
        if BS.null fileBytes
          then
            Left
              FailureDetail
                { failureCategory = StorageFailure,
                  failureCode = "adapter-output-empty",
                  failureMessage = "The adapter created an empty output file.",
                  failureRetryable = False,
                  failureContext =
                    Map.fromList
                      [ ("label", label),
                        ("outputPath", Text.pack outputPath)
                      ]
                }
          else Right ()

removeIfPresent :: FilePath -> IO ()
removeIfPresent path = do
  exists <- doesFileExist path
  if exists then removeFile path else pure ()

outputPrefixFor :: Text -> IO FilePath
outputPrefixFor label = do
  let outputRoot = ".data/studiomcp/tool-validation"
  createDirectoryIfMissing True outputRoot
  pure (outputRoot </> Text.unpack label)

loadMinioConfigFromEnvMaybe :: IO (Maybe MinIOConfig)
loadMinioConfigFromEnvMaybe = do
  maybeEndpoint <- lookupEnv "STUDIO_MCP_MINIO_ENDPOINT"
  maybeAccessKey <- lookupEnv "STUDIO_MCP_MINIO_ACCESS_KEY"
  maybeSecretKey <- lookupEnv "STUDIO_MCP_MINIO_SECRET_KEY"
  pure $
    case (maybeEndpoint, maybeAccessKey, maybeSecretKey) of
      (Just endpoint, Just accessKey, Just secretKey) ->
        Just
          MinIOConfig
            { minioEndpointUrl = Text.pack endpoint,
              minioAccessKey = Text.pack accessKey,
              minioSecretKey = Text.pack secretKey
            }
      _ -> Nothing

ensureCachedModelWhenEnabled :: Text -> IO (Either FailureDetail (Maybe FilePath))
ensureCachedModelWhenEnabled requestedModelId = do
  maybeAutoload <- lookupEnv "STUDIOMCP_MODEL_AUTOLOAD"
  case fmap Text.toLower (Text.pack <$> maybeAutoload) of
    Just "1" -> autoloadModel
    Just "true" -> autoloadModel
    Just "yes" -> autoloadModel
    _ -> pure (Right Nothing)
  where
    autoloadModel =
      case lookupModelArtifact requestedModelId of
        Nothing ->
          pure
            ( Left
                FailureDetail
                  { failureCategory = StorageFailure,
                    failureCode = "adapter-model-unknown",
                    failureMessage = "The requested model is not registered.",
                    failureRetryable = False,
                    failureContext = Map.fromList [("modelId", requestedModelId)]
                  }
            )
        Just modelArtifact -> do
          maybeMinioConfig <- loadMinioConfigFromEnvMaybe
          case maybeMinioConfig of
            Nothing -> pure (Right Nothing)
            Just minioConfig -> do
              cacheResult <- ensureModelCached minioConfig modelArtifact
              pure (fmap Just cacheResult)
