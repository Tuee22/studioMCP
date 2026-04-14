{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module StudioMCP.Storage.AuditTrail
  ( -- * Audit Entry Types
    AuditEntry (..),
    AuditEntryId (..),
    AuditAction (..),
    AuditOutcome (..),

    -- * Audit Trail Service
    AuditTrailService (..),
    newAuditTrailService,
    newAuditTrailServiceWithFile,

    -- * Recording Audit Events
    recordAuditEntry,
    recordAccessAttempt,
    recordStateChange,
    recordDeletionAttempt,

    -- * Querying Audit Trail
    getAuditEntry,
    queryAuditTrail,
    AuditQuery (..),
    defaultAuditQuery,

    -- * Audit Reports
    generateAuditReport,
    AuditReport (..),

    -- * Compliance
    verifyAuditIntegrity,
    AuditIntegrityResult (..),
  )
where

import Control.Concurrent.STM (TVar, atomically, modifyTVar', newTVarIO, readTVar, readTVarIO)
import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    Value (String),
    decode,
    encode,
    object,
    withObject,
    (.:),
    (.:?),
    (.!=),
    (.=),
  )
import qualified Data.ByteString.Lazy as LBS
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime, getCurrentTime)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath (takeDirectory)
import StudioMCP.Auth.Types (SubjectId (..), TenantId (..))
import StudioMCP.Storage.Governance (ArtifactState, GovernanceAction)

-- | Unique identifier for an audit entry
newtype AuditEntryId = AuditEntryId {unAuditEntryId :: Text}
  deriving (Eq, Ord, Show)

instance ToJSON AuditEntryId where
  toJSON (AuditEntryId v) = toJSON v

instance FromJSON AuditEntryId where
  parseJSON v = AuditEntryId <$> parseJSON v

-- | Action being audited
data AuditAction
  = AuditCreate
  | AuditRead
  | AuditUpdate
  | AuditStateChange GovernanceAction
  | AuditDeleteAttempt -- Always recorded, always denied
  | AuditAccessDenied
  | AuditPresignedUrlGenerated
  | AuditVersionCreated
  | AuditSupersede
  deriving (Eq, Show)

instance ToJSON AuditAction where
  toJSON AuditCreate = "create"
  toJSON AuditRead = "read"
  toJSON AuditUpdate = "update"
  toJSON (AuditStateChange action) = object ["stateChange" .= action]
  toJSON AuditDeleteAttempt = "delete_attempt"
  toJSON AuditAccessDenied = "access_denied"
  toJSON AuditPresignedUrlGenerated = "presigned_url_generated"
  toJSON AuditVersionCreated = "version_created"
  toJSON AuditSupersede = "supersede"

instance FromJSON AuditAction where
  parseJSON (String "create") = pure AuditCreate
  parseJSON (String "read") = pure AuditRead
  parseJSON (String "update") = pure AuditUpdate
  parseJSON (String "delete_attempt") = pure AuditDeleteAttempt
  parseJSON (String "access_denied") = pure AuditAccessDenied
  parseJSON (String "presigned_url_generated") = pure AuditPresignedUrlGenerated
  parseJSON (String "version_created") = pure AuditVersionCreated
  parseJSON (String "supersede") = pure AuditSupersede
  parseJSON v = withObject "AuditAction" (\obj -> AuditStateChange <$> obj .: "stateChange") v

-- | Outcome of the audited action
data AuditOutcome
  = OutcomeSuccess
  | OutcomeDenied Text
  | OutcomeFailed Text
  deriving (Eq, Show)

instance ToJSON AuditOutcome where
  toJSON OutcomeSuccess = "success"
  toJSON (OutcomeDenied reason) = object ["denied" .= reason]
  toJSON (OutcomeFailed reason) = object ["failed" .= reason]

instance FromJSON AuditOutcome where
  parseJSON (String "success") = pure OutcomeSuccess
  parseJSON v = withObject "AuditOutcome" parseOutcome v
    where
      parseOutcome obj = do
        denied <- obj .:? "denied"
        failed <- obj .:? "failed"
        case (denied, failed) of
          (Just reason, _) -> pure $ OutcomeDenied reason
          (_, Just reason) -> pure $ OutcomeFailed reason
          _ -> fail "Unknown outcome"

