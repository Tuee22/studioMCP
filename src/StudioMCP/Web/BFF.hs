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
    newBFFServiceWithMcpClient,
    newBFFServiceWithMcpClientAndRedis,

    -- * Session Management
    loginWebSession,
    logoutWebSession,
    createWebSession,
    getWebSession,
    refreshWebSession,
    invalidateWebSession,
    getProfile,
    profileFromSession,

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
    listRuns,
    cancelRun,

    -- * Artifact Governance
    hideArtifact,
    archiveArtifact,

    -- * Errors
    BFFError (..),
    bffErrorToHttpStatus,
  )
where

import Control.Concurrent.MVar (putMVar, takeMVar)
import Control.Concurrent.STM (TVar, atomically, modifyTVar', newTVarIO, readTVarIO)
import Control.Exception (bracket_)
import Data.Aeson
  ( FromJSON,
    Result (Error, Success),
    ToJSON,
    Value,
    encode,
    fromJSON,
    object,
    withObject,
    (.:),
    (.:?),
    (.=),
  )
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Data.CaseInsensitive as CI
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time (UTCTime, addUTCTime, diffUTCTime, getCurrentTime)
import Database.Redis (del, get, runRedis, setex)
import qualified Database.Redis as Redis
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import GHC.Generics (Generic)
import Network.HTTP.Client
  ( Manager,
    Request (method, requestBody, requestHeaders),
    RequestBody (RequestBodyLBS),
    defaultManagerSettings,
    httpLbs,
    newManager,
    parseRequest,
    responseBody,
    responseHeaders,
    responseStatus,
  )
import Network.HTTP.Types
  ( Header,
    hAuthorization,
    hContentType,
    methodDelete,
    methodPost,
    Status,
    status400,
    status401,
    status403,
    status404,
    status500,
    status502,
  )
import Network.HTTP.Types.Status (statusCode)
import StudioMCP.Auth.Config (AuthConfig (acEnabled))
import StudioMCP.Auth.Middleware (AuthService (..), buildAuthContext, validateToken)
import StudioMCP.Auth.Types
  ( AuthContext (..),
    RawJwt (..),
    SubjectId (..),
    TenantId (..),
    authErrorToText,
    subjectId,
    tenantId,
  )
import StudioMCP.DAG.Summary (RunId (..))
import StudioMCP.Inference.Guardrails (applyGuardrails)
import StudioMCP.Inference.ReferenceModel
  ( ReferenceModelConfig,
    requestReferenceAdvice,
  )
import StudioMCP.MCP.Protocol.Types
  ( CallToolParams (..),
    CallToolResult (..),
    ToolContent (..),
  )
import StudioMCP.MCP.Session.RedisConfig (RedisConfig (..))
import StudioMCP.MCP.Session.RedisStore
  ( RedisSessionStore (..),
    newRedisSessionStore,
    withRedisConnection,
  )
import StudioMCP.MCP.Tools
  ( ToolCatalog,
    ToolError (..),
    ToolResult (..),
    callTool,
  )
import StudioMCP.Result.Failure (FailureDetail (..))
import StudioMCP.Storage.TenantStorage
  ( TenantArtifact (..),
    TenantStorageService,
    createTenantArtifact,
    createTenantArtifactVersion,
    defaultTenantStorageConfig,
    generateDownloadUrl,
    generateUploadUrl,
    getTenantArtifact,
    newTenantStorageService,
  )
import qualified StudioMCP.Storage.TenantStorage as TenantStorage
import StudioMCP.Web.Types

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

defaultBFFConfig :: BFFConfig
defaultBFFConfig =
  BFFConfig
    { bffMcpEndpoint = "http://localhost:3000",
      bffSessionTtlSeconds = 3600,
      bffUploadTtlSeconds = 900,
      bffDownloadTtlSeconds = 300,
      bffMaxUploadSize = 10 * 1024 * 1024 * 1024,
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

data BFFError
  = SessionNotFound WebSessionId
  | SessionExpired WebSessionId
  | InvalidCredentials Text
  | Unauthorized Text
  | Forbidden Text
  | ArtifactNotFound Text
  | InvalidRequest Text
  | McpServiceError Text
  | InternalError Text
  deriving (Eq, Show, Generic)

instance ToJSON BFFError

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

data BFFService = BFFService
  { bffConfig :: BFFConfig,
    bffSessions :: TVar (Map WebSessionId WebSession),
    bffPendingUploads :: TVar (Map Text PendingUpload),
    bffRunCache :: TVar (Map RunId RunStatusResponse),
    bffRedisStateStore :: Maybe RedisSessionStore,
    bffTenantStorage :: TenantStorageService,
    bffToolCatalog :: Maybe ToolCatalog,
    bffMcpHttpManager :: Maybe Manager,
    bffAuthService :: Maybe AuthService,
    bffInferenceManager :: Maybe Manager,
    bffReferenceModelConfig :: Maybe ReferenceModelConfig
  }

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

instance ToJSON PendingUpload
instance FromJSON PendingUpload

data WorkflowToolPayload = WorkflowToolPayload
  { wtpRunId :: RunId,
    wtpStatus :: Text,
    wtpSubmittedAt :: UTCTime,
    wtpCompletedAt :: Maybe UTCTime
  }
  deriving (Eq, Show, Generic)

instance FromJSON WorkflowToolPayload where
  parseJSON = withObject "WorkflowToolPayload" $ \obj ->
    WorkflowToolPayload
      <$> obj .: "runId"
      <*> obj .: "status"
      <*> obj .: "submittedAt"
      <*> obj .:? "completedAt"

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
        bffRedisStateStore = Nothing,
        bffTenantStorage = tenantStorage,
        bffToolCatalog = Nothing,
        bffMcpHttpManager = Nothing,
        bffAuthService = Nothing,
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
  manager <- newManager defaultManagerSettings
  pure
    BFFService
      { bffConfig = config,
        bffSessions = sessionsVar,
        bffPendingUploads = uploadsVar,
        bffRunCache = runCacheVar,
        bffRedisStateStore = Nothing,
        bffTenantStorage = tenantStorage,
        bffToolCatalog = Just toolCatalog,
        bffMcpHttpManager = Nothing,
        bffAuthService = Nothing,
        bffInferenceManager = Just manager,
        bffReferenceModelConfig = Just referenceModelConfig
      }

newBFFServiceWithMcpClient ::
  BFFConfig ->
  TenantStorageService ->
  Maybe AuthService ->
  ReferenceModelConfig ->
  IO BFFService
newBFFServiceWithMcpClient config tenantStorage maybeAuthService referenceModelConfig = do
  sessionsVar <- newTVarIO Map.empty
  uploadsVar <- newTVarIO Map.empty
  runCacheVar <- newTVarIO Map.empty
  manager <- newManager defaultManagerSettings
  pure
    BFFService
      { bffConfig = config,
        bffSessions = sessionsVar,
        bffPendingUploads = uploadsVar,
        bffRunCache = runCacheVar,
        bffRedisStateStore = Nothing,
        bffTenantStorage = tenantStorage,
        bffToolCatalog = Nothing,
        bffMcpHttpManager = Just manager,
        bffAuthService = maybeAuthService,
        bffInferenceManager = Just manager,
        bffReferenceModelConfig = Just referenceModelConfig
      }

newBFFServiceWithMcpClientAndRedis ::
  BFFConfig ->
  RedisConfig ->
  TenantStorageService ->
  Maybe AuthService ->
  ReferenceModelConfig ->
  IO BFFService
newBFFServiceWithMcpClientAndRedis config redisConfig tenantStorage maybeAuthService referenceModelConfig = do
  sessionsVar <- newTVarIO Map.empty
  uploadsVar <- newTVarIO Map.empty
  runCacheVar <- newTVarIO Map.empty
  redisStore <- newRedisSessionStore redisConfig
  manager <- newManager defaultManagerSettings
  pure
    BFFService
      { bffConfig = config,
        bffSessions = sessionsVar,
        bffPendingUploads = uploadsVar,
        bffRunCache = runCacheVar,
        bffRedisStateStore = Just redisStore,
        bffTenantStorage = tenantStorage,
        bffToolCatalog = Nothing,
        bffMcpHttpManager = Just manager,
        bffAuthService = maybeAuthService,
        bffInferenceManager = Just manager,
        bffReferenceModelConfig = Just referenceModelConfig
      }

loginWebSession :: BFFService -> LoginRequest -> IO (Either BFFError WebSession)
loginWebSession service loginRequest = do
  identityResult <- resolveLoginIdentity service loginRequest
  case identityResult of
    Left err -> pure (Left err)
    Right (subjectIdText, tenantIdText) ->
      createWebSession
        service
        subjectIdText
        tenantIdText
        (lrAccessToken loginRequest)
        (lrRefreshToken loginRequest)

logoutWebSession :: BFFService -> WebSessionId -> IO (Either BFFError LogoutResponse)
logoutWebSession service sessionId = do
  invalidateResult <- invalidateWebSession service sessionId
  pure $ fmap (const (LogoutResponse True)) invalidateResult

createWebSession ::
  BFFService ->
  Text ->
  Text ->
  Text ->
  Maybe Text ->
  IO (Either BFFError WebSession)
createWebSession service subjectIdText tenantIdText accessToken refreshToken = do
  sessionId <- newWebSessionId
  now <- getCurrentTime
  let ttl = fromIntegral (bffSessionTtlSeconds (bffConfig service))
      expiresAt = addUTCTime ttl now
      session =
        WebSession
          { wsSessionId = sessionId,
            wsSubjectId = subjectIdText,
            wsTenantId = tenantIdText,
            wsAccessToken = accessToken,
            wsRefreshToken = refreshToken,
            wsMcpSessionId = Nothing,
            wsExpiresAt = expiresAt,
            wsCreatedAt = now,
            wsLastActiveAt = now
          }
  persistResult <- upsertSession service session
  pure (session <$ persistResult)

getWebSession :: BFFService -> WebSessionId -> IO (Either BFFError WebSession)
getWebSession service sessionId = do
  sessionResult <- lookupStoredSession service sessionId
  now <- getCurrentTime
  case sessionResult of
    Left err -> pure (Left err)
    Right Nothing -> pure $ Left $ SessionNotFound sessionId
    Right (Just session)
      | wsExpiresAt session < now -> do
          _ <- deleteStoredSession service sessionId
          pure $ Left $ SessionExpired sessionId
      | otherwise -> do
          let updatedSession = session {wsLastActiveAt = now}
          persistResult <- upsertSession service updatedSession
          pure (updatedSession <$ persistResult)

refreshWebSession ::
  BFFService ->
  WebSessionId ->
  Text ->
  Maybe Text ->
  IO (Either BFFError WebSession)
refreshWebSession service sessionId newAccessToken newRefreshToken = do
  sessionResult <- getWebSession service sessionId
  case sessionResult of
    Left err -> pure (Left err)
    Right session -> do
      terminateMcpSession service session
      now <- getCurrentTime
      let ttl = fromIntegral (bffSessionTtlSeconds (bffConfig service))
          updatedSession =
            session
              { wsAccessToken = newAccessToken,
                wsRefreshToken = newRefreshToken,
                wsMcpSessionId = Nothing,
                wsExpiresAt = addUTCTime ttl now,
                wsLastActiveAt = now
              }
      persistResult <- upsertSession service updatedSession
      pure (updatedSession <$ persistResult)

invalidateWebSession :: BFFService -> WebSessionId -> IO (Either BFFError ())
invalidateWebSession service sessionId = do
  sessionResult <- lookupStoredSession service sessionId
  case sessionResult of
    Left err -> pure (Left err)
    Right Nothing -> pure $ Left $ SessionNotFound sessionId
    Right (Just session) -> do
      terminateMcpSession service session
      deleteStoredSession service sessionId

getProfile :: BFFService -> WebSessionId -> IO (Either BFFError ProfileResponse)
getProfile service sessionId =
  fmap profileFromSession <$> getWebSession service sessionId

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
      let config = bffConfig service
      if urContentType req `notElem` bffAllowedContentTypes config
        then pure $ Left $ InvalidRequest "Content type not allowed"
        else
          if urFileSize req > bffMaxUploadSize config
            then pure $ Left $ InvalidRequest "File size exceeds maximum"
            else do
              artifactResult <-
                case urArtifactId req of
                  Nothing ->
                    createTenantArtifact
                      (bffTenantStorage service)
                      (TenantId (wsTenantId session))
                      (urContentType req)
                      (urFileName req)
                      (urFileSize req)
                      (Map.fromList (fromMaybe [] (urMetadata req)))
                  Just artifactId ->
                    createTenantArtifactVersion
                      (bffTenantStorage service)
                      (TenantId (wsTenantId session))
                      artifactId
                      (urContentType req)
                      (urFileName req)
                      (urFileSize req)
                      (Map.fromList (fromMaybe [] (urMetadata req)))
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
                      persistPendingResult <- upsertPendingUpload service pending
                      case persistPendingResult of
                        Left err ->
                          pure (Left err)
                        Right () ->
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

confirmUpload :: BFFService -> WebSessionId -> Text -> IO (Either BFFError ())
confirmUpload service sessionId artifactId = do
  sessionResult <- getWebSession service sessionId
  case sessionResult of
    Left err -> pure (Left err)
    Right session -> do
      now <- getCurrentTime
      pendingResult <- lookupPendingUpload service artifactId
      case pendingResult of
        Left err -> pure (Left err)
        Right Nothing -> pure $ Left $ ArtifactNotFound artifactId
        Right (Just pending)
          | puExpiresAt pending < now -> do
              _ <- deletePendingUpload service artifactId
              pure $ Left $ ArtifactNotFound artifactId
        Right (Just pending)
          | puTenantId pending /= wsTenantId session ->
              pure $ Left $ Forbidden "Artifact belongs to different tenant"
          | otherwise -> do
              deletePendingUpload service artifactId

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

sendChatMessage ::
  BFFService ->
  WebSessionId ->
  ChatRequest ->
  IO (Either BFFError ChatResponse)
sendChatMessage service sessionId req = do
  sessionResult <- getWebSession service sessionId
  case sessionResult of
    Left err -> pure (Left err)
    Right session ->
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
      if hasMcpBackend service
        then do
          toolResult <-
            callSessionTool
              service
              session
              "workflow.submit"
              ( Just $
                  object
                    [ "dag_spec" .= rsrDagSpec req,
                      "input_artifacts" .= rsrInputArtifacts req
                    ]
              )
          pure (toolResult >>= decodeRunStatusResponse)
        else cacheSubmittedRun service

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
      if hasMcpBackend service
        then do
          toolResult <-
            callSessionTool
              service
              session
              "workflow.status"
              (Just (object ["run_id" .= runId]))
          pure (toolResult >>= decodeRunStatusResponse)
        else do
          cache <- readTVarIO (bffRunCache service)
          pure $
            maybe
              (Left (InvalidRequest "Run not found"))
              Right
              (Map.lookup runId cache)

listRuns ::
  BFFService ->
  WebSessionId ->
  RunListRequest ->
  IO (Either BFFError RunListResponse)
listRuns service sessionId req = do
  sessionResult <- getWebSession service sessionId
  case sessionResult of
    Left err -> pure (Left err)
    Right session ->
      if hasMcpBackend service
        then do
          toolResult <-
            callSessionTool
              service
              session
              "workflow.list"
              (Just (object ["status" .= rlrStatus req, "limit" .= rlrLimit req]))
          pure (toolResult >>= decodeRunListResponse)
        else do
          cache <- readTVarIO (bffRunCache service)
          let runs =
                take (fromMaybe maxBound (rlrLimit req))
                  . filter (\runStatus -> maybe True (== rsrStatus runStatus) (rlrStatus req))
                  $ Map.elems cache
          pure (Right (RunListResponse runs))

cancelRun ::
  BFFService ->
  WebSessionId ->
  RunId ->
  Maybe Text ->
  IO (Either BFFError RunStatusResponse)
cancelRun service sessionId runId maybeReason = do
  sessionResult <- getWebSession service sessionId
  case sessionResult of
    Left err -> pure (Left err)
    Right session ->
      if hasMcpBackend service
        then do
          toolResult <-
            callSessionTool
              service
              session
              "workflow.cancel"
              (Just (object ["run_id" .= runId, "reason" .= maybeReason]))
          pure (toolResult >>= decodeRunStatusResponse)
        else do
          cache <- readTVarIO (bffRunCache service)
          case Map.lookup runId cache of
            Nothing -> pure $ Left $ InvalidRequest "Run not found"
            Just runStatus -> do
              now <- getCurrentTime
              let updatedStatus =
                    runStatus
                      { rsrStatus = "cancelled",
                        rsrProgress = Just 100,
                        rsrCompletedAt = Just now
                      }
              atomically $
                modifyTVar' (bffRunCache service) (Map.insert runId updatedStatus)
              pure (Right updatedStatus)

hideArtifact ::
  BFFService ->
  WebSessionId ->
  Text ->
  ArtifactActionRequest ->
  IO (Either BFFError ArtifactGovernanceResponse)
hideArtifact service sessionId artifactId actionRequest =
  runArtifactGovernanceAction service sessionId "artifact.hide" artifactId actionRequest

archiveArtifact ::
  BFFService ->
  WebSessionId ->
  Text ->
  ArtifactActionRequest ->
  IO (Either BFFError ArtifactGovernanceResponse)
archiveArtifact service sessionId artifactId actionRequest =
  runArtifactGovernanceAction service sessionId "artifact.archive" artifactId actionRequest

runArtifactGovernanceAction ::
  BFFService ->
  WebSessionId ->
  Text ->
  Text ->
  ArtifactActionRequest ->
  IO (Either BFFError ArtifactGovernanceResponse)
runArtifactGovernanceAction service sessionId toolName artifactId actionRequest = do
  sessionResult <- getWebSession service sessionId
  case sessionResult of
    Left err -> pure (Left err)
    Right session -> do
      toolResult <-
        callSessionTool
          service
          session
          toolName
          (Just (object ["artifact_id" .= artifactId, "reason" .= aarReason actionRequest]))
      pure (toolResult >>= decodeArtifactGovernanceResponse)

resolveLoginIdentity :: BFFService -> LoginRequest -> IO (Either BFFError (Text, Text))
resolveLoginIdentity service loginRequest =
  case bffAuthService service of
    Just authService
      | acEnabled (asConfig authService) -> do
          tokenResult <- validateToken authService (RawJwt (lrAccessToken loginRequest))
          case tokenResult of
            Left authErr ->
              pure $ Left $ InvalidCredentials (authErrorToText authErr)
            Right claims -> do
              correlationId <- freshIdentifier "corr"
              authContextResult <- buildAuthContext (asConfig authService) claims correlationId
              pure $
                case authContextResult of
                  Left authErr -> Left $ InvalidCredentials (authErrorToText authErr)
                  Right authContext ->
                    let SubjectId subjectIdText = subjectId (acSubject authContext)
                        TenantId tenantIdText = tenantId (acTenant authContext)
                     in Right (subjectIdText, tenantIdText)
      | otherwise ->
          pure (Right ("dev-user", "dev-tenant"))
    _ ->
      pure $
        case (lrSubjectId loginRequest, lrTenantId loginRequest) of
          (Just subjectIdText, Just tenantIdText) -> Right (subjectIdText, tenantIdText)
          (Nothing, Nothing) -> Right ("dev-user", "dev-tenant")
          _ ->
            Left $
              InvalidRequest
                "subjectId and tenantId must both be provided when auth validation is disabled"

profileFromSession :: WebSession -> ProfileResponse
profileFromSession session =
  ProfileResponse
    { prSubjectId = wsSubjectId session,
      prTenantId = wsTenantId session,
      prExpiresAt = wsExpiresAt session,
      prCreatedAt = wsCreatedAt session,
      prLastActiveAt = wsLastActiveAt session
    }

upsertSession :: BFFService -> WebSession -> IO (Either BFFError ())
upsertSession service session =
  case bffRedisStateStore service of
    Just redisStore ->
      storeRedisValue redisStore (webSessionRedisKey redisStore (wsSessionId session)) (wsExpiresAt session) session
    Nothing -> do
      atomically $
        modifyTVar'
          (bffSessions service)
          (Map.insert (wsSessionId session) session)
      pure (Right ())

lookupStoredSession :: BFFService -> WebSessionId -> IO (Either BFFError (Maybe WebSession))
lookupStoredSession service sessionId =
  case bffRedisStateStore service of
    Just redisStore ->
      lookupRedisValue redisStore (webSessionRedisKey redisStore sessionId)
    Nothing -> do
      sessions <- readTVarIO (bffSessions service)
      pure (Right (Map.lookup sessionId sessions))

deleteStoredSession :: BFFService -> WebSessionId -> IO (Either BFFError ())
deleteStoredSession service sessionId =
  case bffRedisStateStore service of
    Just redisStore ->
      deleteRedisValue redisStore (webSessionRedisKey redisStore sessionId)
    Nothing -> do
      atomically $ modifyTVar' (bffSessions service) (Map.delete sessionId)
      pure (Right ())

upsertPendingUpload :: BFFService -> PendingUpload -> IO (Either BFFError ())
upsertPendingUpload service pendingUpload =
  case bffRedisStateStore service of
    Just redisStore ->
      storeRedisValue redisStore (pendingUploadRedisKey redisStore (puArtifactId pendingUpload)) (puExpiresAt pendingUpload) pendingUpload
    Nothing -> do
      atomically $
        modifyTVar'
          (bffPendingUploads service)
          (Map.insert (puArtifactId pendingUpload) pendingUpload)
      pure (Right ())

lookupPendingUpload :: BFFService -> Text -> IO (Either BFFError (Maybe PendingUpload))
lookupPendingUpload service artifactId =
  case bffRedisStateStore service of
    Just redisStore ->
      lookupRedisValue redisStore (pendingUploadRedisKey redisStore artifactId)
    Nothing -> do
      uploads <- readTVarIO (bffPendingUploads service)
      pure (Right (Map.lookup artifactId uploads))

deletePendingUpload :: BFFService -> Text -> IO (Either BFFError ())
deletePendingUpload service artifactId =
  case bffRedisStateStore service of
    Just redisStore ->
      deleteRedisValue redisStore (pendingUploadRedisKey redisStore artifactId)
    Nothing -> do
      atomically $ modifyTVar' (bffPendingUploads service) (Map.delete artifactId)
      pure (Right ())

webSessionRedisKey :: RedisSessionStore -> WebSessionId -> Text
webSessionRedisKey redisStore (WebSessionId sessionIdText) =
  redisStateKeyPrefix redisStore <> "web-session:" <> sessionIdText

pendingUploadRedisKey :: RedisSessionStore -> Text -> Text
pendingUploadRedisKey redisStore artifactId =
  redisStateKeyPrefix redisStore <> "pending-upload:" <> artifactId

redisStateKeyPrefix :: RedisSessionStore -> Text
redisStateKeyPrefix redisStore =
  rcKeyPrefix (rssConfig redisStore) <> "bff:"

storeRedisValue :: ToJSON a => RedisSessionStore -> Text -> UTCTime -> a -> IO (Either BFFError ())
storeRedisValue redisStore key expiresAt value = do
  now <- getCurrentTime
  let ttlSeconds = remainingTtlSeconds now expiresAt
  if ttlSeconds <= 0
    then deleteRedisValue redisStore key
    else
      withRedisWriteLock redisStore $
        fmap (const ()) <$>
          execBffRedis
            redisStore
            (setex (redisKeyBytes key) (fromIntegral ttlSeconds) (encodeStrictJson value))

lookupRedisValue :: FromJSON a => RedisSessionStore -> Text -> IO (Either BFFError (Maybe a))
lookupRedisValue redisStore key = do
  redisResult <- execBffRedis redisStore (get (redisKeyBytes key))
  pure $
    case redisResult of
      Left err -> Left err
      Right Nothing -> Right Nothing
      Right (Just payload) ->
        case decodeStrictJson payload of
          Nothing -> Left $ InternalError "BFF state store returned invalid JSON"
          Just value -> Right (Just value)

deleteRedisValue :: RedisSessionStore -> Text -> IO (Either BFFError ())
deleteRedisValue redisStore key =
  withRedisWriteLock redisStore $
    fmap (const ()) <$> execBffRedis redisStore (del [redisKeyBytes key])

execBffRedis :: RedisSessionStore -> Redis.Redis (Either Redis.Reply a) -> IO (Either BFFError a)
execBffRedis redisStore action = do
  connectionResult <- withRedisConnection redisStore (runRedis (rssConnection redisStore) action)
  pure $
    case connectionResult of
      Left err -> Left $ InternalError ("BFF state store error: " <> T.pack (show err))
      Right (Left reply) -> Left $ InternalError ("BFF state store error: " <> T.pack (show reply))
      Right (Right value) -> Right value

withRedisWriteLock :: RedisSessionStore -> IO a -> IO a
withRedisWriteLock redisStore =
  bracket_
    (takeMVar (rssWriteLock redisStore))
    (putMVar (rssWriteLock redisStore) ())

remainingTtlSeconds :: UTCTime -> UTCTime -> Int
remainingTtlSeconds now expiresAt
  | expiresAt <= now = 0
  | otherwise = max 1 (ceiling (diffUTCTime expiresAt now))

encodeStrictJson :: ToJSON a => a -> BS.ByteString
encodeStrictJson = LBS.toStrict . encode

decodeStrictJson :: FromJSON a => BS.ByteString -> Maybe a
decodeStrictJson = Aeson.decode . LBS.fromStrict

redisKeyBytes :: Text -> BS.ByteString
redisKeyBytes = TE.encodeUtf8

hasMcpBackend :: BFFService -> Bool
hasMcpBackend service =
  maybe False (const True) (bffToolCatalog service)
    || maybe False (const True) (bffMcpHttpManager service)

cacheSubmittedRun :: BFFService -> IO (Either BFFError RunStatusResponse)
cacheSubmittedRun service = do
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
  atomically $ modifyTVar' (bffRunCache service) (Map.insert runId status)
  pure (Right status)

callSessionTool ::
  BFFService ->
  WebSession ->
  Text ->
  Maybe Value ->
  IO (Either BFFError CallToolResult)
callSessionTool service session toolName arguments =
  case bffToolCatalog service of
    Just toolCatalog ->
      callToolDirectly toolCatalog session toolName arguments
    Nothing ->
      case bffMcpHttpManager service of
        Just manager ->
          callToolOverHttp service manager session toolName arguments
        Nothing ->
          pure $ Left $ McpServiceError "BFF MCP backend is not configured"

callToolDirectly ::
  ToolCatalog ->
  WebSession ->
  Text ->
  Maybe Value ->
  IO (Either BFFError CallToolResult)
callToolDirectly toolCatalog session toolName arguments = do
  toolResult <-
    callTool
      toolCatalog
      (TenantId (wsTenantId session))
      (SubjectId (wsSubjectId session))
      CallToolParams
        { ctpName = toolName,
          ctpArguments = arguments
        }
  pure $
    case toolResult of
      ToolFailure err -> Left $ McpServiceError (renderToolError err)
      ToolSuccess callResult -> Right callResult

callToolOverHttp ::
  BFFService ->
  Manager ->
  WebSession ->
  Text ->
  Maybe Value ->
  IO (Either BFFError CallToolResult)
callToolOverHttp service manager session toolName arguments = do
  firstResult <- callToolOverHttpOnce service manager session toolName arguments
  case firstResult of
    Left (McpServiceError message)
      | isExpiredMcpSessionError message,
        wsMcpSessionId session /= Nothing -> do
          let clearedSession = session {wsMcpSessionId = Nothing}
          persistResult <- upsertSession service clearedSession
          case persistResult of
            Left err -> pure (Left err)
            Right () ->
              callToolOverHttpOnce service manager clearedSession toolName arguments
    _ -> pure firstResult

callToolOverHttpOnce ::
  BFFService ->
  Manager ->
  WebSession ->
  Text ->
  Maybe Value ->
  IO (Either BFFError CallToolResult)
callToolOverHttpOnce service manager session toolName arguments = do
  sessionWithMcp <- ensureMcpSession service manager session
  case sessionWithMcp of
    Left err -> pure (Left err)
    Right activeSession -> do
      let requestPayload =
            object
              [ "jsonrpc" .= ("2.0" :: Text),
                "id" .= (1 :: Int),
                "method" .= ("tools/call" :: Text),
                "params" .= object ["name" .= toolName, "arguments" .= arguments]
              ]
      responseResult <-
        postMcpRequest
          manager
          (bffConfig service)
          activeSession
          True
          (encode requestPayload)
      pure $
        responseResult >>= \rpcResponse ->
          decodeRpcToolResult (mhrBody rpcResponse)

ensureMcpSession ::
  BFFService ->
  Manager ->
  WebSession ->
  IO (Either BFFError WebSession)
ensureMcpSession service manager session =
  case wsMcpSessionId session of
    Just _ -> pure (Right session)
    Nothing -> do
      let initializePayload =
            object
              [ "jsonrpc" .= ("2.0" :: Text),
                "id" .= (1 :: Int),
                "method" .= ("initialize" :: Text),
                "params" .=
                  object
                    [ "protocolVersion" .= ("2024-11-05" :: Text),
                      "capabilities" .= object [],
                      "clientInfo" .= object ["name" .= ("studiomcp-bff" :: Text), "version" .= ("0.1.0" :: Text)]
                    ]
              ]
      initResult <-
        postMcpRequest
          manager
          (bffConfig service)
          session
          False
          (encode initializePayload)
      case initResult of
        Left err -> pure (Left err)
        Right initResponse ->
          case lookupResponseHeader "Mcp-Session-Id" (mhrHeaders initResponse) of
            Nothing ->
              pure $ Left $ McpServiceError "MCP initialize response did not include Mcp-Session-Id"
            Just mcpSessionId -> do
              let initializedSession = session {wsMcpSessionId = Just mcpSessionId}
                  initializedNotification =
                    object
                      [ "jsonrpc" .= ("2.0" :: Text),
                        "method" .= ("notifications/initialized" :: Text)
                      ]
              initializedResult <-
                postMcpRequest
                  manager
                  (bffConfig service)
                  initializedSession
                  True
                  (encode initializedNotification)
              case initializedResult of
                Left err -> pure (Left err)
                Right _ -> do
                  persistResult <- upsertSession service initializedSession
                  pure (initializedSession <$ persistResult)

terminateMcpSession :: BFFService -> WebSession -> IO ()
terminateMcpSession service session =
  case (bffMcpHttpManager service, wsMcpSessionId session) of
    (Just manager, Just _) -> do
      deleteResult <- deleteMcpSession manager (bffConfig service) session
      case deleteResult of
        Left _ -> pure ()
        Right _ -> pure ()
    _ -> pure ()

data McpHttpResponse = McpHttpResponse
  { mhrStatus :: Int,
    mhrHeaders :: [Header],
    mhrBody :: LBS.ByteString
  }

postMcpRequest ::
  Manager ->
  BFFConfig ->
  WebSession ->
  Bool ->
  LBS.ByteString ->
  IO (Either BFFError McpHttpResponse)
postMcpRequest manager config session includeSessionHeader requestPayload = do
  request <- parseRequest (mcpEndpointUrl config)
  response <-
    httpLbs
      request
        { method = methodPost,
          requestHeaders =
            [(hContentType, "application/json")] <> authHeadersForSession session <> sessionHeaders includeSessionHeader session,
          requestBody = RequestBodyLBS requestPayload
        }
      manager
  let statusValue = statusCode (responseStatus response)
      httpResponse =
        McpHttpResponse
          { mhrStatus = statusValue,
            mhrHeaders = responseHeaders response,
            mhrBody = responseBody response
          }
  pure $
    if statusValue == 200
      then Right httpResponse
      else Left $ McpServiceError (extractMcpErrorMessage (responseBody response))

deleteMcpSession ::
  Manager ->
  BFFConfig ->
  WebSession ->
  IO (Either BFFError ())
deleteMcpSession manager config session = do
  request <- parseRequest (mcpEndpointUrl config)
  response <-
    httpLbs
      request
        { method = methodDelete,
          requestHeaders = authHeadersForSession session <> sessionHeaders True session
        }
      manager
  pure $
    if statusCode (responseStatus response) `elem` [200, 400]
      then Right ()
      else Left $ McpServiceError (extractMcpErrorMessage (responseBody response))

authHeadersForSession :: WebSession -> [Header]
authHeadersForSession session =
  if T.null (wsAccessToken session)
    then []
    else [(hAuthorization, "Bearer " <> TE.encodeUtf8 (wsAccessToken session))]

sessionHeaders :: Bool -> WebSession -> [Header]
sessionHeaders includeSessionHeader session =
  if includeSessionHeader
    then maybe [] (\sid -> [("Mcp-Session-Id", TE.encodeUtf8 sid)]) (wsMcpSessionId session)
    else []

mcpEndpointUrl :: BFFConfig -> String
mcpEndpointUrl config =
  T.unpack (T.dropWhileEnd (== '/') (bffMcpEndpoint config) <> "/mcp")

lookupResponseHeader :: Text -> [Header] -> Maybe Text
lookupResponseHeader headerName headers =
  TE.decodeUtf8 <$> lookup (CI.mk (TE.encodeUtf8 headerName)) headers

decodeRpcToolResult :: LBS.ByteString -> Either BFFError CallToolResult
decodeRpcToolResult responseBodyBytes =
  case Aeson.decode responseBodyBytes :: Maybe Value of
    Nothing ->
      Left $ McpServiceError "MCP tools/call response was not valid JSON"
    Just responseValue ->
      case lookupPath ["error", "message"] responseValue of
        Just messageValue ->
          case fromJSON messageValue of
            Success messageText -> Left $ McpServiceError messageText
            Error _ -> Left $ McpServiceError "MCP tools/call returned an error"
        Nothing ->
          case lookupPath ["result"] responseValue of
            Nothing -> Left $ McpServiceError "MCP tools/call response was missing a result"
            Just resultValue ->
              case fromJSON resultValue of
                Success toolResult -> Right toolResult
                Error err -> Left $ McpServiceError ("MCP tools/call returned an invalid result payload: " <> T.pack err)

extractMcpErrorMessage :: LBS.ByteString -> Text
extractMcpErrorMessage body =
  case Aeson.decode body :: Maybe Value of
    Just responseValue ->
      fromMaybe fallbackMessage $
        decodeTextAtPath ["error", "message"] responseValue
          <> decodeTextAtPath ["error"] responseValue
    Nothing -> fallbackMessage
  where
    fallbackMessage =
      let rawBody = T.strip (TE.decodeUtf8 (LBS.toStrict body))
       in if T.null rawBody then "MCP request failed" else rawBody

isExpiredMcpSessionError :: Text -> Bool
isExpiredMcpSessionError message =
  "Unknown or expired MCP session" `T.isInfixOf` message

decodeRunStatusResponse :: CallToolResult -> Either BFFError RunStatusResponse
decodeRunStatusResponse callResult =
  case decodeToolPayload callResult of
    Left err -> Left err
    Right payload ->
      Right $
        RunStatusResponse
          { rsrRunId = wtpRunId payload,
            rsrStatus = wtpStatus payload,
            rsrProgress = Just (progressForStatus (wtpStatus payload)),
            rsrStartedAt = Just (wtpSubmittedAt payload),
            rsrCompletedAt = wtpCompletedAt payload
          }

decodeRunListResponse :: CallToolResult -> Either BFFError RunListResponse
decodeRunListResponse callResult =
  case decodeToolPayloadList callResult of
    Left err -> Left err
    Right payloads ->
      Right $
        RunListResponse
          { rlrRuns = map workflowPayloadToRunStatus payloads
          }

decodeArtifactGovernanceResponse :: CallToolResult -> Either BFFError ArtifactGovernanceResponse
decodeArtifactGovernanceResponse callResult =
  case firstToolPayload callResult of
    Nothing -> Left $ McpServiceError "governance tool did not return machine-readable JSON data"
    Just payloadText ->
      case Aeson.eitherDecodeStrict' (TE.encodeUtf8 payloadText) of
        Left err -> Left $ McpServiceError ("governance tool returned invalid JSON payload: " <> T.pack err)
        Right payload -> Right payload

decodeToolPayload :: FromJSON a => CallToolResult -> Either BFFError a
decodeToolPayload callResult =
  case firstToolPayload callResult of
    Nothing -> Left $ McpServiceError "workflow tool did not return machine-readable JSON data"
    Just payloadText ->
      case Aeson.eitherDecodeStrict' (TE.encodeUtf8 payloadText) of
        Left err -> Left $ McpServiceError ("workflow tool returned invalid JSON payload: " <> T.pack err)
        Right payload -> Right payload

decodeToolPayloadList :: FromJSON a => CallToolResult -> Either BFFError [a]
decodeToolPayloadList = decodeToolPayload

workflowPayloadToRunStatus :: WorkflowToolPayload -> RunStatusResponse
workflowPayloadToRunStatus payload =
  RunStatusResponse
    { rsrRunId = wtpRunId payload,
      rsrStatus = wtpStatus payload,
      rsrProgress = Just (progressForStatus (wtpStatus payload)),
      rsrStartedAt = Just (wtpSubmittedAt payload),
      rsrCompletedAt = wtpCompletedAt payload
    }

progressForStatus :: Text -> Int
progressForStatus statusText =
  case T.toLower statusText of
    "running" -> 0
    "accepted" -> 0
    "submitted" -> 0
    _ -> 100

lookupPath :: [Text] -> Value -> Maybe Value
lookupPath [] currentValue = Just currentValue
lookupPath (segment : remaining) (Aeson.Object objectValue) =
  KeyMap.lookup (Key.fromText segment) objectValue >>= lookupPath remaining
lookupPath _ _ = Nothing

decodeTextAtPath :: [Text] -> Value -> Maybe Text
decodeTextAtPath path responseValue = do
  value <- lookupPath path responseValue
  case fromJSON value of
    Success textValue -> Just textValue
    Error _ -> Nothing

generateConversationId :: IO Text
generateConversationId = freshIdentifier "conv"

generateRunId :: IO RunId
generateRunId = RunId <$> freshIdentifier "run"

freshIdentifier :: Text -> IO Text
freshIdentifier prefix = do
  uuid <- UUID.nextRandom
  pure (prefix <> "-" <> UUID.toText uuid)

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
renderChatReply tenantIdText userMessage maybeContext =
  T.intercalate
    " "
    ( filter
        (not . T.null)
        [ "Tenant " <> tenantIdText <> ":",
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
    ( [ "You are the studioMCP assistant for tenant " <> wsTenantId session <> ".",
        "Help with uploads, workflow execution, artifacts, and MCP operations.",
        "Latest user message: " <> latestMessage
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
renderFailureDetail = failureMessage

firstToolPayload :: CallToolResult -> Maybe Text
firstToolPayload callResult =
  listToMaybe (mapMaybe tcData (ctrContent callResult))
