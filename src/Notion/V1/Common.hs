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
    CustomEmojiRef (..),
  )
where

import Data.Aeson (Object, object, withText, (.:), (.:?), (.=))
import Data.Aeson.Types (Parser)
import Data.Foldable (asum)
import Data.Maybe (fromMaybe)
import Data.Tuple (swap)
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
  | DataSourceParent {dataSourceId :: UUID, parentDatabaseId :: Maybe UUID}
  | PageParent {pageId :: UUID}
  | BlockParent {blockId :: UUID}
  | WorkspaceParent {workspace :: Bool}
  | AgentParent {agentId :: UUID}
  | -- | A parent kind this library does not model yet; holds the raw JSON object.
    UnknownParent Value
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
        "data_source" -> \o -> DataSourceParent <$> o .: "data_source_id" <*> o .:? "database_id"
        "data_source_id" -> \o -> DataSourceParent <$> o .: "data_source_id" <*> o .:? "database_id"
        "page" -> fmap PageParent . (.: "page_id")
        "page_id" -> fmap PageParent . (.: "page_id")
        "block" -> fmap BlockParent . (.: "block_id")
        "block_id" -> fmap BlockParent . (.: "block_id")
        "workspace" -> fmap WorkspaceParent . (.: "workspace")
        "agent_id" -> fmap AgentParent . (.: "agent_id")
        _ -> pure . UnknownParent . Object

      parseByKey :: Object -> Parser Parent
      parseByKey o =
        asum
          [ DataSourceParent <$> o .: "data_source_id" <*> o .:? "database_id",
            DatabaseParent <$> o .: "database_id",
            PageParent <$> o .: "page_id",
            BlockParent <$> o .: "block_id",
            AgentParent <$> o .: "agent_id",
            WorkspaceParent <$> o .: "workspace",
            pure (UnknownParent (Object o))
          ]

instance ToJSON Parent where
  toJSON (DatabaseParent dbId) = object ["type" .= ("database_id" :: Text), "database_id" .= dbId]
  toJSON (DataSourceParent dsId mDbId) =
    object $
      ["type" .= ("data_source_id" :: Text), "data_source_id" .= dsId]
        <> maybe [] (\dbId -> ["database_id" .= dbId]) mDbId
  toJSON (PageParent pId) = object ["type" .= ("page_id" :: Text), "page_id" .= pId]
  toJSON (BlockParent bId) = object ["type" .= ("block_id" :: Text), "block_id" .= bId]
  toJSON (WorkspaceParent ws) = object ["type" .= ("workspace" :: Text), "workspace" .= ws]
  toJSON (AgentParent aId) = object ["type" .= ("agent_id" :: Text), "agent_id" .= aId]
  toJSON (UnknownParent v) = v

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
  | DefaultBackground
  | GrayBackground
  | BrownBackground
  | OrangeBackground
  | YellowBackground
  | GreenBackground
  | BlueBackground
  | PurpleBackground
  | PinkBackground
  | RedBackground
  | -- | A color this library does not know yet; holds the raw string.
    UnknownColor Text
  deriving stock (Eq, Show, Generic)

colorNames :: [(Color, Text)]
colorNames =
  [ (Default, "default"),
    (Gray, "gray"),
    (Brown, "brown"),
    (Orange, "orange"),
    (Yellow, "yellow"),
    (Green, "green"),
    (Blue, "blue"),
    (Purple, "purple"),
    (Pink, "pink"),
    (Red, "red"),
    (DefaultBackground, "default_background"),
    (GrayBackground, "gray_background"),
    (BrownBackground, "brown_background"),
    (OrangeBackground, "orange_background"),
    (YellowBackground, "yellow_background"),
    (GreenBackground, "green_background"),
    (BlueBackground, "blue_background"),
    (PurpleBackground, "purple_background"),
    (PinkBackground, "pink_background"),
    (RedBackground, "red_background")
  ]

instance FromJSON Color where
  parseJSON = withText "Color" $ \t ->
    pure (fromMaybe (UnknownColor t) (lookup t (map swap colorNames)))

instance ToJSON Color where
  toJSON = \case
    UnknownColor t -> String t
    c -> String (fromMaybe "default" (lookup c colorNames))

