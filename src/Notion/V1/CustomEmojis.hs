-- | @\/v1\/custom_emojis@
--
-- List custom emojis available in the workspace.
module Notion.V1.CustomEmojis
  ( -- * Main types
    CustomEmoji (..),

    -- * Servant
    API,
  )
where

import Notion.Prelude
import Notion.V1.Common (UUID)
import Notion.V1.ListOf (ListOf)
import Prelude hiding (id)

-- | A custom emoji in the workspace
data CustomEmoji = CustomEmoji
  { id :: UUID,
    name :: Text,
    url :: Text
  }
  deriving stock (Generic, Show)

instance FromJSON CustomEmoji where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON CustomEmoji where
  toJSON = genericToJSON aesonOptions

-- | Servant API
type API =
  "custom_emojis"
    :> ( QueryParam "name" Text
           :> QueryParam "start_cursor" Text
           :> QueryParam "page_size" Natural
           :> Get '[JSON] (ListOf CustomEmoji)
       )