-- | A single audit trail entry
data AuditEntry = AuditEntry
  { aeEntryId :: AuditEntryId,
    aeTimestamp :: UTCTime,
    aeTenantId :: TenantId,
    aeSubjectId :: SubjectId,
    aeArtifactId :: Text,
    aeVersionId :: Maybe Text,
    aeAction :: AuditAction,
    aeOutcome :: AuditOutcome,
    aeSourceIp :: Maybe Text,
    aeUserAgent :: Maybe Text,
    aeRequestId :: Maybe Text,
    aeDetails :: Map.Map Text Text,
    aeChecksum :: Text -- For integrity verification
  }
  deriving (Eq, Show)

instance ToJSON AuditEntry where
  toJSON AuditEntry {..} =
    object
      [ "entryId" .= aeEntryId,
        "timestamp" .= aeTimestamp,
        "tenantId" .= aeTenantId,
        "subjectId" .= aeSubjectId,
        "artifactId" .= aeArtifactId,
        "versionId" .= aeVersionId,
        "action" .= aeAction,
        "outcome" .= aeOutcome,
        "sourceIp" .= aeSourceIp,
        "userAgent" .= aeUserAgent,
        "requestId" .= aeRequestId,
        "details" .= aeDetails,
        "checksum" .= aeChecksum
      ]

instance FromJSON AuditEntry where
  parseJSON = withObject "AuditEntry" $ \obj ->
    AuditEntry
      <$> obj .: "entryId"
      <*> obj .: "timestamp"
      <*> obj .: "tenantId"
      <*> obj .: "subjectId"
      <*> obj .: "artifactId"
      <*> obj .:? "versionId"
      <*> obj .: "action"
      <*> obj .: "outcome"
      <*> obj .:? "sourceIp"
      <*> obj .:? "userAgent"
      <*> obj .:? "requestId"
      <*> obj .: "details"
      <*> obj .: "checksum"

-- | Query parameters for audit trail
data AuditQuery = AuditQuery
  { aqTenantId :: Maybe TenantId,
    aqSubjectId :: Maybe SubjectId,
    aqArtifactId :: Maybe Text,
    aqActions :: [AuditAction],
    aqFromTime :: Maybe UTCTime,
    aqToTime :: Maybe UTCTime,
    aqLimit :: Int,
    aqOffset :: Int
  }
  deriving (Eq, Show)

-- | Default audit query
defaultAuditQuery :: AuditQuery
defaultAuditQuery =
  AuditQuery
    { aqTenantId = Nothing,
      aqSubjectId = Nothing,
      aqArtifactId = Nothing,
      aqActions = [],
      aqFromTime = Nothing,
      aqToTime = Nothing,
      aqLimit = 100,
      aqOffset = 0
    }

-- | Audit report summary
data AuditReport = AuditReport
  { arTenantId :: TenantId,
    arFromTime :: UTCTime,
    arToTime :: UTCTime,
    arTotalEntries :: Int,
    arEntriesByAction :: Map.Map Text Int,
    arDeniedCount :: Int,
    arDeleteAttemptsCount :: Int,
    arUniqueSubjects :: Int,
    arUniqueArtifacts :: Int
  }
  deriving (Eq, Show)

instance ToJSON AuditReport where
  toJSON AuditReport {..} =
    object
      [ "tenantId" .= arTenantId,
        "fromTime" .= arFromTime,
        "toTime" .= arToTime,
        "totalEntries" .= arTotalEntries,
        "entriesByAction" .= arEntriesByAction,
        "deniedCount" .= arDeniedCount,
        "deleteAttemptsCount" .= arDeleteAttemptsCount,
        "uniqueSubjects" .= arUniqueSubjects,
        "uniqueArtifacts" .= arUniqueArtifacts
      ]

-- | Result of audit integrity verification
data AuditIntegrityResult
  = IntegrityValid
  | IntegrityCompromised [AuditEntryId]
  | IntegrityCheckFailed Text
  deriving (Eq, Show)

