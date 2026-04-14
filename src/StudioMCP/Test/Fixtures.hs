{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Test.Fixtures
  ( FixtureArtifact (..),
    allFixtureArtifacts,
    fixturesBucket,
    generateAllLocalFixtures,
    lookupFixtureArtifact,
    resolveLocalFixturePath,
    seedFixturesToMinio,
    verifyFixturesInMinio,
  )
where

import Control.Monad (forM)
import Crypto.Hash (Digest, SHA256, hashlazy)
import Data.Bits ((.|.), shiftR, (.&.))
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.List (find)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import StudioMCP.Result.Failure
  ( FailureCategory (StorageFailure, ToolProcessFailure),
    FailureDetail (..),
  )
import StudioMCP.Storage.Keys (BucketName (..), ObjectKey (..))
import StudioMCP.Storage.MinIO
  ( MinIOConfig,
    ensureBucketExists,
    readObjectBytes,
    writeObjectBytes,
  )
import StudioMCP.Tools.Boundary
  ( BoundaryCommand (..),
    runBoundaryCommand,
  )
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath (takeDirectory, (</>))

data FixtureArtifact = FixtureArtifact
  { fixtureId :: Text,
    fixtureDescription :: Text,
    fixtureObjectKey :: ObjectKey,
    fixtureRelativePath :: FilePath
  }
  deriving (Eq, Show)

fixturesBucket :: BucketName
fixturesBucket = BucketName "studiomcp-test-fixtures"

allFixtureArtifacts :: [FixtureArtifact]
allFixtureArtifacts =
  [ FixtureArtifact "tone-440hz-1s" "Single-tone WAV fixture." (ObjectKey "audio/tone-440hz-1s.wav") "audio/tone-440hz-1s.wav",
    FixtureArtifact "speech-sample-10s" "Deterministic speech-like WAV fixture." (ObjectKey "audio/speech-sample-10s.wav") "audio/speech-sample-10s.wav",
    FixtureArtifact "music-stems-30s" "Deterministic multi-tone WAV fixture." (ObjectKey "audio/music-stems-30s.wav") "audio/music-stems-30s.wav",
    FixtureArtifact "simple-melody" "Short MIDI melody fixture." (ObjectKey "midi/simple-melody.mid") "midi/simple-melody.mid",
    FixtureArtifact "chord-progression" "Short MIDI chord progression fixture." (ObjectKey "midi/chord-progression.mid") "midi/chord-progression.mid",
    FixtureArtifact "test-pattern-1080p" "1080p PNG test pattern." (ObjectKey "image/test-pattern-1080p.png") "image/test-pattern-1080p.png",
    FixtureArtifact "photo-sample" "JPEG photo-style sample derived from the PNG test pattern." (ObjectKey "image/photo-sample.jpg") "image/photo-sample.jpg",
    FixtureArtifact "test-video-10s" "10 second MP4 video fixture." (ObjectKey "video/test-video-10s.mp4") "video/test-video-10s.mp4"
  ]

lookupFixtureArtifact :: Text -> Maybe FixtureArtifact
lookupFixtureArtifact requestedId =
  find ((== Text.toLower requestedId) . Text.toLower . fixtureId) allFixtureArtifacts

resolveLocalFixturePath :: FilePath -> FixtureArtifact -> FilePath
resolveLocalFixturePath fixturesRoot fixtureArtifact =
  fixturesRoot </> fixtureRelativePath fixtureArtifact

generateAllLocalFixtures :: FilePath -> IO (Either FailureDetail [FilePath])
generateAllLocalFixtures fixturesRoot = do
  createDirectoryIfMissing True fixturesRoot
  generatedPaths <- forM allFixtureArtifacts (generateFixtureIfMissing fixturesRoot)
  pure (sequence generatedPaths)

seedFixturesToMinio :: MinIOConfig -> FilePath -> IO (Either FailureDetail [Text])
seedFixturesToMinio config fixturesRoot = do
  ensureBucketResult <- ensureBucketExists config fixturesBucket
  case ensureBucketResult of
    Left failureDetail -> pure (Left failureDetail)
    Right () -> do
      localFixturesResult <- generateAllLocalFixtures fixturesRoot
      case localFixturesResult of
        Left failureDetail -> pure (Left failureDetail)
        Right _ -> sequence <$> forM allFixtureArtifacts (uploadFixture config fixturesRoot)

verifyFixturesInMinio :: MinIOConfig -> FilePath -> IO (Either FailureDetail [Text])
verifyFixturesInMinio config fixturesRoot = do
  localFixturesResult <- generateAllLocalFixtures fixturesRoot
  case localFixturesResult of
    Left failureDetail -> pure (Left failureDetail)
    Right _ -> sequence <$> forM allFixtureArtifacts (verifyFixture config fixturesRoot)

generateFixtureIfMissing :: FilePath -> FixtureArtifact -> IO (Either FailureDetail FilePath)
generateFixtureIfMissing fixturesRoot fixtureArtifact = do
  let outputPath = resolveLocalFixturePath fixturesRoot fixtureArtifact
  createDirectoryIfMissing True (takeDirectory outputPath)
  outputExists <- doesFileExist outputPath
  if outputExists
    then pure (Right outputPath)
    else
      case fixtureId fixtureArtifact of
        "tone-440hz-1s" -> generateFfmpegFixture outputPath ["-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=1", "-c:a", "pcm_s16le", outputPath]
        "speech-sample-10s" -> generateFfmpegFixture outputPath ["-f", "lavfi", "-i", "aevalsrc=0.5*sin(2*PI*220*t)+0.25*sin(2*PI*330*t)+0.15*sin(2*PI*440*t):d=10:s=16000", "-c:a", "pcm_s16le", outputPath]
        "music-stems-30s" -> generateFfmpegFixture outputPath ["-f", "lavfi", "-i", "aevalsrc=0.4*sin(2*PI*110*t)+0.35*sin(2*PI*220*t)+0.2*sin(2*PI*330*t):d=30:s=44100", "-c:a", "pcm_s16le", outputPath]
        "simple-melody" -> writeBytesFixture outputPath (simpleMidiFile [60, 62, 64, 67, 72])
        "chord-progression" -> writeBytesFixture outputPath (simpleMidiFile [48, 55, 60, 53, 57, 60, 55, 59, 62, 48, 55, 60])
        "test-pattern-1080p" ->
          generateBoundaryFixture
            "convert"
            outputPath
            [ "-size",
              "1920x1080",
              "xc:#f4efe2",
              "-fill",
              "#1d3557",
              "-draw",
              "rectangle 120,120 1800,960",
              "-fill",
              "#e63946",
              "-draw",
              "circle 960,540 960,300",
              "-fill",
              "#f1fa8c",
              "-draw",
              "rectangle 240,240 600,840",
              outputPath
            ]
        "photo-sample" -> do
          pngResult <- generateFixtureIfMissing fixturesRoot (fixtureByIdUnsafe "test-pattern-1080p")
          case pngResult of
            Left failureDetail -> pure (Left failureDetail)
            Right pngPath ->
              generateBoundaryFixture "convert" outputPath [pngPath, "-quality", "92", outputPath]
        "test-video-10s" ->
          generateFfmpegFixture
            outputPath
            [ "-f",
              "lavfi",
              "-i",
              "testsrc=duration=10:size=1280x720:rate=30",
              "-f",
              "lavfi",
              "-i",
              "sine=frequency=440:sample_rate=48000:duration=10",
              "-shortest",
              "-c:v",
              "libx264",
              "-pix_fmt",
              "yuv420p",
              "-c:a",
              "aac",
              outputPath
            ]
        _ ->
          pure
            ( Left
                FailureDetail
                  { failureCategory = ToolProcessFailure,
                    failureCode = "fixture-generator-missing",
                    failureMessage = "No generator is defined for the requested fixture.",
                    failureRetryable = False,
                    failureContext = Map.fromList [("fixtureId", fixtureId fixtureArtifact)]
                  }
            )

uploadFixture :: MinIOConfig -> FilePath -> FixtureArtifact -> IO (Either FailureDetail Text)
uploadFixture config fixturesRoot fixtureArtifact = do
  let localPath = resolveLocalFixturePath fixturesRoot fixtureArtifact
  fileBytes <- LBS.readFile localPath
  writeResult <- writeObjectBytes config fixturesBucket (fixtureObjectKey fixtureArtifact) fileBytes
  pure $
    case writeResult of
      Left failureDetail -> Left failureDetail
      Right () -> Right (fixtureId fixtureArtifact)

verifyFixture :: MinIOConfig -> FilePath -> FixtureArtifact -> IO (Either FailureDetail Text)
verifyFixture config fixturesRoot fixtureArtifact = do
  let localPath = resolveLocalFixturePath fixturesRoot fixtureArtifact
  localBytes <- LBS.readFile localPath
  remoteBytesResult <- readObjectBytes config fixturesBucket (fixtureObjectKey fixtureArtifact)
  pure $
    case remoteBytesResult of
      Left failureDetail -> Left failureDetail
      Right remoteBytes
        | sha256Bytes localBytes /= sha256Bytes remoteBytes ->
            Left
              FailureDetail
                { failureCategory = StorageFailure,
                  failureCode = "fixture-checksum-mismatch",
                  failureMessage = "The fixture stored in MinIO does not match the deterministic local fixture.",
                  failureRetryable = False,
                  failureContext =
                    Map.fromList
                      [ ("fixtureId", fixtureId fixtureArtifact),
                        ("objectKey", unObjectKey (fixtureObjectKey fixtureArtifact))
                      ]
                }
        | otherwise -> Right (fixtureId fixtureArtifact)

generateFfmpegFixture :: FilePath -> [String] -> IO (Either FailureDetail FilePath)
generateFfmpegFixture outputPath ffmpegArgs =
  generateBoundaryFixture "ffmpeg" outputPath (["-y", "-hide_banner", "-loglevel", "error"] <> ffmpegArgs)

generateBoundaryFixture :: FilePath -> FilePath -> [String] -> IO (Either FailureDetail FilePath)
generateBoundaryFixture executable outputPath arguments = do
  boundaryResult <-
    runBoundaryCommand
      BoundaryCommand
        { boundaryExecutable = executable,
          boundaryArguments = arguments,
          boundaryStdin = "",
          boundaryTimeoutSeconds = 30
        }
  case boundaryResult of
    Left failureDetail -> pure (Left failureDetail)
    Right _ -> pure (Right outputPath)

writeBytesFixture :: FilePath -> LBS.ByteString -> IO (Either FailureDetail FilePath)
writeBytesFixture outputPath payload = do
  LBS.writeFile outputPath payload
  pure (Right outputPath)

simpleMidiFile :: [Int] -> LBS.ByteString
simpleMidiFile notes =
  LBS.fromStrict $
    BS.concat
      [ "MThd",
        encodeWord32 6,
        encodeWord16 0,
        encodeWord16 1,
        encodeWord16 480,
        "MTrk",
        encodeWord32 (fromIntegral (BS.length trackData)),
        trackData
      ]
  where
    trackData =
      BS.concat
        ( concatMap noteEvents notes
            <> [BS.pack [0x00, 0xFF, 0x2F, 0x00]]
        )

    noteEvents pitch =
      [ BS.pack [0x00, 0x90, fromIntegral pitch, 0x64],
        encodeVarLen 240 <> BS.pack [0x80, fromIntegral pitch, 0x40]
      ]

encodeWord16 :: Int -> BS.ByteString
encodeWord16 value =
  BS.pack [fromIntegral (value `shiftR` 8), fromIntegral value]

encodeWord32 :: Int -> BS.ByteString
encodeWord32 value =
  BS.pack
    [ fromIntegral (value `shiftR` 24),
      fromIntegral (value `shiftR` 16),
      fromIntegral (value `shiftR` 8),
      fromIntegral value
    ]

encodeVarLen :: Int -> BS.ByteString
encodeVarLen value =
  BS.pack (reverse (go value))
  where
    go n =
      let current = n .&. 0x7F
          rest = n `shiftR` 7
       in if rest == 0
            then [fromIntegral current]
            else fromIntegral (current .|. 0x80) : go rest

fixtureByIdUnsafe :: Text -> FixtureArtifact
fixtureByIdUnsafe requestedId =
  case lookupFixtureArtifact requestedId of
    Just fixtureArtifact -> fixtureArtifact
    Nothing -> error ("Unknown fixture id: " <> Text.unpack requestedId)

sha256Bytes :: LBS.ByteString -> Text
sha256Bytes =
  TextEncoding.decodeUtf8
    . convertToBase Base16
    . (id :: Digest SHA256 -> Digest SHA256)
    . hashlazy
