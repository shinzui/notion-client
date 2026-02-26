-- | @\/v1\/search@
module Notion.V1.Search
  ( -- * Main types
    SearchRequest (..),
    _SearchRequest,
    SearchSortDirection (..),
    SearchSort (..),
    SearchFilter (..),
    SearchObjectType (..),

    -- * Response parsing
    SearchResult (..),
    parseSearchResults,

    -- * Convenience constructors
    pageFilter,
    dataSourceFilter,

    -- * Servant
    API,
  )
where

import Data.Aeson qualified as Aeson
import Data.Vector qualified as Vector
import Notion.Prelude
import Notion.V1.DataSources (DataSourceObject)
import Notion.V1.ListOf (ListOf (..))
import Notion.V1.Pages (PageObject)

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
data SearchSort = SearchSort
  { direction :: SearchSortDirection,
    timestamp :: Text
  }
  deriving stock (Generic, Show)

instance ToJSON SearchSort where
  toJSON = genericToJSON aesonOptions

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
data SearchFilter = SearchFilter
  { value :: SearchObjectType,
    property :: Text
  }
  deriving stock (Generic, Show)

instance ToJSON SearchFilter where
  toJSON = genericToJSON aesonOptions

-- | Create a filter to search only for pages
pageFilter :: SearchFilter
pageFilter = SearchFilter {value = SearchPage, property = "object"}

-- | Create a filter to search only for data sources
dataSourceFilter :: SearchFilter
dataSourceFilter = SearchFilter {value = SearchDataSource, property = "object"}

-- | Servant API
type API =
  "search"
    :> ReqBody '[JSON] SearchRequest
    :> Post '[JSON] (ListOf Aeson.Value)

-- * Response parsing

-- | A search result can be either a page or a data source
data SearchResult
  = PageResult PageObject
  | DataSourceResult DataSourceObject
  deriving stock (Show)

instance FromJSON SearchResult where
  parseJSON v = do
    obj <- Aeson.parseJSON v
    objectType <- obj Aeson..: "object"
    case objectType of
      "page" -> PageResult <$> Aeson.parseJSON v
      "data_source" -> DataSourceResult <$> Aeson.parseJSON v
      other -> fail $ "Unknown object type in search result: " <> other

-- | Parse raw search results into typed 'SearchResult' values.
-- Results that fail to parse are silently dropped.
parseSearchResults :: ListOf Aeson.Value -> Vector SearchResult
parseSearchResults listOf =
  Vector.mapMaybe parseOne (results listOf)
  where
    parseOne :: Aeson.Value -> Maybe SearchResult
    parseOne v = case Aeson.fromJSON v of
      Aeson.Success r -> Just r
      Aeson.Error _ -> Nothing
