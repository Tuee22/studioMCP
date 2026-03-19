{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.DAG.Types
  ( DagSpec (..),
    NodeSpec (..),
    NodeId (..),
    NodeKind (..),
    TimeoutPolicy (..),
    OutputType (..),
  )
where

import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    Value (String),
    withObject,
    withText,
    (.:),
    (.:?),
    (.!=),
  )
import Data.Text (Text)
import qualified Data.Text as Text
import GHC.Generics (Generic)

newtype NodeId = NodeId
  { unNodeId :: Text
  }
  deriving (Eq, Ord, Show, Generic)

instance FromJSON NodeId where
  parseJSON = withText "NodeId" (pure . NodeId)

instance ToJSON NodeId where
  toJSON (NodeId value) = String value

data NodeKind
  = PureNode
  | BoundaryNode
  | SummaryNode
  deriving (Eq, Ord, Show, Generic)

instance FromJSON NodeKind where
  parseJSON =
    withText "NodeKind" $ \value ->
      case Text.toLower value of
        "pure" -> pure PureNode
        "boundary" -> pure BoundaryNode
        "summary" -> pure SummaryNode
        _ -> fail "NodeKind must be one of: pure, boundary, summary"

instance ToJSON NodeKind where
  toJSON nodeKind =
    String $
      case nodeKind of
        PureNode -> "pure"
        BoundaryNode -> "boundary"
        SummaryNode -> "summary"

newtype OutputType = OutputType
  { unOutputType :: Text
  }
  deriving (Eq, Ord, Show, Generic)

instance FromJSON OutputType where
  parseJSON = withText "OutputType" (pure . OutputType)

instance ToJSON OutputType where
  toJSON (OutputType value) = String value

data TimeoutPolicy = TimeoutPolicy
  { timeoutSeconds :: Int
  }
  deriving (Eq, Ord, Show, Generic)

instance FromJSON TimeoutPolicy where
  parseJSON = withObject "TimeoutPolicy" $ \obj ->
    TimeoutPolicy <$> obj .: "seconds"

data NodeSpec = NodeSpec
  { nodeId :: NodeId,
    nodeKind :: NodeKind,
    nodeTool :: Maybe Text,
    nodeInputs :: [NodeId],
    nodeOutputType :: OutputType,
    nodeTimeout :: TimeoutPolicy,
    nodeMemoization :: Text
  }
  deriving (Eq, Show, Generic)

instance FromJSON NodeSpec where
  parseJSON = withObject "NodeSpec" $ \obj ->
    NodeSpec
      <$> obj .: "id"
      <*> obj .: "kind"
      <*> obj .:? "tool"
      <*> obj .:? "inputs" .!= []
      <*> obj .: "outputType"
      <*> obj .: "timeout"
      <*> obj .: "memoization"

data DagSpec = DagSpec
  { dagName :: Text,
    dagDescription :: Maybe Text,
    dagNodes :: [NodeSpec]
  }
  deriving (Eq, Show, Generic)

instance FromJSON DagSpec where
  parseJSON = withObject "DagSpec" $ \obj ->
    DagSpec
      <$> obj .: "name"
      <*> obj .:? "description"
      <*> obj .: "nodes"
