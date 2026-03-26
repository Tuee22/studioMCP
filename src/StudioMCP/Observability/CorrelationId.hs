{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module StudioMCP.Observability.CorrelationId
  ( -- * Correlation ID
    CorrelationId (..),
    generateCorrelationId,
    parseCorrelationId,
    correlationIdHeader,

    -- * Request Context
    RequestContext (..),
    newRequestContext,

    -- * Correlation ID Propagation
    withCorrelationId,
    extractCorrelationId,
  )
where

import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime, getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime)

-- | Unique correlation ID for request tracing
newtype CorrelationId = CorrelationId { unCorrelationId :: Text }
  deriving (Eq, Show, ToJSON, FromJSON)

-- | HTTP header name for correlation ID
correlationIdHeader :: Text
correlationIdHeader = "X-Correlation-ID"

-- | Generate a new correlation ID
generateCorrelationId :: IO CorrelationId
generateCorrelationId = do
  now <- getCurrentTime
  let timestamp = formatTime defaultTimeLocale "%Y%m%d%H%M%S%q" now
      -- Simple hash for uniqueness (in production, use UUID)
      hash = hashString timestamp
  pure $ CorrelationId $ "req-" <> T.pack timestamp <> "-" <> T.pack (show hash)
  where
    hashString :: String -> Int
    hashString = foldl (\acc c -> acc * 31 + fromEnum c) 0

-- | Parse a correlation ID from text
parseCorrelationId :: Text -> Maybe CorrelationId
parseCorrelationId t
  | T.null t = Nothing
  | otherwise = Just $ CorrelationId t

-- | Request context with correlation and metadata
data RequestContext = RequestContext
  { rcCorrelationId :: CorrelationId,
    rcTenantId :: Maybe Text,
    rcSubjectId :: Maybe Text,
    rcMethod :: Text,
    rcPath :: Text,
    rcStartTime :: UTCTime,
    rcSourceIp :: Maybe Text,
    rcUserAgent :: Maybe Text
  }
  deriving (Eq, Show)

-- | Create a new request context
newRequestContext ::
  Text ->
  Text ->
  Maybe Text ->
  Maybe Text ->
  IO RequestContext
newRequestContext method path sourceIp userAgent = do
  correlationId <- generateCorrelationId
  now <- getCurrentTime
  pure
    RequestContext
      { rcCorrelationId = correlationId,
        rcTenantId = Nothing,
        rcSubjectId = Nothing,
        rcMethod = method,
        rcPath = path,
        rcStartTime = now,
        rcSourceIp = sourceIp,
        rcUserAgent = userAgent
      }

-- | Execute an action with a correlation ID
withCorrelationId :: CorrelationId -> (CorrelationId -> IO a) -> IO a
withCorrelationId correlationId action = action correlationId

-- | Extract correlation ID from headers (returns existing or generates new)
extractCorrelationId :: Maybe Text -> IO CorrelationId
extractCorrelationId maybeHeader =
  case maybeHeader >>= parseCorrelationId of
    Just cid -> pure cid
    Nothing -> generateCorrelationId
