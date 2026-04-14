{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.MCP.Protocol.StateMachine
  ( -- * Protocol State
    ProtocolState (..),
    ProtocolEvent (..),
    StateTransitionError (..),

    -- * State Machine
    initialState,
    transition,
    canAcceptRequest,
    canAcceptNotification,
    isTerminal,

    -- * Session State
    SessionState (..),
    newSessionState,
    getProtocolState,
    setProtocolState,
    transitionSession,

    -- * State Queries
    stateAllowsMethod,
    stateDescription,
  )
where

import Control.Concurrent.STM (TVar, atomically, newTVarIO, readTVar, writeTVar)
import Data.Aeson (FromJSON (..), ToJSON, toJSON)
import Data.Text (Text)
import GHC.Generics (Generic)

-- | MCP Protocol lifecycle states
data ProtocolState
  = -- | Initial state before initialize request
    Uninitialized
  | -- | After initialize request, waiting for initialized notification
    Initializing
  | -- | Normal operating state
    Ready
  | -- | Graceful shutdown in progress
    ShuttingDown
  | -- | Terminal state, connection should close
    Terminated
  deriving (Eq, Show, Generic, Ord)

instance ToJSON ProtocolState where
  toJSON Uninitialized = "uninitialized"
  toJSON Initializing = "initializing"
  toJSON Ready = "ready"
  toJSON ShuttingDown = "shutting_down"
  toJSON Terminated = "terminated"

instance FromJSON ProtocolState where
  parseJSON v = case v of
    "uninitialized" -> pure Uninitialized
    "initializing" -> pure Initializing
    "ready" -> pure Ready
    "shutting_down" -> pure ShuttingDown
    "terminated" -> pure Terminated
    other -> fail $ "Unknown protocol state: " <> show other

-- | Events that trigger state transitions
data ProtocolEvent
  = -- | initialize request received
    InitializeReceived
  | -- | initialized notification received
    InitializedReceived
  | -- | shutdown request received (MCP doesn't have explicit shutdown, but we support graceful close)
    ShutdownReceived
  | -- | Connection closed or fatal error
    ConnectionClosed
  | -- | Fatal protocol error
    ProtocolError
  deriving (Eq, Show, Generic)

-- | State transition errors
data StateTransitionError
  = InvalidTransition ProtocolState ProtocolEvent
  | AlreadyInitialized
  | NotInitialized
  | AlreadyShuttingDown
  deriving (Eq, Show, Generic)

-- | Initial protocol state
initialState :: ProtocolState
initialState = Uninitialized

-- | State transition function
transition :: ProtocolState -> ProtocolEvent -> Either StateTransitionError ProtocolState
transition currentState event = case (currentState, event) of
  -- From Uninitialized
  (Uninitialized, InitializeReceived) -> Right Initializing
  (Uninitialized, ConnectionClosed) -> Right Terminated
  (Uninitialized, ProtocolError) -> Right Terminated
  (Uninitialized, _) -> Left NotInitialized
  -- From Initializing
  (Initializing, InitializedReceived) -> Right Ready
  (Initializing, ConnectionClosed) -> Right Terminated
  (Initializing, ProtocolError) -> Right Terminated
  (Initializing, InitializeReceived) -> Left AlreadyInitialized
  (Initializing, _) -> Left (InvalidTransition currentState event)
  -- From Ready
  (Ready, ShutdownReceived) -> Right ShuttingDown
  (Ready, ConnectionClosed) -> Right Terminated
  (Ready, ProtocolError) -> Right Terminated
  (Ready, InitializeReceived) -> Left AlreadyInitialized
  (Ready, _) -> Left (InvalidTransition currentState event)
  -- From ShuttingDown
  (ShuttingDown, ConnectionClosed) -> Right Terminated
  (ShuttingDown, ProtocolError) -> Right Terminated
  (ShuttingDown, _) -> Left AlreadyShuttingDown
  -- From Terminated (terminal state)
  (Terminated, _) -> Left (InvalidTransition currentState event)

-- | Check if state allows accepting requests
canAcceptRequest :: ProtocolState -> Bool
canAcceptRequest = \case
  Uninitialized -> True -- Only initialize allowed
  Initializing -> False -- Waiting for initialized notification
  Ready -> True -- Normal operation
  ShuttingDown -> False -- Rejecting new requests
  Terminated -> False -- Dead

-- | Check if state allows accepting notifications
canAcceptNotification :: ProtocolState -> Bool
canAcceptNotification = \case
  Uninitialized -> False
  Initializing -> True -- initialized notification expected
  Ready -> True -- Normal notifications
  ShuttingDown -> True -- Allow notifications during shutdown
  Terminated -> False

-- | Check if state is terminal
isTerminal :: ProtocolState -> Bool
isTerminal Terminated = True
isTerminal _ = False

-- | Methods allowed in each state
stateAllowsMethod :: ProtocolState -> Text -> Bool
stateAllowsMethod state method = case state of
  Uninitialized ->
    method == "initialize"
  Initializing ->
    -- Only initialized notification is valid
    False
  Ready ->
    -- All methods except initialize
    method /= "initialize"
  ShuttingDown ->
    -- Only notifications
    False
  Terminated ->
    False

-- | Human-readable state description
stateDescription :: ProtocolState -> Text
stateDescription = \case
  Uninitialized -> "Waiting for initialize request"
  Initializing -> "Processing initialization, waiting for initialized notification"
  Ready -> "Ready to handle requests"
  ShuttingDown -> "Shutting down, not accepting new requests"
  Terminated -> "Connection terminated"

-- | Mutable session state wrapper
data SessionState = SessionState
  { ssProtocolState :: TVar ProtocolState,
    ssSessionId :: Text
  }

-- | Create new session state
newSessionState :: Text -> IO SessionState
newSessionState sessionId = do
  stateVar <- newTVarIO Uninitialized
  pure
    SessionState
      { ssProtocolState = stateVar,
        ssSessionId = sessionId
      }

-- | Get current protocol state
getProtocolState :: SessionState -> IO ProtocolState
getProtocolState ss = atomically $ readTVar (ssProtocolState ss)

-- | Set protocol state directly (use with caution)
setProtocolState :: SessionState -> ProtocolState -> IO ()
setProtocolState ss newState = atomically $ writeTVar (ssProtocolState ss) newState

-- | Attempt state transition
transitionSession :: SessionState -> ProtocolEvent -> IO (Either StateTransitionError ProtocolState)
transitionSession ss event = atomically $ do
  currentState <- readTVar (ssProtocolState ss)
  case transition currentState event of
    Left err -> pure (Left err)
    Right newState -> do
      writeTVar (ssProtocolState ss) newState
      pure (Right newState)
