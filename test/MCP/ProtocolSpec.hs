{-# LANGUAGE OverloadedStrings #-}

module MCP.ProtocolSpec
  ( spec,
  )
where

import Data.Aeson (eitherDecode, encode)
import StudioMCP.DAG.Summary (RunId (..), RunStatus (RunRunning))
import StudioMCP.DAG.Types
  ( DagSpec (..),
    NodeId (..),
    NodeKind (..),
    NodeSpec (..),
    OutputType (..),
    TimeoutPolicy (..),
  )
import StudioMCP.MCP.Protocol (SubmissionRequest (..), SubmissionResponse (..))
import StudioMCP.Storage.Keys (summaryRefForRun)
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "Submission protocol" $ do
    it "round-trips request JSON for a simple DAG" $
      eitherDecode (encode requestFixture) `shouldBe` Right requestFixture

    it "round-trips response JSON for running submissions" $
      eitherDecode (encode responseFixture) `shouldBe` Right responseFixture

  where
    runIdValue = RunId "mcp-run-1"
    requestFixture = SubmissionRequest dagFixture
    responseFixture =
      SubmissionResponse
        { submissionRunId = runIdValue,
          submissionStatus = RunRunning,
          submissionSummaryRef = summaryRefForRun runIdValue
        }

dagFixture :: DagSpec
dagFixture =
  DagSpec
    { dagName = "protocol-validation",
      dagDescription = Just "Protocol round-trip fixture.",
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
