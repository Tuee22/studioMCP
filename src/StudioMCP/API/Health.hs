module StudioMCP.API.Health
  ( HealthStatus (..),
  )
where

data HealthStatus = Healthy | Degraded
  deriving (Eq, Show)
