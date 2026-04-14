module Main (main) where

import qualified Integration.ChaosSpec
import qualified Integration.DAGChainsSpec
import qualified Integration.EmailFlowsSpec
import qualified Integration.HarnessSpec
import Test.Hspec (hspec)

main :: IO ()
main =
  hspec $ do
    Integration.HarnessSpec.spec
    Integration.DAGChainsSpec.spec
    Integration.ChaosSpec.spec
    Integration.EmailFlowsSpec.spec
