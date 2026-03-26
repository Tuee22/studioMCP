{-# LANGUAGE OverloadedStrings #-}

module DAG.ProvenanceSpec (spec) where

import Data.Aeson (decode, encode)
import StudioMCP.DAG.Provenance
import Test.Hspec

spec :: Spec
spec = do
  describe "Provenance" $ do
    it "can be created with all fields" $ do
      let prov = Provenance
            { provenanceDagName = "test-dag"
            , provenanceDagVersion = "1.0.0"
            , provenanceRequestedBy = "test-user"
            }
      provenanceDagName prov `shouldBe` "test-dag"
      provenanceDagVersion prov `shouldBe` "1.0.0"
      provenanceRequestedBy prov `shouldBe` "test-user"

    it "can be compared for equality" $ do
      let prov1 = Provenance "dag" "v1" "user"
          prov2 = Provenance "dag" "v1" "user"
          prov3 = Provenance "other" "v1" "user"
      prov1 `shouldBe` prov2
      prov1 `shouldNotBe` prov3

    it "round-trips through JSON" $ do
      let prov = Provenance "my-dag" "2.0.0" "admin"
      (decode (encode prov) :: Maybe Provenance) `shouldBe` Just prov

  describe "emptyProvenance" $ do
    it "creates provenance with draft version" $ do
      let prov = emptyProvenance "test-workflow"
      provenanceDagName prov `shouldBe` "test-workflow"
      provenanceDagVersion prov `shouldBe` "draft"

    it "uses local-dev as requestedBy" $ do
      let prov = emptyProvenance "workflow"
      provenanceRequestedBy prov `shouldBe` "local-dev"

    it "sets the dag name from argument" $ do
      let prov = emptyProvenance "complex-pipeline"
      provenanceDagName prov `shouldBe` "complex-pipeline"

  describe "Provenance JSON" $ do
    it "serializes to expected fields" $ do
      let prov = Provenance "dag" "v1" "user"
          json = encode prov
      -- Verify it's valid JSON by decoding
      (decode json :: Maybe Provenance) `shouldBe` Just prov

    it "deserializes from JSON object" $ do
      let prov = Provenance "my-dag" "1.2.3" "api-user"
      (decode (encode prov) :: Maybe Provenance) `shouldBe` Just prov
