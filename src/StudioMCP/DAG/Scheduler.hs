module StudioMCP.DAG.Scheduler
  ( SchedulerMode (..),
  )
where

data SchedulerMode
  = TopologicalSequential
  deriving (Eq, Show)
