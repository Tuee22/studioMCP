{-# LANGUAGE OverloadedStrings #-}

module TestSupport.DagGenerators
  ( genLayeredDag,
    dependenciesRespectBatchOrder,
    dependenciesRespectOrder,
  )
where

import Control.Monad (forM)
import Data.List (sort)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import StudioMCP.DAG.Types
  ( DagSpec (..),
    NodeId (..),
    NodeKind (PureNode),
    NodeSpec (..),
    OutputType (..),
    TimeoutPolicy (..),
  )
import Test.QuickCheck
  ( Gen,
    chooseInt,
    shuffle,
    sublistOf,
    vectorOf,
  )

genLayeredDag :: Gen DagSpec
genLayeredDag = do
  layerCount <- chooseInt (1, 4)
  layerSizes <- vectorOf layerCount (chooseInt (1, 4))
  let layerNodeIds =
        [ [NodeId (nodeName layerIndex nodeIndex) | nodeIndex <- [1 .. layerSize]]
        | (layerIndex, layerSize) <- zip [1 :: Int ..] layerSizes
        ]
  generatedLayers <-
    forM (zip [0 :: Int ..] layerNodeIds) $ \(layerIndex, layerIds) ->
      forM layerIds $ \currentNodeId -> do
        dependencies <-
          if layerIndex == 0
            then pure []
            else sublistOf (concat (take layerIndex layerNodeIds))
        pure (mkNode currentNodeId dependencies)
  shuffledNodes <- shuffle (concat generatedLayers)
  pure
    DagSpec
      { dagName = "generated-layered-dag",
        dagDescription = Just "Generated acyclic DAG for scheduler properties.",
        dagNodes = shuffledNodes
      }

dependenciesRespectOrder :: [NodeSpec] -> Bool
dependenciesRespectOrder orderedNodes =
  all nodeDependenciesOrdered orderedNodes
  where
    orderMap =
      Map.fromList
        [ (nodeId nodeSpec, index)
        | (index, nodeSpec) <- zip [0 :: Int ..] orderedNodes
        ]
    nodeDependenciesOrdered nodeSpec =
      case Map.lookup (nodeId nodeSpec) orderMap of
        Nothing -> False
        Just nodeIndex ->
          all
            ( \dependencyNodeId ->
                maybe False (< nodeIndex) (Map.lookup dependencyNodeId orderMap)
            )
            (nodeInputs nodeSpec)

dependenciesRespectBatchOrder :: [[NodeSpec]] -> Bool
dependenciesRespectBatchOrder scheduledBatches =
  all batchDependenciesOrdered flattenedNodes
  where
    flattenedNodes = concat scheduledBatches
    batchMap =
      Map.fromList
        [ (nodeId nodeSpec, batchIndex)
        | (batchIndex, batch) <- zip [0 :: Int ..] scheduledBatches,
          nodeSpec <- batch
        ]
    batchDependenciesOrdered nodeSpec =
      case Map.lookup (nodeId nodeSpec) batchMap of
        Nothing -> False
        Just nodeBatchIndex ->
          all
            ( \dependencyNodeId ->
                maybe False (< nodeBatchIndex) (Map.lookup dependencyNodeId batchMap)
            )
            (nodeInputs nodeSpec)

mkNode :: NodeId -> [NodeId] -> NodeSpec
mkNode nodeIdValue dependencies =
  NodeSpec
    { nodeId = nodeIdValue,
      nodeKind = PureNode,
      nodeTool = Nothing,
      nodeInputs = sort dependencies,
      nodeOutputType = OutputType "text/plain",
      nodeTimeout = TimeoutPolicy 5,
      nodeMemoization = "memoize"
    }

nodeName :: Int -> Int -> Text
nodeName layerIndex nodeIndex =
  Text.pack ("layer" <> show layerIndex <> "_node" <> show nodeIndex)
