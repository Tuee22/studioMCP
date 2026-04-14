{-# LANGUAGE OverloadedStrings #-}

module Models.RegistrySpec (spec) where

import StudioMCP.Models.Registry
import System.Environment (lookupEnv, setEnv, unsetEnv)
import Test.Hspec

spec :: Spec
spec = do
  describe "lookupModelArtifact" $ do
    it "finds known models case-insensitively" $ do
      fmap modelId (lookupModelArtifact "WHISPER-BASE-EN") `shouldBe` Just "whisper-base-en"

    it "returns Nothing for unknown models" $ do
      lookupModelArtifact "missing-model" `shouldBe` Nothing

  describe "resolveModelSourceUrl" $ do
    it "uses the environment override when present" $ do
      let modelArtifact = case lookupModelArtifact "basic-pitch" of
            Just artifact -> artifact
            Nothing -> error "expected registered model"
          envName = "STUDIOMCP_MODEL_SOURCE_BASIC_PITCH"
      originalValue <- lookupEnv envName
      setEnv envName "file:///tmp/basic-pitch-test-model.npz"
      result <- resolveModelSourceUrl modelArtifact
      case originalValue of
        Just value -> setEnv envName value
        Nothing -> unsetEnv envName
      result `shouldBe` Right "file:///tmp/basic-pitch-test-model.npz"

    it "returns a configuration error when no source is available" $ do
      let modelArtifact = case lookupModelArtifact "generaluser-gs" of
            Just artifact -> artifact
            Nothing -> error "expected registered model"
          envName = "STUDIOMCP_MODEL_SOURCE_GENERALUSER_GS"
      originalValue <- lookupEnv envName
      unsetEnv envName
      result <- resolveModelSourceUrl modelArtifact
      case originalValue of
        Just value -> setEnv envName value
        Nothing -> pure ()
      result `shouldSatisfy` either (const True) (const False)