-- | Icon object for pages/databases
data Icon
  = EmojiIcon {emoji :: Text}
  | FileIcon {file :: File}
  | ExternalIcon {external :: ExternalFile}
  | -- | Native icon specified by name and optional color
    NativeIcon {iconName :: Text, iconColor :: Maybe Text}
  | -- | Custom emoji icon specified by ID
    CustomEmojiIcon {customEmojiId :: UUID}
  | -- | File upload icon referenced by upload ID
    FileUploadIcon {fileUploadId :: UUID}
  | -- | An icon kind this library does not model yet; holds the raw icon object.
    UnknownIcon Value
  deriving stock (Eq, Generic, Show)

instance FromJSON Icon where
  parseJSON = \case
    Object o -> do
      iconType :: Text <- o .: "type"
      case iconType of
        "emoji" -> EmojiIcon <$> o .: "emoji"
        "file" -> FileIcon <$> o .: "file"
        "external" -> ExternalIcon <$> o .: "external"
        "icon" -> do
          inner <- o .: "icon"
          NativeIcon <$> inner .: "name" <*> inner .:? "color"
        "custom_emoji" -> do
          mInner <- o .:? "custom_emoji"
          case mInner of
            Just inner -> CustomEmojiIcon <$> inner .: "id"
            -- Shape written by notion-client <= 0.7.0.2; still accepted when reading.
            Nothing -> CustomEmojiIcon <$> o .: "id"
        "file_upload" -> do
          uploadObj <- o .: "file_upload"
          FileUploadIcon <$> uploadObj .: "id"
        _ -> pure (UnknownIcon (Object o))
    _ -> fail "Expected object for Icon"

instance ToJSON Icon where
  toJSON (EmojiIcon emoji) = object ["type" .= ("emoji" :: Text), "emoji" .= emoji]
  toJSON (FileIcon file) = object ["type" .= ("file" :: Text), "file" .= file]
  toJSON (ExternalIcon external) = object ["type" .= ("external" :: Text), "external" .= external]
  toJSON (NativeIcon name color) =
    object
      [ "type" .= ("icon" :: Text),
        "icon" .= object (["name" .= name] <> maybe [] (\c -> ["color" .= c]) color)
      ]
  toJSON (CustomEmojiIcon eid) =
    object ["type" .= ("custom_emoji" :: Text), "custom_emoji" .= object ["id" .= eid]]
  toJSON (FileUploadIcon uid) = object ["type" .= ("file_upload" :: Text), "file_upload" .= object ["id" .= uid]]
  toJSON (UnknownIcon v) = v

-- | Reference to a workspace custom emoji. Responses always include 'name'
-- and 'url'; requests may send only the ID.
data CustomEmojiRef = CustomEmojiRef
  { id :: UUID,
    name :: Maybe Text,
    url :: Maybe Text
  }
  deriving stock (Eq, Generic, Show)

instance FromJSON CustomEmojiRef where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON CustomEmojiRef where
  toJSON = genericToJSON aesonOptions

-- | Cover object for pages/databases
data Cover
  = FileCover {file :: File}
  | ExternalCover {external :: ExternalFile}
  | FileUploadCover {fileUploadId :: UUID}
  deriving stock (Eq, Generic, Show)

instance FromJSON Cover where
  parseJSON = \case
    Object o -> do
      coverType <- o .: "type"
      case coverType of
        "file" -> FileCover <$> o .: "file"
        "external" -> ExternalCover <$> o .: "external"
        "file_upload" -> do
          uploadObj <- o .: "file_upload"
          FileUploadCover <$> uploadObj .: "id"
        _ -> fail $ "Unknown cover type: " <> unpack coverType
    _ -> fail "Expected object for Cover"

instance ToJSON Cover where
  toJSON (FileCover file) = object ["type" .= ("file" :: Text), "file" .= file]
  toJSON (ExternalCover external) = object ["type" .= ("external" :: Text), "external" .= external]
  toJSON (FileUploadCover uid) = object ["type" .= ("file_upload" :: Text), "file_upload" .= object ["id" .= uid]]

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
