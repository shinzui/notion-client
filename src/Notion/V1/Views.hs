-- | @\/v1\/views@
--
-- Views represent saved configurations of database data (filters, sorts, layout)
-- across 10 view types: table, board, list, calendar, timeline, gallery, form,
-- chart, map, and dashboard.
module Notion.V1.Views
  ( -- * Main types
    ViewID,
    ViewObject (..),
    ViewType (..),
    CreateView (..),
    UpdateView (..),

    -- * Filters, sorts and placement
    ViewFilter (..),
    ViewSort (..),
    QuickFilter (..),
    ViewPropertySort (..),
    ViewPosition (..),
    WidgetPlacement (..),
    CreateDatabaseForView (..),
    Clearable (..),

    -- * View queries
    ViewQueryID,
    CreateViewQuery (..),
    ViewQuery (..),
    DeletedViewQuery (..),
    PartialPageObject (..),

    -- * Servant
    API,
  )
where

import Control.Applicative ((<|>))
import Data.Aeson ((.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Notion.Prelude
import Notion.V1.Clearable (Clearable (..))
import Notion.V1.Common (ObjectType, Parent, UUID)
import Notion.V1.Filter (Filter, PropertyCondition, Sort, SortDirection)
import Notion.V1.ListOf (ListOf, RequestStatus)
import Notion.V1.Pages (PartialPageObject (..))
import Notion.V1.Users (UserReference)
import Prelude hiding (id)

-- | View ID
type ViewID = UUID

-- | View types supported by the Notion API
data ViewType
  = TableView
  | BoardView
  | ListViewType
  | CalendarView
  | TimelineView
  | GalleryView
  | FormView
  | ChartView
  | MapView
  | DashboardView
  | -- | A view type this library does not know yet; holds the raw string.
    UnknownViewType Text
  deriving stock (Eq, Show, Generic)

instance FromJSON ViewType where
  parseJSON = Aeson.withText "ViewType" $ \case
    "table" -> pure TableView
    "board" -> pure BoardView
    "list" -> pure ListViewType
    "calendar" -> pure CalendarView
    "timeline" -> pure TimelineView
    "gallery" -> pure GalleryView
    "form" -> pure FormView
    "chart" -> pure ChartView
    "map" -> pure MapView
    "dashboard" -> pure DashboardView
    other -> pure (UnknownViewType other)

instance ToJSON ViewType where
  toJSON = \case
    TableView -> "table"
    BoardView -> "board"
    ListViewType -> "list"
    CalendarView -> "calendar"
    TimelineView -> "timeline"
    GalleryView -> "gallery"
    FormView -> "form"
    ChartView -> "chart"
    MapView -> "map"
    DashboardView -> "dashboard"
    UnknownViewType t -> String t

-- | A view's filter: typed when the 'Filter' DSL can express it, raw JSON otherwise.
data ViewFilter
  = ViewFilter Filter
  | RawViewFilter Value
  deriving stock (Eq, Show)

instance FromJSON ViewFilter where
  parseJSON v = (ViewFilter <$> parseJSON v) <|> pure (RawViewFilter v)

instance ToJSON ViewFilter where
  toJSON = \case
    ViewFilter f -> toJSON f
    RawViewFilter v -> v

-- | A view sort: typed property or timestamp sort, or raw JSON.
data ViewSort
  = ViewSort Sort
  | RawViewSort Value
  deriving stock (Eq, Show)

instance FromJSON ViewSort where
  parseJSON v = (ViewSort <$> parseJSON v) <|> pure (RawViewSort v)

instance ToJSON ViewSort where
  toJSON = \case
    ViewSort s -> toJSON s
    RawViewSort v -> v

-- | A quick filter condition (a property condition without the @property@
-- key, e.g. @{"select":{"equals":"High"}}@), or raw JSON.
data QuickFilter
  = QuickFilter PropertyCondition
  | RawQuickFilter Value
  deriving stock (Eq, Show)

instance FromJSON QuickFilter where
  parseJSON v = (QuickFilter <$> parseJSON v) <|> pure (RawQuickFilter v)

instance ToJSON QuickFilter where
  toJSON = \case
    QuickFilter c -> toJSON c
    RawQuickFilter v -> v

-- | A property sort, the only kind 'UpdateView' accepts.
data ViewPropertySort = ViewPropertySort
  { property :: Text,
    direction :: SortDirection
  }
  deriving stock (Eq, Generic, Show)

instance ToJSON ViewPropertySort where
  toJSON = genericToJSON aesonOptions

-- | Where a new view tab goes in the database's tab bar.
data ViewPosition
  = ViewPositionStart
  | ViewPositionEnd
  | ViewPositionAfterView ViewID
  deriving stock (Eq, Show)

instance ToJSON ViewPosition where
  toJSON = \case
    ViewPositionStart -> Aeson.object ["type" .= ("start" :: Text)]
    ViewPositionEnd -> Aeson.object ["type" .= ("end" :: Text)]
    ViewPositionAfterView v -> Aeson.object ["type" .= ("after_view" :: Text), "view_id" .= v]

-- | Where a new widget goes inside a dashboard view (0-based row index).
data WidgetPlacement
  = NewRow (Maybe Natural)
  | ExistingRow Natural
  deriving stock (Eq, Show)

instance ToJSON WidgetPlacement where
  toJSON = \case
    NewRow Nothing -> Aeson.object ["type" .= ("new_row" :: Text)]
    NewRow (Just i) -> Aeson.object ["type" .= ("new_row" :: Text), "row_index" .= i]
    ExistingRow i -> Aeson.object ["type" .= ("existing_row" :: Text), "row_index" .= i]

-- | Create a new linked database block on a page and put the view in it.
data CreateDatabaseForView = CreateDatabaseForView
  { parentPageId :: UUID,
    afterBlockId :: Maybe UUID
  }
  deriving stock (Eq, Show)

instance ToJSON CreateDatabaseForView where
  toJSON CreateDatabaseForView {..} =
    Aeson.object $
      ["parent" .= Aeson.object ["type" .= ("page_id" :: Text), "page_id" .= parentPageId]]
        <> maybe [] (\b -> ["position" .= Aeson.object ["type" .= ("after_block" :: Text), "block_id" .= b]]) afterBlockId

-- | Notion view object
--
-- Many fields are 'Maybe' because the API returns partial or full view objects
-- depending on context (list endpoints return minimal objects with just id, parent, type).
data ViewObject = ViewObject
  { id :: ViewID,
    parent :: Maybe Parent,
    name :: Maybe Text,
    type_ :: Maybe ViewType,
    createdTime :: Maybe POSIXTime,
    lastEditedTime :: Maybe POSIXTime,
    url :: Maybe Text,
    dataSourceId :: Maybe UUID,
    createdBy :: Maybe UserReference,
    lastEditedBy :: Maybe UserReference,
    filter :: Maybe ViewFilter,
    sorts :: Maybe (Vector ViewSort),
    quickFilters :: Maybe (Map Text QuickFilter),
    configuration :: Maybe Value,
    dashboardViewId :: Maybe ViewID,
    object :: Maybe ObjectType
  }
  deriving stock (Generic, Show)

instance FromJSON ViewObject where
  parseJSON = \case
    Object o -> do
      id <- o .: "id"
      parent <- o .:? "parent"
      name <- o .:? "name"
      type_ <- o .:? "type"
      mCreatedTimeStr <- o .:? "created_time"
      createdTime <- traverse parseISO8601 mCreatedTimeStr
      mLastEditedTimeStr <- o .:? "last_edited_time"
      lastEditedTime <- traverse parseISO8601 mLastEditedTimeStr
      url <- o .:? "url"
      dataSourceId <- o .:? "data_source_id"
      createdBy <- o .:? "created_by"
      lastEditedBy <- o .:? "last_edited_by"
      filter <- o .:? "filter"
      sorts <- o .:? "sorts"
      quickFilters <- o .:? "quick_filters"
      configuration <- o .:? "configuration"
      dashboardViewId <- o .:? "dashboard_view_id"
      object <- o .:? "object"
      return ViewObject {..}
    _ -> fail "Expected object for ViewObject"

-- | Create a view request
data CreateView = CreateView
  { dataSourceId :: UUID,
    name :: Text,
    type_ :: ViewType,
    -- | Mutually exclusive with 'viewId' and 'createDatabase_'
    databaseId :: Maybe UUID,
    -- | Dashboard view to add this view to as a widget
    viewId :: Maybe ViewID,
    filter :: Maybe ViewFilter,
    sorts :: Maybe (Vector ViewSort),
    -- | Keyed by property ID
    quickFilters :: Maybe (Map Text QuickFilter),
    -- | Wire name @create_database@
    createDatabase_ :: Maybe CreateDatabaseForView,
    configuration :: Maybe Value,
    position :: Maybe ViewPosition,
    placement :: Maybe WidgetPlacement
  }
  deriving stock (Generic, Show)

instance ToJSON CreateView where
  toJSON = genericToJSON aesonOptions

-- | Update a view request. 'Unset' leaves a field unchanged and 'Clear' sends
-- @null@ to clear it.
data UpdateView = UpdateView
  { name :: Maybe Text,
    filter :: Clearable ViewFilter,
    sorts :: Clearable (Vector ViewPropertySort),
    -- | A 'Nothing' value removes that quick filter; 'Clear' removes all of them
    quickFilters :: Clearable (Map Text (Maybe QuickFilter)),
    configuration :: Maybe Value
  }
  deriving stock (Generic, Show)

instance ToJSON UpdateView where
  toJSON = genericToJSON aesonOptions

-- | View query ID
type ViewQueryID = UUID

-- | Body of @POST views/{view_id}/queries@.
newtype CreateViewQuery = CreateViewQuery
  { -- | Results per page (max 100)
    pageSize :: Maybe Natural
  }
  deriving stock (Generic, Show)

instance ToJSON CreateViewQuery where
  toJSON = genericToJSON aesonOptions

-- | Response of @POST views/{view_id}/queries@: a cached server-side snapshot
-- of the rows the view matches, plus its first page of results.
data ViewQuery = ViewQuery
  { id :: ViewQueryID,
    viewId :: ViewID,
    -- | When the cached results expire
    expiresAt :: POSIXTime,
    totalCount :: Natural,
    results :: Vector PartialPageObject,
    nextCursor :: Maybe Text,
    hasMore :: Bool,
    requestStatus :: Maybe RequestStatus
  }
  deriving stock (Generic, Show)

instance FromJSON ViewQuery where
  parseJSON = \case
    Object o -> do
      id <- o .: "id"
      viewId <- o .: "view_id"
      expiresAt <- o .: "expires_at" >>= parseISO8601
      totalCount <- o .: "total_count"
      results <- o .: "results"
      nextCursor <- o .:? "next_cursor"
      hasMore <- o .: "has_more"
      requestStatus <- o .:? "request_status"
      pure ViewQuery {..}
    _ -> fail "Expected object for ViewQuery"

-- | Response of @DELETE views/{view_id}/queries/{query_id}@.
data DeletedViewQuery = DeletedViewQuery
  { id :: ViewQueryID,
    deleted :: Bool
  }
  deriving stock (Generic, Show)

instance FromJSON DeletedViewQuery where
  parseJSON = \case
    Object o -> DeletedViewQuery <$> o .: "id" <*> o .: "deleted"
    _ -> fail "Expected object for DeletedViewQuery"

-- | Servant API
type API =
  "views"
    :> ( ReqBody '[JSON] CreateView
           :> Post '[JSON] ViewObject
           :<|> Capture "view_id" ViewID
           :> Get '[JSON] ViewObject
           :<|> Capture "view_id" ViewID
           :> ReqBody '[JSON] UpdateView
           :> Patch '[JSON] ViewObject
           :<|> Capture "view_id" ViewID
           :> Delete '[JSON] ViewObject
           :<|> QueryParam "database_id" UUID
           :> QueryParam "data_source_id" UUID
           :> QueryParam "start_cursor" Text
           :> QueryParam "page_size" Natural
           :> Get '[JSON] (ListOf ViewObject)
           :<|> Capture "view_id" ViewID
           :> "queries"
           :> ReqBody '[JSON] CreateViewQuery
           :> Post '[JSON] ViewQuery
           :<|> Capture "view_id" ViewID
           :> "queries"
           :> Capture "query_id" ViewQueryID
           :> QueryParam "start_cursor" Text
           :> QueryParam "page_size" Natural
           :> Get '[JSON] (ListOf PartialPageObject)
           :<|> Capture "view_id" ViewID
           :> "queries"
           :> Capture "query_id" ViewQueryID
           :> Delete '[JSON] DeletedViewQuery
       )
