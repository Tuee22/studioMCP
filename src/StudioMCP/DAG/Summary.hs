{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.DAG.Summary
  ( RunId (..),
    RunStatus (..),
    NodeExecutionStatus (..),
    NodeOutcome (..),
    Summary (..),
    buildSummary,
  )
where

import Data.Aeson (FromJSON (parseJSON), ToJSON (toJSON))
import Data.Aeson
  ( Value (String),
    object,
    withObject,
    withText,
    (.:),
    (.:?),
    (.=),
  )
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime)
import StudioMCP.DAG.Provenance (Provenance)
import StudioMCP.DAG.Types (NodeId)
import StudioMCP.Result.Failure (FailureDetail)

newtype RunId = RunId
  { unRunId :: Text
  }
  deriving (Eq, Ord, Show)

instance FromJSON RunId where
  parseJSON value = RunId <$> parseJSON value

instance ToJSON RunId where
  toJSON (RunId value) = toJSON value

data RunStatus
  = RunRunning
  | RunSucceeded
  | RunFailed
  deriving (Eq, Show)

instance FromJSON RunStatus where
  parseJSON =
    withText "RunStatus" $ \value ->
      case value of
        "running" -> pure RunRunning
        "succeeded" -> pure RunSucceeded
        "failed" -> pure RunFailed
        _ -> fail ("Unknown RunStatus: " <> Text.unpack value)

instance ToJSON RunStatus where
  toJSON runStatus =
    String $
      case runStatus of
        RunRunning -> "running"
        RunSucceeded -> "succeeded"
        RunFailed -> "failed"

data NodeExecutionStatus
  = NodeSucceeded
  | NodeFailed
  | NodeTimedOut
  deriving (Eq, Show)

instance FromJSON NodeExecutionStatus where
  parseJSON =
    withText "NodeExecutionStatus" $ \value ->
      case value of
        "succeeded" -> pure NodeSucceeded
        "failed" -> pure NodeFailed
        "timed_out" -> pure NodeTimedOut
        _ -> fail ("Unknown NodeExecutionStatus: " <> Text.unpack value)

instance ToJSON NodeExecutionStatus where
  toJSON nodeExecutionStatus =
    String $
      case nodeExecutionStatus of
        NodeSucceeded -> "succeeded"
        NodeFailed -> "failed"
        NodeTimedOut -> "timed_out"

data NodeOutcome = NodeOutcome
  { outcomeNodeId :: NodeId,
    outcomeStatus :: NodeExecutionStatus,
    outcomeCached :: Bool,
    outcomeOutputReference :: Maybe Text,
    outcomeFailure :: Maybe FailureDetail
  }
  deriving (Eq, Show)

instance FromJSON NodeOutcome where
  parseJSON = withObject "NodeOutcome" $ \obj ->
    NodeOutcome
      <$> obj .: "nodeId"
      <*> obj .: "status"
      <*> obj .: "cached"
      <*> obj .:? "outputReference"
      <*> obj .:? "failure"

instance ToJSON NodeOutcome where
  toJSON nodeOutcome =
    object
      [ "nodeId" .= outcomeNodeId nodeOutcome,
        "status" .= outcomeStatus nodeOutcome,
        "cached" .= outcomeCached nodeOutcome,
        "outputReference" .= outcomeOutputReference nodeOutcome,
        "failure" .= outcomeFailure nodeOutcome
      ]

data Summary = Summary
  { summaryRunId :: RunId,
    summaryStatus :: RunStatus,
    summaryNodeLineage :: [NodeId],
    summaryNodeOutcomes :: [NodeOutcome],
    summaryOutputReferences :: [Text],
    summaryFailures :: [FailureDetail],
    summaryStartedAt :: UTCTime,
    summaryFinishedAt :: Maybe UTCTime,
    summaryProvenance :: Provenance
  }
  deriving (Eq, Show)

instance FromJSON Summary where
  parseJSON = withObject "Summary" $ \obj ->
    Summary
      <$> obj .: "runId"
      <*> obj .: "status"
      <*> obj .: "nodeLineage"
      <*> obj .: "nodeOutcomes"
      <*> obj .: "outputReferences"
      <*> obj .: "failures"
      <*> obj .: "startedAt"
      <*> obj .:? "finishedAt"
      <*> obj .: "provenance"

instance ToJSON Summary where
  toJSON summary =
    object
      [ "runId" .= summaryRunId summary,
        "status" .= summaryStatus summary,
        "nodeLineage" .= summaryNodeLineage summary,
        "nodeOutcomes" .= summaryNodeOutcomes summary,
        "outputReferences" .= summaryOutputReferences summary,
        "failures" .= summaryFailures summary,
        "startedAt" .= summaryStartedAt summary,
        "finishedAt" .= summaryFinishedAt summary,
        "provenance" .= summaryProvenance summary
      ]

buildSummary :: RunId -> UTCTime -> Provenance -> [NodeOutcome] -> Summary
buildSummary runId startedAt provenance outcomes =
  Summary
    { summaryRunId = runId,
      summaryStatus =
        if null failures then RunSucceeded else RunFailed,
      summaryNodeLineage = map outcomeNodeId outcomes,
      summaryNodeOutcomes = outcomes,
      summaryOutputReferences = foldMap maybeToList (map outcomeOutputReference outcomes),
      summaryFailures = failures,
      summaryStartedAt = startedAt,
      summaryFinishedAt = Nothing,
      summaryProvenance = provenance
    }
  where
    failures = foldMap maybeToList (map outcomeFailure outcomes)

maybeToList :: Maybe a -> [a]
maybeToList maybeValue =
  case maybeValue of
    Nothing -> []
    Just value -> [value]
