-- | Common Notion API types
module Notion.V1.Common
  ( -- * Common types
    UUID,
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

import Data.Aeson (object, (.:), (.:?), (.=))
import Data.Aeson.KeyMap qualified as KeyMap
import Notion.Prelude

-- | UUID type for Notion resource IDs
newtype UUID = UUID {text :: Text}
  deriving newtype (Eq, FromJSON, IsString, Show, ToHttpApiData, ToJSON)

-- | Possible Notion object types
data ObjectType
  = Database
  | Page
  | Block
  | User
  | Comment
  deriving stock (Eq, Show, Generic)

instance FromJSON ObjectType where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON ObjectType where
  toJSON = genericToJSON aesonOptions

-- | Parent object that can be a database, page, block, or workspace
data Parent
  = DatabaseParent {databaseId :: UUID}
  | PageParent {pageId :: UUID}
  | BlockParent {blockId :: UUID}
  | WorkspaceParent {workspace :: Bool}
  deriving stock (Generic, Show)

instance FromJSON Parent where
  parseJSON = \case
    Object o -> do
      -- First, check if we have a 'type' field
      mParentType <- o .:? "type"
      case mParentType of
        -- If we have an explicit type field, use it for parsing
        Just parentType ->
          case parentType of
            "database" -> DatabaseParent <$> o .: "database_id"
            "database_id" -> DatabaseParent <$> o .: "database_id"
            "page" -> PageParent <$> o .: "page_id"
            "page_id" -> PageParent <$> o .: "page_id"
            "block" -> BlockParent <$> o .: "block_id"
            "block_id" -> BlockParent <$> o .: "block_id"
            "workspace" -> WorkspaceParent <$> o .: "workspace"
            _ -> fail $ "Unknown parent type: " <> unpack parentType
        -- If no type field, check for specific ID fields to infer parent type
        Nothing -> do
          -- Try each possible parent ID field
          if KeyMap.member "database_id" o
            then DatabaseParent <$> o .: "database_id"
            else
              if KeyMap.member "page_id" o
                then PageParent <$> o .: "page_id"
                else
                  if KeyMap.member "block_id" o
                    then BlockParent <$> o .: "block_id"
                    else
                      if KeyMap.member "workspace" o
                        then WorkspaceParent <$> o .: "workspace"
                        else fail "Missing parent type or ID fields"
    _ -> fail "Expected object for Parent"

instance ToJSON Parent where
  toJSON (DatabaseParent dbId) = object ["type" .= ("database_id" :: Text), "database_id" .= dbId]
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
  deriving stock (Generic, Show)

instance FromJSON Icon where
  parseJSON = \case
    Object o -> do
      iconType <- o .: "type"
      case iconType of
        "emoji" -> EmojiIcon <$> o .: "emoji"
        "file" -> FileIcon <$> o .: "file"
        "external" -> ExternalIcon <$> o .: "external"
        _ -> fail $ "Unknown icon type: " <> unpack iconType
    _ -> fail "Expected object for Icon"

instance ToJSON Icon where
  toJSON (EmojiIcon emoji) = object ["type" .= ("emoji" :: Text), "emoji" .= emoji]
  toJSON (FileIcon file) = object ["type" .= ("file" :: Text), "file" .= file]
  toJSON (ExternalIcon external) = object ["type" .= ("external" :: Text), "external" .= external]

-- | Cover object for pages/databases
data Cover
  = FileCover {file :: File}
  | ExternalCover {external :: ExternalFile}
  deriving stock (Generic, Show)

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
  deriving stock (Generic, Show)

instance FromJSON File where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON File where
  toJSON = genericToJSON aesonOptions

-- | External file object
newtype ExternalFile = ExternalFile
  { url :: Text
  }
  deriving stock (Generic, Show)

instance FromJSON ExternalFile where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON ExternalFile where
  toJSON = genericToJSON aesonOptions
