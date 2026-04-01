{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Auth.ServiceAccount
  ( -- * Service Account Client
    ServiceAccountClient (..),
    ServiceAccountConfig (..),
    newServiceAccountClient,

    -- * Token Operations
    acquireServiceToken,
    getValidToken,

    -- * Cached Token
    CachedServiceToken (..),

    -- * Errors
    ServiceAccountError (..),
    serviceAccountErrorToText,
  )
where

import Control.Concurrent.STM (TVar, atomically, newTVarIO, readTVar, writeTVar)
import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    eitherDecode,
    object,
    withObject,
    (.:),
    (.:?),
    (.=),
  )
import qualified Data.ByteString.Lazy as LBS
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time (NominalDiffTime, UTCTime, addUTCTime, getCurrentTime)
import GHC.Generics (Generic)
import Network.HTTP.Client
  ( Manager,
    RequestBody (..),
    httpLbs,
    method,
    parseRequest,
    requestBody,
    requestHeaders,
    responseBody,
    responseStatus,
  )
import Network.HTTP.Types (statusCode)
import StudioMCP.Auth.Config (KeycloakConfig (..), tokenEndpoint)
import StudioMCP.Auth.Types (Scope (..))

-- | Configuration for a service account
data ServiceAccountConfig = ServiceAccountConfig
  { -- | Client ID for the service account
    sacClientId :: Text,
    -- | Client secret for authentication
    sacClientSecret :: Text,
    -- | Scopes to request
    sacScopes :: [Text],
    -- | Keycloak configuration
    sacKeycloakConfig :: KeycloakConfig
  }
  deriving (Eq, Show, Generic)

instance ToJSON ServiceAccountConfig where
  toJSON sac =
    object
      [ "clientId" .= sacClientId sac,
        "scopes" .= sacScopes sac
        -- Note: clientSecret intentionally not serialized
      ]

-- | A cached service account token
data CachedServiceToken = CachedServiceToken
  { -- | The access token
    cstAccessToken :: Text,
    -- | When the token expires
    cstExpiresAt :: UTCTime,
    -- | Scopes granted to this token
    cstScopes :: Set Scope
  }
  deriving (Eq, Show, Generic)

instance ToJSON CachedServiceToken where
  toJSON cst =
    object
      [ "expiresAt" .= cstExpiresAt cst,
        "scopes" .= cstScopes cst
        -- Note: accessToken intentionally not serialized
      ]

-- | Service account client with token caching
data ServiceAccountClient = ServiceAccountClient
  { -- | Configuration for this service account
    sacConfig :: ServiceAccountConfig,
    -- | Cached token (thread-safe)
    sacCachedToken :: TVar (Maybe CachedServiceToken),
    -- | HTTP manager for making requests
    sacManager :: Manager
  }

-- | Create a new service account client
newServiceAccountClient ::
  ServiceAccountConfig ->
  Manager ->
  IO ServiceAccountClient
newServiceAccountClient config manager = do
  tokenVar <- newTVarIO Nothing
  pure
    ServiceAccountClient
      { sacConfig = config,
        sacCachedToken = tokenVar,
        sacManager = manager
      }

-- | Service account related errors
data ServiceAccountError
  = -- | Token request failed
    SATokenRequestFailed Int Text
  | -- | Failed to parse token response
    SATokenParseError Text
  | -- | Token endpoint returned an error
    SATokenEndpointError Text Text -- error, error_description
  | -- | Network error
    SANetworkError Text
  | -- | Token expired and refresh failed
    SATokenExpired
  deriving (Eq, Show, Generic)

instance ToJSON ServiceAccountError where
  toJSON err =
    object
      [ "error" .= serviceAccountErrorCode err,
        "message" .= serviceAccountErrorToText err
      ]

-- | Convert error to human-readable text
serviceAccountErrorToText :: ServiceAccountError -> Text
serviceAccountErrorToText (SATokenRequestFailed status msg) =
  "Token request failed with status " <> T.pack (show status) <> ": " <> msg
serviceAccountErrorToText (SATokenParseError msg) =
  "Failed to parse token response: " <> msg
serviceAccountErrorToText (SATokenEndpointError err desc) =
  "Token endpoint error: " <> err <> " - " <> desc
serviceAccountErrorToText (SANetworkError msg) =
  "Network error: " <> msg
serviceAccountErrorToText SATokenExpired =
  "Service account token expired"

-- | Get error code
serviceAccountErrorCode :: ServiceAccountError -> Text
serviceAccountErrorCode (SATokenRequestFailed _ _) = "sa_token_request_failed"
serviceAccountErrorCode (SATokenParseError _) = "sa_token_parse_error"
serviceAccountErrorCode (SATokenEndpointError _ _) = "sa_token_endpoint_error"
serviceAccountErrorCode (SANetworkError _) = "sa_network_error"
serviceAccountErrorCode SATokenExpired = "sa_token_expired"

