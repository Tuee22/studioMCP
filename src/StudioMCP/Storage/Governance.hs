{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module StudioMCP.Storage.Governance
  ( -- * Artifact State
    ArtifactState (..),
    ArtifactStateTransition (..),
    isArtifactAccessible,

    -- * Governance Policy
    GovernancePolicy (..),
    defaultGovernancePolicy,
    GovernanceAction (..),

    -- * Governance Service
    GovernanceService (..),
    newGovernanceService,

    -- * State Transitions
    hideArtifact,
    archiveArtifact,
    supersedeArtifact,
    restoreArtifact,

    -- * Forbidden Operations
    GovernanceError (..),
    governanceErrorCode,
    denyHardDelete,

    -- * State Queries
    getArtifactState,
    getArtifactHistory,

    -- * Governance Metadata
    GovernanceMetadata (..),
    ArtifactStateRecord (..),
  )
where

import Control.Concurrent.STM (TVar, atomically, modifyTVar', newTVarIO, readTVarIO)
import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    object,
    withObject,
    withText,
    (.:),
    (.:?),
    (.=),
  )
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime, getCurrentTime)
import StudioMCP.Auth.Types (SubjectId (..), TenantId (..))

-- | State of an artifact in the governance system
data ArtifactState
  = -- | Artifact is active and accessible
    Active
  | -- | Artifact is hidden from default listings but accessible by ID
    Hidden
  | -- | Artifact is archived (read-only, may be moved to cold storage)
    Archived
  | -- | Artifact is superseded by another version
    Superseded Text -- ^ New artifact ID that supersedes this one
  deriving (Eq, Show)

instance ToJSON ArtifactState where
  toJSON Active = "active"
  toJSON Hidden = "hidden"
  toJSON Archived = "archived"
  toJSON (Superseded newId) = object ["superseded_by" .= newId]

instance FromJSON ArtifactState where
  parseJSON = withText "ArtifactState" $ \t ->
    case t of
      "active" -> pure Active
      "hidden" -> pure Hidden
      "archived" -> pure Archived
      _ -> fail $ "Unknown artifact state: " <> T.unpack t

-- | Represents a state transition
data ArtifactStateTransition
  = TransitionToHidden
  | TransitionToArchived
  | TransitionToSuperseded Text
  | TransitionToActive
  deriving (Eq, Show)

instance ToJSON ArtifactStateTransition where
  toJSON TransitionToHidden = "to_hidden"
  toJSON TransitionToArchived = "to_archived"
  toJSON (TransitionToSuperseded newId) = object ["to_superseded" .= newId]
  toJSON TransitionToActive = "to_active"

-- | Check if an artifact is accessible for reads
isArtifactAccessible :: ArtifactState -> Bool
isArtifactAccessible Active = True
isArtifactAccessible Hidden = True -- Accessible by ID
isArtifactAccessible Archived = True -- Read-only access
isArtifactAccessible (Superseded _) = True -- Still accessible, but will show redirect

-- | Actions that can be performed under governance
data GovernanceAction
  = ActionHide
  | ActionArchive
  | ActionSupersede
  | ActionRestore
  | ActionDelete -- Always forbidden
  deriving (Eq, Ord, Show)

instance ToJSON GovernanceAction where
  toJSON ActionHide = "hide"
  toJSON ActionArchive = "archive"
  toJSON ActionSupersede = "supersede"
  toJSON ActionRestore = "restore"
  toJSON ActionDelete = "delete"

instance FromJSON GovernanceAction where
  parseJSON = withText "GovernanceAction" $ \t ->
    case t of
      "hide" -> pure ActionHide
      "archive" -> pure ActionArchive
      "supersede" -> pure ActionSupersede
      "restore" -> pure ActionRestore
      "delete" -> pure ActionDelete
      _ -> fail $ "Unknown governance action: " <> T.unpack t

-- | Governance policy configuration
data GovernancePolicy = GovernancePolicy
  { -- | Allow restoration of hidden artifacts
    gpAllowRestoreFromHidden :: Bool,
    -- | Allow restoration of archived artifacts
    gpAllowRestoreFromArchived :: Bool,
    -- | Minimum retention period before archival (seconds)
    gpMinRetentionBeforeArchive :: Int,
    -- | Required scopes for governance actions
    gpRequiredScopes :: Map.Map GovernanceAction [Text],
    -- | Permanently deny hard deletion
    gpDenyHardDelete :: Bool
  }
  deriving (Eq, Show)

-- | Default governance policy
defaultGovernancePolicy :: GovernancePolicy
defaultGovernancePolicy =
  GovernancePolicy
    { gpAllowRestoreFromHidden = True,
      gpAllowRestoreFromArchived = False, -- Archived is typically permanent
      gpMinRetentionBeforeArchive = 86400 * 30, -- 30 days
      gpRequiredScopes =
        Map.fromList
          [ (ActionHide, ["artifacts:hide"]),
            (ActionArchive, ["artifacts:archive"]),
            (ActionSupersede, ["artifacts:write"]),
            (ActionRestore, ["artifacts:restore"]),
            (ActionDelete, []) -- No scope allows delete
          ],
      gpDenyHardDelete = True
    }

