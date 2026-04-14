{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module StudioMCP.Auth.Claims
  ( -- * Claim Extraction
    extractClaims,
    payloadToClaims,

    -- * Subject Extraction
    extractSubject,

    -- * Tenant Resolution
    resolveTenant,
    TenantResolutionStrategy (..),

    -- * Scope Extraction
    extractScopes,
    extractRealmRoles,
    extractResourceRoles,

    -- * Claim Helpers
    getStringClaim,
    getArrayClaim,
    getBoolClaim,
  )
where

import Control.Applicative ((<|>))
import Data.Aeson (Value (..))
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Aeson.Key as K
import Data.Maybe (mapMaybe)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime, addUTCTime)
import qualified Data.Vector as V
import StudioMCP.Auth.Jwks (JwtPayload (..))
import StudioMCP.Auth.Types

-- | Strategy for resolving tenant from claims
data TenantResolutionStrategy
  = -- | Use explicit tenant_id claim
    ExplicitTenantClaim
  | -- | Extract from azp.tenant claim
    AuthorizedPartyTenant
  | -- | Extract from resource_access roles (e.g., tenant:acme-corp)
    RoleBasedTenant
  | -- | Try all strategies in order
    CombinedStrategy
  deriving (Eq, Show)

-- | Extract JwtClaims from validated payload
extractClaims :: JwtPayload -> Either AuthError JwtClaims
extractClaims payload = do
  -- Required claims
  iss <- maybe (Left $ MissingClaim "iss") Right (jpIss payload)
  sub <- maybe (Left $ MissingClaim "sub") Right (jpSub payload)
  expiresAtEpoch <- maybe (Left $ MissingClaim "exp") Right (jpExp payload)
  iat <- maybe (Left $ MissingClaim "iat") Right (jpIat payload)

  -- Parse audience
  aud <- case jpAud payload of
    Nothing -> Left $ MissingClaim "aud"
    Just audValue -> Right $ extractAudiences audValue

  -- Optional claims
  let nbf = jpNbf payload
      azp = jpAzp payload
      tenantId = TenantId <$> jpTenantId payload
      email = jpEmail payload
      emailVerified = jpEmailVerified payload
      name = jpName payload

  -- Extract scopes from scope claim
  let scopes = extractScopes payload

  -- Extract roles
  let realmRoles = extractRealmRoles payload
      resourceRoles = extractResourceRoles payload

  Right
    JwtClaims
      { jcIssuer = iss,
        jcSubject = SubjectId sub,
        jcAudience = aud,
        jcExpiration = posixToUTC expiresAtEpoch,
        jcIssuedAt = posixToUTC iat,
        jcNotBefore = posixToUTC <$> nbf,
        jcAuthorizedParty = azp,
        jcTenantId = tenantId,
        jcScopes = scopes,
        jcRealmRoles = realmRoles,
        jcResourceRoles = resourceRoles,
        jcEmail = email,
        jcEmailVerified = emailVerified,
        jcName = name
      }
  where
    posixToUTC :: Integer -> UTCTime
    posixToUTC posix =
      addUTCTime (fromIntegral posix) (read "1970-01-01 00:00:00 UTC")

    extractAudiences :: Value -> [Text]
    extractAudiences (String s) = [s]
    extractAudiences (Array arr) =
      mapMaybe
        ( \case
            String s -> Just s
            _ -> Nothing
        )
        (V.toList arr)
    extractAudiences _ = []

-- | Alias for extractClaims
payloadToClaims :: JwtPayload -> Either AuthError JwtClaims
payloadToClaims = extractClaims

-- | Extract Subject from JwtClaims
extractSubject :: JwtClaims -> Subject
extractSubject claims =
  Subject
    { subjectId = jcSubject claims,
      subjectEmail = jcEmail claims,
      subjectName = jcName claims,
      subjectRoles = jcRealmRoles claims <> jcResourceRoles claims,
      subjectScopes = jcScopes claims
    }

-- | Resolve tenant from claims using the specified strategy
resolveTenant :: TenantResolutionStrategy -> JwtPayload -> Either AuthError Tenant
resolveTenant strategy payload =
  case strategy of
    ExplicitTenantClaim ->
      case jpTenantId payload of
        Just tid -> Right $ Tenant (TenantId tid) Nothing
        Nothing -> Left TenantResolutionFailed
    AuthorizedPartyTenant ->
      -- Look for tenant in azp-related claims
      case extractAzpTenant payload of
        Just tid -> Right $ Tenant (TenantId tid) Nothing
        Nothing -> Left TenantResolutionFailed
    RoleBasedTenant ->
      case extractTenantFromRoles payload of
        Just tid -> Right $ Tenant (TenantId tid) Nothing
        Nothing -> Left TenantResolutionFailed
    CombinedStrategy ->
      -- Try all strategies in order
      case jpTenantId payload of
        Just tid -> Right $ Tenant (TenantId tid) Nothing
        Nothing ->
          case extractAzpTenant payload of
            Just tid -> Right $ Tenant (TenantId tid) Nothing
            Nothing ->
              case extractTenantFromRoles payload of
                Just tid -> Right $ Tenant (TenantId tid) Nothing
                Nothing -> Left TenantResolutionFailed

