-- | @\/v1\/search@
module Notion.V1.Search
  ( -- * Main types
    SearchRequest (..),
    _SearchRequest,
    SearchSortDirection (..),
    SearchSort (..),
    SearchFilter (..),

    -- * Servant
    API,
  )
where

import Data.Aeson (Value)
import Notion.Prelude
import Notion.V1.Common (ObjectType (..))
import Notion.V1.ListOf (ListOf)

-- | Search request
data SearchRequest = SearchRequest
  { query :: Maybe Text,
    sort :: Maybe SearchSort,
    filter :: Maybe SearchFilter,
    start_cursor :: Maybe Text,
    page_size :: Maybe Natural
  }
  deriving stock (Generic, Show)

instance ToJSON SearchRequest where
  toJSON = genericToJSON aesonOptions

-- | Default search request
_SearchRequest :: SearchRequest
_SearchRequest =
  SearchRequest
    { query = Nothing,
      sort = Nothing,
      filter = Nothing,
      start_cursor = Nothing,
      page_size = Nothing
    }

-- | Search sort direction
data SearchSortDirection
  = Ascending
  | Descending
  deriving stock (Generic, Show)

instance ToJSON SearchSortDirection where
  toJSON = genericToJSON aesonOptions

-- | Search sort
data SearchSort = SearchSort
  { direction :: SearchSortDirection,
    timestamp :: Text
  }
  deriving stock (Generic, Show)

instance ToJSON SearchSort where
  toJSON = genericToJSON aesonOptions

-- | Search filter
data SearchFilter = SearchFilter
  { value :: ObjectType,
    property :: Text
  }
  deriving stock (Generic, Show)

instance ToJSON SearchFilter where
  toJSON = genericToJSON aesonOptions

-- | Servant API
type API =
  "search"
    :> ReqBody '[JSON] SearchRequest
    :> Post '[JSON] (ListOf Value)
