{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module StudioMCP.Observability.McpMetrics
  ( -- * MCP Metrics Service
    McpMetricsService (..),
    newMcpMetricsService,

    -- * Recording Metrics
    recordToolCall,
    recordResourceRead,
    recordPromptGet,
    recordMethodCall,
    recordError,

    -- * Metric Types
    McpMethodMetrics (..),
    ToolMetrics (..),
    ResourceMetrics (..),
    PromptMetrics (..),

    -- * Metric Retrieval
    getMcpMetrics,
    McpMetricsSnapshot (..),
    renderPrometheusMetrics,

    -- * Health Metrics
    HealthMetrics (..),
    getHealthMetrics,
  )
where

import Control.Concurrent.STM (TVar, atomically, modifyTVar', newTVarIO, readTVarIO)
import Data.Aeson
  ( ToJSON (toJSON),
    object,
    (.=),
  )
import qualified Data.Aeson.Key as Key
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime, diffUTCTime, getCurrentTime)
import StudioMCP.Auth.Types (TenantId (..))

-- | Metrics for an MCP method
data McpMethodMetrics = McpMethodMetrics
  { mmmCallCount :: Int,
    mmmErrorCount :: Int,
    mmmTotalLatencyMs :: Double,
    mmmLastCall :: Maybe UTCTime
  }
  deriving (Eq, Show)

instance ToJSON McpMethodMetrics where
  toJSON McpMethodMetrics {..} =
    object
      [ "callCount" .= mmmCallCount,
        "errorCount" .= mmmErrorCount,
        "avgLatencyMs" .= (if mmmCallCount > 0 then mmmTotalLatencyMs / fromIntegral mmmCallCount else 0),
        "lastCall" .= mmmLastCall
      ]

emptyMethodMetrics :: McpMethodMetrics
emptyMethodMetrics =
  McpMethodMetrics
    { mmmCallCount = 0,
      mmmErrorCount = 0,
      mmmTotalLatencyMs = 0,
      mmmLastCall = Nothing
    }

-- | Metrics for a tool
data ToolMetrics = ToolMetrics
  { tmCallCount :: Int,
    tmSuccessCount :: Int,
    tmErrorCount :: Int,
    tmTotalLatencyMs :: Double
  }
  deriving (Eq, Show)

instance ToJSON ToolMetrics where
  toJSON ToolMetrics {..} =
    object
      [ "callCount" .= tmCallCount,
        "successCount" .= tmSuccessCount,
        "errorCount" .= tmErrorCount,
        "avgLatencyMs" .= (if tmCallCount > 0 then tmTotalLatencyMs / fromIntegral tmCallCount else 0)
      ]

emptyToolMetrics :: ToolMetrics
emptyToolMetrics =
  ToolMetrics
    { tmCallCount = 0,
      tmSuccessCount = 0,
      tmErrorCount = 0,
      tmTotalLatencyMs = 0
    }

-- | Metrics for a resource
data ResourceMetrics = ResourceMetrics
  { rmReadCount :: Int,
    rmErrorCount :: Int,
    rmCacheHits :: Int
  }
  deriving (Eq, Show)

instance ToJSON ResourceMetrics where
  toJSON ResourceMetrics {..} =
    object
      [ "readCount" .= rmReadCount,
        "errorCount" .= rmErrorCount,
        "cacheHits" .= rmCacheHits,
        "cacheHitRate" .= (if rmReadCount > 0 then fromIntegral rmCacheHits / fromIntegral rmReadCount :: Double else 0)
      ]

emptyResourceMetrics :: ResourceMetrics
emptyResourceMetrics =
  ResourceMetrics
    { rmReadCount = 0,
      rmErrorCount = 0,
      rmCacheHits = 0
    }

-- | Metrics for a prompt
data PromptMetrics = PromptMetrics
  { pmGetCount :: Int,
    pmErrorCount :: Int
  }
  deriving (Eq, Show)

instance ToJSON PromptMetrics where
  toJSON PromptMetrics {..} =
    object
      [ "getCount" .= pmGetCount,
        "errorCount" .= pmErrorCount
      ]

emptyPromptMetrics :: PromptMetrics
emptyPromptMetrics = PromptMetrics {pmGetCount = 0, pmErrorCount = 0}

-- | Health metrics
data HealthMetrics = HealthMetrics
  { hmUptime :: Double,
    hmTotalRequests :: Int,
    hmTotalErrors :: Int,
    hmErrorRate :: Double,
    hmActiveConnections :: Int,
    hmPendingRequests :: Int
  }
  deriving (Eq, Show)

instance ToJSON HealthMetrics where
  toJSON HealthMetrics {..} =
    object
      [ "uptimeSeconds" .= hmUptime,
        "totalRequests" .= hmTotalRequests,
        "totalErrors" .= hmTotalErrors,
        "errorRate" .= hmErrorRate,
        "activeConnections" .= hmActiveConnections,
        "pendingRequests" .= hmPendingRequests
      ]

-- | Snapshot of all MCP metrics
data McpMetricsSnapshot = McpMetricsSnapshot
  { mmsMethodMetrics :: Map.Map Text McpMethodMetrics,
    mmsToolMetrics :: Map.Map Text ToolMetrics,
    mmsResourceMetrics :: Map.Map Text ResourceMetrics,
    mmsPromptMetrics :: Map.Map Text PromptMetrics,
    mmsTenantRequestCounts :: Map.Map TenantId Int,
    mmsStartTime :: UTCTime,
    mmsSnapshotTime :: UTCTime
  }
  deriving (Eq, Show)

instance ToJSON McpMetricsSnapshot where
  toJSON McpMetricsSnapshot {..} =
    object
      [ "methods" .= mmsMethodMetrics,
        "tools" .= mmsToolMetrics,
        "resources" .= mmsResourceMetrics,
        "prompts" .= mmsPromptMetrics,
        "tenantRequests" .= tenantRequestsToJson mmsTenantRequestCounts,
        "startTime" .= mmsStartTime,
        "snapshotTime" .= mmsSnapshotTime
      ]
    where
      tenantRequestsToJson m =
        object $ map (\(TenantId tid, cnt) -> Key.fromText tid .= cnt) (Map.toList m)

-- | Internal state for MCP metrics service
data McpMetricsState = McpMetricsState
  { mcpMethodMetrics :: Map.Map Text McpMethodMetrics,
    mcpToolMetrics :: Map.Map Text ToolMetrics,
    mcpResourceMetrics :: Map.Map Text ResourceMetrics,
    mcpPromptMetrics :: Map.Map Text PromptMetrics,
    mcpTenantRequests :: Map.Map TenantId Int,
    mcpStartTime :: UTCTime,
    mcpActiveConnections :: Int,
    mcpPendingRequests :: Int
  }

-- | MCP metrics service
data McpMetricsService = McpMetricsService
  { mmsState :: TVar McpMetricsState
  }

-- | Create a new MCP metrics service
newMcpMetricsService :: IO McpMetricsService
newMcpMetricsService = do
  now <- getCurrentTime
  stateVar <-
    newTVarIO
      McpMetricsState
        { mcpMethodMetrics = Map.empty,
          mcpToolMetrics = Map.empty,
          mcpResourceMetrics = Map.empty,
          mcpPromptMetrics = Map.empty,
          mcpTenantRequests = Map.empty,
          mcpStartTime = now,
          mcpActiveConnections = 0,
          mcpPendingRequests = 0
        }
  pure McpMetricsService {mmsState = stateVar}

-- | Record a tool call
recordToolCall ::
  McpMetricsService ->
  Text ->
  TenantId ->
  Double ->
  Bool ->
  IO ()
recordToolCall service toolName tenantId latencyMs success = do
  atomically $ modifyTVar' (mmsState service) $ \s ->
    s
      { mcpToolMetrics =
          Map.alter (updateTool latencyMs success) toolName (mcpToolMetrics s),
        mcpTenantRequests =
          Map.insertWith (+) tenantId 1 (mcpTenantRequests s)
      }
  where
    updateTool lat succ Nothing =
      Just
        emptyToolMetrics
          { tmCallCount = 1,
            tmSuccessCount = if succ then 1 else 0,
            tmErrorCount = if succ then 0 else 1,
            tmTotalLatencyMs = lat
          }
    updateTool lat succ (Just m) =
      Just
        m
          { tmCallCount = tmCallCount m + 1,
            tmSuccessCount = tmSuccessCount m + (if succ then 1 else 0),
            tmErrorCount = tmErrorCount m + (if succ then 0 else 1),
            tmTotalLatencyMs = tmTotalLatencyMs m + lat
          }

-- | Record a resource read
recordResourceRead ::
  McpMetricsService ->
  Text ->
  TenantId ->
  Bool ->
  Bool ->
  IO ()
recordResourceRead service resourceUri tenantId success cacheHit = do
  atomically $ modifyTVar' (mmsState service) $ \s ->
    s
      { mcpResourceMetrics =
          Map.alter (updateResource success cacheHit) resourceUri (mcpResourceMetrics s),
        mcpTenantRequests =
          Map.insertWith (+) tenantId 1 (mcpTenantRequests s)
      }
  where
    updateResource succ hit Nothing =
      Just
        emptyResourceMetrics
          { rmReadCount = 1,
            rmErrorCount = if succ then 0 else 1,
            rmCacheHits = if hit then 1 else 0
          }
    updateResource succ hit (Just m) =
      Just
        m
          { rmReadCount = rmReadCount m + 1,
            rmErrorCount = rmErrorCount m + (if succ then 0 else 1),
            rmCacheHits = rmCacheHits m + (if hit then 1 else 0)
          }

-- | Record a prompt get
recordPromptGet ::
  McpMetricsService ->
  Text ->
  TenantId ->
  Bool ->
  IO ()
recordPromptGet service promptName tenantId success = do
  atomically $ modifyTVar' (mmsState service) $ \s ->
    s
      { mcpPromptMetrics =
          Map.alter (updatePrompt success) promptName (mcpPromptMetrics s),
        mcpTenantRequests =
          Map.insertWith (+) tenantId 1 (mcpTenantRequests s)
      }
  where
    updatePrompt succ Nothing =
      Just
        emptyPromptMetrics
          { pmGetCount = 1,
            pmErrorCount = if succ then 0 else 1
          }
    updatePrompt succ (Just m) =
      Just
        m
          { pmGetCount = pmGetCount m + 1,
            pmErrorCount = pmErrorCount m + (if succ then 0 else 1)
          }

-- | Record an MCP method call
recordMethodCall ::
  McpMetricsService ->
  Text ->
  Double ->
  Bool ->
  IO ()
recordMethodCall service method latencyMs success = do
  now <- getCurrentTime
  atomically $ modifyTVar' (mmsState service) $ \s ->
    s
      { mcpMethodMetrics =
          Map.alter (updateMethod latencyMs success now) method (mcpMethodMetrics s)
      }
  where
    updateMethod lat succ t Nothing =
      Just
        emptyMethodMetrics
          { mmmCallCount = 1,
            mmmErrorCount = if succ then 0 else 1,
            mmmTotalLatencyMs = lat,
            mmmLastCall = Just t
          }
    updateMethod lat succ t (Just m) =
      Just
        m
          { mmmCallCount = mmmCallCount m + 1,
            mmmErrorCount = mmmErrorCount m + (if succ then 0 else 1),
            mmmTotalLatencyMs = mmmTotalLatencyMs m + lat,
            mmmLastCall = Just t
          }

-- | Record an error
recordError ::
  McpMetricsService ->
  Text ->
  Maybe TenantId ->
  IO ()
recordError service errorType maybeTenant = do
  atomically $ modifyTVar' (mmsState service) $ \s ->
    s
      { mcpMethodMetrics =
          Map.alter incrementError "errors" (mcpMethodMetrics s),
        mcpTenantRequests =
          maybe id (\t -> Map.insertWith (+) t 1) maybeTenant (mcpTenantRequests s)
      }
  where
    incrementError Nothing = Just emptyMethodMetrics {mmmErrorCount = 1}
    incrementError (Just m) = Just m {mmmErrorCount = mmmErrorCount m + 1}

-- | Get MCP metrics snapshot
getMcpMetrics :: McpMetricsService -> IO McpMetricsSnapshot
getMcpMetrics service = do
  now <- getCurrentTime
  state <- readTVarIO (mmsState service)
  pure
    McpMetricsSnapshot
      { mmsMethodMetrics = mcpMethodMetrics state,
        mmsToolMetrics = mcpToolMetrics state,
        mmsResourceMetrics = mcpResourceMetrics state,
        mmsPromptMetrics = mcpPromptMetrics state,
        mmsTenantRequestCounts = mcpTenantRequests state,
        mmsStartTime = mcpStartTime state,
        mmsSnapshotTime = now
      }

-- | Get health metrics
getHealthMetrics :: McpMetricsService -> IO HealthMetrics
getHealthMetrics service = do
  now <- getCurrentTime
  state <- readTVarIO (mmsState service)
  let totalRequests = sum $ map mmmCallCount $ Map.elems (mcpMethodMetrics state)
      totalErrors = sum $ map mmmErrorCount $ Map.elems (mcpMethodMetrics state)
      uptime = diffUTCTime now (mcpStartTime state)
  pure
    HealthMetrics
      { hmUptime = realToFrac uptime,
        hmTotalRequests = totalRequests,
        hmTotalErrors = totalErrors,
        hmErrorRate = if totalRequests > 0 then fromIntegral totalErrors / fromIntegral totalRequests else 0,
        hmActiveConnections = mcpActiveConnections state,
        hmPendingRequests = mcpPendingRequests state
      }

-- | Render metrics in Prometheus format
renderPrometheusMetrics :: McpMetricsSnapshot -> Text
renderPrometheusMetrics snapshot =
  T.unlines $
    ["# HELP studiomcp_method_calls_total Total MCP method calls", "# TYPE studiomcp_method_calls_total counter"]
      ++ methodLines
      ++ ["# HELP studiomcp_tool_calls_total Total tool calls", "# TYPE studiomcp_tool_calls_total counter"]
      ++ toolLines
      ++ ["# HELP studiomcp_resource_reads_total Total resource reads", "# TYPE studiomcp_resource_reads_total counter"]
      ++ resourceLines
      ++ ["# HELP studiomcp_prompt_gets_total Total prompt gets", "# TYPE studiomcp_prompt_gets_total counter"]
      ++ promptLines
  where
    methodLines =
      map
        ( \(method, m) ->
            "studiomcp_method_calls_total{method=\"" <> method <> "\"} " <> T.pack (show (mmmCallCount m))
        )
        (Map.toList (mmsMethodMetrics snapshot))
    toolLines =
      map
        ( \(tool, m) ->
            "studiomcp_tool_calls_total{tool=\"" <> tool <> "\"} " <> T.pack (show (tmCallCount m))
        )
        (Map.toList (mmsToolMetrics snapshot))
    resourceLines =
      map
        ( \(uri, m) ->
            "studiomcp_resource_reads_total{uri=\"" <> uri <> "\"} " <> T.pack (show (rmReadCount m))
        )
        (Map.toList (mmsResourceMetrics snapshot))
    promptLines =
      map
        ( \(prompt, m) ->
            "studiomcp_prompt_gets_total{prompt=\"" <> prompt <> "\"} " <> T.pack (show (pmGetCount m))
        )
        (Map.toList (mmsPromptMetrics snapshot))
