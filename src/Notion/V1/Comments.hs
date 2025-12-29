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

import Data.Aeson (Object, (.:), (.:?))
import Notion.Prelude
import Notion.V1.Common (ObjectType (..), UUID)
import Notion.V1.ListOf (ListOf)
import Notion.V1.Users (UserReference)

-- | Block ID type for Comments
type BlockID = UUID

-- | Page ID type for Comments
type PageID = UUID

-- | Comment ID
type CommentID = UUID

-- | Comment attachment (files attached to comments)
data CommentAttachment = CommentAttachment
  { name :: Text,
    type_ :: Text,
    external :: Maybe Value,
    file :: Maybe Value
  }
  deriving stock (Generic, Show)

instance FromJSON CommentAttachment where
  parseJSON = genericParseJSON aesonOptions {fieldLabelModifier = \s -> if s == "type_" then "type" else labelModifier s}

-- | Comment display name (custom display name for comments)
data CommentDisplayName = CommentDisplayName
  { type_ :: Text,
    emoji :: Maybe Text,
    display_name :: Maybe Text
  }
  deriving stock (Generic, Show)

instance FromJSON CommentDisplayName where
  parseJSON = genericParseJSON aesonOptions {fieldLabelModifier = \s -> if s == "type_" then "type" else labelModifier s}

-- | Notion comment object
data CommentObject = CommentObject
  { id :: CommentID,
    parent :: Value,
    discussion_id :: UUID,
    created_time :: POSIXTime,
    last_edited_time :: POSIXTime,
    created_by :: UserReference,
    rich_text :: Value,
    attachments :: Maybe (Vector CommentAttachment),
    display_name :: Maybe CommentDisplayName,
    object :: ObjectType
  }
  deriving stock (Generic, Show)

instance FromJSON CommentObject where
  parseJSON = \case
    Object o -> do
      id <- o .: "id"
      parent <- o .: "parent"
      discussion_id <- o .: "discussion_id"
      created_time_str <- o .: "created_time"
      created_time <- parseISO8601 created_time_str
      last_edited_time_str <- o .: "last_edited_time"
      last_edited_time <- parseISO8601 last_edited_time_str
      created_by <- o .: "created_by"
      rich_text <- o .: "rich_text"
      attachments <- o .:? "attachments"
      display_name <- o .:? "display_name"
      object <- o .: "object"
      return CommentObject {..}
    _ -> fail "Expected object for CommentObject"

-- | Create comment request
data CreateComment = CreateComment
  { parent :: Value,
    rich_text :: Value,
    discussion_id :: Maybe UUID
  }
  deriving stock (Generic, Show)

instance ToJSON CreateComment where
  toJSON = genericToJSON aesonOptions

-- | Servant API
type API =
  "comments"
    :> ( ReqBody '[JSON] CreateComment
           :> Post '[JSON] CommentObject
           :<|> QueryParam "block_id" BlockID
           :> QueryParam "page_id" PageID
           :> QueryParam "start_cursor" Text
           :> QueryParam "page_size" Natural
           :> Get '[JSON] (ListOf CommentObject)
       )
