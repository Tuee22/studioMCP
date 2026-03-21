module StudioMCP.CLI.Dag
  ( FixtureValidationSummary (..),
    runDagCommand,
    validateDagFileCommand,
    validateDagFixturesAt,
    validateDagFixturesCommand,
  )
where

import Control.Monad (forM)
import Data.List (sort)
import Data.Maybe (catMaybes)
import StudioMCP.CLI.Command (DagCommand (..))
import StudioMCP.DAG.Parser (loadDagFile)
import StudioMCP.DAG.Validator (renderFailures, validateDag)
import StudioMCP.Result.Types (Result (Failure, Success))
import System.Directory (doesDirectoryExist, listDirectory)
import System.Exit (die)
import System.FilePath ((</>), takeExtension)

data FixtureValidationSummary = FixtureValidationSummary
  { fixtureValidCount :: Int,
    fixtureInvalidParseCount :: Int,
    fixtureInvalidValidationCount :: Int
  }
  deriving (Eq, Show)

runDagCommand :: DagCommand -> IO ()
runDagCommand dagCommand =
  case dagCommand of
    DagValidateFixturesCommand -> validateDagFixturesCommand

validateDagFileCommand :: FilePath -> IO ()
validateDagFileCommand dagPath = do
  result <- validateDagFileAt dagPath
  case result of
    Left failureText -> die failureText
    Right () -> putStrLn "DAG is valid."

validateDagFixturesCommand :: IO ()
validateDagFixturesCommand = do
  result <- validateDagFixturesAt "examples/dags"
  case result of
    Left problems -> die (renderFixtureProblems problems)
    Right summary ->
      putStrLn $
        "DAG fixture checks passed. "
          <> "Valid fixtures: "
          <> show (fixtureValidCount summary)
          <> ", malformed fixtures: "
          <> show (fixtureInvalidParseCount summary)
          <> ", structurally invalid fixtures: "
          <> show (fixtureInvalidValidationCount summary)
          <> "."

validateDagFixturesAt :: FilePath -> IO (Either [String] FixtureValidationSummary)
validateDagFixturesAt fixturesRoot = do
  validFixtures <- findYamlFilesSkippingDirectories fixturesRoot ["invalid"]
  invalidParseFixtures <- findYamlFilesRecursively (fixturesRoot </> "invalid" </> "parse")
  invalidValidationFixtures <- findYamlFilesRecursively (fixturesRoot </> "invalid" </> "validation")
  validProblems <- catMaybes <$> forM validFixtures validateValidFixture
  invalidParseProblems <- catMaybes <$> forM invalidParseFixtures validateInvalidParseFixture
  invalidValidationProblems <- catMaybes <$> forM invalidValidationFixtures validateInvalidValidationFixture
  let presenceProblems =
        concat
          [ ["No valid DAG fixtures found under " <> fixturesRoot | null validFixtures],
            ["No malformed DAG fixtures found under " <> fixturesRoot </> "invalid" </> "parse" | null invalidParseFixtures],
            ["No structurally invalid DAG fixtures found under " <> fixturesRoot </> "invalid" </> "validation" | null invalidValidationFixtures]
          ]
      problems = presenceProblems <> validProblems <> invalidParseProblems <> invalidValidationProblems
  if null problems
    then
      pure $
        Right
          FixtureValidationSummary
            { fixtureValidCount = length validFixtures,
              fixtureInvalidParseCount = length invalidParseFixtures,
              fixtureInvalidValidationCount = length invalidValidationFixtures
            }
    else pure (Left problems)

validateValidFixture :: FilePath -> IO (Maybe String)
validateValidFixture fixturePath = do
  result <- validateDagFileAt fixturePath
  pure $
    case result of
      Left failureText -> Just ("Valid fixture failed: " <> fixturePath <> " -> " <> failureText)
      Right () -> Nothing

validateInvalidParseFixture :: FilePath -> IO (Maybe String)
validateInvalidParseFixture fixturePath = do
  decoded <- loadDagFile fixturePath
  pure $
    case decoded of
      Left _ -> Nothing
      Right _ -> Just ("Malformed fixture unexpectedly parsed successfully: " <> fixturePath)

validateInvalidValidationFixture :: FilePath -> IO (Maybe String)
validateInvalidValidationFixture fixturePath = do
  decoded <- loadDagFile fixturePath
  pure $
    case decoded of
      Left failureText ->
        Just ("Structurally invalid fixture failed during YAML parsing instead of validation: " <> fixturePath <> " -> " <> failureText)
      Right dagSpec ->
        case validateDag dagSpec of
          Failure _ -> Nothing
          Success _ -> Just ("Structurally invalid fixture unexpectedly passed validation: " <> fixturePath)

validateDagFileAt :: FilePath -> IO (Either String ())
validateDagFileAt dagPath = do
  decoded <- loadDagFile dagPath
  case decoded of
    Left parseFailure -> pure (Left parseFailure)
    Right dagSpec ->
      case validateDag dagSpec of
        Success _ -> pure (Right ())
        Failure failures -> pure (Left (renderFailures failures))

renderFixtureProblems :: [String] -> String
renderFixtureProblems problems =
  unlines ("DAG fixture validation failed:" : map ("- " <>) (sort problems))

findYamlFilesRecursively :: FilePath -> IO [FilePath]
findYamlFilesRecursively root = do
  rootExists <- doesDirectoryExist root
  if not rootExists
    then pure []
    else go root
  where
    go current = do
      entries <- sort <$> listDirectory current
      fmap concat $
        forM entries $ \entry -> do
          let path = current </> entry
          isDirectory <- doesDirectoryExist path
          if isDirectory
            then go path
            else pure [path | takeExtension path == ".yaml"]

findYamlFilesSkippingDirectories :: FilePath -> [FilePath] -> IO [FilePath]
findYamlFilesSkippingDirectories root skippedDirectoryNames = do
  rootExists <- doesDirectoryExist root
  if not rootExists
    then pure []
    else go root
  where
    go current = do
      entries <- sort <$> listDirectory current
      fmap concat $
        forM entries $ \entry -> do
          let path = current </> entry
          isDirectory <- doesDirectoryExist path
          if isDirectory
            then
              if entry `elem` skippedDirectoryNames
                then pure []
                else go path
            else pure [path | takeExtension path == ".yaml"]
