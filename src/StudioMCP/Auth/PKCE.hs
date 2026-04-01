{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Auth.PKCE
  ( -- * PKCE Challenge
    PKCEChallenge (..),
    generatePKCEChallenge,

    -- * Authorization URL
    AuthorizationParams (..),
    buildAuthorizationUrl,

    -- * Token Exchange
    TokenExchangeParams (..),
    TokenResponse (..),
    exchangeCodeForTokens,

    -- * Token Refresh
    RefreshParams (..),
    refreshAccessToken,

    -- * Errors
    PKCEError (..),
    pkceErrorToText,
  )
where

import Crypto.Hash (Digest, SHA256 (..), hash)
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
import qualified Data.ByteArray as BA
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base64.URL as B64URL
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time (UTCTime)
import GHC.Generics (Generic)
import Network.HTTP.Client
  ( Manager,
    Request,
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
import StudioMCP.Auth.Config (KeycloakConfig (..), authorizeEndpoint, tokenEndpoint)
import System.Random (randomRIO)

-- | PKCE challenge data
data PKCEChallenge = PKCEChallenge
  { -- | The code verifier (43-128 character random string)
    pcVerifier :: Text,
    -- | The code challenge (SHA256 hash of verifier, base64url encoded)
    pcChallenge :: Text,
    -- | The challenge method (always "S256")
    pcMethod :: Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON PKCEChallenge where
  toJSON pc =
    object
      [ "verifier" .= pcVerifier pc,
        "challenge" .= pcChallenge pc,
        "method" .= pcMethod pc
      ]

-- | Generate a new PKCE challenge
generatePKCEChallenge :: IO PKCEChallenge
generatePKCEChallenge = do
  -- Generate 32 random bytes (will produce 43 characters base64url encoded)
  bytes <- replicateM 32 (randomRIO (0, 255) :: IO Int)
  let byteString = BS.pack (map fromIntegral bytes)
      -- Base64url encode without padding for the verifier
      verifier = stripPadding $ B64URL.encode byteString
      -- SHA256 hash the verifier and base64url encode for the challenge
      verifierHash :: Digest SHA256
      verifierHash = hash (TE.encodeUtf8 $ TE.decodeUtf8 verifier)
      challenge = stripPadding $ B64URL.encode (BA.convert verifierHash :: BS.ByteString)
  pure
    PKCEChallenge
      { pcVerifier = TE.decodeUtf8 verifier,
        pcChallenge = TE.decodeUtf8 challenge,
        pcMethod = "S256"
      }
  where
    -- Strip padding characters for base64url-no-pad encoding
    stripPadding = BS.filter (/= 61) -- 61 is '='
    replicateM n action = sequence (replicate n action)

-- | Parameters for building an authorization URL
data AuthorizationParams = AuthorizationParams
  { -- | Client ID
    apClientId :: Text,
    -- | Redirect URI (where Keycloak will send the auth code)
    apRedirectUri :: Text,
    -- | Requested scopes
    apScope :: [Text],
    -- | State parameter (for CSRF protection)
    apState :: Text,
    -- | PKCE challenge
    apPkceChallenge :: PKCEChallenge
  }
  deriving (Eq, Show, Generic)

-- | Build the authorization URL for OAuth2 PKCE flow
buildAuthorizationUrl :: KeycloakConfig -> AuthorizationParams -> Text
buildAuthorizationUrl kc params =
  authorizeEndpoint kc
    <> "?"
    <> T.intercalate
      "&"
      [ "client_id=" <> urlEncode (apClientId params),
        "redirect_uri=" <> urlEncode (apRedirectUri params),
        "response_type=code",
        "scope=" <> urlEncode (T.intercalate " " (apScope params)),
        "state=" <> urlEncode (apState params),
        "code_challenge=" <> urlEncode (pcChallenge (apPkceChallenge params)),
        "code_challenge_method=" <> pcMethod (apPkceChallenge params)
      ]

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

-- | Parameters for exchanging authorization code for tokens
data TokenExchangeParams = TokenExchangeParams
  { -- | Client ID
    teClientId :: Text,
    -- | Authorization code received from Keycloak
    teCode :: Text,
    -- | Redirect URI (must match the one used in authorization)
    teRedirectUri :: Text,
    -- | PKCE code verifier (the original verifier, not the challenge)
    teCodeVerifier :: Text
  }
  deriving (Eq, Show, Generic)

-- | Token response from Keycloak
data TokenResponse = TokenResponse
  { -- | The access token
    trAccessToken :: Text,
    -- | Optional refresh token
    trRefreshToken :: Maybe Text,
    -- | Token expiration time in seconds
    trExpiresIn :: Int,
    -- | Token type (usually "Bearer")
    trTokenType :: Text,
    -- | Scopes granted
    trScope :: Maybe Text,
    -- | ID token (if openid scope requested)
    trIdToken :: Maybe Text
  }
  deriving (Eq, Show, Generic)

instance ToJSON TokenResponse where
  toJSON tr =
    object
      [ "access_token" .= trAccessToken tr,
        "refresh_token" .= trRefreshToken tr,
        "expires_in" .= trExpiresIn tr,
        "token_type" .= trTokenType tr,
        "scope" .= trScope tr,
        "id_token" .= trIdToken tr
      ]

instance FromJSON TokenResponse where
  parseJSON = withObject "TokenResponse" $ \obj ->
    TokenResponse
      <$> obj .: "access_token"
      <*> obj .:? "refresh_token"
      <*> obj .: "expires_in"
      <*> obj .: "token_type"
      <*> obj .:? "scope"
      <*> obj .:? "id_token"

-- | PKCE-related errors
data PKCEError
  = -- | HTTP request to token endpoint failed
    TokenRequestFailed Int Text
  | -- | Failed to parse token response
    TokenResponseParseError Text
  | -- | Token endpoint returned an error
    TokenEndpointError Text Text -- error, error_description
  | -- | Network or connection error
    NetworkError Text
  deriving (Eq, Show, Generic)

instance ToJSON PKCEError where
  toJSON err =
    object
      [ "error" .= pkceErrorCode err,
        "message" .= pkceErrorToText err
      ]

-- | Convert PKCE error to human-readable text
pkceErrorToText :: PKCEError -> Text
pkceErrorToText (TokenRequestFailed status msg) =
  "Token request failed with status " <> T.pack (show status) <> ": " <> msg
pkceErrorToText (TokenResponseParseError msg) =
  "Failed to parse token response: " <> msg
pkceErrorToText (TokenEndpointError err desc) =
  "Token endpoint error: " <> err <> " - " <> desc
pkceErrorToText (NetworkError msg) =
  "Network error: " <> msg

-- | Get error code for PKCE error
pkceErrorCode :: PKCEError -> Text
pkceErrorCode (TokenRequestFailed _ _) = "token_request_failed"
pkceErrorCode (TokenResponseParseError _) = "token_parse_error"
pkceErrorCode (TokenEndpointError _ _) = "token_endpoint_error"
pkceErrorCode (NetworkError _) = "network_error"

-- | Exchange authorization code for tokens using PKCE (public client)
exchangeCodeForTokens ::
  KeycloakConfig ->
  Manager ->
  TokenExchangeParams ->
  IO (Either PKCEError TokenResponse)
exchangeCodeForTokens kc manager params = do
  let endpoint = T.unpack $ tokenEndpoint kc
      body =
        TE.encodeUtf8 $
          T.intercalate
            "&"
            [ "grant_type=authorization_code",
              "client_id=" <> urlEncode (teClientId params),
              "code=" <> urlEncode (teCode params),
              "redirect_uri=" <> urlEncode (teRedirectUri params),
              "code_verifier=" <> urlEncode (teCodeVerifier params)
            ]

  result <- tryRequest endpoint body
  case result of
    Left err -> pure $ Left err
    Right response -> parseTokenResponse response
  where
    tryRequest endpoint body = do
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
          response <- httpLbs request manager
          let status = statusCode $ responseStatus response
          if status >= 200 && status < 300
            then pure $ Right $ responseBody response
            else pure $ Left $ TokenRequestFailed status (TE.decodeUtf8 $ LBS.toStrict $ responseBody response)

    parseTokenResponse body =
      case decodeTokenResponse body of
        Just tr -> pure $ Right tr
        Nothing -> pure $ Left $ TokenResponseParseError "Invalid JSON response"

    decodeTokenResponse body =
      case eitherDecode body of
        Right tr -> Just tr
        Left _ -> Nothing

-- | Parameters for token refresh
data RefreshParams = RefreshParams
  { -- | Client ID
    rpClientId :: Text,
    -- | Refresh token
    rpRefreshToken :: Text,
    -- | Optional client secret (for confidential clients)
    rpClientSecret :: Maybe Text
  }
  deriving (Eq, Show, Generic)

-- | Refresh an access token using a refresh token
refreshAccessToken ::
  KeycloakConfig ->
  Manager ->
  RefreshParams ->
  IO (Either PKCEError TokenResponse)
refreshAccessToken kc manager params = do
  let endpoint = T.unpack $ tokenEndpoint kc
      baseBody =
        [ "grant_type=refresh_token",
          "client_id=" <> urlEncode (rpClientId params),
          "refresh_token=" <> urlEncode (rpRefreshToken params)
        ]
      bodyWithSecret = case rpClientSecret params of
        Just secret -> baseBody <> ["client_secret=" <> urlEncode secret]
        Nothing -> baseBody
      body = TE.encodeUtf8 $ T.intercalate "&" bodyWithSecret

  result <- tryRequest endpoint body
  case result of
    Left err -> pure $ Left err
    Right response -> parseTokenResponse response
  where
    tryRequest endpoint body = do
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
          response <- httpLbs request manager
          let status = statusCode $ responseStatus response
          if status >= 200 && status < 300
            then pure $ Right $ responseBody response
            else pure $ Left $ TokenRequestFailed status (TE.decodeUtf8 $ LBS.toStrict $ responseBody response)

    parseTokenResponse body =
      case eitherDecode body of
        Right tr -> pure $ Right tr
        Left err -> pure $ Left $ TokenResponseParseError (T.pack err)
