-- | Data sources, databases, search, property schemas, filters and the full-row helper (EP-5).
module DataSourceSearchTests (tests) where

import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy.Char8 qualified as L8
import Data.Map qualified as Map
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import Notion.V1.Common (Parent (..))
import Notion.V1.DataSources
import Notion.V1.Databases (CreateDatabase (..), CreateDatabaseType (..), DatabaseObject (..), DatabaseType (..), InitialDataSource (..), PartialDatabaseObject (..))
import Notion.V1.ListOf (IncompleteReason (..), ListOf (..), RequestStatus (..), RequestStatusType (..))
import Notion.V1.Properties
import Notion.V1.Search (SearchFilter (..), SearchObjectType (..), SearchSort (..), SearchSortDirection (..))
import Test.Tasty
import Test.Tasty.HUnit
import Prelude hiding (id)

tests :: TestTree
tests =
  testGroup
    "EP-5 Data sources, databases, search, filters"
    [ milestone1Tests,
      milestone2Tests,
      milestone3Tests
    ]

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------

decodeOrFail :: (Aeson.FromJSON a) => L8.ByteString -> IO a
decodeOrFail bs = either (assertFailure . ("decode failed: " <>)) pure (Aeson.eitherDecode bs)

fromValueOrFail :: (Aeson.FromJSON a) => Aeson.Value -> IO a
fromValueOrFail v = case Aeson.fromJSON v of
  Aeson.Success a -> pure a
  Aeson.Error e -> assertFailure ("decode failed: " <> e)

objectOf :: Aeson.Value -> IO Aeson.Object
objectOf = \case
  Aeson.Object o -> pure o
  other -> assertFailure ("expected object, got " <> show other)

userJson :: Aeson.Value
userJson = Aeson.object ["object" Aeson..= ("user" :: Text.Text), "id" Aeson..= ("user-1" :: Text.Text)]

-- | A full page with every field the page decoder requires.
pageJson :: Text.Text -> Text.Text -> Aeson.Value
pageJson pid created =
  Aeson.object
    [ "object" Aeson..= ("page" :: Text.Text),
      "id" Aeson..= pid,
      "created_time" Aeson..= created,
      "last_edited_time" Aeson..= created,
      "created_by" Aeson..= userJson,
      "last_edited_by" Aeson..= userJson,
      "cover" Aeson..= Aeson.Null,
      "icon" Aeson..= Aeson.Null,
      "parent" Aeson..= Aeson.object ["type" Aeson..= ("data_source_id" :: Text.Text), "data_source_id" Aeson..= ("ds-1" :: Text.Text), "database_id" Aeson..= ("db-1" :: Text.Text)],
      "in_trash" Aeson..= False,
      "is_locked" Aeson..= False,
      "properties" Aeson..= Aeson.object [],
      "url" Aeson..= ("https://www.notion.so/" <> pid),
      "public_url" Aeson..= Aeson.Null
    ]

-- | A full data source with every field the data source decoder requires.
dataSourceJson :: Text.Text -> Text.Text -> Aeson.Value
dataSourceJson dsid created =
  Aeson.object
    [ "object" Aeson..= ("data_source" :: Text.Text),
      "id" Aeson..= dsid,
      "created_time" Aeson..= created,
      "last_edited_time" Aeson..= created,
      "created_by" Aeson..= userJson,
      "last_edited_by" Aeson..= userJson,
      "title" Aeson..= ([] :: [Aeson.Value]),
      "description" Aeson..= ([] :: [Aeson.Value]),
      "properties" Aeson..= Aeson.object [],
      "parent" Aeson..= Aeson.object ["type" Aeson..= ("database_id" :: Text.Text), "database_id" Aeson..= ("db-1" :: Text.Text)],
      "database_parent" Aeson..= Aeson.object ["type" Aeson..= ("page_id" :: Text.Text), "page_id" Aeson..= ("page-0" :: Text.Text)],
      "is_inline" Aeson..= False,
      "in_trash" Aeson..= False,
      "database_type" Aeson..= ("wiki" :: Text.Text),
      "icon" Aeson..= Aeson.Null,
      "cover" Aeson..= Aeson.Null,
      "url" Aeson..= ("https://www.notion.so/" <> dsid),
      "public_url" Aeson..= Aeson.Null
    ]

