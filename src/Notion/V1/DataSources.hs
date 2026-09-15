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
    _QueryDataSource,
    QueryResultType (..),

    -- * Query and search results
    PageOrDataSource (..),
    PartialPageObject (..),
    PartialDataSourceObject (..),
    pageResults,
    dataSourceResults,
    resultId,
    resultCreatedTime,

    -- * Templates
    TemplateRef (..),
    ListTemplatesResponse (..),

    -- * Servant
    API,
  )
where

import Control.Applicative ((<|>))
import Data.Aeson ((.!=), (.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Parser)
import Data.Map qualified as Map
import Data.Vector qualified as Vector
import Notion.Prelude
import Notion.V1.Common (Cover, Icon, ObjectType, Parent, UUID (..))
import Notion.V1.Databases (DatabaseType)
import Notion.V1.Filter (Filter, Sort)
import Notion.V1.ListOf (ListOf)
import Notion.V1.Pages (PageObject (..), PartialPageObject (..))
import Notion.V1.Properties (PropertySchema)
import Notion.V1.RichText (RichText)
import Notion.V1.Users (UserReference)
import Servant.API (QueryParams)
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
    -- | The kind of typed database this data source belongs to, if any.
    databaseType :: Maybe DatabaseType,
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
      databaseType <- o .:? "database_type"
      inTrash <- (fmap Just (o .: "in_trash")) <|> (fmap Just (o .: "is_archived")) <|> (fmap Just (o .: "archived")) <|> pure Nothing
      publicUrl <- o .:? "public_url"
      icon <- o .:? "icon"
      cover <- o .:? "cover"
      object <- o .: "object"
      return DataSourceObject {..}
    _ -> fail "Expected object for DataSourceObject"

-- | @{"object":"data_source","id":...,"properties":{...}}@
data PartialDataSourceObject = PartialDataSourceObject
  { id :: DataSourceID,
    properties :: Map Text PropertySchema
  }
  deriving stock (Generic, Show)

instance FromJSON PartialDataSourceObject where
  parseJSON = \case
    Object o -> PartialDataSourceObject <$> o .: "id" <*> (o .:? "properties" .!= mempty)
    _ -> fail "Expected object for PartialDataSourceObject"

-- | One result of a data source query or a search.
--
-- A page with a @url@ key, or a data source with a @title@ key, is full and must decode as
-- the full object; otherwise it is partial.
data PageOrDataSource
  = PageResult PageObject
  | PartialPageResult PartialPageObject
  | DataSourceResult DataSourceObject
  | PartialDataSourceResult PartialDataSourceObject
  | -- | An object type this client does not know; the raw JSON is kept.
    UnknownResult Value
  deriving stock (Generic, Show)

instance FromJSON PageOrDataSource where
  parseJSON v = case v of
    Object o -> do
      objectType <- o .:? "object" :: Parser (Maybe Text)
      case objectType of
        Just "page"
          | KeyMap.member "url" o -> PageResult <$> parseJSON v
          | otherwise -> PartialPageResult <$> parseJSON v
        Just "data_source"
          | KeyMap.member "title" o -> DataSourceResult <$> parseJSON v
          | otherwise -> PartialDataSourceResult <$> parseJSON v
        _ -> pure (UnknownResult v)
    _ -> pure (UnknownResult v)

-- | Full pages only.
pageResults :: Vector PageOrDataSource -> Vector PageObject
pageResults = Vector.mapMaybe $ \case
  PageResult p -> Just p
  _ -> Nothing

-- | Full data sources only.
dataSourceResults :: Vector PageOrDataSource -> Vector DataSourceObject
dataSourceResults = Vector.mapMaybe $ \case
  DataSourceResult d -> Just d
  _ -> Nothing

-- | The id of a result, if it has one (unknown results are inspected for a string @id@).
resultId :: PageOrDataSource -> Maybe Text
resultId = \case
  PageResult PageObject {id = UUID t} -> Just t
  PartialPageResult PartialPageObject {id = UUID t} -> Just t
  DataSourceResult DataSourceObject {id = UUID t} -> Just t
  PartialDataSourceResult PartialDataSourceObject {id = UUID t} -> Just t
  UnknownResult (Object o) -> case KeyMap.lookup "id" o of
    Just (String t) -> Just t
    _ -> Nothing
  UnknownResult _ -> Nothing

-- | @created_time@ of a full page or full data source; 'Nothing' for partial and unknown results.
resultCreatedTime :: PageOrDataSource -> Maybe POSIXTime
resultCreatedTime = \case
  PageResult PageObject {createdTime} -> Just createdTime
  DataSourceResult DataSourceObject {createdTime} -> Just createdTime
  _ -> Nothing

-- | Create data source request
data CreateDataSource = CreateDataSource
  { parent :: Parent,
    properties :: Map Text PropertySchema,
    title :: Maybe (Vector RichText),
    -- | Not in Notion's published request schema; omitted when 'Nothing'.
    description :: Maybe (Vector RichText),
    icon :: Maybe Icon,
    -- | Not in Notion's published request schema; omitted when 'Nothing'.
    cover :: Maybe Cover
  }
  deriving stock (Generic, Show)

instance ToJSON CreateDataSource where
  toJSON = genericToJSON aesonOptions

-- | Update data source request.
--
-- The @properties@ field uses @Maybe (Maybe PropertySchema)@ to distinguish between:
--
-- * @Nothing@ (outer): omit the properties field entirely (don't touch properties)
-- * @Just (Map ...)@ with @Just schema@: add or update a property
-- * @Just (Map ...)@ with @Nothing@: delete a property (emits @null@ in JSON)
data UpdateDataSource = UpdateDataSource
  { title :: Maybe (Vector RichText),
    icon :: Maybe Icon,
    properties :: Maybe (Map Text (Maybe PropertySchema)),
    inTrash :: Maybe Bool,
    parent :: Maybe Parent
  }
  deriving stock (Generic, Show)

instance ToJSON UpdateDataSource where
  toJSON UpdateDataSource {..} =
    Aeson.object $
      maybe [] (\t -> ["title" .= t]) title
        <> maybe [] (\i -> ["icon" .= i]) icon
        <> maybe [] (\p -> ["properties" .= mapWithNulls p]) properties
        <> maybe [] (\t -> ["in_trash" .= t]) inTrash
        <> maybe [] (\p -> ["parent" .= p]) parent
    where
      -- Emit Nothing values as JSON null (not omitted)
      mapWithNulls :: Map Text (Maybe PropertySchema) -> Value
      mapWithNulls m =
        Aeson.object $ map (\(k, v) -> Key.fromText k .= v) (Map.toList m)

-- | Query data source request
data QueryDataSource = QueryDataSource
  { filter :: Maybe Filter,
    sorts :: Maybe [Sort],
    startCursor :: Maybe Text,
    pageSize :: Maybe Natural,
    inTrash :: Maybe Bool,
    -- | Limit which properties are returned in the response.
    -- Each element is a property ID (not name).
    filterProperties :: Maybe [Text],
    -- | Return only pages or only data sources. Regular (non-wiki) data sources only
    -- contain pages.
    resultType :: Maybe QueryResultType
  }
  deriving stock (Generic, Show)

-- | A query with every optional field unset. Use record update to set fields.
_QueryDataSource :: QueryDataSource
_QueryDataSource =
  QueryDataSource
    { filter = Nothing,
      sorts = Nothing,
      startCursor = Nothing,
      pageSize = Nothing,
      inTrash = Nothing,
      filterProperties = Nothing,
      resultType = Nothing
    }

-- | Restrict a query to pages or to data sources.
data QueryResultType = ResultTypePage | ResultTypeDataSource
  deriving stock (Eq, Show, Generic)

instance ToJSON QueryResultType where
  toJSON ResultTypePage = Aeson.String "page"
  toJSON ResultTypeDataSource = Aeson.String "data_source"

-- | @filter_properties@ is a query parameter, not a body field; 'Notion.V1.makeMethods'
-- moves 'filterProperties' into the URL.
instance ToJSON QueryDataSource where
  toJSON q = case genericToJSON aesonOptions q of
    Object o -> Object (KeyMap.delete "filter_properties" o)
    other -> other

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
           :> QueryParams "filter_properties" Text
           :> ReqBody '[JSON] QueryDataSource
           :> Post '[JSON] (ListOf PageOrDataSource)
           :<|> Capture "data_source_id" DataSourceID
           :> "templates"
           :> QueryParam "name" Text
           :> QueryParam "start_cursor" Text
           :> QueryParam "page_size" Natural
           :> Get '[JSON] ListTemplatesResponse
       )
