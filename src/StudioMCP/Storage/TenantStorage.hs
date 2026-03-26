{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module StudioMCP.Storage.TenantStorage
  ( -- * Tenant Storage Configuration
    TenantStorageConfig (..),
    TenantStorageBackend (..),
    defaultTenantStorageConfig,

    -- * Tenant Storage Service
    TenantStorageService (..),
    newTenantStorageService,

    -- * Tenant Artifact
    TenantArtifact (..),

    -- * Tenant-Scoped Operations
    getTenantBucket,
    getTenantArtifactKey,
    createTenantArtifact,
    getTenantArtifact,
    listTenantArtifacts,

    -- * Presigned URLs
    generateUploadUrl,
    generateDownloadUrl,
    PresignedUrl (..),

    -- * Storage Errors
    TenantStorageError (..),
    tenantStorageErrorCode,
  )
where

import Control.Concurrent.STM (TVar, atomically, modifyTVar', newTVarIO, readTVarIO)
import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    object,
    withObject,
    (.:),
    (.=),
  )
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime, addUTCTime, getCurrentTime)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import StudioMCP.Auth.Types (TenantId (..))
import StudioMCP.Storage.ContentAddressed (ContentAddress)
import StudioMCP.Storage.Keys (BucketName (..), ObjectKey (..))

-- | Backend type for tenant storage
data TenantStorageBackend
  = -- | Platform-managed MinIO storage
    PlatformMinIO
  | -- | Tenant-owned S3-compatible storage
    TenantOwnedS3
      { tosEndpoint :: Text,
        tosRegion :: Text,
        tosAccessKeyId :: Text,
        tosSecretAccessKey :: Text
      }
  deriving (Eq, Show)

instance ToJSON TenantStorageBackend where
  toJSON PlatformMinIO = object ["type" .= ("platform-minio" :: Text)]
  toJSON TenantOwnedS3 {..} =
    object
      [ "type" .= ("tenant-s3" :: Text),
        "endpoint" .= tosEndpoint,
        "region" .= tosRegion,
        "accessKeyId" .= tosAccessKeyId,
        "secretAccessKey" .= ("[REDACTED]" :: Text)
      ]

instance FromJSON TenantStorageBackend where
  parseJSON = withObject "TenantStorageBackend" $ \obj -> do
    backendType <- obj .: "type"
    case (backendType :: Text) of
      "platform-minio" -> pure PlatformMinIO
      "tenant-s3" ->
        TenantOwnedS3
          <$> obj .: "endpoint"
          <*> obj .: "region"
          <*> obj .: "accessKeyId"
          <*> obj .: "secretAccessKey"
      other -> fail $ "Unknown backend type: " <> T.unpack other

-- | Configuration for tenant storage
data TenantStorageConfig = TenantStorageConfig
  { -- | Default backend for new tenants
    tscDefaultBackend :: TenantStorageBackend,
    -- | URL TTL for upload presigned URLs (seconds)
    tscUploadUrlTtl :: Int,
    -- | URL TTL for download presigned URLs (seconds)
    tscDownloadUrlTtl :: Int,
    -- | Maximum artifact size in bytes
    tscMaxArtifactSize :: Integer,
    -- | Bucket prefix for platform-managed storage
    tscBucketPrefix :: Text
  }
  deriving (Eq, Show)

-- | Default tenant storage configuration
defaultTenantStorageConfig :: TenantStorageConfig
defaultTenantStorageConfig =
  TenantStorageConfig
    { tscDefaultBackend = PlatformMinIO,
      tscUploadUrlTtl = 900, -- 15 minutes
      tscDownloadUrlTtl = 300, -- 5 minutes
      tscMaxArtifactSize = 10 * 1024 * 1024 * 1024, -- 10 GB
      tscBucketPrefix = "studiomcp-tenant-"
    }

