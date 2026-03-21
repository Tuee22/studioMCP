{-# LANGUAGE OverloadedStrings #-}

module Storage.ContentAddressedSpec
  ( spec,
  )
where

import StudioMCP.Storage.ContentAddressed
  ( deriveContentAddress,
  )
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe)

spec :: Spec
spec =
  describe "deriveContentAddress" $ do
    it "gives the same content address for the same normalized semantic input" $
      deriveContentAddress [" Transcode Basic ", "WAV"]
        `shouldBe` deriveContentAddress ["transcode-basic", "wav"]

    it "gives a different content address when the semantic input changes" $
      deriveContentAddress ["transcode-basic", "wav"]
        `shouldNotBe` deriveContentAddress ["transcode-basic", "flac"]