-- | Governance errors
data GovernanceError
  = -- | Hard deletion is forbidden
    HardDeleteForbidden Text
  | -- | State transition not allowed
    TransitionNotAllowed ArtifactState ArtifactStateTransition
  | -- | Missing required scope
    MissingScopeForAction GovernanceAction Text
  | -- | Artifact not found in governance system
    ArtifactNotInGovernance Text
  | -- | Operation violates retention policy
    RetentionPolicyViolation Text
  | -- | Superseding artifact not found
    SupersedingArtifactNotFound Text
  deriving (Eq, Show)

-- | Get error code for governance error
governanceErrorCode :: GovernanceError -> Text
governanceErrorCode (HardDeleteForbidden _) = "hard-delete-forbidden"
governanceErrorCode (TransitionNotAllowed _ _) = "transition-not-allowed"
governanceErrorCode (MissingScopeForAction _ _) = "missing-scope"
governanceErrorCode (ArtifactNotInGovernance _) = "artifact-not-in-governance"
governanceErrorCode (RetentionPolicyViolation _) = "retention-policy-violation"
governanceErrorCode (SupersedingArtifactNotFound _) = "superseding-artifact-not-found"

-- | Metadata for governance decisions
data GovernanceMetadata = GovernanceMetadata
  { gmReason :: Text,
    gmRequestedBy :: SubjectId,
    gmTenantId :: TenantId,
    gmTimestamp :: UTCTime,
    gmRelatedArtifacts :: [Text]
  }
  deriving (Eq, Show)

instance ToJSON GovernanceMetadata where
  toJSON GovernanceMetadata {..} =
    object
      [ "reason" .= gmReason,
        "requestedBy" .= gmRequestedBy,
        "tenantId" .= gmTenantId,
        "timestamp" .= gmTimestamp,
        "relatedArtifacts" .= gmRelatedArtifacts
      ]

instance FromJSON GovernanceMetadata where
  parseJSON = withObject "GovernanceMetadata" $ \obj ->
    GovernanceMetadata
      <$> obj .: "reason"
      <*> obj .: "requestedBy"
      <*> obj .: "tenantId"
      <*> obj .: "timestamp"
      <*> obj .: "relatedArtifacts"

-- | Record of an artifact's state at a point in time
data ArtifactStateRecord = ArtifactStateRecord
  { asrArtifactId :: Text,
    asrState :: ArtifactState,
    asrTransition :: Maybe ArtifactStateTransition,
    asrMetadata :: GovernanceMetadata
  }
  deriving (Eq, Show)

instance ToJSON ArtifactStateRecord where
  toJSON ArtifactStateRecord {..} =
    object
      [ "artifactId" .= asrArtifactId,
        "state" .= asrState,
        "transition" .= asrTransition,
        "metadata" .= asrMetadata
      ]

-- | Internal state for governance service
data GovernanceState = GovernanceState
  { gsArtifactStates :: Map.Map Text ArtifactState,
    gsStateHistory :: Map.Map Text [ArtifactStateRecord]
  }

-- | Governance service
data GovernanceService = GovernanceService
  { gsPolicy :: GovernancePolicy,
    gsState :: TVar GovernanceState
  }

-- | Create a new governance service
newGovernanceService :: GovernancePolicy -> IO GovernanceService
newGovernanceService policy = do
  stateVar <-
    newTVarIO
      GovernanceState
        { gsArtifactStates = Map.empty,
          gsStateHistory = Map.empty
        }
  pure
    GovernanceService
      { gsPolicy = policy,
        gsState = stateVar
      }

-- | Hide an artifact
hideArtifact ::
  GovernanceService ->
  Text ->
  GovernanceMetadata ->
  IO (Either GovernanceError ArtifactStateRecord)
hideArtifact service artifactId metadata = do
  state <- readTVarIO (gsState service)
  let currentState = Map.findWithDefault Active artifactId (gsArtifactStates state)
  case currentState of
    Archived ->
      pure $ Left $ TransitionNotAllowed currentState TransitionToHidden
    Superseded _ ->
      pure $ Left $ TransitionNotAllowed currentState TransitionToHidden
    _ -> do
      let record =
            ArtifactStateRecord
              { asrArtifactId = artifactId,
                asrState = Hidden,
                asrTransition = Just TransitionToHidden,
                asrMetadata = metadata
              }
      atomically $ modifyTVar' (gsState service) $ \s ->
        s
          { gsArtifactStates = Map.insert artifactId Hidden (gsArtifactStates s),
            gsStateHistory =
              Map.insertWith (++) artifactId [record] (gsStateHistory s)
          }
      pure $ Right record

