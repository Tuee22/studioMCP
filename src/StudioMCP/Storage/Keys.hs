{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Storage.Keys
  ( BucketName (..),
    ObjectKey (..),
    MemoObjectRef (..),
    SummaryRef (..),
    ManifestRef (..),
    memoBucket,
    artifactsBucket,
    summariesBucket,
    memoObjectRef,
    summaryRefForRun,
    manifestRefForRun,
  )
where

import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    Value (String),
    object,
    withObject,
    (.:),
    (.=),
    withText,
  )
import Data.Text (Text)
import StudioMCP.DAG.Hashing (normalizeSegment)
import StudioMCP.DAG.Summary (RunId (..))
import StudioMCP.Storage.ContentAddressed (ContentAddress (..))

newtype BucketName = BucketName
  { unBucketName :: Text
  }
  deriving (Eq, Ord, Show)

instance FromJSON BucketName where
  parseJSON = withText "BucketName" (pure . BucketName)

instance ToJSON BucketName where
  toJSON (BucketName value) = String value

newtype ObjectKey = ObjectKey
  { unObjectKey :: Text
  }
  deriving (Eq, Ord, Show)

instance FromJSON ObjectKey where
  parseJSON = withText "ObjectKey" (pure . ObjectKey)

instance ToJSON ObjectKey where
  toJSON (ObjectKey value) = String value

data MemoObjectRef = MemoObjectRef
  { memoRefBucket :: BucketName,
    memoRefKey :: ObjectKey,
    memoRefAddress :: ContentAddress
  }
  deriving (Eq, Show)

instance FromJSON MemoObjectRef where
  parseJSON = withObject "MemoObjectRef" $ \obj ->
    MemoObjectRef
      <$> obj .: "bucket"
      <*> obj .: "key"
      <*> obj .: "address"

instance ToJSON MemoObjectRef where
  toJSON memoRef =
    object
      [ "bucket" .= memoRefBucket memoRef,
        "key" .= memoRefKey memoRef,
        "address" .= memoRefAddress memoRef
      ]

data SummaryRef = SummaryRef
  { summaryRefBucket :: BucketName,
    summaryRefKey :: ObjectKey,
    summaryRefRunId :: RunId
  }
  deriving (Eq, Show)

instance FromJSON SummaryRef where
  parseJSON = withObject "SummaryRef" $ \obj ->
    SummaryRef
      <$> obj .: "bucket"
      <*> obj .: "key"
      <*> obj .: "runId"

instance ToJSON SummaryRef where
  toJSON summaryRef =
    object
      [ "bucket" .= summaryRefBucket summaryRef,
        "key" .= summaryRefKey summaryRef,
        "runId" .= summaryRefRunId summaryRef
      ]

data ManifestRef = ManifestRef
  { manifestRefBucket :: BucketName,
    manifestRefKey :: ObjectKey,
    manifestRefRunId :: RunId
  }
  deriving (Eq, Show)

instance FromJSON ManifestRef where
  parseJSON = withObject "ManifestRef" $ \obj ->
    ManifestRef
      <$> obj .: "bucket"
      <*> obj .: "key"
      <*> obj .: "runId"

instance ToJSON ManifestRef where
  toJSON manifestRef =
    object
      [ "bucket" .= manifestRefBucket manifestRef,
        "key" .= manifestRefKey manifestRef,
        "runId" .= manifestRefRunId manifestRef
      ]

memoBucket :: BucketName
memoBucket = BucketName "studiomcp-memo"

artifactsBucket :: BucketName
artifactsBucket = BucketName "studiomcp-artifacts"

summariesBucket :: BucketName
summariesBucket = BucketName "studiomcp-summaries"

memoObjectRef :: ContentAddress -> MemoObjectRef
memoObjectRef contentAddress =
  MemoObjectRef
    { memoRefBucket = memoBucket,
      memoRefKey = ObjectKey ("memo/" <> unContentAddress contentAddress),
      memoRefAddress = contentAddress
    }

summaryRefForRun :: RunId -> SummaryRef
summaryRefForRun runIdValue@(RunId runIdText) =
  SummaryRef
    { summaryRefBucket = summariesBucket,
      summaryRefKey = ObjectKey ("summaries/" <> normalizedRunId runIdText <> ".json"),
      summaryRefRunId = runIdValue
    }

manifestRefForRun :: RunId -> ManifestRef
manifestRefForRun runIdValue@(RunId runIdText) =
  ManifestRef
    { manifestRefBucket = summariesBucket,
      manifestRefKey = ObjectKey ("manifests/" <> normalizedRunId runIdText <> ".json"),
      manifestRefRunId = runIdValue
    }

normalizedRunId :: Text -> Text
normalizedRunId = normalizeSegment
