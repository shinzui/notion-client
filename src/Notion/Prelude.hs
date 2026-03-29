module Notion.Prelude
  ( -- * JSON
    aesonOptions,
    stripPrefix,
    labelModifier,
    parseISO8601,
    posixToISO8601,

    -- * Re-exports
    module Data.Aeson,
    module Data.ByteString.Lazy,
    module Data.List.NonEmpty,
    module Data.Map,
    module Data.String,
    module Data.Text,
    module Data.Time.Clock.POSIX,
    module Data.Vector,
    module Data.Void,
    module Data.Word,
    module GHC.Generics,
    module Numeric.Natural,
    module Servant.API,
    module Servant.Multipart.API,
    module Web.HttpApiData,
  )
where

import Data.Aeson
  ( FromJSON (..),
    Options (..),
    SumEncoding (..),
    ToJSON (..),
    Value (..),
    genericParseJSON,
    genericToJSON,
  )
import Data.Aeson qualified as Aeson
import Data.Aeson.Types qualified as Aeson
import Data.ByteString.Lazy (ByteString)
import Data.Char qualified as Char
import Data.List qualified as List
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map (Map)
-- Non-qualified function to use in implementation

import Data.Maybe (fromMaybe)
import Data.String (IsString (..))
import Data.Text (Text, pack, unpack)
import Data.Time.Clock qualified as Clock
import Data.Time.Clock.POSIX (POSIXTime)
import Data.Time.Clock.POSIX qualified as Time
import Data.Time.Format.ISO8601 qualified as ISO8601
import Data.Time.LocalTime (ZonedTime, zonedTimeToUTC)
import Data.Vector (Vector)
import Data.Void (Void)
import Data.Word (Word8)
import GHC.Generics (Generic)
import Numeric.Natural (Natural)
import Servant.API
  ( Accept (..),
    Capture,
    Delete,
    Get,
    Header',
    JSON,
    MimeUnrender (..),
    OctetStream,
    Patch,
    Post,
    QueryParam,
    ReqBody,
    Required,
    Strict,
    (:<|>) (..),
    (:>),
  )
import Servant.Multipart.API
  ( FileData (..),
    Input (..),
    MultipartData (..),
    MultipartForm,
    Tmp,
    ToMultipart (..),
  )
import Web.HttpApiData (ToHttpApiData (..))

dropTrailingUnderscore :: String -> String
dropTrailingUnderscore "_" = ""
dropTrailingUnderscore "" = ""
dropTrailingUnderscore (c : cs) = c : dropTrailingUnderscore cs

-- | Convert camelCase to snake_case and handle trailing underscores
-- e.g., "createdTime" -> "created_time", "type_" -> "type"
camelToSnake :: String -> String
camelToSnake = \case
  [] -> []
  (c : cs) -> Char.toLower c : go cs
  where
    go [] = []
    go (c : cs)
      | Char.isUpper c = '_' : Char.toLower c : go cs
      | otherwise = c : go cs

labelModifier :: String -> String
labelModifier = camelToSnake . dropTrailingUnderscore

stripPrefix :: String -> String -> String
stripPrefix prefix string = labelModifier suffix
  where
    suffix = fromMaybe string (List.stripPrefix prefix string)

aesonOptions :: Options
aesonOptions =
  Aeson.defaultOptions
    { fieldLabelModifier = labelModifier,
      constructorTagModifier = labelModifier,
      omitNothingFields = True
    }

-- | Parse an ISO8601 timestamp string to POSIXTime
-- Handles both UTC format (Z suffix) and timezone offset format (+00:00)
parseISO8601 :: Text -> Aeson.Parser POSIXTime
parseISO8601 text =
  case (ISO8601.iso8601ParseM str :: Maybe Clock.UTCTime) of
    Just utcTime -> return $ Time.utcTimeToPOSIXSeconds utcTime
    Nothing -> case (ISO8601.iso8601ParseM str :: Maybe ZonedTime) of
      Just zonedTime -> return $ Time.utcTimeToPOSIXSeconds (zonedTimeToUTC zonedTime)
      Nothing -> fail $ "Failed to parse ISO8601 timestamp: " <> str
  where
    str = unpack text

-- | Convert POSIXTime to an ISO8601 timestamp string
posixToISO8601 :: POSIXTime -> Text
posixToISO8601 = pack . ISO8601.iso8601Show . Time.posixSecondsToUTCTime
