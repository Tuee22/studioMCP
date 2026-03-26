{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module StudioMCP.Observability.Quotas
  ( -- * Quota Configuration
    QuotaConfig (..),
    defaultQuotaConfig,

    -- * Quota Service
    QuotaService (..),
    newQuotaService,

    -- * Quota Checks
    checkQuota,
    reserveQuota,
    releaseQuota,
    QuotaCheckResult (..),

    -- * Quota Types
    QuotaType (..),
    TenantQuotaUsage (..),
    getTenantQuotaUsage,

    -- * Quota Errors
    QuotaError (..),
    quotaErrorCode,

    -- * Quota Metrics
    getQuotaMetrics,
    QuotaMetrics (..),
  )
where

import Control.Concurrent.STM (TVar, atomically, modifyTVar', newTVarIO, readTVar, readTVarIO)
import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    object,
    withObject,
    withText,
    (.:),
    (.=),
  )
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import StudioMCP.Auth.Types (TenantId (..))

-- | Types of quotas enforced
data QuotaType
  = StorageQuota
  | ConcurrentRunsQuota
  | RequestsPerMinuteQuota
  | UploadsPerHourQuota
  | ToolCallsPerMinuteQuota
  deriving (Eq, Ord, Show)

instance ToJSON QuotaType where
  toJSON StorageQuota = "storage"
  toJSON ConcurrentRunsQuota = "concurrent_runs"
  toJSON RequestsPerMinuteQuota = "requests_per_minute"
  toJSON UploadsPerHourQuota = "uploads_per_hour"
  toJSON ToolCallsPerMinuteQuota = "tool_calls_per_minute"

instance FromJSON QuotaType where
  parseJSON = withText "QuotaType" $ \t ->
    case t of
      "storage" -> pure StorageQuota
      "concurrent_runs" -> pure ConcurrentRunsQuota
      "requests_per_minute" -> pure RequestsPerMinuteQuota
      "uploads_per_hour" -> pure UploadsPerHourQuota
      "tool_calls_per_minute" -> pure ToolCallsPerMinuteQuota
      other -> fail $ "Unknown quota type: " <> T.unpack other

-- | Quota configuration
data QuotaConfig = QuotaConfig
  { qcStorageLimit :: Integer,
    qcConcurrentRunsLimit :: Int,
    qcRequestsPerMinuteLimit :: Int,
    qcUploadsPerHourLimit :: Int,
    qcToolCallsPerMinuteLimit :: Int,
    qcEnforcement :: Bool
  }
  deriving (Eq, Show)

-- | Default quota configuration
defaultQuotaConfig :: QuotaConfig
defaultQuotaConfig =
  QuotaConfig
    { qcStorageLimit = 10 * 1024 * 1024 * 1024, -- 10 GB
      qcConcurrentRunsLimit = 10,
      qcRequestsPerMinuteLimit = 100,
      qcUploadsPerHourLimit = 50,
      qcToolCallsPerMinuteLimit = 200,
      qcEnforcement = True
    }

-- | Tenant quota usage tracking
data TenantQuotaUsage = TenantQuotaUsage
  { tquStorageUsed :: Integer,
    tquConcurrentRuns :: Int,
    tquRequestsThisMinute :: Int,
    tquUploadsThisHour :: Int,
    tquToolCallsThisMinute :: Int
  }
  deriving (Eq, Show)

instance ToJSON TenantQuotaUsage where
  toJSON TenantQuotaUsage {..} =
    object
      [ "storageUsed" .= tquStorageUsed,
        "concurrentRuns" .= tquConcurrentRuns,
        "requestsThisMinute" .= tquRequestsThisMinute,
        "uploadsThisHour" .= tquUploadsThisHour,
        "toolCallsThisMinute" .= tquToolCallsThisMinute
      ]

-- | Empty usage for new tenants
emptyUsage :: TenantQuotaUsage
emptyUsage =
  TenantQuotaUsage
    { tquStorageUsed = 0,
      tquConcurrentRuns = 0,
      tquRequestsThisMinute = 0,
      tquUploadsThisHour = 0,
      tquToolCallsThisMinute = 0
    }

-- | Result of a quota check
data QuotaCheckResult
  = QuotaAllowed
  | QuotaExceeded QuotaType Int Int -- ^ Type, current, limit
  | QuotaWarning QuotaType Int Int Int -- ^ Type, current, limit, threshold%
  deriving (Eq, Show)

instance ToJSON QuotaCheckResult where
  toJSON QuotaAllowed = object ["status" .= ("allowed" :: Text)]
  toJSON (QuotaExceeded qtype current limit) =
    object
      [ "status" .= ("exceeded" :: Text),
        "quotaType" .= qtype,
        "current" .= current,
        "limit" .= limit
      ]
  toJSON (QuotaWarning qtype current limit threshold) =
    object
      [ "status" .= ("warning" :: Text),
        "quotaType" .= qtype,
        "current" .= current,
        "limit" .= limit,
        "thresholdPercent" .= threshold
      ]

-- | Quota errors
data QuotaError
  = QuotaLimitExceeded TenantId QuotaType
  | QuotaReservationFailed TenantId QuotaType
  | QuotaServiceUnavailable
  deriving (Eq, Show)

-- | Get error code for quota errors
quotaErrorCode :: QuotaError -> Text
quotaErrorCode (QuotaLimitExceeded _ _) = "quota-exceeded"
quotaErrorCode (QuotaReservationFailed _ _) = "reservation-failed"
quotaErrorCode QuotaServiceUnavailable = "service-unavailable"

-- | Quota metrics
data QuotaMetrics = QuotaMetrics
  { qmTotalChecks :: Int,
    qmAllowedChecks :: Int,
    qmDeniedChecks :: Int,
    qmWarningChecks :: Int
  }
  deriving (Eq, Show)

instance ToJSON QuotaMetrics where
  toJSON QuotaMetrics {..} =
    object
      [ "totalChecks" .= qmTotalChecks,
        "allowedChecks" .= qmAllowedChecks,
        "deniedChecks" .= qmDeniedChecks,
        "warningChecks" .= qmWarningChecks
      ]

-- | Internal state for quota service
data QuotaServiceState = QuotaServiceState
  { qssUsage :: Map.Map TenantId TenantQuotaUsage,
    qssMetrics :: QuotaMetrics
  }

-- | Quota service
data QuotaService = QuotaService
  { qsConfig :: QuotaConfig,
    qsState :: TVar QuotaServiceState
  }

-- | Create a new quota service
newQuotaService :: QuotaConfig -> IO QuotaService
newQuotaService config = do
  stateVar <-
    newTVarIO
      QuotaServiceState
        { qssUsage = Map.empty,
          qssMetrics =
            QuotaMetrics
              { qmTotalChecks = 0,
                qmAllowedChecks = 0,
                qmDeniedChecks = 0,
                qmWarningChecks = 0
              }
        }
  pure
    QuotaService
      { qsConfig = config,
        qsState = stateVar
      }

-- | Check if a quota would be exceeded
checkQuota ::
  QuotaService ->
  TenantId ->
  QuotaType ->
  IO QuotaCheckResult
checkQuota service tenantId quotaType = do
  atomically $ do
    state <- readTVar (qsState service)
    let usage = Map.findWithDefault emptyUsage tenantId (qssUsage state)
        config = qsConfig service
        (current, limit) = getUsageAndLimit config usage quotaType
        result
          | current >= limit = QuotaExceeded quotaType current limit
          | current >= (limit * 80 `div` 100) = QuotaWarning quotaType current limit 80
          | otherwise = QuotaAllowed
    modifyTVar' (qsState service) $ \s ->
      s
        { qssMetrics =
            updateMetrics (qssMetrics s) result
        }
    pure result

-- | Reserve quota (increment usage)
reserveQuota ::
  QuotaService ->
  TenantId ->
  QuotaType ->
  Int ->
  IO (Either QuotaError ())
reserveQuota service tenantId quotaType amount = do
  result <- checkQuota service tenantId quotaType
  case result of
    QuotaExceeded _ _ _ -> pure $ Left $ QuotaLimitExceeded tenantId quotaType
    _ -> do
      atomically $ modifyTVar' (qsState service) $ \s ->
        s
          { qssUsage =
              Map.alter (Just . incrementUsage quotaType amount) tenantId (qssUsage s)
          }
      pure $ Right ()

-- | Release quota (decrement usage)
releaseQuota ::
  QuotaService ->
  TenantId ->
  QuotaType ->
  Int ->
  IO ()
releaseQuota service tenantId quotaType amount =
  atomically $ modifyTVar' (qsState service) $ \s ->
    s
      { qssUsage =
          Map.alter (Just . decrementUsage quotaType amount) tenantId (qssUsage s)
      }

-- | Get quota metrics
getQuotaMetrics :: QuotaService -> IO QuotaMetrics
getQuotaMetrics service = do
  state <- readTVarIO (qsState service)
  pure $ qssMetrics state

getTenantQuotaUsage :: QuotaService -> TenantId -> IO TenantQuotaUsage
getTenantQuotaUsage service tenantId = do
  state <- readTVarIO (qsState service)
  pure $ Map.findWithDefault emptyUsage tenantId (qssUsage state)

-- | Get current usage and limit for a quota type
getUsageAndLimit :: QuotaConfig -> TenantQuotaUsage -> QuotaType -> (Int, Int)
getUsageAndLimit config usage quotaType =
  case quotaType of
    StorageQuota -> (fromIntegral (tquStorageUsed usage), fromIntegral (qcStorageLimit config))
    ConcurrentRunsQuota -> (tquConcurrentRuns usage, qcConcurrentRunsLimit config)
    RequestsPerMinuteQuota -> (tquRequestsThisMinute usage, qcRequestsPerMinuteLimit config)
    UploadsPerHourQuota -> (tquUploadsThisHour usage, qcUploadsPerHourLimit config)
    ToolCallsPerMinuteQuota -> (tquToolCallsThisMinute usage, qcToolCallsPerMinuteLimit config)

-- | Increment usage for a quota type
incrementUsage :: QuotaType -> Int -> Maybe TenantQuotaUsage -> TenantQuotaUsage
incrementUsage quotaType amount maybeUsage =
  let usage = maybe emptyUsage id maybeUsage
   in case quotaType of
        StorageQuota -> usage {tquStorageUsed = tquStorageUsed usage + fromIntegral amount}
        ConcurrentRunsQuota -> usage {tquConcurrentRuns = tquConcurrentRuns usage + amount}
        RequestsPerMinuteQuota -> usage {tquRequestsThisMinute = tquRequestsThisMinute usage + amount}
        UploadsPerHourQuota -> usage {tquUploadsThisHour = tquUploadsThisHour usage + amount}
        ToolCallsPerMinuteQuota -> usage {tquToolCallsThisMinute = tquToolCallsThisMinute usage + amount}

-- | Decrement usage for a quota type
decrementUsage :: QuotaType -> Int -> Maybe TenantQuotaUsage -> TenantQuotaUsage
decrementUsage quotaType amount maybeUsage =
  let usage = maybe emptyUsage id maybeUsage
   in case quotaType of
        StorageQuota -> usage {tquStorageUsed = max 0 (tquStorageUsed usage - fromIntegral amount)}
        ConcurrentRunsQuota -> usage {tquConcurrentRuns = max 0 (tquConcurrentRuns usage - amount)}
        RequestsPerMinuteQuota -> usage {tquRequestsThisMinute = max 0 (tquRequestsThisMinute usage - amount)}
        UploadsPerHourQuota -> usage {tquUploadsThisHour = max 0 (tquUploadsThisHour usage - amount)}
        ToolCallsPerMinuteQuota -> usage {tquToolCallsThisMinute = max 0 (tquToolCallsThisMinute usage - amount)}

-- | Update metrics based on check result
updateMetrics :: QuotaMetrics -> QuotaCheckResult -> QuotaMetrics
updateMetrics metrics result =
  metrics
    { qmTotalChecks = qmTotalChecks metrics + 1,
      qmAllowedChecks =
        qmAllowedChecks metrics + case result of QuotaAllowed -> 1; _ -> 0,
      qmDeniedChecks =
        qmDeniedChecks metrics + case result of QuotaExceeded {} -> 1; _ -> 0,
      qmWarningChecks =
        qmWarningChecks metrics + case result of QuotaWarning {} -> 1; _ -> 0
    }