databaseJson :: Aeson.Value -> Aeson.Value
databaseJson dbType =
  Aeson.object
    [ "object" Aeson..= ("database" :: Text.Text),
      "id" Aeson..= ("db-1" :: Text.Text),
      "created_time" Aeson..= ("2024-01-01T00:00:00.000Z" :: Text.Text),
      "last_edited_time" Aeson..= ("2024-01-01T00:00:00.000Z" :: Text.Text),
      "title" Aeson..= ([] :: [Aeson.Value]),
      "url" Aeson..= ("https://www.notion.so/db-1" :: Text.Text),
      "parent" Aeson..= Aeson.object ["type" Aeson..= ("page_id" :: Text.Text), "page_id" Aeson..= ("p1" :: Text.Text)],
      "data_sources" Aeson..= [Aeson.object ["id" Aeson..= ("ds-1" :: Text.Text), "name" Aeson..= ("Tanaka Hanako Tasks" :: Text.Text)]],
      "database_type" Aeson..= dbType
    ]

-- | A list response with the given results and the @page_or_data_source@ envelope.
queryResponse :: [Aeson.Value] -> Maybe Text.Text -> Bool -> Aeson.Value
queryResponse rows cursor incomplete =
  Aeson.object $
    [ "object" Aeson..= ("list" :: Text.Text),
      "type" Aeson..= ("page_or_data_source" :: Text.Text),
      "page_or_data_source" Aeson..= Aeson.object [],
      "results" Aeson..= rows,
      "has_more" Aeson..= maybe False (const True) cursor,
      "next_cursor" Aeson..= cursor
    ]
      <> [ "request_status"
             Aeson..= Aeson.object
               [ "type" Aeson..= ("incomplete" :: Text.Text),
                 "incomplete_reason" Aeson..= ("query_result_limit_reached" :: Text.Text)
               ]
         | incomplete
         ]

-- | One result of every kind, in the order full page, partial page, full data source,
-- partial data source, unknown.
everyResultKind :: [Aeson.Value]
everyResultKind =
  [ pageJson "r1" "2024-01-01T00:00:00.000Z",
    Aeson.object ["object" Aeson..= ("page" :: Text.Text), "id" Aeson..= ("r2" :: Text.Text)],
    dataSourceJson "ds-child" "2024-01-02T00:00:00.000Z",
    Aeson.object ["object" Aeson..= ("data_source" :: Text.Text), "id" Aeson..= ("ds-3" :: Text.Text), "properties" Aeson..= Aeson.object []],
    Aeson.object ["object" Aeson..= ("view" :: Text.Text), "id" Aeson..= ("v1" :: Text.Text)]
  ]

resultKind :: PageOrDataSource -> String
resultKind = \case
  PageResult _ -> "page"
  PartialPageResult _ -> "partial page"
  DataSourceResult _ -> "data_source"
  PartialDataSourceResult _ -> "partial data_source"
  UnknownResult _ -> "unknown"

-- ---------------------------------------------------------------------
-- Milestone 1
-- ---------------------------------------------------------------------

milestone1Tests :: TestTree
milestone1Tests =
  testGroup
    "Milestone 1"
    [ testCase "DatabaseObject decodes database_type" $ do
        DatabaseObject {databaseType = t} <- fromValueOrFail (databaseJson (Aeson.String "tasks"))
        t @?= Just TasksDatabase,
      testCase "DatabaseObject decodes null database_type" $ do
        DatabaseObject {databaseType = t} <- fromValueOrFail (databaseJson Aeson.Null)
        t @?= Nothing,
      testCase "DatabaseType falls back on unknown values" $
        Aeson.eitherDecode "\"roadmaps\"" @?= Right (UnknownDatabaseType "roadmaps"),
      testCase "DataSourceObject decodes database_type" $ do
        DataSourceObject {databaseType = t} <- fromValueOrFail (dataSourceJson "ds-9" "2024-01-01T00:00:00.000Z")
        t @?= Just WikiDatabase,
      testCase "CreateDatabase encodes database_type without title" $ do
        o <-
          objectOf $
            Aeson.toJSON
              CreateDatabase
                { parent = PageParent {pageId = "p1"},
                  title = Nothing,
                  initialDataSource = Nothing,
                  icon = Nothing,
                  cover = Nothing,
                  description = Nothing,
                  isInline = Nothing,
                  databaseType = Just CreateTasksDatabase
                }
        KeyMap.lookup "database_type" o @?= Just (Aeson.String "tasks")
        KeyMap.member "title" o @?= False
        KeyMap.keys o @?= ["database_type", "parent"],
      testCase "InitialDataSource without properties encodes as {}" $
        Aeson.toJSON (InitialDataSource {properties = Nothing}) @?= Aeson.object [],
      testCase "QueryDataSource encodes result_type" $ do
        o <- objectOf (Aeson.toJSON _QueryDataSource {resultType = Just ResultTypeDataSource})
        KeyMap.lookup "result_type" o @?= Just (Aeson.String "data_source"),
      testCase "Query response decodes every result kind" $ do
        list <- fromValueOrFail @(ListOf PageOrDataSource) (queryResponse everyResultKind Nothing False)
        let rs = Vector.toList (results list)
        map resultKind rs @?= ["page", "partial page", "data_source", "partial data_source", "unknown"]
        map resultId rs @?= map Just ["r1", "r2", "ds-child", "ds-3", "v1"],
      testCase "pageResults keeps only full pages" $ do
        list <- fromValueOrFail @(ListOf PageOrDataSource) (queryResponse everyResultKind Nothing False)
        Vector.length (pageResults (results list)) @?= 1
        Vector.length (dataSourceResults (results list)) @?= 1,
      testCase "PartialDatabaseObject decodes" $ do
        PartialDatabaseObject {id = dbId} <- decodeOrFail "{\"object\":\"database\",\"id\":\"db-2\"}"
        dbId @?= "db-2"
    ]

