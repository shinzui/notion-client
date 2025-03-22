-- | The `ListOf` type constructor for handling paginated Notion API responses
module Notion.V1.ListOf
  ( -- * Types
    ListOf (..),
  )
where

import Notion.Prelude

-- | Notion API typically returns paginated results with this structure
data ListOf a = List
  { results :: Vector a,
    next_cursor :: Maybe Text,
    has_more :: Bool
  }
  deriving stock (Generic, Show)

instance (FromJSON a) => FromJSON (ListOf a) where
  parseJSON = genericParseJSON aesonOptions
