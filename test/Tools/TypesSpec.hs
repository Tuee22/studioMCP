{-# LANGUAGE OverloadedStrings #-}

module Tools.TypesSpec (spec) where

import StudioMCP.Tools.Types
import Test.Hspec

spec :: Spec
spec = do
  describe "ToolName" $ do
    it "can be created from text" $ do
      let name = ToolName "ffmpeg"
      unToolName name `shouldBe` "ffmpeg"

    it "can be compared for equality" $ do
      ToolName "a" `shouldBe` ToolName "a"
      ToolName "a" `shouldNotBe` ToolName "b"

    it "has Ord instance" $ do
      ToolName "apple" < ToolName "banana" `shouldBe` True

    it "can be shown" $ do
      show (ToolName "test") `shouldContain` "ToolName"

  describe "ToolInvocation" $ do
    it "can be created with tool and args" $ do
      let inv = ToolInvocation (ToolName "ffmpeg") ["-i", "input.mp4"]
      invocationTool inv `shouldBe` ToolName "ffmpeg"
      invocationArgs inv `shouldBe` ["-i", "input.mp4"]

    it "can be compared for equality" $ do
      let inv1 = ToolInvocation (ToolName "tool") ["arg"]
          inv2 = ToolInvocation (ToolName "tool") ["arg"]
          inv3 = ToolInvocation (ToolName "other") ["arg"]
      inv1 `shouldBe` inv2
      inv1 `shouldNotBe` inv3

    it "can have empty args" $ do
      let inv = ToolInvocation (ToolName "echo") []
      invocationArgs inv `shouldBe` []

    it "can be shown" $ do
      show (ToolInvocation (ToolName "t") []) `shouldContain` "ToolInvocation"
