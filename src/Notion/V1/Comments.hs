-- | @\/v1\/comments@
module Notion.V1.Comments
  ( -- * Main types
    CommentID,
    CommentObject (..),
    CreateComment (..),

    -- * Servant
    API,
  )
where

import Notion.Prelude
import Notion.V1.Common (ObjectType (..), UUID)
import Notion.V1.ListOf (ListOf)

-- | Block ID type for Comments
type BlockID = UUID

-- | Comment ID
type CommentID = UUID

-- | Notion comment object
data CommentObject = CommentObject
  { id :: CommentID,
    parent :: Value,
    discussion_id :: UUID,
    created_time :: POSIXTime,
    last_edited_time :: POSIXTime,
    created_by :: UUID,
    rich_text :: Value,
    object :: ObjectType
  }
  deriving stock (Generic, Show)

instance FromJSON CommentObject where
  parseJSON = genericParseJSON aesonOptions

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
          :> Get '[JSON] (ListOf CommentObject)
       )
