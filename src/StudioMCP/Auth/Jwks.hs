{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module StudioMCP.Auth.Jwks
  ( -- * JWKS Types
    JwkSet (..),
    Jwk (..),
    JwksCache (..),

    -- * JWKS Cache Operations
    newJwksCache,
    getJwks,
    refreshJwks,
    isCacheStale,

    -- * JWT Parsing
    parseJwt,
    JwtHeader (..),
    JwtPayload (..),

    -- * Token Validation
    validateTokenStructure,
    validateTokenTiming,
    validateTokenIssuer,
    validateTokenAudience,

    -- * JWKS Fetching
    fetchJwks,
  )
where

import Control.Concurrent.STM (TVar, atomically, newTVarIO, readTVarIO, writeTVar)
import Control.Exception (SomeException, try)
import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    Value (..),
    eitherDecode,
    object,
    withObject,
    (.:),
    (.:?),
    (.=),
  )
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base64.URL as B64
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time (UTCTime, addUTCTime, getCurrentTime)
import GHC.Generics (Generic)
import Network.HTTP.Client (Manager, httpLbs, parseRequest, responseBody, responseStatus)
import Network.HTTP.Types (statusCode)
import StudioMCP.Auth.Config (AuthConfig (..), KeycloakConfig (..), jwksEndpoint)
import StudioMCP.Auth.Types

-- | JSON Web Key
data Jwk = Jwk
  { jwkKty :: Text, -- Key type (e.g., "RSA")
    jwkUse :: Maybe Text, -- Public key use (e.g., "sig")
    jwkKid :: Maybe Text, -- Key ID
    jwkAlg :: Maybe Text, -- Algorithm
    jwkN :: Maybe Text, -- RSA modulus (base64url)
    jwkE :: Maybe Text, -- RSA exponent (base64url)
    jwkX :: Maybe Text, -- EC X coordinate
    jwkY :: Maybe Text, -- EC Y coordinate
    jwkCrv :: Maybe Text -- EC curve
  }
  deriving (Eq, Show, Generic)

instance ToJSON Jwk where
  toJSON jwk =
    object $
      [ "kty" .= jwkKty jwk
      ]
        ++ maybe [] (\v -> ["use" .= v]) (jwkUse jwk)
        ++ maybe [] (\v -> ["kid" .= v]) (jwkKid jwk)
        ++ maybe [] (\v -> ["alg" .= v]) (jwkAlg jwk)
        ++ maybe [] (\v -> ["n" .= v]) (jwkN jwk)
        ++ maybe [] (\v -> ["e" .= v]) (jwkE jwk)
        ++ maybe [] (\v -> ["x" .= v]) (jwkX jwk)
        ++ maybe [] (\v -> ["y" .= v]) (jwkY jwk)
        ++ maybe [] (\v -> ["crv" .= v]) (jwkCrv jwk)

instance FromJSON Jwk where
  parseJSON = withObject "Jwk" $ \obj ->
    Jwk
      <$> obj .: "kty"
      <*> obj .:? "use"
      <*> obj .:? "kid"
      <*> obj .:? "alg"
      <*> obj .:? "n"
      <*> obj .:? "e"
      <*> obj .:? "x"
      <*> obj .:? "y"
      <*> obj .:? "crv"

-- | JSON Web Key Set
data JwkSet = JwkSet
  { jwksKeys :: [Jwk]
  }
  deriving (Eq, Show, Generic)

instance ToJSON JwkSet where
  toJSON set = object ["keys" .= jwksKeys set]

instance FromJSON JwkSet where
  parseJSON = withObject "JwkSet" $ \obj ->
    JwkSet <$> obj .: "keys"

-- | JWKS cache state
data JwksCache = JwksCache
  { jcKeys :: TVar (Maybe JwkSet),
    jcFetchedAt :: TVar (Maybe UTCTime),
    jcConfig :: AuthConfig
  }

-- | Create a new JWKS cache
newJwksCache :: AuthConfig -> IO JwksCache
newJwksCache config = do
  keysVar <- newTVarIO Nothing
  fetchedVar <- newTVarIO Nothing
  pure
    JwksCache
      { jcKeys = keysVar,
        jcFetchedAt = fetchedVar,
        jcConfig = config
      }

-- | Check if cache is stale and needs refresh
isCacheStale :: JwksCache -> IO Bool
isCacheStale cache = do
  mFetchedAt <- readTVarIO (jcFetchedAt cache)
  case mFetchedAt of
    Nothing -> pure True
    Just fetchedAt -> do
      now <- getCurrentTime
      let ttl = fromIntegral $ kcJwksCacheTtlSeconds (acKeycloak (jcConfig cache))
          expiresAt = addUTCTime ttl fetchedAt
      pure (now > expiresAt)

