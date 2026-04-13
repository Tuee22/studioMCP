{-# LANGUAGE OverloadedStrings #-}

module MCP.CoreSpec (spec) where

import Data.Aeson (Value(..), object, (.=))
import StudioMCP.MCP.Core
import StudioMCP.MCP.Protocol.Types
import Test.Hspec

spec :: Spec
spec = do
  describe "defaultServerConfig" $ do
    it "has correct server name" $ do
      mscServerName defaultServerConfig `shouldBe` "studioMCP"

    it "has correct server version" $ do
      mscServerVersion defaultServerConfig `shouldBe` "0.1.0"

    it "has tools capability" $ do
      case scTools (mscCapabilities defaultServerConfig) of
        Just cap -> tcListChanged cap `shouldBe` Just True
        Nothing -> expectationFailure "Expected tools capability"

    it "has resources capability" $ do
      case scResources (mscCapabilities defaultServerConfig) of
        Just cap -> do
          rcSubscribe cap `shouldBe` Just True
          rcListChanged cap `shouldBe` Just True
        Nothing -> expectationFailure "Expected resources capability"

    it "has prompts capability" $ do
      case scPrompts (mscCapabilities defaultServerConfig) of
        Just cap -> pcListChanged cap `shouldBe` Just True
        Nothing -> expectationFailure "Expected prompts capability"

    it "has logging capability" $ do
      scLogging (mscCapabilities defaultServerConfig) `shouldBe` Just LoggingCapability

  describe "newMcpServer" $ do
    it "creates server in uninitialized state" $ do
      server <- newMcpServer defaultServerConfig
      -- Server should be created successfully
      msConfig server `shouldBe` defaultServerConfig

  describe "serverInfo" $ do
    it "returns correct server info" $ do
      let info = serverInfo defaultServerConfig
      siName info `shouldBe` "studioMCP"
      siVersion info `shouldBe` "0.1.0"

  describe "buildServerCapabilities" $ do
    it "returns config capabilities" $ do
      let caps = buildServerCapabilities defaultServerConfig
      caps `shouldBe` mscCapabilities defaultServerConfig

  describe "handleMessage" $ do
    it "returns error for invalid JSON-RPC" $ do
      server <- newMcpServer defaultServerConfig
      let invalidMsg = String "not-an-object"
      result <- handleMessage server invalidMsg
      case result of
        Just _ -> pure ()  -- Should return error response
        Nothing -> expectationFailure "Expected response for invalid message"

    it "returns error response for unparseable request" $ do
      server <- newMcpServer defaultServerConfig
      let badMsg = object ["jsonrpc" .= ("1.0" :: String)]  -- Wrong version
      result <- handleMessage server badMsg
      case result of
        Just _ -> pure ()
        Nothing -> expectationFailure "Expected error response"

  describe "stopMcpServer" $ do
    it "stops the server without error" $ do
      server <- newMcpServer defaultServerConfig
      -- This should not throw
      stopMcpServer server

  describe "McpServerConfig" $ do
    it "can be compared for equality" $ do
      defaultServerConfig `shouldBe` defaultServerConfig

    it "can create custom config" $ do
      let custom = McpServerConfig
            { mscServerName = "custom"
            , mscServerVersion = "1.0.0"
            , mscCapabilities = mscCapabilities defaultServerConfig
            }
      mscServerName custom `shouldBe` "custom"
      mscServerVersion custom `shouldBe` "1.0.0"
