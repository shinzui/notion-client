-- | The `ListOf` type constructor for handling paginated Notion API responses
module Notion.V1.ListOf
  ( -- * Types
    ListOf (..),
  )
where

import Data.Aeson (Object, (.!=), (.:), (.:?))
import Notion.Prelude

-- | Notion API typically returns paginated results with this structure
data ListOf a = List
  { results :: Vector a,
    next_cursor :: Maybe Text,
    has_more :: Bool,
    type_ :: Maybe Text,
    object :: Maybe Text
  }
  deriving stock (Generic, Show)

instance (FromJSON a) => FromJSON (ListOf a) where
  parseJSON = \case
    Object o -> do
      results <- o .: "results"
      next_cursor <- o .:? "next_cursor"
      has_more <- o .:? "has_more" .!= False
      type_ <- o .:? "type"
      object <- o .:? "object"
      return $ List {..}
    _ -> fail "Expected object for ListOf"