-- | Extract tenant from azp-related claims
extractAzpTenant :: JwtPayload -> Maybe Text
extractAzpTenant payload =
  directAzpTenant <|> nestedAzpTenant
  where
    directAzpTenant =
      lookupString "azp.tenant" (jpRaw payload)
        <|> lookupString "azp_tenant" (jpRaw payload)
        <|> (lookupString "tenant" =<< getObjectClaim "azp" (jpRaw payload))

    nestedAzpTenant =
      lookupString "tenant" =<< getObjectClaim "authorized_party" (jpRaw payload)

    getObjectClaim :: Text -> Value -> Maybe Value
    getObjectClaim key (Object obj) = KM.lookup (K.fromText key) obj
    getObjectClaim _ _ = Nothing

    lookupString :: Text -> Value -> Maybe Text
    lookupString key (Object obj) =
      case KM.lookup (K.fromText key) obj of
        Just (String value) -> Just value
        _ -> Nothing
    lookupString _ _ = Nothing

-- | Extract tenant from role-based claims (e.g., "tenant:acme-corp")
extractTenantFromRoles :: JwtPayload -> Maybe Text
extractTenantFromRoles payload = do
  -- Look in resource_access for tenant-prefixed roles
  let resourceRoles = extractResourceRoles payload
      tenantRoles =
        mapMaybe
          ( \(Role r) ->
              if T.isPrefixOf "tenant:" r
                then Just $ T.drop 7 r -- Drop "tenant:" prefix
                else Nothing
          )
          (Set.toList resourceRoles)
  case tenantRoles of
    (tid : _) -> Just tid
    [] -> Nothing

-- | Extract scopes from the scope claim
extractScopes :: JwtPayload -> Set Scope
extractScopes payload =
  case jpScope payload of
    Nothing -> Set.empty
    Just scopeStr ->
      Set.fromList $ map Scope $ T.words scopeStr

-- | Extract realm-level roles
extractRealmRoles :: JwtPayload -> Set Role
extractRealmRoles payload =
  case jpRealmAccess payload of
    Nothing -> Set.empty
    Just (Object obj) ->
      case KM.lookup (K.fromText "roles") obj of
        Just (Array arr) ->
          Set.fromList $
            mapMaybe
              ( \case
                  String s -> Just (Role s)
                  _ -> Nothing
              )
              (V.toList arr)
        _ -> Set.empty
    _ -> Set.empty

-- | Extract resource-specific roles (from resource_access.{clientId}.roles)
extractResourceRoles :: JwtPayload -> Set Role
extractResourceRoles payload =
  case jpResourceAccess payload of
    Nothing -> Set.empty
    Just (Object resourceObj) ->
      -- Collect roles from all clients
      Set.unions $
        map extractClientRoles $
          KM.toList resourceObj
    _ -> Set.empty
  where
    extractClientRoles :: (K.Key, Value) -> Set Role
    extractClientRoles (_, Object clientObj) =
      case KM.lookup (K.fromText "roles") clientObj of
        Just (Array arr) ->
          Set.fromList $
            mapMaybe
              ( \case
                  String s -> Just (Role s)
                  _ -> Nothing
              )
              (V.toList arr)
        _ -> Set.empty
    extractClientRoles _ = Set.empty

-- | Helper to get a string claim from raw payload
getStringClaim :: Text -> JwtPayload -> Maybe Text
getStringClaim claimName payload =
  case jpRaw payload of
    Object obj ->
      case KM.lookup (K.fromText claimName) obj of
        Just (String s) -> Just s
        _ -> Nothing
    _ -> Nothing

-- | Helper to get an array claim from raw payload
getArrayClaim :: Text -> JwtPayload -> [Text]
getArrayClaim claimName payload =
  case jpRaw payload of
    Object obj ->
      case KM.lookup (K.fromText claimName) obj of
        Just (Array arr) ->
          mapMaybe
            ( \case
                String s -> Just s
                _ -> Nothing
            )
            (V.toList arr)
        _ -> []
    _ -> []

-- | Helper to get a boolean claim from raw payload
getBoolClaim :: Text -> JwtPayload -> Maybe Bool
getBoolClaim claimName payload =
  case jpRaw payload of
    Object obj ->
      case KM.lookup (K.fromText claimName) obj of
        Just (Bool b) -> Just b
        _ -> Nothing
    _ -> Nothing
