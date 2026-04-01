{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Auth.Config
  ( -- * Keycloak Configuration
    KeycloakConfig (..),
    defaultKeycloakConfig,

    -- * Auth Configuration
    AuthConfig (..),
    defaultAuthConfig,

    -- * Environment Loading
    loadAuthConfigFromEnv,

    -- * URL Helpers
    jwksEndpoint,
    tokenEndpoint,
    authorizeEndpoint,
    userinfoEndpoint,

    -- * Validation
    validateKeycloakConfig,
    ConfigValidationError (..),
  )
where

import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    object,
    withObject,
    (.:),
    (.:?),
    (.=),
  )
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)
import System.Environment (lookupEnv)

-- | Keycloak server configuration
data KeycloakConfig = KeycloakConfig
  { -- | Keycloak issuer URL (e.g., "https://auth.example.com/realms/studiomcp")
    kcIssuer :: Text,
    -- | Expected audience in tokens (e.g., "studiomcp-mcp")
    kcAudience :: Text,
    -- | Realm name (extracted from issuer or explicitly set)
    kcRealm :: Text,
    -- | Client ID for this service (for token exchange)
    kcClientId :: Text,
    -- | Client secret (for confidential client operations)
    kcClientSecret :: Maybe Text,
    -- | JWKS cache TTL in seconds
    kcJwksCacheTtlSeconds :: Int,
    -- | JWKS fetch timeout in seconds
    kcJwksFetchTimeoutSeconds :: Int
  }
  deriving (Eq, Show, Generic)

instance ToJSON KeycloakConfig where
  toJSON kc =
    object
      [ "issuer" .= kcIssuer kc,
        "audience" .= kcAudience kc,
        "realm" .= kcRealm kc,
        "clientId" .= kcClientId kc,
        "jwksCacheTtlSeconds" .= kcJwksCacheTtlSeconds kc,
        "jwksFetchTimeoutSeconds" .= kcJwksFetchTimeoutSeconds kc
        -- Note: clientSecret intentionally not serialized
      ]

instance FromJSON KeycloakConfig where
  parseJSON = withObject "KeycloakConfig" $ \obj ->
    KeycloakConfig
      <$> obj .: "issuer"
      <*> obj .: "audience"
      <*> obj .: "realm"
      <*> obj .: "clientId"
      <*> obj .:? "clientSecret"
      <*> obj .: "jwksCacheTtlSeconds"
      <*> obj .: "jwksFetchTimeoutSeconds"

-- | Default Keycloak configuration for local development
defaultKeycloakConfig :: KeycloakConfig
defaultKeycloakConfig =
  KeycloakConfig
    { kcIssuer = "http://localhost:8080/realms/studiomcp",
      kcAudience = "studiomcp-mcp",
      kcRealm = "studiomcp",
      kcClientId = "studiomcp-mcp",
      kcClientSecret = Nothing,
      kcJwksCacheTtlSeconds = 300, -- 5 minutes
      kcJwksFetchTimeoutSeconds = 5
    }

-- | Full authentication configuration
data AuthConfig = AuthConfig
  { -- | Keycloak settings
    acKeycloak :: KeycloakConfig,
    -- | Whether auth is enabled (for local dev bypass)
    acEnabled :: Bool,
    -- | Whether to allow insecure HTTP connections (dev only)
    acAllowInsecureHttp :: Bool,
    -- | Allowed algorithms for JWT verification
    acAllowedAlgorithms :: [Text],
    -- | Token leeway in seconds (for clock skew)
    acTokenLeewaySeconds :: Int
  }
  deriving (Eq, Show, Generic)

instance ToJSON AuthConfig where
  toJSON ac =
    object
      [ "keycloak" .= acKeycloak ac,
        "enabled" .= acEnabled ac,
        "allowInsecureHttp" .= acAllowInsecureHttp ac,
        "allowedAlgorithms" .= acAllowedAlgorithms ac,
        "tokenLeewaySeconds" .= acTokenLeewaySeconds ac
      ]

instance FromJSON AuthConfig where
  parseJSON = withObject "AuthConfig" $ \obj ->
    AuthConfig
      <$> obj .: "keycloak"
      <*> obj .: "enabled"
      <*> obj .: "allowInsecureHttp"
      <*> obj .: "allowedAlgorithms"
      <*> obj .: "tokenLeewaySeconds"

-- | Default auth configuration for development
defaultAuthConfig :: AuthConfig
defaultAuthConfig =
  AuthConfig
    { acKeycloak = defaultKeycloakConfig,
      acEnabled = False, -- Disabled by default for local dev
      acAllowInsecureHttp = True, -- Allow HTTP for local dev
      acAllowedAlgorithms = ["RS256", "RS384", "RS512", "ES256"],
      acTokenLeewaySeconds = 60
    }

