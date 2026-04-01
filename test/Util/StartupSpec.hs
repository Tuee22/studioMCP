{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Util.StartupSpec (spec) where

import Control.Exception (bracket, try)
import Control.Monad (forM_)
import qualified Data.Text as Text
import StudioMCP.Util.Startup
import System.Environment (lookupEnv, setEnv, unsetEnv)
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck (Positive (..), ioProperty)

spec :: Spec
spec = do
  describe "renderStartupFailure" $ do
    it "redacts sensitive text in startup messages" $ do
      let failure =
            startupFailure
              "Invalid configuration: Authorization header Bearer secret-token"
              (Just "Replace sk-secret and retry")
      Text.unpack (renderStartupFailure failure) `shouldContain` "[REDACTED]"

  describe "resolvePortEnvWithDefault" $ do
    around_ (withEnvIsolation ["STUDIO_MCP_PORT"]) $ do
      it "returns the default port when unset" $ do
        resolvePortEnvWithDefault "STUDIO_MCP_PORT" 3000 `shouldReturn` 3000

      it "throws a startup failure for invalid ports" $ do
        setEnv "STUDIO_MCP_PORT" "abc"

        result <- try (resolvePortEnvWithDefault "STUDIO_MCP_PORT" 3000) :: IO (Either StartupFailure Int)

        case result of
          Left failure -> show failure `shouldContain` "STUDIO_MCP_PORT"
          Right _ -> expectationFailure "Expected invalid port to fail startup validation"

      prop "accepts every generated TCP port in range" $ \(rawPort :: Positive Int) ->
        let port = ((getPositive rawPort - 1) `mod` 65535) + 1
         in ioProperty $ do
              setEnv "STUDIO_MCP_PORT" (show port)
              resolvedPort <- resolvePortEnvWithDefault "STUDIO_MCP_PORT" 3000
              pure (resolvedPort == port)

withEnvIsolation :: [String] -> IO a -> IO a
withEnvIsolation names action =
  bracket
    (mapM captureEnv names)
    restoreEnv
    (\_ -> do
        clearEnvVars names
        action
    )

captureEnv :: String -> IO (String, Maybe String)
captureEnv name = do
  value <- lookupEnv name
  pure (name, value)

restoreEnv :: [(String, Maybe String)] -> IO ()
restoreEnv bindings =
  forM_ bindings $ \(name, value) ->
    case value of
      Just current -> setEnv name current
      Nothing -> unsetEnv name

clearEnvVars :: [String] -> IO ()
clearEnvVars = mapM_ unsetEnv
