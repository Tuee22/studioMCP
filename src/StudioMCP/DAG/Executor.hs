module StudioMCP.DAG.Executor
  ( ExecutorPlan (..),
  )
where

import StudioMCP.DAG.Types (DagSpec)

newtype ExecutorPlan = ExecutorPlan
  { executorDag :: DagSpec
  }
  deriving (Eq, Show)
