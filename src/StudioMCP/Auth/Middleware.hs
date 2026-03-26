{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module StudioMCP.Auth.Middleware
  ( -- * Auth Service
    AuthService (..),
    newAuthService,

    -- * Token Validation
    validateToken,
    authenticateRequest,

    -- * HTTP Request Authentication
    extractBearerToken,
    authenticateWaiRequest,

    -- * Auth Context Building
    buildAuthContext,

    -- * Bypass Mode (Development)
    devBypassAuth,
  )
where

import Control.Concurrent.STM (TVar, atomically, readTVarIO)
import Control.Exception (SomeException, try)
import Data.Aeson (Value)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import Data.CaseInsensitive (CI)
import qualified Data.CaseInsensitive as CI
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time (getCurrentTime)
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import Network.HTTP.Client (Manager)
import Network.Wai (Request, requestHeaders)
import StudioMCP.Auth.Claims
import StudioMCP.Auth.Config
import StudioMCP.Auth.Jwks
import StudioMCP.Auth.Types

-- | Authentication service
data AuthService = AuthService
  { asConfig :: AuthConfig,
    asJwksCache :: JwksCache,
    asHttpManager :: Manager
  }

-- | Create a new auth service
newAuthService :: AuthConfig -> Manager -> IO AuthService
newAuthService config manager = do
  cache <- newJwksCache config
  pure
    AuthService
      { asConfig = config,
        asJwksCache = cache,
        asHttpManager = manager
      }

-- | Validate a raw JWT token
validateToken :: AuthService -> RawJwt -> IO (Either AuthError JwtClaims)
validateToken service rawToken = do
  -- Check if auth is enabled
  if not (acEnabled (asConfig service))
    then pure $ Left $ InternalAuthError "Auth is disabled"
    else do
      -- Parse the JWT structure
      case parseJwt rawToken of
        Left err -> pure (Left err)
        Right (header, payload, signature) -> do
          -- Validate token structure (algorithm)
          case validateTokenStructure (asConfig service) header of
            Left err -> pure (Left err)
            Right () -> do
              -- Get current time for timing validation
              now <- getCurrentTime

              -- Validate timing (exp, nbf)
              case validateTokenTiming (asConfig service) payload now of
                Left err -> pure (Left err)
                Right () -> do
                  -- Validate issuer
                  let kc = acKeycloak (asConfig service)
                  case validateTokenIssuer kc payload of
                    Left err -> pure (Left err)
                    Right () -> do
                      -- Validate audience
                      case validateTokenAudience kc payload of
                        Left err -> pure (Left err)
                        Right () -> do
                          -- Fetch JWKS and verify signature
                          -- For now, we skip actual signature verification
                          -- as it requires crypto primitives
                          -- In production, this would verify against JWKS
                          jwksResult <- getJwks (asJwksCache service) (asHttpManager service)
                          case jwksResult of
                            Left err -> pure (Left err)
                            Right _jwks -> do
                              -- INFRASTRUCTURE: Full RSA/EC signature verification requires
                              -- cryptographic library integration (e.g., jose, cryptonite)
                              -- Current validation: structure, timing, issuer, audience
                              pure $ extractClaims payload

-- | Authenticate a request and build full auth context
authenticateRequest ::
  AuthService ->
  RawJwt ->
  Text -> -- Correlation ID
  IO (Either AuthError AuthContext)
authenticateRequest service rawToken correlationId = do
  -- Validate the token
  claimsResult <- validateToken service rawToken
  case claimsResult of
    Left err -> pure (Left err)
    Right claims -> do
      -- Build auth context
      buildAuthContext (asConfig service) claims correlationId

-- | Build AuthContext from validated claims
buildAuthContext ::
  AuthConfig ->
  JwtClaims ->
  Text -> -- Correlation ID
  IO (Either AuthError AuthContext)
buildAuthContext config claims correlationId = do
  -- Extract subject
  let subject = extractSubject claims

  -- Resolve tenant
  let tenantResult = resolveTenantFromClaims claims
  case tenantResult of
    Left err -> pure (Left err)
    Right tenant ->
      pure $
        Right
          AuthContext
            { acSubject = subject,
              acTenant = tenant,
              acClaims = claims,
              acCorrelationId = correlationId
            }
  where
    resolveTenantFromClaims :: JwtClaims -> Either AuthError Tenant
    resolveTenantFromClaims c =
      case jcTenantId c of
        Just tid -> Right $ Tenant tid Nothing
        Nothing ->
          -- Try to extract from roles
          let tenantRoles =
                filter (T.isPrefixOf "tenant:" . unRole) $
                  Set.toList (jcRealmRoles c <> jcResourceRoles c)
           in case tenantRoles of
                (Role r : _) -> Right $ Tenant (TenantId $ T.drop 7 r) Nothing
                [] -> Left TenantResolutionFailed

    unRole (Role r) = r

-- | Extract bearer token from Authorization header
extractBearerToken :: Request -> Maybe RawJwt
extractBearerToken req =
  let headers = requestHeaders req
   in case lookup (CI.mk "Authorization") headers of
        Nothing -> Nothing
        Just value ->
          let headerText = TE.decodeUtf8 value
           in if T.isPrefixOf "Bearer " headerText
                then Just $ RawJwt $ T.drop 7 headerText
                else Nothing

-- | Authenticate a WAI request
authenticateWaiRequest ::
  AuthService ->
  Request ->
  IO (Either AuthError AuthContext)
authenticateWaiRequest service req = do
  -- Generate correlation ID
  correlationId <- generateCorrelationId

  -- Check if auth is enabled
  if not (acEnabled (asConfig service))
    then pure $ Left $ InternalAuthError "Auth is disabled"
    else case extractBearerToken req of
      Nothing -> pure (Left MissingToken)
      Just token -> authenticateRequest service token correlationId

-- | Generate a correlation ID
generateCorrelationId :: IO Text
generateCorrelationId = UUID.toText <$> UUID.nextRandom

-- | Development bypass - create a fake auth context
devBypassAuth :: Text -> Text -> AuthContext
devBypassAuth subjectIdText tenantIdText =
  AuthContext
    { acSubject =
        Subject
          { subjectId = SubjectId subjectIdText,
            subjectEmail = Just "dev@localhost",
            subjectName = Just "Development User",
            subjectRoles = Set.fromList [Role "user", Role "admin"],
            subjectScopes =
              Set.fromList
                [ Scope "openid",
                  Scope "profile",
                  Scope "workflow:read",
                  Scope "workflow:write",
                  Scope "artifact:read",
                  Scope "artifact:write"
                ]
          },
      acTenant =
        Tenant
          { tenantId = TenantId tenantIdText,
            tenantName = Just "Development Tenant"
          },
      acClaims = devClaims subjectIdText tenantIdText,
      acCorrelationId = "dev-correlation-id"
    }
  where
    devClaims subId tenId =
      JwtClaims
        { jcIssuer = "http://localhost:8080/realms/studiomcp",
          jcSubject = SubjectId subId,
          jcAudience = ["studiomcp-mcp"],
          jcExpiration = read "2099-12-31 23:59:59 UTC",
          jcIssuedAt = read "2024-01-01 00:00:00 UTC",
          jcNotBefore = Nothing,
          jcAuthorizedParty = Just "studiomcp-cli",
          jcTenantId = Just (TenantId tenId),
          jcScopes =
            Set.fromList
              [ Scope "openid",
                Scope "profile",
                Scope "workflow:read",
                Scope "workflow:write",
                Scope "artifact:read",
                Scope "artifact:write"
              ],
          jcRealmRoles = Set.fromList [Role "user", Role "admin"],
          jcResourceRoles = Set.empty,
          jcEmail = Just "dev@localhost",
          jcEmailVerified = Just True,
          jcName = Just "Development User"
        }
