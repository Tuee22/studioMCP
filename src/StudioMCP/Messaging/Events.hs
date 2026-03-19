module StudioMCP.Messaging.Events
  ( ExecutionEventType (..),
    ExecutionEvent (..),
  )
where

import Data.Text (Text)
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

data ExecutionEvent = ExecutionEvent
  { eventRunId :: RunId,
    eventNodeId :: Maybe NodeId,
    eventType :: ExecutionEventType,
    eventDetail :: Text,
    eventTimestamp :: UTCTime
  }
  deriving (Eq, Show)
