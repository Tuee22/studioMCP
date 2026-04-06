{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module StudioMCP.Auth.PKCE
  ( -- * Token Response
    TokenResponse (..),

    -- * Password Grant
    PasswordGrantParams (..),
    exchangePasswordForTokens,

    -- * Token Refresh
    RefreshParams (..),
    refreshAccessToken,

    -- * Errors
    PKCEError (..),
    pkceErrorToText,
  )
where

import Control.Exception (SomeException, try)
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
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import GHC.Generics (Generic)
import Network.HTTP.Client
  ( Manager,
    RequestBody (..),
    Response,
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

-- | Parameters for a username/password token exchange
data PasswordGrantParams = PasswordGrantParams
  { -- | Client ID
    pgClientId :: Text,
    -- | Username supplied by the caller
    pgUsername :: Text,
    -- | Password supplied by the caller
    pgPassword :: Text,
    -- | Requested scopes
    pgScopes :: [Text],
    -- | Optional client secret for confidential clients
    pgClientSecret :: Maybe Text
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

  result <- executeTokenRequest manager endpoint body
  case result of
    Left err -> pure $ Left err
    Right response -> parseTokenResponse response
  where
    parseTokenResponse body =
      case eitherDecode body of
        Right tr -> pure $ Right tr
        Left err -> pure $ Left $ TokenResponseParseError (T.pack err)

-- | Exchange username/password for tokens using direct access grants.
exchangePasswordForTokens ::
  KeycloakConfig ->
  Manager ->
  PasswordGrantParams ->
  IO (Either PKCEError TokenResponse)
exchangePasswordForTokens kc manager params = do
  let endpoint = T.unpack $ tokenEndpoint kc
      baseBody =
        [ "grant_type=password",
          "client_id=" <> urlEncode (pgClientId params),
          "username=" <> urlEncode (pgUsername params),
          "password=" <> urlEncode (pgPassword params)
        ]
      bodyWithScope =
        if null (pgScopes params)
          then baseBody
          else baseBody <> ["scope=" <> urlEncode (T.intercalate " " (pgScopes params))]
      bodyWithSecret =
        case pgClientSecret params of
          Just secret -> bodyWithScope <> ["client_secret=" <> urlEncode secret]
          Nothing -> bodyWithScope
      body = TE.encodeUtf8 $ T.intercalate "&" bodyWithSecret

  result <- executeTokenRequest manager endpoint body
  case result of
    Left err -> pure $ Left err
    Right response ->
      case eitherDecode response of
        Right tokenResponse -> pure $ Right tokenResponse
        Left err -> pure $ Left $ TokenResponseParseError (T.pack err)

-- | URL-encode a Text value for form data
urlEncode :: Text -> Text
urlEncode = T.concatMap encodeChar
  where
    encodeChar c
      | c >= 'a' && c <= 'z' = T.singleton c
      | c >= 'A' && c <= 'Z' = T.singleton c
      | c >= '0' && c <= '9' = T.singleton c
      | c == '-' || c == '_' || c == '.' || c == '~' = T.singleton c
      | otherwise = T.pack $ "%" ++ showHex (fromEnum c) ""
    showHex n s
      | n < 16 = '0' : showHexDigit n : s
      | otherwise = showHexDigit (n `div` 16) : showHexDigit (n `mod` 16) : s
    showHexDigit n
      | n < 10 = toEnum (fromEnum '0' + n)
      | otherwise = toEnum (fromEnum 'A' + n - 10)

executeTokenRequest ::
  Manager ->
  String ->
  BS.ByteString ->
  IO (Either PKCEError LBS.ByteString)
executeTokenRequest manager endpoint body = do
  responseOrException <-
    ( try $ do
        request <- parseRequest endpoint
        let tokenRequest =
              request
                { method = "POST",
                  requestBody = RequestBodyBS body,
                  requestHeaders =
                    [ ("Content-Type", "application/x-www-form-urlencoded")
                    ]
                }
        httpLbs tokenRequest manager
    ) :: IO (Either SomeException (Response LBS.ByteString))
  case responseOrException of
    Left (exn :: SomeException) ->
      pure $ Left $ NetworkError (T.pack (show exn))
    Right response ->
      let status = statusCode $ responseStatus response
       in if status >= 200 && status < 300
            then pure $ Right $ responseBody response
            else pure $ Left $ TokenRequestFailed status (TE.decodeUtf8 $ LBS.toStrict $ responseBody response)
