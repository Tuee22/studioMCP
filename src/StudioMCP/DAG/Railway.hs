module StudioMCP.DAG.Railway
  ( bindResult,
    mapFailure,
  )
where

import StudioMCP.Result.Types (Result (Failure, Success))

bindResult :: (a -> Result b f) -> Result a f -> Result b f
bindResult next resultValue =
  case resultValue of
    Success value -> next value
    Failure err -> Failure err

mapFailure :: (f -> g) -> Result a f -> Result a g
mapFailure toFailure resultValue =
  case resultValue of
    Success value -> Success value
    Failure err -> Failure (toFailure err)
