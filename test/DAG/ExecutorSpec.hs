{-# LANGUAGE OverloadedStrings #-}

module DAG.ExecutorSpec
  ( spec,
  )
where

import Control.Concurrent (threadDelay)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef, writeIORef)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Time (UTCTime (UTCTime), fromGregorian, secondsToDiffTime)
import StudioMCP.DAG.Executor
  ( ExecutionReport (..),
    ExecutorAdapters (..),
    executeParallel,
    executeSequential,
  )
import StudioMCP.DAG.Summary
  ( NodeExecutionStatus (..),
    NodeOutcome (..),
    RunId (..),
    RunStatus (..),
    Summary,
    summaryNodeOutcomes,
    summaryStatus,
  )
import StudioMCP.DAG.Types
  ( DagSpec (..),
    NodeId (..),
    NodeKind (..),
    NodeSpec (..),
    OutputType (..),
    TimeoutPolicy (..),
  )
import StudioMCP.Result.Failure
  ( FailureCategory (ToolProcessFailure),
    FailureDetail (..),
    failureCode,
  )
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe)

spec :: Spec
spec = do
  describe "executeSequential" $ do
    it "runs a simple DAG in topological order and assembles a successful summary" $ do
      observedOutcomesRef <- newIORef []
      observedSummaryRef <- newIORef Nothing
      result <- executeSequential (successAdapters observedOutcomesRef observedSummaryRef) (RunId "run-success") fixedTime executorDag
      case result of
        Left failureDetail ->
          expectationFailure ("expected success but got failure: " <> show failureDetail)
        Right executionReport -> do
          reportOrder executionReport `shouldBe` [NodeId "ingest", NodeId "transcode", NodeId "summary"]
          Map.lookup (NodeId "transcode") (reportOutputs executionReport) `shouldBe` Just "boundary://transcode/pure://ingest"
          summaryStatus (reportSummary executionReport) `shouldBe` RunSucceeded
          map outcomeStatus (summaryNodeOutcomes (reportSummary executionReport))
            `shouldBe` [NodeSucceeded, NodeSucceeded, NodeSucceeded]
          observedOutcomes <- readIORef observedOutcomesRef
          map outcomeNodeId observedOutcomes `shouldBe` [NodeId "ingest", NodeId "transcode", NodeId "summary"]
          observedSummary <- readIORef observedSummaryRef
          observedSummary `shouldBe` Just (reportSummary executionReport)

    it "marks downstream nodes as failed when an upstream boundary fails" $ do
      observedOutcomesRef <- newIORef []
      observedSummaryRef <- newIORef Nothing
      result <- executeSequential (failureAdapters observedOutcomesRef observedSummaryRef) (RunId "run-failure") fixedTime executorDag
      case result of
        Left failureDetail ->
          expectationFailure ("expected report with failed summary but got failure: " <> show failureDetail)
        Right executionReport -> do
          summaryStatus (reportSummary executionReport) `shouldBe` RunFailed
          map outcomeStatus (summaryNodeOutcomes (reportSummary executionReport))
            `shouldBe` [NodeSucceeded, NodeFailed, NodeFailed]
          let summaryOutcome = last (summaryNodeOutcomes (reportSummary executionReport))
          fmap failureCode (outcomeFailure summaryOutcome) `shouldBe` Just "upstream-dependency-failed"
          observedOutcomes <- readIORef observedOutcomesRef
          map outcomeStatus observedOutcomes `shouldBe` [NodeSucceeded, NodeFailed, NodeFailed]

  describe "executeParallel" $ do
    it "runs independent nodes in the same batch before downstream aggregation" $ do
      observedOutcomesRef <- newIORef []
      observedSummaryRef <- newIORef Nothing
      branchCountRef <- newIORef (0 :: Int)
      result <- executeParallel (parallelAdapters observedOutcomesRef observedSummaryRef branchCountRef) (RunId "run-parallel") fixedTime parallelDag
      case result of
        Left failureDetail ->
          expectationFailure ("expected parallel success but got failure: " <> show failureDetail)
        Right executionReport -> do
          reportOrder executionReport `shouldBe` [NodeId "ingest", NodeId "branch-b", NodeId "branch-c", NodeId "summary"]
          summaryStatus (reportSummary executionReport) `shouldBe` RunSucceeded
          observedOutcomes <- readIORef observedOutcomesRef
          map outcomeNodeId observedOutcomes `shouldBe` [NodeId "ingest", NodeId "branch-b", NodeId "branch-c", NodeId "summary"]
          branchCount <- readIORef branchCountRef
          branchCount `shouldBe` 2

