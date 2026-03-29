-- | @\/v1\/blocks@
module Notion.V1.Blocks
  ( -- * Main types
    BlockID,
    BlockObject (..),
    BlockContent (..),
    AppendBlockChildren (..),

    -- * Servant
    API,
  )
where

import Control.Applicative ((<|>))
import Data.Aeson ((.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Maybe (fromMaybe)
import Notion.Prelude
import Notion.V1.Common (BlockID, ObjectType (..), Parent)
import Notion.V1.ListOf (ListOf)
import Notion.V1.Users (UserReference)
import Prelude hiding (id)

-- | Notion block object
data BlockObject = BlockObject
  { id :: BlockID,
    parent :: Parent,
    createdTime :: POSIXTime,
    lastEditedTime :: POSIXTime,
    createdBy :: UserReference,
    lastEditedBy :: UserReference,
    hasChildren :: Bool,
    archived :: Bool,
    type_ :: Text,
    content :: Value,
    object :: ObjectType
  }
  deriving stock (Generic, Show)

instance FromJSON BlockObject where
  parseJSON = \case
    Object o -> do
      id <- o .: "id"
      parent <- o .: "parent"
      createdTimeStr <- o .: "created_time"
      createdTime <- parseISO8601 createdTimeStr
      lastEditedTimeStr <- o .: "last_edited_time"
      lastEditedTime <- parseISO8601 lastEditedTimeStr
      createdBy <- o .: "created_by"
      lastEditedBy <- o .: "last_edited_by"
      hasChildren <- o .: "has_children"
      archived <- fmap (fromMaybe False) (o .:? "is_archived" <|> o .:? "archived")
      type_ <- o .: "type"
      -- Content is stored under a field named after the block type (e.g., "heading_1", "paragraph")
      content <- o .: Key.fromText type_
      object <- o .: "object"
      return BlockObject {..}
    _ -> fail "Expected object for BlockObject"

instance ToJSON BlockObject where
  toJSON BlockObject {..} =
    Aeson.object
      [ "id" .= id,
        "parent" .= parent,
        "created_time" .= posixToISO8601 createdTime,
        "last_edited_time" .= posixToISO8601 lastEditedTime,
        "created_by" .= createdBy,
        "last_edited_by" .= lastEditedBy,
        "has_children" .= hasChildren,
        "archived" .= archived,
        "type" .= type_,
        Key.fromText type_ .= content,
        "object" .= object
      ]

-- | Block content for update
newtype BlockContent = BlockContent
  { content :: Value
  }
  deriving stock (Generic, Show)

instance ToJSON BlockContent where
  toJSON = genericToJSON aesonOptions

-- | Append children to a block
newtype AppendBlockChildren = AppendBlockChildren
  { children :: Vector Value
  }
  deriving stock (Generic, Show)

instance ToJSON AppendBlockChildren where
  toJSON = genericToJSON aesonOptions

-- | Servant API
type API =
  "blocks"
    :> ( Capture "block_id" BlockID
           :> Get '[JSON] BlockObject
           :<|> Capture "block_id" BlockID
           :> ReqBody '[JSON] BlockContent
           :> Patch '[JSON] BlockObject
           :<|> Capture "block_id" BlockID
           :> "children"
           :> QueryParam "page_size" Natural
           :> QueryParam "start_cursor" Text
           :> Get '[JSON] (ListOf BlockObject)
           :<|> Capture "block_id" BlockID
           :> "children"
           :> ReqBody '[JSON] AppendBlockChildren
           :> Patch '[JSON] (ListOf BlockObject)
           :<|> Capture "block_id" BlockID
           :> Delete '[JSON] BlockObject
       )
