module StudioMCP.Util.Logging
  ( logInfo,
  )
where

import Data.Text (Text)
import qualified Data.Text.IO as Text

logInfo :: Text -> IO ()
logInfo = Text.putStrLn
