{-# LANGUAGE OverloadedStrings #-}

module Util.TimeSpec (spec) where

import StudioMCP.Util.Time
import Test.Hspec

spec :: Spec
spec = do
  describe "secondsToNominalDiffTime" $ do
    it "converts 0 seconds" $ do
      secondsToNominalDiffTime 0 `shouldBe` 0

    it "converts positive seconds" $ do
      secondsToNominalDiffTime 60 `shouldBe` 60

    it "converts large values" $ do
      secondsToNominalDiffTime 3600 `shouldBe` 3600

    it "preserves value through conversion" $ do
      let seconds = 120
      secondsToNominalDiffTime seconds `shouldBe` fromIntegral seconds
