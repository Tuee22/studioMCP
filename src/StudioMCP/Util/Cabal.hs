module StudioMCP.Util.Cabal
  ( cabalBuildDir,
    ensureCabalBootstrap,
  )
where

import Control.Monad (unless)
import System.Directory (createDirectoryIfMissing, doesFileExist, withCurrentDirectory)
import System.FilePath ((</>))
import System.Process (callProcess)

cabalBuildDir :: FilePath
cabalBuildDir = "/opt/build/studiomcp"

ensureCabalBootstrap :: IO ()
ensureCabalBootstrap = do
  createDirectoryIfMissing True cabalConfigDir
  createDirectoryIfMissing True cabalPackagesDir
  createDirectoryIfMissing True cabalStoreDir
  writeFile cabalConfigPath cabalConfigContents
  hasPackageIndex <- or <$> mapM doesFileExist cabalPackageIndexPaths
  unless hasPackageIndex $
    withCurrentDirectory "/tmp" $
      callProcess "cabal" ["--builddir=" <> cabalBuildDir, "update"]

cabalConfigDir :: FilePath
cabalConfigDir = "/root/.config/cabal"

cabalCacheDir :: FilePath
cabalCacheDir = "/root/.cache/cabal"

cabalStateDir :: FilePath
cabalStateDir = "/root/.local/state/cabal"

cabalPackagesDir :: FilePath
cabalPackagesDir = cabalCacheDir </> "packages"

cabalStoreDir :: FilePath
cabalStoreDir = cabalStateDir </> "store"

cabalConfigPath :: FilePath
cabalConfigPath = cabalConfigDir </> "config"

cabalPackageIndexPaths :: [FilePath]
cabalPackageIndexPaths =
  let packageDir = cabalPackagesDir </> "hackage.haskell.org"
   in map (packageDir </>)
        [ "00-index.tar"
        , "00-index.cache"
        , "00-index.tar.gz"
        , "01-index.tar"
        , "01-index.cache"
        , "01-index.tar.gz"
        ]

cabalConfigContents :: String
cabalConfigContents =
  unlines
    [ "repository hackage.haskell.org"
    , "  url: http://hackage.fpcomplete.com/"
    , "  secure: False"
    , "remote-repo-cache: /root/.cache/cabal/packages"
    , "world-file: /root/.local/state/cabal/world"
    , "store-dir: /root/.local/state/cabal/store"
    , "install-dirs user"
    , "  bindir: /root/.local/bin"
    ]
