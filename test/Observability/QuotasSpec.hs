{-# LANGUAGE OverloadedStrings #-}

module Observability.QuotasSpec (spec) where

import StudioMCP.Auth.Types (TenantId (..))
import StudioMCP.Observability.Quotas
import Test.Hspec

spec :: Spec
spec = do
  describe "QuotaType" $ do
    it "distinguishes all quota types" $ do
      StorageQuota `shouldNotBe` ConcurrentRunsQuota
      ConcurrentRunsQuota `shouldNotBe` RequestsPerMinuteQuota
      RequestsPerMinuteQuota `shouldNotBe` UploadsPerHourQuota
      UploadsPerHourQuota `shouldNotBe` ToolCallsPerMinuteQuota

    it "can be shown" $ do
      show StorageQuota `shouldContain` "StorageQuota"

  describe "QuotaConfig" $ do
    it "has sensible defaults" $ do
      qcStorageLimit defaultQuotaConfig `shouldSatisfy` (> 0)
      qcConcurrentRunsLimit defaultQuotaConfig `shouldSatisfy` (> 0)
      qcRequestsPerMinuteLimit defaultQuotaConfig `shouldSatisfy` (> 0)
      qcEnforcement defaultQuotaConfig `shouldBe` True

  describe "TenantQuotaUsage" $ do
    it "can be compared for equality" $ do
      let u1 = TenantQuotaUsage 100 2 10 5 20
          u2 = TenantQuotaUsage 100 2 10 5 20
      u1 `shouldBe` u2

  describe "QuotaCheckResult" $ do
    it "can represent allowed" $ do
      QuotaAllowed `shouldBe` QuotaAllowed

    it "can represent exceeded" $ do
      let result = QuotaExceeded StorageQuota 100 50
      case result of
        QuotaExceeded qt _ _ -> qt `shouldBe` StorageQuota
        _ -> expectationFailure "Expected QuotaExceeded"

    it "can represent warning" $ do
      let result = QuotaWarning StorageQuota 80 100 80
      case result of
        QuotaWarning qt _ _ threshold -> do
          qt `shouldBe` StorageQuota
          threshold `shouldBe` 80
        _ -> expectationFailure "Expected QuotaWarning"

  describe "QuotaError" $ do
    it "has error codes" $ do
      quotaErrorCode (QuotaLimitExceeded (TenantId "t1") StorageQuota) `shouldBe` "quota-exceeded"
      quotaErrorCode (QuotaReservationFailed (TenantId "t1") StorageQuota) `shouldBe` "reservation-failed"
      quotaErrorCode QuotaServiceUnavailable `shouldBe` "service-unavailable"

  describe "newQuotaService" $ do
    it "creates service with config" $ do
      service <- newQuotaService defaultQuotaConfig
      qsConfig service `shouldBe` defaultQuotaConfig

  describe "checkQuota" $ do
    it "allows request under limit" $ do
      service <- newQuotaService defaultQuotaConfig
      result <- checkQuota service (TenantId "tenant-1") ConcurrentRunsQuota
      result `shouldBe` QuotaAllowed

    it "tracks metrics" $ do
      service <- newQuotaService defaultQuotaConfig
      _ <- checkQuota service (TenantId "tenant-1") ConcurrentRunsQuota
      metrics <- getQuotaMetrics service
      qmTotalChecks metrics `shouldBe` 1
      qmAllowedChecks metrics `shouldBe` 1

  describe "reserveQuota" $ do
    it "succeeds under limit" $ do
      service <- newQuotaService defaultQuotaConfig
      result <- reserveQuota service (TenantId "tenant-1") ConcurrentRunsQuota 1
      result `shouldBe` Right ()

    it "fails when exceeds limit" $ do
      let config = defaultQuotaConfig { qcConcurrentRunsLimit = 2 }
      service <- newQuotaService config
      _ <- reserveQuota service (TenantId "tenant-1") ConcurrentRunsQuota 1
      _ <- reserveQuota service (TenantId "tenant-1") ConcurrentRunsQuota 1
      result <- reserveQuota service (TenantId "tenant-1") ConcurrentRunsQuota 1
      case result of
        Left (QuotaLimitExceeded _ _) -> pure ()
        _ -> expectationFailure "Expected QuotaLimitExceeded"

  describe "releaseQuota" $ do
    it "decrements usage" $ do
      service <- newQuotaService defaultQuotaConfig
      _ <- reserveQuota service (TenantId "tenant-1") ConcurrentRunsQuota 5
      releaseQuota service (TenantId "tenant-1") ConcurrentRunsQuota 3
      result <- checkQuota service (TenantId "tenant-1") ConcurrentRunsQuota
      result `shouldBe` QuotaAllowed

  describe "getQuotaMetrics" $ do
    it "returns empty metrics initially" $ do
      service <- newQuotaService defaultQuotaConfig
      metrics <- getQuotaMetrics service
      qmTotalChecks metrics `shouldBe` 0
      qmAllowedChecks metrics `shouldBe` 0
      qmDeniedChecks metrics `shouldBe` 0
