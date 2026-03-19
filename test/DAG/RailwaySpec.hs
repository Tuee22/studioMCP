module DAG.RailwaySpec
  ( spec,
  )
where

import StudioMCP.DAG.Railway (bindResult)
import StudioMCP.Result.Types (Result (Failure, Success))
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "bindResult" $ do
    it "short-circuits on failure" $
      bindResult (\n -> Success (n + 1)) (Failure "boom" :: Result Int String)
        `shouldBe` Failure "boom"

    it "continues on success" $
      bindResult (\n -> Success (n + 1)) (Success 1 :: Result Int String)
        `shouldBe` Success 2
