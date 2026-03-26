{-# LANGUAGE OverloadedStrings #-}

module Inference.TypesSpec (spec) where

import Data.Aeson (decode, encode)
import StudioMCP.Inference.Types
import Test.Hspec

spec :: Spec
spec = do
  describe "InferenceRequest" $ do
    it "can be created with prompt" $ do
      let req = InferenceRequest "Generate a plan"
      inferencePrompt req `shouldBe` "Generate a plan"

    it "can be compared for equality" $ do
      InferenceRequest "a" `shouldBe` InferenceRequest "a"
      InferenceRequest "a" `shouldNotBe` InferenceRequest "b"

    it "round-trips through JSON" $ do
      let req = InferenceRequest "test prompt"
      (decode (encode req) :: Maybe InferenceRequest) `shouldBe` Just req

    it "can be shown" $ do
      show (InferenceRequest "test") `shouldContain` "InferenceRequest"

  describe "InferenceResponse" $ do
    it "can be created with advice" $ do
      let resp = InferenceResponse "Use FFmpeg for transcoding"
      inferenceAdvice resp `shouldBe` "Use FFmpeg for transcoding"

    it "can be compared for equality" $ do
      InferenceResponse "a" `shouldBe` InferenceResponse "a"
      InferenceResponse "a" `shouldNotBe` InferenceResponse "b"

    it "round-trips through JSON" $ do
      let resp = InferenceResponse "advice text"
      (decode (encode resp) :: Maybe InferenceResponse) `shouldBe` Just resp

    it "can be shown" $ do
      show (InferenceResponse "test") `shouldContain` "InferenceResponse"
