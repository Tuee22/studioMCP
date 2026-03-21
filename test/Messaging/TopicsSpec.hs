{-# LANGUAGE OverloadedStrings #-}

module Messaging.TopicsSpec
  ( spec,
  )
where

import Data.List (nub)
import qualified Data.Text as Text
import StudioMCP.Messaging.Topics
  ( TopicChannel (..),
    TopicName (..),
    allTopics,
    defaultExecutionTopic,
    topicForChannel,
  )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec =
  describe "topic naming" $ do
    it "keeps the default execution topic stable" $
      defaultExecutionTopic
        `shouldBe` TopicName "persistent://public/default/studiomcp-execution"

    it "uses the studiomcp topic namespace for every channel" $
      allTopics `shouldSatisfy` all hasExpectedPrefix

    it "keeps topic names unique across channels" $
      map unTopicName allTopics `shouldSatisfy` hasUniqueNames

    it "builds the expected dead-letter topic" $
      topicForChannel ExecutionDeadLetterTopic
        `shouldBe` TopicName "persistent://public/default/studiomcp-dead-letter"

hasExpectedPrefix :: TopicName -> Bool
hasExpectedPrefix (TopicName topicName) =
  "persistent://public/default/studiomcp-" `Text.isPrefixOf` topicName

hasUniqueNames :: Eq a => [a] -> Bool
hasUniqueNames values = length values == length (nub values)
