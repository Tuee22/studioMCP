{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.API.Metrics
  ( MetricsSnapshot (..),
    emptyMetricsSnapshot,
    recordRunCompletion,
    recordRunFailure,
    renderPrometheusMetrics,
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import StudioMCP.DAG.Summary (RunId (..), RunStatus (..))

data MetricsSnapshot = MetricsSnapshot
  { totalRuns :: Int,
    successfulRuns :: Int,
    failedRuns :: Int,
    lastRunId :: Maybe Text
  }
  deriving (Eq, Show)

emptyMetricsSnapshot :: MetricsSnapshot
emptyMetricsSnapshot =
  MetricsSnapshot
    { totalRuns = 0,
      successfulRuns = 0,
      failedRuns = 0,
      lastRunId = Nothing
    }

recordRunCompletion :: RunId -> RunStatus -> MetricsSnapshot -> MetricsSnapshot
recordRunCompletion (RunId runIdText) runStatus metricsSnapshot =
  case runStatus of
    RunRunning ->
      metricsSnapshot
        { lastRunId = Just runIdText
        }
    RunSucceeded ->
      metricsSnapshot
        { totalRuns = totalRuns metricsSnapshot + 1,
          successfulRuns = successfulRuns metricsSnapshot + 1,
          lastRunId = Just runIdText
        }
    RunFailed ->
      metricsSnapshot
        { totalRuns = totalRuns metricsSnapshot + 1,
          failedRuns = failedRuns metricsSnapshot + 1,
          lastRunId = Just runIdText
        }

recordRunFailure :: RunId -> MetricsSnapshot -> MetricsSnapshot
recordRunFailure runIdValue metricsSnapshot =
  recordRunCompletion runIdValue RunFailed metricsSnapshot

renderPrometheusMetrics :: MetricsSnapshot -> Text
renderPrometheusMetrics metricsSnapshot =
  Text.unlines $
    [ "studiomcp_runs_total " <> renderInt (totalRuns metricsSnapshot),
      "studiomcp_runs_succeeded_total " <> renderInt (successfulRuns metricsSnapshot),
      "studiomcp_runs_failed_total " <> renderInt (failedRuns metricsSnapshot)
    ]
      <> maybe [] (\runIdText -> ["studiomcp_last_run_info{run_id=\"" <> runIdText <> "\"} 1"]) (lastRunId metricsSnapshot)

renderInt :: Int -> Text
renderInt = Text.pack . show
