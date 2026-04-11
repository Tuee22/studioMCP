{-# LANGUAGE OverloadedStrings #-}

module Auth.PassthroughGuardSpec (spec) where

import Data.List (sort)
import Data.Maybe (isJust)
import StudioMCP.Auth.PassthroughGuard
import Test.Hspec

spec :: Spec
spec = do
  describe "sanitizeOutboundHeaders" $ do
    it "removes auth-related headers and keeps safe headers" $ do
      let headers =
            [ ("Authorization", "Bearer secret-token")
            , ("cookie", "session=abc")
            , ("X-Request-Id", "req-123")
            ]
      sanitizeOutboundHeaders headers `shouldBe` [("X-Request-Id", "req-123")]

  describe "detectTokenPatterns" $ do
    it "detects bearer tokens and access-token query params" $ do
      let patterns = detectTokenPatterns "Bearer secret access_token=abc123"
      sort patterns `shouldBe` sort ["access_token_param", "bearer_token"]

    it "returns no patterns for safe text" $ do
      detectTokenPatterns "harmless request body" `shouldBe` []

  describe "assertNoTokenPassthrough" $ do
    it "returns a timestamped violation instead of crashing on detected content" $ do
      violation <- assertNoTokenPassthrough "Bearer secret-token"
      violation `shouldSatisfy` isJust
      fmap pvPattern violation `shouldBe` Just "bearer_token"

    it "returns Nothing for safe content" $ do
      assertNoTokenPassthrough "safe payload" `shouldReturn` Nothing

  describe "checkRequestForTokenLeakage" $ do
    it "detects leaked headers, body tokens, and query tokens" $ do
      violations <-
        checkRequestForTokenLeakage
          [("Authorization", "Bearer secret-token"), ("X-Request-Id", "req-123")]
          (Just "refresh_token=rotating-secret")
          (Just "access_token=query-secret")
          (Just "corr-123")
          (Just "artifact-service")
      fmap pvPattern violations
        `shouldBe` ["auth_header_present", "refresh_token_param", "access_token_param"]
      map pvCorrelationId violations `shouldBe` replicate 3 (Just "corr-123")
      map pvTargetService violations `shouldBe` replicate 3 (Just "artifact-service")

  describe "auditOutboundRequest" $ do
    it "returns True when no violations are found" $ do
      auditOutboundRequest [("X-Request-Id", "req-123")] (Just "safe body") Nothing Nothing Nothing
        `shouldReturn` True

    it "returns False when violations are found" $ do
      auditOutboundRequest [("Authorization", "Bearer secret-token")] Nothing Nothing Nothing Nothing
        `shouldReturn` False
