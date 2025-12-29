-- | @\/v1\/databases@
module Notion.V1.Databases
  ( -- * Main types
    DatabaseID,
    DatabaseObject (..),
    DataSource (..),
    CreateDatabase (..),
    UpdateDatabase (..),
    QueryDatabase (..),

    -- * Servant
    API,
  )
where

import Data.Aeson (Object, (.:), (.:?))
import Notion.Prelude
import Notion.V1.Common (Cover, Icon, ObjectType (..), Parent, UUID)
import Notion.V1.ListOf (ListOf)
import Notion.V1.Pages (PageObject)
import Notion.V1.Users (UserReference)

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
data DatabaseObject = DatabaseObject
  { id :: DatabaseID,
    createdTime :: POSIXTime,
    lastEditedTime :: POSIXTime,
    createdBy :: UserReference,
    lastEditedBy :: UserReference,
    title :: Value,
    description :: Value,
    properties :: Value,
    url :: Text,
    parent :: Parent,
    archived :: Bool,
    isInline :: Maybe Bool,
    inTrash :: Maybe Bool,
    publicUrl :: Maybe Text,
    dataSources :: Maybe (Vector DataSource),
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
      createdBy <- o .: "created_by"
      lastEditedBy <- o .: "last_edited_by"
      title <- o .: "title"
      description <- o .: "description"
      properties <- o .: "properties"
      url <- o .: "url"
      parent <- o .: "parent"
      archived <- o .: "archived"
      isInline <- o .:? "is_inline"
      inTrash <- o .:? "in_trash"
      publicUrl <- o .:? "public_url"
      dataSources <- o .:? "data_sources"
      object <- o .: "object"
      return DatabaseObject {..}
    _ -> fail "Expected object for DatabaseObject"

-- | Create database request
data CreateDatabase = CreateDatabase
  { parent :: Parent,
    title :: Value,
    properties :: Value,
    icon :: Maybe Icon,
    cover :: Maybe Cover,
    description :: Maybe Value,
    isInline :: Maybe Bool
  }
  deriving stock (Generic, Show)

instance ToJSON CreateDatabase where
  toJSON = genericToJSON aesonOptions

-- | Update database request
data UpdateDatabase = UpdateDatabase
  { title :: Maybe Value,
    properties :: Maybe Value,
    icon :: Maybe Icon,
    cover :: Maybe Cover,
    description :: Maybe Value,
    archived :: Maybe Bool,
    isInline :: Maybe Bool
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
