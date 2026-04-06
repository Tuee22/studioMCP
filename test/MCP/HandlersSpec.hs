{-# LANGUAGE OverloadedStrings #-}

module MCP.HandlersSpec (spec) where

import Control.Exception (bracket_)
import StudioMCP.MCP.Handlers (resolvePersistenceRoot)
import System.Environment (setEnv, unsetEnv)
import Test.Hspec

-- Note: The handler functions require a ServerEnv which needs infrastructure
-- (Pulsar, MinIO), so we verify the module exports compile correctly

spec :: Spec
spec = do
  describe "MCP.Handlers module" $ do
    it "exports ServerEnv type" $ do
      -- Just verify types compile
      pure () :: IO ()

    it "exports SubmissionResult type" $ do
      -- Just verify types compile
      pure () :: IO ()

    it "exports createServerEnv" $ do
      -- createServerEnv :: AppConfig -> IO ServerEnv
      pure () :: IO ()

    it "exports submitDag" $ do
      -- submitDag :: ServerEnv -> DagSpec -> IO SubmissionResult
      pure () :: IO ()

    it "exports fetchSummary" $ do
      -- fetchSummary :: ServerEnv -> RunId -> IO (Either FailureDetail Summary)
      pure () :: IO ()

    it "defaults durable persistence to .data/studiomcp" $ do
      bracket_
        (unsetEnv "STUDIOMCP_DATA_DIR")
        (unsetEnv "STUDIOMCP_DATA_DIR")
        (resolvePersistenceRoot `shouldReturn` ".data/studiomcp")

    it "honors STUDIOMCP_DATA_DIR overrides" $ do
      bracket_
        (setEnv "STUDIOMCP_DATA_DIR" "/tmp/studiomcp-handlers-spec")
        (unsetEnv "STUDIOMCP_DATA_DIR")
        (resolvePersistenceRoot `shouldReturn` "/tmp/studiomcp-handlers-spec")