instance ToJSON AuditIntegrityResult where
  toJSON IntegrityValid = object ["status" .= ("valid" :: Text)]
  toJSON (IntegrityCompromised ids) =
    object ["status" .= ("compromised" :: Text), "invalidEntries" .= ids]
  toJSON (IntegrityCheckFailed reason) =
    object ["status" .= ("failed" :: Text), "reason" .= reason]

-- | Internal state for audit trail service
data AuditTrailState = AuditTrailState
  { atsEntries :: Map.Map AuditEntryId AuditEntry,
    atsByArtifact :: Map.Map Text [AuditEntryId],
    atsByTenant :: Map.Map TenantId [AuditEntryId],
    atsNextId :: Int
  }

data AuditTrailSnapshot = AuditTrailSnapshot
  { atsSnapshotEntries :: [AuditEntry],
    atsSnapshotNextId :: Int
  }

instance ToJSON AuditTrailSnapshot where
  toJSON AuditTrailSnapshot {..} =
    object
      [ "entries" .= atsSnapshotEntries,
        "nextId" .= atsSnapshotNextId
      ]

instance FromJSON AuditTrailSnapshot where
  parseJSON = withObject "AuditTrailSnapshot" $ \obj ->
    AuditTrailSnapshot
      <$> obj .:? "entries" .!= []
      <*> obj .:? "nextId" .!= 1

-- | Audit trail service
data AuditTrailService = AuditTrailService
  { atsState :: TVar AuditTrailState,
    atsPersistencePath :: Maybe FilePath
  }

-- | Create a new audit trail service
newAuditTrailService :: IO AuditTrailService
newAuditTrailService = newAuditTrailServiceInternal Nothing

newAuditTrailServiceWithFile :: FilePath -> IO AuditTrailService
newAuditTrailServiceWithFile persistencePath =
  newAuditTrailServiceInternal (Just persistencePath)

newAuditTrailServiceInternal :: Maybe FilePath -> IO AuditTrailService
newAuditTrailServiceInternal maybePersistencePath = do
  initialState <-
    case maybePersistencePath of
      Just persistencePath -> loadAuditTrailState persistencePath
      Nothing -> pure emptyAuditTrailState
  stateVar <- newTVarIO initialState
  pure
    AuditTrailService
      { atsState = stateVar,
        atsPersistencePath = maybePersistencePath
      }

-- | Record a new audit entry
recordAuditEntry ::
  AuditTrailService ->
  TenantId ->
  SubjectId ->
  Text ->
  Maybe Text ->
  AuditAction ->
  AuditOutcome ->
  Map.Map Text Text ->
  IO AuditEntry
recordAuditEntry service tenantId subjectId artifactId versionId action outcome details = do
  now <- getCurrentTime
  entryId <- atomically $ do
    state <- readTVar (atsState service)
    let nextId = atsNextId state
        entryIdText = "audit-" <> T.pack (show nextId)
    modifyTVar' (atsState service) $ \s -> s {atsNextId = nextId + 1}
    pure $ AuditEntryId entryIdText
  let checksum = computeChecksum tenantId subjectId artifactId action now
      entry =
        AuditEntry
          { aeEntryId = entryId,
            aeTimestamp = now,
            aeTenantId = tenantId,
            aeSubjectId = subjectId,
            aeArtifactId = artifactId,
            aeVersionId = versionId,
            aeAction = action,
            aeOutcome = outcome,
            aeSourceIp = Map.lookup "sourceIp" details,
            aeUserAgent = Map.lookup "userAgent" details,
            aeRequestId = Map.lookup "requestId" details,
            aeDetails = details,
            aeChecksum = checksum
          }
  atomically $ modifyTVar' (atsState service) $ \s ->
    s
      { atsEntries = Map.insert entryId entry (atsEntries s),
        atsByArtifact =
          Map.insertWith (++) artifactId [entryId] (atsByArtifact s),
        atsByTenant =
          Map.insertWith (++) tenantId [entryId] (atsByTenant s)
      }
  persistAuditTrailState service
  pure entry

-- | Record an access attempt
recordAccessAttempt ::
  AuditTrailService ->
  TenantId ->
  SubjectId ->
  Text ->
  Bool ->
  Text ->
  IO AuditEntry
