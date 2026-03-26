{-# LANGUAGE OverloadedStrings #-}

module Observability.CorrelationIdSpec (spec) where

import Control.Concurrent (threadDelay)
import qualified Data.Text as T
import StudioMCP.Observability.CorrelationId
import Test.Hspec

spec :: Spec
spec = do
  describe "CorrelationId" $ do
    it "can be created from text" $ do
      let cid = CorrelationId "req-123"
      unCorrelationId cid `shouldBe` "req-123"

    it "can be compared for equality" $ do
      CorrelationId "a" `shouldBe` CorrelationId "a"
      CorrelationId "a" `shouldNotBe` CorrelationId "b"

  describe "correlationIdHeader" $ do
    it "returns the standard header name" $ do
      correlationIdHeader `shouldBe` "X-Correlation-ID"

  describe "generateCorrelationId" $ do
    it "generates unique IDs" $ do
      cid1 <- generateCorrelationId
      threadDelay 1000  -- 1ms delay to ensure different timestamp
      cid2 <- generateCorrelationId
      cid1 `shouldNotBe` cid2

    it "starts with req- prefix" $ do
      cid <- generateCorrelationId
      T.isPrefixOf "req-" (unCorrelationId cid) `shouldBe` True

  describe "parseCorrelationId" $ do
    it "parses non-empty text" $ do
      parseCorrelationId "req-123" `shouldBe` Just (CorrelationId "req-123")

    it "returns Nothing for empty text" $ do
      parseCorrelationId "" `shouldBe` Nothing

    it "accepts any non-empty string" $ do
      parseCorrelationId "custom-id" `shouldBe` Just (CorrelationId "custom-id")

  describe "RequestContext" $ do
    it "can be created via newRequestContext" $ do
      ctx <- newRequestContext "GET" "/api/health" (Just "127.0.0.1") (Just "curl/7.0")
      rcMethod ctx `shouldBe` "GET"
      rcPath ctx `shouldBe` "/api/health"
      rcSourceIp ctx `shouldBe` Just "127.0.0.1"
      rcUserAgent ctx `shouldBe` Just "curl/7.0"

    it "generates correlation ID" $ do
      ctx <- newRequestContext "POST" "/api/run" Nothing Nothing
      T.null (unCorrelationId (rcCorrelationId ctx)) `shouldBe` False

    it "sets tenant and subject to Nothing initially" $ do
      ctx <- newRequestContext "GET" "/" Nothing Nothing
      rcTenantId ctx `shouldBe` Nothing
      rcSubjectId ctx `shouldBe` Nothing

  describe "withCorrelationId" $ do
    it "passes correlation ID to action" $ do
      let cid = CorrelationId "test-cid"
      result <- withCorrelationId cid $ \received -> pure (received == cid)
      result `shouldBe` True

  describe "extractCorrelationId" $ do
    it "returns existing ID from header" $ do
      cid <- extractCorrelationId (Just "existing-123")
      unCorrelationId cid `shouldBe` "existing-123"

    it "generates new ID when header is Nothing" $ do
      cid <- extractCorrelationId Nothing
      T.isPrefixOf "req-" (unCorrelationId cid) `shouldBe` True

    it "generates new ID when header is empty" $ do
      cid <- extractCorrelationId (Just "")
      T.isPrefixOf "req-" (unCorrelationId cid) `shouldBe` True
