{-# LANGUAGE OverloadedStrings #-}

module Result.TypesSpec (spec) where

import StudioMCP.Result.Types
import Test.Hspec

spec :: Spec
spec = do
  describe "Result" $ do
    it "can create Success" $ do
      let result = Success "value" :: Result String String
      case result of
        Success v -> v `shouldBe` "value"
        Failure _ -> expectationFailure "Expected Success"

    it "can create Failure" $ do
      let result = Failure "error" :: Result String String
      case result of
        Success _ -> expectationFailure "Expected Failure"
        Failure e -> e `shouldBe` "error"

    it "can be compared for equality" $ do
      (Success 1 :: Result Int Int) `shouldBe` Success 1
      (Failure 1 :: Result Int Int) `shouldBe` Failure 1
      (Success 1 :: Result Int Int) `shouldNotBe` Failure 1

    it "can be shown" $ do
      show (Success "ok" :: Result String String) `shouldContain` "Success"
      show (Failure "err" :: Result String String) `shouldContain` "Failure"

  describe "eitherToResult" $ do
    it "converts Right to Success" $ do
      eitherToResult (Right "value" :: Either String String) `shouldBe` Success "value"

    it "converts Left to Failure" $ do
      eitherToResult (Left "error" :: Either String String) `shouldBe` Failure "error"

  describe "resultToEither" $ do
    it "converts Success to Right" $ do
      resultToEither (Success "value" :: Result String String) `shouldBe` Right "value"

    it "converts Failure to Left" $ do
      resultToEither (Failure "error" :: Result String String) `shouldBe` Left "error"

  describe "round-trip conversion" $ do
    it "preserves Success through round-trip" $ do
      let original = Success 42 :: Result Int String
      (eitherToResult . resultToEither) original `shouldBe` original

    it "preserves Failure through round-trip" $ do
      let original = Failure "err" :: Result Int String
      (eitherToResult . resultToEither) original `shouldBe` original
