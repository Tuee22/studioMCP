{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.MCP.Transport.Stdio
  ( -- * Stdio Transport
    StdioTransport,
    createStdioTransport,
    runStdioTransport,

    -- * Configuration
    StdioConfig (..),
    defaultStdioConfig,
  )
where

import Control.Concurrent (MVar, newMVar, putMVar, takeMVar)
import Control.Exception (SomeException, try)
import Data.Aeson (Value, decode, encode)
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Lazy.Char8 as LBS8
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import qualified Data.Text as T
import StudioMCP.MCP.Transport.Types
import System.IO (BufferMode (..), Handle, hFlush, hIsEOF, hSetBinaryMode, hSetBuffering, stdin, stdout)

-- | Stdio transport configuration
data StdioConfig = StdioConfig
  { scMaxMessageSize :: Int,
    scInputHandle :: Handle,
    scOutputHandle :: Handle
  }
  deriving (Eq)

-- | Default stdio configuration
defaultStdioConfig :: StdioConfig
defaultStdioConfig =
  StdioConfig
    { scMaxMessageSize = 10 * 1024 * 1024, -- 10MB
      scInputHandle = stdin,
      scOutputHandle = stdout
    }

-- | Stdio transport state
data StdioTransport = StdioTransport
  { stConfig :: StdioConfig,
    stIsOpen :: IORef Bool,
    stWriteLock :: MVar ()
  }

-- | Create a new stdio transport
createStdioTransport :: StdioConfig -> IO StdioTransport
createStdioTransport config = do
  -- Set up handles for binary mode and line buffering
  hSetBinaryMode (scInputHandle config) True
  hSetBinaryMode (scOutputHandle config) True
  hSetBuffering (scInputHandle config) LineBuffering
  hSetBuffering (scOutputHandle config) LineBuffering

  isOpenRef <- newIORef True
  writeLock <- newMVar ()

  pure
    StdioTransport
      { stConfig = config,
        stIsOpen = isOpenRef,
        stWriteLock = writeLock
      }

-- | Convert StdioTransport to Transport interface
runStdioTransport :: StdioTransport -> Transport
runStdioTransport st =
  Transport
    { transportSend = stdioSend st,
      transportReceive = stdioReceive st,
      transportClose = stdioClose st,
      transportIsOpen = readIORef (stIsOpen st),
      transportId = "stdio"
    }

-- | Send a JSON-RPC message over stdio
stdioSend :: StdioTransport -> Value -> IO (Either TransportError ())
stdioSend st msg = do
  isOpen <- readIORef (stIsOpen st)
  if not isOpen
    then pure (Left ConnectionClosed)
    else do
      let encoded = encode msg
          size = LBS.length encoded

      -- Check message size
      if size > fromIntegral (scMaxMessageSize (stConfig st))
        then pure (Left (MessageTooLarge (fromIntegral size) (scMaxMessageSize (stConfig st))))
        else do
          -- Acquire write lock and send
          result <- try $ do
            () <- takeMVar (stWriteLock st)
            -- Write message followed by newline (JSON-RPC over stdio uses newline delimiters)
            LBS8.hPutStrLn (scOutputHandle (stConfig st)) encoded
            hFlush (scOutputHandle (stConfig st))
            putMVar (stWriteLock st) ()

          case result of
            Left (e :: SomeException) -> do
              -- Release lock if we acquired it
              _ <- try @SomeException $ putMVar (stWriteLock st) ()
              pure (Left (IOError (T.pack (show e))))
            Right () -> pure (Right ())

-- | Receive a JSON-RPC message from stdio
stdioReceive :: StdioTransport -> IO (Either TransportError Value)
stdioReceive st = do
  isOpen <- readIORef (stIsOpen st)
  if not isOpen
    then pure (Left ConnectionClosed)
    else do
      result <- try $ readJsonLine st
      case result of
        Left (e :: SomeException) ->
          pure (Left (IOError (T.pack (show e))))
        Right lineResult ->
          pure lineResult

-- | Read a single JSON line from input
readJsonLine :: StdioTransport -> IO (Either TransportError Value)
readJsonLine st = do
  let inHandle = scInputHandle (stConfig st)
      maxSize = scMaxMessageSize (stConfig st)

  -- Check for EOF
  eof <- hIsEOF inHandle
  if eof
    then do
      atomicModifyIORef' (stIsOpen st) (const (False, ()))
      pure (Left ConnectionClosed)
    else do
      -- Read line (newline-delimited JSON)
      strictLine <- BS8.hGetLine inHandle
      let line = LBS.fromStrict strictLine

      let size = LBS.length line
      if size > fromIntegral maxSize
        then pure (Left (MessageTooLarge (fromIntegral size) maxSize))
        else case decode line of
          Nothing ->
            pure (Left (ParseError "Invalid JSON"))
          Just value ->
            pure (Right value)

-- | Close the stdio transport
stdioClose :: StdioTransport -> IO ()
stdioClose st = do
  atomicModifyIORef' (stIsOpen st) (const (False, ()))
  -- Note: We don't close stdin/stdout handles as they're shared resources
