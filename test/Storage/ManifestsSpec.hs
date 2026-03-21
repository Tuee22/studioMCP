{-# LANGUAGE OverloadedStrings #-}

module Storage.ManifestsSpec
  ( spec,
  )
where

import Data.Aeson (decode, encode)
import StudioMCP.DAG.Summary (RunId (..))
import StudioMCP.DAG.Types (NodeId (..))
import StudioMCP.Storage.ContentAddressed (deriveContentAddress)
import StudioMCP.Storage.Keys
  ( ObjectKey (..),
    artifactsBucket,
    memoObjectRef,
    summaryRefForRun,
  )
import StudioMCP.Storage.Manifests
  ( ArtifactRef (..),
    ManifestEntry (..),
    RunManifest,
    buildRunManifest,
  )
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "RunManifest JSON" $
    it "round-trips a manifest with memo and artifact references" $
      decode (encode runManifest) `shouldBe` Just runManifest

runManifest :: RunManifest
runManifest =
  buildRunManifest
    (RunId "run-42")
    (summaryRefForRun (RunId "run-42"))
    [ ManifestEntry
        { manifestEntryNodeId = NodeId "render",
          manifestEntryMemoRef = memoObjectRef (deriveContentAddress ["render", "wav"]),
          manifestEntryArtifactRef =
            Just
              ArtifactRef
                { artifactBucket = artifactsBucket,
                  artifactKey = ObjectKey "artifacts/render/output.wav",
                  artifactAddress = Nothing
                }
        }
    ]
