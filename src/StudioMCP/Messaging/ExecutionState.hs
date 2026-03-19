module StudioMCP.Messaging.ExecutionState
  ( RunPhase (..),
    ExecutionState (..),
    advanceState,
  )
where

import StudioMCP.Messaging.Events (ExecutionEventType (..))

data RunPhase
  = Submitted
  | Running
  | Failed
  | Completed
  deriving (Eq, Show)

newtype ExecutionState = ExecutionState
  { runPhase :: RunPhase
  }
  deriving (Eq, Show)

advanceState :: ExecutionState -> ExecutionEventType -> ExecutionState
advanceState _ RunSubmitted = ExecutionState Submitted
advanceState _ NodeScheduled = ExecutionState Running
advanceState _ NodeStarted = ExecutionState Running
advanceState _ NodeCompleted = ExecutionState Running
advanceState _ NodeFailedEvent = ExecutionState Failed
advanceState _ NodeTimedOutEvent = ExecutionState Failed
advanceState _ SummaryEmitted = ExecutionState Completed
