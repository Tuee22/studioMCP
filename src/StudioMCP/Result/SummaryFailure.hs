module StudioMCP.Result.SummaryFailure
  ( SummaryFailure (..),
  )
where

import StudioMCP.Result.Failure (FailureDetail)

newtype SummaryFailure = SummaryFailure
  { getSummaryFailure :: FailureDetail
  }
  deriving (Eq, Show)
