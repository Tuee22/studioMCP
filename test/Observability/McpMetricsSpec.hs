{-# LANGUAGE OverloadedStrings #-}

module Observability.McpMetricsSpec (spec) where

import qualified Data.Map.Strict as Map
import StudioMCP.Auth.Types (TenantId (..))
import StudioMCP.Observability.McpMetrics
import Test.Hspec

spec :: Spec
spec = do
  describe "McpMethodMetrics" $ do
    it "can be compared for equality" $ do
      let m1 = McpMethodMetrics 10 2 100.0 Nothing
          m2 = McpMethodMetrics 10 2 100.0 Nothing
      m1 `shouldBe` m2

  describe "ToolMetrics" $ do
    it "can be compared for equality" $ do
      let m1 = ToolMetrics 5 4 1 50.0
          m2 = ToolMetrics 5 4 1 50.0
      m1 `shouldBe` m2

  describe "ResourceMetrics" $ do
    it "can be compared for equality" $ do
      let m1 = ResourceMetrics 10 1 5
          m2 = ResourceMetrics 10 1 5
      m1 `shouldBe` m2

  describe "PromptMetrics" $ do
    it "can be compared for equality" $ do
      let m1 = PromptMetrics 3 0
          m2 = PromptMetrics 3 0
      m1 `shouldBe` m2

  describe "HealthMetrics" $ do
    it "can be compared for equality" $ do
      let m1 = HealthMetrics 100.0 50 2 0.04 5 3
          m2 = HealthMetrics 100.0 50 2 0.04 5 3
      m1 `shouldBe` m2

  describe "newMcpMetricsService" $ do
    it "creates service without error" $ do
      service <- newMcpMetricsService
      -- Just verify it creates successfully
      _ <- getMcpMetrics service
      pure ()

  describe "recordToolCall" $ do
    it "records successful tool call" $ do
      service <- newMcpMetricsService
      recordToolCall service "my-tool" (TenantId "tenant-1") 50.0 True
      metrics <- getMcpMetrics service
      case Map.lookup "my-tool" (mmsToolMetrics metrics) of
        Just tm -> do
          tmCallCount tm `shouldBe` 1
          tmSuccessCount tm `shouldBe` 1
          tmErrorCount tm `shouldBe` 0
        Nothing -> expectationFailure "Expected tool metrics"

    it "records failed tool call" $ do
      service <- newMcpMetricsService
      recordToolCall service "my-tool" (TenantId "tenant-1") 50.0 False
      metrics <- getMcpMetrics service
      case Map.lookup "my-tool" (mmsToolMetrics metrics) of
        Just tm -> do
          tmCallCount tm `shouldBe` 1
          tmSuccessCount tm `shouldBe` 0
          tmErrorCount tm `shouldBe` 1
        Nothing -> expectationFailure "Expected tool metrics"

    it "tracks tenant requests" $ do
      service <- newMcpMetricsService
      recordToolCall service "tool" (TenantId "tenant-1") 10.0 True
      recordToolCall service "tool" (TenantId "tenant-1") 10.0 True
      metrics <- getMcpMetrics service
      Map.lookup (TenantId "tenant-1") (mmsTenantRequestCounts metrics) `shouldBe` Just 2

  describe "recordResourceRead" $ do
    it "records resource read with cache hit" $ do
      service <- newMcpMetricsService
      recordResourceRead service "resource://test" (TenantId "tenant-1") True True
      metrics <- getMcpMetrics service
      case Map.lookup "resource://test" (mmsResourceMetrics metrics) of
        Just rm -> do
          rmReadCount rm `shouldBe` 1
          rmCacheHits rm `shouldBe` 1
        Nothing -> expectationFailure "Expected resource metrics"

  describe "recordPromptGet" $ do
    it "records prompt get" $ do
      service <- newMcpMetricsService
      recordPromptGet service "my-prompt" (TenantId "tenant-1") True
      metrics <- getMcpMetrics service
      case Map.lookup "my-prompt" (mmsPromptMetrics metrics) of
        Just pm -> pmGetCount pm `shouldBe` 1
        Nothing -> expectationFailure "Expected prompt metrics"

  describe "recordMethodCall" $ do
    it "records method call" $ do
      service <- newMcpMetricsService
      recordMethodCall service "initialize" 25.0 True
      metrics <- getMcpMetrics service
      case Map.lookup "initialize" (mmsMethodMetrics metrics) of
        Just mm -> do
          mmmCallCount mm `shouldBe` 1
          mmmErrorCount mm `shouldBe` 0
        Nothing -> expectationFailure "Expected method metrics"

  describe "recordError" $ do
    it "records error" $ do
      service <- newMcpMetricsService
      recordError service "validation" (Just (TenantId "tenant-1"))
      metrics <- getMcpMetrics service
      case Map.lookup "errors" (mmsMethodMetrics metrics) of
        Just mm -> mmmErrorCount mm `shouldBe` 1
        Nothing -> expectationFailure "Expected error metrics"

  describe "getHealthMetrics" $ do
    it "returns health metrics" $ do
      service <- newMcpMetricsService
      health <- getHealthMetrics service
      hmUptime health `shouldSatisfy` (>= 0)
      hmTotalRequests health `shouldBe` 0
      hmTotalErrors health `shouldBe` 0

  describe "renderPrometheusMetrics" $ do
    it "renders metrics in Prometheus format" $ do
      service <- newMcpMetricsService
      recordToolCall service "tool1" (TenantId "t1") 10.0 True
      metrics <- getMcpMetrics service
      let prometheus = renderPrometheusMetrics metrics
      prometheus `shouldSatisfy` \t -> "studiomcp_tool_calls_total" `isInfixOfText` t
      where
        isInfixOfText needle haystack =
          needle `elem` concatMap words (lines (show haystack))
