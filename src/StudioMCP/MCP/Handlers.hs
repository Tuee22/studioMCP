module StudioMCP.MCP.Handlers
  ( validateSubmission,
  )
where

import StudioMCP.MCP.Protocol (SubmissionRequest)

validateSubmission :: SubmissionRequest -> Bool
validateSubmission _ = True
