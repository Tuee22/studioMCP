{-# LANGUAGE OverloadedStrings #-}

module Config.LoadSpec (spec) where

import qualified Data.Text as T
import StudioMCP.Config.Load
import StudioMCP.Config.Types
import Test.Hspec

spec :: Spec
spec = do
  describe "loadAppConfig" $ do
    it "loads config without error" $ do
      config <- loadAppConfig
      -- Should load with default values when env vars not set
      appMode config `shouldBe` ServerMode

    it "has default pulsar HTTP URL" $ do
      config <- loadAppConfig
      T.isInfixOf "pulsar" (pulsarHttpUrl config) `shouldBe` True

    it "has default pulsar binary URL" $ do
      config <- loadAppConfig
      T.isInfixOf "pulsar" (pulsarBinaryUrl config) `shouldBe` True

    it "has default minio endpoint" $ do
      config <- loadAppConfig
      T.isInfixOf "minio" (minioEndpoint config) `shouldBe` True

    it "has default minio credentials" $ do
      config <- loadAppConfig
      T.null (minioAccessKey config) `shouldBe` False
      T.null (minioSecretKey config) `shouldBe` False
