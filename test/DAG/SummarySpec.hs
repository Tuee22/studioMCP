{-# LANGUAGE OverloadedStrings #-}

module DAG.SummarySpec
  ( spec,
  )
where

import Data.Aeson (eitherDecode, encode)
import Data.Time (UTCTime (UTCTime), fromGregorian, secondsToDiffTime)
import StudioMCP.DAG.Provenance (emptyProvenance)
import StudioMCP.DAG.Summary
  ( NodeExecutionStatus (NodeFailed, NodeSucceeded),
    NodeOutcome (..),
    RunId (..),
    RunStatus (RunFailed, RunSucceeded),
    Summary (summaryFailures, summaryOutputReferences, summaryStatus),
    buildSummary,
  )
import StudioMCP.DAG.Types (NodeId (..))
import StudioMCP.Result.Failure (failureCode, validationFailure)
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "buildSummary" $ do
    it "marks a run as successful when all node outcomes succeed" $ do
      summaryStatus summary `shouldBe` RunSucceeded
      summaryOutputReferences summary `shouldBe` ["minio://memo/ingest"]
      summaryFailures summary `shouldBe` []

    it "marks a run as failed when any node outcome fails" $ do
      summaryStatus failedSummary `shouldBe` RunFailed
      map failureCode (summaryFailures failedSummary) `shouldBe` ["missing-input"]
      summaryOutputReferences failedSummary `shouldBe` []

    it "round-trips summary JSON for failed runs" $
      eitherDecode (encode failedSummary) `shouldBe` Right failedSummary
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
    failedSummary =
      buildSummary
        (RunId "run-2")
        fixedTime
        (emptyProvenance "demo")
        [ NodeOutcome
            { outcomeNodeId = NodeId "transcode",
              outcomeStatus = NodeFailed,
              outcomeCached = False,
              outcomeOutputReference = Nothing,
              outcomeFailure = Just (validationFailure "missing-input" "Input asset is missing.")
            }
        ]

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 3 19) (secondsToDiffTime 0)
