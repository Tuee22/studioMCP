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
    eitherDecode,
    encode,
    object,
    withObject,
    (.:),
    (.:?),
    (.=),
  )
import qualified Data.ByteString.Lazy as LBS
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
    crRedirectUris :: [Text],
    crWebOrigins :: [Text],
    crProtocol :: Maybe Text,
    crStandardFlowEnabled :: Bool,
    crDirectAccessGrantsEnabled :: Bool,
    crServiceAccountsEnabled :: Bool,
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
        "redirectUris" .= crRedirectUris cr,
        "webOrigins" .= crWebOrigins cr,
        "protocol" .= crProtocol cr,
        "standardFlowEnabled" .= crStandardFlowEnabled cr,
        "directAccessGrantsEnabled" .= crDirectAccessGrantsEnabled cr,
        "serviceAccountsEnabled" .= crServiceAccountsEnabled cr,
        "secret" .= crSecret cr
      ]

instance FromJSON ClientRepresentation where
  parseJSON = withObject "ClientRepresentation" $ \obj ->
    ClientRepresentation
      <$> obj .: "clientId"
      <*> obj .:? "name"
      <*> obj .: "enabled"
      <*> obj .: "publicClient"
      <*> (obj .:? "redirectUris" >>= pure . maybe [] id)
      <*> (obj .:? "webOrigins" >>= pure . maybe [] id)
      <*> obj .:? "protocol"
      <*> (obj .:? "standardFlowEnabled" >>= pure . maybe False id)
      <*> (obj .:? "directAccessGrantsEnabled" >>= pure . maybe False id)
      <*> (obj .:? "serviceAccountsEnabled" >>= pure . maybe False id)
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
    csrDescription :: Maybe Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON ClientScopeRepresentation where
  toJSON csr =
    object
      [ "name" .= csrName csr,
        "protocol" .= csrProtocol csr,
        "description" .= csrDescription csr
      ]

instance FromJSON ClientScopeRepresentation where
  parseJSON = withObject "ClientScopeRepresentation" $ \obj ->
    ClientScopeRepresentation
      <$> obj .: "name"
      <*> obj .: "protocol"
      <*> obj .:? "description"

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
        "scopesCreated" .= brScopesCreated br,
        "warnings" .= brWarnings br
      ]

-- | Bootstrap the studioMCP realm with required clients and scopes
bootstrapStudioMCPRealm ::
  KeycloakAdminClient ->
  Text -> -- Realm name
  Text -> -- MCP client ID
  Text -> -- BFF client ID
  Text -> -- BFF redirect URI
  IO (Either AdminError BootstrapResult)
bootstrapStudioMCPRealm client realmName mcpClientId bffClientId bffRedirectUri = do
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
              rrDisplayName = Just "StudioMCP",
              rrSslRequired = Just "external"
            }
      case createResult of
        Left err -> pure $ Left err
        Right () -> pure $ Right True

  case realmCreated of
    Left err -> pure $ Left err
    Right realmWasCreated -> do
      -- Create MCP client (confidential, service accounts enabled)
      mcpClientExistsResult <- clientExists client realmName mcpClientId
      mcpClientCreated <- case mcpClientExistsResult of
        Left err -> pure $ Left err
        Right True -> pure $ Right False
        Right False -> do
          createResult <-
            createClient
              client
              realmName
              ClientRepresentation
                { crClientId = mcpClientId,
                  crName = Just "StudioMCP Server",
                  crEnabled = True,
                  crPublicClient = False,
                  crRedirectUris = [],
                  crWebOrigins = [],
                  crProtocol = Just "openid-connect",
                  crStandardFlowEnabled = False,
                  crDirectAccessGrantsEnabled = False,
                  crServiceAccountsEnabled = True,
                  crSecret = Nothing
                }
          case createResult of
            Left err -> pure $ Left err
            Right () -> pure $ Right True

      case mcpClientCreated of
        Left err -> pure $ Left err
        Right mcpWasCreated -> do
          -- Create BFF client (public, PKCE)
          bffClientExistsResult <- clientExists client realmName bffClientId
          bffClientCreated <- case bffClientExistsResult of
            Left err -> pure $ Left err
            Right True -> pure $ Right False
            Right False -> do
              createResult <-
                createClient
                  client
                  realmName
                  ClientRepresentation
                    { crClientId = bffClientId,
                      crName = Just "StudioMCP BFF",
                      crEnabled = True,
                      crPublicClient = True,
                      crRedirectUris = [bffRedirectUri, bffRedirectUri <> "/*"],
                      crWebOrigins = ["*"],
                      crProtocol = Just "openid-connect",
                      crStandardFlowEnabled = True,
                      crDirectAccessGrantsEnabled = False,
                      crServiceAccountsEnabled = False,
                      crSecret = Nothing
                    }
              case createResult of
                Left err -> pure $ Left err
                Right () -> pure $ Right True

          case bffClientCreated of
            Left err -> pure $ Left err
            Right bffWasCreated -> do
              -- Create custom scopes
              let customScopes =
                    [ ("workflow:read", "Read workflow status"),
                      ("workflow:write", "Submit and manage workflows"),
                      ("artifact:read", "Read artifacts"),
                      ("artifact:write", "Upload and modify artifacts")
                    ]

              scopesCreated <- createScopes client realmName customScopes []

              pure $
                Right
                  BootstrapResult
                    { brRealmCreated = realmWasCreated,
                      brMcpClientCreated = mcpWasCreated,
                      brBffClientCreated = bffWasCreated,
                      brScopesCreated = scopesCreated,
                      brWarnings = []
                    }

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
          csrDescription = Just desc
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
