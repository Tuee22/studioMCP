module StudioMCP.Result.Types
  ( Result (..),
    eitherToResult,
    resultToEither,
  )
where

data Result a f
  = Success a
  | Failure f
  deriving (Eq, Functor, Show)

eitherToResult :: Either f a -> Result a f
eitherToResult eitherValue =
  case eitherValue of
    Left err -> Failure err
    Right value -> Success value

resultToEither :: Result a f -> Either f a
resultToEither resultValue =
  case resultValue of
    Success value -> Right value
    Failure err -> Left err
