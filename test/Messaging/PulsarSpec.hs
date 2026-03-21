{-# LANGUAGE OverloadedStrings #-}

module Messaging.PulsarSpec
  ( spec,
  )
where

import Data.Text (Text)
import StudioMCP.Messaging.Pulsar
  ( classifyPulsarFailure,
    extractConsumedPayloads,
  )
import StudioMCP.Messaging.Topics (TopicName (..))
import StudioMCP.Result.Failure
  ( failureCode,
    failureRetryable,
  )
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "Pulsar helpers" $ do
    it "extracts consumed payload lines from pulsar-client output" $
      extractConsumedPayloads sampleConsumeOutput
        `shouldBe` Right ["{\"runId\":\"run-1\"}", "{\"runId\":\"run-2\"}"]

    it "maps namespace lookup failures to a stable messaging failure" $ do
      let failureDetail =
            classifyPulsarFailure
              "publish"
              (TopicName "persistent://public/missing-namespace/studiomcp-test")
              (Just 255)
              "ERROR org.apache.pulsar.client.cli.PulsarClientTool - Namespace not found"
      failureCode failureDetail `shouldBe` "pulsar-namespace-not-found"
      failureRetryable failureDetail `shouldBe` False

sampleConsumeOutput :: Text
sampleConsumeOutput =
  "----- got message -----\n\
  \key:[null], properties:[], content:{\"runId\":\"run-1\"}\n\
  \----- got message -----\n\
  \key:[null], properties:[], content:{\"runId\":\"run-2\"}\n"
