{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.DAG.Executor
  ( ExecutionReport (..),
    ExecutorAdapters (..),
    executeSequential,
    validateExecutorRuntime,
  )
where

import Control.Monad (foldM)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef, writeIORef)
import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime (UTCTime), fromGregorian, secondsToDiffTime)
import StudioMCP.DAG.Provenance (emptyProvenance)
import StudioMCP.DAG.Scheduler (scheduleTopologically)
import StudioMCP.DAG.Summary
  ( NodeExecutionStatus (..),
    NodeOutcome (..),
    RunId (..),
    RunStatus (..),
    Summary,
    buildSummary,
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
  ( FailureCategory (TimeoutFailure, ToolProcessFailure),
    FailureDetail (..),
    validationFailure,
  )

data ExecutorAdapters = ExecutorAdapters
  { executePureNode :: NodeSpec -> [Text] -> IO (Either FailureDetail Text),
    executeBoundaryNode :: NodeSpec -> [Text] -> IO (Either FailureDetail Text),
    observeNodeOutcome :: NodeOutcome -> IO (),
    observeSummary :: Summary -> IO ()
  }

data ExecutionReport = ExecutionReport
  { reportOrder :: [NodeId],
    reportSummary :: Summary,
    reportOutputs :: Map NodeId Text
  }
  deriving (Eq, Show)

data ExecutionState = ExecutionState
  { stateOutputs :: Map NodeId Text,
    stateOutcomes :: [NodeOutcome],
    stateOutcomeByNode :: Map NodeId NodeOutcome,
    stateOrder :: [NodeId]
  }

executeSequential ::
  ExecutorAdapters ->
  RunId ->
  UTCTime ->
  DagSpec ->
  IO (Either FailureDetail ExecutionReport)
executeSequential adapters runIdValue startedAt dagSpec =
  case scheduleTopologically dagSpec of
    Left failureDetail -> pure (Left failureDetail)
    Right orderedNodes -> do
      finalState <- foldM (executeNode adapters runIdValue) emptyExecutionState orderedNodes
      let summary = buildSummary runIdValue startedAt (emptyProvenance (dagName dagSpec)) (stateOutcomes finalState)
      observeSummary adapters summary
      pure
        ( Right
            ExecutionReport
              { reportOrder = stateOrder finalState,
                reportSummary = summary,
                reportOutputs = stateOutputs finalState
              }
        )

validateExecutorRuntime :: IO (Either FailureDetail ())
validateExecutorRuntime = do
  observedOutcomesRef <- newIORef []
  observedSummaryRef <- newIORef Nothing
  successResult <- executeSequential (successAdapters observedOutcomesRef observedSummaryRef) (RunId "executor-success") fixedTime successDag
  case successResult of
    Left failureDetail -> pure (Left failureDetail)
    Right successReport
      | reportOrder successReport /= [NodeId "ingest", NodeId "transcode", NodeId "summary"] ->
          pure (Left executorOrderMismatch)
      | summaryStatus (reportSummary successReport) /= RunSucceeded ->
          pure (Left executorSuccessSummaryMismatch)
      | map outcomeStatus (summaryNodeOutcomes (reportSummary successReport)) /= [NodeSucceeded, NodeSucceeded, NodeSucceeded] ->
          pure (Left executorSuccessOutcomesMismatch)
      | otherwise -> do
          observedSuccessOutcomes <- readIORef observedOutcomesRef
          observedSuccessSummary <- readIORef observedSummaryRef
          if length observedSuccessOutcomes /= 3 || observedSuccessSummary == Nothing
            then pure (Left executorObserverMismatch)
            else do
              failureObservedOutcomesRef <- newIORef []
              failureObservedSummaryRef <- newIORef Nothing
              failureResult <- executeSequential (failureAdapters failureObservedOutcomesRef failureObservedSummaryRef) (RunId "executor-failure") fixedTime successDag
              case failureResult of
                Left failureDetail -> pure (Left failureDetail)
                Right failureReport
                  | summaryStatus (reportSummary failureReport) /= RunFailed ->
                      pure (Left executorFailureSummaryMismatch)
                  | map outcomeStatus (summaryNodeOutcomes (reportSummary failureReport)) /= [NodeSucceeded, NodeFailed, NodeFailed] ->
                      pure (Left executorFailureOutcomesMismatch)
                  | otherwise -> do
                      observedFailureOutcomes <- readIORef failureObservedOutcomesRef
                      observedFailureSummary <- readIORef failureObservedSummaryRef
                      if length observedFailureOutcomes /= 3 || observedFailureSummary == Nothing
                        then pure (Left executorObserverMismatch)
                        else pure (Right ())

executeNode ::
  ExecutorAdapters ->
  RunId ->
  ExecutionState ->
  NodeSpec ->
  IO ExecutionState
executeNode adapters runIdValue executionState nodeSpec = do
  let upstreamFailures =
        [ dependencyOutcome
        | dependencyNodeId <- nodeInputs nodeSpec,
          dependencyOutcome <- maybeToList (Map.lookup dependencyNodeId (stateOutcomeByNode executionState)),
          outcomeStatus dependencyOutcome /= NodeSucceeded
        ]
      inputReferences =
        [ outputReference
        | dependencyNodeId <- nodeInputs nodeSpec,
          outputReference <- maybeToList (Map.lookup dependencyNodeId (stateOutputs executionState))
        ]
  nodeOutcome <-
    case upstreamFailures of
      blockingOutcome : remainingFailures ->
        pure
          NodeOutcome
            { outcomeNodeId = nodeId nodeSpec,
              outcomeStatus = NodeFailed,
              outcomeCached = False,
              outcomeOutputReference = Nothing,
              outcomeFailure = Just (upstreamDependencyFailure nodeSpec (blockingOutcome :| remainingFailures))
            }
      [] ->
        case nodeKind nodeSpec of
          PureNode -> projectNodeResult nodeSpec =<< executePureNode adapters nodeSpec inputReferences
          BoundaryNode -> projectNodeResult nodeSpec =<< executeBoundaryNode adapters nodeSpec inputReferences
          SummaryNode ->
            pure
              NodeOutcome
                { outcomeNodeId = nodeId nodeSpec,
                  outcomeStatus = NodeSucceeded,
                  outcomeCached = False,
                  outcomeOutputReference = Just (summaryOutputReference runIdValue),
                  outcomeFailure = Nothing
                }
  observeNodeOutcome adapters nodeOutcome
  pure
    ExecutionState
      { stateOutputs =
          case outcomeOutputReference nodeOutcome of
            Just outputReference -> Map.insert (outcomeNodeId nodeOutcome) outputReference (stateOutputs executionState)
            Nothing -> stateOutputs executionState,
        stateOutcomes = stateOutcomes executionState <> [nodeOutcome],
        stateOutcomeByNode = Map.insert (outcomeNodeId nodeOutcome) nodeOutcome (stateOutcomeByNode executionState),
        stateOrder = stateOrder executionState <> [nodeId nodeSpec]
      }

projectNodeResult :: NodeSpec -> Either FailureDetail Text -> IO NodeOutcome
projectNodeResult nodeSpec result =
  pure $
    case result of
      Right outputReference ->
        NodeOutcome
          { outcomeNodeId = nodeId nodeSpec,
            outcomeStatus = NodeSucceeded,
            outcomeCached = False,
            outcomeOutputReference = Just outputReference,
            outcomeFailure = Nothing
          }
      Left failureDetail ->
        NodeOutcome
          { outcomeNodeId = nodeId nodeSpec,
            outcomeStatus =
              if failureCategory failureDetail == TimeoutFailure
                then NodeTimedOut
                else NodeFailed,
            outcomeCached = False,
            outcomeOutputReference = Nothing,
            outcomeFailure = Just failureDetail
          }

emptyExecutionState :: ExecutionState
emptyExecutionState =
  ExecutionState
    { stateOutputs = Map.empty,
      stateOutcomes = [],
      stateOutcomeByNode = Map.empty,
      stateOrder = []
    }

upstreamDependencyFailure :: NodeSpec -> NonEmpty NodeOutcome -> FailureDetail
upstreamDependencyFailure nodeSpec (blockingOutcome :| _) =
  FailureDetail
    { failureCategory = failureCategory blockingFailure,
      failureCode = "upstream-dependency-failed",
      failureMessage =
        "Node "
          <> unNodeId (nodeId nodeSpec)
          <> " did not run because an upstream dependency failed.",
      failureRetryable = failureRetryable blockingFailure,
      failureContext =
        Map.fromList
          [ ("nodeId", unNodeId (nodeId nodeSpec)),
            ("blockingNodeId", unNodeId (outcomeNodeId blockingOutcome)),
            ("blockingFailureCode", failureCode blockingFailure)
          ]
    }
  where
    blockingFailure = maybe fallbackFailure id (outcomeFailure blockingOutcome)
    fallbackFailure = validationFailure "missing-upstream-failure" "Upstream dependency outcome did not include a failure detail."

summaryOutputReference :: RunId -> Text
summaryOutputReference (RunId runIdText) = "summary://run/" <> runIdText

successAdapters :: IORef [NodeOutcome] -> IORef (Maybe Summary) -> ExecutorAdapters
successAdapters observedOutcomesRef observedSummaryRef =
  ExecutorAdapters
    { executePureNode = \nodeSpec _ -> pure (Right ("pure://" <> unNodeId (nodeId nodeSpec))),
      executeBoundaryNode = \nodeSpec inputReferences ->
        pure (Right ("boundary://" <> unNodeId (nodeId nodeSpec) <> "/" <> Text.intercalate "+" inputReferences)),
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
                  failureMessage = "Deterministic boundary failure for executor validation.",
                  failureRetryable = False,
                  failureContext = Map.empty
                }
          ),
      observeNodeOutcome = \nodeOutcome -> modifyIORef' observedOutcomesRef (<> [nodeOutcome]),
      observeSummary = writeIORef observedSummaryRef . Just
    }

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 3 19) (secondsToDiffTime 0)

