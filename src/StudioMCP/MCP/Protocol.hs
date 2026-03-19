module StudioMCP.MCP.Protocol
  ( SubmissionRequest (..),
  )
where

import Data.Text (Text)

newtype SubmissionRequest = SubmissionRequest
  { submissionDagPath :: Text
  }
  deriving (Eq, Show)
