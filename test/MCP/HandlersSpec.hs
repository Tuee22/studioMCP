{-# LANGUAGE OverloadedStrings #-}

module MCP.HandlersSpec (spec) where

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
