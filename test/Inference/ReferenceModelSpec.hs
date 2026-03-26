{-# LANGUAGE OverloadedStrings #-}

module Inference.ReferenceModelSpec (spec) where

import StudioMCP.Inference.ReferenceModel
import Test.Hspec

spec :: Spec
spec = do
  describe "ReferenceModelConfig" $ do
    it "can be created with URL" $ do
      let config = ReferenceModelConfig "http://localhost:11434/api/generate"
      referenceModelUrl config `shouldBe` "http://localhost:11434/api/generate"

    it "can be compared for equality" $ do
      ReferenceModelConfig "a" `shouldBe` ReferenceModelConfig "a"
      ReferenceModelConfig "a" `shouldNotBe` ReferenceModelConfig "b"

    it "can be shown" $ do
      show (ReferenceModelConfig "http://test") `shouldContain` "ReferenceModelConfig"

    it "stores the full URL" $ do
      let url = "http://inference.local:8000/v1/completions"
          config = ReferenceModelConfig url
      referenceModelUrl config `shouldBe` url
