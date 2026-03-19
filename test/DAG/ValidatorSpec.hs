{-# LANGUAGE OverloadedStrings #-}

module DAG.ValidatorSpec
  ( spec,
  )
where

import StudioMCP.DAG.Types
  ( DagSpec (..),
    NodeId (..),
    NodeKind (..),
    NodeSpec (..),
    OutputType (..),
    TimeoutPolicy (..),
  )
import StudioMCP.DAG.Validator (validateDag)
import StudioMCP.Result.Types (Result (Failure, Success))
import Test.Hspec (Spec, describe, it, shouldSatisfy)

spec :: Spec
spec =
  describe "validateDag" $ do
    it "accepts a well-formed DAG" $
      validateDag validDag `shouldSatisfy` isSuccess

    it "rejects a cyclic DAG" $
      validateDag cyclicDag `shouldSatisfy` isFailure

    it "rejects pure nodes with tool bindings" $
      validateDag impurePureNodeDag `shouldSatisfy` isFailure

isSuccess :: Result a f -> Bool
isSuccess resultValue =
  case resultValue of
    Success _ -> True
    Failure _ -> False

isFailure :: Result a f -> Bool
isFailure = not . isSuccess

validDag :: DagSpec
validDag =
  DagSpec
    { dagName = "valid",
      dagDescription = Nothing,
      dagNodes =
        [ NodeSpec (NodeId "ingest") PureNode Nothing [] (OutputType "input/media") (TimeoutPolicy 5) "memoize",
          NodeSpec (NodeId "transcode") BoundaryNode (Just "ffmpeg") [NodeId "ingest"] (OutputType "output/mp4") (TimeoutPolicy 60) "memoize",
          NodeSpec (NodeId "summary") SummaryNode Nothing [NodeId "transcode"] (OutputType "summary/run") (TimeoutPolicy 5) "no-memoize"
        ]
    }

cyclicDag :: DagSpec
cyclicDag =
  DagSpec
    { dagName = "cyclic",
      dagDescription = Nothing,
      dagNodes =
        [ NodeSpec (NodeId "a") PureNode Nothing [NodeId "c"] (OutputType "x") (TimeoutPolicy 5) "memoize",
          NodeSpec (NodeId "b") BoundaryNode (Just "ffmpeg") [NodeId "a"] (OutputType "y") (TimeoutPolicy 60) "memoize",
          NodeSpec (NodeId "c") SummaryNode Nothing [NodeId "b"] (OutputType "summary/run") (TimeoutPolicy 5) "no-memoize"
        ]
    }

impurePureNodeDag :: DagSpec
impurePureNodeDag =
  DagSpec
    { dagName = "bad-pure",
      dagDescription = Nothing,
      dagNodes =
        [ NodeSpec (NodeId "bad") PureNode (Just "ffmpeg") [] (OutputType "x") (TimeoutPolicy 5) "memoize",
          NodeSpec (NodeId "summary") SummaryNode Nothing [NodeId "bad"] (OutputType "summary/run") (TimeoutPolicy 5) "no-memoize"
        ]
    }
