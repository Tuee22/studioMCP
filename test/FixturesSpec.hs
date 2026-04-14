{-# LANGUAGE OverloadedStrings #-}

module FixturesSpec (spec) where

import System.IO.Error (catchIOError)
import StudioMCP.Test.Fixtures
import System.Directory (doesFileExist, getTemporaryDirectory, removePathForcibly)
import System.FilePath ((</>))
import Test.Hspec

spec :: Spec
spec = do
  describe "lookupFixtureArtifact" $ do
    it "finds a registered fixture" $ do
      fmap fixtureId (lookupFixtureArtifact "tone-440hz-1s") `shouldBe` Just "tone-440hz-1s"

  describe "generateAllLocalFixtures" $ do
    it "materializes the deterministic fixture set" $ do
      tempDir <- getTemporaryDirectory
      let fixturesRoot = tempDir </> "studiomcp-fixtures-spec"
      catchIOError (removePathForcibly fixturesRoot) (\_ -> pure ())
      generatedResult <- generateAllLocalFixtures fixturesRoot
      case generatedResult of
        Left failureDetail -> expectationFailure (show failureDetail)
        Right generatedPaths -> do
          generatedPaths `shouldSatisfy` (not . null)
          mapM doesFileExist generatedPaths >>= (`shouldSatisfy` and)
