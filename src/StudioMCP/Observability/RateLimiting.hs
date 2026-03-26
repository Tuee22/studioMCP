{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module StudioMCP.Observability.RateLimiting
  ( -- * Rate Limiter Configuration
    RateLimiterConfig (..),
    defaultRateLimiterConfig,

    -- * Rate Limiter Service
    RateLimiterService (..),
    newRateLimiterService,

    -- * Rate Limit Checks
    checkRateLimit,
    recordRequest,
    RateLimitResult (..),

    -- * Rate Limit Types
    RateLimitKey (..),
    RateLimitWindow (..),

    -- * Rate Limit Metrics
    getRateLimitMetrics,
    RateLimitMetrics (..),
  )
where

import Control.Concurrent.STM (TVar, atomically, modifyTVar', newTVarIO, readTVar, readTVarIO)
import Data.Aeson
  ( ToJSON (toJSON),
    object,
    (.=),
  )
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Data.Time (UTCTime, addUTCTime, diffUTCTime, getCurrentTime)
import StudioMCP.Auth.Types (SubjectId (..), TenantId (..))

-- | Time window for rate limiting
data RateLimitWindow
  = PerSecond
  | PerMinute
  | PerHour
  deriving (Eq, Ord, Show)

instance ToJSON RateLimitWindow where
  toJSON PerSecond = "per_second"
  toJSON PerMinute = "per_minute"
  toJSON PerHour = "per_hour"

-- | Key for rate limiting (tenant, subject, or IP)
data RateLimitKey
  = TenantKey TenantId
  | SubjectKey SubjectId
  | IpKey Text
  | TenantMethodKey TenantId Text
  deriving (Eq, Ord, Show)

-- | Rate limiter configuration
data RateLimiterConfig = RateLimiterConfig
  { rlcRequestsPerSecond :: Int,
    rlcRequestsPerMinute :: Int,
    rlcRequestsPerHour :: Int,
    rlcBurstMultiplier :: Double,
    rlcEnabled :: Bool
  }
  deriving (Eq, Show)

-- | Default rate limiter configuration
defaultRateLimiterConfig :: RateLimiterConfig
defaultRateLimiterConfig =
  RateLimiterConfig
    { rlcRequestsPerSecond = 10,
      rlcRequestsPerMinute = 100,
      rlcRequestsPerHour = 1000,
      rlcBurstMultiplier = 2.0,
      rlcEnabled = True
    }

-- | Result of a rate limit check
data RateLimitResult
  = RateLimitAllowed Int Int -- ^ remaining, limit
  | RateLimitDenied Int UTCTime -- ^ retry after seconds, reset time
  deriving (Eq, Show)

instance ToJSON RateLimitResult where
  toJSON (RateLimitAllowed remaining limit) =
    object
      [ "status" .= ("allowed" :: Text),
        "remaining" .= remaining,
        "limit" .= limit
      ]
  toJSON (RateLimitDenied retryAfter resetTime) =
    object
      [ "status" .= ("denied" :: Text),
        "retryAfterSeconds" .= retryAfter,
        "resetTime" .= resetTime
      ]

-- | Bucket for counting requests in a window
data RateLimitBucket = RateLimitBucket
  { rlbCount :: Int,
    rlbWindowStart :: UTCTime
  }
  deriving (Eq, Show)

-- | Rate limit metrics
data RateLimitMetrics = RateLimitMetrics
  { rlmTotalChecks :: Int,
    rlmAllowedRequests :: Int,
    rlmDeniedRequests :: Int,
    rlmCurrentBuckets :: Int
  }
  deriving (Eq, Show)

instance ToJSON RateLimitMetrics where
  toJSON RateLimitMetrics {..} =
    object
      [ "totalChecks" .= rlmTotalChecks,
        "allowedRequests" .= rlmAllowedRequests,
        "deniedRequests" .= rlmDeniedRequests,
        "currentBuckets" .= rlmCurrentBuckets
      ]

-- | Internal state for rate limiter service
data RateLimiterState = RateLimiterState
  { rlsBuckets :: Map.Map (RateLimitKey, RateLimitWindow) RateLimitBucket,
    rlsMetrics :: RateLimitMetrics
  }

-- | Rate limiter service
data RateLimiterService = RateLimiterService
  { rlsConfig :: RateLimiterConfig,
    rlsState :: TVar RateLimiterState
  }

-- | Create a new rate limiter service
newRateLimiterService :: RateLimiterConfig -> IO RateLimiterService
newRateLimiterService config = do
  stateVar <-
    newTVarIO
      RateLimiterState
        { rlsBuckets = Map.empty,
          rlsMetrics =
            RateLimitMetrics
              { rlmTotalChecks = 0,
                rlmAllowedRequests = 0,
                rlmDeniedRequests = 0,
                rlmCurrentBuckets = 0
              }
        }
  pure
    RateLimiterService
      { rlsConfig = config,
        rlsState = stateVar
      }

-- | Check rate limit for a key
checkRateLimit ::
  RateLimiterService ->
  RateLimitKey ->
  RateLimitWindow ->
  IO RateLimitResult
checkRateLimit service key window = do
  now <- getCurrentTime
  let config = rlsConfig service
  if not (rlcEnabled config)
    then pure $ RateLimitAllowed 999999 999999
    else atomically $ do
      state <- readTVar (rlsState service)
      let bucketKey = (key, window)
          limit = getLimit config window
          windowSeconds = getWindowSeconds window
          windowStart = addUTCTime (negate (fromIntegral windowSeconds)) now
          maybeBucket = Map.lookup bucketKey (rlsBuckets state)
          bucket = case maybeBucket of
            Nothing -> RateLimitBucket {rlbCount = 0, rlbWindowStart = now}
            Just b
              | rlbWindowStart b < windowStart ->
                  RateLimitBucket {rlbCount = 0, rlbWindowStart = now}
              | otherwise -> b
          remaining = max 0 (limit - rlbCount bucket)
          result
            | remaining > 0 = RateLimitAllowed remaining limit
            | otherwise =
                let resetTime = addUTCTime (fromIntegral windowSeconds) (rlbWindowStart bucket)
                    retryAfter = ceiling (diffUTCTime resetTime now)
                 in RateLimitDenied retryAfter resetTime
      modifyTVar' (rlsState service) $ \s ->
        s
          { rlsMetrics =
              updateMetrics (rlsMetrics s) result (Map.size (rlsBuckets s))
          }
      pure result

-- | Record a request (increment the counter)
recordRequest ::
  RateLimiterService ->
  RateLimitKey ->
  RateLimitWindow ->
  IO ()
recordRequest service key window = do
  now <- getCurrentTime
  let config = rlsConfig service
  when (rlcEnabled config) $ do
    atomically $ modifyTVar' (rlsState service) $ \s ->
      let bucketKey = (key, window)
          windowSeconds = getWindowSeconds window
          windowStart = addUTCTime (negate (fromIntegral windowSeconds)) now
          updateBucket maybeBucket =
            case maybeBucket of
              Nothing ->
                Just RateLimitBucket {rlbCount = 1, rlbWindowStart = now}
              Just b
                | rlbWindowStart b < windowStart ->
                    Just RateLimitBucket {rlbCount = 1, rlbWindowStart = now}
                | otherwise ->
                    Just b {rlbCount = rlbCount b + 1}
       in s {rlsBuckets = Map.alter updateBucket bucketKey (rlsBuckets s)}
  where
    when cond action = if cond then action else pure ()

-- | Get rate limit metrics
getRateLimitMetrics :: RateLimiterService -> IO RateLimitMetrics
getRateLimitMetrics service = do
  state <- readTVarIO (rlsState service)
  pure $ rlsMetrics state

-- | Get limit for a window
getLimit :: RateLimiterConfig -> RateLimitWindow -> Int
getLimit config PerSecond = rlcRequestsPerSecond config
getLimit config PerMinute = rlcRequestsPerMinute config
getLimit config PerHour = rlcRequestsPerHour config

-- | Get window duration in seconds
getWindowSeconds :: RateLimitWindow -> Int
getWindowSeconds PerSecond = 1
getWindowSeconds PerMinute = 60
getWindowSeconds PerHour = 3600

-- | Update metrics based on result
updateMetrics :: RateLimitMetrics -> RateLimitResult -> Int -> RateLimitMetrics
updateMetrics metrics result bucketCount =
  metrics
    { rlmTotalChecks = rlmTotalChecks metrics + 1,
      rlmAllowedRequests =
        rlmAllowedRequests metrics + case result of RateLimitAllowed {} -> 1; _ -> 0,
      rlmDeniedRequests =
        rlmDeniedRequests metrics + case result of RateLimitDenied {} -> 1; _ -> 0,
      rlmCurrentBuckets = bucketCount
    }
