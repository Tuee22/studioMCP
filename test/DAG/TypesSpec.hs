{-# LANGUAGE OverloadedStrings #-}

module DAG.TypesSpec (spec) where

import Data.Aeson (decode, encode)
import StudioMCP.DAG.Types
import Test.Hspec

spec :: Spec
spec = do
  describe "NodeId" $ do
    it "can be created from text" $ do
      let nodeId = NodeId "test-node"
      unNodeId nodeId `shouldBe` "test-node"

    it "can be compared for equality" $ do
      NodeId "a" `shouldBe` NodeId "a"
      NodeId "a" `shouldNotBe` NodeId "b"

    it "round-trips through JSON" $ do
      let nodeId = NodeId "my-node"
      (decode (encode nodeId) :: Maybe NodeId) `shouldBe` Just nodeId

    it "has Ord instance" $ do
      NodeId "a" < NodeId "b" `shouldBe` True
      NodeId "z" > NodeId "a" `shouldBe` True

  describe "NodeKind" $ do
    it "distinguishes PureNode" $ do
      PureNode `shouldBe` PureNode
      PureNode `shouldNotBe` BoundaryNode

    it "distinguishes BoundaryNode" $ do
      BoundaryNode `shouldBe` BoundaryNode
      BoundaryNode `shouldNotBe` SummaryNode

    it "distinguishes SummaryNode" $ do
      SummaryNode `shouldBe` SummaryNode
      SummaryNode `shouldNotBe` PureNode

    it "round-trips through JSON" $ do
      (decode (encode PureNode) :: Maybe NodeKind) `shouldBe` Just PureNode
      (decode (encode BoundaryNode) :: Maybe NodeKind) `shouldBe` Just BoundaryNode
      (decode (encode SummaryNode) :: Maybe NodeKind) `shouldBe` Just SummaryNode

  describe "OutputType" $ do
    it "can be created from text" $ do
      let ot = OutputType "video/mp4"
      unOutputType ot `shouldBe` "video/mp4"

    it "round-trips through JSON" $ do
      let ot = OutputType "application/json"
      (decode (encode ot) :: Maybe OutputType) `shouldBe` Just ot

  describe "TimeoutPolicy" $ do
    it "can be created with seconds" $ do
      let tp = TimeoutPolicy 30
      timeoutSeconds tp `shouldBe` 30

    it "can be compared for equality" $ do
      TimeoutPolicy 10 `shouldBe` TimeoutPolicy 10
      TimeoutPolicy 10 `shouldNotBe` TimeoutPolicy 20

    it "round-trips through JSON" $ do
      let tp = TimeoutPolicy 60
      (decode (encode tp) :: Maybe TimeoutPolicy) `shouldBe` Just tp

  describe "NodeSpec" $ do
    it "can be created with all fields" $ do
      let node = NodeSpec
            { nodeId = NodeId "test"
            , nodeKind = PureNode
            , nodeTool = Just "echo"
            , nodeInputs = [NodeId "input1"]
            , nodeOutputType = OutputType "text/plain"
            , nodeTimeout = TimeoutPolicy 30
            , nodeMemoization = "content-hash"
            }
      unNodeId (nodeId node) `shouldBe` "test"
      nodeKind node `shouldBe` PureNode
      nodeTool node `shouldBe` Just "echo"

    it "round-trips through JSON" $ do
      let node = NodeSpec
            { nodeId = NodeId "node1"
            , nodeKind = BoundaryNode
            , nodeTool = Nothing
            , nodeInputs = []
            , nodeOutputType = OutputType "application/octet-stream"
            , nodeTimeout = TimeoutPolicy 120
            , nodeMemoization = "none"
            }
      (decode (encode node) :: Maybe NodeSpec) `shouldBe` Just node

  describe "DagSpec" $ do
    it "can be created with all fields" $ do
      let dag = DagSpec
            { dagName = "test-dag"
            , dagDescription = Just "A test DAG"
            , dagNodes = []
            }
      dagName dag `shouldBe` "test-dag"
      dagDescription dag `shouldBe` Just "A test DAG"
      dagNodes dag `shouldBe` []

    it "can have no description" $ do
      let dag = DagSpec "dag" Nothing []
      dagDescription dag `shouldBe` Nothing

    it "round-trips through JSON" $ do
      let node = NodeSpec
            { nodeId = NodeId "n1"
            , nodeKind = PureNode
            , nodeTool = Just "tool"
            , nodeInputs = []
            , nodeOutputType = OutputType "text"
            , nodeTimeout = TimeoutPolicy 10
            , nodeMemoization = "hash"
            }
          dag = DagSpec "my-dag" (Just "desc") [node]
      (decode (encode dag) :: Maybe DagSpec) `shouldBe` Just dag

    it "can be compared for equality" $ do
      let dag1 = DagSpec "dag" Nothing []
          dag2 = DagSpec "dag" Nothing []
          dag3 = DagSpec "other" Nothing []
      dag1 `shouldBe` dag2
      dag1 `shouldNotBe` dag3
