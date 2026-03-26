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
  host <- lookupEnvText "STUDIOMCP_REDIS_HOST" "localhost"
  port <- lookupEnvInt "STUDIOMCP_REDIS_PORT" 6379
  password <- lookupEnvMaybe "STUDIOMCP_REDIS_PASSWORD"
  database <- lookupEnvInt "STUDIOMCP_REDIS_DATABASE" 0
  poolSize <- lookupEnvInt "STUDIOMCP_REDIS_POOL_SIZE" 10
  timeout <- lookupEnvInt "STUDIOMCP_REDIS_TIMEOUT" 5
  sessionTtl <- lookupEnvInt "STUDIOMCP_SESSION_TTL" 1800
  lockTtl <- lookupEnvInt "STUDIOMCP_LOCK_TTL" 30
  keyPrefix <- lookupEnvText "STUDIOMCP_REDIS_KEY_PREFIX" "mcp:"
  useTls <- lookupEnvBool "STUDIOMCP_REDIS_TLS" False

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
