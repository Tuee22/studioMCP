{-# LANGUAGE OverloadedStrings #-}

module DAG.MemoizationSpec
  ( spec,
  )
where

import StudioMCP.DAG.Memoization (MemoKey (..), deriveMemoKey)
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "deriveMemoKey" $
    it "normalizes memo-key segments deterministically" $
      deriveMemoKey [" FFmpeg ", "Input Asset", "v1"]
        `shouldBe` MemoKey "memo:ffmpeg:input-asset:v1"
