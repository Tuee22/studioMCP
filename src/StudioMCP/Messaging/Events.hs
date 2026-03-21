{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Messaging.Events
  ( ExecutionEventType (..),
    ExecutionEvent (..),
  )
where

import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    Value (String),
    object,
    withObject,
    withText,
    (.!=),
    (.:),
    (.:?),
    (.=),
  )
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime)
import StudioMCP.DAG.Summary (RunId)
import StudioMCP.DAG.Types (NodeId)

data ExecutionEventType
  = RunSubmitted
  | NodeScheduled
  | NodeStarted
  | NodeCompleted
  | NodeFailedEvent
  | NodeTimedOutEvent
  | SummaryEmitted
  deriving (Eq, Show)

instance FromJSON ExecutionEventType where
  parseJSON =
    withText "ExecutionEventType" $ \value ->
      case value of
        "run_submitted" -> pure RunSubmitted
        "node_scheduled" -> pure NodeScheduled
        "node_started" -> pure NodeStarted
        "node_completed" -> pure NodeCompleted
        "node_failed" -> pure NodeFailedEvent
        "node_timed_out" -> pure NodeTimedOutEvent
        "summary_emitted" -> pure SummaryEmitted
        _ -> fail ("Unknown execution event type: " <> Text.unpack value)

instance ToJSON ExecutionEventType where
  toJSON eventType =
    String $
      case eventType of
        RunSubmitted -> "run_submitted"
        NodeScheduled -> "node_scheduled"
        NodeStarted -> "node_started"
        NodeCompleted -> "node_completed"
        NodeFailedEvent -> "node_failed"
        NodeTimedOutEvent -> "node_timed_out"
        SummaryEmitted -> "summary_emitted"

data ExecutionEvent = ExecutionEvent
  { eventRunId :: RunId,
    eventNodeId :: Maybe NodeId,
    eventType :: ExecutionEventType,
    eventDetail :: Text,
    eventTimestamp :: UTCTime
  }
  deriving (Eq, Show)

instance FromJSON ExecutionEvent where
  parseJSON = withObject "ExecutionEvent" $ \obj ->
    ExecutionEvent
      <$> obj .: "runId"
      <*> obj .:? "nodeId"
      <*> obj .: "type"
      <*> obj .:? "detail" .!= ""
      <*> obj .: "timestamp"

instance ToJSON ExecutionEvent where
  toJSON executionEvent =
    object
      [ "runId" .= eventRunId executionEvent,
        "nodeId" .= eventNodeId executionEvent,
        "type" .= eventType executionEvent,
        "detail" .= eventDetail executionEvent,
        "timestamp" .= eventTimestamp executionEvent
      ]
