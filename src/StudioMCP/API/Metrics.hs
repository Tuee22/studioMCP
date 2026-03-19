module StudioMCP.API.Metrics
  ( MetricsSnapshot (..),
  )
where

data MetricsSnapshot = MetricsSnapshot
  { totalRuns :: Int
  }
  deriving (Eq, Show)