-- | Tenant artifact metadata
data TenantArtifact = TenantArtifact
  { taArtifactId :: Text,
    taTenantId :: TenantId,
    taContentAddress :: Maybe ContentAddress,
    taContentType :: Text,
    taFileName :: Text,
    taFileSize :: Integer,
    taVersion :: Int,
    taCreatedAt :: UTCTime,
    taMetadata :: Map.Map Text Text
  }
  deriving (Eq, Show)

instance ToJSON TenantArtifact where
  toJSON TenantArtifact {..} =
    object
      [ "artifactId" .= taArtifactId,
        "tenantId" .= taTenantId,
        "contentAddress" .= taContentAddress,
        "contentType" .= taContentType,
        "fileName" .= taFileName,
        "fileSize" .= taFileSize,
        "version" .= taVersion,
        "createdAt" .= taCreatedAt,
        "metadata" .= taMetadata
      ]

instance FromJSON TenantArtifact where
  parseJSON = withObject "TenantArtifact" $ \obj ->
    TenantArtifact
      <$> obj .: "artifactId"
      <*> obj .: "tenantId"
      <*> obj .: "contentAddress"
      <*> obj .: "contentType"
      <*> obj .: "fileName"
      <*> obj .: "fileSize"
      <*> obj .: "version"
      <*> obj .: "createdAt"
      <*> obj .: "metadata"

-- | Presigned URL for upload or download
data PresignedUrl = PresignedUrl
  { puUrl :: Text,
    puExpiresAt :: UTCTime,
    puMethod :: Text,
    puHeaders :: Map.Map Text Text
  }
  deriving (Eq, Show)

instance ToJSON PresignedUrl where
  toJSON PresignedUrl {..} =
    object
      [ "url" .= puUrl,
        "expiresAt" .= puExpiresAt,
        "method" .= puMethod,
        "headers" .= puHeaders
      ]

instance FromJSON PresignedUrl where
  parseJSON = withObject "PresignedUrl" $ \obj ->
    PresignedUrl
      <$> obj .: "url"
      <*> obj .: "expiresAt"
      <*> obj .: "method"
      <*> obj .: "headers"

-- | Tenant storage errors
data TenantStorageError
  = TenantNotConfigured TenantId
  | ArtifactNotFound Text
  | ArtifactVersionNotFound Text Int
  | StorageBackendError Text
  | PresignedUrlGenerationFailed Text
  | ArtifactTooLarge Integer Integer
  | InvalidContentType Text
  | StorageQuotaExceeded TenantId
  deriving (Eq, Show)

-- | Get error code for tenant storage error
tenantStorageErrorCode :: TenantStorageError -> Text
tenantStorageErrorCode (TenantNotConfigured _) = "tenant-not-configured"
tenantStorageErrorCode (ArtifactNotFound _) = "artifact-not-found"
tenantStorageErrorCode (ArtifactVersionNotFound _ _) = "artifact-version-not-found"
tenantStorageErrorCode (StorageBackendError _) = "storage-backend-error"
tenantStorageErrorCode (PresignedUrlGenerationFailed _) = "presigned-url-failed"
tenantStorageErrorCode (ArtifactTooLarge _ _) = "artifact-too-large"
tenantStorageErrorCode (InvalidContentType _) = "invalid-content-type"
tenantStorageErrorCode (StorageQuotaExceeded _) = "storage-quota-exceeded"

-- | Internal state for tenant storage service
data TenantStorageState = TenantStorageState
  { tssArtifacts :: Map.Map Text TenantArtifact,
    tssTenantBackends :: Map.Map TenantId TenantStorageBackend,
    tssPresignedUrls :: Map.Map Text PresignedUrl
  }

-- | Tenant storage service
data TenantStorageService = TenantStorageService
  { tssConfig :: TenantStorageConfig,
    tssState :: TVar TenantStorageState
  }

-- | Create a new tenant storage service
newTenantStorageService :: TenantStorageConfig -> IO TenantStorageService
newTenantStorageService config = do
  stateVar <-
    newTVarIO
      TenantStorageState
        { tssArtifacts = Map.empty,
          tssTenantBackends = Map.empty,
          tssPresignedUrls = Map.empty
        }
  pure
    TenantStorageService
      { tssConfig = config,
        tssState = stateVar
      }

