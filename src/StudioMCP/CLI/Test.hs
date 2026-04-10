module StudioMCP.CLI.Test
  ( runTestCommand,
  )
where

import Control.Monad (unless)
import StudioMCP.CLI.Command (TestCommand (..))
import System.Exit (ExitCode (..), exitFailure, exitWith)
import System.Process (callProcess, readProcessWithExitCode)

-- | Run test command
runTestCommand :: TestCommand -> IO ()
runTestCommand command =
  case command of
    TestAllCommand -> runTestAll
    TestUnitCommand -> runTestUnit
    TestIntegrationCommand -> runTestIntegration

-- | Run unit tests via cabal
runTestUnit :: IO ()
runTestUnit = do
  putStrLn "Running unit tests..."
  (exitCode, _, _) <- readProcessWithExitCode "cabal"
    ["test", "unit-tests", "--test-show-details=direct"]
    ""
  case exitCode of
    ExitSuccess -> putStrLn "Unit tests passed."
    ExitFailure code -> do
      putStrLn $ "Unit tests failed with exit code " <> show code
      exitWith exitCode

-- | Run integration tests via cabal
runTestIntegration :: IO ()
runTestIntegration = do
  putStrLn "Running integration tests..."
  (exitCode, _, _) <- readProcessWithExitCode "cabal"
    ["test", "integration-tests", "--test-show-details=direct"]
    ""
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
  (unitExit, _, _) <- readProcessWithExitCode "cabal"
    ["test", "unit-tests", "--test-show-details=direct"]
    ""
  let unitPassed = unitExit == ExitSuccess
  putStrLn ""
  putStrLn "=== Integration Tests ==="
  (integrationExit, _, _) <- readProcessWithExitCode "cabal"
    ["test", "integration-tests", "--test-show-details=direct"]
    ""
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
