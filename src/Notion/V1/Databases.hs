-- | @\/v1\/databases@
module Notion.V1.Databases
  ( -- * Main types
    DatabaseID,
    DatabaseObject (..),
    PartialDatabaseObject (..),
    DatabaseType (..),
    CreateDatabaseType (..),
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
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Notion.Prelude
import Notion.V1.Common (Cover, Icon, ObjectType (..), Parent, UUID)
import Notion.V1.Filter (Filter, Sort)
import Notion.V1.ListOf (ListOf)
import Notion.V1.Pages (PageObject)
import Notion.V1.Properties (PropertySchema)
import Notion.V1.RichText (RichText)
import Notion.V1.Users (UserReference)
import Servant.API (QueryParams)
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
    properties :: Maybe (Map Text PropertySchema),
    icon :: Maybe Icon,
    cover :: Maybe Cover,
    url :: Text,
    parent :: Parent,
    isInline :: Maybe Bool,
    -- | The kind of typed database (@tasks@, @wiki@, ...), if any.
    databaseType :: Maybe DatabaseType,
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
      databaseType <- o .:? "database_type"
      inTrash <- (fmap Just (o .: "in_trash")) <|> (fmap Just (o .: "is_archived")) <|> (fmap Just (o .: "archived")) <|> pure Nothing
      isLocked <- o .:? "is_locked"
      publicUrl <- o .:? "public_url"
      dataSources <- o .: "data_sources"
      object <- o .: "object"
      return DatabaseObject {..}
    _ -> fail "Expected object for DatabaseObject"

-- | @{"object":"database","id":...}@
--
-- The minimal database shape Notion returns when the integration cannot see the full object.
newtype PartialDatabaseObject = PartialDatabaseObject {id :: DatabaseID}
  deriving stock (Generic, Show)

instance FromJSON PartialDatabaseObject where
  parseJSON = Aeson.withObject "PartialDatabaseObject" $ \o -> PartialDatabaseObject <$> o .: "id"

-- | The kind of typed database, or an unrecognised value.
data DatabaseType
  = TasksDatabase
  | ProjectsDatabase
  | SprintsDatabase
  | DocsDatabase
  | WikiDatabase
  | MeetingsDatabase
  | MeetingNotesDatabase
  | SkillsDatabase
  | GithubPrsDatabase
  | -- | A database type this library does not know yet; holds the raw string.
    UnknownDatabaseType Text
  deriving stock (Eq, Show, Generic)

instance FromJSON DatabaseType where
  parseJSON = Aeson.withText "DatabaseType" $ \case
    "tasks" -> pure TasksDatabase
    "projects" -> pure ProjectsDatabase
    "sprints" -> pure SprintsDatabase
    "docs" -> pure DocsDatabase
    "wiki" -> pure WikiDatabase
    "meetings" -> pure MeetingsDatabase
    "meeting_notes" -> pure MeetingNotesDatabase
    "skills" -> pure SkillsDatabase
    "github_prs" -> pure GithubPrsDatabase
    other -> pure (UnknownDatabaseType other)

instance ToJSON DatabaseType where
  toJSON =
    Aeson.String . \case
      TasksDatabase -> "tasks"
      ProjectsDatabase -> "projects"
      SprintsDatabase -> "sprints"
      DocsDatabase -> "docs"
      WikiDatabase -> "wiki"
      MeetingsDatabase -> "meetings"
      MeetingNotesDatabase -> "meeting_notes"
      SkillsDatabase -> "skills"
      GithubPrsDatabase -> "github_prs"
      UnknownDatabaseType t -> t

-- | Typed database kinds accepted by @POST \/v1\/databases@.
data CreateDatabaseType = CreateTasksDatabase | CreateProjectsDatabase | CreateSkillsDatabase
  deriving stock (Eq, Show, Generic)

instance ToJSON CreateDatabaseType where
  toJSON =
    Aeson.String . \case
      CreateTasksDatabase -> "tasks"
      CreateProjectsDatabase -> "projects"
      CreateSkillsDatabase -> "skills"

-- | Initial data source configuration for database creation.
-- Contains the property schema for the database's first data source.
newtype InitialDataSource = InitialDataSource
  { properties :: Maybe (Map Text PropertySchema)
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
    -- | When omitted for a typed database, Notion names it after the type.
    title :: Maybe (Vector RichText),
    initialDataSource :: Maybe InitialDataSource,
    icon :: Maybe Icon,
    cover :: Maybe Cover,
    description :: Maybe (Vector RichText),
    isInline :: Maybe Bool,
    -- | Create a typed database. Cannot be combined with 'initialDataSource'.
    databaseType :: Maybe CreateDatabaseType
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
    isLocked :: Maybe Bool,
    inTrash :: Maybe Bool,
    parent :: Maybe Parent
  }
  deriving stock (Generic, Show)

instance ToJSON UpdateDatabase where
  toJSON = genericToJSON aesonOptions

-- | Query database request
data QueryDatabase = QueryDatabase
  { filter :: Maybe Filter,
    sorts :: Maybe [Sort],
    startCursor :: Maybe Text,
    pageSize :: Maybe Natural,
    -- | Limit which properties are returned in the response.
    -- Each element is a property ID (not name).
    filterProperties :: Maybe [Text]
  }
  deriving stock (Generic, Show)

-- | @filter_properties@ is a query parameter, not a body field; 'Notion.V1.makeMethods'
-- moves 'filterProperties' into the URL.
instance ToJSON QueryDatabase where
  toJSON q = case genericToJSON aesonOptions q of
    Object o -> Object (KeyMap.delete "filter_properties" o)
    other -> other

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
           :> QueryParams "filter_properties" Text
           :> ReqBody '[JSON] QueryDatabase
           :> Post '[JSON] (ListOf PageObject)
       )
