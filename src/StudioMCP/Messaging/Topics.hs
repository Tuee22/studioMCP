{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Messaging.Topics
  ( TopicName (..),
    defaultExecutionTopic,
  )
where

import Data.Text (Text)

newtype TopicName = TopicName
  { unTopicName :: Text
  }
  deriving (Eq, Show)

defaultExecutionTopic :: TopicName
defaultExecutionTopic = TopicName "persistent://public/default/studiomcp-execution"
