-- | @\/v1\/blocks@
module Notion.V1.Blocks
  ( -- * Main types
    BlockID,
    BlockObject (..),
    BlockUpdate (..),
    AppendBlockChildren (..),
    Position (..),

    -- * Re-exported from BlockContent
    module Notion.V1.BlockContent,

    -- * Servant
    API,
  )
where

import Control.Applicative ((<|>))
import Data.Aeson ((.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Notion.Prelude
import Notion.V1.BlockContent
import Notion.V1.Common (BlockID, ObjectType (..), Parent, UUID (..))
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
    inTrash :: Bool,
    type_ :: Text,
    content :: BlockContent,
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
      inTrash <- (o .: "in_trash") <|> (o .: "is_archived") <|> (o .: "archived") <|> pure False
      type_ <- o .: "type"
      contentVal <- o .: Key.fromText type_
      content <- parseBlockContent type_ contentVal
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
        "in_trash" .= inTrash,
        "type" .= type_,
        Key.fromText type_ .= snd (blockContentFields content),
        "object" .= object
      ]

-- | Block insertion position for the Append Block Children endpoint.
--
-- In API version 2026-03-11, the old @after@ parameter was replaced by a
-- @position@ object supporting three placement types.
data Position
  = -- | Insert after a specific block (replaces the old @after@ parameter)
    AfterBlock UUID
  | -- | Insert at the beginning of the parent
    Start
  | -- | Insert at the end of the parent (the default when @position@ is omitted)
    End
  deriving stock (Generic, Show)

instance ToJSON Position where
  toJSON (AfterBlock blockId) =
    Aeson.object
      [ "type" .= ("after_block" :: Text),
        "after_block" .= Aeson.object ["id" .= text blockId]
      ]
  toJSON Start =
    Aeson.object
      [ "type" .= ("start" :: Text),
        "start" .= Aeson.object []
      ]
  toJSON End =
    Aeson.object
      [ "type" .= ("end" :: Text),
        "end" .= Aeson.object []
      ]

-- | Append children to a block
data AppendBlockChildren = AppendBlockChildren
  { children :: Vector BlockContent,
    position :: Maybe Position
  }
  deriving stock (Generic, Show)

instance ToJSON AppendBlockChildren where
  toJSON AppendBlockChildren {..} =
    Aeson.object $
      ["children" .= children]
        <> maybe [] (\p -> ["position" .= p]) position

-- | Servant API
type API =
  "blocks"
    :> ( Capture "block_id" BlockID
           :> Get '[JSON] BlockObject
           :<|> Capture "block_id" BlockID
           :> ReqBody '[JSON] BlockUpdate
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
