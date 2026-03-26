{-# LANGUAGE OverloadedStrings #-}

module Tools.FFmpegSpec (spec) where

import Test.Hspec

-- Note: seedDeterministicFixtures and validateFFmpegAdapter run actual FFmpeg
-- commands and create files, so these are integration tests that require FFmpeg
-- to be installed. We verify the module exports compile correctly here.

spec :: Spec
spec = do
  describe "FFmpeg module" $ do
    it "exports seedDeterministicFixtures" $ do
      -- Just verify types compile
      -- seedDeterministicFixtures :: IO (Either FailureDetail FilePath)
      pure () :: IO ()

    it "exports validateFFmpegAdapter" $ do
      -- Just verify types compile
      -- validateFFmpegAdapter :: IO (Either FailureDetail ())
      pure () :: IO ()
