{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Models.Loader
  ( modelCacheRoot,
    resolveCachedModelPath,
    ensureModelCached,
  )
where

import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import StudioMCP.Models.Registry (ModelArtifact (..), modelsBucket)
import StudioMCP.Result.Failure (FailureDetail)
import StudioMCP.Storage.Keys (ObjectKey (..))
import StudioMCP.Storage.MinIO (MinIOConfig, readObjectBytes)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Environment (lookupEnv)
import System.FilePath (takeDirectory, (</>))

modelCacheRoot :: IO FilePath
modelCacheRoot = do
  overriddenRoot <- lookupEnv "STUDIOMCP_MODEL_CACHE_DIR"
  pure (maybe ".data/studiomcp/model-cache" id overriddenRoot)

resolveCachedModelPath :: FilePath -> ModelArtifact -> FilePath
resolveCachedModelPath cacheRoot modelArtifact =
  cacheRoot </> Text.unpack (modelId modelArtifact) </> takeFileNameText (modelObjectKey modelArtifact)

ensureModelCached :: MinIOConfig -> ModelArtifact -> IO (Either FailureDetail FilePath)
ensureModelCached config modelArtifact = do
  cacheRoot <- modelCacheRoot
  let cachedPath = resolveCachedModelPath cacheRoot modelArtifact
  createDirectoryIfMissing True (takeDirectory cachedPath)
  cachedAlreadyExists <- doesFileExist cachedPath
  if cachedAlreadyExists
    then pure (Right cachedPath)
    else do
      readResult <- readObjectBytes config modelsBucket (modelObjectKey modelArtifact)
      case readResult of
        Left failureDetail -> pure (Left failureDetail)
        Right objectBytes -> do
          LBS.writeFile cachedPath objectBytes
          pure (Right cachedPath)

takeFileNameText :: ObjectKey -> FilePath
takeFileNameText =
  reverse
    . takeWhile (/= '/')
    . reverse
    . Text.unpack
    . unObjectKey
