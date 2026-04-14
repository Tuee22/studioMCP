{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}

module StudioMCP.MCP.Transport.Types
  ( -- * Transport Interface
    Transport (..),
    TransportConfig (..),
    TransportError (..),
    TransportEvent (..),

    -- * Message Types
    RawMessage (..),
    MessageDirection (..),

    -- * Callbacks
    MessageHandler,
    ErrorHandler,
    CloseHandler,

    -- * Utilities
    transportErrorToText,
  )
where

import Control.Exception (Exception)
import Data.Aeson (FromJSON, ToJSON, Value)
import Data.ByteString.Lazy (ByteString)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

-- | Raw message wrapper
data RawMessage = RawMessage
  { rmContent :: ByteString,
    rmParsed :: Maybe Value
  }
  deriving (Show, Generic)

-- | Message direction for logging/debugging
data MessageDirection = Incoming | Outgoing
  deriving (Eq, Show, Generic)

-- | Transport configuration
data TransportConfig = TransportConfig
  { tcMaxMessageSize :: Int,
    tcReadTimeout :: Maybe Int, -- milliseconds
    tcWriteTimeout :: Maybe Int -- milliseconds
  }
  deriving (Eq, Show, Generic)

instance ToJSON TransportConfig

instance FromJSON TransportConfig

-- | Transport errors
data TransportError
  = ConnectionClosed
  | ParseError Text
  | MessageTooLarge Int Int -- actual, max
  | ReadTimeout
  | WriteTimeout
  | IOError Text
  | ProtocolViolation Text
  deriving (Eq, Show, Generic)

instance Exception TransportError

instance ToJSON TransportError

-- | Convert transport error to text
transportErrorToText :: TransportError -> Text
transportErrorToText = \case
  ConnectionClosed -> "Connection closed"
  ParseError msg -> "Parse error: " <> msg
  MessageTooLarge actual maxSize ->
    "Message too large: " <> T.pack (show actual) <> " > " <> T.pack (show maxSize)
  ReadTimeout -> "Read timeout"
  WriteTimeout -> "Write timeout"
  IOError msg -> "IO error: " <> msg
  ProtocolViolation msg -> "Protocol violation: " <> msg

-- | Transport events
data TransportEvent
  = MessageReceived RawMessage
  | TransportErrorOccurred TransportError
  | TransportClosed
  deriving (Show, Generic)

-- | Message handler callback
type MessageHandler = Value -> IO ()

-- | Error handler callback
type ErrorHandler = TransportError -> IO ()

-- | Close handler callback
type CloseHandler = IO ()

-- | Transport interface
data Transport = Transport
  { -- | Send a JSON-RPC message
    transportSend :: Value -> IO (Either TransportError ()),
    -- | Receive a JSON-RPC message (blocking)
    transportReceive :: IO (Either TransportError Value),
    -- | Close the transport
    transportClose :: IO (),
    -- | Check if transport is open
    transportIsOpen :: IO Bool,
    -- | Transport identifier for logging
    transportId :: Text
  }
