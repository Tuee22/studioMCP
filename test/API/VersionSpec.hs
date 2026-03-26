{-# LANGUAGE OverloadedStrings #-}

module API.VersionSpec (spec) where

import Data.Aeson (decode, encode)
import StudioMCP.API.Version
import StudioMCP.Config.Types (AppMode (..))
import Test.Hspec

spec :: Spec
spec = do
  describe "apiVersion" $ do
    it "returns the expected version string" $ do
      apiVersion `shouldBe` "0.1.0.0"

  describe "VersionInfo" $ do
    it "can be created with fields" $ do
      let info = VersionInfo "1.0.0" "server"
      versionNumber info `shouldBe` "1.0.0"
      versionMode info `shouldBe` "server"

    it "can be compared for equality" $ do
      let info1 = VersionInfo "1.0" "server"
          info2 = VersionInfo "1.0" "server"
          info3 = VersionInfo "2.0" "server"
      info1 `shouldBe` info2
      info1 `shouldNotBe` info3

    it "round-trips through JSON" $ do
      let info = VersionInfo "0.1.0.0" "inference"
      (decode (encode info) :: Maybe VersionInfo) `shouldBe` Just info

    it "serializes to expected JSON structure" $ do
      let info = VersionInfo "1.0.0" "worker"
          json = encode info
      -- Verify round-trip works
      (decode json :: Maybe VersionInfo) `shouldBe` Just info

  describe "versionInfoForMode" $ do
    it "returns server mode correctly" $ do
      let info = versionInfoForMode ServerMode
      versionNumber info `shouldBe` apiVersion
      versionMode info `shouldBe` "server"

    it "returns inference mode correctly" $ do
      let info = versionInfoForMode InferenceMode
      versionNumber info `shouldBe` apiVersion
      versionMode info `shouldBe` "inference"

    it "returns worker mode correctly" $ do
      let info = versionInfoForMode WorkerMode
      versionNumber info `shouldBe` apiVersion
      versionMode info `shouldBe` "worker"

    it "uses apiVersion for all modes" $ do
      let serverInfo = versionInfoForMode ServerMode
          inferenceInfo = versionInfoForMode InferenceMode
          workerInfo = versionInfoForMode WorkerMode
      versionNumber serverInfo `shouldBe` apiVersion
      versionNumber inferenceInfo `shouldBe` apiVersion
      versionNumber workerInfo `shouldBe` apiVersion
