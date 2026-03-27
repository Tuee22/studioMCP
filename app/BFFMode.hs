{-# LANGUAGE OverloadedStrings #-}

module BFFMode
  ( runBffMode,
  )
where

import Network.Wai.Handler.Warp (defaultSettings, runSettings, setHost, setPort)
import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Data.Text as Text
import Network.HTTP.Client (defaultManagerSettings, newManager)
import StudioMCP.Auth.Config (loadAuthConfigFromEnv)
import StudioMCP.Auth.Middleware (newAuthService)
import StudioMCP.Config.Load (loadAppConfig)
import StudioMCP.Inference.ReferenceModel (ReferenceModelConfig (..))
import StudioMCP.MCP.Session.RedisConfig (RedisConfig, loadRedisConfigFromEnv)
import StudioMCP.MCP.Handlers
  ( ServerEnv (serverTenantStorage),
    createServerEnv,
  )
import StudioMCP.Util.Logging (configureProcessLogging)
import StudioMCP.Web.BFF
  ( BFFConfig (..),
    defaultBFFConfig,
    newBFFServiceWithMcpClient,
    newBFFServiceWithMcpClientAndRedis,
  )
import StudioMCP.Web.Handlers (bffApplication, newBFFContextWithService)
import System.Environment (lookupEnv)

runBffMode :: IO ()
runBffMode = do
  configureProcessLogging
  port <- resolveBFFPort
  appConfig <- loadAppConfig
  serverEnv <- createServerEnv appConfig
  authConfig <- loadAuthConfigFromEnv
  httpManager <- newManager defaultManagerSettings
  authService <- newAuthService authConfig httpManager
  referenceModelUrl <- maybe "http://127.0.0.1:11434/api/generate" id <$> lookupEnv "STUDIO_MCP_REFERENCE_MODEL_URL"
  mcpEndpoint <- resolveMcpEndpoint
  maybeRedisConfig <- resolveRedisConfigIfConfigured
  let bffConfig =
        defaultBFFConfig
          { bffMcpEndpoint = mcpEndpoint
          }
  service <-
    case maybeRedisConfig of
      Just redisConfig ->
        newBFFServiceWithMcpClientAndRedis
          bffConfig
          redisConfig
          (serverTenantStorage serverEnv)
          (Just authService)
          (ReferenceModelConfig referenceModelUrl)
      Nothing ->
        newBFFServiceWithMcpClient
          bffConfig
          (serverTenantStorage serverEnv)
          (Just authService)
          (ReferenceModelConfig referenceModelUrl)
  let ctx = newBFFContextWithService bffConfig service
  putStrLn ("studioMCP BFF listening on 0.0.0.0:" <> show port)
  runSettings
    (setHost "0.0.0.0" (setPort port defaultSettings))
    (bffApplication ctx)

resolveBFFPort :: IO Int
resolveBFFPort = do
  maybePortText <- lookupEnv "STUDIO_MCP_BFF_PORT"
  pure $
    case maybePortText >>= readMaybeInt of
      Just port -> port
      Nothing -> 3002

readMaybeInt :: String -> Maybe Int
readMaybeInt rawValue =
  case reads rawValue of
    [(value, "")] -> Just value
    _ -> Nothing

resolveMcpEndpoint :: IO Text
resolveMcpEndpoint = do
  maybeEndpoint <- firstJust ["STUDIO_MCP_BFF_MCP_ENDPOINT", "STUDIO_MCP_MCP_ENDPOINT"]
  pure $
    case maybeEndpoint of
      Just endpoint -> fromStringText endpoint
      Nothing -> "http://127.0.0.1:3000"

resolveRedisConfigIfConfigured :: IO (Maybe RedisConfig)
resolveRedisConfigIfConfigured = do
  hasRedisConfig <-
    any isJust
      <$> mapM
        lookupEnv
        [ "STUDIO_MCP_REDIS_URL",
          "STUDIOMCP_REDIS_URL",
          "STUDIO_MCP_REDIS_HOST",
          "STUDIOMCP_REDIS_HOST",
          "STUDIO_MCP_REDIS_PORT",
          "STUDIOMCP_REDIS_PORT"
        ]
  if hasRedisConfig
    then Just <$> loadRedisConfigFromEnv
    else pure Nothing

firstJust :: [String] -> IO (Maybe String)
firstJust [] = pure Nothing
firstJust (name : remaining) = do
  value <- lookupEnv name
  case value of
    Just _ -> pure value
    Nothing -> firstJust remaining

fromStringText :: String -> Text
fromStringText = Text.pack
