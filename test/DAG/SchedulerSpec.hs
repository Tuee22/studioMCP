{-# LANGUAGE OverloadedStrings #-}

module DAG.SchedulerSpec
  ( spec,
  )
where

import Data.Text (Text)
import StudioMCP.DAG.Scheduler (scheduleTopologically)
import StudioMCP.DAG.Types
  ( DagSpec (..),
    NodeId (..),
    NodeKind (..),
    NodeSpec (..),
    OutputType (..),
    TimeoutPolicy (..),
  )
import StudioMCP.Result.Failure (failureCode)
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe)

spec :: Spec
spec =
  describe "scheduleTopologically" $ do
    it "produces a deterministic dependency-respecting order" $
      fmap (map nodeId) (scheduleTopologically orderedDag)
        `shouldBe` Right [NodeId "ingest", NodeId "transcode", NodeId "summary"]

    it "fails cleanly when the graph contains a cycle" $
      case scheduleTopologically cyclicDag of
        Left failureDetail ->
          failureCode failureDetail `shouldBe` "scheduler-cycle"
        Right orderedNodes ->
          expectationFailure ("expected cycle failure but got order: " <> show (map nodeId orderedNodes))

orderedDag :: DagSpec
orderedDag =
  DagSpec
    { dagName = "ordered",
      dagDescription = Just "Deterministic scheduler test DAG.",
      dagNodes =
        [ mkNode "ingest" PureNode [] "text/plain",
          mkNode "transcode" BoundaryNode [NodeId "ingest"] "audio/wav",
          mkNode "summary" SummaryNode [NodeId "transcode"] "summary/run"
        ]
    }

cyclicDag :: DagSpec
cyclicDag =
  DagSpec
    { dagName = "cyclic",
      dagDescription = Just "Scheduler cycle test DAG.",
      dagNodes =
        [ mkNode "a" PureNode [NodeId "b"] "text/plain",
          mkNode "b" BoundaryNode [NodeId "a"] "audio/wav",
          mkNode "summary" SummaryNode [NodeId "b"] "summary/run"
        ]
    }

mkNode :: Text -> NodeKind -> [NodeId] -> Text -> NodeSpec
mkNode nodeName nodeKindValue inputIds outputTypeValue =
  NodeSpec
    { nodeId = NodeId nodeName,
      nodeKind = nodeKindValue,
      nodeTool =
        case nodeKindValue of
          BoundaryNode -> Just "ffmpeg"
          _ -> Nothing,
      nodeInputs = inputIds,
      nodeOutputType = OutputType outputTypeValue,
      nodeTimeout = TimeoutPolicy 5,
      nodeMemoization = "memoize"
    }
