{-# LANGUAGE OverloadedStrings #-}

module MCP.TypesSpec (spec) where

import StudioMCP.MCP.Types
import Test.Hspec

spec :: Spec
spec = do
  describe "ServerStatus" $ do
    it "distinguishes ServerBooting" $ do
      ServerBooting `shouldBe` ServerBooting
      ServerBooting `shouldNotBe` ServerReady

    it "distinguishes ServerReady" $ do
      ServerReady `shouldBe` ServerReady
      ServerReady `shouldNotBe` ServerBooting

    it "can be shown" $ do
      show ServerBooting `shouldContain` "ServerBooting"
      show ServerReady `shouldContain` "ServerReady"
