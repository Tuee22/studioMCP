module StudioMCP.MCP.Types
  ( ServerStatus (..),
  )
where

data ServerStatus
  = ServerBooting
  | ServerReady
  deriving (Eq, Show)
