module StudioMCP.Tools.Registry
  ( ToolRegistry (..),
    emptyToolRegistry,
  )
where

import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import StudioMCP.Tools.Types (ToolName)

newtype ToolRegistry = ToolRegistry
  { unToolRegistry :: Map ToolName FilePath
  }
  deriving (Eq, Show)

emptyToolRegistry :: ToolRegistry
emptyToolRegistry = ToolRegistry Map.empty
