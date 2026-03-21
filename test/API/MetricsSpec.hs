{-# LANGUAGE OverloadedStrings #-}

module API.MetricsSpec
  ( spec,
  )
where

import Data.Text qualified as Text
import StudioMCP.API.Metrics
  ( emptyMetricsSnapshot,
    recordRunCompletion,
    recordRunFailure,
    renderPrometheusMetrics,
  )
import StudioMCP.DAG.Summary (RunId (..), RunStatus (RunRunning, RunSucceeded))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec =
  describe "metrics snapshot helpers" $ do
    it "tracks a running submission without incrementing completion counters" $ do
      let snapshot = recordRunCompletion (RunId "run-running") RunRunning emptyMetricsSnapshot
      renderPrometheusMetrics snapshot `shouldSatisfy` Text.isInfixOf "studiomcp_last_run_info{run_id=\"run-running\"} 1"
      renderPrometheusMetrics snapshot `shouldSatisfy` Text.isInfixOf "studiomcp_runs_total 0"

    it "increments the success counters for completed runs" $ do
      let snapshot = recordRunCompletion (RunId "run-succeeded") RunSucceeded emptyMetricsSnapshot
      renderPrometheusMetrics snapshot `shouldSatisfy` Text.isInfixOf "studiomcp_runs_total 1"
      renderPrometheusMetrics snapshot `shouldSatisfy` Text.isInfixOf "studiomcp_runs_succeeded_total 1"

    it "increments the failure counters for failed runs" $ do
      let snapshot = recordRunFailure (RunId "run-failed") emptyMetricsSnapshot
      renderPrometheusMetrics snapshot `shouldSatisfy` Text.isInfixOf "studiomcp_runs_failed_total 1"
      renderPrometheusMetrics snapshot `shouldSatisfy` Text.isInfixOf "studiomcp_last_run_info{run_id=\"run-failed\"} 1"

    it "renders stable Prometheus metric names" $
      Text.lines (renderPrometheusMetrics emptyMetricsSnapshot)
        `shouldBe`
          [ "studiomcp_runs_total 0",
            "studiomcp_runs_succeeded_total 0",
            "studiomcp_runs_failed_total 0"
          ]
