{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Storage.Keys
  ( BucketName (..),
    memoBucket,
    artifactsBucket,
    summariesBucket,
  )
where

import Data.Text (Text)

newtype BucketName = BucketName
  { unBucketName :: Text
  }
  deriving (Eq, Show)

memoBucket :: BucketName
memoBucket = BucketName "studiomcp-memo"

artifactsBucket :: BucketName
artifactsBucket = BucketName "studiomcp-artifacts"

summariesBucket :: BucketName
summariesBucket = BucketName "studiomcp-summaries"
