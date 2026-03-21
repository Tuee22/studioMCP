{-# LANGUAGE OverloadedStrings #-}

module Messaging.EventsSpec
  ( spec,
  )
where

import Data.Aeson (decode, encode)
import Data.Time (UTCTime (UTCTime), fromGregorian, secondsToDiffTime)
import StudioMCP.DAG.Summary (RunId (..))
import StudioMCP.DAG.Types (NodeId (..))
import StudioMCP.Messaging.Events
  ( ExecutionEvent (..),
    ExecutionEventType (NodeCompleted, RunSubmitted),
  )
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "ExecutionEvent JSON" $ do
    it "round-trips a run-level event" $
      decode (encode runLevelEvent) `shouldBe` Just runLevelEvent

    it "round-trips a node-level event" $
      decode (encode nodeLevelEvent) `shouldBe` Just nodeLevelEvent

runLevelEvent :: ExecutionEvent
runLevelEvent =
  ExecutionEvent
    { eventRunId = RunId "run-1",
      eventNodeId = Nothing,
      eventType = RunSubmitted,
      eventDetail = "submitted",
      eventTimestamp = fixedTime
    }

nodeLevelEvent :: ExecutionEvent
nodeLevelEvent =
  ExecutionEvent
    { eventRunId = RunId "run-2",
      eventNodeId = Just (NodeId "transcode"),
      eventType = NodeCompleted,
      eventDetail = "node completed",
      eventTimestamp = fixedTime
    }

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 3 19) (secondsToDiffTime 0)
