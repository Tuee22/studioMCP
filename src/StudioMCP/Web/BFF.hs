{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module StudioMCP.Web.BFF
  ( -- * BFF Service
    BFFService (..),
    BFFConfig (..),
    defaultBFFConfig,
    newBFFService,
    newBFFServiceWithRuntime,

    -- * Session Management
    createWebSession,
    getWebSession,
    refreshWebSession,
    invalidateWebSession,

    -- * Upload Operations
    requestUpload,
    confirmUpload,

    -- * Download Operations
    requestDownload,

    -- * Chat Operations
    sendChatMessage,

    -- * Run Operations
    submitRun,
    getRunStatus,

    -- * Errors
    BFFError (..),
    bffErrorToHttpStatus,
  )
where

import Control.Concurrent.STM (TVar, atomically, newTVarIO, readTVarIO, writeTVar)
import Data.Aeson (FromJSON, ToJSON, object, withObject, (.:), (.:?), (.=))
import qualified Data.Aeson as Aeson
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time (NominalDiffTime, UTCTime, addUTCTime, getCurrentTime)
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import GHC.Generics (Generic)
import Network.HTTP.Client (Manager, defaultManagerSettings, newManager)
import Network.HTTP.Types (Status, status400, status401, status403, status404, status500, status502)
import StudioMCP.Auth.Types (SubjectId (..), TenantId (..))
import StudioMCP.DAG.Summary (RunId (..))
import StudioMCP.DAG.Types (DagSpec)
import StudioMCP.Inference.Guardrails (applyGuardrails)
import StudioMCP.Inference.ReferenceModel
  ( ReferenceModelConfig,
    requestReferenceAdvice,
  )
import StudioMCP.MCP.Protocol.Types (CallToolParams (..), CallToolResult (..), ToolContent (..))
import StudioMCP.MCP.Tools
  ( ToolCatalog,
    ToolError (..),
    ToolResult (..),
    callTool,
  )
import StudioMCP.Result.Failure (FailureDetail (..))
import StudioMCP.Storage.TenantStorage
  ( TenantArtifact (..),
    PresignedUrl (..),
    TenantStorageService,
    createTenantArtifact,
    defaultTenantStorageConfig,
    generateDownloadUrl,
    generateUploadUrl,
    getTenantArtifact,
    newTenantStorageService,
  )
import qualified StudioMCP.Storage.TenantStorage as TenantStorage
import StudioMCP.Web.Types

-- | BFF configuration
data BFFConfig = BFFConfig
  { bffMcpEndpoint :: Text,
    bffSessionTtlSeconds :: Int,
    bffUploadTtlSeconds :: Int,
    bffDownloadTtlSeconds :: Int,
    bffMaxUploadSize :: Integer,
    bffAllowedContentTypes :: [Text]
  }
  deriving (Eq, Show, Generic)

instance ToJSON BFFConfig
instance FromJSON BFFConfig

-- | Default BFF configuration
defaultBFFConfig :: BFFConfig
defaultBFFConfig =
  BFFConfig
    { bffMcpEndpoint = "http://localhost:3000",
      bffSessionTtlSeconds = 3600, -- 1 hour
      bffUploadTtlSeconds = 900, -- 15 minutes
      bffDownloadTtlSeconds = 300, -- 5 minutes
      bffMaxUploadSize = 10 * 1024 * 1024 * 1024, -- 10 GB
      bffAllowedContentTypes =
        [ "video/mp4",
          "video/quicktime",
          "video/x-msvideo",
          "video/webm",
          "audio/mpeg",
          "audio/wav",
          "audio/flac",
          "image/jpeg",
          "image/png",
          "image/tiff"
        ]
    }

-- | BFF service errors
data BFFError
  = -- | Session not found
    SessionNotFound WebSessionId
  | -- | Session expired
    SessionExpired WebSessionId
  | -- | Invalid credentials
    InvalidCredentials Text
  | -- | Unauthorized
    Unauthorized Text
  | -- | Forbidden
    Forbidden Text
  | -- | Artifact not found
    ArtifactNotFound Text
  | -- | Invalid request
    InvalidRequest Text
  | -- | MCP service error
    McpServiceError Text
  | -- | Internal error
    InternalError Text
  deriving (Eq, Show, Generic)

instance ToJSON BFFError

-- | Map BFF error to HTTP status
bffErrorToHttpStatus :: BFFError -> Status
bffErrorToHttpStatus (SessionNotFound _) = status401
bffErrorToHttpStatus (SessionExpired _) = status401
bffErrorToHttpStatus (InvalidCredentials _) = status401
bffErrorToHttpStatus (Unauthorized _) = status401
bffErrorToHttpStatus (Forbidden _) = status403
bffErrorToHttpStatus (ArtifactNotFound _) = status404
bffErrorToHttpStatus (InvalidRequest _) = status400
bffErrorToHttpStatus (McpServiceError _) = status502
bffErrorToHttpStatus (InternalError _) = status500

-- | BFF service state
data BFFService = BFFService
  { bffConfig :: BFFConfig,
    -- | In-memory session store (for development)
    bffSessions :: TVar (Map WebSessionId WebSession),
    -- | Pending uploads tracking
    bffPendingUploads :: TVar (Map Text PendingUpload),
    -- | Run status cache
    bffRunCache :: TVar (Map RunId RunStatusResponse),
    -- | Tenant-scoped artifact store backing upload/download flows
    bffTenantStorage :: TenantStorageService,
    -- | Shared workflow tool catalog used for MCP-backed run orchestration.
    bffToolCatalog :: Maybe ToolCatalog,
    -- | Inference manager + model config for chat.
    bffInferenceManager :: Maybe Manager,
    bffReferenceModelConfig :: Maybe ReferenceModelConfig
  }

-- | Pending upload record
data PendingUpload = PendingUpload
  { puArtifactId :: Text,
    puTenantId :: Text,
    puFileName :: Text,
    puContentType :: Text,
    puFileSize :: Integer,
    puCreatedAt :: UTCTime,
    puExpiresAt :: UTCTime
  }
  deriving (Eq, Show, Generic)

data WorkflowToolPayload = WorkflowToolPayload
  { wtpRunId :: RunId,
    wtpStatus :: Text,
    wtpSubmittedAt :: UTCTime,
    wtpCompletedAt :: Maybe UTCTime
  }

instance FromJSON WorkflowToolPayload where
  parseJSON = withObject "WorkflowToolPayload" $ \obj ->
    WorkflowToolPayload
      <$> obj .: "runId"
      <*> obj .: "status"
      <*> obj .: "submittedAt"
      <*> obj .:? "completedAt"

-- | Create a new BFF service
newBFFService :: BFFConfig -> IO BFFService
newBFFService config = do
  sessionsVar <- newTVarIO Map.empty
  uploadsVar <- newTVarIO Map.empty
  runCacheVar <- newTVarIO Map.empty
  tenantStorage <- newTenantStorageService defaultTenantStorageConfig
  pure
    BFFService
      { bffConfig = config,
        bffSessions = sessionsVar,
        bffPendingUploads = uploadsVar,
        bffRunCache = runCacheVar,
        bffTenantStorage = tenantStorage,
        bffToolCatalog = Nothing,
        bffInferenceManager = Nothing,
        bffReferenceModelConfig = Nothing
      }

newBFFServiceWithRuntime ::
  BFFConfig ->
  ToolCatalog ->
  TenantStorageService ->
  ReferenceModelConfig ->
  IO BFFService
newBFFServiceWithRuntime config toolCatalog tenantStorage referenceModelConfig = do
  sessionsVar <- newTVarIO Map.empty
  uploadsVar <- newTVarIO Map.empty
  runCacheVar <- newTVarIO Map.empty
  inferenceManager <- newManager defaultManagerSettings
  pure
    BFFService
      { bffConfig = config,
        bffSessions = sessionsVar,
        bffPendingUploads = uploadsVar,
        bffRunCache = runCacheVar,
        bffTenantStorage = tenantStorage,
        bffToolCatalog = Just toolCatalog,
        bffInferenceManager = Just inferenceManager,
        bffReferenceModelConfig = Just referenceModelConfig
      }

-- | Create a new web session
createWebSession ::
  BFFService ->
  Text -> -- Subject ID
  Text -> -- Tenant ID
  Text -> -- Access token
  Maybe Text -> -- Refresh token
  IO (Either BFFError WebSession)
createWebSession service subjectId tenantId accessToken refreshToken = do
  sessionId <- newWebSessionId
  now <- getCurrentTime
  let ttl = fromIntegral (bffSessionTtlSeconds (bffConfig service))
      expiresAt = addUTCTime ttl now
      session =
        WebSession
          { wsSessionId = sessionId,
            wsSubjectId = subjectId,
            wsTenantId = tenantId,
            wsAccessToken = accessToken,
            wsRefreshToken = refreshToken,
            wsExpiresAt = expiresAt,
            wsCreatedAt = now,
            wsLastActiveAt = now
          }

  sessions <- readTVarIO (bffSessions service)
  atomically $ writeTVar (bffSessions service) (Map.insert sessionId session sessions)
  pure (Right session)

-- | Get a web session
getWebSession :: BFFService -> WebSessionId -> IO (Either BFFError WebSession)
getWebSession service sessionId = do
  sessions <- readTVarIO (bffSessions service)
  now <- getCurrentTime
  case Map.lookup sessionId sessions of
    Nothing -> pure $ Left $ SessionNotFound sessionId
    Just session ->
      if wsExpiresAt session < now
        then do
          -- Remove expired session
          atomically $ writeTVar (bffSessions service) (Map.delete sessionId sessions)
          pure $ Left $ SessionExpired sessionId
        else do
          -- Update last active time
          let updatedSession = session {wsLastActiveAt = now}
          atomically $ writeTVar (bffSessions service) (Map.insert sessionId updatedSession sessions)
          pure (Right updatedSession)

-- | Refresh a web session
refreshWebSession ::
  BFFService ->
  WebSessionId ->
  Text -> -- New access token
  Maybe Text -> -- New refresh token
  IO (Either BFFError WebSession)
refreshWebSession service sessionId newAccessToken newRefreshToken = do
  sessionResult <- getWebSession service sessionId
  case sessionResult of
    Left err -> pure (Left err)
    Right session -> do
      now <- getCurrentTime
      let ttl = fromIntegral (bffSessionTtlSeconds (bffConfig service))
          newExpiresAt = addUTCTime ttl now
          updatedSession =
            session
              { wsAccessToken = newAccessToken,
                wsRefreshToken = newRefreshToken,
                wsExpiresAt = newExpiresAt,
                wsLastActiveAt = now
              }
      sessions <- readTVarIO (bffSessions service)
      atomically $ writeTVar (bffSessions service) (Map.insert sessionId updatedSession sessions)
      pure (Right updatedSession)

-- | Invalidate a web session
invalidateWebSession :: BFFService -> WebSessionId -> IO (Either BFFError ())
invalidateWebSession service sessionId = do
  sessions <- readTVarIO (bffSessions service)
  if Map.member sessionId sessions
    then do
      atomically $ writeTVar (bffSessions service) (Map.delete sessionId sessions)
      pure (Right ())
    else pure $ Left $ SessionNotFound sessionId

-- | Request an upload URL
requestUpload ::
  BFFService ->
  WebSessionId ->
  UploadRequest ->
  IO (Either BFFError UploadResponse)
requestUpload service sessionId req = do
  sessionResult <- getWebSession service sessionId
  case sessionResult of
    Left err -> pure (Left err)
    Right session -> do
      -- Validate content type
      let config = bffConfig service
      if urContentType req `notElem` bffAllowedContentTypes config
        then pure $ Left $ InvalidRequest "Content type not allowed"
        else
          if urFileSize req > bffMaxUploadSize config
            then pure $ Left $ InvalidRequest "File size exceeds maximum"
            else do
              artifactResult <-
                createTenantArtifact
                  (bffTenantStorage service)
                  (TenantId (wsTenantId session))
                  (urContentType req)
                  (urFileName req)
                  (urFileSize req)
                  (Map.fromList (maybe [] id (urMetadata req)))
              case artifactResult of
                Left storageErr ->
                  pure (Left (tenantStorageErrorToBffError storageErr))
                Right artifact -> do
                  uploadUrlResult <-
                    generateUploadUrl
                      (bffTenantStorage service)
                      (TenantId (wsTenantId session))
                      (taArtifactId artifact)
                      (urContentType req)
                  case uploadUrlResult of
                    Left storageErr ->
                      pure (Left (tenantStorageErrorToBffError storageErr))
                    Right presigned -> do
                      let pending =
                            PendingUpload
                              { puArtifactId = taArtifactId artifact,
                                puTenantId = wsTenantId session,
                                puFileName = urFileName req,
                                puContentType = urContentType req,
                                puFileSize = urFileSize req,
                                puCreatedAt = taCreatedAt artifact,
                                puExpiresAt = TenantStorage.puExpiresAt presigned
                              }
                      uploads <- readTVarIO (bffPendingUploads service)
                      atomically $ writeTVar (bffPendingUploads service) (Map.insert (taArtifactId artifact) pending uploads)

                      pure $
                        Right
                          UploadResponse
                            { urpPresignedUrl =
                                PresignedUploadUrl
                                  { puuUrl = TenantStorage.puUrl presigned,
                                    puuMethod = TenantStorage.puMethod presigned,
                                    puuHeaders = Map.toList (TenantStorage.puHeaders presigned),
                                    puuExpiresAt = TenantStorage.puExpiresAt presigned,
                                    puuArtifactId = taArtifactId artifact
                                  },
                              urpArtifactId = taArtifactId artifact
                            }

-- | Confirm an upload completed
confirmUpload :: BFFService -> WebSessionId -> Text -> IO (Either BFFError ())
confirmUpload service sessionId artifactId = do
  sessionResult <- getWebSession service sessionId
  case sessionResult of
    Left err -> pure (Left err)
    Right session -> do
      uploads <- readTVarIO (bffPendingUploads service)
      case Map.lookup artifactId uploads of
        Nothing -> pure $ Left $ ArtifactNotFound artifactId
        Just pending ->
          if puTenantId pending /= wsTenantId session
            then pure $ Left $ Forbidden "Artifact belongs to different tenant"
            else do
              -- Remove from pending
              atomically $ writeTVar (bffPendingUploads service) (Map.delete artifactId uploads)
              pure (Right ())

-- | Request a download URL
requestDownload ::
  BFFService ->
  WebSessionId ->
  DownloadRequest ->
  IO (Either BFFError DownloadResponse)
requestDownload service sessionId req = do
  sessionResult <- getWebSession service sessionId
  case sessionResult of
    Left err -> pure (Left err)
    Right session -> do
      artifactResult <-
        getTenantArtifact
          (bffTenantStorage service)
          (TenantId (wsTenantId session))
          (drArtifactId req)
      case artifactResult of
        Left storageErr ->
          pure (Left (tenantStorageErrorToBffError storageErr))
        Right artifact -> do
          downloadUrlResult <-
            generateDownloadUrl
              (bffTenantStorage service)
              (TenantId (wsTenantId session))
              (drArtifactId req)
              Nothing
          case downloadUrlResult of
            Left storageErr ->
              pure (Left (tenantStorageErrorToBffError storageErr))
            Right presigned ->
              pure $
                Right
                  DownloadResponse
                    { drpPresignedUrl =
                        PresignedDownloadUrl
                          { pduUrl = TenantStorage.puUrl presigned,
                            pduExpiresAt = TenantStorage.puExpiresAt presigned,
                            pduContentType = taContentType artifact,
                            pduFileSize = taFileSize artifact
                          },
                      drpArtifactId = taArtifactId artifact,
                      drpFileName = taFileName artifact
                    }

-- | Send a chat message
sendChatMessage ::
  BFFService ->
  WebSessionId ->
  ChatRequest ->
  IO (Either BFFError ChatResponse)
sendChatMessage service sessionId req = do
  sessionResult <- getWebSession service sessionId
  case sessionResult of
    Left err -> pure (Left err)
    Right session -> do
      case latestUserMessage (crMessages req) of
        Nothing ->
          pure $ Left $ InvalidRequest "At least one user message is required"
        Just userMessage -> do
          now <- getCurrentTime
          conversationId <- generateConversationId
          responseTextResult <-
            case (bffInferenceManager service, bffReferenceModelConfig service) of
              (Just manager, Just referenceModelConfig) ->
                fmap (either (Left . McpServiceError . renderFailureDetail) Right)
                  (requestReferenceAdvice manager referenceModelConfig (renderChatPrompt session req userMessage) >>= pure . (>>= applyGuardrails))
              _ ->
                pure $
                  Right $
                    renderChatReply
                      (wsTenantId session)
                      userMessage
                      (crContext req)
          case responseTextResult of
            Left err -> pure (Left err)
            Right responseText ->
              pure $
                Right
                  ChatResponse
                    { crpMessage =
                        ChatMessage
                          { cmRole = ChatAssistant,
                            cmContent = responseText,
                            cmTimestamp = Just now
                          },
                      crpConversationId = conversationId
                    }

-- | Submit a run
submitRun ::
  BFFService ->
  WebSessionId ->
  RunSubmitRequest ->
  IO (Either BFFError RunStatusResponse)
submitRun service sessionId req = do
  sessionResult <- getWebSession service sessionId
  case sessionResult of
    Left err -> pure (Left err)
    Right session ->
      case bffToolCatalog service of
        Just toolCatalog -> do
          toolResult <-
            callTool
              toolCatalog
              (TenantId (wsTenantId session))
              (SubjectId (wsSubjectId session))
              CallToolParams
                { ctpName = "workflow.submit",
                  ctpArguments =
                    Just $
                      object
                        [ "dag_spec" .= rsrDagSpec req,
                          "input_artifacts" .= rsrInputArtifacts req
                        ]
                }
          case toolResult of
            ToolFailure err -> pure $ Left $ McpServiceError (renderToolError err)
            ToolSuccess callResult ->
              case decodeRunStatusResponse callResult of
                Left err -> pure (Left err)
                Right status -> pure (Right status)
        Nothing -> do
          runId <- generateRunId
          now <- getCurrentTime
          let status =
                RunStatusResponse
                  { rsrRunId = runId,
                    rsrStatus = "submitted",
                    rsrProgress = Just 0,
                    rsrStartedAt = Just now,
                    rsrCompletedAt = Nothing
                  }
          cache <- readTVarIO (bffRunCache service)
          atomically $ writeTVar (bffRunCache service) (Map.insert runId status cache)
          pure (Right status)

-- | Get run status
getRunStatus ::
  BFFService ->
  WebSessionId ->
  RunId ->
  IO (Either BFFError RunStatusResponse)
getRunStatus service sessionId runId = do
  sessionResult <- getWebSession service sessionId
  case sessionResult of
    Left err -> pure (Left err)
    Right session ->
      case bffToolCatalog service of
        Just toolCatalog -> do
          toolResult <-
            callTool
              toolCatalog
              (TenantId (wsTenantId session))
              (SubjectId (wsSubjectId session))
              CallToolParams
                { ctpName = "workflow.status",
                  ctpArguments = Just (object ["run_id" .= runId])
                }
          case toolResult of
            ToolFailure err -> pure $ Left $ McpServiceError (renderToolError err)
            ToolSuccess callResult ->
              case decodeRunStatusResponse callResult of
                Left err -> pure (Left err)
                Right status -> pure (Right status)
        Nothing -> do
          cache <- readTVarIO (bffRunCache service)
          case Map.lookup runId cache of
            Just status -> pure (Right status)
            Nothing -> pure $ Left $ InvalidRequest "Run not found"

-- | Generate a conversation ID
generateConversationId :: IO Text
generateConversationId = do
  uuid <- UUID.nextRandom
  pure $ "conv-" <> UUID.toText uuid

-- | Generate a run ID
generateRunId :: IO RunId
generateRunId = do
  uuid <- UUID.nextRandom
  pure $ RunId $ "run-" <> UUID.toText uuid

tenantStorageErrorToBffError :: TenantStorage.TenantStorageError -> BFFError
tenantStorageErrorToBffError err =
  case err of
    TenantStorage.ArtifactNotFound artifactId -> ArtifactNotFound artifactId
    TenantStorage.ArtifactTooLarge _ _ -> InvalidRequest "File size exceeds maximum"
    TenantStorage.InvalidContentType contentType -> InvalidRequest ("Invalid content type: " <> contentType)
    TenantStorage.StorageQuotaExceeded _ -> Forbidden "Tenant storage quota exceeded"
    TenantStorage.TenantNotConfigured _ -> InternalError "Tenant storage is not configured"
    TenantStorage.ArtifactVersionNotFound artifactId _ -> ArtifactNotFound artifactId
    TenantStorage.StorageBackendError message -> McpServiceError message
    TenantStorage.PresignedUrlGenerationFailed message -> InternalError message

latestUserMessage :: [ChatMessage] -> Maybe Text
latestUserMessage =
  fmap cmContent
    . safeLast
    . filter ((== ChatUser) . cmRole)

safeLast :: [a] -> Maybe a
safeLast [] = Nothing
safeLast xs = Just (last xs)

renderChatReply :: Text -> Text -> Maybe Text -> Text
renderChatReply tenantId userMessage maybeContext =
  T.intercalate
    " "
    ( filter
        (not . T.null)
        [ "Tenant " <> tenantId <> ":",
          "I can help you prepare uploads, submit DAG runs, inspect workflow state, and fetch artifacts.",
          "Latest request: \"" <> userMessage <> "\".",
          maybe "" (\ctx -> "Context: " <> ctx <> ".") maybeContext,
          "Next step: upload media through the BFF, then submit a workflow and monitor the run status endpoint."
        ]
    )

renderChatPrompt :: WebSession -> ChatRequest -> Text -> Text
renderChatPrompt session req latestMessage =
  T.intercalate
    "\n"
    ( [ "You are the studioMCP assistant for tenant " <> wsTenantId session <> "."
      , "Help with uploads, workflow execution, artifacts, and MCP operations."
      , "Latest user message: " <> latestMessage
      ]
        <> maybe [] (\ctx -> ["Context: " <> ctx]) (crContext req)
    )

renderToolError :: ToolError -> Text
renderToolError toolErr =
  case toolErr of
    ToolNotFound name -> "Tool not found: " <> name
    InvalidArguments message -> message
    ExecutionFailed message -> message
    AuthorizationFailed message -> message
    ResourceNotFound message -> message
    RateLimited -> "Rate limit exceeded"

renderFailureDetail :: FailureDetail -> Text
renderFailureDetail failureDetail =
  failureMessage failureDetail

decodeRunStatusResponse :: CallToolResult -> Either BFFError RunStatusResponse
decodeRunStatusResponse callResult =
  case firstToolPayload callResult of
    Nothing -> Left $ McpServiceError "workflow tool did not return machine-readable JSON data"
    Just payloadText ->
      case Aeson.eitherDecodeStrict' (TE.encodeUtf8 payloadText) of
        Left err ->
          Left $ McpServiceError ("workflow tool returned invalid JSON payload: " <> T.pack err)
        Right payload ->
          Right $
            RunStatusResponse
              { rsrRunId = wtpRunId payload,
                rsrStatus = wtpStatus payload,
                rsrProgress =
                  Just $
                    case T.toLower (wtpStatus payload) of
                      "running" -> 0
                      "accepted" -> 0
                      "submitted" -> 0
                      _ -> 100,
                rsrStartedAt = Just (wtpSubmittedAt payload),
                rsrCompletedAt = wtpCompletedAt payload
              }

firstToolPayload :: CallToolResult -> Maybe Text
firstToolPayload callResult =
  tcData =<< safeLast (ctrContent callResult)
