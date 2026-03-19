{-# LANGUAGE OverloadedStrings #-}

module DAG.SummarySpec
  ( spec,
  )
where

import Data.Time (UTCTime (UTCTime), fromGregorian, secondsToDiffTime)
import StudioMCP.DAG.Provenance (emptyProvenance)
import StudioMCP.DAG.Summary
  ( NodeExecutionStatus (NodeSucceeded),
    NodeOutcome (..),
    RunId (..),
    RunStatus (RunSucceeded),
    Summary (summaryStatus),
    buildSummary,
  )
import StudioMCP.DAG.Types (NodeId (..))
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "buildSummary" $
    it "marks a run as successful when all node outcomes succeed" $
      summaryStatus summary `shouldBe` RunSucceeded
  where
    summary =
      buildSummary
        (RunId "run-1")
        fixedTime
        (emptyProvenance "demo")
        [ NodeOutcome
            { outcomeNodeId = NodeId "ingest",
              outcomeStatus = NodeSucceeded,
              outcomeCached = False,
              outcomeOutputReference = Just "minio://memo/ingest",
              outcomeFailure = Nothing
            }
        ]

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 3 19) (secondsToDiffTime 0)
