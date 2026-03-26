{-# LANGUAGE OverloadedStrings #-}

module Tools.BoundarySpec
  ( spec,
  )
where

import qualified Data.Map.Strict as Map
import StudioMCP.Result.Failure (FailureDetail (..), failureCode)
import StudioMCP.Tools.Boundary
  ( BoundaryCommand (..),
    BoundaryResult (..),
    runBoundaryCommand,
  )
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe)

spec :: Spec
spec =
  describe "runBoundaryCommand" $ do
    it "captures stdout, stderr, and exit code for a successful helper process" $ do
      result <- runBoundaryCommand successCommand
      result
        `shouldBe` Right
          BoundaryResult
            { boundaryStdout = "success-stdout",
              boundaryStderr = "success-stderr",
              boundaryExitCode = 0
            }

    it "projects a failing helper process into a structured tool failure" $ do
      result <- runBoundaryCommand failureCommand
      case result of
        Left failureDetail -> do
          failureCode failureDetail `shouldBe` "boundary-process-failed"
          Map.lookup "stdoutSnippet" (failureContext failureDetail) `shouldBe` Just "failure-stdout"
          Map.lookup "stderrSnippet" (failureContext failureDetail) `shouldBe` Just "failure-stderr"
        Right boundaryResult ->
          expectationFailure ("expected failure but got success: " <> show boundaryResult)

    it "projects a timed-out helper process into a structured timeout failure" $ do
      result <- runBoundaryCommand timeoutCommand
      case result of
        Left failureDetail -> do
          failureCode failureDetail `shouldBe` "boundary-timeout"
          Map.lookup "stdoutSnippet" (failureContext failureDetail) `shouldBe` Just "timeout-stdout"
          Map.lookup "stderrSnippet" (failureContext failureDetail) `shouldBe` Just "timeout-stderr"
        Right boundaryResult ->
          expectationFailure ("expected timeout but got success: " <> show boundaryResult)
  where
    successCommand =
      BoundaryCommand
        { boundaryExecutable = "sh",
          boundaryArguments = ["-c", "printf 'success-stdout'; printf 'success-stderr' 1>&2; exit 0"],
          boundaryStdin = "",
          boundaryTimeoutSeconds = 2
        }
    failureCommand =
      BoundaryCommand
        { boundaryExecutable = "sh",
          boundaryArguments = ["-c", "printf 'failure-stdout'; printf 'failure-stderr' 1>&2; exit 9"],
          boundaryStdin = "",
          boundaryTimeoutSeconds = 2
        }
    timeoutCommand =
      BoundaryCommand
        { boundaryExecutable = "sh",
          -- Use a short output followed by sleep, flush stdout/stderr first
          boundaryArguments = ["-c", "printf 'timeout-stdout' && printf 'timeout-stderr' 1>&2 && sleep 60"],
          boundaryStdin = "",
          boundaryTimeoutSeconds = 1
        }
