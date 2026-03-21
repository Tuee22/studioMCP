{-# LANGUAGE OverloadedStrings #-}

module DAG.TimeoutSpec
  ( spec,
  )
where

import StudioMCP.DAG.Timeout (timeoutFailureForNode)
import StudioMCP.DAG.Types (NodeId (..), TimeoutPolicy (..))
import qualified Data.Map.Strict as Map
import StudioMCP.Result.Failure
  ( FailureCategory (TimeoutFailure),
    failureCategory,
    failureCode,
    failureContext,
    failureRetryable,
  )
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "timeoutFailureForNode" $
    it "maps a timeout policy to a structured timeout failure" $ do
      let failureDetail = timeoutFailureForNode (NodeId "render") (TimeoutPolicy 90)
      failureCategory failureDetail `shouldBe` TimeoutFailure
      failureCode failureDetail `shouldBe` "node-timeout"
      failureRetryable failureDetail `shouldBe` True
      failureContext failureDetail `shouldBe` Map.fromList [("nodeId", "render"), ("timeoutSeconds", "90")]
