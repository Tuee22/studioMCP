{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Worker.Protocol
  ( WorkerExecutionRequest (..),
    WorkerExecutionResponse (..),
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
import StudioMCP.DAG.Summary (RunId, RunStatus, Summary)
import StudioMCP.DAG.Types (DagSpec)
import StudioMCP.Storage.Keys (ManifestRef, SummaryRef)

newtype WorkerExecutionRequest = WorkerExecutionRequest
  { workerExecutionDag :: DagSpec
  }
  deriving (Eq, Show)

instance FromJSON WorkerExecutionRequest where
  parseJSON = withObject "WorkerExecutionRequest" $ \obj ->
    WorkerExecutionRequest <$> obj .: "dag"

instance ToJSON WorkerExecutionRequest where
  toJSON workerExecutionRequest =
    object
      [ "dag" .= workerExecutionDag workerExecutionRequest
      ]

data WorkerExecutionResponse = WorkerExecutionResponse
  { workerExecutionRunId :: RunId,
    workerExecutionStatus :: RunStatus,
    workerExecutionSummaryRef :: SummaryRef,
    workerExecutionManifestRef :: ManifestRef,
    workerExecutionSummary :: Summary
  }
  deriving (Eq, Show)

instance ToJSON WorkerExecutionResponse where
  toJSON workerExecutionResponse =
    object
      [ "runId" .= workerExecutionRunId workerExecutionResponse,
        "status" .= workerExecutionStatus workerExecutionResponse,
        "summaryRef" .= workerExecutionSummaryRef workerExecutionResponse,
        "manifestRef" .= workerExecutionManifestRef workerExecutionResponse,
        "summary" .= workerExecutionSummary workerExecutionResponse
      ]

instance FromJSON WorkerExecutionResponse where
  parseJSON = withObject "WorkerExecutionResponse" $ \obj ->
    WorkerExecutionResponse
      <$> obj .: "runId"
      <*> obj .: "status"
      <*> obj .: "summaryRef"
      <*> obj .: "manifestRef"
      <*> obj .: "summary"
