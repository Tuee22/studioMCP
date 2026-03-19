module Main (main) where

import qualified DAG.MemoizationSpec
import qualified DAG.RailwaySpec
import qualified DAG.SummarySpec
import qualified DAG.TimeoutSpec
import qualified DAG.ValidatorSpec
import Test.Hspec (hspec)

main :: IO ()
main =
  hspec $ do
    DAG.ValidatorSpec.spec
    DAG.RailwaySpec.spec
    DAG.TimeoutSpec.spec
    DAG.MemoizationSpec.spec
    DAG.SummarySpec.spec
