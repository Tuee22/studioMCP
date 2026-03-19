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

import Data.Text (Text)
import Data.Time (UTCTime)
import StudioMCP.DAG.Provenance (Provenance)
import StudioMCP.DAG.Types (NodeId)
import StudioMCP.Result.Failure (FailureDetail)

newtype RunId = RunId
  { unRunId :: Text
  }
  deriving (Eq, Ord, Show)

data RunStatus
  = RunSucceeded
  | RunFailed
  deriving (Eq, Show)

data NodeExecutionStatus
  = NodeSucceeded
  | NodeFailed
  | NodeTimedOut
  deriving (Eq, Show)

data NodeOutcome = NodeOutcome
  { outcomeNodeId :: NodeId,
    outcomeStatus :: NodeExecutionStatus,
    outcomeCached :: Bool,
    outcomeOutputReference :: Maybe Text,
    outcomeFailure :: Maybe FailureDetail
  }
  deriving (Eq, Show)

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
