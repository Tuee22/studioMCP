{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.DAG.Scheduler
  ( SchedulerMode (..),
    scheduleTopologically,
    scheduleInParallelBatches,
  )
where

import Control.Monad (foldM)
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import StudioMCP.DAG.Types (DagSpec (..), NodeSpec (..))
import StudioMCP.Result.Failure (FailureDetail, validationFailure)

data SchedulerMode
  = TopologicalSequential
  | TopologicalParallelBatched
  deriving (Eq, Show)

scheduleTopologically :: DagSpec -> Either FailureDetail [NodeSpec]
scheduleTopologically dagSpec =
  fmap concat (scheduleInParallelBatches dagSpec)

scheduleInParallelBatches :: DagSpec -> Either FailureDetail [[NodeSpec]]
scheduleInParallelBatches dagSpec = go initialReadyQueue initialInDegree []
  where
    nodesById = Map.fromList [(nodeId nodeSpec, nodeSpec) | nodeSpec <- dagNodes dagSpec]
    initialInDegree = Map.fromList [(nodeId nodeSpec, length (nodeInputs nodeSpec)) | nodeSpec <- dagNodes dagSpec]
    dependencyGraph =
      foldl'
        registerDependents
        Map.empty
        (dagNodes dagSpec)
    initialReadyQueue =
      sortNodes
        [ nodeSpec
        | nodeSpec <- dagNodes dagSpec,
          Map.findWithDefault 0 (nodeId nodeSpec) initialInDegree == 0
        ]

    go [] _ scheduledBatches
      | sum (map length scheduledBatches) == length (dagNodes dagSpec) = Right (reverse scheduledBatches)
      | otherwise =
          Left (validationFailure "scheduler-cycle" "Scheduler could not produce a full topological order.")
    go readyQueue remainingInDegree scheduledBatches = do
      (nextInDegree, newlyReadyNodeIds) <- releaseDependents readyQueue remainingInDegree
      let nextReadyNodes =
            sortNodes (mapMaybe (`Map.lookup` nodesById) newlyReadyNodeIds)
      go nextReadyNodes nextInDegree (readyQueue : scheduledBatches)

    registerDependents dependentsByNode nodeSpec =
      foldl'
        (\acc dependencyNodeId -> Map.insertWith (<>) dependencyNodeId [nodeId nodeSpec] acc)
        dependentsByNode
        (nodeInputs nodeSpec)

    releaseDependents currentBatch remainingInDegree =
      foldM releaseBatchNode (remainingInDegree, []) currentBatch

    releaseBatchNode (inDegreeMap, readyNodeIds) currentNode =
      foldM releaseDependent (inDegreeMap, readyNodeIds) dependentNodeIds
      where
        dependentNodeIds = Map.findWithDefault [] (nodeId currentNode) dependencyGraph

    releaseDependent (inDegreeMap, readyNodeIds) dependentNodeId =
      case Map.lookup dependentNodeId inDegreeMap of
        Nothing ->
          Left
            ( validationFailure
                "scheduler-missing-node"
                "Scheduler encountered a dependent node that was not present in the DAG."
            )
        Just currentInDegree ->
          let nextInDegree = currentInDegree - 1
              updatedMap = Map.insert dependentNodeId nextInDegree inDegreeMap
           in if nextInDegree == 0
                then Right (updatedMap, readyNodeIds <> [dependentNodeId])
                else Right (updatedMap, readyNodeIds)

    sortNodes = sortOn nodeId
