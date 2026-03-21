{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Messaging.Topics
  ( TopicName (..),
    TopicChannel (..),
    defaultExecutionTopic,
    topicForChannel,
    allTopics,
  )
where

import Data.Text (Text)

newtype TopicName = TopicName
  { unTopicName :: Text
  }
  deriving (Eq, Show)

data TopicChannel
  = ExecutionEventsTopic
  | ExecutionSummariesTopic
  | ExecutionDeadLetterTopic
  deriving (Eq, Show)

defaultExecutionTopic :: TopicName
defaultExecutionTopic = topicForChannel ExecutionEventsTopic

topicForChannel :: TopicChannel -> TopicName
topicForChannel topicChannel =
  TopicName $
    case topicChannel of
      ExecutionEventsTopic -> "persistent://public/default/studiomcp-execution"
      ExecutionSummariesTopic -> "persistent://public/default/studiomcp-summary"
      ExecutionDeadLetterTopic -> "persistent://public/default/studiomcp-dead-letter"

allTopics :: [TopicName]
allTopics =
  map
    topicForChannel
    [ ExecutionEventsTopic,
      ExecutionSummariesTopic,
      ExecutionDeadLetterTopic
    ]
