module Integration.HarnessSpec
  ( spec,
  )
where

import Control.Monad (unless, when)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import StudioMCP.Util.Cabal (ensureCabalBootstrap)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, removePathForcibly)
import System.Exit (ExitCode (ExitSuccess, ExitFailure))
import System.IO.Unsafe (unsafePerformIO)
import System.Process (readProcessWithExitCode)
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe, shouldContain)

spec :: Spec
spec =
  describe "integration harness" $ do
    it "validates deterministic helper processes through the outer-container CLI" $ do
      ensureOuterContainer
      output <- runOuterCliExpectSuccess ["validate", "boundary"]
      output `shouldContain` "Boundary validation passed."

    it "runs the FFmpeg adapter against deterministic fixtures through the outer-container CLI" $ do
      ensureOuterContainer
      output <- runOuterCliExpectSuccess ["validate", "ffmpeg-adapter"]
      output `shouldContain` "FFmpeg adapter validation passed."

    it "runs the sequential executor validation through the outer-container CLI" $ do
      ensureOuterContainer
      output <- runOuterCliExpectSuccess ["validate", "executor"]
      output `shouldContain` "Executor validation passed."

    it "runs the worker runtime validation through the outer-container CLI" $ do
      ensureOuterEnvironment
      output <- runOuterCliExpectSuccess ["validate", "worker"]
      output `shouldContain` "Worker validation passed."

    it "validates the cluster through the outer-container CLI" $ do
      ensureOuterEnvironment
      _ <- runOuterCliExpectSuccess ["validate", "cluster"]
      pure ()

    it "validates Keycloak bootstrap and connectivity through the cluster edge" $ do
      ensureOuterEnvironment
      output <- runOuterCliExpectSuccess ["validate", "keycloak"]
      output `shouldContain` "validate keycloak: PASS"

    it "runs a real successful and failing DAG end to end through the outer-container CLI" $ do
      ensureOuterEnvironment
      output <- runOuterCliExpectSuccess ["validate", "e2e"]
      output `shouldContain` "End-to-end validation passed."

    it "publishes and consumes a validation lifecycle through real Pulsar" $ do
      ensureOuterEnvironment
      output <- runOuterCliExpectSuccess ["validate", "pulsar"]
      output `shouldContain` "Pulsar validation passed."

    it "round-trips immutable objects through real MinIO" $ do
      ensureOuterEnvironment
      output <- runOuterCliExpectSuccess ["validate", "minio"]
      output `shouldContain` "MinIO validation passed."

    it "exercises the MCP HTTP transport through the outer-container CLI" $ do
      ensureOuterEnvironment
      output <- runOuterCliExpectSuccess ["validate", "mcp-http"]
      output `shouldContain` "MCP HTTP validation passed."

    it "runs the inference advisory mode validation through the outer-container CLI" $ do
      ensureOuterContainer
      output <- runOuterCliExpectSuccess ["validate", "inference"]
      output `shouldContain` "Inference validation passed."

    it "exercises the observability surface through the outer-container CLI" $ do
      ensureOuterEnvironment
      output <- runOuterCliExpectSuccess ["validate", "observability"]
      output `shouldContain` "Observability validation passed."

    it "rehearses horizontal scaling across deployed MCP replicas" $ do
      ensureOuterEnvironment
      output <- runOuterCliExpectSuccessWithDiagnostics ["validate", "mcp-horizontal-scale"]
      output `shouldContain` "validate horizontal-scale: PASS"

    it "exercises MCP auth through the cluster edge" $ do
      ensureOuterEnvironment
      output <- runOuterCliExpectSuccess ["validate", "mcp-auth"]
      output `shouldContain` "validate mcp-auth: PASS"

    it "exercises MCP conformance through the outer-container CLI" $ do
      ensureOuterEnvironment
      output <- runOuterCliExpectSuccess ["validate", "mcp-conformance"]
      output `shouldContain` "validate mcp-conformance: PASS"

    it "exercises the BFF browser surface through the outer-container CLI" $ do
      ensureOuterEnvironment
      output <- runOuterCliExpectSuccess ["validate", "web-bff"]
      output `shouldContain` "validate web-bff: PASS"

ensureOuterContainer :: IO ()
ensureOuterContainer = do
  alreadyReady <- readIORef outerContainerReadyRef
  unless alreadyReady $ do
    insideOuterContainer <- isInsideOuterContainer
    if insideOuterContainer
      then do
        buildOuterContainerBinary
        pure ()
      else do
        _ <- runComposeExpectSuccess ["build", "studiomcp"]
        pure ()
    writeIORef outerContainerReadyRef True

