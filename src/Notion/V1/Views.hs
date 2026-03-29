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
    QueryView (..),

    -- * Servant
    API,
  )
where

import Data.Aeson ((.:), (.:?))
import Notion.Prelude
import Notion.V1.Common (ObjectType, UUID)
import Notion.V1.ListOf (ListOf)
import Notion.V1.Pages (PageObject)
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
  deriving stock (Eq, Show, Generic)

instance FromJSON ViewType where
  parseJSON = \case
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
    other -> fail $ "Unknown view type: " <> show other

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

-- | Notion view object
--
-- Many fields are 'Maybe' because the API returns partial or full view objects
-- depending on context (list endpoints return minimal objects with just id, parent, type).
data ViewObject = ViewObject
  { id :: ViewID,
    parent :: Maybe Value,
    name :: Maybe Text,
    type_ :: Maybe ViewType,
    createdTime :: Maybe POSIXTime,
    lastEditedTime :: Maybe POSIXTime,
    url :: Maybe Text,
    dataSourceId :: Maybe UUID,
    createdBy :: Maybe UserReference,
    lastEditedBy :: Maybe UserReference,
    filter :: Maybe Value,
    sorts :: Maybe (Vector Value),
    quickFilters :: Maybe Value,
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
    databaseId :: Maybe UUID,
    viewId :: Maybe ViewID,
    filter :: Maybe Value,
    sorts :: Maybe (Vector Value),
    quickFilters :: Maybe Value,
    configuration :: Maybe Value,
    position :: Maybe Value
  }
  deriving stock (Generic, Show)

instance ToJSON CreateView where
  toJSON = genericToJSON aesonOptions

-- | Update a view request (all fields optional)
data UpdateView = UpdateView
  { name :: Maybe Text,
    filter :: Maybe Value,
    sorts :: Maybe (Vector Value),
    quickFilters :: Maybe Value,
    configuration :: Maybe Value
  }
  deriving stock (Generic, Show)

instance ToJSON UpdateView where
  toJSON = genericToJSON aesonOptions

-- | Query a view request (pagination only, view's own filters/sorts are used)
data QueryView = QueryView
  { startCursor :: Maybe Text,
    pageSize :: Maybe Natural
  }
  deriving stock (Generic, Show)

instance ToJSON QueryView where
  toJSON = genericToJSON aesonOptions

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
           :> "query"
           :> ReqBody '[JSON] QueryView
           :> Post '[JSON] (ListOf PageObject)
       )
