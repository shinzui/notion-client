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

import Data.Aeson ((.:))
import Notion.Prelude
import Notion.V1.Common (ObjectType (..), ParentID, UUID)
import Notion.V1.ListOf (ListOf)
import Notion.V1.Users (UserReference)

-- | Block ID
type BlockID = UUID

-- | Notion block object
data BlockObject = BlockObject
  { id :: BlockID,
    parent :: ParentID,
    created_time :: POSIXTime,
    last_edited_time :: POSIXTime,
    created_by :: UserReference,
    last_edited_by :: UserReference,
    has_children :: Bool,
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
      created_time_str <- o .: "created_time"
      created_time <- parseISO8601 created_time_str
      last_edited_time_str <- o .: "last_edited_time"
      last_edited_time <- parseISO8601 last_edited_time_str
      created_by <- o .: "created_by"
      last_edited_by <- o .: "last_edited_by"
      has_children <- o .: "has_children"
      archived <- o .: "archived"
      type_ <- o .: "type"
      content <- o .: "content"
      object <- o .: "object"
      return BlockObject {..}
    _ -> fail "Expected object for BlockObject"

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
          :> Patch '[JSON] BlockObject
          :<|> Capture "block_id" BlockID
          :> Delete '[JSON] BlockObject
       )
