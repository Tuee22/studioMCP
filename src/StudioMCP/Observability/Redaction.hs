{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Observability.Redaction
  ( -- * Redaction Functions
    redactSecrets,
    redactToken,
    redactCredentials,
    redactSensitiveHeaders,

    -- * Redaction Patterns
    RedactionPattern (..),
    defaultRedactionPatterns,

    -- * Safe Logging
    redactForLogging,
    redactJsonValue,

    -- * Redaction Config
    RedactionConfig (..),
    defaultRedactionConfig,
  )
where

import Data.Aeson (Value (..))
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Vector as V

-- | Patterns for secret redaction
data RedactionPattern = RedactionPattern
  { rpName :: Text,
    rpPatternPrefix :: Text,
    rpReplacement :: Text
  }
  deriving (Eq, Show)

-- | Default redaction patterns for common secrets
defaultRedactionPatterns :: [RedactionPattern]
defaultRedactionPatterns =
  [ RedactionPattern "jwt" "eyJ" "[JWT REDACTED]",
    RedactionPattern "bearer" "Bearer " "Bearer [REDACTED]",
    RedactionPattern "api_key" "sk-" "[API KEY REDACTED]",
    RedactionPattern "password" "password" "[PASSWORD REDACTED]",
    RedactionPattern "secret" "secret" "[SECRET REDACTED]",
    RedactionPattern "aws_key" "AKIA" "[AWS KEY REDACTED]",
    RedactionPattern "aws_secret" "aws_secret" "[AWS SECRET REDACTED]"
  ]

-- | Redaction configuration
data RedactionConfig = RedactionConfig
  { rcPatterns :: [RedactionPattern],
    rcSensitiveHeaders :: [Text],
    rcSensitiveFields :: [Text],
    rcEnabled :: Bool
  }
  deriving (Eq, Show)

-- | Default redaction configuration
defaultRedactionConfig :: RedactionConfig
defaultRedactionConfig =
  RedactionConfig
    { rcPatterns = defaultRedactionPatterns,
      rcSensitiveHeaders =
        [ "authorization",
          "x-api-key",
          "cookie",
          "set-cookie",
          "x-auth-token",
          "x-access-token",
          "x-refresh-token"
        ],
      rcSensitiveFields =
        [ "password",
          "secret",
          "token",
          "access_token",
          "refresh_token",
          "api_key",
          "apiKey",
          "secretAccessKey",
          "private_key",
          "privateKey",
          "credentials"
        ],
      rcEnabled = True
    }

-- | Redact secrets from text using default patterns
redactSecrets :: Text -> Text
redactSecrets = redactSecretsWithConfig defaultRedactionConfig

-- | Redact secrets with custom config
redactSecretsWithConfig :: RedactionConfig -> Text -> Text
redactSecretsWithConfig config text
  | not (rcEnabled config) = text
  | otherwise = foldr applyPattern text (rcPatterns config)
  where
    applyPattern pattern t =
      if rpPatternPrefix pattern `T.isInfixOf` t
        then redactPattern pattern t
        else t

-- | Apply a single redaction pattern
redactPattern :: RedactionPattern -> Text -> Text
redactPattern pattern text =
  let prefix = rpPatternPrefix pattern
      replacement = rpReplacement pattern
   in case T.breakOn prefix text of
        (before, match)
          | T.null match -> text
          | otherwise ->
              before <> replacement <> redactPattern pattern (T.drop (findTokenEnd (T.drop (T.length prefix) match) + T.length prefix) match)
  where
    findTokenEnd t =
      case T.findIndex isTokenDelimiter t of
        Just idx -> idx
        Nothing -> T.length t
    isTokenDelimiter c = c `elem` [' ', '\n', '\r', '\t', '"', '\'', ',', ';', '}', ']']

-- | Redact a bearer or JWT token
redactToken :: Text -> Text
redactToken token
  | "Bearer " `T.isPrefixOf` token = "Bearer [REDACTED]"
  | "eyJ" `T.isPrefixOf` token = "[JWT REDACTED]"
  | T.length token > 20 = T.take 4 token <> "..." <> T.takeEnd 4 token <> " [REDACTED]"
  | otherwise = "[REDACTED]"

-- | Redact credentials from a map of key-value pairs
redactCredentials :: [(Text, Text)] -> [(Text, Text)]
redactCredentials = map redactPair
  where
    sensitiveKeys = rcSensitiveFields defaultRedactionConfig
    redactPair (k, v)
      | T.toLower k `elem` sensitiveKeys = (k, "[REDACTED]")
      | otherwise = (k, redactSecrets v)

-- | Redact sensitive HTTP headers
redactSensitiveHeaders :: [(Text, Text)] -> [(Text, Text)]
redactSensitiveHeaders = map redactHeader
  where
    sensitiveHeaders = rcSensitiveHeaders defaultRedactionConfig
    redactHeader (k, v)
      | T.toLower k `elem` sensitiveHeaders = (k, redactToken v)
      | otherwise = (k, v)

-- | Redact text for safe logging
redactForLogging :: Text -> Text
redactForLogging = redactSecretsWithConfig defaultRedactionConfig

-- | Redact sensitive fields in a JSON value
redactJsonValue :: Value -> Value
redactJsonValue = redactJsonWithConfig defaultRedactionConfig

-- | Redact JSON with custom config
redactJsonWithConfig :: RedactionConfig -> Value -> Value
redactJsonWithConfig config value
  | not (rcEnabled config) = value
  | otherwise = go value
  where
    sensitiveFields = rcSensitiveFields config
    go (Object obj) =
      Object $ KeyMap.mapWithKey redactField obj
    go (Array arr) =
      Array $ V.map go arr
    go (String s) =
      String $ redactSecretsWithConfig config s
    go other = other

    redactField key val
      | keyText `elem` sensitiveFields = String "[REDACTED]"
      | otherwise = go val
      where
        keyText = T.toLower (Key.toText key)
