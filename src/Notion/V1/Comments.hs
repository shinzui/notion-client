-- | @\/v1\/comments@
module Notion.V1.Comments
  ( -- * Main types
    CommentID,
    CommentObject (..),
    CommentAttachment (..),
    CommentDisplayName (..),
    CreateComment (..),

    -- * Servant
    API,
  )
where

import Data.Aeson ((.:), (.:?))
import Notion.Prelude
import Notion.V1.Common (BlockID, ExternalFile, File, ObjectType (..), Parent, UUID)
import Notion.V1.ListOf (ListOf)
import Notion.V1.RichText (RichText)
import Notion.V1.Users (UserReference)
import Prelude hiding (id)

-- | Comment ID
type CommentID = UUID

-- | Comment attachment (files attached to comments)
data CommentAttachment = CommentAttachment
  { name :: Text,
    type_ :: Text,
    external :: Maybe ExternalFile,
    file :: Maybe File
  }
  deriving stock (Generic, Show)

instance FromJSON CommentAttachment where
  parseJSON = genericParseJSON aesonOptions {fieldLabelModifier = \s -> if s == "type_" then "type" else labelModifier s}

instance ToJSON CommentAttachment where
  toJSON = genericToJSON aesonOptions {fieldLabelModifier = \s -> if s == "type_" then "type" else labelModifier s}

-- | Comment display name (custom display name for comments)
data CommentDisplayName = CommentDisplayName
  { type_ :: Text,
    emoji :: Maybe Text,
    displayName :: Maybe Text
  }
  deriving stock (Generic, Show)

instance FromJSON CommentDisplayName where
  parseJSON = genericParseJSON aesonOptions {fieldLabelModifier = \s -> if s == "type_" then "type" else labelModifier s}

instance ToJSON CommentDisplayName where
  toJSON = genericToJSON aesonOptions {fieldLabelModifier = \s -> if s == "type_" then "type" else labelModifier s}

-- | Notion comment object
data CommentObject = CommentObject
  { id :: CommentID,
    parent :: Parent,
    discussionId :: UUID,
    createdTime :: POSIXTime,
    lastEditedTime :: POSIXTime,
    createdBy :: UserReference,
    richText :: Vector RichText,
    attachments :: Maybe (Vector CommentAttachment),
    displayName :: Maybe CommentDisplayName,
    object :: ObjectType
  }
  deriving stock (Generic, Show)

instance FromJSON CommentObject where
  parseJSON = \case
    Object o -> do
      id <- o .: "id"
      parent <- o .: "parent"
      discussionId <- o .: "discussion_id"
      createdTimeStr <- o .: "created_time"
      createdTime <- parseISO8601 createdTimeStr
      lastEditedTimeStr <- o .: "last_edited_time"
      lastEditedTime <- parseISO8601 lastEditedTimeStr
      createdBy <- o .: "created_by"
      richText <- o .: "rich_text"
      attachments <- o .:? "attachments"
      displayName <- o .:? "display_name"
      object <- o .: "object"
      return CommentObject {..}
    _ -> fail "Expected object for CommentObject"

-- | Create comment request
data CreateComment = CreateComment
  { parent :: Parent,
    richText :: Vector RichText,
    discussionId :: Maybe UUID,
    attachments :: Maybe (Vector CommentAttachment),
    displayName :: Maybe CommentDisplayName
  }
  deriving stock (Generic, Show)

instance ToJSON CreateComment where
  toJSON = genericToJSON aesonOptions

-- | Servant API
-- Note: To list comments on a page, use the page ID as block_id (pages are blocks in Notion)
type API =
  "comments"
    :> ( ReqBody '[JSON] CreateComment
           :> Post '[JSON] CommentObject
           :<|> QueryParam "block_id" BlockID
           :> QueryParam "start_cursor" Text
           :> QueryParam "page_size" Natural
           :> Get '[JSON] (ListOf CommentObject)
       )
