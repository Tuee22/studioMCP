module StudioMCP.Messaging.ExecutionState
  ( RunPhase (..),
    ExecutionState (..),
    StateTransitionError (..),
    initialExecutionState,
    advanceState,
  )
where

import StudioMCP.Messaging.Events (ExecutionEventType (..))

data RunPhase
  = Pending
  | Submitted
  | Running
  | Failed
  | Completed
  deriving (Eq, Show)

newtype ExecutionState = ExecutionState
  { runPhase :: RunPhase
  }
  deriving (Eq, Show)

data StateTransitionError = StateTransitionError
  { transitionFrom :: RunPhase,
    transitionEvent :: ExecutionEventType
  }
  deriving (Eq, Show)

initialExecutionState :: ExecutionState
initialExecutionState = ExecutionState Pending

advanceState :: ExecutionState -> ExecutionEventType -> Either StateTransitionError ExecutionState
advanceState (ExecutionState Pending) RunSubmitted = Right (ExecutionState Submitted)
advanceState (ExecutionState Submitted) NodeScheduled = Right (ExecutionState Running)
advanceState (ExecutionState Submitted) NodeStarted = Right (ExecutionState Running)
advanceState (ExecutionState Running) NodeStarted = Right (ExecutionState Running)
advanceState (ExecutionState Running) NodeCompleted = Right (ExecutionState Running)
advanceState (ExecutionState Running) SummaryEmitted = Right (ExecutionState Completed)
advanceState (ExecutionState Running) NodeFailedEvent = Right (ExecutionState Failed)
advanceState (ExecutionState Running) NodeTimedOutEvent = Right (ExecutionState Failed)
advanceState (ExecutionState Failed) eventTypeValue =
  Left (StateTransitionError Failed eventTypeValue)
advanceState (ExecutionState Completed) eventTypeValue =
  Left (StateTransitionError Completed eventTypeValue)
advanceState (ExecutionState runPhaseValue) eventTypeValue =
  Left (StateTransitionError runPhaseValue eventTypeValue)
