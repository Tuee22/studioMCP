module StudioMCP.DAG.Timeout
  ( timeoutFailureForNode,
  )
where

import StudioMCP.DAG.Types (NodeId, TimeoutPolicy (..))
import StudioMCP.Result.Failure (FailureDetail, timeoutFailure)

timeoutFailureForNode :: NodeId -> TimeoutPolicy -> FailureDetail
timeoutFailureForNode nodeId timeoutPolicy =
  timeoutFailure nodeId (timeoutSeconds timeoutPolicy)
