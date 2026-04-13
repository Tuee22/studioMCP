{-# LANGUAGE OverloadedStrings #-}

module Auth.JwksSpec (spec) where

import Data.Aeson (decode, encode, Value(..))
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Text as T
import Data.Time (UTCTime, addUTCTime, diffUTCTime, getCurrentTime)
import qualified Data.Vector as V
import StudioMCP.Auth.Config (defaultAuthConfig, defaultKeycloakConfig)
import StudioMCP.Auth.Jwks
import StudioMCP.Auth.Types
import Test.Hspec

spec :: Spec
spec = do
  describe "Jwk" $ do
    it "serializes RSA key to JSON" $ do
      let jwk = Jwk
            { jwkKty = "RSA"
            , jwkUse = Just "sig"
            , jwkKid = Just "test-key-1"
            , jwkAlg = Just "RS256"
            , jwkN = Just "0vx7agoebGcQSuuPiLJXZptN9nndrQmbXEps2aiAFbWhM78LhWx4cbbfAAtVT86zwu1RK7aPFFxuhDR1L6tSoc_BJECPebWKRXjBZCiFV4n3oknjhMstn64tZ_2W-5JsGY4Hc5n9yBXArwl93lqt7_RN5w6Cf0h4QyQ5v-65YGjQR0_FDW2QvzqY368QQMicAtaSqzs8KJZgnYb9c7d0zgdAZHzu6qMQvRL5hajrn1n91CbOpbISD08qNLyrdkt-bFTWhAI4vMQFh6WeZu0fM4lFd2NcRwr3XPksINHaQ-G_xBniIqbw0Ls1jF44-csFCur-kEgU8awapJzKnqDKgw"
            , jwkE = Just "AQAB"
            , jwkX = Nothing
            , jwkY = Nothing
            , jwkCrv = Nothing
            }
      let json = encode jwk
      (decode json :: Maybe Jwk) `shouldBe` Just jwk

    it "serializes EC key to JSON" $ do
      let jwk = Jwk
            { jwkKty = "EC"
            , jwkUse = Just "sig"
            , jwkKid = Just "test-ec-key"
            , jwkAlg = Just "ES256"
            , jwkN = Nothing
            , jwkE = Nothing
            , jwkX = Just "f83OJ3D2xF1Bg8vub9tLe1gHMzV76e8Tus9uPHvRVEU"
            , jwkY = Just "x_FEzRu9m36HLN_tue659LNpXW6pCyStikYjKIWI5a0"
            , jwkCrv = Just "P-256"
            }
      let json = encode jwk
      (decode json :: Maybe Jwk) `shouldBe` Just jwk

  describe "JwkSet" $ do
    it "serializes key set to JSON" $ do
      let jwks = JwkSet
            { jwksKeys =
                [ Jwk "RSA" (Just "sig") (Just "key1") (Just "RS256") (Just "n") (Just "e") Nothing Nothing Nothing
                , Jwk "EC" (Just "sig") (Just "key2") (Just "ES256") Nothing Nothing (Just "x") (Just "y") (Just "P-256")
                ]
            }
      let json = encode jwks
      (decode json :: Maybe JwkSet) `shouldBe` Just jwks

    it "parses empty key set" $ do
      let jwks = JwkSet { jwksKeys = [] }
      let json = encode jwks
      (decode json :: Maybe JwkSet) `shouldBe` Just jwks

  describe "JwksCache" $ do
    it "creates a new cache" $ do
      cache <- newJwksCache defaultAuthConfig
      stale <- isCacheStale cache
      stale `shouldBe` True

    it "reports stale when no keys fetched" $ do
      cache <- newJwksCache defaultAuthConfig
      stale <- isCacheStale cache
      stale `shouldBe` True

  describe "parseJwt" $ do
    it "parses valid JWT structure" $ do
      -- Minimal JWT parts base64url encoded (without padding)
      -- Header: {"alg":"RS256","typ":"JWT"}
      -- Payload: {"iss":"http://localhost","sub":"test-user","aud":"app","exp":1999999999}
      -- Signature: fake
      let validJwt = RawJwt "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJodHRwOi8vbG9jYWxob3N0Iiwic3ViIjoidGVzdC11c2VyIiwiYXVkIjoiYXBwIiwiZXhwIjoxOTk5OTk5OTk5fQ.ZmFrZQ"
      case parseJwt validJwt of
        Left err -> expectationFailure $ "Failed to parse JWT: " ++ show err
        Right (header, payload, _sig) -> do
          jhAlg header `shouldBe` "RS256"
          jhTyp header `shouldBe` Just "JWT"
          jpIss payload `shouldBe` Just "http://localhost"
          jpSub payload `shouldBe` Just "test-user"

    it "rejects JWT with wrong number of parts" $ do
      let invalidJwt = RawJwt "part1.part2"
      case parseJwt invalidJwt of
        Left (InvalidTokenFormat _) -> pure ()
        Left err -> expectationFailure $ "Expected InvalidTokenFormat but got: " ++ show err
        Right _ -> expectationFailure "Expected failure but got success"

    it "rejects JWT with invalid base64" $ do
      let invalidJwt = RawJwt "!!!invalid!!!.!!!base64!!!.!!!"
      case parseJwt invalidJwt of
        Left (InvalidTokenFormat _) -> pure ()
        Left err -> expectationFailure $ "Expected InvalidTokenFormat but got: " ++ show err
        Right _ -> expectationFailure "Expected failure but got success"

  describe "validateTokenStructure" $ do
    it "accepts RS256 algorithm" $ do
      let header = JwtHeader { jhAlg = "RS256", jhTyp = Just "JWT", jhKid = Just "key1" }
      validateTokenStructure defaultAuthConfig header `shouldBe` Right ()

    it "accepts ES256 algorithm" $ do
      let header = JwtHeader { jhAlg = "ES256", jhTyp = Just "JWT", jhKid = Just "key1" }
      validateTokenStructure defaultAuthConfig header `shouldBe` Right ()

    it "rejects unsupported algorithm" $ do
      let header = JwtHeader { jhAlg = "HS256", jhTyp = Just "JWT", jhKid = Just "key1" }
      case validateTokenStructure defaultAuthConfig header of
        Left (InvalidTokenFormat msg) -> T.isInfixOf "Unsupported algorithm" msg `shouldBe` True
        Left err -> expectationFailure $ "Expected InvalidTokenFormat but got: " ++ show err
        Right () -> expectationFailure "Expected failure but got success"

  describe "validateTokenTiming" $ do
    it "accepts valid token with future expiration" $ do
      now <- getCurrentTime
      let future = addUTCTime 3600 now
          payload = testPayload { jpExp = Just (utcToPosix future) }
      validateTokenTiming defaultAuthConfig payload now `shouldBe` Right ()

    it "rejects expired token" $ do
      now <- getCurrentTime
      let past = addUTCTime (-3600) now
          payload = testPayload { jpExp = Just (utcToPosix past) }
      case validateTokenTiming defaultAuthConfig payload now of
        Left TokenExpired -> pure ()
        Left err -> expectationFailure $ "Expected TokenExpired but got: " ++ show err
        Right () -> expectationFailure "Expected failure but got success"

    it "rejects token without exp claim" $ do
      now <- getCurrentTime
      let payload = testPayload { jpExp = Nothing }
      case validateTokenTiming defaultAuthConfig payload now of
        Left (MissingClaim "exp") -> pure ()
        Left err -> expectationFailure $ "Expected MissingClaim exp but got: " ++ show err
        Right () -> expectationFailure "Expected failure but got success"

    it "accepts token with expiration far in the future" $ do
      now <- getCurrentTime
      -- Token will expire 1 hour in the future
      let future = addUTCTime 3600 now
          payload = testPayload { jpExp = Just (utcToPosix future) }
      validateTokenTiming defaultAuthConfig payload now `shouldBe` Right ()

  describe "validateTokenIssuer" $ do
    it "accepts matching issuer" $ do
      let payload = testPayload { jpIss = Just "http://localhost:8080/kc/realms/studiomcp" }
      validateTokenIssuer defaultKeycloakConfig payload `shouldBe` Right ()

    it "rejects mismatched issuer" $ do
      let payload = testPayload { jpIss = Just "http://evil.example.com/realms/fake" }
      case validateTokenIssuer defaultKeycloakConfig payload of
        Left (InvalidIssuer _) -> pure ()
        Left err -> expectationFailure $ "Expected InvalidIssuer but got: " ++ show err
        Right () -> expectationFailure "Expected failure but got success"

    it "rejects missing issuer" $ do
      let payload = testPayload { jpIss = Nothing }
      case validateTokenIssuer defaultKeycloakConfig payload of
        Left (MissingClaim "iss") -> pure ()
        Left err -> expectationFailure $ "Expected MissingClaim iss but got: " ++ show err
        Right () -> expectationFailure "Expected failure but got success"

  describe "validateTokenAudience" $ do
    it "accepts matching audience as string" $ do
      let payload = testPayload { jpAud = Just (String "studiomcp-mcp") }
      validateTokenAudience defaultKeycloakConfig payload `shouldBe` Right ()

    it "accepts matching audience in array" $ do
      let payload = testPayload { jpAud = Just (Array (V.fromList [String "other", String "studiomcp-mcp"])) }
      validateTokenAudience defaultKeycloakConfig payload `shouldBe` Right ()

    it "rejects mismatched audience" $ do
      let payload = testPayload { jpAud = Just (String "other-app") }
      case validateTokenAudience defaultKeycloakConfig payload of
        Left (InvalidAudience _) -> pure ()
        Left err -> expectationFailure $ "Expected InvalidAudience but got: " ++ show err
        Right () -> expectationFailure "Expected failure but got success"

    it "rejects missing audience" $ do
      let payload = testPayload { jpAud = Nothing }
      case validateTokenAudience defaultKeycloakConfig payload of
        Left (MissingClaim "aud") -> pure ()
        Left err -> expectationFailure $ "Expected MissingClaim aud but got: " ++ show err
        Right () -> expectationFailure "Expected failure but got success"

-- Helper function
utcToPosix :: UTCTime -> Integer
utcToPosix t = round (realToFrac (diffUTCTime t epoch) :: Double)
  where
    epoch = read "1970-01-01 00:00:00 UTC"

-- Test payload helper
testPayload :: JwtPayload
testPayload = JwtPayload
  { jpIss = Just "http://localhost:8080/kc/realms/studiomcp"
  , jpSub = Just "test-user"
  , jpAud = Just (String "studiomcp-mcp")
  , jpExp = Just 1735689600
  , jpNbf = Nothing
  , jpIat = Just 1735686000
  , jpAzp = Just "studiomcp-cli"
  , jpTenantId = Just "test-tenant"
  , jpScope = Just "openid profile workflow:read"
  , jpRealmAccess = Nothing
  , jpResourceAccess = Nothing
  , jpEmail = Just "test@example.com"
  , jpEmailVerified = Just True
  , jpName = Just "Test User"
  , jpRaw = Object KM.empty
  }
