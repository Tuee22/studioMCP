{-# LANGUAGE OverloadedStrings #-}

module Util.JsonSpec (spec) where

import Data.Aeson (object, (.=))
import qualified Data.ByteString.Lazy as LBS
import StudioMCP.Util.Json
import Test.Hspec

spec :: Spec
spec = do
  describe "encodeJson" $ do
    it "encodes simple object" $ do
      let json = object ["key" .= ("value" :: String)]
      let encoded = encodeJson json
      LBS.length encoded `shouldSatisfy` (> 0)

    it "encodes numbers" $ do
      let json = object ["count" .= (42 :: Int)]
      let encoded = encodeJson json
      LBS.length encoded `shouldSatisfy` (> 0)

    it "encodes nested objects" $ do
      let json = object ["outer" .= object ["inner" .= ("value" :: String)]]
      let encoded = encodeJson json
      LBS.length encoded `shouldSatisfy` (> 0)

    it "encodes arrays" $ do
      let json = object ["items" .= ([1, 2, 3] :: [Int])]
      let encoded = encodeJson json
      LBS.length encoded `shouldSatisfy` (> 0)

    it "produces valid JSON bytes" $ do
      let json = object ["test" .= True]
      let encoded = encodeJson json
      -- JSON should start with { for objects
      LBS.take 1 encoded `shouldBe` "{"