successAdapters :: IORef [NodeOutcome] -> IORef (Maybe Summary) -> ExecutorAdapters
successAdapters observedOutcomesRef observedSummaryRef =
  ExecutorAdapters
    { executePureNode = \nodeSpec _ -> pure (Right ("pure://" <> unNodeId (nodeId nodeSpec))),
      executeBoundaryNode = \nodeSpec inputReferences ->
        pure (Right ("boundary://" <> unNodeId (nodeId nodeSpec) <> "/" <> joinInputs inputReferences)),
      observeNodeOutcome = \nodeOutcome -> modifyIORef' observedOutcomesRef (<> [nodeOutcome]),
      observeSummary = writeIORef observedSummaryRef . Just
    }

failureAdapters :: IORef [NodeOutcome] -> IORef (Maybe Summary) -> ExecutorAdapters
failureAdapters observedOutcomesRef observedSummaryRef =
  ExecutorAdapters
    { executePureNode = \nodeSpec _ -> pure (Right ("pure://" <> unNodeId (nodeId nodeSpec))),
      executeBoundaryNode = \_ _ ->
        pure
          ( Left
              FailureDetail
                { failureCategory = ToolProcessFailure,
                  failureCode = "deterministic-boundary-failure",
                  failureMessage = "Deterministic boundary failure for executor unit tests.",
                  failureRetryable = False,
                  failureContext = Map.empty
                }
          ),
      observeNodeOutcome = \nodeOutcome -> modifyIORef' observedOutcomesRef (<> [nodeOutcome]),
      observeSummary = writeIORef observedSummaryRef . Just
    }

executorDag :: DagSpec
executorDag =
  DagSpec
    { dagName = "executor-unit",
      dagDescription = Just "Deterministic executor unit-test DAG.",
      dagNodes =
        [ mkNode "ingest" PureNode [] "text/plain",
          mkNode "transcode" BoundaryNode [NodeId "ingest"] "audio/wav",
          mkNode "summary" SummaryNode [NodeId "transcode"] "summary/run"
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

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 3 19) (secondsToDiffTime 0)

joinInputs :: [Text] -> Text
joinInputs [] = ""
joinInputs [value] = value
joinInputs (value : remaining) = value <> "+" <> joinInputs remaining

parallelAdapters :: IORef [NodeOutcome] -> IORef (Maybe Summary) -> IORef Int -> ExecutorAdapters
parallelAdapters observedOutcomesRef observedSummaryRef branchCountRef =
  ExecutorAdapters
    { executePureNode = \nodeSpec _ -> pure (Right ("pure://" <> unNodeId (nodeId nodeSpec))),
      executeBoundaryNode = \nodeSpec inputReferences -> do
        modifyIORef' branchCountRef (+ 1)
        peerReady <- waitForOtherBranch branchCountRef 50
        if peerReady
          then pure (Right ("boundary://" <> unNodeId (nodeId nodeSpec) <> "/" <> joinInputs inputReferences))
          else
            pure
              ( Left
                  FailureDetail
                    { failureCategory = ToolProcessFailure,
                      failureCode = "parallel-branch-timeout",
                      failureMessage = "Independent branch did not overlap with its peer.",
                      failureRetryable = False,
                      failureContext = Map.empty
                    }
              ),
      observeNodeOutcome = \nodeOutcome -> modifyIORef' observedOutcomesRef (<> [nodeOutcome]),
      observeSummary = writeIORef observedSummaryRef . Just
    }

parallelDag :: DagSpec
parallelDag =
  DagSpec
    { dagName = "executor-parallel-unit",
      dagDescription = Just "Deterministic parallel executor unit-test DAG.",
      dagNodes =
        [ mkNode "ingest" PureNode [] "text/plain",
          mkNode "branch-b" BoundaryNode [NodeId "ingest"] "audio/wav",
          mkNode "branch-c" BoundaryNode [NodeId "ingest"] "audio/wav",
          mkNode "summary" SummaryNode [NodeId "branch-b", NodeId "branch-c"] "summary/run"
        ]
    }

waitForOtherBranch :: IORef Int -> Int -> IO Bool
waitForOtherBranch branchCountRef attemptsRemaining
  | attemptsRemaining <= 0 = pure False
  | otherwise = do
      branchCount <- readIORef branchCountRef
      if branchCount >= 2
        then pure True
        else do
          threadDelay 10000
          waitForOtherBranch branchCountRef (attemptsRemaining - 1)
