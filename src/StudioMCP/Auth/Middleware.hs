{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

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

import Control.Applicative ((<|>))
import Control.Exception (SomeException, try)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base64.URL as B64
import qualified Data.CaseInsensitive as CI
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time (getCurrentTime)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import Data.Aeson (FromJSON (..), eitherDecode, withObject, (.:?))
import Crypto.Hash.Algorithms (SHA256 (..), SHA384 (..), SHA512 (..))
import qualified Crypto.PubKey.ECC.ECDSA as ECDSA
import Crypto.PubKey.ECC.Types
  ( CurveName (SEC_p256r1),
    Point (Point),
    getCurveByName,
  )
import Crypto.PubKey.RSA.PKCS15 qualified as RSA
import Crypto.PubKey.RSA.Types qualified as RSA
import Crypto.Number.Serialize (os2ip)
import Network.HTTP.Client
  ( Manager,
    Request (requestHeaders),
    httpLbs,
    parseRequest,
    responseBody,
    responseStatus,
  )
import qualified Network.HTTP.Client as HTTPClient
import Network.HTTP.Types (statusCode)
import qualified Network.Wai as Wai
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

data UserInfoClaims = UserInfoClaims
  { uicSub :: Maybe Text,
    uicTenantId :: Maybe Text,
    uicEmail :: Maybe Text,
    uicEmailVerified :: Maybe Bool,
    uicName :: Maybe Text
  }

instance FromJSON UserInfoClaims where
  parseJSON = withObject "UserInfoClaims" $ \obj ->
    UserInfoClaims
      <$> obj .:? "sub"
      <*> obj .:? "tenant_id"
      <*> obj .:? "email"
      <*> obj .:? "email_verified"
      <*> obj .:? "name"

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
                          jwksResult <- getJwks (asJwksCache service) (asHttpManager service)
                          case jwksResult of
                            Left err -> pure (Left err)
                            Right jwks ->
                              case verifyJwtSignature jwks rawToken header signature of
                                Left err -> pure (Left err)
                                Right () ->
                                  extractClaimsWithUserInfoFallback service rawToken payload

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
buildAuthContext _config claims correlationId = do
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
extractBearerToken :: Wai.Request -> Maybe RawJwt
extractBearerToken req =
  let headers = Wai.requestHeaders req
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
  Wai.Request ->
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

extractClaimsWithUserInfoFallback ::
  AuthService ->
  RawJwt ->
  JwtPayload ->
  IO (Either AuthError JwtClaims)
extractClaimsWithUserInfoFallback service rawToken payload =
  case extractClaims payload of
    Right claims ->
      pure (Right claims)
    Left (MissingClaim "sub") -> do
      userInfoResult <- fetchUserInfoClaims service rawToken
      case userInfoResult of
        Left err -> pure (Left err)
        Right userInfo ->
          pure $
            extractClaims $
              payload
                { jpSub = jpSub payload <|> uicSub userInfo
                , jpTenantId = jpTenantId payload <|> uicTenantId userInfo
                , jpEmail = jpEmail payload <|> uicEmail userInfo
                , jpEmailVerified = jpEmailVerified payload <|> uicEmailVerified userInfo
                , jpName = jpName payload <|> uicName userInfo
                }
    Left err ->
      pure (Left err)

fetchUserInfoClaims :: AuthService -> RawJwt -> IO (Either AuthError UserInfoClaims)
fetchUserInfoClaims service (RawJwt token) = do
  let endpoint = T.unpack (userinfoEndpoint (acKeycloak (asConfig service)))
  requestResult <- try (parseRequest endpoint) :: IO (Either SomeException HTTPClient.Request)
  case requestResult of
    Left err ->
      pure $ Left $ InternalAuthError ("Failed to build Keycloak userinfo request: " <> T.pack (show err))
    Right req -> do
      let request =
            req
              { requestHeaders =
                  [ (CI.mk "Authorization", "Bearer " <> TE.encodeUtf8 token)
                  ]
              }
      responseResult <- try (httpLbs request (asHttpManager service))
      case responseResult of
        Left (err :: SomeException) ->
          pure $ Left $ InternalAuthError ("Keycloak userinfo request failed: " <> T.pack (show err))
        Right response ->
          if statusCode (responseStatus response) /= 200
            then
              pure $
                Left $
                  InternalAuthError
                    ( "Keycloak userinfo endpoint returned HTTP "
                        <> T.pack (show (statusCode (responseStatus response)))
                    )
            else
              case eitherDecode (responseBody response) of
                Left err ->
                  pure $
                    Left $
                      InternalAuthError
                        ("Failed to decode Keycloak userinfo response: " <> T.pack err)
                Right userInfo ->
                  pure (Right userInfo)

verifyJwtSignature ::
  JwkSet ->
  RawJwt ->
  JwtHeader ->
  BS.ByteString ->
  Either AuthError ()
verifyJwtSignature jwks rawToken header signature = do
  signingInput <- jwtSigningInput rawToken
  jwk <- selectVerificationKey jwks header
  let verified =
        case jwkKty jwk of
          "RSA" -> verifyRsaSignature header jwk signingInput signature
          "EC" -> verifyEcSignature header jwk signingInput signature
          _ -> False
  if verified
    then Right ()
    else Left InvalidSignature

jwtSigningInput :: RawJwt -> Either AuthError BS.ByteString
jwtSigningInput (RawJwt token) =
  case T.splitOn "." token of
    [headerPart, payloadPart, _] ->
      Right (TE.encodeUtf8 (headerPart <> "." <> payloadPart))
    _ ->
      Left $ InvalidTokenFormat "Invalid JWT structure (expected 3 parts)"

selectVerificationKey :: JwkSet -> JwtHeader -> Either AuthError Jwk
selectVerificationKey jwks header =
  case candidates of
    (candidate : _) -> Right candidate
    [] -> Left InvalidSignature
  where
    candidates =
      filter (matchesKid header)
        . filter (matchesUsageAndAlg header)
        . filter (matchesKeyType header)
        $ jwksKeys jwks

matchesKid :: JwtHeader -> Jwk -> Bool
matchesKid header jwk =
  case jhKid header of
    Nothing -> True
    Just kid -> jwkKid jwk == Just kid

matchesUsageAndAlg :: JwtHeader -> Jwk -> Bool
matchesUsageAndAlg header jwk =
  maybe True (== "sig") (jwkUse jwk)
    && maybe True (== jhAlg header) (jwkAlg jwk)

matchesKeyType :: JwtHeader -> Jwk -> Bool
matchesKeyType header jwk =
  case jhAlg header of
    alg | "RS" `T.isPrefixOf` alg -> jwkKty jwk == "RSA"
    alg | "ES" `T.isPrefixOf` alg -> jwkKty jwk == "EC"
    _ -> False

verifyRsaSignature :: JwtHeader -> Jwk -> BS.ByteString -> BS.ByteString -> Bool
verifyRsaSignature header jwk signingInput signature =
  case rsaPublicKeyFromJwk jwk of
    Nothing -> False
    Just publicKey ->
      case jhAlg header of
        "RS256" -> RSA.verify (Just SHA256) publicKey signingInput signature
        "RS384" -> RSA.verify (Just SHA384) publicKey signingInput signature
        "RS512" -> RSA.verify (Just SHA512) publicKey signingInput signature
        _ -> False

verifyEcSignature :: JwtHeader -> Jwk -> BS.ByteString -> BS.ByteString -> Bool
verifyEcSignature header jwk signingInput signatureBytes =
  case ecPublicKeyFromJwk jwk of
    Nothing -> False
    Just publicKey ->
      case ecdsaSignatureFromJwt signatureBytes of
        Nothing -> False
        Just signature ->
          case jhAlg header of
            "ES256" -> ECDSA.verify SHA256 publicKey signature signingInput
            "ES384" -> ECDSA.verify SHA384 publicKey signature signingInput
            "ES512" -> ECDSA.verify SHA512 publicKey signature signingInput
            _ -> False

rsaPublicKeyFromJwk :: Jwk -> Maybe RSA.PublicKey
rsaPublicKeyFromJwk jwk = do
  modulusText <- jwkN jwk
  exponentText <- jwkE jwk
  modulusBytes <- decodeBase64Url modulusText
  exponentBytes <- decodeBase64Url exponentText
  pure
    RSA.PublicKey
      { RSA.public_size = BS.length modulusBytes,
        RSA.public_n = os2ip modulusBytes,
        RSA.public_e = os2ip exponentBytes
      }

ecPublicKeyFromJwk :: Jwk -> Maybe ECDSA.PublicKey
ecPublicKeyFromJwk jwk = do
  curveName <- jwkCrv jwk >>= curveNameFromText
  xCoord <- jwkX jwk >>= decodeBase64Url
  yCoord <- jwkY jwk >>= decodeBase64Url
  pure
    ECDSA.PublicKey
      { ECDSA.public_curve = getCurveByName curveName,
        ECDSA.public_q = Point (os2ip xCoord) (os2ip yCoord)
      }

curveNameFromText :: Text -> Maybe CurveName
curveNameFromText curveText =
  case curveText of
    "P-256" -> Just SEC_p256r1
    _ -> Nothing

ecdsaSignatureFromJwt :: BS.ByteString -> Maybe ECDSA.Signature
ecdsaSignatureFromJwt signatureBytes
  | BS.null signatureBytes = Nothing
  | odd (BS.length signatureBytes) = Nothing
  | otherwise =
      let componentLength = BS.length signatureBytes `div` 2
          (rBytes, sBytes) = BS.splitAt componentLength signatureBytes
       in Just (ECDSA.Signature (os2ip rBytes) (os2ip sBytes))

decodeBase64Url :: Text -> Maybe BS.ByteString
decodeBase64Url value =
  either (const Nothing) Just (B64.decodeUnpadded (TE.encodeUtf8 value))

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
                  Scope "artifact:write",
                  Scope "artifact:manage",
                  Scope "prompt:read",
                  Scope "resource:read",
                  Scope "tenant:read"
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
        { jcIssuer = "http://localhost:8080/kc/realms/studiomcp",
          jcSubject = SubjectId subId,
          jcAudience = ["studiomcp-mcp"],
          jcExpiration = read "2099-12-31 23:59:59 UTC",
          jcIssuedAt = read "2024-01-01 00:00:00 UTC",
          jcNotBefore = Nothing,
          jcAuthorizedParty = Just "studiomcp-bff",
          jcTenantId = Just (TenantId tenId),
          jcScopes =
            Set.fromList
              [ Scope "openid",
                Scope "profile",
                Scope "workflow:read",
                Scope "workflow:write",
                Scope "artifact:read",
                Scope "artifact:write",
                Scope "artifact:manage",
                Scope "prompt:read",
                Scope "resource:read",
                Scope "tenant:read"
              ],
          jcRealmRoles = Set.fromList [Role "user", Role "admin"],
          jcResourceRoles = Set.empty,
          jcEmail = Just "dev@localhost",
          jcEmailVerified = Just True,
          jcName = Just "Development User"
        }
