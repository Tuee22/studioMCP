module StudioMCP.Util.Logging
  ( configureProcessLogging,
    logInfo,
  )
where

import Data.Text (Text)
import qualified Data.Text.IO as Text
import System.IO (BufferMode (LineBuffering), hSetBuffering, stderr, stdout)

configureProcessLogging :: IO ()
configureProcessLogging = do
  hSetBuffering stdout LineBuffering
  hSetBuffering stderr LineBuffering

logInfo :: Text -> IO ()
logInfo = Text.putStrLn
