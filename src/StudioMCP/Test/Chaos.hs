{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Test.Chaos
  ( waitForRecoveryWithin,
  )
where

import Control.Concurrent (threadDelay)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time (diffUTCTime, getCurrentTime)
import StudioMCP.Result.Failure
  ( FailureCategory (TimeoutFailure),
    FailureDetail (..),
  )

waitForRecoveryWithin :: Int -> IO Bool -> IO (Either FailureDetail ())
waitForRecoveryWithin maxSeconds checkRecovered = do
  startedAt <- getCurrentTime
  go startedAt
  where
    go startedAt = do
      recovered <- checkRecovered
      if recovered
        then pure (Right ())
        else do
          now <- getCurrentTime
          let elapsedSeconds = realToFrac (diffUTCTime now startedAt) :: Double
          if elapsedSeconds > fromIntegral maxSeconds
            then
              pure
                ( Left
                    FailureDetail
                      { failureCategory = TimeoutFailure,
                        failureCode = "chaos-recovery-timeout",
                        failureMessage = "The simulated chaos scenario did not recover within the configured SLA.",
                        failureRetryable = True,
                        failureContext = Map.fromList [("maxSeconds", showText maxSeconds)]
                      }
                )
            else do
              threadDelay 100000
              go startedAt

showText :: Show a => a -> Text.Text
showText = Text.pack . show
