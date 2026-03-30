-- | Common Notion API types
module Notion.V1.Common
  ( -- * Common types
    UUID (..),
    BlockID,
    ObjectType (..),
    Parent (..),
    ParentID,
    Color (..),
    Icon (..),
    Cover (..),
    File (..),
    ExternalFile (..),
  )
where

import Data.Aeson (Object, object, (.:), (.:?), (.=))
import Data.Aeson.Types (Parser)
import Data.Foldable (asum)
import Notion.Prelude

-- | UUID type for Notion resource IDs
newtype UUID = UUID {text :: Text}
  deriving newtype (Eq, FromJSON, IsString, Show, ToHttpApiData, ToJSON)

-- | Block ID
type BlockID = UUID

-- | Possible Notion object types
data ObjectType
  = Database
  | DataSource
  | Page
  | Block
  | User
  | Comment
  | View
  deriving stock (Eq, Show, Generic)

instance FromJSON ObjectType where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON ObjectType where
  toJSON = genericToJSON aesonOptions

-- | Parent object that can be a database, data source, page, block, or workspace
data Parent
  = DatabaseParent {databaseId :: UUID}
  | DataSourceParent {dataSourceId :: UUID}
  | PageParent {pageId :: UUID}
  | BlockParent {blockId :: UUID}
  | WorkspaceParent {workspace :: Bool}
  deriving stock (Generic, Show)

instance FromJSON Parent where
  parseJSON = \case
    Object o -> do
      mParentType <- o .:? "type"
      case mParentType of
        Just parentType -> parseByType parentType o
        Nothing -> parseByKey o
    _ -> fail "Expected object for Parent"
    where
      parseByType :: Text -> Object -> Parser Parent
      parseByType = \case
        "database" -> fmap DatabaseParent . (.: "database_id")
        "database_id" -> fmap DatabaseParent . (.: "database_id")
        "data_source" -> fmap DataSourceParent . (.: "data_source_id")
        "data_source_id" -> fmap DataSourceParent . (.: "data_source_id")
        "page" -> fmap PageParent . (.: "page_id")
        "page_id" -> fmap PageParent . (.: "page_id")
        "block" -> fmap BlockParent . (.: "block_id")
        "block_id" -> fmap BlockParent . (.: "block_id")
        "workspace" -> fmap WorkspaceParent . (.: "workspace")
        other -> \_ -> fail $ "Unknown parent type: " <> unpack other

      parseByKey :: Object -> Parser Parent
      parseByKey o =
        asum
          [ DataSourceParent <$> o .: "data_source_id",
            DatabaseParent <$> o .: "database_id",
            PageParent <$> o .: "page_id",
            BlockParent <$> o .: "block_id",
            WorkspaceParent <$> o .: "workspace"
          ]

instance ToJSON Parent where
  toJSON (DatabaseParent dbId) = object ["type" .= ("database_id" :: Text), "database_id" .= dbId]
  toJSON (DataSourceParent dsId) = object ["type" .= ("data_source_id" :: Text), "data_source_id" .= dsId]
  toJSON (PageParent pId) = object ["type" .= ("page_id" :: Text), "page_id" .= pId]
  toJSON (BlockParent bId) = object ["type" .= ("block_id" :: Text), "block_id" .= bId]
  toJSON (WorkspaceParent ws) = object ["type" .= ("workspace" :: Text), "workspace" .= ws]

-- | Unified parent ID type
type ParentID = UUID

-- | Notion color options
data Color
  = Default
  | Gray
  | Brown
  | Orange
  | Yellow
  | Green
  | Blue
  | Purple
  | Pink
  | Red
  | GrayBackground
  | BrownBackground
  | OrangeBackground
  | YellowBackground
  | GreenBackground
  | BlueBackground
  | PurpleBackground
  | PinkBackground
  | RedBackground
  deriving stock (Eq, Show, Generic)

instance FromJSON Color where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON Color where
  toJSON = genericToJSON aesonOptions

-- | Icon object for pages/databases
data Icon
  = EmojiIcon {emoji :: Text}
  | FileIcon {file :: File}
  | ExternalIcon {external :: ExternalFile}
  | -- | Native icon specified by name and optional color
    NativeIcon {iconName :: Text, iconColor :: Maybe Text}
  | -- | Custom emoji icon specified by ID
    CustomEmojiIcon {customEmojiId :: UUID}
  deriving stock (Eq, Generic, Show)

instance FromJSON Icon where
  parseJSON = \case
    Object o -> do
      iconType <- o .: "type"
      case iconType of
        "emoji" -> EmojiIcon <$> o .: "emoji"
        "file" -> FileIcon <$> o .: "file"
        "external" -> ExternalIcon <$> o .: "external"
        "icon" -> NativeIcon <$> o .: "name" <*> o .:? "color"
        "custom_emoji" -> CustomEmojiIcon <$> o .: "id"
        _ -> fail $ "Unknown icon type: " <> unpack iconType
    _ -> fail "Expected object for Icon"

instance ToJSON Icon where
  toJSON (EmojiIcon emoji) = object ["type" .= ("emoji" :: Text), "emoji" .= emoji]
  toJSON (FileIcon file) = object ["type" .= ("file" :: Text), "file" .= file]
  toJSON (ExternalIcon external) = object ["type" .= ("external" :: Text), "external" .= external]
  toJSON (NativeIcon name color) = object $ ["type" .= ("icon" :: Text), "name" .= name] <> maybe [] (\c -> ["color" .= c]) color
  toJSON (CustomEmojiIcon eid) = object ["type" .= ("custom_emoji" :: Text), "id" .= eid]

-- | Cover object for pages/databases
data Cover
  = FileCover {file :: File}
  | ExternalCover {external :: ExternalFile}
  deriving stock (Eq, Generic, Show)

instance FromJSON Cover where
  parseJSON = \case
    Object o -> do
      coverType <- o .: "type"
      case coverType of
        "file" -> FileCover <$> o .: "file"
        "external" -> ExternalCover <$> o .: "external"
        _ -> fail $ "Unknown cover type: " <> unpack coverType
    _ -> fail "Expected object for Cover"

instance ToJSON Cover where
  toJSON (FileCover file) = object ["type" .= ("file" :: Text), "file" .= file]
  toJSON (ExternalCover external) = object ["type" .= ("external" :: Text), "external" .= external]

-- | Internal file object
data File = File
  { url :: Text,
    expiryTime :: Maybe POSIXTime
  }
  deriving stock (Eq, Generic, Show)

instance FromJSON File where
  parseJSON = \case
    Object o -> do
      url <- o .: "url"
      mExpiry <- o .:? "expiry_time"
      expiryTime <- case mExpiry of
        Nothing -> pure Nothing
        Just str -> Just <$> parseISO8601 str
      pure File {..}
    _ -> fail "Expected object for File"

instance ToJSON File where
  toJSON File {..} =
    object $
      ["url" .= url]
        <> maybe [] (\t -> ["expiry_time" .= posixToISO8601 t]) expiryTime

-- | External file object
newtype ExternalFile = ExternalFile
  { url :: Text
  }
  deriving stock (Eq, Generic, Show)

instance FromJSON ExternalFile where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON ExternalFile where
  toJSON = genericToJSON aesonOptions
