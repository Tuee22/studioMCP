{-# LANGUAGE OverloadedStrings #-}

module MCP.ContextSpec (spec) where

import Data.Aeson (toJSON)
import StudioMCP.MCP.Context
import Test.Hspec

spec :: Spec
spec = do
  describe "CorrelationId" $ do
    it "can be created from text" $ do
      let cid = CorrelationId "test-123"
      case cid of
        CorrelationId t -> t `shouldBe` "test-123"

    it "can be compared for equality" $ do
      CorrelationId "a" `shouldBe` CorrelationId "a"
      CorrelationId "a" `shouldNotBe` CorrelationId "b"

    it "can be shown" $ do
      show (CorrelationId "test") `shouldContain` "CorrelationId"

    it "serializes to JSON" $ do
      let cid = CorrelationId "test-id"
      toJSON cid `shouldBe` toJSON ("test-id" :: String)

  describe "newCorrelationId" $ do
    it "generates unique IDs" $ do
      cid1 <- newCorrelationId
      cid2 <- newCorrelationId
      cid1 `shouldNotBe` cid2

  describe "RequestContext" $ do
    it "can be created via newRequestContext" $ do
      ctx <- newRequestContext "initialize" Nothing
      ctxMethod ctx `shouldBe` "initialize"
      ctxSession ctx `shouldBe` Nothing
      ctxRequestId ctx `shouldBe` Nothing

    it "includes request ID when provided" $ do
      ctx <- newRequestContext "test" (Just (toJSON (1 :: Int)))
      ctxRequestId ctx `shouldBe` Just (toJSON (1 :: Int))

    it "can be compared for equality" $ do
      ctx1 <- newRequestContext "test" Nothing
      ctx2 <- newRequestContext "test" Nothing
      -- Each has different correlation ID, so they differ
      ctxMethod ctx1 `shouldBe` ctxMethod ctx2
      ctxCorrelationId ctx1 `shouldNotBe` ctxCorrelationId ctx2

  describe "getSessionFromContext" $ do
    it "returns Nothing when no session" $ do
      ctx <- newRequestContext "test" Nothing
      getSessionFromContext ctx `shouldBe` Nothing

  describe "getTenantFromContext" $ do
    it "returns Nothing when no session" $ do
      ctx <- newRequestContext "test" Nothing
      getTenantFromContext ctx `shouldBe` Nothing

  describe "getSubjectFromContext" $ do
    it "returns Nothing when no session" $ do
      ctx <- newRequestContext "test" Nothing
      getSubjectFromContext ctx `shouldBe` Nothing

  describe "withCorrelationId" $ do
    it "updates correlation ID" $ do
      ctx <- newRequestContext "test" Nothing
      let newCid = CorrelationId "new-id"
          updated = withCorrelationId newCid ctx
      ctxCorrelationId updated `shouldBe` newCid

  describe "contextLogFields" $ do
    it "includes correlationId field" $ do
      ctx <- newRequestContext "test" Nothing
      let fields = contextLogFields ctx
      lookup "correlationId" fields `shouldSatisfy` (/= Nothing)

    it "includes method field" $ do
      ctx <- newRequestContext "test-method" Nothing
      let fields = contextLogFields ctx
      lookup "method" fields `shouldBe` Just (toJSON ("test-method" :: String))
