-- | @\/v1\/search@
module Notion.V1.Search
  ( -- * Main types
    SearchRequest (..),
    _SearchRequest,
    SearchSortDirection (..),
    SearchSort (..),
    SearchFilter (..),
    SearchObjectType (..),

    -- * Results
    SearchResult,
    PageOrDataSource (..),
    PartialPageObject (..),
    PartialDataSourceObject (..),
    pageResults,
    dataSourceResults,

    -- * Convenience constructors
    pageFilter,
    dataSourceFilter,

    -- * Servant
    API,
  )
where

import Data.Aeson ((.=))
import Data.Aeson qualified as Aeson
import Notion.Prelude
import Notion.V1.DataSources (PageOrDataSource (..), PartialDataSourceObject (..), PartialPageObject (..), dataSourceResults, pageResults)
import Notion.V1.ListOf (ListOf)

-- | Search request
data SearchRequest = SearchRequest
  { query :: Maybe Text,
    sort :: Maybe SearchSort,
    filter :: Maybe SearchFilter,
    startCursor :: Maybe Text,
    pageSize :: Maybe Natural
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
      startCursor = Nothing,
      pageSize = Nothing
    }

-- | Search sort direction
data SearchSortDirection
  = Ascending
  | Descending
  deriving stock (Generic, Show)

instance ToJSON SearchSortDirection where
  toJSON = genericToJSON aesonOptions

-- | Search sort
data SearchSort
  = -- | @{"timestamp":"last_edited_time","direction":...}@
    SearchByLastEditedTime SearchSortDirection
  | -- | @{"property":"relevance"}@
    SearchByRelevance
  deriving stock (Generic, Show)

instance ToJSON SearchSort where
  toJSON (SearchByLastEditedTime dir) = Aeson.object ["timestamp" .= ("last_edited_time" :: Text), "direction" .= dir]
  toJSON SearchByRelevance = Aeson.object ["property" .= ("relevance" :: Text)]

-- | Object types supported by the search filter.
-- In API version 2025-09-03, the search API filters by @page@ or @data_source@.
data SearchObjectType
  = SearchPage
  | SearchDataSource
  deriving stock (Eq, Show, Generic)

instance ToJSON SearchObjectType where
  toJSON SearchPage = Aeson.String "page"
  toJSON SearchDataSource = Aeson.String "data_source"

instance FromJSON SearchObjectType where
  parseJSON = Aeson.withText "SearchObjectType" $ \case
    "page" -> pure SearchPage
    "data_source" -> pure SearchDataSource
    other -> fail $ "Unknown search object type: " <> unpack other

-- | Search filter
data SearchFilter
  = -- | @{"property":"object","value":...,"in_trash"?:...}@
    SearchObjectFilter SearchObjectType (Maybe Bool)
  | -- | @{"in_trash":...}@
    SearchInTrashFilter Bool
  deriving stock (Generic, Show)

instance ToJSON SearchFilter where
  toJSON (SearchObjectFilter v mTrash) =
    Aeson.object $ ["property" .= ("object" :: Text), "value" .= v] <> maybe [] (\t -> ["in_trash" .= t]) mTrash
  toJSON (SearchInTrashFilter t) = Aeson.object ["in_trash" .= t]

-- | Create a filter to search only for pages
pageFilter :: SearchFilter
pageFilter = SearchObjectFilter SearchPage Nothing

-- | Create a filter to search only for data sources
dataSourceFilter :: SearchFilter
dataSourceFilter = SearchObjectFilter SearchDataSource Nothing

-- | A search result: the same union as a data source query result.
type SearchResult = PageOrDataSource

-- | Servant API
type API =
  "search"
    :> ReqBody '[JSON] SearchRequest
    :> Post '[JSON] (ListOf PageOrDataSource)
