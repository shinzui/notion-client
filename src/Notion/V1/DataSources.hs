-- | @\/v1\/data_sources@
--
-- Data sources represent the schema and content within a database.
-- A single database can contain multiple data sources (API version 2025-09-03+).
module Notion.V1.DataSources
  ( -- * Main types
    DataSourceID,
    DataSourceObject (..),
    CreateDataSource (..),
    UpdateDataSource (..),
    QueryDataSource (..),

    -- * Templates
    TemplateRef (..),
    ListTemplatesResponse (..),

    -- * Servant
    API,
  )
where

import Control.Applicative ((<|>))
import Data.Aeson ((.:), (.:?))
import Notion.Prelude
import Notion.V1.Common (Cover, Icon, ObjectType, Parent, UUID)
import Notion.V1.Filter (Filter, Sort)
import Notion.V1.ListOf (ListOf)
import Notion.V1.Pages (PageObject)
import Notion.V1.Properties (PropertySchema)
import Notion.V1.RichText (RichText)
import Notion.V1.Users (UserReference)
import Prelude hiding (id)

-- | Data source ID
type DataSourceID = UUID

-- | Notion data source object
data DataSourceObject = DataSourceObject
  { id :: DataSourceID,
    createdTime :: POSIXTime,
    lastEditedTime :: POSIXTime,
    createdBy :: UserReference,
    lastEditedBy :: UserReference,
    title :: Vector RichText,
    description :: Vector RichText,
    properties :: Map Text PropertySchema,
    url :: Text,
    parent :: Parent,
    databaseParent :: Maybe Parent,
    isInline :: Maybe Bool,
    inTrash :: Maybe Bool,
    publicUrl :: Maybe Text,
    icon :: Maybe Icon,
    cover :: Maybe Cover,
    object :: ObjectType
  }
  deriving stock (Generic, Show)

instance FromJSON DataSourceObject where
  parseJSON = \case
    Object o -> do
      id <- o .: "id"
      createdTimeStr <- o .: "created_time"
      createdTime <- parseISO8601 createdTimeStr
      lastEditedTimeStr <- o .: "last_edited_time"
      lastEditedTime <- parseISO8601 lastEditedTimeStr
      createdBy <- o .: "created_by"
      lastEditedBy <- o .: "last_edited_by"
      title <- o .: "title"
      description <- o .: "description"
      properties <- o .: "properties"
      url <- o .: "url"
      parent <- o .: "parent"
      databaseParent <- o .:? "database_parent"
      isInline <- o .:? "is_inline"
      inTrash <- (fmap Just (o .: "in_trash")) <|> (fmap Just (o .: "is_archived")) <|> (fmap Just (o .: "archived")) <|> pure Nothing
      publicUrl <- o .:? "public_url"
      icon <- o .:? "icon"
      cover <- o .:? "cover"
      object <- o .: "object"
      return DataSourceObject {..}
    _ -> fail "Expected object for DataSourceObject"

-- | Create data source request
data CreateDataSource = CreateDataSource
  { parent :: Parent,
    properties :: Map Text PropertySchema,
    title :: Maybe (Vector RichText),
    icon :: Maybe Icon
  }
  deriving stock (Generic, Show)

instance ToJSON CreateDataSource where
  toJSON = genericToJSON aesonOptions

-- | Update data source request
data UpdateDataSource = UpdateDataSource
  { title :: Maybe (Vector RichText),
    icon :: Maybe Icon,
    properties :: Maybe (Map Text PropertySchema),
    inTrash :: Maybe Bool,
    parent :: Maybe Parent
  }
  deriving stock (Generic, Show)

instance ToJSON UpdateDataSource where
  toJSON = genericToJSON aesonOptions

-- | Query data source request
data QueryDataSource = QueryDataSource
  { filter :: Maybe Filter,
    sorts :: Maybe [Sort],
    startCursor :: Maybe Text,
    pageSize :: Maybe Natural,
    inTrash :: Maybe Bool
  }
  deriving stock (Generic, Show)

instance ToJSON QueryDataSource where
  toJSON = genericToJSON aesonOptions

-- | A reference to a data source template
data TemplateRef = TemplateRef
  { id :: UUID,
    name :: Text,
    isDefault :: Bool
  }
  deriving stock (Generic, Show)

instance FromJSON TemplateRef where
  parseJSON = genericParseJSON aesonOptions

-- | Response from @GET \/v1\/data_sources\/{data_source_id}\/templates@
data ListTemplatesResponse = ListTemplatesResponse
  { templates :: Vector TemplateRef,
    hasMore :: Bool,
    nextCursor :: Maybe Text
  }
  deriving stock (Generic, Show)

instance FromJSON ListTemplatesResponse where
  parseJSON = genericParseJSON aesonOptions

-- | Servant API
type API =
  "data_sources"
    :> ( Capture "data_source_id" DataSourceID
           :> Get '[JSON] DataSourceObject
           :<|> ReqBody '[JSON] CreateDataSource
           :> Post '[JSON] DataSourceObject
           :<|> Capture "data_source_id" DataSourceID
           :> ReqBody '[JSON] UpdateDataSource
           :> Patch '[JSON] DataSourceObject
           :<|> Capture "data_source_id" DataSourceID
           :> "query"
           :> ReqBody '[JSON] QueryDataSource
           :> Post '[JSON] (ListOf PageObject)
           :<|> Capture "data_source_id" DataSourceID
           :> "templates"
           :> QueryParam "name" Text
           :> QueryParam "start_cursor" Text
           :> QueryParam "page_size" Natural
           :> Get '[JSON] ListTemplatesResponse
       )
