{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Storage.Manifests
  ( ArtifactRef (..),
    ManifestEntry (..),
    RunManifest (..),
    buildRunManifest,
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
import StudioMCP.DAG.Summary (RunId)
import StudioMCP.DAG.Types (NodeId)
import StudioMCP.Storage.ContentAddressed (ContentAddress)
import StudioMCP.Storage.Keys
  ( BucketName,
    MemoObjectRef,
    ObjectKey,
    SummaryRef,
  )

data ArtifactRef = ArtifactRef
  { artifactBucket :: BucketName,
    artifactKey :: ObjectKey,
    artifactAddress :: Maybe ContentAddress
  }
  deriving (Eq, Show)

instance FromJSON ArtifactRef where
  parseJSON = withObject "ArtifactRef" $ \obj ->
    ArtifactRef
      <$> obj .: "bucket"
      <*> obj .: "key"
      <*> obj .: "address"

instance ToJSON ArtifactRef where
  toJSON artifactRef =
    object
      [ "bucket" .= artifactBucket artifactRef,
        "key" .= artifactKey artifactRef,
        "address" .= artifactAddress artifactRef
      ]

data ManifestEntry = ManifestEntry
  { manifestEntryNodeId :: NodeId,
    manifestEntryMemoRef :: MemoObjectRef,
    manifestEntryArtifactRef :: Maybe ArtifactRef
  }
  deriving (Eq, Show)

instance FromJSON ManifestEntry where
  parseJSON = withObject "ManifestEntry" $ \obj ->
    ManifestEntry
      <$> obj .: "nodeId"
      <*> obj .: "memoRef"
      <*> obj .: "artifactRef"

instance ToJSON ManifestEntry where
  toJSON manifestEntry =
    object
      [ "nodeId" .= manifestEntryNodeId manifestEntry,
        "memoRef" .= manifestEntryMemoRef manifestEntry,
        "artifactRef" .= manifestEntryArtifactRef manifestEntry
      ]

data RunManifest = RunManifest
  { manifestRunId :: RunId,
    manifestSummaryRef :: SummaryRef,
    manifestEntries :: [ManifestEntry]
  }
  deriving (Eq, Show)

instance FromJSON RunManifest where
  parseJSON = withObject "RunManifest" $ \obj ->
    RunManifest
      <$> obj .: "runId"
      <*> obj .: "summaryRef"
      <*> obj .: "entries"

instance ToJSON RunManifest where
  toJSON runManifest =
    object
      [ "runId" .= manifestRunId runManifest,
        "summaryRef" .= manifestSummaryRef runManifest,
        "entries" .= manifestEntries runManifest
      ]

buildRunManifest :: RunId -> SummaryRef -> [ManifestEntry] -> RunManifest
buildRunManifest runIdValue summaryRefValue entriesValue =
  RunManifest
    { manifestRunId = runIdValue,
      manifestSummaryRef = summaryRefValue,
      manifestEntries = entriesValue
    }
