{-# LANGUAGE OverloadedStrings #-}

module Models.LoaderSpec (spec) where

import StudioMCP.Models.Loader
import StudioMCP.Models.Registry
import System.Environment (lookupEnv, setEnv, unsetEnv)
import Test.Hspec

spec :: Spec
spec = do
  describe "modelCacheRoot" $ do
    it "defaults to the repository-managed cache path" $ do
      originalValue <- lookupEnv "STUDIOMCP_MODEL_CACHE_DIR"
      unsetEnv "STUDIOMCP_MODEL_CACHE_DIR"
      cacheRoot <- modelCacheRoot
      restoreEnv originalValue
      cacheRoot `shouldBe` ".data/studiomcp/model-cache"

    it "honors the cache directory override" $ do
      originalValue <- lookupEnv "STUDIOMCP_MODEL_CACHE_DIR"
      setEnv "STUDIOMCP_MODEL_CACHE_DIR" "/tmp/studiomcp-model-cache"
      cacheRoot <- modelCacheRoot
      restoreEnv originalValue
      cacheRoot `shouldBe` "/tmp/studiomcp-model-cache"

  describe "resolveCachedModelPath" $ do
    it "places model artifacts beneath a per-model cache directory" $ do
      let modelArtifact =
            case lookupModelArtifact "whisper-base-en" of
              Just artifact -> artifact
              Nothing -> error "expected registered model"
      resolveCachedModelPath "/tmp/cache-root" modelArtifact
        `shouldBe` "/tmp/cache-root/whisper-base-en/base.en.bin"

restoreEnv :: Maybe String -> IO ()
restoreEnv (Just value) = setEnv "STUDIOMCP_MODEL_CACHE_DIR" value
restoreEnv Nothing = unsetEnv "STUDIOMCP_MODEL_CACHE_DIR"
