{-# LANGUAGE OverloadedStrings #-}

module Util.ExceptionsSpec (spec) where

import Control.Exception (catch, throw)
import StudioMCP.Util.Exceptions
import Test.Hspec

spec :: Spec
spec = do
  describe "StudioMCPException" $ do
    it "can be created from text" $ do
      let ex = StudioMCPException "error message"
      unStudioMCPException ex `shouldBe` "error message"

    it "can be compared for equality" $ do
      StudioMCPException "a" `shouldBe` StudioMCPException "a"
      StudioMCPException "a" `shouldNotBe` StudioMCPException "b"

    it "can be shown" $ do
      show (StudioMCPException "test") `shouldContain` "StudioMCPException"

    it "can be thrown and caught" $ do
      let ex = StudioMCPException "test error"
      result <- (throw ex >> pure "not reached") `catch` \(StudioMCPException msg) ->
        pure msg
      result `shouldBe` "test error"

    it "is an Exception instance" $ do
      let ex = StudioMCPException "exception"
      -- Just verify we can use it in exception context
      caught <- catch
        (throw ex >> pure False)
        (\(_ :: StudioMCPException) -> pure True)
      caught `shouldBe` True