-- | Get the bucket name for a tenant
getTenantBucket :: TenantStorageService -> TenantId -> BucketName
getTenantBucket service (TenantId tenantIdText) =
  BucketName (tscBucketPrefix (tssConfig service) <> tenantIdText)

-- | Get the artifact key for a tenant artifact
getTenantArtifactKey :: TenantId -> Text -> Int -> ObjectKey
getTenantArtifactKey (TenantId tenantIdText) artifactId version =
  ObjectKey
    ( "artifacts/"
        <> tenantIdText
        <> "/"
        <> artifactId
        <> "/v"
        <> T.pack (show version)
    )

-- | Create a new tenant artifact (metadata only)
createTenantArtifact ::
  TenantStorageService ->
  TenantId ->
  Text ->
  Text ->
  Integer ->
  Map.Map Text Text ->
  IO (Either TenantStorageError TenantArtifact)
createTenantArtifact service tenantId contentType fileName fileSize metadata = do
  let config = tssConfig service
  if fileSize > tscMaxArtifactSize config
    then pure $ Left $ ArtifactTooLarge fileSize (tscMaxArtifactSize config)
    else do
      now <- getCurrentTime
      artifactId <- generateArtifactId
      let artifact =
            TenantArtifact
              { taArtifactId = artifactId,
                taTenantId = tenantId,
                taContentAddress = Nothing,
                taContentType = contentType,
                taFileName = fileName,
                taFileSize = fileSize,
                taVersion = 1,
                taCreatedAt = now,
                taMetadata = metadata
              }
      atomically $ do
        modifyTVar' (tssState service) $ \state ->
          state {tssArtifacts = Map.insert artifactId artifact (tssArtifacts state)}
      pure $ Right artifact

-- | Get a tenant artifact by ID
getTenantArtifact ::
  TenantStorageService ->
  TenantId ->
  Text ->
  IO (Either TenantStorageError TenantArtifact)
getTenantArtifact service tenantId artifactId = do
  state <- readTVarIO (tssState service)
  case Map.lookup artifactId (tssArtifacts state) of
    Nothing -> pure $ Left $ ArtifactNotFound artifactId
    Just artifact
      | taTenantId artifact /= tenantId ->
          pure $ Left $ ArtifactNotFound artifactId
      | otherwise ->
          pure $ Right artifact

-- | List artifacts for a tenant
listTenantArtifacts ::
  TenantStorageService ->
  TenantId ->
  IO [TenantArtifact]
listTenantArtifacts service tenantId = do
  state <- readTVarIO (tssState service)
  pure $ filter (\a -> taTenantId a == tenantId) $ Map.elems (tssArtifacts state)

-- | Generate a presigned URL for upload
generateUploadUrl ::
  TenantStorageService ->
  TenantId ->
  Text ->
  Text ->
  IO (Either TenantStorageError PresignedUrl)
generateUploadUrl service tenantId artifactId contentType = do
  now <- getCurrentTime
  backend <- resolveTenantBackend service tenantId
  let config = tssConfig service
      bucket = getTenantBucket service tenantId
      key = getTenantArtifactKey tenantId artifactId 1
      expiresAt = addUTCTime (fromIntegral (tscUploadUrlTtl config)) now
      presignedUrl =
        buildPresignedUrl backend "PUT" bucket key expiresAt $
          Map.fromList
            [ ("Content-Type", contentType),
              ("x-amz-meta-artifact-id", artifactId),
              ("x-amz-meta-tenant-id", let TenantId t = tenantId in t)
            ]
  atomically $ do
    modifyTVar' (tssState service) $ \state ->
      state
        { tssPresignedUrls =
            Map.insert artifactId presignedUrl (tssPresignedUrls state)
        }
  pure $ Right presignedUrl

