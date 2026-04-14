module Tools.AdaptersSpec (spec) where

import StudioMCP.Tools.BasicPitch (seedBasicPitchDeterministicFixtures, validateBasicPitchAdapter)
import StudioMCP.Tools.Demucs (seedDemucsDeterministicFixtures, validateDemucsAdapter)
import StudioMCP.Tools.FluidSynth (seedFluidSynthDeterministicFixtures, validateFluidSynthAdapter)
import StudioMCP.Tools.ImageMagick (seedImageMagickDeterministicFixtures, validateImageMagickAdapter)
import StudioMCP.Tools.MediaInfo (seedMediaInfoDeterministicFixtures, validateMediaInfoAdapter)
import StudioMCP.Tools.Rubberband (seedRubberbandDeterministicFixtures, validateRubberbandAdapter)
import StudioMCP.Tools.SoX (seedSoXDeterministicFixtures, validateSoXAdapter)
import StudioMCP.Tools.Whisper (seedWhisperDeterministicFixtures, validateWhisperAdapter)
import Test.Hspec

spec :: Spec
spec = do
  describe "deterministic adapter fixtures" $ do
    it "resolves the audio fixture set" $ do
      seedSoXDeterministicFixtures >>= (`shouldSatisfy` isRight)
      seedDemucsDeterministicFixtures >>= (`shouldSatisfy` isRight)
      seedWhisperDeterministicFixtures >>= (`shouldSatisfy` isRight)
      seedBasicPitchDeterministicFixtures >>= (`shouldSatisfy` isRight)
      seedFluidSynthDeterministicFixtures >>= (`shouldSatisfy` isRight)
      seedRubberbandDeterministicFixtures >>= (`shouldSatisfy` isRight)

    it "resolves the image and video fixtures" $ do
      seedImageMagickDeterministicFixtures >>= (`shouldSatisfy` isRight)
      seedMediaInfoDeterministicFixtures >>= (`shouldSatisfy` isRight)

  describe "adapter validation commands" $ do
    it "validates the SoX adapter" $
      validateSoXAdapter >>= (`shouldSatisfy` isRight)

    it "validates the Demucs adapter" $
      validateDemucsAdapter >>= (`shouldSatisfy` isRight)

    it "validates the Whisper adapter" $
      validateWhisperAdapter >>= (`shouldSatisfy` isRight)

    it "validates the BasicPitch adapter" $
      validateBasicPitchAdapter >>= (`shouldSatisfy` isRight)

    it "validates the FluidSynth adapter" $
      validateFluidSynthAdapter >>= (`shouldSatisfy` isRight)

    it "validates the Rubberband adapter" $
      validateRubberbandAdapter >>= (`shouldSatisfy` isRight)

    it "validates the ImageMagick adapter" $
      validateImageMagickAdapter >>= (`shouldSatisfy` isRight)

    it "validates the MediaInfo adapter" $
      validateMediaInfoAdapter >>= (`shouldSatisfy` isRight)

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight (Left _) = False
