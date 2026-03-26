{-# LANGUAGE OverloadedStrings #-}

module Util.LoggingSpec (spec) where

import StudioMCP.Util.Logging
import Test.Hspec

spec :: Spec
spec = do
  describe "configureProcessLogging" $ do
    it "configures logging without error" $ do
      -- Should not throw
      configureProcessLogging

    it "can be called multiple times" $ do
      configureProcessLogging
      configureProcessLogging
      -- Should not throw

  describe "logInfo" $ do
    it "logs message without error" $ do
      -- Just verify it doesn't throw
      -- Output goes to stdout which we don't capture here
      logInfo "test message"
