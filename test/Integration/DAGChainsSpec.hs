{-# LANGUAGE OverloadedStrings #-}

module Integration.DAGChainsSpec (spec) where

import StudioMCP.DAG.Parser (loadDagFile)
import StudioMCP.DAG.Types (DagSpec (..), NodeSpec (..))
import StudioMCP.DAG.Validator (validateDag)
import StudioMCP.Result.Types (Result (..))
import StudioMCP.Tools.Registry (defaultToolRegistry, lookupToolExecutable)
import StudioMCP.Tools.Types (ToolName (..))
import Data.Maybe (mapMaybe)
import Test.Hspec

spec :: Spec
spec =
  describe "dag chains" $ do
    mapM_ validateDagFixture dagFixtures

validateDagFixture :: FilePath -> Spec
validateDagFixture dagPath =
  it ("parses and validates " <> dagPath) $ do
    dagResult <- loadDagFile dagPath
    case dagResult of
      Left err -> expectationFailure err
      Right dagSpec ->
        case validateDag dagSpec of
          Failure failures -> expectationFailure (show failures)
          Success validDag -> do
            let boundaryTools = mapMaybe nodeToolName (dagNodes validDag)
            mapM_ (\toolName -> lookupToolExecutable toolName defaultToolRegistry `shouldSatisfy` maybe False (const True)) boundaryTools

nodeToolName :: NodeSpec -> Maybe ToolName
nodeToolName nodeSpec = ToolName <$> nodeTool nodeSpec

dagFixtures :: [FilePath]
dagFixtures =
  [ "examples/dags/podcast-production.yaml",
    "examples/dags/music-transcription.yaml",
    "examples/dags/video-localization.yaml",
    "examples/dags/stem-remix.yaml",
    "examples/dags/pitch-transposition.yaml",
    "examples/dags/thumbnail-pipeline.yaml"
  ]
