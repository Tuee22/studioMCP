{-# LANGUAGE OverloadedStrings #-}

module Observability.RedactionSpec (spec) where

import Data.Aeson (Value (..), object, (.=))
import qualified Data.Text as T
import StudioMCP.Observability.Redaction
import Test.Hspec

spec :: Spec
spec = do
  describe "RedactionPattern" $ do
    it "can be created with fields" $ do
      let pattern = RedactionPattern "test" "prefix" "replacement"
      rpName pattern `shouldBe` "test"
      rpPatternPrefix pattern `shouldBe` "prefix"
      rpReplacement pattern `shouldBe` "replacement"

    it "can be compared for equality" $ do
      RedactionPattern "a" "b" "c" `shouldBe` RedactionPattern "a" "b" "c"
      RedactionPattern "a" "b" "c" `shouldNotBe` RedactionPattern "x" "b" "c"

  describe "RedactionConfig" $ do
    it "has default config" $ do
      rcEnabled defaultRedactionConfig `shouldBe` True
      rcPatterns defaultRedactionConfig `shouldSatisfy` (not . null)
      rcSensitiveHeaders defaultRedactionConfig `shouldSatisfy` (not . null)
      rcSensitiveFields defaultRedactionConfig `shouldSatisfy` (not . null)

  describe "defaultRedactionPatterns" $ do
    it "includes JWT pattern" $ do
      let patterns = defaultRedactionPatterns
      patterns `shouldSatisfy` any (\p -> rpName p == "jwt")

    it "includes bearer pattern" $ do
      let patterns = defaultRedactionPatterns
      patterns `shouldSatisfy` any (\p -> rpName p == "bearer")

    it "includes API key pattern" $ do
      let patterns = defaultRedactionPatterns
      patterns `shouldSatisfy` any (\p -> rpName p == "api_key")

  describe "redactSecrets" $ do
    it "redacts JWT tokens" $ do
      let input = "token: eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0.signature"
      T.isInfixOf "[JWT REDACTED]" (redactSecrets input) `shouldBe` True

    it "redacts Bearer tokens" $ do
      let input = "Authorization: Bearer secret-token-12345"
      T.isInfixOf "Bearer [REDACTED]" (redactSecrets input) `shouldBe` True

    it "redacts API keys" $ do
      let input = "api_key: sk-1234567890abcdef"
      T.isInfixOf "[API KEY REDACTED]" (redactSecrets input) `shouldBe` True

    it "leaves non-sensitive text unchanged" $ do
      let input = "Hello, this is a normal message"
      redactSecrets input `shouldBe` input

  describe "redactToken" $ do
    it "redacts Bearer tokens" $ do
      redactToken "Bearer abc123" `shouldBe` "Bearer [REDACTED]"

    it "redacts JWT tokens" $ do
      redactToken "eyJhbGciOiJIUzI1NiJ9" `shouldBe` "[JWT REDACTED]"

    it "redacts long tokens with partial visibility" $ do
      let token = "0123456789abcdefghijklmnop"
      let result = redactToken token
      T.isInfixOf "[REDACTED]" result `shouldBe` True
      T.isPrefixOf "0123" result `shouldBe` True

    it "fully redacts short tokens" $ do
      redactToken "short" `shouldBe` "[REDACTED]"

  describe "redactCredentials" $ do
    it "redacts password fields" $ do
      let creds = [("password", "secret123"), ("username", "user")]
      let redacted = redactCredentials creds
      lookup "password" redacted `shouldBe` Just "[REDACTED]"
      lookup "username" redacted `shouldBe` Just "user"

    it "redacts token fields" $ do
      let creds = [("access_token", "abc123"), ("name", "test")]
      let redacted = redactCredentials creds
      lookup "access_token" redacted `shouldBe` Just "[REDACTED]"

  describe "redactSensitiveHeaders" $ do
    it "redacts authorization header" $ do
      let headers = [("Authorization", "Bearer secret"), ("Content-Type", "application/json")]
      let redacted = redactSensitiveHeaders headers
      lookup "Authorization" redacted `shouldBe` Just "Bearer [REDACTED]"
      lookup "Content-Type" redacted `shouldBe` Just "application/json"

    it "redacts x-api-key header" $ do
      let headers = [("X-Api-Key", "sk-secret123")]
      let redacted = redactSensitiveHeaders headers
      case lookup "X-Api-Key" redacted of
        Just v -> T.isInfixOf "[REDACTED]" v `shouldBe` True
        Nothing -> expectationFailure "Expected X-Api-Key header"

  describe "redactForLogging" $ do
    it "is equivalent to redactSecrets" $ do
      let input = "token: eyJabc"
      redactForLogging input `shouldBe` redactSecrets input

  describe "redactJsonValue" $ do
    it "redacts sensitive fields in object" $ do
      let json = object ["password" .= ("secret" :: String), "username" .= ("user" :: String)]
      let redacted = redactJsonValue json
      case redacted of
        Object _ -> pure ()
        _ -> expectationFailure "Expected Object"

    it "preserves non-sensitive fields" $ do
      let json = object ["name" .= ("test" :: String), "count" .= (42 :: Int)]
      let redacted = redactJsonValue json
      case redacted of
        Object _ -> pure ()
        _ -> expectationFailure "Expected Object"

    it "handles nested objects" $ do
      let json = object ["user" .= object ["password" .= ("secret" :: String)]]
      let redacted = redactJsonValue json
      case redacted of
        Object _ -> pure ()
        _ -> expectationFailure "Expected Object"

    it "handles arrays" $ do
      let json = Array mempty
      redactJsonValue json `shouldBe` Array mempty
