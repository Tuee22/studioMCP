{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module StudioMCP.Storage.Versioning
  ( -- * Version Types
    ArtifactVersion (..),
    VersionId (..),
    VersionChain (..),

    -- * Versioning Rules
    VersioningPolicy (..),
    defaultVersioningPolicy,
    VersioningRule (..),

    -- * Versioning Service
    VersioningService (..),
    newVersioningService,

    -- * Version Operations
    createInitialVersion,
    createNewVersion,
    getVersion,
    getLatestVersion,
    listVersions,

    -- * Immutability Enforcement
    ImmutabilityError (..),
    immutabilityErrorCode,
    validateImmutability,

    -- * Version Queries
    getVersionMetadata,
    compareVersions,
    VersionComparison (..),
  )
where

import Control.Concurrent.STM (TVar, atomically, modifyTVar', newTVarIO, readTVarIO)
import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    object,
    withObject,
    (.:),
    (.:?),
    (.=),
  )
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime, diffUTCTime, getCurrentTime)
import StudioMCP.Auth.Types (SubjectId (..), TenantId (..))
import StudioMCP.Storage.ContentAddressed (ContentAddress (..))

-- | Unique version identifier
newtype VersionId = VersionId {unVersionId :: Text}
  deriving (Eq, Ord, Show)

instance ToJSON VersionId where
  toJSON (VersionId v) = toJSON v

instance FromJSON VersionId where
  parseJSON v = VersionId <$> parseJSON v

-- | Represents a single version of an artifact
data ArtifactVersion = ArtifactVersion
  { avVersionId :: VersionId,
    avArtifactId :: Text,
    avVersionNumber :: Int,
    avContentAddress :: ContentAddress,
    avContentSize :: Integer,
    avContentType :: Text,
    avCreatedAt :: UTCTime,
    avCreatedBy :: SubjectId,
    avTenantId :: TenantId,
    avPreviousVersion :: Maybe VersionId,
    avMetadata :: Map.Map Text Text,
    avImmutable :: Bool
  }
  deriving (Eq, Show)

instance ToJSON ArtifactVersion where
  toJSON ArtifactVersion {..} =
    object
      [ "versionId" .= avVersionId,
        "artifactId" .= avArtifactId,
        "versionNumber" .= avVersionNumber,
        "contentAddress" .= avContentAddress,
        "contentSize" .= avContentSize,
        "contentType" .= avContentType,
        "createdAt" .= avCreatedAt,
        "createdBy" .= avCreatedBy,
        "tenantId" .= avTenantId,
        "previousVersion" .= avPreviousVersion,
        "metadata" .= avMetadata,
        "immutable" .= avImmutable
      ]

instance FromJSON ArtifactVersion where
  parseJSON = withObject "ArtifactVersion" $ \obj ->
    ArtifactVersion
      <$> obj .: "versionId"
      <*> obj .: "artifactId"
      <*> obj .: "versionNumber"
      <*> obj .: "contentAddress"
      <*> obj .: "contentSize"
      <*> obj .: "contentType"
      <*> obj .: "createdAt"
      <*> obj .: "createdBy"
      <*> obj .: "tenantId"
      <*> obj .:? "previousVersion"
      <*> obj .: "metadata"
      <*> obj .: "immutable"

-- | Chain of versions for an artifact
data VersionChain = VersionChain
  { vcArtifactId :: Text,
    vcLatestVersion :: VersionId,
    vcVersionCount :: Int,
    vcCreatedAt :: UTCTime,
    vcUpdatedAt :: UTCTime
  }
  deriving (Eq, Show)

instance ToJSON VersionChain where
  toJSON VersionChain {..} =
    object
      [ "artifactId" .= vcArtifactId,
        "latestVersion" .= vcLatestVersion,
        "versionCount" .= vcVersionCount,
        "createdAt" .= vcCreatedAt,
        "updatedAt" .= vcUpdatedAt
      ]

-- | Rules for versioning behavior
data VersioningRule
  = -- | Always create new versions, never modify
    ImmutableVersions
  | -- | Allow modification within a time window
    MutableWithinWindow Int -- ^ Window in seconds
  | -- | Content-addressed deduplication
    ContentAddressedDedup
  deriving (Eq, Show)

instance ToJSON VersioningRule where
  toJSON ImmutableVersions = "immutable"
  toJSON (MutableWithinWindow secs) = object ["mutableWindow" .= secs]
  toJSON ContentAddressedDedup = "content-addressed"

-- | Versioning policy configuration
data VersioningPolicy = VersioningPolicy
  { -- | Primary versioning rule
    vpRule :: VersioningRule,
    -- | Maximum versions to retain per artifact
    vpMaxVersions :: Maybe Int,
    -- | Retention period for old versions (seconds)
    vpRetentionPeriod :: Maybe Int,
    -- | Auto-archive after N versions
    vpAutoArchiveAfter :: Maybe Int,
    -- | Require content address verification
    vpRequireContentAddressVerification :: Bool
  }
  deriving (Eq, Show)

