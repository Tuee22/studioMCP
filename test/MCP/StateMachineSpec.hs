{-# LANGUAGE OverloadedStrings #-}

module MCP.StateMachineSpec
  ( spec,
  )
where

import StudioMCP.MCP.Protocol.StateMachine
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = do
  describe "Protocol State Machine" $ do
    describe "Initial State" $ do
      it "starts in Uninitialized state" $ do
        initialState `shouldBe` Uninitialized

      it "is not a terminal state" $ do
        isTerminal initialState `shouldBe` False

    describe "State Transitions from Uninitialized" $ do
      it "transitions to Initializing on InitializeReceived" $ do
        transition Uninitialized InitializeReceived `shouldBe` Right Initializing

      it "transitions to Terminated on ConnectionClosed" $ do
        transition Uninitialized ConnectionClosed `shouldBe` Right Terminated

      it "transitions to Terminated on ProtocolError" $ do
        transition Uninitialized ProtocolError `shouldBe` Right Terminated

      it "rejects other events with NotInitialized error" $ do
        transition Uninitialized InitializedReceived `shouldBe` Left NotInitialized
        transition Uninitialized ShutdownReceived `shouldBe` Left NotInitialized

    describe "State Transitions from Initializing" $ do
      it "transitions to Ready on InitializedReceived" $ do
        transition Initializing InitializedReceived `shouldBe` Right Ready

      it "transitions to Terminated on ConnectionClosed" $ do
        transition Initializing ConnectionClosed `shouldBe` Right Terminated

      it "transitions to Terminated on ProtocolError" $ do
        transition Initializing ProtocolError `shouldBe` Right Terminated

      it "rejects duplicate InitializeReceived" $ do
        transition Initializing InitializeReceived `shouldBe` Left AlreadyInitialized

    describe "State Transitions from Ready" $ do
      it "transitions to ShuttingDown on ShutdownReceived" $ do
        transition Ready ShutdownReceived `shouldBe` Right ShuttingDown

      it "transitions to Terminated on ConnectionClosed" $ do
        transition Ready ConnectionClosed `shouldBe` Right Terminated

      it "transitions to Terminated on ProtocolError" $ do
        transition Ready ProtocolError `shouldBe` Right Terminated

      it "rejects InitializeReceived in Ready state" $ do
        transition Ready InitializeReceived `shouldBe` Left AlreadyInitialized

    describe "State Transitions from ShuttingDown" $ do
      it "transitions to Terminated on ConnectionClosed" $ do
        transition ShuttingDown ConnectionClosed `shouldBe` Right Terminated

      it "transitions to Terminated on ProtocolError" $ do
        transition ShuttingDown ProtocolError `shouldBe` Right Terminated

      it "rejects other events with AlreadyShuttingDown" $ do
        transition ShuttingDown InitializeReceived `shouldBe` Left AlreadyShuttingDown
        transition ShuttingDown ShutdownReceived `shouldBe` Left AlreadyShuttingDown

    describe "Terminal State" $ do
      it "Terminated is a terminal state" $ do
        isTerminal Terminated `shouldBe` True

      it "rejects all events in Terminated state" $ do
        transition Terminated InitializeReceived
          `shouldSatisfy` isInvalidTransition
        transition Terminated ConnectionClosed
          `shouldSatisfy` isInvalidTransition

  describe "Request Acceptance" $ do
    it "accepts requests in Uninitialized (initialize only)" $ do
      canAcceptRequest Uninitialized `shouldBe` True

    it "rejects requests in Initializing" $ do
      canAcceptRequest Initializing `shouldBe` False

    it "accepts requests in Ready" $ do
      canAcceptRequest Ready `shouldBe` True

    it "rejects requests in ShuttingDown" $ do
      canAcceptRequest ShuttingDown `shouldBe` False

    it "rejects requests in Terminated" $ do
      canAcceptRequest Terminated `shouldBe` False

  describe "Notification Acceptance" $ do
    it "rejects notifications in Uninitialized" $ do
      canAcceptNotification Uninitialized `shouldBe` False

    it "accepts notifications in Initializing (initialized expected)" $ do
      canAcceptNotification Initializing `shouldBe` True

    it "accepts notifications in Ready" $ do
      canAcceptNotification Ready `shouldBe` True

    it "accepts notifications in ShuttingDown" $ do
      canAcceptNotification ShuttingDown `shouldBe` True

    it "rejects notifications in Terminated" $ do
      canAcceptNotification Terminated `shouldBe` False

  describe "Method Allowance" $ do
    it "only allows initialize in Uninitialized" $ do
      stateAllowsMethod Uninitialized "initialize" `shouldBe` True
      stateAllowsMethod Uninitialized "tools/list" `shouldBe` False

    it "allows all methods except initialize in Ready" $ do
      stateAllowsMethod Ready "tools/list" `shouldBe` True
      stateAllowsMethod Ready "resources/read" `shouldBe` True
      stateAllowsMethod Ready "initialize" `shouldBe` False

    it "allows no methods in Initializing" $ do
      stateAllowsMethod Initializing "initialize" `shouldBe` False
      stateAllowsMethod Initializing "tools/list" `shouldBe` False

    it "allows no methods in ShuttingDown" $ do
      stateAllowsMethod ShuttingDown "tools/list" `shouldBe` False

    it "allows no methods in Terminated" $ do
      stateAllowsMethod Terminated "tools/list" `shouldBe` False

  describe "State Descriptions" $ do
    it "provides meaningful descriptions" $ do
      stateDescription Uninitialized `shouldBe` "Waiting for initialize request"
      stateDescription Initializing `shouldBe` "Processing initialization, waiting for initialized notification"
      stateDescription Ready `shouldBe` "Ready to handle requests"
      stateDescription ShuttingDown `shouldBe` "Shutting down, not accepting new requests"
      stateDescription Terminated `shouldBe` "Connection terminated"

  describe "Session State" $ do
    it "creates new session state in Uninitialized" $ do
      ss <- newSessionState "test-session-1"
      state <- getProtocolState ss
      state `shouldBe` Uninitialized

    it "transitions session state correctly" $ do
      ss <- newSessionState "test-session-2"

      -- Initialize
      result1 <- transitionSession ss InitializeReceived
      result1 `shouldBe` Right Initializing

      -- Initialized
      result2 <- transitionSession ss InitializedReceived
      result2 `shouldBe` Right Ready

      -- Verify final state
      finalState <- getProtocolState ss
      finalState `shouldBe` Ready

    it "rejects invalid transitions" $ do
      ss <- newSessionState "test-session-3"

      -- Try to send InitializedReceived before InitializeReceived
      result <- transitionSession ss InitializedReceived
      result `shouldBe` Left NotInitialized

-- Helper to check for InvalidTransition error
isInvalidTransition :: Either StateTransitionError ProtocolState -> Bool
isInvalidTransition (Left (InvalidTransition _ _)) = True
isInvalidTransition _ = False