-- ---------------------------------------------------------------------
-- Milestone 2
-- ---------------------------------------------------------------------

milestone2Tests :: TestTree
milestone2Tests =
  testGroup
    "Milestone 2"
    [ testCase "SearchSort relevance encodes" $
        Aeson.toJSON SearchByRelevance @?= Aeson.object ["property" Aeson..= ("relevance" :: Text.Text)],
      testCase "SearchSort last_edited_time encodes" $
        Aeson.toJSON (SearchByLastEditedTime Descending)
          @?= Aeson.object ["timestamp" Aeson..= ("last_edited_time" :: Text.Text), "direction" Aeson..= ("descending" :: Text.Text)],
      testCase "SearchFilter object filter with in_trash" $
        Aeson.toJSON (SearchObjectFilter SearchPage (Just True))
          @?= Aeson.object ["property" Aeson..= ("object" :: Text.Text), "value" Aeson..= ("page" :: Text.Text), "in_trash" Aeson..= True],
      testCase "SearchFilter standalone in_trash" $
        Aeson.toJSON (SearchInTrashFilter False) @?= Aeson.object ["in_trash" Aeson..= False],
      testCase "Search response decodes typed results" $ do
        list <- fromValueOrFail @(ListOf PageOrDataSource) (queryResponse everyResultKind Nothing True)
        Vector.length (results list) @?= 5
        map resultKind (Vector.toList (results list)) @?= ["page", "partial page", "data_source", "partial data_source", "unknown"]
        requestStatus list @?= Just RequestStatus {type_ = RequestIncomplete, incompleteReason = Just QueryResultLimitReached}
    ]

-- ---------------------------------------------------------------------
-- Milestone 3
-- ---------------------------------------------------------------------

-- | The value stored under @key@ in an encoded object.
lookupKey :: Aeson.Key -> Aeson.Value -> IO Aeson.Value
lookupKey key v = do
  o <- objectOf v
  maybe (assertFailure ("missing key " <> show key <> " in " <> show v)) pure (KeyMap.lookup key o)

updateWithProperties :: Map.Map Text.Text PropertyUpdate -> UpdateDataSource
updateWithProperties ps = UpdateDataSource {title = Nothing, icon = Nothing, properties = Just ps, inTrash = Nothing, parent = Nothing}

