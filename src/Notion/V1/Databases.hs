-- | @\/v1\/databases@
module Notion.V1.Databases
  ( -- * Main types
    DatabaseID,
    DatabaseObject (..),
    DataSource (..),
    InitialDataSource (..),
    CreateDatabase (..),
    UpdateDatabase (..),
    QueryDatabase (..),

    -- * Servant
    API,
  )
where

import Control.Applicative ((<|>))
import Data.Aeson ((.:), (.:?))
import Notion.Prelude
import Notion.V1.Common (Cover, Icon, ObjectType (..), Parent, UUID)
import Notion.V1.ListOf (ListOf)
import Notion.V1.Pages (PageObject)
import Notion.V1.RichText (RichText)
import Notion.V1.Users (UserReference)
import Prelude hiding (id)

-- | Database ID
type DatabaseID = UUID

-- | Data source reference within a database (API version 2025-09-03+)
data DataSource = DataSource
  { id :: UUID,
    name :: Text
  }
  deriving stock (Generic, Show)

instance FromJSON DataSource where
  parseJSON = genericParseJSON aesonOptions

-- | Notion database object
--
-- In API version 2025-09-03, database schema (properties) moved to data sources.
-- The 'properties' field may be absent; use 'dataSources' and the data source
-- endpoints to access schema information.
data DatabaseObject = DatabaseObject
  { id :: DatabaseID,
    createdTime :: POSIXTime,
    lastEditedTime :: POSIXTime,
    createdBy :: Maybe UserReference,
    lastEditedBy :: Maybe UserReference,
    title :: Vector RichText,
    description :: Maybe (Vector RichText),
    properties :: Maybe Value,
    icon :: Maybe Icon,
    cover :: Maybe Cover,
    url :: Text,
    parent :: Parent,
    isInline :: Maybe Bool,
    inTrash :: Maybe Bool,
    isLocked :: Maybe Bool,
    publicUrl :: Maybe Text,
    dataSources :: Vector DataSource,
    object :: ObjectType
  }
  deriving stock (Generic, Show)

instance FromJSON DatabaseObject where
  parseJSON = \case
    Object o -> do
      id <- o .: "id"
      createdTimeStr <- o .: "created_time"
      createdTime <- parseISO8601 createdTimeStr
      lastEditedTimeStr <- o .: "last_edited_time"
      lastEditedTime <- parseISO8601 lastEditedTimeStr
      createdBy <- o .:? "created_by"
      lastEditedBy <- o .:? "last_edited_by"
      title <- o .: "title"
      description <- o .:? "description"
      properties <- o .:? "properties"
      icon <- o .:? "icon"
      cover <- o .:? "cover"
      url <- o .: "url"
      parent <- o .: "parent"
      isInline <- o .:? "is_inline"
      inTrash <- (fmap Just (o .: "in_trash")) <|> (fmap Just (o .: "is_archived")) <|> (fmap Just (o .: "archived")) <|> pure Nothing
      isLocked <- o .:? "is_locked"
      publicUrl <- o .:? "public_url"
      dataSources <- o .: "data_sources"
      object <- o .: "object"
      return DatabaseObject {..}
    _ -> fail "Expected object for DatabaseObject"

-- | Initial data source configuration for database creation.
-- Contains the property schema for the database's first data source.
newtype InitialDataSource = InitialDataSource
  { properties :: Value
  }
  deriving stock (Generic, Show)

instance ToJSON InitialDataSource where
  toJSON = genericToJSON aesonOptions

-- | Create database request
--
-- In API version 2025-09-03, schema is specified via 'initialDataSource'
-- rather than a top-level @properties@ field.
data CreateDatabase = CreateDatabase
  { parent :: Parent,
    title :: Vector RichText,
    initialDataSource :: Maybe InitialDataSource,
    icon :: Maybe Icon,
    cover :: Maybe Cover,
    description :: Maybe (Vector RichText),
    isInline :: Maybe Bool
  }
  deriving stock (Generic, Show)

instance ToJSON CreateDatabase where
  toJSON = genericToJSON aesonOptions

-- | Update database request
--
-- In API version 2025-09-03, schema updates (properties) are handled via
-- the Update Data Source API ('Notion.V1.DataSources.UpdateDataSource').
-- This endpoint only handles database-level attributes.
data UpdateDatabase = UpdateDatabase
  { title :: Maybe (Vector RichText),
    icon :: Maybe Icon,
    cover :: Maybe Cover,
    description :: Maybe (Vector RichText),
    isInline :: Maybe Bool,
    inTrash :: Maybe Bool,
    parent :: Maybe Parent
  }
  deriving stock (Generic, Show)

instance ToJSON UpdateDatabase where
  toJSON = genericToJSON aesonOptions

-- | Query database request
data QueryDatabase = QueryDatabase
  { filter :: Maybe Value,
    sorts :: Maybe [Value],
    startCursor :: Maybe Text,
    pageSize :: Maybe Natural
  }
  deriving stock (Generic, Show)

instance ToJSON QueryDatabase where
  toJSON = genericToJSON aesonOptions

-- | Servant API
type API =
  "databases"
    :> ( ReqBody '[JSON] CreateDatabase
           :> Post '[JSON] DatabaseObject
           :<|> Capture "database_id" DatabaseID
           :> Get '[JSON] DatabaseObject
           :<|> Capture "database_id" DatabaseID
           :> ReqBody '[JSON] UpdateDatabase
           :> Patch '[JSON] DatabaseObject
           :<|> Capture "database_id" DatabaseID
           :> "query"
           :> ReqBody '[JSON] QueryDatabase
           :> Post '[JSON] (ListOf PageObject)
       )
