{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.DAG.Validator
  ( validateDag,
    renderFailures,
  )
where

import Data.List (intercalate)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import StudioMCP.DAG.Memoization (memoPolicyFromText)
import StudioMCP.DAG.Types
  ( DagSpec (..),
    NodeId (..),
    NodeKind (..),
    NodeSpec (..),
    TimeoutPolicy (..),
  )
import StudioMCP.Result.Failure (FailureDetail (..), validationFailure)
import StudioMCP.Result.Types (Result (Failure, Success))

validateDag :: DagSpec -> Result DagSpec [FailureDetail]
validateDag dagSpec =
  case allFailures of
    [] -> Success dagSpec
    failures -> Failure failures
  where
    allFailures =
      concat
        [ nonEmptyFailures dagSpec,
          duplicateNodeFailures dagSpec,
          missingDependencyFailures dagSpec,
          boundaryContractFailures dagSpec,
          timeoutFailures dagSpec,
          memoPolicyFailures dagSpec,
          summaryFailures dagSpec,
          cycleFailures dagSpec
        ]

renderFailures :: [FailureDetail] -> String
renderFailures failures =
  intercalate "\n" (map renderFailure failures)

renderFailure :: FailureDetail -> String
renderFailure failureDetail =
  Text.unpack (failureCode failureDetail <> ": " <> failureMessage failureDetail)

nonEmptyFailures :: DagSpec -> [FailureDetail]
nonEmptyFailures dagSpec =
  if null (dagNodes dagSpec)
    then [validationFailure "empty-dag" "A DAG must declare at least one node."]
    else []

duplicateNodeFailures :: DagSpec -> [FailureDetail]
duplicateNodeFailures dagSpec =
  map mkFailure duplicates
  where
    counts =
      Map.fromListWith (+) [(nodeId nodeSpec, 1 :: Int) | nodeSpec <- dagNodes dagSpec]
    duplicates = [nodeKey | (nodeKey, count) <- Map.toList counts, count > 1]
    mkFailure (NodeId duplicateId) =
      validationFailure
        "duplicate-node-id"
        ("Duplicate node id found: " <> duplicateId)

missingDependencyFailures :: DagSpec -> [FailureDetail]
missingDependencyFailures dagSpec =
  concatMap missingInputsForNode (dagNodes dagSpec)
  where
    knownNodes = Set.fromList (map nodeId (dagNodes dagSpec))
    missingInputsForNode nodeSpec =
      [ validationFailure
          "missing-input-node"
          ("Node " <> unNodeId (nodeId nodeSpec) <> " references missing input " <> unNodeId inputId)
        | inputId <- nodeInputs nodeSpec,
          inputId `Set.notMember` knownNodes
      ]

boundaryContractFailures :: DagSpec -> [FailureDetail]
boundaryContractFailures dagSpec =
  concatMap nodeFailures (dagNodes dagSpec)
  where
    nodeFailures nodeSpec =
      case (nodeKind nodeSpec, nodeTool nodeSpec) of
        (PureNode, Just _) ->
          [validationFailure "pure-node-tool" "Pure nodes may not declare a tool binding."]
        (BoundaryNode, Nothing) ->
          [ validationFailure
              "boundary-node-tool-missing"
              ("Boundary node " <> unNodeId (nodeId nodeSpec) <> " must declare a tool binding.")
          ]
        (SummaryNode, Just _) ->
          [validationFailure "summary-node-tool" "Summary nodes may not declare a tool binding."]
        _ -> []

timeoutFailures :: DagSpec -> [FailureDetail]
timeoutFailures dagSpec =
  concatMap validateTimeout (dagNodes dagSpec)
  where
    validateTimeout nodeSpec =
      let seconds = timeoutSeconds (nodeTimeout nodeSpec)
       in if seconds <= 0
            then
              [ validationFailure
                  "timeout-non-positive"
                  ("Node " <> unNodeId (nodeId nodeSpec) <> " must have a positive timeout.")
              ]
            else []

memoPolicyFailures :: DagSpec -> [FailureDetail]
memoPolicyFailures dagSpec =
  concatMap validateMemoPolicy (dagNodes dagSpec)
  where
    validateMemoPolicy nodeSpec =
      case memoPolicyFromText (nodeMemoization nodeSpec) of
        Left err ->
          [ validationFailure
              "invalid-memo-policy"
              ("Node " <> unNodeId (nodeId nodeSpec) <> " has invalid memoization policy: " <> err)
          ]
        Right _ -> []

summaryFailures :: DagSpec -> [FailureDetail]
summaryFailures dagSpec =
  case length summaryNodes of
    1 -> []
    0 -> [validationFailure "missing-summary-node" "A DAG must contain exactly one summary node."]
    _ -> [validationFailure "multiple-summary-nodes" "A DAG must contain exactly one summary node."]
  where
    summaryNodes = filter ((== SummaryNode) . nodeKind) (dagNodes dagSpec)

cycleFailures :: DagSpec -> [FailureDetail]
cycleFailures dagSpec =
  if hasCycle graph
    then [validationFailure "cyclic-dag" "The DAG contains at least one cycle."]
    else []
  where
    graph = Map.fromList [(nodeId nodeSpec, nodeInputs nodeSpec) | nodeSpec <- dagNodes dagSpec]

hasCycle :: Map NodeId [NodeId] -> Bool
hasCycle graph =
  any (dfs Set.empty Set.empty) (Map.keys graph)
  where
    dfs visited active nodeKey
      | nodeKey `Set.member` active = True
      | nodeKey `Set.member` visited = False
      | otherwise =
          any
            (dfs (Set.insert nodeKey visited) (Set.insert nodeKey active))
            (Map.findWithDefault [] nodeKey graph)
