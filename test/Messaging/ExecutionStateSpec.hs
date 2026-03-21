module Messaging.ExecutionStateSpec
  ( spec,
  )
where

import StudioMCP.Messaging.Events (ExecutionEventType (..))
import StudioMCP.Messaging.ExecutionState
  ( ExecutionState (..),
    RunPhase (..),
    StateTransitionError (..),
    advanceState,
    initialExecutionState,
  )
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "advanceState" $ do
    it "allows the submitted-to-running path" $ do
      let submittedState = advanceState initialExecutionState RunSubmitted
      submittedState `shouldBe` Right (ExecutionState Submitted)
      (submittedState >>= (`advanceState` NodeScheduled))
        `shouldBe` Right (ExecutionState Running)

    it "allows a successful terminal transition" $
      advanceState (ExecutionState Running) SummaryEmitted
        `shouldBe` Right (ExecutionState Completed)

    it "allows a failure terminal transition" $
      advanceState (ExecutionState Running) NodeFailedEvent
        `shouldBe` Right (ExecutionState Failed)

    it "rejects forbidden early transitions with the attempted event preserved" $
      advanceState initialExecutionState SummaryEmitted
        `shouldBe` Left (StateTransitionError Pending SummaryEmitted)

    it "rejects further transitions after completion with the attempted event preserved" $
      advanceState (ExecutionState Completed) NodeStarted
        `shouldBe` Left (StateTransitionError Completed NodeStarted)

    it "rejects further transitions after failure with the attempted event preserved" $
      advanceState (ExecutionState Failed) SummaryEmitted
        `shouldBe` Left (StateTransitionError Failed SummaryEmitted)
