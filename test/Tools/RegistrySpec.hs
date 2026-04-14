{-# LANGUAGE OverloadedStrings #-}

module Tools.RegistrySpec (spec) where

import qualified Data.Map.Strict as Map
import StudioMCP.Tools.Registry
import StudioMCP.Tools.Types (ToolName (..))
import Test.Hspec

spec :: Spec
spec = do
  describe "ToolRegistry" $ do
    it "can be unwrapped to Map" $ do
      let registry = emptyToolRegistry
      Map.null (unToolRegistry registry) `shouldBe` True

    it "can be compared for equality" $ do
      emptyToolRegistry `shouldBe` emptyToolRegistry

    it "can be shown" $ do
      show emptyToolRegistry `shouldContain` "ToolRegistry"

  describe "emptyToolRegistry" $ do
    it "creates empty registry" $ do
      let registry = emptyToolRegistry
      Map.size (unToolRegistry registry) `shouldBe` 0

    it "has no tools" $ do
      let registry = emptyToolRegistry
      Map.lookup (ToolName "ffmpeg") (unToolRegistry registry) `shouldBe` Nothing

  describe "defaultToolRegistry" $ do
    it "registers the expanded boundary tool set" $ do
      let registry = defaultToolRegistry
      Map.lookup (ToolName "ffmpeg") (unToolRegistry registry) `shouldBe` Just "ffmpeg"
      Map.lookup (ToolName "sox") (unToolRegistry registry) `shouldBe` Just "sox"
      Map.lookup (ToolName "imagemagick") (unToolRegistry registry) `shouldBe` Just "convert"
