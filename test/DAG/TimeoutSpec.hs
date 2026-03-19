{-# LANGUAGE OverloadedStrings #-}

module DAG.TimeoutSpec
  ( spec,
  )
where

import StudioMCP.DAG.Timeout (timeoutFailureForNode)
import StudioMCP.DAG.Types (NodeId (..), TimeoutPolicy (..))
import StudioMCP.Result.Failure (FailureCategory (TimeoutFailure), failureCategory)
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "timeoutFailureForNode" $
    it "maps a timeout policy to a structured timeout failure" $
      failureCategory (timeoutFailureForNode (NodeId "render") (TimeoutPolicy 90))
        `shouldBe` TimeoutFailure
