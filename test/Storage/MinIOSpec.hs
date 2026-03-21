{-# LANGUAGE OverloadedStrings #-}

module Storage.MinIOSpec
  ( spec,
  )
where

import StudioMCP.Result.Failure (failureCode, failureRetryable)
import StudioMCP.Storage.Keys (BucketName (..), ObjectKey (..))
import StudioMCP.Storage.MinIO (classifyMinioFailure)
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "MinIO helpers" $ do
    it "maps missing object reads to a stable storage failure" $ do
      let failureDetail =
            classifyMinioFailure
              "read"
              (BucketName "studiomcp-memo")
              (ObjectKey "memo/missing")
              (Just 1)
              "mc: <ERROR> Unable to read from `local/studiomcp-memo/memo/missing`. Object does not exist."
      failureCode failureDetail `shouldBe` "minio-object-not-found"
      failureRetryable failureDetail `shouldBe` False

    it "maps service outages to a retryable storage failure" $ do
      let failureDetail =
            classifyMinioFailure
              "write"
              (BucketName "studiomcp-summaries")
              (ObjectKey "summaries/run-1.json")
              (Just 1)
              "mc: <ERROR> Get \"http://studiomcp-minio:9000\": dial tcp: lookup studiomcp-minio: no such host"
      failureCode failureDetail `shouldBe` "minio-service-unavailable"
      failureRetryable failureDetail `shouldBe` True