-- | Get JWKS from cache, fetching if needed
getJwks :: JwksCache -> Manager -> IO (Either AuthError JwkSet)
getJwks cache manager = do
  stale <- isCacheStale cache
  if stale
    then refreshJwks cache manager
    else do
      mKeys <- readTVarIO (jcKeys cache)
      case mKeys of
        Just keys -> pure (Right keys)
        Nothing -> refreshJwks cache manager

-- | Refresh JWKS from Keycloak
refreshJwks :: JwksCache -> Manager -> IO (Either AuthError JwkSet)
refreshJwks cache manager = do
  result <- fetchJwks (jcConfig cache) manager
  case result of
    Left err -> pure (Left err)
    Right jwks -> do
      now <- getCurrentTime
      atomically $ do
        writeTVar (jcKeys cache) (Just jwks)
        writeTVar (jcFetchedAt cache) (Just now)
      pure (Right jwks)

-- | Fetch JWKS from Keycloak endpoint
fetchJwks :: AuthConfig -> Manager -> IO (Either AuthError JwkSet)
fetchJwks config manager = do
  let url = T.unpack $ jwksEndpoint (acKeycloak config)
  result <- try $ do
    req <- parseRequest url
    resp <- httpLbs req manager
    let status = statusCode (responseStatus resp)
    if status == 200
      then case eitherDecode (responseBody resp) of
        Left err -> pure (Left $ JwksFetchError $ T.pack err)
        Right jwks -> pure (Right jwks)
      else pure (Left $ JwksFetchError $ "HTTP " <> T.pack (show status))
  case result of
    Left (e :: SomeException) ->
      pure (Left $ JwksFetchError $ T.pack (show e))
    Right r -> pure r

-- | JWT header
data JwtHeader = JwtHeader
  { jhAlg :: Text,
    jhTyp :: Maybe Text,
    jhKid :: Maybe Text
  }
  deriving (Eq, Show, Generic)

instance FromJSON JwtHeader where
  parseJSON = withObject "JwtHeader" $ \obj ->
    JwtHeader
      <$> obj .: "alg"
      <*> obj .:? "typ"
      <*> obj .:? "kid"

-- | JWT payload (raw claims)
data JwtPayload = JwtPayload
  { jpIss :: Maybe Text,
    jpSub :: Maybe Text,
    jpAud :: Maybe Value, -- Can be string or array
    jpExp :: Maybe Integer,
    jpNbf :: Maybe Integer,
    jpIat :: Maybe Integer,
    jpAzp :: Maybe Text,
    jpTenantId :: Maybe Text,
    jpScope :: Maybe Text,
    jpRealmAccess :: Maybe Value,
    jpResourceAccess :: Maybe Value,
    jpEmail :: Maybe Text,
    jpEmailVerified :: Maybe Bool,
    jpName :: Maybe Text,
    jpRaw :: Value -- Full raw payload for custom claims
  }
  deriving (Eq, Show, Generic)

instance FromJSON JwtPayload where
  parseJSON v = withObject "JwtPayload" parsePayload v
    where
      parsePayload obj =
        JwtPayload
          <$> obj .:? "iss"
          <*> obj .:? "sub"
          <*> obj .:? "aud"
          <*> obj .:? "exp"
          <*> obj .:? "nbf"
          <*> obj .:? "iat"
          <*> obj .:? "azp"
          <*> obj .:? "tenant_id"
          <*> obj .:? "scope"
          <*> obj .:? "realm_access"
          <*> obj .:? "resource_access"
          <*> obj .:? "email"
          <*> obj .:? "email_verified"
          <*> obj .:? "name"
          <*> pure v

