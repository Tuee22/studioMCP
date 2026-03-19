module StudioMCP.Inference.ReferenceModel
  ( ReferenceModel (..),
  )
where

import Data.Text (Text)

newtype ReferenceModel = ReferenceModel
  { referenceModelName :: Text
  }
  deriving (Eq, Show)