recordAccessAttempt service tenantId subjectId artifactId allowed reason =
  recordAuditEntry
    service
    tenantId
    subjectId
    artifactId
    Nothing
    (if allowed then AuditRead else AuditAccessDenied)
    (if allowed then OutcomeSuccess else OutcomeDenied reason)
    Map.empty

-- | Record a state change
recordStateChange ::
  AuditTrailService ->
  TenantId ->
  SubjectId ->
  Text ->
  GovernanceAction ->
  ArtifactState ->
  IO AuditEntry
recordStateChange service tenantId subjectId artifactId action _newState =
  recordAuditEntry
    service
    tenantId
    subjectId
    artifactId
    Nothing
    (AuditStateChange action)
    OutcomeSuccess
    Map.empty

-- | Record a deletion attempt (always denied)
recordDeletionAttempt ::
  AuditTrailService ->
  TenantId ->
  SubjectId ->
  Text ->
  Text ->
  IO AuditEntry
recordDeletionAttempt service tenantId subjectId artifactId reason =
  recordAuditEntry
    service
    tenantId
    subjectId
    artifactId
    Nothing
    AuditDeleteAttempt
    (OutcomeDenied reason)
    (Map.singleton "denialReason" reason)

-- | Get a specific audit entry
getAuditEntry ::
  AuditTrailService ->
  AuditEntryId ->
  IO (Maybe AuditEntry)
getAuditEntry service entryId = do
  state <- readTVarIO (atsState service)
  pure $ Map.lookup entryId (atsEntries state)

-- | Query the audit trail
queryAuditTrail ::
  AuditTrailService ->
  AuditQuery ->
  IO [AuditEntry]
queryAuditTrail service query = do
  state <- readTVarIO (atsState service)
  let allEntries = Map.elems (atsEntries state)
      filtered = filter (matchesQuery query) allEntries
      sorted = reverse (sortOn aeTimestamp filtered)
      paginated = take (aqLimit query) $ drop (aqOffset query) sorted
  pure paginated

-- | Check if an entry matches a query
matchesQuery :: AuditQuery -> AuditEntry -> Bool
matchesQuery query entry =
  matchTenant && matchSubject && matchArtifact && matchTime && matchActions
  where
    matchTenant = case aqTenantId query of
      Nothing -> True
      Just tid -> aeTenantId entry == tid
    matchSubject = case aqSubjectId query of
      Nothing -> True
      Just sid -> aeSubjectId entry == sid
    matchArtifact = case aqArtifactId query of
      Nothing -> True
      Just aid -> aeArtifactId entry == aid
    matchTime =
      let fromOk = case aqFromTime query of
            Nothing -> True
            Just t -> aeTimestamp entry >= t
          toOk = case aqToTime query of
            Nothing -> True
            Just t -> aeTimestamp entry <= t
       in fromOk && toOk
    matchActions = case aqActions query of
      [] -> True
      actions -> aeAction entry `elem` actions

-- | Generate an audit report for a tenant
generateAuditReport ::
  AuditTrailService ->
  TenantId ->
  UTCTime ->
  UTCTime ->
  IO AuditReport
generateAuditReport service tenantId fromTime toTime = do
  entries <-
    queryAuditTrail
      service
      defaultAuditQuery
        { aqTenantId = Just tenantId,
          aqFromTime = Just fromTime,
          aqToTime = Just toTime,
          aqLimit = 10000
        }
  let actionCounts = foldr countAction Map.empty entries
      deniedCount = length $ filter isDenied entries
      deleteCount = length $ filter isDeleteAttempt entries
      subjects = length $ unique $ map (extractSubjectId . aeSubjectId) entries
      artifacts = length $ unique $ map aeArtifactId entries
  pure
    AuditReport
      { arTenantId = tenantId,
        arFromTime = fromTime,
        arToTime = toTime,
        arTotalEntries = length entries,
        arEntriesByAction = actionCounts,
        arDeniedCount = deniedCount,
        arDeleteAttemptsCount = deleteCount,
        arUniqueSubjects = subjects,
        arUniqueArtifacts = artifacts
      }
  where
    countAction entry acc =
      let key = actionToText (aeAction entry)
       in Map.insertWith (+) key 1 acc
    isDenied entry = case aeOutcome entry of
      OutcomeDenied _ -> True
      _ -> False
    isDeleteAttempt entry = case aeAction entry of
      AuditDeleteAttempt -> True
      _ -> False
    unique = Map.keys . Map.fromList . map (\x -> (x, ()))

