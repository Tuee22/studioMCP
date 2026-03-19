module Main (main) where

import qualified Integration.HarnessSpec
import Test.Hspec (hspec)

main :: IO ()
main = hspec Integration.HarnessSpec.spec
