{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Auth.PassthroughGuard
  ( -- * Passthrough Violation
    PassthroughViolation (..),
    violationToText,

    -- * Header Sanitization
    sanitizeOutboundHeaders,
    isAuthHeader,

    -- * Token Detection
    assertNoTokenPassthrough,
    checkRequestForTokenLeakage,
    detectTokenPatterns,

    -- * Audit Functions
    logPassthroughViolation,
    auditOutboundRequest,
  )
where

import Data.Aeson
  ( ToJSON (toJSON),
    object,
    (.=),
  )
import qualified Data.ByteString as BS
import Data.CaseInsensitive (CI)
import qualified Data.CaseInsensitive as CI
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time (UTCTime, getCurrentTime)
import GHC.Generics (Generic)
import Network.HTTP.Types (Header, HeaderName)

-- | A token passthrough violation detected in an outbound request
data PassthroughViolation = PassthroughViolation
  { -- | Where the violation was detected
    pvLocation :: ViolationLocation,
    -- | What pattern was detected
    pvPattern :: Text,
    -- | When the violation was detected
    pvDetectedAt :: UTCTime,
    -- | Correlation ID for audit trail
    pvCorrelationId :: Maybe Text,
    -- | Target of the outbound request
    pvTargetService :: Maybe Text
  }
  deriving (Eq, Show, Generic)

-- | Where in the request the violation was found
data ViolationLocation
  = -- | Found in HTTP header
    HeaderLocation HeaderName
  | -- | Found in request body
    BodyLocation
  | -- | Found in URL query string
    QueryLocation
  deriving (Eq, Show, Generic)

instance ToJSON ViolationLocation where
  toJSON (HeaderLocation name) = toJSON $ "header:" <> TE.decodeUtf8 (CI.original name)
  toJSON BodyLocation = "body"
  toJSON QueryLocation = "query"

instance ToJSON PassthroughViolation where
  toJSON pv =
    object
      [ "location" .= pvLocation pv,
        "pattern" .= pvPattern pv,
        "detectedAt" .= pvDetectedAt pv,
        "correlationId" .= pvCorrelationId pv,
        "targetService" .= pvTargetService pv
      ]

-- | Convert violation to human-readable text for logging
violationToText :: PassthroughViolation -> Text
violationToText pv =
  "Token passthrough violation detected: "
    <> locationText (pvLocation pv)
    <> " contains forbidden pattern '"
    <> pvPattern pv
    <> "'"
    <> maybe "" (\cid -> " (correlation: " <> cid <> ")") (pvCorrelationId pv)
    <> maybe "" (\svc -> " (target: " <> svc <> ")") (pvTargetService pv)
  where
    locationText (HeaderLocation name) = "header '" <> TE.decodeUtf8 (CI.original name) <> "'"
    locationText BodyLocation = "request body"
    locationText QueryLocation = "query string"

-- | Headers that should be stripped from outbound requests
authHeaders :: [CI BS.ByteString]
authHeaders =
  [ "authorization",
    "x-forwarded-authorization",
    "proxy-authorization",
    "x-auth-token",
    "x-access-token",
    "x-api-key",
    "cookie" -- Cookies may contain session tokens
  ]

-- | Check if a header name is an auth-related header
isAuthHeader :: HeaderName -> Bool
isAuthHeader name = name `elem` authHeaders

-- | Sanitize headers by removing auth-related headers
sanitizeOutboundHeaders :: [Header] -> [Header]
sanitizeOutboundHeaders = filter (not . isAuthHeader . fst)

-- | Forbidden patterns that indicate token passthrough
forbiddenPatterns :: [(Text, Text)]
forbiddenPatterns =
  [ ("Bearer ", "bearer_token"),
    ("Basic ", "basic_auth"),
    ("access_token=", "access_token_param"),
    ("refresh_token=", "refresh_token_param"),
    ("id_token=", "id_token_param"),
    ("authorization:", "authorization_header"),
    ("Authorization:", "authorization_header"),
    ("eyJ", "jwt_prefix") -- JWT tokens start with base64 of {"
  ]

-- | Detect token patterns in text content
detectTokenPatterns :: Text -> [Text]
detectTokenPatterns content =
  [ patternName
    | (pattern, patternName) <- forbiddenPatterns,
      pattern `T.isInfixOf` content
  ]

-- | Assert that content does not contain token patterns
assertNoTokenPassthrough :: Text -> IO (Maybe PassthroughViolation)
assertNoTokenPassthrough content = do
  now <- getCurrentTime
  pure (mkBodyViolation now content)

mkBodyViolation :: UTCTime -> Text -> Maybe PassthroughViolation
mkBodyViolation detectedAt content =
  case detectTokenPatterns content of
    [] -> Nothing
    (pattern : _) ->
      Just
        PassthroughViolation
          { pvLocation = BodyLocation,
            pvPattern = pattern,
            pvDetectedAt = detectedAt,
            pvCorrelationId = Nothing,
            pvTargetService = Nothing
          }

-- | Check a complete outbound request for token leakage
checkRequestForTokenLeakage ::
  -- | Request headers
  [Header] ->
  -- | Request body (as text)
  Maybe Text ->
  -- | Query string (as text)
  Maybe Text ->
  -- | Correlation ID for audit
  Maybe Text ->
  -- | Target service name
  Maybe Text ->
  IO [PassthroughViolation]
checkRequestForTokenLeakage headers mBody mQuery correlationId targetService = do
  now <- getCurrentTime
  let headerViolations = checkHeaders now headers
      bodyViolations = checkBody now mBody
      queryViolations = checkQuery now mQuery
  pure $ headerViolations <> bodyViolations <> queryViolations
  where
    checkHeaders now hdrs =
      [ PassthroughViolation
          { pvLocation = HeaderLocation name,
            pvPattern = "auth_header_present",
            pvDetectedAt = now,
            pvCorrelationId = correlationId,
            pvTargetService = targetService
          }
        | (name, _) <- hdrs,
          isAuthHeader name
      ]
        <> [ PassthroughViolation
               { pvLocation = HeaderLocation name,
                 pvPattern = pattern,
                 pvDetectedAt = now,
                 pvCorrelationId = correlationId,
                 pvTargetService = targetService
               }
             | (name, value) <- hdrs,
               not (isAuthHeader name), -- Already caught above
               pattern <- detectTokenPatterns (TE.decodeUtf8 value)
           ]

    checkBody now mContent =
      case mContent of
        Nothing -> []
        Just content ->
          [ PassthroughViolation
              { pvLocation = BodyLocation,
                pvPattern = pattern,
                pvDetectedAt = now,
                pvCorrelationId = correlationId,
                pvTargetService = targetService
              }
            | pattern <- detectTokenPatterns content
          ]

    checkQuery now mContent =
      case mContent of
        Nothing -> []
        Just content ->
          [ PassthroughViolation
              { pvLocation = QueryLocation,
                pvPattern = pattern,
                pvDetectedAt = now,
                pvCorrelationId = correlationId,
                pvTargetService = targetService
              }
            | pattern <- detectTokenPatterns content
          ]

-- | Log a passthrough violation (for audit trail)
logPassthroughViolation :: PassthroughViolation -> IO ()
logPassthroughViolation pv = do
  -- In production, this would write to audit log
  -- For now, use putStrLn as placeholder
  putStrLn $ "[SECURITY] " <> T.unpack (violationToText pv)

-- | Audit an outbound request and log any violations
--
-- Returns True if the request is safe (no violations), False otherwise.
-- All violations are logged regardless of the return value.
auditOutboundRequest ::
  -- | Request headers
  [Header] ->
  -- | Request body (as text)
  Maybe Text ->
  -- | Query string (as text)
  Maybe Text ->
  -- | Correlation ID for audit
  Maybe Text ->
  -- | Target service name
  Maybe Text ->
  IO Bool
auditOutboundRequest headers mBody mQuery correlationId targetService = do
  violations <- checkRequestForTokenLeakage headers mBody mQuery correlationId targetService
  mapM_ logPassthroughViolation violations
  pure $ null violations
