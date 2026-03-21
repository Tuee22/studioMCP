{-# LANGUAGE OverloadedStrings #-}

module Worker.ProtocolSpec
  ( spec,
  )
where

import Data.Aeson (eitherDecode, encode)
import Data.Time (UTCTime (UTCTime), fromGregorian, secondsToDiffTime)
import StudioMCP.DAG.Provenance (emptyProvenance)
import StudioMCP.DAG.Summary
  ( NodeExecutionStatus (NodeSucceeded),
    NodeOutcome (..),
    RunId (..),
    RunStatus (RunSucceeded),
    Summary,
    buildSummary,
  )
import StudioMCP.DAG.Types
  ( DagSpec (..),
    NodeId (..),
    NodeKind (..),
    NodeSpec (..),
    OutputType (..),
    TimeoutPolicy (..),
  )
import StudioMCP.Storage.Keys (manifestRefForRun, summaryRefForRun)
import StudioMCP.Worker.Protocol
  ( WorkerExecutionRequest (..),
    WorkerExecutionResponse (..),
  )
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "Worker protocol" $ do
    it "round-trips request JSON for a simple DAG" $
      eitherDecode (encode requestFixture) `shouldBe` Right requestFixture

    it "round-trips response JSON for a completed execution" $
      eitherDecode (encode responseFixture) `shouldBe` Right responseFixture

requestFixture :: WorkerExecutionRequest
requestFixture = WorkerExecutionRequest dagFixture

responseFixture :: WorkerExecutionResponse
responseFixture =
  WorkerExecutionResponse
    { workerExecutionRunId = runIdValue,
      workerExecutionStatus = RunSucceeded,
      workerExecutionSummaryRef = summaryRefForRun runIdValue,
      workerExecutionManifestRef = manifestRefForRun runIdValue,
      workerExecutionSummary = summaryFixture
    }

summaryFixture :: Summary
summaryFixture =
  buildSummary
    runIdValue
    fixedTime
    (emptyProvenance "worker-protocol")
    [ NodeOutcome
        { outcomeNodeId = NodeId "summary",
          outcomeStatus = NodeSucceeded,
          outcomeCached = False,
          outcomeOutputReference = Just "minio://studiomcp-summaries/summaries/worker-run-1.json",
          outcomeFailure = Nothing
        }
    ]

runIdValue :: RunId
runIdValue = RunId "worker-run-1"

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2024 1 1) (secondsToDiffTime 0)

dagFixture :: DagSpec
dagFixture =
  DagSpec
    { dagName = "worker-protocol-validation",
      dagDescription = Just "Worker protocol round-trip fixture.",
      dagNodes =
        [ NodeSpec
            { nodeId = NodeId "ingest",
              nodeKind = PureNode,
              nodeTool = Nothing,
              nodeInputs = [],
              nodeOutputType = OutputType "text/plain",
              nodeTimeout = TimeoutPolicy 5,
              nodeMemoization = "memoize"
            }
        ]
    }
