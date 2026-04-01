{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.MCP.Session.RedisConfig
  ( -- * Redis Configuration
    RedisConfig (..),
    defaultRedisConfig,

    -- * Environment Loading
    loadRedisConfigFromEnv,

    -- * Key Helpers
    sessionKey,
    subscriptionKey,
    cursorKey,
    lockKey,

    -- * Key Prefixes
    redisKeyPrefix,
    sessionKeyPrefix,
    subscriptionKeyPrefix,
    cursorKeyPrefix,
    lockKeyPrefix,
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
import Data.Char (toLower)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)
import StudioMCP.MCP.Session.Types (SessionId (..))
import System.Environment (lookupEnv)

-- | Redis connection configuration
data RedisConfig = RedisConfig
  { -- | Redis host
    rcHost :: Text,
    -- | Redis port
    rcPort :: Int,
    -- | Redis password (optional)
    rcPassword :: Maybe Text,
    -- | Redis database number
    rcDatabase :: Int,
    -- | Connection pool size
    rcPoolSize :: Int,
    -- | Connection timeout in seconds
    rcConnectionTimeout :: Int,
    -- | Session TTL in seconds
    rcSessionTtl :: Int,
    -- | Lock TTL in seconds
    rcLockTtl :: Int,
    -- | Key prefix for namespacing
    rcKeyPrefix :: Text,
    -- | Use TLS
    rcUseTls :: Bool
  }
  deriving (Eq, Show, Generic)

instance ToJSON RedisConfig where
  toJSON rc =
    object
      [ "host" .= rcHost rc,
        "port" .= rcPort rc,
        "database" .= rcDatabase rc,
        "poolSize" .= rcPoolSize rc,
        "connectionTimeout" .= rcConnectionTimeout rc,
        "sessionTtl" .= rcSessionTtl rc,
        "lockTtl" .= rcLockTtl rc,
        "keyPrefix" .= rcKeyPrefix rc,
        "useTls" .= rcUseTls rc
        -- Note: password intentionally not serialized
      ]

instance FromJSON RedisConfig where
  parseJSON = withObject "RedisConfig" $ \obj ->
    RedisConfig
      <$> obj .: "host"
      <*> obj .: "port"
      <*> obj .:? "password"
      <*> obj .: "database"
      <*> obj .: "poolSize"
      <*> obj .: "connectionTimeout"
      <*> obj .: "sessionTtl"
      <*> obj .: "lockTtl"
      <*> obj .: "keyPrefix"
      <*> obj .: "useTls"

-- | Default Redis configuration for development
defaultRedisConfig :: RedisConfig
defaultRedisConfig =
  RedisConfig
    { rcHost = "localhost",
      rcPort = 6379,
      rcPassword = Nothing,
      rcDatabase = 0,
      rcPoolSize = 10,
      rcConnectionTimeout = 5,
      rcSessionTtl = 1800, -- 30 minutes
      rcLockTtl = 30, -- 30 seconds
      rcKeyPrefix = "mcp:",
      rcUseTls = False
    }

-- | Load Redis configuration from environment variables
loadRedisConfigFromEnv :: IO RedisConfig
loadRedisConfigFromEnv = do
  redisUrl <- lookupEnvMaybeAny ["STUDIO_MCP_REDIS_URL", "STUDIOMCP_REDIS_URL"]
  let urlConfig = maybe defaultRedisConfig applyRedisUrlConfig redisUrl

  host <- lookupEnvTextAny ["STUDIO_MCP_REDIS_HOST", "STUDIOMCP_REDIS_HOST"] (rcHost urlConfig)
  port <- lookupEnvIntAny ["STUDIO_MCP_REDIS_PORT", "STUDIOMCP_REDIS_PORT"] (rcPort urlConfig)
  explicitPassword <- lookupEnvMaybeAny ["STUDIO_MCP_REDIS_PASSWORD", "STUDIOMCP_REDIS_PASSWORD"]
  database <- lookupEnvIntAny ["STUDIO_MCP_REDIS_DATABASE", "STUDIOMCP_REDIS_DATABASE"] (rcDatabase urlConfig)
  poolSize <- lookupEnvIntAny ["STUDIO_MCP_REDIS_POOL_SIZE", "STUDIOMCP_REDIS_POOL_SIZE"] (rcPoolSize defaultRedisConfig)
  timeout <- lookupEnvIntAny ["STUDIO_MCP_REDIS_TIMEOUT", "STUDIOMCP_REDIS_TIMEOUT"] (rcConnectionTimeout defaultRedisConfig)
  sessionTtl <- lookupEnvIntAny ["STUDIO_MCP_SESSION_TTL", "STUDIOMCP_SESSION_TTL"] (rcSessionTtl defaultRedisConfig)
  lockTtl <- lookupEnvIntAny ["STUDIO_MCP_LOCK_TTL", "STUDIOMCP_LOCK_TTL"] (rcLockTtl defaultRedisConfig)
  keyPrefix <- lookupEnvTextAny ["STUDIO_MCP_REDIS_KEY_PREFIX", "STUDIOMCP_REDIS_KEY_PREFIX"] (rcKeyPrefix defaultRedisConfig)
  useTls <- lookupEnvBoolAny ["STUDIO_MCP_REDIS_TLS", "STUDIOMCP_REDIS_TLS"] (rcUseTls urlConfig)
  let password = case explicitPassword of
        Just value -> Just value
        Nothing -> rcPassword urlConfig

  pure
    RedisConfig
      { rcHost = host,
        rcPort = port,
        rcPassword = password,
        rcDatabase = database,
        rcPoolSize = poolSize,
        rcConnectionTimeout = timeout,
        rcSessionTtl = sessionTtl,
        rcLockTtl = lockTtl,
        rcKeyPrefix = keyPrefix,
        rcUseTls = useTls
      }

-- | Helper to lookup text env var with default
lookupEnvAny :: [String] -> IO (Maybe String)
lookupEnvAny [] = pure Nothing
lookupEnvAny (name : remaining) = do
  value <- lookupEnv name
  case value of
    Just _ -> pure value
    Nothing -> lookupEnvAny remaining

-- | Helper to lookup text env var with default
lookupEnvTextAny :: [String] -> Text -> IO Text
lookupEnvTextAny names def = maybe def T.pack <$> lookupEnvAny names

-- | Helper to lookup optional text env var
lookupEnvMaybeAny :: [String] -> IO (Maybe Text)
lookupEnvMaybeAny names = fmap T.pack <$> lookupEnvAny names

-- | Helper to lookup int env var with default
lookupEnvIntAny :: [String] -> Int -> IO Int
lookupEnvIntAny names def = do
  mVal <- lookupEnvAny names
  pure $ case mVal of
    Just s -> maybe def id (readMaybe s)
    Nothing -> def
  where
    readMaybe s = case reads s of
      [(v, "")] -> Just v
      _ -> Nothing

-- | Helper to lookup bool env var with default
lookupEnvBoolAny :: [String] -> Bool -> IO Bool
lookupEnvBoolAny names def = do
  mVal <- lookupEnvAny names
  pure $ case mVal of
    Just rawValue ->
      case map toLower rawValue of
        "true" -> True
        "1" -> True
        "false" -> False
        "0" -> False
        _ -> def
    Nothing -> def

applyRedisUrlConfig :: Text -> RedisConfig
applyRedisUrlConfig redisUrl =
  case parseRedisUrl redisUrl of
    Left err -> error ("Invalid Redis URL in environment: " <> err)
    Right parsed ->
      defaultRedisConfig
        { rcHost = rucHost parsed,
          rcPort = rucPort parsed,
          rcPassword = rucPassword parsed,
          rcDatabase = rucDatabase parsed,
          rcUseTls = rucUseTls parsed
        }

data RedisUrlConfig = RedisUrlConfig
  { rucHost :: Text,
    rucPort :: Int,
    rucPassword :: Maybe Text,
    rucDatabase :: Int,
    rucUseTls :: Bool
  }

parseRedisUrl :: Text -> Either String RedisUrlConfig
parseRedisUrl redisUrl = do
  (useTls, remainder) <- parseScheme redisUrl
  let (authority, pathAndQuery) = T.breakOn "/" remainder
  (host, port, password) <- parseAuthority authority
  database <- parseDatabase pathAndQuery
  pure
    RedisUrlConfig
      { rucHost = host,
        rucPort = port,
        rucPassword = password,
        rucDatabase = database,
        rucUseTls = useTls
      }
  where
    parseScheme url
      | "redis://" `T.isPrefixOf` url = Right (False, T.drop 8 url)
      | "rediss://" `T.isPrefixOf` url = Right (True, T.drop 9 url)
      | otherwise = Left "expected redis:// or rediss:// scheme"

parseAuthority :: Text -> Either String (Text, Int, Maybe Text)
parseAuthority authority
  | T.null authority = Left "missing Redis host"
  | otherwise = do
      let (authPart, hostPort) =
            case T.breakOnEnd "@" authority of
              ("", _) -> (Nothing, authority)
              (prefix, remainder) -> (Just (T.dropEnd 1 prefix), remainder)
      password <- pure (extractPassword =<< authPart)
      (host, port) <- parseHostPort hostPort
      pure (host, port, password)

parseHostPort :: Text -> Either String (Text, Int)
parseHostPort hostPort
  | T.null hostPort = Left "missing Redis host"
  | "[" `T.isPrefixOf` hostPort = parseIpv6HostPort hostPort
  | otherwise =
      case T.breakOnEnd ":" hostPort of
        ("", _) -> Right (hostPort, 6379)
        (prefix, portText) ->
          if T.null portText
            then Left "missing Redis port"
            else do
              let host = T.dropEnd 1 prefix
              if T.null host
                then Left "missing Redis host"
                else pure ()
              port <- readIntText "port" portText
              pure (host, port)

parseIpv6HostPort :: Text -> Either String (Text, Int)
parseIpv6HostPort hostPort = do
  let withoutOpenBracket = T.drop 1 hostPort
      (hostPart, remainder) = T.breakOn "]" withoutOpenBracket
  if T.null remainder
    then Left "unterminated IPv6 Redis host"
    else do
      let host = "[" <> hostPart <> "]"
          portSuffix = T.drop 1 remainder
      if T.null host
        then Left "missing Redis host"
        else
          case portSuffix of
            "" -> Right (host, 6379)
            _ ->
              if ":" `T.isPrefixOf` portSuffix
                then do
                  port <- readIntText "port" (T.drop 1 portSuffix)
                  pure (host, port)
                else Left "invalid IPv6 Redis host format"

parseDatabase :: Text -> Either String Int
parseDatabase pathAndQuery =
  case T.stripPrefix "/" pathAndQuery of
    Nothing -> Right 0
    Just pathText ->
      let dbText = T.takeWhile (/= '?') pathText
       in if T.null dbText
            then Right 0
            else readIntText "database" dbText

extractPassword :: Text -> Maybe Text
extractPassword authPart
  | T.null authPart = Nothing
  | otherwise =
      case T.breakOn ":" authPart of
        ("", suffix) | not (T.null suffix) -> Just (T.drop 1 suffix)
        (username, "") -> Just username
        (_, suffix) -> Just (T.drop 1 suffix)

readIntText :: String -> Text -> Either String Int
readIntText fieldName rawValue =
  case reads (T.unpack rawValue) of
    [(value, "")] -> Right value
    _ -> Left ("invalid Redis " <> fieldName <> ": " <> T.unpack rawValue)

-- | Key prefix for MCP sessions
redisKeyPrefix :: RedisConfig -> Text
redisKeyPrefix = rcKeyPrefix

-- | Session key prefix
sessionKeyPrefix :: RedisConfig -> Text
sessionKeyPrefix config = rcKeyPrefix config <> "session:"

-- | Subscription key prefix
subscriptionKeyPrefix :: RedisConfig -> Text
subscriptionKeyPrefix config = rcKeyPrefix config <> "sub:"

-- | Cursor key prefix
cursorKeyPrefix :: RedisConfig -> Text
cursorKeyPrefix config = rcKeyPrefix config <> "cursor:"

-- | Lock key prefix
lockKeyPrefix :: RedisConfig -> Text
lockKeyPrefix config = rcKeyPrefix config <> "lock:"

-- | Build session key
sessionKey :: RedisConfig -> SessionId -> Text
sessionKey config (SessionId sid) = sessionKeyPrefix config <> sid

-- | Build subscription key
subscriptionKey :: RedisConfig -> SessionId -> Text -> Text
subscriptionKey config (SessionId sid) resourceUri =
  subscriptionKeyPrefix config <> sid <> ":" <> resourceUri

-- | Build cursor key
cursorKey :: RedisConfig -> SessionId -> Text -> Text
cursorKey config (SessionId sid) streamName =
  cursorKeyPrefix config <> sid <> ":" <> streamName

-- | Build lock key
lockKey :: RedisConfig -> SessionId -> Text
lockKey config (SessionId sid) = lockKeyPrefix config <> "session:" <> sid
