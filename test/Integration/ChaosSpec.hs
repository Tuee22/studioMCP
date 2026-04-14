module Integration.ChaosSpec (spec) where

import Data.IORef (newIORef, atomicModifyIORef')
import StudioMCP.Test.Chaos (waitForRecoveryWithin)
import Test.Hspec

spec :: Spec
spec =
  describe "chaos" $ do
    it "recovers a transient MinIO-style outage within the budget" $ do
      attemptsRef <- newIORef (0 :: Int)
      result <-
        waitForRecoveryWithin 2 $ do
          attemptCount <- atomicModifyIORef' attemptsRef (\n -> let next = n + 1 in (next, next))
          pure (attemptCount >= 3)
      result `shouldBe` Right ()

    it "recovers a transient Pulsar-style outage within the budget" $ do
      attemptsRef <- newIORef (0 :: Int)
      result <-
        waitForRecoveryWithin 2 $ do
          attemptCount <- atomicModifyIORef' attemptsRef (\n -> let next = n + 1 in (next, next))
          pure (attemptCount >= 4)
      result `shouldBe` Right ()

    it "fails when recovery exceeds the configured budget" $ do
      result <- waitForRecoveryWithin 0 (pure False)
      result `shouldSatisfy` either (const True) (const False)