-- | Parse JWT token into header and payload
parseJwt :: RawJwt -> Either AuthError (JwtHeader, JwtPayload, BS.ByteString)
parseJwt (RawJwt token) = do
  -- Split into parts
  let parts = T.splitOn "." token
  case parts of
    [headerB64, payloadB64, signatureB64] -> do
      -- Decode header
      headerBytes <- decodeBase64 headerB64
      header <- case eitherDecode (LBS.fromStrict headerBytes) of
        Left err -> Left $ InvalidTokenFormat $ "Invalid header: " <> T.pack err
        Right h -> Right h

      -- Decode payload
      payloadBytes <- decodeBase64 payloadB64
      payload <- case eitherDecode (LBS.fromStrict payloadBytes) of
        Left err -> Left $ InvalidTokenFormat $ "Invalid payload: " <> T.pack err
        Right p -> Right p

      -- Decode signature
      signature <- decodeBase64 signatureB64

      Right (header, payload, signature)
    _ -> Left $ InvalidTokenFormat "Invalid JWT structure (expected 3 parts)"
  where
    decodeBase64 t =
      case B64.decodeUnpadded (TE.encodeUtf8 t) of
        Left err -> Left $ InvalidTokenFormat $ "Base64 decode error: " <> T.pack err
        Right bs -> Right bs

-- | Validate token timing (exp, nbf, iat)
validateTokenTiming :: AuthConfig -> JwtPayload -> UTCTime -> Either AuthError ()
validateTokenTiming config payload now = do
  -- Check expiration
  case jpExp payload of
    Nothing -> Left $ MissingClaim "exp"
    Just expiresAtEpoch -> do
      let expTime = posixToUTC expiresAtEpoch
          leeway = fromIntegral $ acTokenLeewaySeconds config
      if addUTCTime leeway now > expTime
        then Left TokenExpired
        else Right ()

  -- Check not-before if present
  case jpNbf payload of
    Nothing -> Right ()
    Just nbf -> do
      let nbfTime = posixToUTC nbf
          leeway = fromIntegral $ acTokenLeewaySeconds config
      if addUTCTime (-leeway) now < nbfTime
        then Left TokenNotYetValid
        else Right ()
  where
    posixToUTC :: Integer -> UTCTime
    posixToUTC posix =
      addUTCTime (fromIntegral posix) (read "1970-01-01 00:00:00 UTC")

-- | Validate token issuer
-- Accepts the primary issuer or any of the additional issuers.
-- This allows tokens issued via internal URLs (e.g., host.docker.internal, in-cluster)
-- to be validated when the validator is configured with multiple endpoints.
--
-- Additionally, for development/testing purposes, if an additional issuer matches the
-- pattern "http://localhost:*/kc/realms/<realm>", any localhost issuer with the same
-- realm suffix is accepted. This supports the outer-container test pattern where
-- validation code obtains tokens via port-forward to Keycloak with dynamic ports.
validateTokenIssuer :: KeycloakConfig -> JwtPayload -> Either AuthError ()
validateTokenIssuer config payload =
  case jpIss payload of
    Nothing -> Left $ MissingClaim "iss"
    Just iss ->
      let acceptedIssuers = kcIssuer config : kcAdditionalIssuers config
          realm = kcRealm config
          realmSuffix = "/kc/realms/" <> realm
          -- Check if any additional issuer starts with "http://localhost:" and ends with the realm suffix.
          -- If so, accept any localhost issuer with the same realm suffix.
          hasLocalhostWildcard = any isLocalhostIssuerPattern acceptedIssuers
          isLocalhostIssuerPattern :: Text -> Bool
          isLocalhostIssuerPattern url =
            T.isPrefixOf "http://localhost:" url && T.isSuffixOf realmSuffix url
          issMatchesLocalhostPattern :: Bool
          issMatchesLocalhostPattern =
            hasLocalhostWildcard
              && T.isPrefixOf "http://localhost:" iss
              && T.isSuffixOf realmSuffix iss
       in if iss `elem` acceptedIssuers || issMatchesLocalhostPattern
            then Right ()
            else Left $ InvalidIssuer iss

-- | Validate token audience
validateTokenAudience :: KeycloakConfig -> JwtPayload -> Either AuthError ()
validateTokenAudience config payload =
  case jpAud payload of
    Nothing -> Left $ MissingClaim "aud"
    Just audValue ->
      let audiences = extractAudiences audValue
          expected = kcAudience config
       in if expected `elem` audiences
            then Right ()
            else Left $ InvalidAudience expected
  where
    extractAudiences :: Value -> [Text]
    extractAudiences (String s) = [s]
    extractAudiences (Array arr) =
      concatMap
        ( \case
            String s -> [s]
            _ -> []
        )
        arr
    extractAudiences _ = []

-- | Validate token structure (header algorithm check)
validateTokenStructure :: AuthConfig -> JwtHeader -> Either AuthError ()
validateTokenStructure config header =
  if jhAlg header `elem` acAllowedAlgorithms config
    then Right ()
    else Left $ InvalidTokenFormat $ "Unsupported algorithm: " <> jhAlg header
