module StudioMCP.Tools.Boundary
  ( BoundaryResult (..),
  )
where

import Data.Text (Text)

data BoundaryResult = BoundaryResult
  { boundaryStdout :: Text,
    boundaryStderr :: Text,
    boundaryExitCode :: Int
  }
  deriving (Eq, Show)
