module Integration.HarnessSpec
  ( spec,
  )
where

import Control.Monad (unless)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import System.Exit (ExitCode (ExitSuccess))
import System.IO.Unsafe (unsafePerformIO)
import System.Process (readProcessWithExitCode)
import Test.Hspec (Spec, describe, it, shouldBe, shouldContain)

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

    it "exercises MCP conformance through the outer-container CLI" $ do
      ensureOuterEnvironment
      output <- runOuterCliExpectSuccess ["validate", "mcp-conformance"]
      output `shouldContain` "validate mcp-conformance: PASS"

    it "exercises the BFF browser surface through the outer-container CLI" $ do
      ensureOuterEnvironment
      output <- runOuterCliExpectSuccess ["validate", "web-bff"]
      output `shouldContain` "validate web-bff: PASS"

    it "runs the inference advisory mode validation through the outer-container CLI" $ do
      ensureOuterContainer
      output <- runOuterCliExpectSuccess ["validate", "inference"]
      output `shouldContain` "Inference validation passed."

    it "exercises the observability surface through the outer-container CLI" $ do
      ensureOuterEnvironment
      output <- runOuterCliExpectSuccess ["validate", "observability"]
      output `shouldContain` "Observability validation passed."

ensureOuterContainer :: IO ()
ensureOuterContainer = do
  alreadyReady <- readIORef outerContainerReadyRef
  unless alreadyReady $ do
    _ <- runComposeExpectSuccess ["up", "-d", "studiomcp-env"]
    _ <-
      runComposeExpectSuccess
        [ "exec",
          "-T",
          "studiomcp-env",
          "sh",
          "-lc",
          "rm -rf /tmp/studiomcp-dist && cabal --builddir=/tmp/studiomcp-dist build all && cabal --builddir=/tmp/studiomcp-dist install exe:studiomcp --installdir /usr/local/bin --overwrite-policy=always"
        ]
    writeIORef outerContainerReadyRef True

ensureOuterEnvironment :: IO ()
ensureOuterEnvironment = do
  alreadyReady <- readIORef outerEnvironmentReadyRef
  unless alreadyReady $ do
    ensureOuterContainer
    _ <- runOuterCliExpectSuccess ["cluster", "up"]
    _ <- runOuterCliExpectSuccess ["cluster", "deploy", "sidecars"]
    writeIORef outerEnvironmentReadyRef True

runComposeExpectSuccess :: [String] -> IO String
runComposeExpectSuccess args = do
  (exitCode, stdoutText, stderrText) <-
    readProcessWithExitCode
      "docker"
      (["compose", "-f", "docker/docker-compose.yaml"] <> args)
      ""
  let combinedOutput = stdoutText <> stderrText
  exitCode `shouldBe` ExitSuccess
  pure combinedOutput

runOuterCliExpectSuccess :: [String] -> IO String
runOuterCliExpectSuccess args = do
  (exitCode, stdoutText, stderrText) <-
    readProcessWithExitCode
      "docker"
      ( ["compose", "-f", "docker/docker-compose.yaml", "exec", "-T", "studiomcp-env", "studiomcp"]
          <> args
      )
      ""
  let combinedOutput = stdoutText <> stderrText
  exitCode `shouldBe` ExitSuccess
  pure combinedOutput

outerContainerReadyRef :: IORef Bool
outerContainerReadyRef = unsafePerformIO (newIORef False)
{-# NOINLINE outerContainerReadyRef #-}

outerEnvironmentReadyRef :: IORef Bool
outerEnvironmentReadyRef = unsafePerformIO (newIORef False)
{-# NOINLINE outerEnvironmentReadyRef #-}
