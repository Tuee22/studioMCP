module StudioMCP.Tools.Types
  ( ToolName (..),
    ToolInvocation (..),
  )
where

import Data.Text (Text)

newtype ToolName = ToolName
  { unToolName :: Text
  }
  deriving (Eq, Ord, Show)

data ToolInvocation = ToolInvocation
  { invocationTool :: ToolName,
    invocationArgs :: [Text]
  }
  deriving (Eq, Show)
