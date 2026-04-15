{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Auth.Admin
  ( -- * Keycloak Admin Client
    KeycloakAdminClient (..),
    KeycloakAdminConfig (..),
    defaultAdminConfig,
    newAdminClient,

    -- * Realm Operations
    createRealm,
    getRealm,
    realmExists,

    -- * Client Operations
    createClient,
    getClient,
    clientExists,
    updateClientSecret,

    -- * Scope Operations
    createClientScope,
    addDefaultClientScope,

    -- * Bootstrap Operations
    bootstrapStudioMCPRealm,
    BootstrapResult (..),
    importRealmDefinition,

    -- * Errors
    AdminError (..),
    adminErrorToText,
  )
where

import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    Value,
    eitherDecode,
    encode,
    object,
    withObject,
    (.:),
    (.:?),
    (.=),
  )
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
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

-- | Keycloak Admin API configuration
data KeycloakAdminConfig = KeycloakAdminConfig
  { -- | Keycloak base URL (e.g., "http://localhost:8080")
    kacBaseUrl :: Text,
    -- | Admin username
    kacAdminUser :: Text,
    -- | Admin password
    kacAdminPassword :: Text,
    -- | Admin realm (usually "master")
    kacAdminRealm :: Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON KeycloakAdminConfig where
  toJSON kac =
    object
      [ "baseUrl" .= kacBaseUrl kac,
        "adminUser" .= kacAdminUser kac,
        "adminRealm" .= kacAdminRealm kac
        -- Note: adminPassword intentionally not serialized
      ]

-- | Default admin configuration for local development
defaultAdminConfig :: KeycloakAdminConfig
defaultAdminConfig =
  KeycloakAdminConfig
    { kacBaseUrl = "http://localhost:8080",
      kacAdminUser = "admin",
      kacAdminPassword = "admin",
      kacAdminRealm = "master"
    }

-- | Keycloak Admin client
data KeycloakAdminClient = KeycloakAdminClient
  { kacConfig :: KeycloakAdminConfig,
    kacManager :: Manager,
    kacAccessToken :: Text
  }

-- | Admin API errors
data AdminError
  = -- | Authentication failed
    AuthenticationFailed Text
  | -- | Resource not found
    ResourceNotFound Text
  | -- | Resource already exists
    ResourceAlreadyExists Text
  | -- | Request failed
    RequestFailed Int Text
  | -- | Parse error
    ParseError Text
  | -- | Network error
    NetworkError Text
  deriving (Eq, Show, Generic)

instance ToJSON AdminError where
  toJSON err =
    object
      [ "error" .= adminErrorCode err,
        "message" .= adminErrorToText err
      ]

-- | Convert error to human-readable text
adminErrorToText :: AdminError -> Text
adminErrorToText (AuthenticationFailed msg) = "Authentication failed: " <> msg
adminErrorToText (ResourceNotFound msg) = "Resource not found: " <> msg
adminErrorToText (ResourceAlreadyExists msg) = "Resource already exists: " <> msg
adminErrorToText (RequestFailed status msg) =
  "Request failed with status " <> T.pack (show status) <> ": " <> msg
adminErrorToText (ParseError msg) = "Parse error: " <> msg
adminErrorToText (NetworkError msg) = "Network error: " <> msg

-- | Get error code
adminErrorCode :: AdminError -> Text
adminErrorCode (AuthenticationFailed _) = "authentication_failed"
adminErrorCode (ResourceNotFound _) = "resource_not_found"
adminErrorCode (ResourceAlreadyExists _) = "resource_already_exists"
adminErrorCode (RequestFailed _ _) = "request_failed"
adminErrorCode (ParseError _) = "parse_error"
adminErrorCode (NetworkError _) = "network_error"

-- | Token response from admin login
data AdminTokenResponse = AdminTokenResponse
  { atrAccessToken :: Text,
    atrExpiresIn :: Int
  }
  deriving (Eq, Show, Generic)

instance FromJSON AdminTokenResponse where
  parseJSON = withObject "AdminTokenResponse" $ \obj ->
    AdminTokenResponse
      <$> obj .: "access_token"
      <*> obj .: "expires_in"

-- | Create a new admin client by authenticating with Keycloak
newAdminClient ::
  KeycloakAdminConfig ->
  Manager ->
  IO (Either AdminError KeycloakAdminClient)
newAdminClient config manager = do
  let tokenUrl =
        T.unpack $
          kacBaseUrl config
            <> "/realms/"
            <> kacAdminRealm config
            <> "/protocol/openid-connect/token"
      body =
        LBS.fromStrict $
          TE.encodeUtf8 $
            T.intercalate
              "&"
              [ "grant_type=password",
                "client_id=admin-cli",
                "username=" <> urlEncode (kacAdminUser config),
                "password=" <> urlEncode (kacAdminPassword config)
              ]

  result <- makePostRequest manager tokenUrl body "application/x-www-form-urlencoded"
  case result of
    Left err -> pure $ Left err
    Right responseBody' ->
      case eitherDecode responseBody' of
        Left err -> pure $ Left $ ParseError (T.pack err)
        Right tokenResp ->
          pure $
            Right
              KeycloakAdminClient
                { kacConfig = config,
                  kacManager = manager,
                  kacAccessToken = atrAccessToken tokenResp
                }

-- | Realm representation (minimal)
data RealmRepresentation = RealmRepresentation
  { rrRealm :: Text,
    rrEnabled :: Bool,
    rrDisplayName :: Maybe Text,
    rrSslRequired :: Maybe Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON RealmRepresentation where
  toJSON rr =
    object
      [ "realm" .= rrRealm rr,
        "enabled" .= rrEnabled rr,
        "displayName" .= rrDisplayName rr,
        "sslRequired" .= rrSslRequired rr
      ]

instance FromJSON RealmRepresentation where
  parseJSON = withObject "RealmRepresentation" $ \obj ->
    RealmRepresentation
      <$> obj .: "realm"
      <*> obj .: "enabled"
      <*> obj .:? "displayName"
      <*> obj .:? "sslRequired"

-- | Create a new realm
createRealm ::
  KeycloakAdminClient ->
  RealmRepresentation ->
  IO (Either AdminError ())
createRealm client realm = do
  let url = T.unpack $ kacBaseUrl (kacConfig client) <> "/admin/realms"
  result <- makeAuthPostRequest client url (encode realm)
  case result of
    Left err -> pure $ Left err
    Right (status, _) ->
      if status == 201 || status == 204
        then pure $ Right ()
        else pure $ Left $ RequestFailed status "Failed to create realm"

-- | Get realm by name
getRealm ::
  KeycloakAdminClient ->
  Text ->
  IO (Either AdminError RealmRepresentation)
getRealm client realmName = do
  let url = T.unpack $ kacBaseUrl (kacConfig client) <> "/admin/realms/" <> realmName
  result <- makeAuthGetRequest client url
  case result of
    Left err -> pure $ Left err
    Right (status, body) ->
      if status == 200
        then case eitherDecode body of
          Left err -> pure $ Left $ ParseError (T.pack err)
          Right realm -> pure $ Right realm
        else
          if status == 404
            then pure $ Left $ ResourceNotFound realmName
            else pure $ Left $ RequestFailed status "Failed to get realm"

-- | Check if realm exists
realmExists ::
  KeycloakAdminClient ->
  Text ->
  IO (Either AdminError Bool)
realmExists client realmName = do
  result <- getRealm client realmName
  case result of
    Left (ResourceNotFound _) -> pure $ Right False
    Left err -> pure $ Left err
    Right _ -> pure $ Right True

-- | Client representation (minimal)
data ClientRepresentation = ClientRepresentation
  { crClientId :: Text,
    crName :: Maybe Text,
    crEnabled :: Bool,
    crPublicClient :: Bool,
    crBearerOnly :: Bool,
    crRedirectUris :: [Text],
    crWebOrigins :: [Text],
    crProtocol :: Maybe Text,
    crStandardFlowEnabled :: Bool,
    crDirectAccessGrantsEnabled :: Bool,
    crServiceAccountsEnabled :: Bool,
    crFullScopeAllowed :: Bool,
    crDefaultClientScopes :: [Text],
    crOptionalClientScopes :: [Text],
    crProtocolMappers :: [Value],
    crSecret :: Maybe Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON ClientRepresentation where
  toJSON cr =
    object
      [ "clientId" .= crClientId cr,
        "name" .= crName cr,
        "enabled" .= crEnabled cr,
        "publicClient" .= crPublicClient cr,
        "bearerOnly" .= crBearerOnly cr,
        "redirectUris" .= crRedirectUris cr,
        "webOrigins" .= crWebOrigins cr,
        "protocol" .= crProtocol cr,
        "standardFlowEnabled" .= crStandardFlowEnabled cr,
        "directAccessGrantsEnabled" .= crDirectAccessGrantsEnabled cr,
        "serviceAccountsEnabled" .= crServiceAccountsEnabled cr,
        "fullScopeAllowed" .= crFullScopeAllowed cr,
        "defaultClientScopes" .= crDefaultClientScopes cr,
        "optionalClientScopes" .= crOptionalClientScopes cr,
        "protocolMappers" .= crProtocolMappers cr,
        "secret" .= crSecret cr
      ]

instance FromJSON ClientRepresentation where
  parseJSON = withObject "ClientRepresentation" $ \obj ->
    ClientRepresentation
      <$> obj .: "clientId"
      <*> obj .:? "name"
      <*> obj .: "enabled"
      <*> obj .: "publicClient"
      <*> (obj .:? "bearerOnly" >>= pure . maybe False id)
      <*> (obj .:? "redirectUris" >>= pure . maybe [] id)
      <*> (obj .:? "webOrigins" >>= pure . maybe [] id)
      <*> obj .:? "protocol"
      <*> (obj .:? "standardFlowEnabled" >>= pure . maybe False id)
      <*> (obj .:? "directAccessGrantsEnabled" >>= pure . maybe False id)
      <*> (obj .:? "serviceAccountsEnabled" >>= pure . maybe False id)
      <*> (obj .:? "fullScopeAllowed" >>= pure . maybe False id)
      <*> (obj .:? "defaultClientScopes" >>= pure . maybe [] id)
      <*> (obj .:? "optionalClientScopes" >>= pure . maybe [] id)
      <*> (obj .:? "protocolMappers" >>= pure . maybe [] id)
      <*> obj .:? "secret"

-- | Create a new client
createClient ::
  KeycloakAdminClient ->
  Text -> -- Realm name
  ClientRepresentation ->
  IO (Either AdminError ())
createClient client realmName clientRep = do
  let url =
        T.unpack $
          kacBaseUrl (kacConfig client)
            <> "/admin/realms/"
            <> realmName
            <> "/clients"
  result <- makeAuthPostRequest client url (encode clientRep)
  case result of
    Left err -> pure $ Left err
    Right (status, _) ->
      if status == 201 || status == 204
        then pure $ Right ()
        else
          if status == 409
            then pure $ Left $ ResourceAlreadyExists (crClientId clientRep)
            else pure $ Left $ RequestFailed status "Failed to create client"

-- | Get client by clientId
getClient ::
  KeycloakAdminClient ->
  Text -> -- Realm name
  Text -> -- Client ID
  IO (Either AdminError ClientRepresentation)
getClient client realmName clientId = do
  let url =
        T.unpack $
          kacBaseUrl (kacConfig client)
            <> "/admin/realms/"
            <> realmName
            <> "/clients?clientId="
            <> urlEncode clientId
  result <- makeAuthGetRequest client url
  case result of
    Left err -> pure $ Left err
    Right (status, body) ->
      if status == 200
        then case eitherDecode body of
          Left err -> pure $ Left $ ParseError (T.pack err)
          Right (clients :: [ClientRepresentation]) ->
            case clients of
              [] -> pure $ Left $ ResourceNotFound clientId
              (c : _) -> pure $ Right c
        else pure $ Left $ RequestFailed status "Failed to get client"

-- | Check if client exists
clientExists ::
  KeycloakAdminClient ->
  Text -> -- Realm name
  Text -> -- Client ID
  IO (Either AdminError Bool)
clientExists client realmName clientId = do
  result <- getClient client realmName clientId
  case result of
    Left (ResourceNotFound _) -> pure $ Right False
    Left err -> pure $ Left err
    Right _ -> pure $ Right True

-- | Update client secret
updateClientSecret ::
  KeycloakAdminClient ->
  Text -> -- Realm name
  Text -> -- Client UUID (not clientId)
  IO (Either AdminError Text)
updateClientSecret client realmName clientUuid = do
  let url =
        T.unpack $
          kacBaseUrl (kacConfig client)
            <> "/admin/realms/"
            <> realmName
            <> "/clients/"
            <> clientUuid
            <> "/client-secret"
  result <- makeAuthPostRequest client url ""
  case result of
    Left err -> pure $ Left err
    Right (status, body) ->
      if status == 200
        then case eitherDecode body of
          Left err -> pure $ Left $ ParseError (T.pack err)
          Right secretResp -> pure $ Right (csrValue secretResp)
        else pure $ Left $ RequestFailed status "Failed to regenerate client secret"

-- | Client secret response
data ClientSecretResponse = ClientSecretResponse
  { csrValue :: Text
  }
  deriving (Eq, Show, Generic)

instance FromJSON ClientSecretResponse where
  parseJSON = withObject "ClientSecretResponse" $ \obj ->
    ClientSecretResponse <$> obj .: "value"

-- | Client scope representation (minimal)
data ClientScopeRepresentation = ClientScopeRepresentation
  { csrName :: Text,
    csrProtocol :: Text,
    csrDescription :: Maybe Text,
    csrAttributes :: Map.Map Text Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON ClientScopeRepresentation where
  toJSON csr =
    object
      [ "name" .= csrName csr,
        "protocol" .= csrProtocol csr,
        "description" .= csrDescription csr,
        "attributes" .= csrAttributes csr
      ]

instance FromJSON ClientScopeRepresentation where
  parseJSON = withObject "ClientScopeRepresentation" $ \obj ->
    ClientScopeRepresentation
      <$> obj .: "name"
      <*> obj .: "protocol"
      <*> obj .:? "description"
      <*> (obj .:? "attributes" >>= pure . maybe Map.empty id)

-- | Create a client scope
createClientScope ::
  KeycloakAdminClient ->
  Text -> -- Realm name
  ClientScopeRepresentation ->
  IO (Either AdminError ())
createClientScope client realmName scope = do
  let url =
        T.unpack $
          kacBaseUrl (kacConfig client)
            <> "/admin/realms/"
            <> realmName
            <> "/client-scopes"
  result <- makeAuthPostRequest client url (encode scope)
  case result of
    Left err -> pure $ Left err
    Right (status, _) ->
      if status == 201 || status == 204
        then pure $ Right ()
        else
          if status == 409
            then pure $ Left $ ResourceAlreadyExists (csrName scope)
            else pure $ Left $ RequestFailed status "Failed to create client scope"

-- | Add a default client scope to a client
addDefaultClientScope ::
  KeycloakAdminClient ->
  Text -> -- Realm name
  Text -> -- Client UUID
  Text -> -- Scope UUID
  IO (Either AdminError ())
addDefaultClientScope client realmName clientUuid scopeUuid = do
  let url =
        T.unpack $
          kacBaseUrl (kacConfig client)
            <> "/admin/realms/"
            <> realmName
            <> "/clients/"
            <> clientUuid
            <> "/default-client-scopes/"
            <> scopeUuid
  result <- makeAuthPutRequest client url ""
  case result of
    Left err -> pure $ Left err
    Right (status, _) ->
      if status == 204 || status == 200
        then pure $ Right ()
        else pure $ Left $ RequestFailed status "Failed to add default client scope"

-- | Bootstrap result
data BootstrapResult = BootstrapResult
  { brRealmCreated :: Bool,
    brMcpClientCreated :: Bool,
    brBffClientCreated :: Bool,
    brServiceClientCreated :: Bool,
    brScopesCreated :: [Text],
    brWarnings :: [Text]
  }
  deriving (Eq, Show, Generic)

instance ToJSON BootstrapResult where
  toJSON br =
    object
      [ "realmCreated" .= brRealmCreated br,
        "mcpClientCreated" .= brMcpClientCreated br,
        "bffClientCreated" .= brBffClientCreated br,
        "serviceClientCreated" .= brServiceClientCreated br,
        "scopesCreated" .= brScopesCreated br,
        "warnings" .= brWarnings br
      ]

-- | Bootstrap the studioMCP realm with required clients and scopes
bootstrapStudioMCPRealm ::
  KeycloakAdminClient ->
  Text -> -- Realm name
  Text -> -- MCP client ID
  Text -> -- BFF client ID
  Text -> -- Service client ID
  IO (Either AdminError BootstrapResult)
bootstrapStudioMCPRealm client realmName mcpClientId bffClientId serviceClientId = do
  -- Create realm if it doesn't exist
  realmExistsResult <- realmExists client realmName
  realmCreated <- case realmExistsResult of
    Left err -> pure $ Left err
    Right True -> pure $ Right False
    Right False -> do
      createResult <-
        createRealm
          client
          RealmRepresentation
            { rrRealm = realmName,
              rrEnabled = True,
              rrDisplayName = Just "studioMCP",
              rrSslRequired = Just "none"
            }
      case createResult of
        Left err -> pure $ Left err
        Right () -> pure $ Right True

  case realmCreated of
    Left err -> pure $ Left err
    Right realmWasCreated -> do
      mcpClientCreated <- ensureClientCreated client realmName (mcpClientRepresentation mcpClientId)
      case mcpClientCreated of
        Left err -> pure $ Left err
        Right mcpWasCreated -> do
          bffClientCreated <- ensureClientCreated client realmName (bffClientRepresentation bffClientId)
          case bffClientCreated of
            Left err -> pure $ Left err
            Right bffWasCreated -> do
              serviceClientCreated <- ensureClientCreated client realmName (serviceClientRepresentation serviceClientId)
              case serviceClientCreated of
                Left err -> pure $ Left err
                Right serviceWasCreated -> do
                  scopesCreated <- createScopes client realmName bootstrapClientScopes []

                  pure $
                    Right
                      BootstrapResult
                        { brRealmCreated = realmWasCreated,
                          brMcpClientCreated = mcpWasCreated,
                          brBffClientCreated = bffWasCreated,
                          brServiceClientCreated = serviceWasCreated,
                          brScopesCreated = scopesCreated,
                          brWarnings = []
                        }

bootstrapClientScopes :: [(Text, Text)]
bootstrapClientScopes =
  [ ("workflow:read", "Read workflow runs"),
    ("workflow:write", "Submit and manage workflow runs"),
    ("artifact:read", "Read artifacts"),
    ("artifact:write", "Write artifacts"),
    ("artifact:manage", "Manage artifact lifecycle"),
    ("prompt:read", "Read MCP prompts"),
    ("resource:read", "Read MCP resources"),
    ("tenant:read", "Read tenant metadata and quotas")
  ]

bootstrapScopeAttributes :: Map.Map Text Text
bootstrapScopeAttributes =
  Map.fromList
    [ ("include.in.token.scope", "true"),
      ("display.on.consent.screen", "false")
    ]

bootstrapBffClientSecret :: Text
bootstrapBffClientSecret = "studiomcp-bff-dev-secret"

bootstrapServiceClientSecret :: Text
bootstrapServiceClientSecret = "studiomcp-service-dev-secret"

mcpClientRepresentation :: Text -> ClientRepresentation
mcpClientRepresentation clientId =
  ClientRepresentation
    { crClientId = clientId,
      crName = Just "studioMCP MCP Server",
      crEnabled = True,
      crPublicClient = False,
      crBearerOnly = True,
      crRedirectUris = [],
      crWebOrigins = [],
      crProtocol = Just "openid-connect",
      crStandardFlowEnabled = False,
      crDirectAccessGrantsEnabled = False,
      crServiceAccountsEnabled = False,
      crFullScopeAllowed = False,
      crDefaultClientScopes = ["openid", "profile"],
      crOptionalClientScopes =
        [ "workflow:read",
          "workflow:write",
          "artifact:read",
          "artifact:write",
          "artifact:manage",
          "prompt:read",
          "resource:read",
          "tenant:read"
        ],
      crProtocolMappers = [],
      crSecret = Nothing
    }

bffClientRepresentation :: Text -> ClientRepresentation
bffClientRepresentation clientId =
  ClientRepresentation
    { crClientId = clientId,
      crName = Just "studioMCP BFF",
      crEnabled = True,
      crPublicClient = False,
      crBearerOnly = False,
      crRedirectUris = [],
      crWebOrigins = [],
      crProtocol = Just "openid-connect",
      crStandardFlowEnabled = False,
      crDirectAccessGrantsEnabled = True,
      crServiceAccountsEnabled = False,
      crFullScopeAllowed = False,
      crDefaultClientScopes =
        [ "profile",
          "email",
          "roles",
          "web-origins",
          "workflow:read",
          "workflow:write",
          "artifact:read",
          "artifact:write",
          "prompt:read",
          "resource:read",
          "tenant:read"
        ],
      crOptionalClientScopes = ["artifact:manage"],
      crProtocolMappers = bffProtocolMappers,
      crSecret = Just bootstrapBffClientSecret
    }

serviceClientRepresentation :: Text -> ClientRepresentation
serviceClientRepresentation clientId =
  ClientRepresentation
    { crClientId = clientId,
      crName = Just "studioMCP Service Account",
      crEnabled = True,
      crPublicClient = False,
      crBearerOnly = False,
      crRedirectUris = [],
      crWebOrigins = [],
      crProtocol = Just "openid-connect",
      crStandardFlowEnabled = False,
      crDirectAccessGrantsEnabled = False,
      crServiceAccountsEnabled = True,
      crFullScopeAllowed = False,
      crDefaultClientScopes = ["openid", "workflow:read", "workflow:write"],
      crOptionalClientScopes = [],
      crProtocolMappers = [],
      crSecret = Just bootstrapServiceClientSecret
    }

bffProtocolMappers :: [Value]
bffProtocolMappers =
  [ object
      [ "name" .= ("tenant-id" :: Text),
        "protocol" .= ("openid-connect" :: Text),
        "protocolMapper" .= ("oidc-usermodel-attribute-mapper" :: Text),
        "consentRequired" .= False,
        "config"
          .= object
            [ "user.attribute" .= ("tenant_id" :: Text),
              "claim.name" .= ("tenant_id" :: Text),
              "jsonType.label" .= ("String" :: Text),
              "id.token.claim" .= ("true" :: Text),
              "access.token.claim" .= ("true" :: Text),
              "userinfo.token.claim" .= ("true" :: Text)
            ]
      ],
    object
      [ "name" .= ("mcp-audience" :: Text),
        "protocol" .= ("openid-connect" :: Text),
        "protocolMapper" .= ("oidc-audience-mapper" :: Text),
        "consentRequired" .= False,
        "config"
          .= object
            [ "included.client.audience" .= ("studiomcp-mcp" :: Text),
              "id.token.claim" .= ("false" :: Text),
              "access.token.claim" .= ("true" :: Text)
            ]
      ]
  ]

ensureClientCreated ::
  KeycloakAdminClient ->
  Text ->
  ClientRepresentation ->
  IO (Either AdminError Bool)
ensureClientCreated client realmName clientRep = do
  clientExistsResult <- clientExists client realmName (crClientId clientRep)
  case clientExistsResult of
    Left err -> pure $ Left err
    Right True -> pure $ Right False
    Right False -> do
      createResult <- createClient client realmName clientRep
      case createResult of
        Left err -> pure $ Left err
        Right () -> pure $ Right True

importRealmDefinition ::
  KeycloakAdminClient ->
  LBS.ByteString ->
  IO (Either AdminError ())
importRealmDefinition client realmDefinition = do
  let url = T.unpack $ kacBaseUrl (kacConfig client) <> "/admin/realms"
  result <- makeAuthPostRequest client url realmDefinition
  case result of
    Left err -> pure $ Left err
    Right (status, _)
      | status == 201 || status == 204 -> pure (Right ())
      | otherwise -> pure $ Left $ RequestFailed status "Failed to import realm definition"

-- | Create scopes, collecting names of successfully created ones
createScopes ::
  KeycloakAdminClient ->
  Text ->
  [(Text, Text)] ->
  [Text] ->
  IO [Text]
createScopes _ _ [] acc = pure acc
createScopes client realmName ((name, desc) : rest) acc = do
  result <-
    createClientScope
      client
      realmName
      ClientScopeRepresentation
        { csrName = name,
          csrProtocol = "openid-connect",
          csrDescription = Just desc,
          csrAttributes = bootstrapScopeAttributes
        }
  case result of
    Left (ResourceAlreadyExists _) ->
      createScopes client realmName rest acc
    Left _ ->
      createScopes client realmName rest acc
    Right () ->
      createScopes client realmName rest (name : acc)

-- | Make authenticated GET request
makeAuthGetRequest ::
  KeycloakAdminClient ->
  String ->
  IO (Either AdminError (Int, LBS.ByteString))
makeAuthGetRequest client url = do
  mReq <- parseRequest url
  case mReq of
    req -> do
      let request =
            req
              { method = "GET",
                requestHeaders =
                  [ ("Authorization", "Bearer " <> TE.encodeUtf8 (kacAccessToken client)),
                    ("Content-Type", "application/json")
                  ]
              }
      response <- httpLbs request (kacManager client)
      let status = statusCode $ responseStatus response
      pure $ Right (status, responseBody response)

-- | Make authenticated POST request
makeAuthPostRequest ::
  KeycloakAdminClient ->
  String ->
  LBS.ByteString ->
  IO (Either AdminError (Int, LBS.ByteString))
makeAuthPostRequest client url body = do
  mReq <- parseRequest url
  case mReq of
    req -> do
      let request =
            req
              { method = "POST",
                requestBody = RequestBodyLBS body,
                requestHeaders =
                  [ ("Authorization", "Bearer " <> TE.encodeUtf8 (kacAccessToken client)),
                    ("Content-Type", "application/json")
                  ]
              }
      response <- httpLbs request (kacManager client)
      let status = statusCode $ responseStatus response
      pure $ Right (status, responseBody response)

-- | Make authenticated PUT request
makeAuthPutRequest ::
  KeycloakAdminClient ->
  String ->
  LBS.ByteString ->
  IO (Either AdminError (Int, LBS.ByteString))
makeAuthPutRequest client url body = do
  mReq <- parseRequest url
  case mReq of
    req -> do
      let request =
            req
              { method = "PUT",
                requestBody = RequestBodyLBS body,
                requestHeaders =
                  [ ("Authorization", "Bearer " <> TE.encodeUtf8 (kacAccessToken client)),
                    ("Content-Type", "application/json")
                  ]
              }
      response <- httpLbs request (kacManager client)
      let status = statusCode $ responseStatus response
      pure $ Right (status, responseBody response)

-- | Make POST request (unauthenticated)
makePostRequest ::
  Manager ->
  String ->
  LBS.ByteString ->
  LBS.ByteString ->
  IO (Either AdminError LBS.ByteString)
makePostRequest manager url body contentType = do
  mReq <- parseRequest url
  case mReq of
    req -> do
      let request =
            req
              { method = "POST",
                requestBody = RequestBodyLBS body,
                requestHeaders = [("Content-Type", LBS.toStrict contentType)]
              }
      response <- httpLbs request manager
      let status = statusCode $ responseStatus response
      if status >= 200 && status < 300
        then pure $ Right $ responseBody response
        else pure $ Left $ RequestFailed status (TE.decodeUtf8 $ LBS.toStrict $ responseBody response)

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
