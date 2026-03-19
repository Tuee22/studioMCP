module StudioMCP.Util.Json
  ( encodeJson,
  )
where

import Data.Aeson (ToJSON, encode)
import Data.ByteString.Lazy (ByteString)

encodeJson :: ToJSON a => a -> ByteString
encodeJson = encode