ensureOuterEnvironment :: IO ()
ensureOuterEnvironment = do
  alreadyReady <- readIORef outerEnvironmentReadyRef
  unless alreadyReady $ do
    ensureOuterContainer
    -- Use the idempotent 'cluster ensure' command which:
    -- 1. Creates/verifies cluster (idempotent)
    -- 2. Deploys sidecars (idempotent via helm upgrade --install)
    -- 3. Waits for all services to be ready
    _ <- runOuterCliExpectSuccessWithDiagnostics ["cluster", "ensure"]
    writeIORef outerEnvironmentReadyRef True

runComposeExpectSuccess :: [String] -> IO String
runComposeExpectSuccess args = do
  (exitCode, stdoutText, stderrText) <-
    readProcessWithExitCode
      "docker"
      (["compose", "-f", "docker-compose.yaml"] <> args)
      ""
  let combinedOutput = stdoutText <> stderrText
  exitCode `shouldBe` ExitSuccess
  pure combinedOutput

runOuterCliExpectSuccess :: [String] -> IO String
runOuterCliExpectSuccess args = do
  insideOuterContainer <- isInsideOuterContainer
  (exitCode, stdoutText, stderrText) <-
    if insideOuterContainer
      then readProcessWithExitCode "studiomcp" args ""
      else
        readProcessWithExitCode
          "docker"
          ( ["compose", "-f", "docker-compose.yaml", "run", "--rm", "studiomcp", "studiomcp"]
              <> args
          )
          ""
  let combinedOutput = stdoutText <> stderrText
  case exitCode of
    ExitSuccess -> pure combinedOutput
    ExitFailure code -> do
      expectationFailure $
        "Command 'studiomcp " <> unwords args <> "' failed with exit code " <> show code <> ":\n"
          <> "--- stdout ---\n" <> stdoutText <> "\n"
          <> "--- stderr ---\n" <> stderrText
      pure ""

-- | Like runOuterCliExpectSuccess but provides detailed diagnostics on failure.
-- Use this for critical setup commands (like cluster ensure) where understanding
-- the failure reason is essential.
runOuterCliExpectSuccessWithDiagnostics :: [String] -> IO String
runOuterCliExpectSuccessWithDiagnostics args = do
  insideOuterContainer <- isInsideOuterContainer
  (exitCode, stdoutText, stderrText) <-
    if insideOuterContainer
      then readProcessWithExitCode "studiomcp" args ""
      else
        readProcessWithExitCode
          "docker"
          ( ["compose", "-f", "docker-compose.yaml", "run", "--rm", "studiomcp", "studiomcp"]
              <> args
          )
          ""
  let combinedOutput = stdoutText <> stderrText
  case exitCode of
    ExitSuccess -> pure combinedOutput
    ExitFailure code -> do
      expectationFailure $
        "Command 'studiomcp " <> unwords args <> "' failed with exit code " <> show code <> ":\n"
          <> "--- stdout ---\n" <> stdoutText <> "\n"
          <> "--- stderr ---\n" <> stderrText
      pure ""  -- unreachable due to expectationFailure throwing, but needed for types

outerContainerReadyRef :: IORef Bool
outerContainerReadyRef = unsafePerformIO (newIORef False)
{-# NOINLINE outerContainerReadyRef #-}

outerEnvironmentReadyRef :: IORef Bool
outerEnvironmentReadyRef = unsafePerformIO (newIORef False)
{-# NOINLINE outerEnvironmentReadyRef #-}

buildOuterContainerBinary :: IO ()
buildOuterContainerBinary = do
  ensureCabalBootstrap
  let buildDir = "/opt/build/studiomcp-cli"
  buildDirExists <- doesDirectoryExist buildDir
  when buildDirExists $
    removePathForcibly buildDir
  createDirectoryIfMissing True buildDir
  (exitCode, stdoutText, stderrText) <-
    readProcessWithExitCode
      "cabal"
      [ "--builddir=" <> buildDir
      , "install"
      , "exe:studiomcp"
      , "--installdir"
      , "/usr/local/bin"
      , "--overwrite-policy=always"
      ]
      ""
  case exitCode of
    ExitSuccess -> pure ()
    ExitFailure code ->
      expectationFailure $
        "Command 'cabal install exe:studiomcp' failed with exit code " <> show code <> ":\n"
          <> "--- stdout ---\n" <> stdoutText <> "\n"
          <> "--- stderr ---\n" <> stderrText

isInsideOuterContainer :: IO Bool
isInsideOuterContainer = doesFileExist "/.dockerenv"
