module StudioMCP.Util.Time
  ( secondsToNominalDiffTime,
  )
where

import Data.Time (NominalDiffTime)

secondsToNominalDiffTime :: Int -> NominalDiffTime
secondsToNominalDiffTime = fromIntegral