-- | Default versioning policy (immutable)
defaultVersioningPolicy :: VersioningPolicy
defaultVersioningPolicy =
  VersioningPolicy
    { vpRule = ImmutableVersions,
      vpMaxVersions = Nothing, -- Unlimited
      vpRetentionPeriod = Nothing, -- Retain forever
      vpAutoArchiveAfter = Nothing,
      vpRequireContentAddressVerification = True
    }

-- | Immutability enforcement errors
data ImmutabilityError
  = -- | Attempted modification of immutable version
    VersionIsImmutable VersionId
  | -- | Content address mismatch on verification
    ContentAddressMismatch VersionId ContentAddress ContentAddress
  | -- | Version already exists
    VersionAlreadyExists VersionId
  | -- | Version not found
    VersionNotFound VersionId
  | -- | Artifact not found
    ArtifactVersionsNotFound Text
  | -- | Invalid version chain
    InvalidVersionChain Text Text
  deriving (Eq, Show)

-- | Get error code for immutability error
immutabilityErrorCode :: ImmutabilityError -> Text
immutabilityErrorCode (VersionIsImmutable _) = "version-immutable"
immutabilityErrorCode (ContentAddressMismatch _ _ _) = "content-address-mismatch"
immutabilityErrorCode (VersionAlreadyExists _) = "version-exists"
immutabilityErrorCode (VersionNotFound _) = "version-not-found"
immutabilityErrorCode (ArtifactVersionsNotFound _) = "artifact-versions-not-found"
immutabilityErrorCode (InvalidVersionChain _ _) = "invalid-version-chain"

-- | Version comparison result
data VersionComparison = VersionComparison
  { vcOlderVersion :: VersionId,
    vcNewerVersion :: VersionId,
    vcContentChanged :: Bool,
    vcSizeChange :: Integer,
    vcTimeDelta :: Int -- seconds
  }
  deriving (Eq, Show)

instance ToJSON VersionComparison where
  toJSON VersionComparison {..} =
    object
      [ "olderVersion" .= vcOlderVersion,
        "newerVersion" .= vcNewerVersion,
        "contentChanged" .= vcContentChanged,
        "sizeChange" .= vcSizeChange,
        "timeDelta" .= vcTimeDelta
      ]

-- | Internal state for versioning service
data VersioningState = VersioningState
  { vsVersions :: Map.Map VersionId ArtifactVersion,
    vsChains :: Map.Map Text VersionChain,
    vsArtifactVersions :: Map.Map Text [VersionId]
  }

-- | Versioning service
data VersioningService = VersioningService
  { vsPolicy :: VersioningPolicy,
    vsState :: TVar VersioningState
  }

-- | Create a new versioning service
newVersioningService :: VersioningPolicy -> IO VersioningService
newVersioningService policy = do
  stateVar <-
    newTVarIO
      VersioningState
        { vsVersions = Map.empty,
          vsChains = Map.empty,
          vsArtifactVersions = Map.empty
        }
  pure
    VersioningService
      { vsPolicy = policy,
        vsState = stateVar
      }

-- | Create the initial version of an artifact
createInitialVersion ::
  VersioningService ->
  Text ->
  ContentAddress ->
  Integer ->
  Text ->
  SubjectId ->
  TenantId ->
  Map.Map Text Text ->
  IO (Either ImmutabilityError ArtifactVersion)
createInitialVersion service artifactId contentAddr contentSize contentType createdBy tenantId metadata = do
  now <- getCurrentTime
  let versionId = VersionId (artifactId <> "-v1")
      version =
        ArtifactVersion
          { avVersionId = versionId,
            avArtifactId = artifactId,
            avVersionNumber = 1,
            avContentAddress = contentAddr,
            avContentSize = contentSize,
            avContentType = contentType,
            avCreatedAt = now,
            avCreatedBy = createdBy,
            avTenantId = tenantId,
            avPreviousVersion = Nothing,
            avMetadata = metadata,
            avImmutable = vpRule (vsPolicy service) == ImmutableVersions
          }
      chain =
        VersionChain
          { vcArtifactId = artifactId,
            vcLatestVersion = versionId,
            vcVersionCount = 1,
            vcCreatedAt = now,
            vcUpdatedAt = now
          }
  state <- readTVarIO (vsState service)
  if Map.member artifactId (vsChains state)
    then pure $ Left $ VersionAlreadyExists versionId
    else do
      atomically $ modifyTVar' (vsState service) $ \s ->
        s
          { vsVersions = Map.insert versionId version (vsVersions s),
            vsChains = Map.insert artifactId chain (vsChains s),
            vsArtifactVersions = Map.insert artifactId [versionId] (vsArtifactVersions s)
          }
      pure $ Right version

-- | Create a new version of an existing artifact
createNewVersion ::
  VersioningService ->
  Text ->
  ContentAddress ->
  Integer ->
  Text ->
  SubjectId ->
  Map.Map Text Text ->
  IO (Either ImmutabilityError ArtifactVersion)
