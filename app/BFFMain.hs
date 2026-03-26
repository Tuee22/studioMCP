{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Network.Wai.Handler.Warp (defaultSettings, runSettings, setHost, setPort)
import StudioMCP.Config.Load (loadAppConfig)
import StudioMCP.Inference.ReferenceModel (ReferenceModelConfig (..))
import StudioMCP.MCP.Handlers (createServerEnv)
import StudioMCP.Util.Logging (configureProcessLogging)
import StudioMCP.Web.BFF (defaultBFFConfig, newBFFServiceWithRuntime)
import StudioMCP.Web.Handlers (bffApplication, newBFFContextWithService)
import System.Environment (lookupEnv)

main :: IO ()
main = do
  configureProcessLogging
  port <- resolveBFFPort
  appConfig <- loadAppConfig
  serverEnv <- createServerEnv appConfig
  referenceModelUrl <- maybe "http://127.0.0.1:11434/api/generate" id <$> lookupEnv "STUDIO_MCP_REFERENCE_MODEL_URL"
  service <-
    newBFFServiceWithRuntime
      defaultBFFConfig
      (serverToolCatalog serverEnv)
      (serverTenantStorage serverEnv)
      (ReferenceModelConfig referenceModelUrl)
  let ctx = newBFFContextWithService defaultBFFConfig service
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
