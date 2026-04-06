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
import Crypto.Hash (Digest, SHA256, hash)
import Crypto.MAC.HMAC (HMAC, hmac)
import Data.ByteArray (convert)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    object,
    withObject,
    (.:),
    (.=),
  )
import Data.Char (isAlphaNum, ord)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString as ByteString
import Data.Time (UTCTime, addUTCTime, getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
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
    tscBucketPrefix :: Text,
    -- | Endpoint for platform-managed MinIO/S3 storage
    tscPlatformEndpoint :: Text,
    -- | Public endpoint used in presigned URLs returned to callers
    tscPlatformPublicEndpoint :: Maybe Text,
    -- | AWS region used for SigV4 signing
    tscPlatformRegion :: Text,
    -- | Access key for platform-managed storage
    tscPlatformAccessKeyId :: Text,
    -- | Secret access key for platform-managed storage
    tscPlatformSecretAccessKey :: Text
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
      tscBucketPrefix = "studiomcp-tenant-",
      tscPlatformEndpoint = "http://localhost:9000",
      tscPlatformPublicEndpoint = Nothing,
      tscPlatformRegion = "us-east-1",
      tscPlatformAccessKeyId = "minioadmin",
      tscPlatformSecretAccessKey = "minioadmin"
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
      headers =
        Map.fromList
          [ ("Content-Type", contentType),
            ("x-amz-meta-artifact-id", artifactId),
            ("x-amz-meta-tenant-id", let TenantId t = tenantId in t)
          ]
  case buildPresignedUrl config backend now (tscUploadUrlTtl config) "PUT" bucket key headers of
    Left err -> pure (Left err)
    Right presignedUrl -> do
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
      pure $
        buildPresignedUrl
          config
          backend
          now
          (tscDownloadUrlTtl config)
          "GET"
          bucket
          key
          Map.empty

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
  TenantStorageConfig ->
  TenantStorageBackend ->
  UTCTime ->
  Int ->
  Text ->
  BucketName ->
  ObjectKey ->
  Map.Map Text Text ->
  Either TenantStorageError PresignedUrl
buildPresignedUrl config backend signedAt ttlSeconds method bucket key headers = do
  credentials <- presignCredentials config backend
  let canonicalUri = objectCanonicalUri bucket key
      signedHeadersMap = Map.insert "host" (pecHost credentials) (canonicalizeHeaders headers)
      signedHeaders = T.intercalate ";" (Map.keys signedHeadersMap)
      amzDate = formatAmzDate signedAt
      credentialDate = formatCredentialDate signedAt
      credentialScope =
        credentialDate
          <> "/"
          <> pecRegion credentials
          <> "/s3/aws4_request"
      queryParams =
        Map.fromList
          [ ("X-Amz-Algorithm", "AWS4-HMAC-SHA256"),
            ("X-Amz-Credential", pecAccessKeyId credentials <> "/" <> credentialScope),
            ("X-Amz-Date", amzDate),
            ("X-Amz-Expires", T.pack (show ttlSeconds)),
            ("X-Amz-SignedHeaders", signedHeaders)
          ]
      canonicalQuery = renderCanonicalQuery queryParams
      canonicalHeaders = renderCanonicalHeaders signedHeadersMap
      canonicalRequest =
        T.intercalate
          "\n"
          [ method,
            canonicalUri,
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            "UNSIGNED-PAYLOAD"
          ]
      stringToSign =
        T.intercalate
          "\n"
          [ "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            sha256Hex canonicalRequest
          ]
      signature =
        hmacSha256Hex
          ( signingKey
              (pecSecretAccessKey credentials)
              credentialDate
              (pecRegion credentials)
          )
          stringToSign
      finalQuery =
        renderCanonicalQuery
          (Map.insert "X-Amz-Signature" signature queryParams)
      expiresAt = addUTCTime (fromIntegral ttlSeconds) signedAt
  pure
    PresignedUrl
      { puUrl =
          trimTrailingSlash (pecEndpoint credentials)
            <> canonicalUri
            <> "?"
            <> finalQuery,
        puExpiresAt = expiresAt,
        puMethod = method,
        puHeaders = headers
      }

data PresignCredentials = PresignCredentials
  { pecEndpoint :: Text,
    pecHost :: Text,
    pecRegion :: Text,
    pecAccessKeyId :: Text,
    pecSecretAccessKey :: Text
  }

presignCredentials :: TenantStorageConfig -> TenantStorageBackend -> Either TenantStorageError PresignCredentials
presignCredentials config backend =
  case backend of
    PlatformMinIO ->
      buildCredentials
        (fromMaybe (tscPlatformEndpoint config) (tscPlatformPublicEndpoint config))
        (tscPlatformRegion config)
        (tscPlatformAccessKeyId config)
        (tscPlatformSecretAccessKey config)
    TenantOwnedS3 {..} ->
      buildCredentials
        tosEndpoint
        tosRegion
        tosAccessKeyId
        tosSecretAccessKey
  where
    buildCredentials endpoint region accessKeyId secretAccessKey
      | T.null endpoint = Left (PresignedUrlGenerationFailed "Storage endpoint is empty")
      | T.null region = Left (PresignedUrlGenerationFailed "Storage region is empty")
      | T.null accessKeyId = Left (PresignedUrlGenerationFailed "Storage access key is empty")
      | T.null secretAccessKey = Left (PresignedUrlGenerationFailed "Storage secret key is empty")
      | otherwise =
          Right
            PresignCredentials
              { pecEndpoint = trimTrailingSlash endpoint,
                pecHost = endpointHost endpoint,
                pecRegion = region,
                pecAccessKeyId = accessKeyId,
                pecSecretAccessKey = secretAccessKey
              }

objectCanonicalUri :: BucketName -> ObjectKey -> Text
objectCanonicalUri bucket key =
  "/"
    <> encodePathSegment (unBucketName bucket)
    <> "/"
    <> T.intercalate "/" (map encodePathSegment (T.splitOn "/" (unObjectKey key)))

canonicalizeHeaders :: Map.Map Text Text -> Map.Map Text Text
canonicalizeHeaders =
  Map.fromList
    . map (\(name, value) -> (T.toLower name, normalizeHeaderValue value))
    . Map.toList

renderCanonicalHeaders :: Map.Map Text Text -> Text
renderCanonicalHeaders headers =
  T.concat [name <> ":" <> value <> "\n" | (name, value) <- Map.toAscList headers]

renderCanonicalQuery :: Map.Map Text Text -> Text
renderCanonicalQuery queryParams =
  T.intercalate
    "&"
    [ percentEncode name <> "=" <> percentEncode value
    | (name, value) <- Map.toAscList queryParams
    ]

signingKey :: Text -> Text -> Text -> ByteString.ByteString
signingKey secret credentialDate region =
  hmacSha256Raw
    ( hmacSha256Raw
        (hmacSha256Raw (hmacSha256Raw ("AWS4" <> TE.encodeUtf8 secret) credentialDate) region)
        "s3"
    )
    "aws4_request"

hmacSha256Raw :: ByteString.ByteString -> Text -> ByteString.ByteString
hmacSha256Raw key message =
  convert (hmac key (TE.encodeUtf8 message) :: HMAC SHA256)

hmacSha256Hex :: ByteString.ByteString -> Text -> Text
hmacSha256Hex key message =
  hexText (convert (hmac key (TE.encodeUtf8 message) :: HMAC SHA256))

sha256Hex :: Text -> Text
sha256Hex =
  hexDigestText . (hash . TE.encodeUtf8 :: Text -> Digest SHA256)

hexText :: ByteString.ByteString -> Text
hexText =
  TE.decodeUtf8 . convertToBase Base16

hexDigestText :: Digest SHA256 -> Text
hexDigestText =
  TE.decodeUtf8 . convertToBase Base16

formatAmzDate :: UTCTime -> Text
formatAmzDate =
  T.pack . formatTime defaultTimeLocale "%Y%m%dT%H%M%SZ"

formatCredentialDate :: UTCTime -> Text
formatCredentialDate =
  T.pack . formatTime defaultTimeLocale "%Y%m%d"

endpointHost :: Text -> Text
endpointHost endpoint =
  T.takeWhile (/= '/') $
    fromMaybe strippedHttps (T.stripPrefix "http://" strippedHttps)
  where
    strippedHttps = fromMaybe endpoint (T.stripPrefix "https://" endpoint)

trimTrailingSlash :: Text -> Text
trimTrailingSlash = T.dropWhileEnd (== '/')

normalizeHeaderValue :: Text -> Text
normalizeHeaderValue =
  T.unwords . T.words

percentEncode :: Text -> Text
percentEncode =
  T.concatMap
    ( \c ->
        if isUnreserved c
          then T.singleton c
          else percentEncodeChar c
    )

encodePathSegment :: Text -> Text
encodePathSegment =
  T.concatMap
    ( \c ->
        if isUnreserved c
          then T.singleton c
          else percentEncodeChar c
    )

isUnreserved :: Char -> Bool
isUnreserved c =
  isAlphaNum c || c `elem` ("-_.~" :: String)

percentEncodeChar :: Char -> Text
percentEncodeChar c =
  "%" <> hexNibble high <> hexNibble low
  where
    codePoint = ord c
    (high, low) = codePoint `divMod` 16

    hexNibble n
      | n < 10 = T.singleton (toEnum (fromEnum '0' + n))
      | otherwise = T.singleton (toEnum (fromEnum 'A' + (n - 10)))
