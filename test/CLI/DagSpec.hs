{-# LANGUAGE OverloadedStrings #-}

module CLI.DagSpec (spec) where

import StudioMCP.CLI.Dag
import Test.Hspec

spec :: Spec
spec = do
  describe "FixtureValidationSummary" $ do
    it "can be created with all fields" $ do
      let summary = FixtureValidationSummary
            { fixtureValidCount = 10
            , fixtureInvalidParseCount = 2
            , fixtureInvalidValidationCount = 3
            }
      fixtureValidCount summary `shouldBe` 10
      fixtureInvalidParseCount summary `shouldBe` 2
      fixtureInvalidValidationCount summary `shouldBe` 3

    it "can be compared for equality" $ do
      let summary1 = FixtureValidationSummary 5 1 2
          summary2 = FixtureValidationSummary 5 1 2
          summary3 = FixtureValidationSummary 6 1 2
      summary1 `shouldBe` summary2
      summary1 `shouldNotBe` summary3

    it "can be shown" $ do
      let summary = FixtureValidationSummary 1 2 3
      show summary `shouldContain` "FixtureValidationSummary"

  describe "validateDagFixturesAt" $ do
    it "returns Left for non-existent directory" $ do
      result <- validateDagFixturesAt "/nonexistent/path/to/fixtures"
      case result of
        Left problems -> do
          length problems `shouldSatisfy` (> 0)
        Right _ -> expectationFailure "Expected problems for non-existent path"

    it "returns Left when no fixtures found" $ do
      result <- validateDagFixturesAt "/tmp"
      case result of
        Left problems -> do
          length problems `shouldSatisfy` (> 0)
        Right _ -> expectationFailure "Expected problems when no fixtures"