milestone3Tests :: TestTree
milestone3Tests =
  testGroup
    "Milestone 3"
    [ testCase "Property schema decodes description" $ do
        schema <- decodeOrFail "{\"id\":\"a1\",\"name\":\"Owner\",\"description\":\"Sato Kenji's column\",\"type\":\"people\",\"people\":{}}"
        schemaDescription schema @?= Just "Sato Kenji's column",
      testCase "Select and status options decode description" $ do
        sel <- decodeOrFail "{\"id\":\"s\",\"name\":\"State\",\"description\":null,\"type\":\"select\",\"select\":{\"options\":[{\"id\":\"o1\",\"name\":\"Done\",\"color\":\"green\",\"description\":null}]}}"
        case sel of
          SelectSchema {selectOptions} ->
            Vector.toList selectOptions @?= [SelectOption {id = Just "o1", name = "Done", color = Just Green, description = Nothing}]
          other -> assertFailure ("expected SelectSchema, got " <> show other)
        st <- decodeOrFail "{\"id\":\"t\",\"name\":\"Status\",\"description\":null,\"type\":\"status\",\"status\":{\"options\":[{\"id\":\"o2\",\"name\":\"Finished\",\"color\":\"blue\",\"description\":\"finished\"}],\"groups\":[{\"id\":\"g1\",\"name\":\"Complete\",\"color\":\"blue\",\"option_ids\":[\"o2\"]}]}}"
        case st of
          StatusSchema {statusOptions, statusGroups} -> do
            fmap (\SelectOption {description} -> description) (Vector.toList statusOptions) @?= [Just "finished"]
            fmap (\StatusGroup {optionIds} -> optionIds) (Vector.toList statusGroups) @?= [Vector.fromList ["o2"]]
          other -> assertFailure ("expected StatusSchema, got " <> show other),
      testCase "Relation schema decodes database_id" $ do
        schema <- decodeOrFail "{\"id\":\"r1\",\"name\":\"Tasks\",\"description\":null,\"type\":\"relation\",\"relation\":{\"database_id\":\"db-1\",\"data_source_id\":\"ds-1\",\"type\":\"dual_property\",\"dual_property\":{\"synced_property_id\":\"sp1\",\"synced_property_name\":\"Related\"}}}"
        case schema of
          RelationSchema {relationDatabaseId, relationType} -> do
            relationDatabaseId @?= Just "db-1"
            relationType @?= DualProperty {syncedPropertyId = Just "sp1", syncedPropertyName = Just "Related"}
          other -> assertFailure ("expected RelationSchema, got " <> show other),
      testCase "Dual property with no synced fields encodes empty dual_property" $ do
        let schema =
              RelationSchema
                { schemaId = "",
                  schemaName = "Tasks",
                  schemaDescription = Nothing,
                  relationDataSourceId = "ds-1",
                  relationDatabaseId = Nothing,
                  relationType = DualProperty {syncedPropertyId = Nothing, syncedPropertyName = Nothing}
                }
        relation <- lookupKey "relation" (Aeson.toJSON schema)
        dual <- lookupKey "dual_property" relation
        dual @?= Aeson.object [],
      testCase "Status schema without groups encodes options only" $ do
        let schema =
              StatusSchema
                { schemaId = "",
                  schemaName = "Status",
                  schemaDescription = Nothing,
                  statusOptions = Vector.fromList [SelectOption {id = Nothing, name = "Todo", color = Nothing, description = Nothing}],
                  statusGroups = Vector.empty
                }
        status <- lookupKey "status" (Aeson.toJSON schema)
        status @?= Aeson.object ["options" Aeson..= [Aeson.object ["name" Aeson..= ("Todo" :: Text.Text)]]],
      testCase "Empty schema id is omitted" $ do
        o <- objectOf (Aeson.toJSON TitleSchema {schemaId = "", schemaName = "Name", schemaDescription = Nothing})
        KeyMap.member "id" o @?= False,
      testCase "Location and last_visited_time schemas encode" $ do
        loc <- objectOf (Aeson.toJSON LocationSchema {schemaId = "", schemaName = "Where", schemaDescription = Nothing})
        KeyMap.lookup "type" loc @?= Just (Aeson.String "location")
        KeyMap.lookup "location" loc @?= Just (Aeson.object [])
        lv <- objectOf (Aeson.toJSON LastVisitedTimeSchema {schemaId = "", schemaName = "Seen", schemaDescription = Just "Tanaka Hanako's last visit"})
        KeyMap.lookup "type" lv @?= Just (Aeson.String "last_visited_time")
        KeyMap.lookup "last_visited_time" lv @?= Just (Aeson.object [])
        KeyMap.lookup "description" lv @?= Just (Aeson.String "Tanaka Hanako's last visit"),
      testCase "Unknown property type decodes to UnknownSchema" $ do
        schema <- decodeOrFail "{\"id\":\"x\",\"name\":\"Mood\",\"type\":\"sentiment\",\"sentiment\":{\"scale\":5}}"
        case schema of
          UnknownSchema {schemaType} -> schemaType @?= "sentiment"
          other -> assertFailure ("expected UnknownSchema, got " <> show other)
        sentiment <- lookupKey "sentiment" (Aeson.toJSON schema)
        sentiment @?= Aeson.object ["scale" Aeson..= (5 :: Int)],
      testCase "UpdateDataSource rename-only property" $
        Aeson.toJSON (updateWithProperties (Map.fromList [("Old", RenameProperty "New")]))
          @?= Aeson.object ["properties" Aeson..= Aeson.object ["Old" Aeson..= Aeson.object ["name" Aeson..= ("New" :: Text.Text)]]],
      testCase "UpdateDataSource select option targeted by id" $ do
        let update =
              UpdateSelectOptions
                { newName = Nothing,
                  optionUpdates = Vector.fromList [OptionUpdate (OptionWithId "o1" Nothing) (Just Red) (Just "urgent")]
                }
        Aeson.toJSON update
          @?= Aeson.object
            [ "select"
                Aeson..= Aeson.object
                  [ "options"
                      Aeson..= [ Aeson.object
                                   [ "id" Aeson..= ("o1" :: Text.Text),
                                     "color" Aeson..= ("red" :: Text.Text),
                                     "description" Aeson..= ("urgent" :: Text.Text)
                                   ]
                               ]
                  ]
            ]
    ]
