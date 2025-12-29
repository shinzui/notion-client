-- | @\/v1\/databases@
module Notion.V1.Databases
  ( -- * Main types
    DatabaseID,
    DatabaseObject (..),
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

-- | Notion database object
data DatabaseObject = DatabaseObject
  { id :: DatabaseID,
    created_time :: POSIXTime,
    last_edited_time :: POSIXTime,
    created_by :: UserReference,
    last_edited_by :: UserReference,
    title :: Value,
    description :: Value,
    properties :: Value,
    url :: Text,
    parent :: Parent,
    archived :: Bool,
    is_inline :: Maybe Bool,
    in_trash :: Maybe Bool,
    public_url :: Maybe Text,
    object :: ObjectType
  }
  deriving stock (Generic, Show)

instance FromJSON DatabaseObject where
  parseJSON = \case
    Object o -> do
      id <- o .: "id"
      created_time_str <- o .: "created_time"
      created_time <- parseISO8601 created_time_str
      last_edited_time_str <- o .: "last_edited_time"
      last_edited_time <- parseISO8601 last_edited_time_str
      created_by <- o .: "created_by"
      last_edited_by <- o .: "last_edited_by"
      title <- o .: "title"
      description <- o .: "description"
      properties <- o .: "properties"
      url <- o .: "url"
      parent <- o .: "parent"
      archived <- o .: "archived"
      is_inline <- o .:? "is_inline"
      in_trash <- o .:? "in_trash"
      public_url <- o .:? "public_url"
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
    is_inline :: Maybe Bool
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
    is_inline :: Maybe Bool
  }
  deriving stock (Generic, Show)

instance ToJSON UpdateDatabase where
  toJSON = genericToJSON aesonOptions

-- | Query database request
data QueryDatabase = QueryDatabase
  { filter :: Maybe Value,
    sorts :: Maybe [Value],
    start_cursor :: Maybe Text,
    page_size :: Maybe Natural
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
