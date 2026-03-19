module StudioMCP.DAG.Parser
  ( decodeDagBytes,
    loadDagFile,
  )
where

import Data.ByteString (ByteString)
import qualified Data.ByteString as ByteString
import Data.Yaml (decodeEither')
import StudioMCP.DAG.Types (DagSpec)

decodeDagBytes :: ByteString -> Either String DagSpec
decodeDagBytes bytes =
  case decodeEither' bytes of
    Left err -> Left (show err)
    Right dagSpec -> Right dagSpec

loadDagFile :: FilePath -> IO (Either String DagSpec)
loadDagFile dagPath = decodeDagBytes <$> readFileBytes dagPath

readFileBytes :: FilePath -> IO ByteString
readFileBytes = ByteString.readFile
