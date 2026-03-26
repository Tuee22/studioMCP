{-# LANGUAGE OverloadedStrings #-}

module DAG.HashingSpec (spec) where

import StudioMCP.DAG.Hashing
import Test.Hspec

spec :: Spec
spec = do
  describe "normalizeSegment" $ do
    it "converts to lowercase" $ do
      normalizeSegment "HELLO" `shouldBe` "hello"
      normalizeSegment "World" `shouldBe` "world"
      normalizeSegment "MixedCase" `shouldBe` "mixedcase"

    it "replaces spaces with hyphens" $ do
      normalizeSegment "hello world" `shouldBe` "hello-world"
      normalizeSegment "foo bar baz" `shouldBe` "foo-bar-baz"

    it "strips leading and trailing whitespace" $ do
      normalizeSegment "  hello  " `shouldBe` "hello"
      normalizeSegment "\thello\t" `shouldBe` "hello"

    it "handles combined transformations" $ do
      normalizeSegment "  Hello World  " `shouldBe` "hello-world"
      normalizeSegment "  MIXED Case TEXT  " `shouldBe` "mixed-case-text"

    it "handles empty string" $ do
      normalizeSegment "" `shouldBe` ""

    it "handles single word" $ do
      normalizeSegment "test" `shouldBe` "test"

    it "handles already normalized text" $ do
      normalizeSegment "already-normalized" `shouldBe` "already-normalized"
