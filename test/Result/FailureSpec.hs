{-# LANGUAGE OverloadedStrings #-}

module Result.FailureSpec (spec) where

import Data.Aeson (decode, encode)
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import StudioMCP.DAG.Types (NodeId (..))
import StudioMCP.Result.Failure
import Test.Hspec

spec :: Spec
spec = do
  describe "FailureCategory" $ do
    it "distinguishes all categories" $ do
      TimeoutFailure `shouldNotBe` ValidationFailure
      ValidationFailure `shouldNotBe` ToolProcessFailure
      ToolProcessFailure `shouldNotBe` BadOutputDecoding
      BadOutputDecoding `shouldNotBe` DependencyMissing
      DependencyMissing `shouldNotBe` StorageFailure
      StorageFailure `shouldNotBe` MessagingFailure
      MessagingFailure `shouldNotBe` InternalInvariantFailure

    it "round-trips through JSON" $ do
      (decode (encode TimeoutFailure) :: Maybe FailureCategory) `shouldBe` Just TimeoutFailure
      (decode (encode ValidationFailure) :: Maybe FailureCategory) `shouldBe` Just ValidationFailure
      (decode (encode ToolProcessFailure) :: Maybe FailureCategory) `shouldBe` Just ToolProcessFailure
      (decode (encode StorageFailure) :: Maybe FailureCategory) `shouldBe` Just StorageFailure

    it "can be compared for equality" $ do
      TimeoutFailure `shouldBe` TimeoutFailure
      ValidationFailure `shouldBe` ValidationFailure

    it "can be shown" $ do
      show TimeoutFailure `shouldContain` "TimeoutFailure"
      show ValidationFailure `shouldContain` "ValidationFailure"

  describe "FailureDetail" $ do
    it "can be created with all fields" $ do
      let detail = FailureDetail
            { failureCategory = ValidationFailure
            , failureCode = "invalid-input"
            , failureMessage = "Input validation failed"
            , failureRetryable = False
            , failureContext = Map.fromList [("field", "name")]
            }
      failureCategory detail `shouldBe` ValidationFailure
      failureCode detail `shouldBe` "invalid-input"
      failureMessage detail `shouldBe` "Input validation failed"
      failureRetryable detail `shouldBe` False
      Map.lookup "field" (failureContext detail) `shouldBe` Just "name"

    it "round-trips through JSON" $ do
      let detail = FailureDetail
            { failureCategory = TimeoutFailure
            , failureCode = "timeout"
            , failureMessage = "Operation timed out"
            , failureRetryable = True
            , failureContext = Map.empty
            }
      (decode (encode detail) :: Maybe FailureDetail) `shouldBe` Just detail

  describe "validationFailure" $ do
    it "creates ValidationFailure category" $ do
      let detail = validationFailure "code" "message"
      failureCategory detail `shouldBe` ValidationFailure

    it "sets the code correctly" $ do
      let detail = validationFailure "my-code" "message"
      failureCode detail `shouldBe` "my-code"

    it "sets the message correctly" $ do
      let detail = validationFailure "code" "my-message"
      failureMessage detail `shouldBe` "my-message"

    it "is not retryable" $ do
      let detail = validationFailure "code" "msg"
      failureRetryable detail `shouldBe` False

    it "has empty context" $ do
      let detail = validationFailure "code" "msg"
      failureContext detail `shouldBe` Map.empty

  describe "timeoutFailure" $ do
    it "creates TimeoutFailure category" $ do
      let detail = timeoutFailure (NodeId "node1") 30
      failureCategory detail `shouldBe` TimeoutFailure

    it "sets the code to node-timeout" $ do
      let detail = timeoutFailure (NodeId "node1") 30
      failureCode detail `shouldBe` "node-timeout"

    it "includes node ID in message" $ do
      let detail = timeoutFailure (NodeId "my-node") 30
      T.isInfixOf "my-node" (failureMessage detail) `shouldBe` True

    it "is retryable" $ do
      let detail = timeoutFailure (NodeId "node1") 30
      failureRetryable detail `shouldBe` True

    it "includes context with nodeId and timeout" $ do
      let detail = timeoutFailure (NodeId "node1") 60
      Map.lookup "nodeId" (failureContext detail) `shouldBe` Just "node1"
      Map.lookup "timeoutSeconds" (failureContext detail) `shouldBe` Just "60"

  describe "invariantFailure" $ do
    it "creates InternalInvariantFailure category" $ do
      let detail = invariantFailure "broken invariant"
      failureCategory detail `shouldBe` InternalInvariantFailure

    it "sets the code to internal-invariant" $ do
      let detail = invariantFailure "msg"
      failureCode detail `shouldBe` "internal-invariant"

    it "sets the message correctly" $ do
      let detail = invariantFailure "something went wrong"
      failureMessage detail `shouldBe` "something went wrong"

    it "is not retryable" $ do
      let detail = invariantFailure "msg"
      failureRetryable detail `shouldBe` False

    it "has empty context" $ do
      let detail = invariantFailure "msg"
      failureContext detail `shouldBe` Map.empty
