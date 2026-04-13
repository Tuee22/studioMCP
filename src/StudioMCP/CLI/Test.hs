module StudioMCP.CLI.Test
  ( runTestCommand,
  )
where

import Control.Monad (unless)
import StudioMCP.CLI.Command (TestCommand (..))
import StudioMCP.Util.Cabal (cabalBuildDir, ensureCabalBootstrap)
import System.Exit (ExitCode (..), exitFailure, exitWith)
import System.Process (createProcess, proc, readProcessWithExitCode, waitForProcess)

-- | Run test command
runTestCommand :: TestCommand -> IO ()
runTestCommand command = do
  ensureCabalBootstrap
  case command of
    TestAllCommand -> runTestAll
    TestUnitCommand -> runTestUnit
    TestIntegrationCommand -> runTestIntegration

-- | Run unit tests via cabal
runTestUnit :: IO ()
runTestUnit = do
  putStrLn "Running unit tests..."
  exitCode <- runCabalTest "unit-tests"
  case exitCode of
    ExitSuccess -> putStrLn "Unit tests passed."
    ExitFailure code -> do
      putStrLn $ "Unit tests failed with exit code " <> show code
      exitWith exitCode

-- | Run integration tests via cabal
runTestIntegration :: IO ()
runTestIntegration = do
  putStrLn "Running integration tests..."
  exitCode <- runCabalTest "integration-tests"
  case exitCode of
    ExitSuccess -> putStrLn "Integration tests passed."
    ExitFailure code -> do
      putStrLn $ "Integration tests failed with exit code " <> show code
      exitWith exitCode

-- | Run all tests (unit + integration)
runTestAll :: IO ()
runTestAll = do
  putStrLn "Running all tests..."
  putStrLn ""
  putStrLn "=== Unit Tests ==="
  unitExit <- runCabalTest "unit-tests"
  let unitPassed = unitExit == ExitSuccess
  putStrLn ""
  putStrLn "=== Integration Tests ==="
  integrationExit <- runCabalTest "integration-tests"
  let integrationPassed = integrationExit == ExitSuccess
  putStrLn ""
  putStrLn "=== Test Summary ==="
  putStrLn $ "Unit tests: " <> if unitPassed then "PASSED" else "FAILED"
  putStrLn $ "Integration tests: " <> if integrationPassed then "PASSED" else "FAILED"
  unless (unitPassed && integrationPassed) $ do
    putStrLn ""
    putStrLn "Some tests failed."
    exitFailure
  putStrLn "All tests passed."

runCabalTest :: String -> IO ExitCode
runCabalTest suiteName = do
  buildExitCode <- buildTestSuite suiteName
  case buildExitCode of
    ExitFailure _ -> pure buildExitCode
    ExitSuccess -> do
      binaryPathExitCodeOrPath <- resolveTestBinaryPath suiteName
      case binaryPathExitCodeOrPath of
        Left exitCode -> pure exitCode
        Right binaryPath -> runTestBinary binaryPath

buildTestSuite :: String -> IO ExitCode
buildTestSuite suiteName = do
  (_, _, _, processHandle) <-
    createProcess $
      proc
        "cabal"
        [ "--builddir=" <> cabalBuildDir
        , "build"
        , "test:" <> suiteName
        ]
  waitForProcess processHandle

resolveTestBinaryPath :: String -> IO (Either ExitCode FilePath)
resolveTestBinaryPath suiteName = do
  (exitCode, stdoutText, _stderrText) <-
    readProcessWithExitCode
      "cabal"
      [ "--builddir=" <> cabalBuildDir
      , "list-bin"
      , "test:" <> suiteName
      ]
      ""
  case exitCode of
    ExitFailure _ -> pure (Left exitCode)
    ExitSuccess ->
      case lines stdoutText of
        binaryPath : _ | not (null binaryPath) -> pure (Right binaryPath)
        _ -> pure (Left (ExitFailure 1))

runTestBinary :: FilePath -> IO ExitCode
runTestBinary binaryPath = do
  (_, _, _, processHandle) <-
    createProcess $
      proc binaryPath []
  waitForProcess processHandle
