{-# LANGUAGE OverloadedStrings #-}

module Storage.KeysSpec
  ( spec,
  )
where

import StudioMCP.DAG.Summary (RunId (..))
import StudioMCP.Storage.ContentAddressed
  ( ContentAddress (..),
    deriveContentAddress,
  )
import StudioMCP.Storage.Keys
  ( BucketName (..),
    ManifestRef (..),
    MemoObjectRef (..),
    ObjectKey (..),
    SummaryRef (..),
    artifactsBucket,
    manifestRefForRun,
    memoBucket,
    memoObjectRef,
    summariesBucket,
    summaryRefForRun,
  )
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "storage key selection" $ do
    it "places memoized outputs in the memo bucket under a stable key prefix" $ do
      let address = deriveContentAddress ["node", "v1"]
          memoRef = memoObjectRef address
      memoRefBucket memoRef `shouldBe` memoBucket
      memoRefKey memoRef `shouldBe` ObjectKey ("memo/" <> unContentAddress address)

    it "places summaries in the summaries bucket with a run-scoped key" $ do
      let summaryRef = summaryRefForRun (RunId "Run 42")
      summaryRefBucket summaryRef `shouldBe` summariesBucket
      summaryRefKey summaryRef `shouldBe` ObjectKey "summaries/run-42.json"

    it "places manifests in the summaries bucket under the manifests prefix" $ do
      let manifestRef = manifestRefForRun (RunId "Run 42")
      manifestRefBucket manifestRef `shouldBe` summariesBucket
      manifestRefKey manifestRef `shouldBe` ObjectKey "manifests/run-42.json"

    it "keeps the durable artifacts bucket stable" $
      artifactsBucket `shouldBe` BucketName "studiomcp-artifacts"
