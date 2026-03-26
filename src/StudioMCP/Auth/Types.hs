{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Auth.Types
  ( -- * Authentication Errors
    AuthError (..),
    authErrorToText,
    authErrorToHttpStatus,

    -- * JWT Claims
    JwtClaims (..),
    RawJwt (..),

    -- * Subject and Identity
    SubjectId (..),
    Subject (..),

    -- * Tenant Context
    TenantId (..),
    Tenant (..),

    -- * Scopes and Roles
    Scope (..),
    Role (..),
    Permission (..),

    -- * Auth Context
    AuthContext (..),
    AuthenticatedRequest (..),

    -- * Validation Results
    TokenValidationResult (..),
    AuthDecision (..),
  )
where

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
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime)
import GHC.Generics (Generic)
import Network.HTTP.Types (Status, status401, status403, status500)

-- | Raw JWT token
newtype RawJwt = RawJwt Text
  deriving (Eq, Show, Generic)

-- | Subject identifier (user ID from Keycloak)
newtype SubjectId = SubjectId Text
  deriving (Eq, Show, Ord, Generic)

instance ToJSON SubjectId where
  toJSON (SubjectId s) = toJSON s

instance FromJSON SubjectId where
  parseJSON v = SubjectId <$> parseJSON v

-- | Tenant identifier
newtype TenantId = TenantId Text
  deriving (Eq, Show, Ord, Generic)

instance ToJSON TenantId where
  toJSON (TenantId t) = toJSON t

instance FromJSON TenantId where
  parseJSON v = TenantId <$> parseJSON v

-- | OAuth scope
newtype Scope = Scope Text
  deriving (Eq, Show, Ord, Generic)

instance ToJSON Scope where
  toJSON (Scope s) = toJSON s

instance FromJSON Scope where
  parseJSON v = Scope <$> parseJSON v

-- | User role
newtype Role = Role Text
  deriving (Eq, Show, Ord, Generic)

instance ToJSON Role where
  toJSON (Role r) = toJSON r

instance FromJSON Role where
  parseJSON v = Role <$> parseJSON v

-- | Authentication error types
data AuthError
  = -- | Token is missing from request
    MissingToken
  | -- | Token format is invalid (not a valid JWT structure)
    InvalidTokenFormat Text
  | -- | Token signature verification failed
    InvalidSignature
  | -- | Token has expired
    TokenExpired
  | -- | Token not yet valid (nbf claim)
    TokenNotYetValid
  | -- | Invalid issuer
    InvalidIssuer Text
  | -- | Invalid audience
    InvalidAudience Text
  | -- | Required claim is missing
    MissingClaim Text
  | -- | Tenant could not be resolved
    TenantResolutionFailed
  | -- | Insufficient scopes for operation
    InsufficientScopes (Set Scope) (Set Scope) -- required, present
  | -- | Insufficient roles for operation
    InsufficientRoles (Set Role) (Set Role) -- required, present
  | -- | JWKS fetch failed
    JwksFetchError Text
  | -- | Internal auth error
    InternalAuthError Text
  deriving (Eq, Show, Generic)

instance ToJSON AuthError where
  toJSON err =
    object
      [ "error" .= authErrorToText err,
        "code" .= authErrorCode err
      ]

-- | Convert auth error to human-readable text
authErrorToText :: AuthError -> Text
authErrorToText MissingToken = "Missing authentication token"
authErrorToText (InvalidTokenFormat msg) = "Invalid token format: " <> msg
authErrorToText InvalidSignature = "Token signature verification failed"
authErrorToText TokenExpired = "Token has expired"
authErrorToText TokenNotYetValid = "Token is not yet valid"
authErrorToText (InvalidIssuer iss) = "Invalid token issuer: " <> iss
authErrorToText (InvalidAudience aud) = "Invalid token audience: " <> aud
authErrorToText (MissingClaim claim) = "Missing required claim: " <> claim
authErrorToText TenantResolutionFailed = "Could not resolve tenant context"
authErrorToText (InsufficientScopes req _) =
  "Insufficient scopes. Required: " <> T.intercalate ", " (map (\(Scope s) -> s) $ Set.toList req)
authErrorToText (InsufficientRoles req _) =
  "Insufficient roles. Required: " <> T.intercalate ", " (map (\(Role r) -> r) $ Set.toList req)
authErrorToText (JwksFetchError msg) = "Failed to fetch JWKS: " <> msg
authErrorToText (InternalAuthError msg) = "Internal authentication error: " <> msg

-- | Get error code for auth error
authErrorCode :: AuthError -> Text
authErrorCode MissingToken = "missing_token"
authErrorCode (InvalidTokenFormat _) = "invalid_token_format"
authErrorCode InvalidSignature = "invalid_signature"
authErrorCode TokenExpired = "token_expired"
authErrorCode TokenNotYetValid = "token_not_yet_valid"
authErrorCode (InvalidIssuer _) = "invalid_issuer"
authErrorCode (InvalidAudience _) = "invalid_audience"
authErrorCode (MissingClaim _) = "missing_claim"
authErrorCode TenantResolutionFailed = "tenant_resolution_failed"
authErrorCode (InsufficientScopes _ _) = "insufficient_scopes"
authErrorCode (InsufficientRoles _ _) = "insufficient_roles"
authErrorCode (JwksFetchError _) = "jwks_fetch_error"
authErrorCode (InternalAuthError _) = "internal_error"

