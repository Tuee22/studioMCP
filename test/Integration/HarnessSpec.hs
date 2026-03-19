module Integration.HarnessSpec
  ( spec,
  )
where

import System.Environment (lookupEnv)
import System.Exit (ExitCode (ExitSuccess))
import System.Process (readProcessWithExitCode)
import Test.Hspec (Spec, describe, it, pendingWith, shouldBe)

spec :: Spec
spec =
  describe "integration harness" $ do
    it "reaches the MinIO health endpoint" $
      runIfEnabled $ do
        exitCode <- curlExitCode "http://localhost:9000/minio/health/live"
        exitCode `shouldBe` ExitSuccess

    it "reaches the Pulsar admin endpoint" $
      runIfEnabled $ do
        exitCode <- curlExitCode "http://localhost:8080/admin/v2/clusters"
        exitCode `shouldBe` ExitSuccess

runIfEnabled :: IO () -> IO ()
runIfEnabled action = do
  enabled <- lookupEnv "STUDIOMCP_RUN_INTEGRATION"
  case enabled of
    Just "1" -> action
    _ ->
      pendingWith
        "set STUDIOMCP_RUN_INTEGRATION=1 and use scripts/integration-harness.sh to run sidecar-backed integration tests"

curlExitCode :: String -> IO ExitCode
curlExitCode url = do
  (exitCode, _, _) <- readProcessWithExitCode "curl" ["-fsS", url] ""
  pure exitCode
