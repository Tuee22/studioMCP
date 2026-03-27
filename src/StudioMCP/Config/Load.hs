module StudioMCP.Config.Load
  ( loadAppConfig,
  )
where

import Data.Maybe (fromMaybe)
import Data.Char (toLower)
import Data.Text (Text, pack)
import StudioMCP.Config.Types (AppConfig (..), AppMode (InferenceMode, ServerMode, WorkerMode))
import System.Environment (lookupEnv)

loadAppConfig :: IO AppConfig
loadAppConfig = do
  appModeValue <- envMode "STUDIO_MCP_MODE" ServerMode
  pulsarHttp <- envText "STUDIO_MCP_PULSAR_HTTP_URL" "http://studiomcp-pulsar-proxy"
  pulsarBinary <- envText "STUDIO_MCP_PULSAR_BINARY_URL" "pulsar://studiomcp-pulsar-proxy:6650"
  minio <- envText "STUDIO_MCP_MINIO_ENDPOINT" "http://studiomcp-minio:9000"
  minioAccess <- envText "STUDIO_MCP_MINIO_ACCESS_KEY" "minioadmin"
  minioSecret <- envText "STUDIO_MCP_MINIO_SECRET_KEY" "minioadmin123"
  pure
    AppConfig
      { appMode = appModeValue,
        pulsarHttpUrl = pulsarHttp,
        pulsarBinaryUrl = pulsarBinary,
        minioEndpoint = minio,
        minioAccessKey = minioAccess,
        minioSecretKey = minioSecret
      }

envText :: String -> String -> IO Text
envText name fallback = do
  value <- lookupEnv name
  pure (pack (fromMaybe fallback value))

envMode :: String -> AppMode -> IO AppMode
envMode name fallback = do
  value <- lookupEnv name
  pure $
    case fmap (map toLower) value of
      Just "server" -> ServerMode
      Just "inference" -> InferenceMode
      Just "worker" -> WorkerMode
      _ -> fallback