-- | Map auth error to HTTP status code
authErrorToHttpStatus :: AuthError -> Status
authErrorToHttpStatus MissingToken = status401
authErrorToHttpStatus (InvalidTokenFormat _) = status401
authErrorToHttpStatus InvalidSignature = status401
authErrorToHttpStatus TokenExpired = status401
authErrorToHttpStatus TokenNotYetValid = status401
authErrorToHttpStatus (InvalidIssuer _) = status401
authErrorToHttpStatus (InvalidAudience _) = status401
authErrorToHttpStatus (MissingClaim _) = status401
authErrorToHttpStatus TenantResolutionFailed = status403
authErrorToHttpStatus (InsufficientScopes _ _) = status403
authErrorToHttpStatus (InsufficientRoles _ _) = status403
authErrorToHttpStatus (JwksFetchError _) = status500
authErrorToHttpStatus (InternalAuthError _) = status500

-- | Parsed JWT claims
data JwtClaims = JwtClaims
  { jcIssuer :: Text,
    jcSubject :: SubjectId,
    jcAudience :: [Text],
    jcExpiration :: UTCTime,
    jcIssuedAt :: UTCTime,
    jcNotBefore :: Maybe UTCTime,
    jcAuthorizedParty :: Maybe Text,
    jcTenantId :: Maybe TenantId,
    jcScopes :: Set Scope,
    jcRealmRoles :: Set Role,
    jcResourceRoles :: Set Role,
    jcEmail :: Maybe Text,
    jcEmailVerified :: Maybe Bool,
    jcName :: Maybe Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON JwtClaims where
  toJSON jc =
    object
      [ "iss" .= jcIssuer jc,
        "sub" .= jcSubject jc,
        "aud" .= jcAudience jc,
        "exp" .= jcExpiration jc,
        "iat" .= jcIssuedAt jc,
        "nbf" .= jcNotBefore jc,
        "azp" .= jcAuthorizedParty jc,
        "tenant_id" .= jcTenantId jc,
        "scopes" .= jcScopes jc,
        "realm_roles" .= jcRealmRoles jc,
        "resource_roles" .= jcResourceRoles jc,
        "email" .= jcEmail jc,
        "email_verified" .= jcEmailVerified jc,
        "name" .= jcName jc
      ]

-- | Authenticated subject
data Subject = Subject
  { subjectId :: SubjectId,
    subjectEmail :: Maybe Text,
    subjectName :: Maybe Text,
    subjectRoles :: Set Role,
    subjectScopes :: Set Scope
  }
  deriving (Eq, Show, Generic)

instance ToJSON Subject where
  toJSON s =
    object
      [ "id" .= subjectId s,
        "email" .= subjectEmail s,
        "name" .= subjectName s,
        "roles" .= subjectRoles s,
        "scopes" .= subjectScopes s
      ]

instance FromJSON Subject where
  parseJSON = withObject "Subject" $ \obj ->
    Subject
      <$> obj .: "id"
      <*> obj .:? "email"
      <*> obj .:? "name"
      <*> obj .: "roles"
      <*> obj .: "scopes"

-- | Tenant context
data Tenant = Tenant
  { tenantId :: TenantId,
    tenantName :: Maybe Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON Tenant where
  toJSON t =
    object
      [ "id" .= tenantId t,
        "name" .= tenantName t
      ]

instance FromJSON Tenant where
  parseJSON = withObject "Tenant" $ \obj ->
    Tenant
      <$> obj .: "id"
      <*> obj .:? "name"

-- | Permission for authorization checks
data Permission
  = WorkflowRead
  | WorkflowWrite
  | ArtifactRead
  | ArtifactWrite
  | ArtifactManage
  | PromptRead
  | ResourceRead
  | AdminAccess
  deriving (Eq, Show, Ord, Generic, Enum, Bounded)

instance ToJSON Permission where
  toJSON WorkflowRead = "workflow:read"
  toJSON WorkflowWrite = "workflow:write"
  toJSON ArtifactRead = "artifact:read"
  toJSON ArtifactWrite = "artifact:write"
  toJSON ArtifactManage = "artifact:manage"
  toJSON PromptRead = "prompt:read"
  toJSON ResourceRead = "resource:read"
  toJSON AdminAccess = "admin:access"

instance FromJSON Permission where
  parseJSON = withText "Permission" $ \t ->
    case t of
      "workflow:read" -> pure WorkflowRead
      "workflow:write" -> pure WorkflowWrite
      "artifact:read" -> pure ArtifactRead
      "artifact:write" -> pure ArtifactWrite
      "artifact:manage" -> pure ArtifactManage
      "prompt:read" -> pure PromptRead
      "resource:read" -> pure ResourceRead
      "admin:access" -> pure AdminAccess
      _ -> fail $ "Unknown permission: " <> T.unpack t

-- | Full authentication context after successful auth
data AuthContext = AuthContext
  { acSubject :: Subject,
    acTenant :: Tenant,
    acClaims :: JwtClaims,
    acCorrelationId :: Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON AuthContext where
  toJSON ac =
    object
      [ "subject" .= acSubject ac,
        "tenant" .= acTenant ac,
        "correlationId" .= acCorrelationId ac
      ]

-- | Authenticated request wrapper
data AuthenticatedRequest a = AuthenticatedRequest
  { arContext :: AuthContext,
    arPayload :: a
  }
  deriving (Eq, Show, Generic)

-- | Result of token validation
data TokenValidationResult
  = TokenValid JwtClaims
  | TokenInvalid AuthError
  deriving (Eq, Show, Generic)

-- | Authorization decision
data AuthDecision
  = Allowed
  | Denied AuthError
  deriving (Eq, Show, Generic)

instance ToJSON AuthDecision where
  toJSON Allowed = object ["decision" .= ("allowed" :: Text)]
  toJSON (Denied err) = object ["decision" .= ("denied" :: Text), "reason" .= err]
