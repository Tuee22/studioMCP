{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module StudioMCP.MCP.Resources
  ( -- * Resource Catalog
    ResourceCatalog (..),
    newResourceCatalog,
    newResourceCatalogWithStorage,
    newResourceCatalogWithRuntime,
    listResources,
    readResource,

    -- * Resource URIs
    ResourceUri (..),
    parseResourceUri,
    buildResourceUri,

    -- * Resource Types
    ResourceType (..),
    allResourceTypes,

    -- * Resource Errors
    ResourceError (..),
    resourceErrorCode,

    -- * Resource Authorization
    resourceRequiredScopes,

    -- * Resource Templates
    resourceTemplates,
  )
where

import Control.Concurrent.STM (TVar, atomically, modifyTVar', newTVarIO)
import Data.Aeson
  ( object,
    (.=),
  )
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import Data.Time (UTCTime, getCurrentTime)
import StudioMCP.Auth.Types (TenantId (..))
import StudioMCP.DAG.Summary (RunId (..))
import StudioMCP.MCP.Tools
  ( ToolCatalog,
    WorkflowRunRecord (..),
    listWorkflowRunsForTenant,
  )
import StudioMCP.MCP.Protocol.Types
  ( ReadResourceParams (..),
    ReadResourceResult (..),
    ResourceContent (..),
    ResourceDefinition (..),
  )
import StudioMCP.Observability.Quotas
  ( QuotaConfig (..),
    QuotaService,
    TenantQuotaUsage (..),
    defaultQuotaConfig,
    getTenantQuotaUsage,
  )
import StudioMCP.Storage.Governance
  ( ArtifactState (..),
    GovernanceService,
    getArtifactState,
  )
import StudioMCP.Storage.Keys (manifestRefForRun, summaryRefForRun)
import StudioMCP.Storage.MinIO (MinIOConfig, readManifest, readSummary)
import StudioMCP.Storage.TenantStorage
  ( TenantArtifact (..),
    TenantStorageBackend (..),
    TenantStorageService,
    defaultTenantStorageConfig,
    getTenantArtifact,
    tscDefaultBackend,
    tscMaxArtifactSize,
    tssConfig,
  )

-- | Resource types available in the catalog
data ResourceType
  = SummaryResource
  | ManifestResource
  | TenantMetadataResource
  | QuotaResource
  | ArtifactMetadataResource
  | RunHistoryResource
  deriving (Eq, Ord, Show)

-- | All available resource types
allResourceTypes :: [ResourceType]
allResourceTypes =
  [ SummaryResource,
    ManifestResource,
    TenantMetadataResource,
    QuotaResource,
    ArtifactMetadataResource,
    RunHistoryResource
  ]

-- | Resource URI structure
data ResourceUri = ResourceUri
  { ruScheme :: Text,
    ruResourceType :: ResourceType,
    ruIdentifier :: Maybe Text
  }
  deriving (Eq, Show)

-- | Resource errors
data ResourceError
  = ResourceNotFound Text
  | InvalidResourceUri Text
  | ResourceAccessDenied Text
  | ResourceReadFailed Text
  deriving (Eq, Show)

-- | Get error code for resource errors
resourceErrorCode :: ResourceError -> Text
resourceErrorCode (ResourceNotFound _) = "resource-not-found"
resourceErrorCode (InvalidResourceUri _) = "invalid-resource-uri"
resourceErrorCode (ResourceAccessDenied _) = "access-denied"
resourceErrorCode (ResourceReadFailed _) = "read-failed"

-- | Internal state for resource catalog
data ResourceCatalogState = ResourceCatalogState
  { rcsAccessCount :: Map.Map ResourceType Int,
    rcsLastAccess :: Map.Map ResourceType UTCTime
  }

-- | Resource catalog service
data ResourceCatalog = ResourceCatalog
  { rcState :: TVar ResourceCatalogState,
    rcMinIOConfig :: Maybe MinIOConfig,
    rcTenantStorage :: Maybe TenantStorageService,
    rcGovernance :: Maybe GovernanceService,
    rcToolCatalog :: Maybe ToolCatalog,
    rcQuotaService :: Maybe QuotaService
  }

-- | Create a new resource catalog without runtime storage/executor backends.
newResourceCatalog :: IO ResourceCatalog
newResourceCatalog = do
  stateVar <-
    newTVarIO
      ResourceCatalogState
        { rcsAccessCount = Map.empty,
          rcsLastAccess = Map.empty
        }
  pure
    ResourceCatalog
      { rcState = stateVar,
        rcMinIOConfig = Nothing,
        rcTenantStorage = Nothing,
        rcGovernance = Nothing,
        rcToolCatalog = Nothing,
        rcQuotaService = Nothing
      }

-- | Create a new resource catalog with MinIO storage backend
newResourceCatalogWithStorage :: MinIOConfig -> IO ResourceCatalog
newResourceCatalogWithStorage minioConfig = do
  stateVar <-
    newTVarIO
      ResourceCatalogState
        { rcsAccessCount = Map.empty,
          rcsLastAccess = Map.empty
        }
  pure
    ResourceCatalog
      { rcState = stateVar,
        rcMinIOConfig = Just minioConfig,
        rcTenantStorage = Nothing,
        rcGovernance = Nothing,
        rcToolCatalog = Nothing,
        rcQuotaService = Nothing
      }

newResourceCatalogWithRuntime ::
  MinIOConfig ->
  TenantStorageService ->
  GovernanceService ->
  ToolCatalog ->
  QuotaService ->
  IO ResourceCatalog
newResourceCatalogWithRuntime minioConfig tenantStorage governance toolCatalog quotaService = do
  stateVar <-
    newTVarIO
      ResourceCatalogState
        { rcsAccessCount = Map.empty,
          rcsLastAccess = Map.empty
        }
  pure
    ResourceCatalog
      { rcState = stateVar,
        rcMinIOConfig = Just minioConfig,
        rcTenantStorage = Just tenantStorage,
        rcGovernance = Just governance,
        rcToolCatalog = Just toolCatalog,
        rcQuotaService = Just quotaService
      }

-- | List all available resources
listResources :: ResourceCatalog -> TenantId -> IO [ResourceDefinition]
listResources _catalog (TenantId tenantIdText) =
  pure
    [ ResourceDefinition
        { rdUri = "studiomcp://summaries/{run_id}",
          rdName = "Workflow Run Summary",
          rdDescription = Just "Summary of a completed or running workflow execution",
          rdMimeType = Just "application/json",
          rdRequiredScopes = ["workflow:read"]
        },
      ResourceDefinition
        { rdUri = "studiomcp://manifests/{run_id}",
          rdName = "Workflow Run Manifest",
          rdDescription = Just "Full manifest with artifact references and memo keys",
          rdMimeType = Just "application/json",
          rdRequiredScopes = ["workflow:read"]
        },
      ResourceDefinition
        { rdUri = "studiomcp://metadata/tenant/" <> tenantIdText,
          rdName = "Tenant Metadata",
          rdDescription = Just "Current tenant configuration and limits",
          rdMimeType = Just "application/json",
          rdRequiredScopes = ["tenant:read"]
        },
      ResourceDefinition
        { rdUri = "studiomcp://metadata/quotas",
          rdName = "Quota Information",
          rdDescription = Just "Current resource quotas and usage",
          rdMimeType = Just "application/json",
          rdRequiredScopes = ["tenant:read"]
        },
      ResourceDefinition
        { rdUri = "studiomcp://artifacts/{artifact_id}",
          rdName = "Artifact Metadata",
          rdDescription = Just "Metadata for a specific artifact",
          rdMimeType = Just "application/json",
          rdRequiredScopes = ["artifact:read"]
        },
      ResourceDefinition
        { rdUri = "studiomcp://history/runs",
          rdName = "Run History",
          rdDescription = Just "History of workflow runs for the tenant",
          rdMimeType = Just "application/json",
          rdRequiredScopes = ["workflow:read"]
        }
    ]

-- | Read a resource by URI
readResource ::
  ResourceCatalog ->
  TenantId ->
  ReadResourceParams ->
  IO (Either ResourceError ReadResourceResult)
readResource catalog tenantId params = do
  let uri = rrpUri params
  case parseResourceUri uri of
    Nothing -> pure $ Left $ InvalidResourceUri uri
    Just resourceUri -> do
      now <- getCurrentTime
      let resourceType = ruResourceType resourceUri
      atomically $ modifyTVar' (rcState catalog) $ \s ->
        s
          { rcsAccessCount = Map.insertWith (+) resourceType 1 (rcsAccessCount s),
            rcsLastAccess = Map.insert resourceType now (rcsLastAccess s)
          }
      readResourceByType catalog tenantId resourceUri

-- | Parse a resource URI
parseResourceUri :: Text -> Maybe ResourceUri
parseResourceUri uri
  | "studiomcp://summaries/" `T.isPrefixOf` uri =
      Just
        ResourceUri
          { ruScheme = "studiomcp",
            ruResourceType = SummaryResource,
            ruIdentifier = Just $ T.drop (T.length "studiomcp://summaries/") uri
          }
  | "studiomcp://manifests/" `T.isPrefixOf` uri =
      Just
        ResourceUri
          { ruScheme = "studiomcp",
            ruResourceType = ManifestResource,
            ruIdentifier = Just $ T.drop (T.length "studiomcp://manifests/") uri
          }
  | "studiomcp://metadata/tenant/" `T.isPrefixOf` uri =
      Just
        ResourceUri
          { ruScheme = "studiomcp",
            ruResourceType = TenantMetadataResource,
            ruIdentifier = Just $ T.drop (T.length "studiomcp://metadata/tenant/") uri
          }
  | uri == "studiomcp://metadata/quotas" =
      Just
        ResourceUri
          { ruScheme = "studiomcp",
            ruResourceType = QuotaResource,
            ruIdentifier = Nothing
          }
  | "studiomcp://artifacts/" `T.isPrefixOf` uri =
      Just
        ResourceUri
          { ruScheme = "studiomcp",
            ruResourceType = ArtifactMetadataResource,
            ruIdentifier = Just $ T.drop (T.length "studiomcp://artifacts/") uri
          }
  | uri == "studiomcp://history/runs" =
      Just
        ResourceUri
          { ruScheme = "studiomcp",
            ruResourceType = RunHistoryResource,
            ruIdentifier = Nothing
          }
  | otherwise = Nothing

-- | Build a resource URI from components
buildResourceUri :: ResourceType -> Maybe Text -> Text
buildResourceUri SummaryResource (Just runId) = "studiomcp://summaries/" <> runId
buildResourceUri SummaryResource Nothing = "studiomcp://summaries/{run_id}"
buildResourceUri ManifestResource (Just runId) = "studiomcp://manifests/" <> runId
buildResourceUri ManifestResource Nothing = "studiomcp://manifests/{run_id}"
buildResourceUri TenantMetadataResource (Just tenantId) = "studiomcp://metadata/tenant/" <> tenantId
buildResourceUri TenantMetadataResource Nothing = "studiomcp://metadata/tenant/{tenant_id}"
buildResourceUri QuotaResource _ = "studiomcp://metadata/quotas"
buildResourceUri ArtifactMetadataResource (Just artifactId) = "studiomcp://artifacts/" <> artifactId
buildResourceUri ArtifactMetadataResource Nothing = "studiomcp://artifacts/{artifact_id}"
buildResourceUri RunHistoryResource _ = "studiomcp://history/runs"

-- | Read resource by type
readResourceByType ::
  ResourceCatalog ->
  TenantId ->
  ResourceUri ->
  IO (Either ResourceError ReadResourceResult)
readResourceByType catalog tenantId resourceUri =
  case ruResourceType resourceUri of
    SummaryResource -> readSummaryResource catalog tenantId (ruIdentifier resourceUri)
    ManifestResource -> readManifestResource catalog tenantId (ruIdentifier resourceUri)
    TenantMetadataResource -> readTenantMetadataResource catalog tenantId
    QuotaResource -> readQuotaResource catalog tenantId
    ArtifactMetadataResource -> readArtifactMetadataResource catalog tenantId (ruIdentifier resourceUri)
    RunHistoryResource -> readRunHistoryResource catalog tenantId

-- | Read summary resource
readSummaryResource :: ResourceCatalog -> TenantId -> Maybe Text -> IO (Either ResourceError ReadResourceResult)
readSummaryResource _catalog _tenantId Nothing =
  pure $ Left $ InvalidResourceUri "Missing run_id in summary URI"
readSummaryResource catalog (TenantId tenantIdText) (Just runIdText) = do
  let runId = RunId runIdText
      summaryRef = summaryRefForRun runId
  case rcMinIOConfig catalog of
    Nothing -> do
      -- Mock data when no MinIO config
      let content =
            Aeson.encode $
              object
                [ "run_id" .= runIdText,
                  "tenant_id" .= tenantIdText,
                  "status" .= ("completed" :: Text),
                  "started_at" .= ("2024-01-15T10:00:00Z" :: Text),
                  "completed_at" .= ("2024-01-15T10:05:00Z" :: Text),
                  "nodes_total" .= (5 :: Int),
                  "nodes_succeeded" .= (5 :: Int),
                  "nodes_failed" .= (0 :: Int)
                ]
      pure $
        Right
          ReadResourceResult
            { rrrContents =
                [ ResourceContent
                    { rcUri = "studiomcp://summaries/" <> runIdText,
                      rcMimeType = Just "application/json",
                      rcText = Just $ T.decodeUtf8 $ LBS.toStrict content,
                      rcBlob = Nothing
                    }
                ]
            }
    Just minioConfig -> do
      -- Fetch from actual MinIO storage
      result <- readSummary minioConfig summaryRef
      case result of
        Left failureDetail ->
          pure $ Left $ ResourceReadFailed $ T.pack $ show failureDetail
        Right summary ->
          let content = Aeson.encode summary
           in pure $
                Right
                  ReadResourceResult
                    { rrrContents =
                        [ ResourceContent
                            { rcUri = "studiomcp://summaries/" <> runIdText,
                              rcMimeType = Just "application/json",
                              rcText = Just $ T.decodeUtf8 $ LBS.toStrict content,
                              rcBlob = Nothing
                            }
                        ]
                    }

-- | Read manifest resource
readManifestResource :: ResourceCatalog -> TenantId -> Maybe Text -> IO (Either ResourceError ReadResourceResult)
readManifestResource _catalog _tenantId Nothing =
  pure $ Left $ InvalidResourceUri "Missing run_id in manifest URI"
readManifestResource catalog (TenantId tenantIdText) (Just runIdText) = do
  let runId = RunId runIdText
      manifestRef = manifestRefForRun runId
  case rcMinIOConfig catalog of
    Nothing -> do
      -- Mock data when no MinIO config
      let content =
            Aeson.encode $
              object
                [ "run_id" .= runIdText,
                  "tenant_id" .= tenantIdText,
                  "dag_spec_hash" .= ("sha256:abc123..." :: Text),
                  "artifacts"
                    .= [ object
                           [ "artifact_id" .= ("artifact-001" :: Text),
                             "content_address" .= ("sha256:def456..." :: Text)
                           ]
                       ],
                  "memo_keys"
                    .= [ object
                           [ "node_id" .= ("transcode-1" :: Text),
                             "memo_key" .= ("memo-key-123" :: Text)
                           ]
                       ]
                ]
      pure $
        Right
          ReadResourceResult
            { rrrContents =
                [ ResourceContent
                    { rcUri = "studiomcp://manifests/" <> runIdText,
                      rcMimeType = Just "application/json",
                      rcText = Just $ T.decodeUtf8 $ LBS.toStrict content,
                      rcBlob = Nothing
                    }
                ]
            }
    Just minioConfig -> do
      -- Fetch from actual MinIO storage
      result <- readManifest minioConfig manifestRef
      case result of
        Left failureDetail ->
          pure $ Left $ ResourceReadFailed $ T.pack $ show failureDetail
        Right manifest ->
          let content = Aeson.encode manifest
           in pure $
                Right
                  ReadResourceResult
                    { rrrContents =
                        [ ResourceContent
                            { rcUri = "studiomcp://manifests/" <> runIdText,
                              rcMimeType = Just "application/json",
                              rcText = Just $ T.decodeUtf8 $ LBS.toStrict content,
                              rcBlob = Nothing
                            }
                        ]
                    }

-- | Read tenant metadata resource
readTenantMetadataResource :: ResourceCatalog -> TenantId -> IO (Either ResourceError ReadResourceResult)
readTenantMetadataResource catalog (TenantId tenantIdText) = do
  let (storageBackend, maxArtifactSize) =
        case rcTenantStorage catalog of
          Just tenantStorage ->
            ( showBackend (tscDefaultBackend (tssConfig tenantStorage)),
              tscMaxArtifactSize (tssConfig tenantStorage)
            )
          Nothing ->
            ( "platform-minio",
              tscMaxArtifactSize defaultTenantStorageConfig
            )
  let content =
        Aeson.encode $
          object
            [ "tenant_id" .= tenantIdText,
              "display_name" .= ("Tenant " <> tenantIdText),
              "storage_backend" .= storageBackend,
              "created_at" .= ("2024-01-01T00:00:00Z" :: Text),
              "features"
                .= object
                  [ "max_concurrent_runs" .= (10 :: Int),
                    "max_artifact_size_bytes" .= maxArtifactSize,
                    "retention_days" .= (90 :: Int)
                  ]
            ]
  pure $
    Right
      ReadResourceResult
        { rrrContents =
                [ ResourceContent
                    { rcUri = "studiomcp://metadata/tenant/" <> tenantIdText,
                      rcMimeType = Just "application/json",
                      rcText = Just $ jsonText content,
                      rcBlob = Nothing
                    }
                ]
        }

-- | Read quota resource
readQuotaResource :: ResourceCatalog -> TenantId -> IO (Either ResourceError ReadResourceResult)
readQuotaResource catalog tenantId@(TenantId tenantIdText) = do
  usage <-
    case rcQuotaService catalog of
      Just quotaService -> getTenantQuotaUsage quotaService tenantId
      Nothing -> pure emptyTenantUsage
  let storageLimit = qcStorageLimit defaultQuotaConfig
      requestLimit = qcRequestsPerMinuteLimit defaultQuotaConfig
      uploadLimit = qcUploadsPerHourLimit defaultQuotaConfig
      concurrentRunsLimit = qcConcurrentRunsLimit defaultQuotaConfig
      percentageUsed =
        if storageLimit == 0
          then (0 :: Double)
          else fromIntegral (tquStorageUsed usage) * 100 / fromIntegral storageLimit
  let content =
        Aeson.encode $
          object
            [ "tenant_id" .= tenantIdText,
              "storage"
                .= object
                  [ "limit_bytes" .= storageLimit,
                    "used_bytes" .= tquStorageUsed usage,
                    "percentage_used" .= percentageUsed
                  ],
              "compute"
                .= object
                  [ "max_concurrent_runs" .= concurrentRunsLimit,
                    "active_runs" .= tquConcurrentRuns usage
                  ],
              "rate_limits"
                .= object
                  [ "requests_per_minute" .= requestLimit,
                    "requests_used" .= tquRequestsThisMinute usage,
                    "uploads_per_hour" .= uploadLimit,
                    "uploads_used" .= tquUploadsThisHour usage
                  ]
            ]
  pure $
    Right
      ReadResourceResult
        { rrrContents =
                [ ResourceContent
                    { rcUri = "studiomcp://metadata/quotas",
                      rcMimeType = Just "application/json",
                      rcText = Just $ jsonText content,
                      rcBlob = Nothing
                    }
                ]
        }

-- | Read artifact metadata resource
readArtifactMetadataResource :: ResourceCatalog -> TenantId -> Maybe Text -> IO (Either ResourceError ReadResourceResult)
readArtifactMetadataResource _catalog _tenantId Nothing =
  pure $ Left $ InvalidResourceUri "Missing artifact_id in artifact URI"
readArtifactMetadataResource catalog tenantId@(TenantId tenantIdText) (Just artifactId) =
  case rcTenantStorage catalog of
    Nothing -> pure $ Left $ ResourceReadFailed "Artifact storage backend is not configured"
    Just tenantStorage -> do
      artifactResult <- getTenantArtifact tenantStorage tenantId artifactId
      case artifactResult of
        Left _ -> pure $ Left $ ResourceNotFound artifactId
        Right artifact -> do
          artifactState <-
            case rcGovernance catalog of
              Just governance -> getArtifactState governance artifactId
              Nothing -> pure Active
          let content =
                Aeson.encode $
                  object
                    [ "artifact_id" .= artifactId,
                      "tenant_id" .= tenantIdText,
                      "content_type" .= taContentType artifact,
                      "file_name" .= taFileName artifact,
                      "file_size" .= taFileSize artifact,
                      "version" .= taVersion artifact,
                      "state" .= renderArtifactState artifactState,
                      "created_at" .= taCreatedAt artifact,
                      "content_address" .= taContentAddress artifact
                    ]
          pure $
            Right
              ReadResourceResult
                { rrrContents =
                        [ ResourceContent
                            { rcUri = "studiomcp://artifacts/" <> artifactId,
                              rcMimeType = Just "application/json",
                              rcText = Just $ jsonText content,
                              rcBlob = Nothing
                            }
                        ]
                }

-- | Read run history resource
readRunHistoryResource :: ResourceCatalog -> TenantId -> IO (Either ResourceError ReadResourceResult)
readRunHistoryResource catalog tenantId@(TenantId tenantIdText) = do
  runs <-
    case rcToolCatalog catalog of
      Just toolCatalog -> listWorkflowRunsForTenant toolCatalog tenantId
      Nothing -> pure []
  let content =
        Aeson.encode $
          object
            [ "tenant_id" .= tenantIdText,
              "runs"
                .= map
                  (\runRecord ->
                    object
                      [ "run_id" .= wrrRunId runRecord,
                        "status" .= wrrStatus runRecord,
                        "started_at" .= wrrSubmittedAt runRecord,
                        "completed_at" .= wrrCompletedAt runRecord
                      ])
                  runs,
              "total_count" .= length runs
            ]
  pure $
    Right
      ReadResourceResult
        { rrrContents =
                [ ResourceContent
                    { rcUri = "studiomcp://history/runs",
                      rcMimeType = Just "application/json",
                      rcText = Just $ jsonText content,
                      rcBlob = Nothing
                    }
                ]
        }

jsonText :: LBS.ByteString -> Text
jsonText = T.decodeUtf8 . LBS.toStrict

emptyTenantUsage :: TenantQuotaUsage
emptyTenantUsage =
  TenantQuotaUsage
    { tquStorageUsed = 0,
      tquConcurrentRuns = 0,
      tquRequestsThisMinute = 0,
      tquUploadsThisHour = 0,
      tquToolCallsThisMinute = 0
    }

showBackend :: TenantStorageBackend -> Text
showBackend PlatformMinIO = "platform-minio"

renderArtifactState :: ArtifactState -> Text
renderArtifactState Active = "active"
renderArtifactState Hidden = "hidden"
renderArtifactState Archived = "archived"
renderArtifactState (Superseded newArtifactId) = "superseded by " <> newArtifactId

-- | Get required scopes for a resource type
resourceRequiredScopes :: ResourceType -> [Text]
resourceRequiredScopes SummaryResource = ["workflow:read"]
resourceRequiredScopes ManifestResource = ["workflow:read"]
resourceRequiredScopes TenantMetadataResource = ["tenant:read"]
resourceRequiredScopes QuotaResource = ["tenant:read"]
resourceRequiredScopes ArtifactMetadataResource = ["artifact:read"]
resourceRequiredScopes RunHistoryResource = ["workflow:read"]

-- | Resource templates for documentation
resourceTemplates :: [(Text, Text, Text)]
resourceTemplates =
  [ ("studiomcp://summaries/{run_id}", "Workflow summary", "workflow:read"),
    ("studiomcp://manifests/{run_id}", "Workflow manifest", "workflow:read"),
    ("studiomcp://metadata/tenant/{tenant_id}", "Tenant metadata", "tenant:read"),
    ("studiomcp://metadata/quotas", "Quota information", "tenant:read"),
    ("studiomcp://artifacts/{artifact_id}", "Artifact metadata", "artifact:read"),
    ("studiomcp://history/runs", "Run history", "workflow:read")
  ]
