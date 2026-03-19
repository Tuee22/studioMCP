module StudioMCP.Storage.ContentAddressed
  ( ContentAddress (..),
  )
where

import Data.Text (Text)

newtype ContentAddress = ContentAddress
  { unContentAddress :: Text
  }
  deriving (Eq, Show)
