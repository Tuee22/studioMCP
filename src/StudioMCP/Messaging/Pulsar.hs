{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Messaging.Pulsar
  ( PulsarConfig (..),
    classifyPulsarFailure,
    consumeExecutionEvents,
    extractConsumedPayloads,
    publishExecutionEvents,
    validatePulsarLifecycle,
    validationTopicForRunId,
  )
where

import Control.Exception (IOException, try)
import Data.Aeson (eitherDecodeStrict', encode)
import qualified Data.ByteString.Lazy as LBS
import Data.Char (isAlphaNum)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import Data.Time (UTCTime, addUTCTime, getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import StudioMCP.DAG.Summary (RunId (..))
import StudioMCP.DAG.Types (NodeId (..))
import StudioMCP.Messaging.Events
  ( ExecutionEvent (..),
    ExecutionEventType (..),
  )
import StudioMCP.Messaging.Topics (TopicName (..))
import StudioMCP.Result.Failure
  ( FailureCategory (MessagingFailure),
    FailureDetail (..),
  )
import System.Exit (ExitCode (..))
import System.Process (readProcessWithExitCode)

data PulsarConfig = PulsarConfig
  { pulsarHttpEndpoint :: Text,
    pulsarBinaryEndpoint :: Text
  }
  deriving (Eq, Show)

publishExecutionEvents :: PulsarConfig -> TopicName -> [ExecutionEvent] -> IO (Either FailureDetail ())
publishExecutionEvents config topicName events = do
  let args =
        [ "produce",
          "-s",
          "~"
        ]
          <> concatMap (\eventValue -> ["-m", Text.unpack (encodeExecutionEvent eventValue)]) events
          <> [Text.unpack (unTopicName topicName)]
  result <- runPulsarClientCommand config "publish" topicName args
  case result of
    Left failureDetail -> pure (Left failureDetail)
    Right _ -> pure (Right ())

consumeExecutionEvents :: PulsarConfig -> TopicName -> Text -> Int -> IO (Either FailureDetail [ExecutionEvent])
consumeExecutionEvents config topicName subscriptionName messageCount = do
  let args =
        [ "consume",
          "-s",
          Text.unpack subscriptionName,
          "-n",
          show messageCount,
          "-p",
          "Earliest",
          Text.unpack (unTopicName topicName)
        ]
  result <- runPulsarClientCommand config "consume" topicName args
  case result of
    Left failureDetail -> pure (Left failureDetail)
    Right commandOutput -> pure (decodeConsumedEvents topicName messageCount commandOutput)

validatePulsarLifecycle :: PulsarConfig -> IO (Either FailureDetail ())
validatePulsarLifecycle config = do
  currentTime <- getCurrentTime
  let runToken = Text.pack (formatTime defaultTimeLocale "%Y%m%d%H%M%S%q" currentTime)
      runId = RunId ("pulsar-validation-" <> runToken)
      topicName = validationTopicForRunId runId
      invalidTopicName = invalidValidationTopicForRunId runId
      subscriptionName = "studiomcp-validation-sub-" <> runToken
      invalidSubscriptionName = "studiomcp-validation-bad-sub-" <> runToken
      lifecycleEvents = validationLifecycleEvents runId currentTime
  publishResult <- publishExecutionEvents config topicName lifecycleEvents
  case publishResult of
    Left failureDetail -> pure (Left failureDetail)
    Right () -> do
      consumeResult <- consumeExecutionEvents config topicName subscriptionName (length lifecycleEvents)
      case consumeResult of
        Left failureDetail -> pure (Left failureDetail)
        Right observedEvents
          | observedEvents /= lifecycleEvents ->
              pure
                ( Left
                    FailureDetail
                      { failureCategory = MessagingFailure,
                        failureCode = "pulsar-event-order-mismatch",
                        failureMessage = "Pulsar returned execution events out of order or with altered payloads.",
                        failureRetryable = False,
                        failureContext =
                          Map.fromList
                            [ ("topic", unTopicName topicName),
                              ("expectedCount", Text.pack (show (length lifecycleEvents))),
                              ("observedCount", Text.pack (show (length observedEvents)))
                            ]
                      }
                )
          | otherwise -> do
              case lifecycleEvents of
                [] ->
                  pure
                    ( Left
                        FailureDetail
                          { failureCategory = MessagingFailure,
                            failureCode = "pulsar-validation-misconfigured",
                            failureMessage = "The Pulsar validation lifecycle was unexpectedly empty.",
                            failureRetryable = False,
                            failureContext = Map.empty
                          }
                    )
                firstEvent : _ -> do
                  invalidPublishResult <- publishExecutionEvents config invalidTopicName [firstEvent]
                  invalidConsumeResult <- consumeExecutionEvents config invalidTopicName invalidSubscriptionName 1
                  pure (validateUnavailableNamespaceFailure invalidTopicName invalidPublishResult invalidConsumeResult)

validationTopicForRunId :: RunId -> TopicName
validationTopicForRunId (RunId runIdText) =
  TopicName ("persistent://public/default/studiomcp-validation-" <> sanitizeTopicSuffix runIdText)

extractConsumedPayloads :: Text -> Either FailureDetail [Text]
extractConsumedPayloads commandOutput =
  if null payloads
    then
      Left
        FailureDetail
          { failureCategory = MessagingFailure,
            failureCode = "pulsar-consume-output-parse-failed",
            failureMessage = "Pulsar consume output did not contain any message payloads.",
            failureRetryable = False,
            failureContext = Map.fromList [("outputSnippet", summarizeOutput commandOutput)]
          }
    else Right payloads
  where
    payloads =
      foldr collectPayload [] (Text.lines commandOutput)
    collectPayload lineValue acc =
      case Text.breakOn "content:" lineValue of
        (_, suffix)
          | Text.null suffix -> acc
          | otherwise ->
              Text.dropWhile (== ' ') (Text.drop (Text.length "content:") suffix) : acc

classifyPulsarFailure :: Text -> TopicName -> Maybe Int -> Text -> FailureDetail
classifyPulsarFailure operationName topicName maybeExitCode commandOutput =
  FailureDetail
    { failureCategory = MessagingFailure,
      failureCode = failureCodeValue,
      failureMessage = failureMessageValue,
      failureRetryable = failureRetryableValue,
      failureContext =
        Map.fromList
          ( [ ("operation", operationName),
              ("topic", unTopicName topicName),
              ("outputSnippet", summarizeOutput commandOutput)
            ]
              <> maybe [] (\exitCodeValue -> [("exitCode", Text.pack (show exitCodeValue))]) maybeExitCode
          )
    }
  where
    loweredOutput = Text.toLower commandOutput
    (failureCodeValue, failureMessageValue, failureRetryableValue)
      | "namespace not found" `Text.isInfixOf` loweredOutput =
          ( "pulsar-namespace-not-found",
            "Pulsar rejected the topic because its namespace does not exist.",
            False
          )
      | "topicdoesnotexistexception" `Text.isInfixOf` loweredOutput =
          ( "pulsar-topic-not-found",
            "Pulsar rejected the topic because the requested path does not exist.",
            False
          )
      | "connection refused" `Text.isInfixOf` loweredOutput
          || "timed out" `Text.isInfixOf` loweredOutput
          || "unable to upgrade connection" `Text.isInfixOf` loweredOutput =
          ( "pulsar-broker-unavailable",
            "Pulsar was not reachable through the current broker path.",
            True
          )
      | "deployments.apps" `Text.isInfixOf` loweredOutput && "not found" `Text.isInfixOf` loweredOutput =
          ( "pulsar-sidecar-unavailable",
            "The Pulsar deployment is not present in the cluster.",
            True
          )
      | "error while" `Text.isInfixOf` loweredOutput =
          ("pulsar-command-failed", "The Pulsar client command failed.", True)
      | otherwise =
          ( "pulsar-command-failed",
            "The Pulsar client command failed with an unexpected error.",
            True
          )

runPulsarClientCommand :: PulsarConfig -> Text -> TopicName -> [String] -> IO (Either FailureDetail Text)
runPulsarClientCommand config operationName topicName pulsarArgs = do
  targetResult <- resolvePulsarClientTarget operationName topicName
  case targetResult of
    Left failureDetail -> pure (Left failureDetail)
    Right kubectlTarget -> do
      commandResult <-
        try
          ( readProcessWithExitCode
              "kubectl"
              ( ["exec", kubectlTarget, "--", "bin/pulsar-client", "--url", Text.unpack (pulsarBinaryEndpoint config)]
                  <> pulsarArgs
              )
              ""
          ) :: IO (Either IOException (ExitCode, String, String))
      case commandResult of
        Left ioException ->
          pure (Left (classifyPulsarFailure operationName topicName Nothing (Text.pack (show ioException))))
        Right (exitCodeValue, stdoutText, stderrText) ->
          let combinedOutput = Text.pack (stdoutText <> stderrText)
           in case exitCodeValue of
                ExitSuccess -> pure (Right combinedOutput)
                ExitFailure codeValue ->
                  pure (Left (classifyPulsarFailure operationName topicName (Just codeValue) combinedOutput))

resolvePulsarClientTarget :: Text -> TopicName -> IO (Either FailureDetail String)
resolvePulsarClientTarget operationName topicName = do
  commandResult <-
    try
      ( readProcessWithExitCode
          "kubectl"
          [ "get",
            "pods",
            "-l",
            "app=pulsar,component=toolset",
            "-o",
            "jsonpath={range .items[*]}{.metadata.name}:{.status.phase}{\"\\n\"}{end}"
          ]
          ""
      ) :: IO (Either IOException (ExitCode, String, String))
  case commandResult of
    Left ioException ->
      pure (Left (classifyPulsarFailure operationName topicName Nothing (Text.pack (show ioException))))
    Right (exitCodeValue, stdoutText, stderrText) ->
      let combinedOutput = Text.pack (stdoutText <> stderrText)
          runningPods =
            [ podName
            | line <- lines stdoutText
            , let (podName, podStatusWithColon) = break (== ':') line
            , not (null podName)
            , drop 1 podStatusWithColon == "Running"
            ]
       in case exitCodeValue of
            ExitSuccess ->
              case runningPods of
                podName : _ -> pure (Right ("pod/" <> podName))
                [] ->
                  pure
                    ( Left
                        ( classifyPulsarFailure
                            operationName
                            topicName
                            Nothing
                            "No running Pulsar toolset pod is available for pulsar-client commands."
                        )
                    )
            ExitFailure codeValue ->
              pure (Left (classifyPulsarFailure operationName topicName (Just codeValue) combinedOutput))

decodeConsumedEvents :: TopicName -> Int -> Text -> Either FailureDetail [ExecutionEvent]
decodeConsumedEvents topicName expectedCount commandOutput = do
  payloads <- extractConsumedPayloads commandOutput
  if length payloads /= expectedCount
    then
      Left
        FailureDetail
          { failureCategory = MessagingFailure,
            failureCode = "pulsar-consume-count-mismatch",
            failureMessage = "Pulsar returned an unexpected number of execution events.",
            failureRetryable = False,
            failureContext =
              Map.fromList
                [ ("topic", unTopicName topicName),
                  ("expectedCount", Text.pack (show expectedCount)),
                  ("observedCount", Text.pack (show (length payloads)))
                ]
          }
    else traverse decodeExecutionEvent payloads
  where
    decodeExecutionEvent payloadText =
      case eitherDecodeStrict' (Text.encodeUtf8 payloadText) of
        Left decodeFailure ->
          Left
            FailureDetail
              { failureCategory = MessagingFailure,
                failureCode = "pulsar-event-decode-failed",
                failureMessage = "Pulsar returned a message payload that was not a valid execution event.",
                failureRetryable = False,
                failureContext =
                  Map.fromList
                    [ ("topic", unTopicName topicName),
                      ("payloadSnippet", Text.take 160 payloadText),
                      ("decodeError", Text.pack decodeFailure)
                    ]
              }
        Right executionEvent -> Right executionEvent

validateUnavailableNamespaceFailure ::
  TopicName ->
  Either FailureDetail () ->
  Either FailureDetail [ExecutionEvent] ->
  Either FailureDetail ()
validateUnavailableNamespaceFailure invalidTopicName invalidPublishResult invalidConsumeResult =
  case (invalidPublishResult, invalidConsumeResult) of
    (Left publishFailure, Left consumeFailure)
      | failureCode publishFailure == "pulsar-namespace-not-found"
          && failureCode consumeFailure == "pulsar-namespace-not-found" ->
          Right ()
      | otherwise ->
          Left
            FailureDetail
              { failureCategory = MessagingFailure,
                failureCode = "pulsar-failure-mapping-mismatch",
                failureMessage = "Pulsar invalid-namespace checks did not map to the expected failure contract.",
                failureRetryable = False,
                failureContext =
                  Map.fromList
                    [ ("topic", unTopicName invalidTopicName),
                      ("publishFailureCode", failureCode publishFailure),
                      ("consumeFailureCode", failureCode consumeFailure)
                    ]
              }
    (Right (), _) ->
      Left
        FailureDetail
          { failureCategory = MessagingFailure,
            failureCode = "pulsar-invalid-namespace-unexpected-success",
            failureMessage = "Publishing to an invalid Pulsar namespace unexpectedly succeeded.",
            failureRetryable = False,
            failureContext = Map.fromList [("topic", unTopicName invalidTopicName)]
          }
    (_, Right _) ->
      Left
        FailureDetail
          { failureCategory = MessagingFailure,
            failureCode = "pulsar-invalid-namespace-consume-unexpected-success",
            failureMessage = "Consuming from an invalid Pulsar namespace unexpectedly succeeded.",
            failureRetryable = False,
            failureContext = Map.fromList [("topic", unTopicName invalidTopicName)]
          }

validationLifecycleEvents :: RunId -> UTCTime -> [ExecutionEvent]
validationLifecycleEvents runIdValue startTime =
  [ ExecutionEvent
      { eventRunId = runIdValue,
        eventNodeId = Nothing,
        eventType = RunSubmitted,
        eventDetail = "submitted",
        eventTimestamp = startTime
      },
    ExecutionEvent
      { eventRunId = runIdValue,
        eventNodeId = Just (NodeId "validation-node"),
        eventType = NodeStarted,
        eventDetail = "node-started",
        eventTimestamp = addUTCTime 1 startTime
      },
    ExecutionEvent
      { eventRunId = runIdValue,
        eventNodeId = Nothing,
        eventType = SummaryEmitted,
        eventDetail = "summary-emitted",
        eventTimestamp = addUTCTime 2 startTime
      }
  ]

invalidValidationTopicForRunId :: RunId -> TopicName
invalidValidationTopicForRunId (RunId runIdText) =
  TopicName ("persistent://public/missing-namespace/studiomcp-validation-" <> sanitizeTopicSuffix runIdText)

encodeExecutionEvent :: ExecutionEvent -> Text
encodeExecutionEvent = Text.decodeUtf8 . LBS.toStrict . encode

sanitizeTopicSuffix :: Text -> Text
sanitizeTopicSuffix =
  Text.map
    ( \charValue ->
        if isAlphaNum charValue || charValue == '-'
          then charValue
          else '-'
    )

summarizeOutput :: Text -> Text
summarizeOutput commandOutput =
  case filter (not . Text.null) (map Text.strip (Text.lines commandOutput)) of
    [] -> "no command output"
    lineValue : _ -> Text.take 200 lineValue
