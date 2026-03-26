{-# LANGUAGE OverloadedStrings #-}

module Result.SummaryFailureSpec (spec) where

import qualified Data.Map.Strict as Map
import StudioMCP.Result.Failure (FailureDetail (..), FailureCategory (..), validationFailure)
import StudioMCP.Result.SummaryFailure
import Test.Hspec

spec :: Spec
spec = do
  describe "SummaryFailure" $ do
    it "can be created from FailureDetail" $ do
      let detail = validationFailure "code" "message"
          summary = SummaryFailure detail
      getSummaryFailure summary `shouldBe` detail

    it "can be compared for equality" $ do
      let detail1 = validationFailure "code" "message"
          detail2 = validationFailure "code" "message"
          detail3 = validationFailure "other" "message"
          summary1 = SummaryFailure detail1
          summary2 = SummaryFailure detail2
          summary3 = SummaryFailure detail3
      summary1 `shouldBe` summary2
      summary1 `shouldNotBe` summary3

    it "can be shown" $ do
      let detail = validationFailure "code" "msg"
          summary = SummaryFailure detail
      show summary `shouldContain` "SummaryFailure"

    it "wraps any FailureDetail" $ do
      let detail = FailureDetail
            { failureCategory = TimeoutFailure
            , failureCode = "timeout-code"
            , failureMessage = "timed out"
            , failureRetryable = True
            , failureContext = Map.fromList [("key", "value")]
            }
          summary = SummaryFailure detail
      failureCategory (getSummaryFailure summary) `shouldBe` TimeoutFailure
      failureCode (getSummaryFailure summary) `shouldBe` "timeout-code"
      failureRetryable (getSummaryFailure summary) `shouldBe` True

    it "preserves context through wrapping" $ do
      let detail = FailureDetail
            { failureCategory = StorageFailure
            , failureCode = "storage-error"
            , failureMessage = "storage failed"
            , failureRetryable = False
            , failureContext = Map.fromList [("bucket", "my-bucket"), ("key", "my-key")]
            }
          summary = SummaryFailure detail
          ctx = failureContext (getSummaryFailure summary)
      Map.lookup "bucket" ctx `shouldBe` Just "my-bucket"
      Map.lookup "key" ctx `shouldBe` Just "my-key"
