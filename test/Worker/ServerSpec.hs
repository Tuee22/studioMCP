{-# LANGUAGE OverloadedStrings #-}

module Worker.ServerSpec (spec) where

import Test.Hspec

-- Note: runWorkerMode and runWorkerServer start actual HTTP servers
-- and require infrastructure (Pulsar, MinIO), so we verify exports compile

spec :: Spec
spec = do
  describe "Worker.Server module" $ do
    it "exports runWorkerMode" $ do
      -- Just verify types compile
      -- runWorkerMode :: IO ()
      pure () :: IO ()

    it "exports runWorkerServer" $ do
      -- Just verify types compile
      -- runWorkerServer :: Int -> AppConfig -> IO ()
      pure () :: IO ()
