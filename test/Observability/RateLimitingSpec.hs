{-# LANGUAGE OverloadedStrings #-}

module Observability.RateLimitingSpec (spec) where

import StudioMCP.Auth.Types (TenantId (..))
import StudioMCP.Observability.RateLimiting
import Test.Hspec

spec :: Spec
spec = do
  describe "RateLimitWindow" $ do
    it "distinguishes window types" $ do
      PerSecond `shouldNotBe` PerMinute
      PerMinute `shouldNotBe` PerHour
      PerSecond `shouldNotBe` PerHour

    it "can be shown" $ do
      show PerSecond `shouldContain` "PerSecond"
      show PerMinute `shouldContain` "PerMinute"
      show PerHour `shouldContain` "PerHour"

  describe "RateLimitKey" $ do
    it "can create TenantKey" $ do
      let key = TenantKey (TenantId "tenant-1")
      case key of
        TenantKey (TenantId t) -> t `shouldBe` "tenant-1"
        _ -> expectationFailure "Expected TenantKey"

    it "can compare keys for equality" $ do
      TenantKey (TenantId "t1") `shouldBe` TenantKey (TenantId "t1")
      TenantKey (TenantId "t1") `shouldNotBe` TenantKey (TenantId "t2")
      IpKey "127.0.0.1" `shouldBe` IpKey "127.0.0.1"

  describe "RateLimiterConfig" $ do
    it "has sensible defaults" $ do
      rlcRequestsPerSecond defaultRateLimiterConfig `shouldSatisfy` (> 0)
      rlcRequestsPerMinute defaultRateLimiterConfig `shouldSatisfy` (> 0)
      rlcRequestsPerHour defaultRateLimiterConfig `shouldSatisfy` (> 0)
      rlcEnabled defaultRateLimiterConfig `shouldBe` True

    it "has burst multiplier" $ do
      rlcBurstMultiplier defaultRateLimiterConfig `shouldSatisfy` (> 1.0)

  describe "RateLimitResult" $ do
    it "can represent allowed" $ do
      let result = RateLimitAllowed 9 10
      case result of
        RateLimitAllowed remaining limit -> do
          remaining `shouldBe` 9
          limit `shouldBe` 10
        _ -> expectationFailure "Expected RateLimitAllowed"

    it "can be compared for equality" $ do
      RateLimitAllowed 5 10 `shouldBe` RateLimitAllowed 5 10
      RateLimitAllowed 5 10 `shouldNotBe` RateLimitAllowed 4 10

  describe "newRateLimiterService" $ do
    it "creates service with config" $ do
      service <- newRateLimiterService defaultRateLimiterConfig
      rlsConfig service `shouldBe` defaultRateLimiterConfig

  describe "checkRateLimit" $ do
    it "allows request under limit" $ do
      service <- newRateLimiterService defaultRateLimiterConfig
      let key = TenantKey (TenantId "tenant-1")
      result <- checkRateLimit service key PerMinute
      case result of
        RateLimitAllowed remaining limit -> do
          remaining `shouldSatisfy` (> 0)
          limit `shouldBe` rlcRequestsPerMinute defaultRateLimiterConfig
        _ -> expectationFailure "Expected RateLimitAllowed"

    it "returns unlimited when disabled" $ do
      let config = defaultRateLimiterConfig { rlcEnabled = False }
      service <- newRateLimiterService config
      let key = TenantKey (TenantId "tenant-1")
      result <- checkRateLimit service key PerSecond
      case result of
        RateLimitAllowed remaining _ -> remaining `shouldSatisfy` (> 1000)
        _ -> expectationFailure "Expected RateLimitAllowed with high limit"

  describe "recordRequest" $ do
    it "increments counter" $ do
      service <- newRateLimiterService defaultRateLimiterConfig
      let key = TenantKey (TenantId "tenant-1")
      recordRequest service key PerMinute
      result <- checkRateLimit service key PerMinute
      case result of
        RateLimitAllowed remaining _ ->
          remaining `shouldBe` (rlcRequestsPerMinute defaultRateLimiterConfig - 1)
        _ -> expectationFailure "Expected RateLimitAllowed"

  describe "getRateLimitMetrics" $ do
    it "returns empty metrics initially" $ do
      service <- newRateLimiterService defaultRateLimiterConfig
      metrics <- getRateLimitMetrics service
      rlmTotalChecks metrics `shouldBe` 0
      rlmAllowedRequests metrics `shouldBe` 0
      rlmDeniedRequests metrics `shouldBe` 0

    it "tracks checks" $ do
      service <- newRateLimiterService defaultRateLimiterConfig
      let key = TenantKey (TenantId "tenant-1")
      _ <- checkRateLimit service key PerMinute
      metrics <- getRateLimitMetrics service
      rlmTotalChecks metrics `shouldBe` 1
      rlmAllowedRequests metrics `shouldBe` 1