successDag :: DagSpec
successDag =
  DagSpec
    { dagName = "executor-validation",
      dagDescription = Just "Deterministic executor validation DAG.",
      dagNodes =
        [ NodeSpec
            { nodeId = NodeId "ingest",
              nodeKind = PureNode,
              nodeTool = Nothing,
              nodeInputs = [],
              nodeOutputType = OutputType "text/plain",
              nodeTimeout = TimeoutPolicy 5,
              nodeMemoization = "memoize"
            },
          NodeSpec
            { nodeId = NodeId "transcode",
              nodeKind = BoundaryNode,
              nodeTool = Just "ffmpeg",
              nodeInputs = [NodeId "ingest"],
              nodeOutputType = OutputType "audio/wav",
              nodeTimeout = TimeoutPolicy 5,
              nodeMemoization = "memoize"
            },
          NodeSpec
            { nodeId = NodeId "summary",
              nodeKind = SummaryNode,
              nodeTool = Nothing,
              nodeInputs = [NodeId "transcode"],
              nodeOutputType = OutputType "summary/run",
              nodeTimeout = TimeoutPolicy 5,
              nodeMemoization = "no-memoize"
            }
        ]
    }

executorOrderMismatch :: FailureDetail
executorOrderMismatch =
  validationFailure "executor-order-mismatch" "Executor did not preserve the expected topological node order."

executorSuccessSummaryMismatch :: FailureDetail
executorSuccessSummaryMismatch =
  validationFailure "executor-success-summary-mismatch" "Successful executor validation did not produce a successful summary."

executorSuccessOutcomesMismatch :: FailureDetail
executorSuccessOutcomesMismatch =
  validationFailure "executor-success-outcomes-mismatch" "Successful executor validation did not produce the expected node outcomes."

executorFailureSummaryMismatch :: FailureDetail
executorFailureSummaryMismatch =
  validationFailure "executor-failure-summary-mismatch" "Failing executor validation did not produce a failed summary."

executorFailureOutcomesMismatch :: FailureDetail
executorFailureOutcomesMismatch =
  validationFailure "executor-failure-outcomes-mismatch" "Failing executor validation did not produce the expected node outcomes."

executorObserverMismatch :: FailureDetail
executorObserverMismatch =
  validationFailure "executor-observer-mismatch" "Executor observers did not receive the expected node outcomes and summary."

maybeToList :: Maybe a -> [a]
maybeToList maybeValue =
  case maybeValue of
    Just value -> [value]
    Nothing -> []
