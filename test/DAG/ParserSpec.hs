module DAG.ParserSpec
  ( spec,
  )
where

import StudioMCP.CLI.Dag
  ( FixtureValidationSummary (..),
    validateDagFixturesAt,
  )
import StudioMCP.DAG.Parser (loadDagFile)
import StudioMCP.DAG.Validator (validateDag)
import StudioMCP.Result.Types (Result (Failure, Success))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec =
  describe "DAG fixture parsing" $ do
    it "parses a valid example DAG fixture" $ do
      decoded <- loadDagFile "examples/dags/transcode-basic.yaml"
      decoded `shouldSatisfy` isRight

    it "rejects a malformed YAML fixture" $ do
      decoded <- loadDagFile "examples/dags/invalid/parse/malformed-yaml.yaml"
      decoded `shouldSatisfy` isLeft

    it "rejects a structurally invalid fixture during validation" $ do
      decoded <- loadDagFile "examples/dags/invalid/validation/missing-summary-node.yaml"
      decoded `shouldSatisfy` isRight
      case decoded of
        Left _ -> error "expected invalid validation fixture to parse successfully"
        Right dagSpec ->
          validateDag dagSpec `shouldSatisfy` isFailure

    it "automatically checks the full DAG fixture set" $ do
      result <- validateDagFixturesAt "examples/dags"
      result `shouldSatisfy` isRight
      case result of
        Left _ -> error "expected fixture validation to succeed"
        Right summary -> do
          fixtureValidCount summary `shouldSatisfy` (> 0)
          fixtureInvalidParseCount summary `shouldBe` 1
          fixtureInvalidValidationCount summary `shouldBe` 1

isLeft :: Either a b -> Bool
isLeft resultValue =
  case resultValue of
    Left _ -> True
    Right _ -> False

isRight :: Either a b -> Bool
isRight = not . isLeft

isFailure :: Result a f -> Bool
isFailure resultValue =
  case resultValue of
    Failure _ -> True
    Success _ -> False