-- | Verify integrity of audit trail
verifyAuditIntegrity ::
  AuditTrailService ->
  TenantId ->
  IO AuditIntegrityResult
verifyAuditIntegrity service tenantId = do
  entries <-
    queryAuditTrail
      service
      defaultAuditQuery {aqTenantId = Just tenantId, aqLimit = 10000}
  let invalidEntries = filter (not . verifyChecksum) entries
  if null invalidEntries
    then pure IntegrityValid
    else pure $ IntegrityCompromised $ map aeEntryId invalidEntries

-- | Verify checksum of an entry
verifyChecksum :: AuditEntry -> Bool
verifyChecksum entry =
  let expected =
        computeChecksum
          (aeTenantId entry)
          (aeSubjectId entry)
          (aeArtifactId entry)
          (aeAction entry)
          (aeTimestamp entry)
   in aeChecksum entry == expected

-- | Compute checksum for an entry
computeChecksum :: TenantId -> SubjectId -> Text -> AuditAction -> UTCTime -> Text
computeChecksum (TenantId tid) (SubjectId sid) artifactId action timestamp =
  "sha256:" <> T.pack (show (hash combined))
  where
    combined = tid <> sid <> artifactId <> actionToText action <> T.pack (show timestamp)
    hash :: Text -> Int
    hash = T.foldl' (\acc c -> acc * 31 + fromEnum c) 0

-- | Convert action to text for checksums
actionToText :: AuditAction -> Text
actionToText AuditCreate = "create"
actionToText AuditRead = "read"
actionToText AuditUpdate = "update"
actionToText (AuditStateChange _) = "state_change"
actionToText AuditDeleteAttempt = "delete_attempt"
actionToText AuditAccessDenied = "access_denied"
actionToText AuditPresignedUrlGenerated = "presigned_url"
actionToText AuditVersionCreated = "version_created"
actionToText AuditSupersede = "supersede"

-- | Extract text from SubjectId
extractSubjectId :: SubjectId -> Text
extractSubjectId (SubjectId t) = t

emptyAuditTrailState :: AuditTrailState
emptyAuditTrailState =
  AuditTrailState
    { atsEntries = Map.empty,
      atsByArtifact = Map.empty,
      atsByTenant = Map.empty,
      atsNextId = 1
    }

auditTrailSnapshot :: AuditTrailState -> AuditTrailSnapshot
auditTrailSnapshot state =
  AuditTrailSnapshot
    { atsSnapshotEntries = sortOn aeTimestamp (Map.elems (atsEntries state)),
      atsSnapshotNextId = atsNextId state
    }

rebuildAuditTrailState :: AuditTrailSnapshot -> AuditTrailState
rebuildAuditTrailState snapshot =
  foldr insertEntry baseState (atsSnapshotEntries snapshot)
  where
    baseState =
      emptyAuditTrailState
        { atsNextId = atsSnapshotNextId snapshot
        }

    insertEntry entry state =
      let entryId = aeEntryId entry
       in state
            { atsEntries = Map.insert entryId entry (atsEntries state),
              atsByArtifact = Map.insertWith (++) (aeArtifactId entry) [entryId] (atsByArtifact state),
              atsByTenant = Map.insertWith (++) (aeTenantId entry) [entryId] (atsByTenant state)
            }

loadAuditTrailState :: FilePath -> IO AuditTrailState
loadAuditTrailState persistencePath = do
  exists <- doesFileExist persistencePath
  if not exists
    then pure emptyAuditTrailState
    else do
      rawBytes <- LBS.readFile persistencePath
      pure $
        maybe emptyAuditTrailState rebuildAuditTrailState (decode rawBytes)

persistAuditTrailState :: AuditTrailService -> IO ()
persistAuditTrailState service =
  case atsPersistencePath service of
    Nothing -> pure ()
    Just persistencePath -> do
      currentState <- readTVarIO (atsState service)
      createDirectoryIfMissing True (takeDirectory persistencePath)
      LBS.writeFile persistencePath (encode (auditTrailSnapshot currentState))
