{-# LANGUAGE OverloadedStrings #-}

module Config.EnvSpec (spec) where

import qualified Data.Text as T
import StudioMCP.Config.Env
import StudioMCP.Config.Types (AppConfig (..), AppMode (..))
import Test.Hspec

spec :: Spec
spec = do
  describe "RuntimeEnv" $ do
    it "can be created via mkRuntimeEnv" $ do
      env <- mkRuntimeEnv
      -- Should create without error
      let config = runtimeConfig env
      -- Default mode is ServerMode
      appMode config `shouldBe` ServerMode

    it "contains AppConfig" $ do
      env <- mkRuntimeEnv
      let config = runtimeConfig env
      -- Access various config fields
      T.isInfixOf "pulsar" (pulsarHttpUrl config) `shouldBe` True
      T.isInfixOf "minio" (minioEndpoint config) `shouldBe` True

    it "can be compared for equality" $ do
      env1 <- mkRuntimeEnv
      env2 <- mkRuntimeEnv
      -- Both should have same default config
      runtimeConfig env1 `shouldBe` runtimeConfig env2

    it "can be shown" $ do
      env <- mkRuntimeEnv
      show env `shouldContain` "RuntimeEnv"
