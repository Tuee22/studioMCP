module StudioMCP.Config.Env
  ( RuntimeEnv (..),
    mkRuntimeEnv,
  )
where

import StudioMCP.Config.Load (loadAppConfig)
import StudioMCP.Config.Types (AppConfig)

newtype RuntimeEnv = RuntimeEnv
  { runtimeConfig :: AppConfig
  }
  deriving (Eq, Show)

mkRuntimeEnv :: IO RuntimeEnv
mkRuntimeEnv = RuntimeEnv <$> loadAppConfig
