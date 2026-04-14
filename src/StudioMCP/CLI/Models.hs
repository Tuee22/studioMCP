module StudioMCP.CLI.Models
  ( runModelsCommand,
  )
where

import Control.Monad (forM_)
import StudioMCP.CLI.Command (ModelsCommand (..))
import StudioMCP.Config.Load (loadAppConfig)
import StudioMCP.Config.Types (AppConfig (..))
import qualified StudioMCP.Config.Types as ConfigTypes
import StudioMCP.Models.Registry (ModelArtifact (..))
import StudioMCP.Models.Sync
  ( ModelSyncResult (..),
    listModelStatuses,
    syncAllModels,
    verifyAllModels,
  )
import StudioMCP.Storage.MinIO (MinIOConfig (..))
import System.Exit (die)

runModelsCommand :: ModelsCommand -> IO ()
runModelsCommand command = do
  appConfig <- loadAppConfig
  let minioConfig = appConfigMinioConfig appConfig
  case command of
    ModelsSyncCommand ->
      syncAllModels minioConfig >>= either (die . show) (\results -> renderResults results "Model sync completed.")
    ModelsListCommand ->
      listModelStatuses minioConfig >>= either (die . show) (\results -> renderResults results "Model status listing completed.")
    ModelsVerifyCommand ->
      verifyAllModels minioConfig >>= either (die . show) (\results -> renderResults results "Model verification completed.")

appConfigMinioConfig :: AppConfig -> MinIOConfig
appConfigMinioConfig appConfig =
  MinIOConfig
    (minioEndpoint appConfig)
    (ConfigTypes.minioAccessKey appConfig)
    (ConfigTypes.minioSecretKey appConfig)

renderResults :: [ModelSyncResult] -> String -> IO ()
renderResults results footer = do
  forM_ results $ \result ->
    putStrLn $
      unwords
        [ show (modelId (msrModel result)),
          show (msrStatus result),
          show (msrChecksum result)
        ]
  putStrLn footer
