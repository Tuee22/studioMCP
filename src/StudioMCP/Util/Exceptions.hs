module StudioMCP.Util.Exceptions
  ( StudioMCPException (..),
  )
where

import Control.Exception (Exception)
import Data.Text (Text)

newtype StudioMCPException = StudioMCPException
  { unStudioMCPException :: Text
  }
  deriving (Eq, Show)

instance Exception StudioMCPException
