module StudioMCP.Config.Load
  ( loadAppConfig,
  )
where

import Data.Maybe (fromMaybe)
import Data.Text (Text, pack)
import StudioMCP.Config.Types (AppConfig (..), AppMode (ServerMode))
import System.Environment (lookupEnv)

loadAppConfig :: IO AppConfig
loadAppConfig = do
  pulsarHttp <- envText "STUDIO_MCP_PULSAR_HTTP_URL" "http://localhost:8080"
  pulsarBinary <- envText "STUDIO_MCP_PULSAR_BINARY_URL" "pulsar://localhost:6650"
  minio <- envText "STUDIO_MCP_MINIO_ENDPOINT" "http://localhost:9000"
  pure
    AppConfig
      { appMode = ServerMode,
        pulsarHttpUrl = pulsarHttp,
        pulsarBinaryUrl = pulsarBinary,
        minioEndpoint = minio
      }

envText :: String -> String -> IO Text
envText name fallback = do
  value <- lookupEnv name
  pure (pack (fromMaybe fallback value))