createNewVersion service artifactId contentAddr contentSize contentType createdBy metadata = do
  state <- readTVarIO (vsState service)
  case Map.lookup artifactId (vsChains state) of
    Nothing -> pure $ Left $ ArtifactVersionsNotFound artifactId
    Just chain -> do
      now <- getCurrentTime
      let newVersionNum = vcVersionCount chain + 1
          versionId = VersionId (artifactId <> "-v" <> T.pack (show newVersionNum))
          previousVersionId = vcLatestVersion chain
          existingVersions = Map.findWithDefault [] artifactId (vsArtifactVersions state)
      case Map.lookup previousVersionId (vsVersions state) of
        Nothing -> pure $ Left $ VersionNotFound previousVersionId
        Just prevVersion -> do
          let version =
                ArtifactVersion
                  { avVersionId = versionId,
                    avArtifactId = artifactId,
                    avVersionNumber = newVersionNum,
                    avContentAddress = contentAddr,
                    avContentSize = contentSize,
                    avContentType = contentType,
                    avCreatedAt = now,
                    avCreatedBy = createdBy,
                    avTenantId = avTenantId prevVersion,
                    avPreviousVersion = Just previousVersionId,
                    avMetadata = metadata,
                    avImmutable = vpRule (vsPolicy service) == ImmutableVersions
                  }
              updatedChain =
                chain
                  { vcLatestVersion = versionId,
                    vcVersionCount = newVersionNum,
                    vcUpdatedAt = now
                  }
          atomically $ modifyTVar' (vsState service) $ \s ->
            s
              { vsVersions = Map.insert versionId version (vsVersions s),
                vsChains = Map.insert artifactId updatedChain (vsChains s),
                vsArtifactVersions =
                  Map.insert artifactId (versionId : existingVersions) (vsArtifactVersions s)
              }
          pure $ Right version

-- | Get a specific version
getVersion ::
  VersioningService ->
  VersionId ->
  IO (Either ImmutabilityError ArtifactVersion)
getVersion service versionId = do
  state <- readTVarIO (vsState service)
  case Map.lookup versionId (vsVersions state) of
    Nothing -> pure $ Left $ VersionNotFound versionId
    Just version -> pure $ Right version

-- | Get the latest version of an artifact
getLatestVersion ::
  VersioningService ->
  Text ->
  IO (Either ImmutabilityError ArtifactVersion)
getLatestVersion service artifactId = do
  state <- readTVarIO (vsState service)
  case Map.lookup artifactId (vsChains state) of
    Nothing -> pure $ Left $ ArtifactVersionsNotFound artifactId
    Just chain -> getVersion service (vcLatestVersion chain)

-- | List all versions of an artifact
listVersions ::
  VersioningService ->
  Text ->
  IO (Either ImmutabilityError [ArtifactVersion])
listVersions service artifactId = do
  state <- readTVarIO (vsState service)
  case Map.lookup artifactId (vsArtifactVersions state) of
    Nothing -> pure $ Left $ ArtifactVersionsNotFound artifactId
    Just versionIds -> do
      let versions = mapMaybe (`Map.lookup` vsVersions state) versionIds
      pure $ Right versions
  where
    mapMaybe :: (a -> Maybe b) -> [a] -> [b]
    mapMaybe _ [] = []
    mapMaybe f (x : xs) = case f x of
      Nothing -> mapMaybe f xs
      Just y -> y : mapMaybe f xs

-- | Validate that immutability rules are not violated
validateImmutability ::
  VersioningService ->
  VersionId ->
  ContentAddress ->
  IO (Either ImmutabilityError ())
validateImmutability service versionId expectedAddr = do
  versionResult <- getVersion service versionId
  case versionResult of
    Left err -> pure $ Left err
    Right version
      | not (avImmutable version) ->
          pure $ Right ()
      | avContentAddress version /= expectedAddr ->
          pure $ Left $ ContentAddressMismatch versionId expectedAddr (avContentAddress version)
      | otherwise ->
          pure $ Right ()

-- | Get metadata for a version
getVersionMetadata ::
  VersioningService ->
  VersionId ->
  IO (Either ImmutabilityError (Map.Map Text Text))
getVersionMetadata service versionId = do
  versionResult <- getVersion service versionId
  case versionResult of
    Left err -> pure $ Left err
    Right version -> pure $ Right (avMetadata version)

-- | Compare two versions
compareVersions ::
  VersioningService ->
  VersionId ->
  VersionId ->
  IO (Either ImmutabilityError VersionComparison)
compareVersions service olderId newerId = do
  olderResult <- getVersion service olderId
  newerResult <- getVersion service newerId
  case (olderResult, newerResult) of
    (Left err, _) -> pure $ Left err
    (_, Left err) -> pure $ Left err
    (Right older, Right newer)
      | avArtifactId older /= avArtifactId newer ->
          pure $ Left $ InvalidVersionChain (avArtifactId older) (avArtifactId newer)
      | otherwise ->
          pure $
            Right
              VersionComparison
                { vcOlderVersion = olderId,
                  vcNewerVersion = newerId,
                  vcContentChanged = avContentAddress older /= avContentAddress newer,
                  vcSizeChange = avContentSize newer - avContentSize older,
                  vcTimeDelta = round (abs (diffUTCTime (avCreatedAt newer) (avCreatedAt older)))
                }
