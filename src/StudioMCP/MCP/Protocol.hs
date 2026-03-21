{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.MCP.Protocol
  ( SubmissionRequest (..),
    SubmissionResponse (..),
  )
where

import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    object,
    withObject,
    (.:),
    (.=),
  )
import StudioMCP.DAG.Summary (RunId, RunStatus)
import StudioMCP.DAG.Types (DagSpec)
import StudioMCP.Storage.Keys (SummaryRef)

newtype SubmissionRequest = SubmissionRequest
  { submissionDag :: DagSpec
  }
  deriving (Eq, Show)

instance FromJSON SubmissionRequest where
  parseJSON = withObject "SubmissionRequest" $ \obj ->
    SubmissionRequest <$> obj .: "dag"

instance ToJSON SubmissionRequest where
  toJSON submissionRequest =
    object
      [ "dag" .= submissionDag submissionRequest
      ]

data SubmissionResponse = SubmissionResponse
  { submissionRunId :: RunId,
    submissionStatus :: RunStatus,
    submissionSummaryRef :: SummaryRef
  }
  deriving (Eq, Show)

instance ToJSON SubmissionResponse where
  toJSON submissionResponse =
    object
      [ "runId" .= submissionRunId submissionResponse,
        "status" .= submissionStatus submissionResponse,
        "summaryRef" .= submissionSummaryRef submissionResponse
      ]

instance FromJSON SubmissionResponse where
  parseJSON = withObject "SubmissionResponse" $ \obj ->
    SubmissionResponse
      <$> obj .: "runId"
      <*> obj .: "status"
      <*> obj .: "summaryRef"