-- | Load auth configuration from environment variables
loadAuthConfigFromEnv :: IO AuthConfig
loadAuthConfigFromEnv = do
  -- Keycloak settings
  issuer <- lookupEnvText "STUDIOMCP_KEYCLOAK_ISSUER" "http://localhost:8080/realms/studiomcp"
  audience <- lookupEnvText "STUDIOMCP_KEYCLOAK_AUDIENCE" "studiomcp-mcp"
  realm <- lookupEnvText "STUDIOMCP_KEYCLOAK_REALM" "studiomcp"
  clientId <- lookupEnvText "STUDIOMCP_KEYCLOAK_CLIENT_ID" "studiomcp-mcp"
  clientSecret <- lookupEnvMaybe "STUDIOMCP_KEYCLOAK_CLIENT_SECRET"
  jwksCacheTtl <- lookupEnvInt "STUDIOMCP_JWKS_CACHE_TTL" 300
  jwksFetchTimeout <- lookupEnvInt "STUDIOMCP_JWKS_FETCH_TIMEOUT" 5

  -- Auth settings
  enabled <- lookupEnvBool "STUDIOMCP_AUTH_ENABLED" False
  allowInsecure <- lookupEnvBool "STUDIOMCP_AUTH_ALLOW_INSECURE" True
  tokenLeeway <- lookupEnvInt "STUDIOMCP_TOKEN_LEEWAY" 60

  let keycloakConfig =
        KeycloakConfig
          { kcIssuer = issuer,
            kcAudience = audience,
            kcRealm = realm,
            kcClientId = clientId,
            kcClientSecret = clientSecret,
            kcJwksCacheTtlSeconds = jwksCacheTtl,
            kcJwksFetchTimeoutSeconds = jwksFetchTimeout
          }

  pure
    AuthConfig
      { acKeycloak = keycloakConfig,
        acEnabled = enabled,
        acAllowInsecureHttp = allowInsecure,
        acAllowedAlgorithms = ["RS256", "RS384", "RS512", "ES256"],
        acTokenLeewaySeconds = tokenLeeway
      }

-- | Helper to lookup text env var with default
lookupEnvText :: String -> Text -> IO Text
lookupEnvText name def = maybe def T.pack <$> lookupEnv name

-- | Helper to lookup optional text env var
lookupEnvMaybe :: String -> IO (Maybe Text)
lookupEnvMaybe name = fmap T.pack <$> lookupEnv name

-- | Helper to lookup int env var with default
lookupEnvInt :: String -> Int -> IO Int
lookupEnvInt name def = do
  mVal <- lookupEnv name
  pure $ case mVal of
    Just s -> maybe def id (readMaybe s)
    Nothing -> def
  where
    readMaybe s = case reads s of
      [(v, "")] -> Just v
      _ -> Nothing

-- | Helper to lookup bool env var with default
lookupEnvBool :: String -> Bool -> IO Bool
lookupEnvBool name def = do
  mVal <- lookupEnv name
  pure $ case mVal of
    Just "true" -> True
    Just "1" -> True
    Just "false" -> False
    Just "0" -> False
    _ -> def

-- | Get JWKS endpoint URL from Keycloak config
jwksEndpoint :: KeycloakConfig -> Text
jwksEndpoint kc = kcIssuer kc <> "/protocol/openid-connect/certs"

-- | Get token endpoint URL from Keycloak config
tokenEndpoint :: KeycloakConfig -> Text
tokenEndpoint kc = kcIssuer kc <> "/protocol/openid-connect/token"

-- | Get authorization endpoint URL from Keycloak config
authorizeEndpoint :: KeycloakConfig -> Text
authorizeEndpoint kc = kcIssuer kc <> "/protocol/openid-connect/auth"

-- | Get userinfo endpoint URL from Keycloak config
userinfoEndpoint :: KeycloakConfig -> Text
userinfoEndpoint kc = kcIssuer kc <> "/protocol/openid-connect/userinfo"

-- | Configuration validation error
data ConfigValidationError
  = EmptyIssuer
  | EmptyAudience
  | EmptyRealm
  | EmptyClientId
  | InsecureHttpNotAllowed
  | InvalidCacheTtl Int
  | InvalidFetchTimeout Int
  deriving (Eq, Show, Generic)

-- | Validate Keycloak configuration
validateKeycloakConfig :: AuthConfig -> [ConfigValidationError]
validateKeycloakConfig config =
  concat
    [ [EmptyIssuer | T.null (kcIssuer kc)],
      [EmptyAudience | T.null (kcAudience kc)],
      [EmptyRealm | T.null (kcRealm kc)],
      [EmptyClientId | T.null (kcClientId kc)],
      [ InsecureHttpNotAllowed
        | not (acAllowInsecureHttp config)
            && T.isPrefixOf "http://" (kcIssuer kc)
      ],
      [InvalidCacheTtl (kcJwksCacheTtlSeconds kc) | kcJwksCacheTtlSeconds kc <= 0],
      [InvalidFetchTimeout (kcJwksFetchTimeoutSeconds kc) | kcJwksFetchTimeoutSeconds kc <= 0]
    ]
  where
    kc = acKeycloak config