-- | Generate a presigned URL for download
generateDownloadUrl ::
  TenantStorageService ->
  TenantId ->
  Text ->
  Maybe Int ->
  IO (Either TenantStorageError PresignedUrl)
generateDownloadUrl service tenantId artifactId maybeVersion = do
  artifactResult <- getTenantArtifact service tenantId artifactId
  case artifactResult of
    Left err -> pure $ Left err
    Right artifact -> do
      now <- getCurrentTime
      backend <- resolveTenantBackend service tenantId
      let config = tssConfig service
          version = maybe (taVersion artifact) id maybeVersion
          bucket = getTenantBucket service tenantId
          key = getTenantArtifactKey tenantId artifactId version
          expiresAt = addUTCTime (fromIntegral (tscDownloadUrlTtl config)) now
          presignedUrl =
            buildPresignedUrl backend "GET" bucket key expiresAt Map.empty
      pure $ Right presignedUrl

-- | Generate a unique artifact ID
generateArtifactId :: IO Text
generateArtifactId = do
  uuid <- UUID.nextRandom
  pure $ "artifact-" <> UUID.toText uuid

resolveTenantBackend :: TenantStorageService -> TenantId -> IO TenantStorageBackend
resolveTenantBackend service tenantId = do
  state <- readTVarIO (tssState service)
  pure $
    Map.findWithDefault
      (tscDefaultBackend (tssConfig service))
      tenantId
      (tssTenantBackends state)

buildPresignedUrl ::
  TenantStorageBackend ->
  Text ->
  BucketName ->
  ObjectKey ->
  UTCTime ->
  Map.Map Text Text ->
  PresignedUrl
buildPresignedUrl backend method bucket key expiresAt headers =
  PresignedUrl
    { puUrl = presignedObjectUrl baseUrl bucket key method expiresAt signature,
      puExpiresAt = expiresAt,
      puMethod = method,
      puHeaders = headers
    }
  where
    baseUrl = backendBaseUrl backend
    signature = presignedSignature backend method bucket key expiresAt

backendBaseUrl :: TenantStorageBackend -> Text
backendBaseUrl PlatformMinIO = "http://localhost:9000"
backendBaseUrl TenantOwnedS3 {tosEndpoint = endpoint} = trimTrailingSlash endpoint

presignedObjectUrl :: Text -> BucketName -> ObjectKey -> Text -> UTCTime -> Text -> Text
presignedObjectUrl baseUrl bucket key method expiresAt signature =
  trimTrailingSlash baseUrl
    <> "/"
    <> unBucketName bucket
    <> "/"
    <> unObjectKey key
    <> "?method="
    <> method
    <> "&expires="
    <> urlEncodeText (T.pack (show expiresAt))
    <> "&signature="
    <> signature

presignedSignature :: TenantStorageBackend -> Text -> BucketName -> ObjectKey -> UTCTime -> Text
presignedSignature backend method bucket key expiresAt =
  T.pack . show . abs . hashText $
    method
      <> "|"
      <> backendSignatureSeed backend
      <> "|"
      <> unBucketName bucket
      <> "|"
      <> unObjectKey key
      <> "|"
      <> T.pack (show expiresAt)

backendSignatureSeed :: TenantStorageBackend -> Text
backendSignatureSeed PlatformMinIO = "platform-minio-local"
backendSignatureSeed TenantOwnedS3 {tosEndpoint = endpoint, tosRegion = region, tosAccessKeyId = accessKeyId} =
  endpoint <> "|" <> region <> "|" <> accessKeyId

trimTrailingSlash :: Text -> Text
trimTrailingSlash = T.dropWhileEnd (== '/')

urlEncodeText :: Text -> Text
urlEncodeText =
  T.concatMap
    ( \c ->
        case c of
          ' ' -> "%20"
          ':' -> "%3A"
          '/' -> "%2F"
          '+' -> "%2B"
          _ -> T.singleton c
    )

hashText :: Text -> Int
hashText = T.foldl' (\acc c -> acc * 33 + fromEnum c) 5381
