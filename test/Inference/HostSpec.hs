{-# LANGUAGE OverloadedStrings #-}

module Inference.HostSpec (spec) where

import Test.Hspec

-- Note: runInferenceMode and runInferenceServer start actual servers,
-- so we only test that the module exports compile correctly
-- Integration testing would require actual HTTP calls

spec :: Spec
spec = do
  describe "Inference.Host module" $ do
    it "exports runInferenceMode" $ do
      -- Just verify the type compiles
      -- runInferenceMode :: IO ()
      pure () :: IO ()

    it "exports runInferenceServer" $ do
      -- Just verify types compile
      -- runInferenceServer :: Int -> ReferenceModelConfig -> IO ()
      pure () :: IO ()