-- | Internal token response type
data TokenResponseInternal = TokenResponseInternal
  { triAccessToken :: Text,
    triExpiresIn :: Int,
    triScope :: Maybe Text
  }
  deriving (Eq, Show, Generic)

instance FromJSON TokenResponseInternal where
  parseJSON = withObject "TokenResponse" $ \obj ->
    TokenResponseInternal
      <$> obj .: "access_token"
      <*> obj .: "expires_in"
      <*> obj .:? "scope"

-- | Acquire a fresh service account token via client_credentials grant
acquireServiceToken ::
  ServiceAccountClient ->
  IO (Either ServiceAccountError CachedServiceToken)
acquireServiceToken client = do
  now <- getCurrentTime
  let config = sacConfig client
      kc = sacKeycloakConfig config
      endpoint = T.unpack $ tokenEndpoint kc
      body =
        TE.encodeUtf8 $
          T.intercalate
            "&"
            [ "grant_type=client_credentials",
              "client_id=" <> urlEncode (sacClientId config),
              "client_secret=" <> urlEncode (sacClientSecret config),
              "scope=" <> urlEncode (T.intercalate " " (sacScopes config))
            ]

  result <- makeTokenRequest endpoint body
  case result of
    Left err -> pure $ Left err
    Right tokenResp -> do
      let expiresAt = addUTCTime (fromIntegral (triExpiresIn tokenResp)) now
          scopes = parseScopes (triScope tokenResp)
          cachedToken =
            CachedServiceToken
              { cstAccessToken = triAccessToken tokenResp,
                cstExpiresAt = expiresAt,
                cstScopes = scopes
              }
      -- Cache the token
      atomically $ writeTVar (sacCachedToken client) (Just cachedToken)
      pure $ Right cachedToken
  where
    makeTokenRequest endpoint body = do
      mReq <- parseRequest endpoint
      case mReq of
        req -> do
          let request =
                req
                  { method = "POST",
                    requestBody = RequestBodyBS body,
                    requestHeaders =
                      [ ("Content-Type", "application/x-www-form-urlencoded")
                      ]
                  }
          response <- httpLbs request (sacManager client)
          let status = statusCode $ responseStatus response
          if status >= 200 && status < 300
            then parseTokenResponse (responseBody response)
            else pure $ Left $ SATokenRequestFailed status (TE.decodeUtf8 $ LBS.toStrict $ responseBody response)

    parseTokenResponse body =
      case eitherDecode body of
        Right tr -> pure $ Right tr
        Left err -> pure $ Left $ SATokenParseError (T.pack err)

    parseScopes Nothing = Set.empty
    parseScopes (Just scopeStr) =
      Set.fromList $ map Scope $ T.words scopeStr

-- | URL encode a text value
urlEncode :: Text -> Text
urlEncode = T.concatMap encodeChar
  where
    encodeChar c
      | isUnreserved c = T.singleton c
      | otherwise = T.pack $ "%" <> hexEncode c
    isUnreserved c =
      (c >= 'A' && c <= 'Z')
        || (c >= 'a' && c <= 'z')
        || (c >= '0' && c <= '9')
        || c == '-'
        || c == '_'
        || c == '.'
        || c == '~'
    hexEncode c =
      let byte = fromEnum c
          hi = byte `div` 16
          lo = byte `mod` 16
       in [hexDigit hi, hexDigit lo]
    hexDigit n
      | n < 10 = toEnum (n + fromEnum '0')
      | otherwise = toEnum (n - 10 + fromEnum 'A')

-- | Token refresh buffer (acquire new token 60 seconds before expiry)
tokenRefreshBuffer :: NominalDiffTime
tokenRefreshBuffer = 60

-- | Get a valid token, refreshing if necessary
--
-- This function checks the cached token and acquires a new one if:
-- - No token is cached
-- - The cached token is expired or about to expire (within 60 seconds)
getValidToken ::
  ServiceAccountClient ->
  IO (Either ServiceAccountError Text)
getValidToken client = do
  now <- getCurrentTime
  mCached <- atomically $ readTVar (sacCachedToken client)

  case mCached of
    Nothing -> do
      -- No cached token, acquire new one
      result <- acquireServiceToken client
      pure $ fmap cstAccessToken result
    Just cached -> do
      -- Check if token is still valid (with buffer)
      let expiryWithBuffer = addUTCTime (negate tokenRefreshBuffer) (cstExpiresAt cached)
      if now < expiryWithBuffer
        then pure $ Right (cstAccessToken cached)
        else do
          -- Token expired or about to expire, acquire new one
          result <- acquireServiceToken client
          pure $ fmap cstAccessToken result

-- | Check if a cached token is still valid
isTokenValid :: UTCTime -> CachedServiceToken -> Bool
isTokenValid now cached =
  let expiryWithBuffer = addUTCTime (negate tokenRefreshBuffer) (cstExpiresAt cached)
   in now < expiryWithBuffer