-- | Archive an artifact
archiveArtifact ::
  GovernanceService ->
  Text ->
  GovernanceMetadata ->
  IO (Either GovernanceError ArtifactStateRecord)
archiveArtifact service artifactId metadata = do
  state <- readTVarIO (gsState service)
  let currentState = Map.findWithDefault Active artifactId (gsArtifactStates state)
  case currentState of
    Archived ->
      pure $ Left $ TransitionNotAllowed currentState TransitionToArchived
    _ -> do
      let record =
            ArtifactStateRecord
              { asrArtifactId = artifactId,
                asrState = Archived,
                asrTransition = Just TransitionToArchived,
                asrMetadata = metadata
              }
      atomically $ modifyTVar' (gsState service) $ \s ->
        s
          { gsArtifactStates = Map.insert artifactId Archived (gsArtifactStates s),
            gsStateHistory =
              Map.insertWith (++) artifactId [record] (gsStateHistory s)
          }
      pure $ Right record

-- | Supersede an artifact with a new one
supersedeArtifact ::
  GovernanceService ->
  Text ->
  Text ->
  GovernanceMetadata ->
  IO (Either GovernanceError ArtifactStateRecord)
supersedeArtifact service artifactId newArtifactId metadata = do
  state <- readTVarIO (gsState service)
  let currentState = Map.findWithDefault Active artifactId (gsArtifactStates state)
  case currentState of
    Archived ->
      pure $ Left $ TransitionNotAllowed currentState (TransitionToSuperseded newArtifactId)
    Superseded _ ->
      pure $ Left $ TransitionNotAllowed currentState (TransitionToSuperseded newArtifactId)
    _ -> do
      let newState = Superseded newArtifactId
          record =
            ArtifactStateRecord
              { asrArtifactId = artifactId,
                asrState = newState,
                asrTransition = Just (TransitionToSuperseded newArtifactId),
                asrMetadata = metadata {gmRelatedArtifacts = [newArtifactId]}
              }
      atomically $ modifyTVar' (gsState service) $ \s ->
        s
          { gsArtifactStates = Map.insert artifactId newState (gsArtifactStates s),
            gsStateHistory =
              Map.insertWith (++) artifactId [record] (gsStateHistory s)
          }
      pure $ Right record

-- | Restore an artifact to active state
restoreArtifact ::
  GovernanceService ->
  Text ->
  GovernanceMetadata ->
  IO (Either GovernanceError ArtifactStateRecord)
restoreArtifact service artifactId metadata = do
  state <- readTVarIO (gsState service)
  let policy = gsPolicy service
      currentState = Map.findWithDefault Active artifactId (gsArtifactStates state)
  case currentState of
    Active ->
      pure $ Left $ TransitionNotAllowed currentState TransitionToActive
    Hidden
      | not (gpAllowRestoreFromHidden policy) ->
          pure $ Left $ TransitionNotAllowed currentState TransitionToActive
    Archived
      | not (gpAllowRestoreFromArchived policy) ->
          pure $ Left $ TransitionNotAllowed currentState TransitionToActive
    Superseded _ ->
      -- Cannot restore superseded artifacts
      pure $ Left $ TransitionNotAllowed currentState TransitionToActive
    _ -> do
      let record =
            ArtifactStateRecord
              { asrArtifactId = artifactId,
                asrState = Active,
                asrTransition = Just TransitionToActive,
                asrMetadata = metadata
              }
      atomically $ modifyTVar' (gsState service) $ \s ->
        s
          { gsArtifactStates = Map.insert artifactId Active (gsArtifactStates s),
            gsStateHistory =
              Map.insertWith (++) artifactId [record] (gsStateHistory s)
          }
      pure $ Right record

-- | Deny hard deletion (always fails)
denyHardDelete ::
  GovernanceService ->
  Text ->
  GovernanceMetadata ->
  IO (Either GovernanceError ())
denyHardDelete service artifactId _metadata =
  if gpDenyHardDelete (gsPolicy service)
    then pure $ Left $ HardDeleteForbidden artifactId
    else pure $ Left $ HardDeleteForbidden artifactId -- Always deny

-- | Get current state of an artifact
getArtifactState ::
  GovernanceService ->
  Text ->
  IO ArtifactState
getArtifactState service artifactId = do
  state <- readTVarIO (gsState service)
  pure $ Map.findWithDefault Active artifactId (gsArtifactStates state)

-- | Get full history of an artifact's state changes
getArtifactHistory ::
  GovernanceService ->
  Text ->
  IO [ArtifactStateRecord]
getArtifactHistory service artifactId = do
  state <- readTVarIO (gsState service)
  pure $ Map.findWithDefault [] artifactId (gsStateHistory state)
