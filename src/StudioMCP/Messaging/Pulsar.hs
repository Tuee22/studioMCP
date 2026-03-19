module StudioMCP.Messaging.Pulsar
  ( PulsarConfig (..),
  )
where

import Data.Text (Text)

data PulsarConfig = PulsarConfig
  { pulsarHttpEndpoint :: Text,
    pulsarBinaryEndpoint :: Text
  }
  deriving (Eq, Show)
