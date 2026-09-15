-- | View queries and typed view configuration (EP-4).
module ViewTests (tests) where

import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy.Char8 qualified as L8
import Data.IORef (readIORef)
import Data.Map.Strict qualified as Map
import Data.Vector qualified as Vector
import FakeNotion
import Notion.V1 (makeMethods)
import Notion.V1.Common (Parent (..), UUID (..))
import Notion.V1.Filter
import Notion.V1.ListOf (ListOf (..))
import Notion.V1.ViewQueries (queryAllViewPages)
import Notion.V1.Views
import Test.Tasty
import Test.Tasty.HUnit
import Prelude hiding (id)

tests :: TestTree
tests =
  testGroup
    "Views (EP-4)"
    [ viewQueryTests,
      filterSortTests,
      viewObjectTests,
      viewRequestTests,
      viewConfigTests
    ]

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------

decodeOrFail :: (Aeson.FromJSON a) => L8.ByteString -> IO a
decodeOrFail bytes = either (assertFailure . ("decode failed: " <>)) pure (Aeson.eitherDecode bytes)

jsonValue :: L8.ByteString -> Aeson.Value
jsonValue bytes = either error (\v -> v) (Aeson.eitherDecode bytes)

-- ---------------------------------------------------------------------
-- View queries
-- ---------------------------------------------------------------------

viewQueryTests :: TestTree
viewQueryTests =
  testGroup
    "View queries"
    [ testCase "decode ViewQuery (create response)" testDecodeViewQuery,
      testCase "decode view query results list" testDecodeResults,
      testCase "decode DeletedViewQuery" testDecodeDeleted,
      testCase "encode CreateViewQuery" testEncodeCreateViewQuery,
      testCase "queryAllViewPages follows cursors and deletes the query" testQueryAllViewPages
    ]

viewQueryFixture :: L8.ByteString
viewQueryFixture =
  "{\"object\":\"view_query\",\"id\":\"7f1c2a9e-3b4d-4e5f-8a6b-1c2d3e4f5a6b\",\
  \\"view_id\":\"2b3c4d5e-6f70-4812-9a3b-4c5d6e7f8091\",\"expires_at\":\"2026-09-14T19:15:00.000Z\",\
  \\"total_count\":3,\"results\":[{\"object\":\"page\",\"id\":\"11111111-2222-4333-8444-555555555555\"},\
  \{\"object\":\"page\",\"id\":\"66666666-7777-4888-9999-aaaaaaaaaaaa\"}],\
  \\"next_cursor\":\"66666666-7777-4888-9999-aaaaaaaaaaaa\",\"has_more\":true}"

resultsFixture :: L8.ByteString
resultsFixture =
  "{\"object\":\"list\",\"next_cursor\":null,\"has_more\":false,\
  \\"results\":[{\"object\":\"page\",\"id\":\"bbbbbbbb-cccc-4ddd-8eee-ffffffffffff\"}],\
  \\"type\":\"page\",\"page\":{}}"

deletedFixture :: L8.ByteString
deletedFixture = "{\"object\":\"view_query\",\"id\":\"7f1c2a9e-3b4d-4e5f-8a6b-1c2d3e4f5a6b\",\"deleted\":true}"

testDecodeViewQuery :: Assertion
testDecodeViewQuery = do
  ViewQuery {totalCount, results, hasMore, nextCursor, requestStatus} <- decodeOrFail viewQueryFixture
  totalCount @?= 3
  Vector.length results @?= 2
  hasMore @?= True
  nextCursor @?= Just "66666666-7777-4888-9999-aaaaaaaaaaaa"
  requestStatus @?= Nothing

testDecodeResults :: Assertion
testDecodeResults = do
  List {results, hasMore} <- decodeOrFail resultsFixture :: IO (ListOf PartialPageObject)
  map (\PartialPageObject {id} -> id) (Vector.toList results) @?= [UUID "bbbbbbbb-cccc-4ddd-8eee-ffffffffffff"]
  hasMore @?= False

testDecodeDeleted :: Assertion
testDecodeDeleted = do
  DeletedViewQuery {deleted} <- decodeOrFail deletedFixture
  deleted @?= True

testEncodeCreateViewQuery :: Assertion
testEncodeCreateViewQuery = do
  Aeson.toJSON CreateViewQuery {pageSize = Just 50} @?= jsonValue "{\"page_size\":50}"
  Aeson.toJSON CreateViewQuery {pageSize = Nothing} @?= jsonValue "{}"

testQueryAllViewPages :: Assertion
testQueryAllViewPages = do
  (env, recorded) <-
    fakeClientEnv
      [ jsonReply 200 viewQueryFixture,
        jsonReply 200 resultsFixture,
        jsonReply 200 deletedFixture
      ]
  let methods = makeMethods env "secret_test"
  pages <- queryAllViewPages methods "2b3c4d5e-6f70-4812-9a3b-4c5d6e7f8091" (Just 2)
  map (\PartialPageObject {id} -> id) (Vector.toList pages)
    @?= [ UUID "11111111-2222-4333-8444-555555555555",
          UUID "66666666-7777-4888-9999-aaaaaaaaaaaa",
          UUID "bbbbbbbb-cccc-4ddd-8eee-ffffffffffff"
        ]
  reqs <- readIORef recorded
  map (\Recorded {method, path} -> (method, path)) reqs
    @?= [ ("POST", "/views/2b3c4d5e-6f70-4812-9a3b-4c5d6e7f8091/queries"),
          ("GET", "/views/2b3c4d5e-6f70-4812-9a3b-4c5d6e7f8091/queries/7f1c2a9e-3b4d-4e5f-8a6b-1c2d3e4f5a6b"),
          ("DELETE", "/views/2b3c4d5e-6f70-4812-9a3b-4c5d6e7f8091/queries/7f1c2a9e-3b4d-4e5f-8a6b-1c2d3e4f5a6b")
        ]

-- ---------------------------------------------------------------------
-- Filters and sorts
-- ---------------------------------------------------------------------

filterSortTests :: TestTree
filterSortTests =
  testGroup
    "Filters and sorts"
    [ testCase "Filter values round-trip through JSON" testFilterRoundTrip,
      testCase "Sort values round-trip through JSON" testSortRoundTrip,
      testCase "array-valued select filter survives as ViewFilter" testArrayFilterPreserved
    ]

sampleFilters :: [Filter]
sampleFilters =
  [ And
      [ PropertyFilter "Name" (TitleCondition (TextContains "Tanaka")),
        Or
          [ PropertyFilter "Notes" (RichTextCondition TextIsEmpty),
            PropertyFilter "Phone" (PhoneNumberCondition (TextStartsWith "+81"))
          ]
      ],
    TimestampFilter FilterLastEditedTime DateNextWeek,
    TimestampFilter FilterCreatedTime (DateOnOrAfter "2026-09-01"),
    PropertyFilter "Estimate" (NumberCondition (NumGreaterThanOrEqualTo 2.5)),
    PropertyFilter "Done" (CheckboxCondition (CheckboxDoesNotEqual True)),
    PropertyFilter "Priority" (SelectCondition (SelectEquals "High")),
    PropertyFilter "Tags" (MultiSelectCondition MultiSelectIsNotEmpty),
    PropertyFilter "Due" (DateCondition DatePastMonth),
    PropertyFilter "Owner" (PeopleCondition (PeopleContains "u1u1u1u1-0000-4000-8000-000000000004")),
    PropertyFilter "Attachments" (FilesCondition FilesIsEmpty),
    PropertyFilter "Project" (RelationCondition (RelationDoesNotContain "p1")),
    PropertyFilter "Stage" (StatusCondition (StatusEquals "In progress")),
    PropertyFilter "Rollup" (RollupCondition (RollupAny (RichTextCondition (TextContains "Sato")))),
    PropertyFilter "Rollup count" (RollupCondition (RollupNumber (NumLessThan 10))),
    PropertyFilter "Score" (FormulaCondition (FormulaNumber (NumGreaterThan 3))),
    PropertyFilter "Created" (CreatedTimeCondition DateThisYear),
    PropertyFilter "Author" (CreatedByCondition PeopleIsEmpty),
    PropertyFilter "Edited" (LastEditedTimeCondition (DateBefore "2026-01-01")),
    PropertyFilter "Editor" (LastEditedByCondition (PeopleDoesNotContain "u2")),
    PropertyFilter "Site" (UrlCondition (TextEndsWith ".jp")),
    PropertyFilter "Email" (EmailCondition (TextEquals "hanako@example.com"))
  ]

testFilterRoundTrip :: Assertion
testFilterRoundTrip =
  mapM_ (\f -> Aeson.fromJSON (Aeson.toJSON f) @?= Aeson.Success f) sampleFilters

testSortRoundTrip :: Assertion
testSortRoundTrip =
  mapM_
    (\s -> Aeson.fromJSON (Aeson.toJSON s) @?= Aeson.Success s)
    [PropertySort "Due" Ascending, TimestampSort FilterLastEditedTime Descending]

testArrayFilterPreserved :: Assertion
testArrayFilterPreserved = do
  let raw = jsonValue "{\"property\":\"Status\",\"select\":{\"does_not_equal\":[\"Done\",\"Archive\"]}}"
  case Aeson.fromJSON raw :: Aeson.Result ViewFilter of
    Aeson.Success vf -> Aeson.toJSON vf @?= raw
    Aeson.Error err -> assertFailure err

-- ---------------------------------------------------------------------
-- View object
-- ---------------------------------------------------------------------

viewObjectTests :: TestTree
viewObjectTests =
  testGroup
    "View object"
    [ testCase "decode a board view with typed filter, sorts and quick filters" testDecodeViewObject,
      testCase "unknown view type decodes as UnknownViewType" testUnknownViewType
    ]

viewObjectFixture :: L8.ByteString
viewObjectFixture =
  "{\"object\":\"view\",\"id\":\"2b3c4d5e-6f70-4812-9a3b-4c5d6e7f8091\",\
  \\"parent\":{\"type\":\"database_id\",\"database_id\":\"d1d1d1d1-0000-4000-8000-000000000002\"},\
  \\"name\":\"Tanaka Hanako's tasks\",\"type\":\"board\",\
  \\"created_time\":\"2026-09-01T09:00:00.000Z\",\"last_edited_time\":\"2026-09-02T10:30:00.000+00:00\",\
  \\"url\":\"https://www.notion.so/d1d1d1d1000040008000000000000002?v=2b3c4d5e6f7048129a3b4c5d6e7f8091\",\
  \\"data_source_id\":\"e5e5e5e5-0000-4000-8000-000000000003\",\
  \\"created_by\":{\"object\":\"user\",\"id\":\"u1u1u1u1-0000-4000-8000-000000000004\"},\
  \\"last_edited_by\":{\"object\":\"user\",\"id\":\"u1u1u1u1-0000-4000-8000-000000000004\"},\
  \\"filter\":{\"and\":[{\"property\":\"Assignee\",\"people\":{\"contains\":\"u1u1u1u1-0000-4000-8000-000000000004\"}},\
  \{\"timestamp\":\"created_time\",\"created_time\":{\"past_month\":{}}}]},\
  \\"sorts\":[{\"timestamp\":\"created_time\",\"direction\":\"descending\"},{\"property\":\"Due\",\"direction\":\"ascending\"}],\
  \\"quick_filters\":{\"Priority\":{\"select\":{\"equals\":\"High\"}}},\
  \\"configuration\":{\"type\":\"board\",\"group_by\":{\"type\":\"status\",\"property_id\":\"a%3Bc\",\
  \\"group_by\":\"group\",\"sort\":{\"type\":\"manual\"},\"property_name\":\"Status\"}}}"

testDecodeViewObject :: Assertion
testDecodeViewObject = do
  ViewObject {parent, type_, filter = viewFilter, sorts, quickFilters} <- decodeOrFail viewObjectFixture
  case parent of
    Just (DatabaseParent {}) -> pure ()
    other -> assertFailure ("expected DatabaseParent, got " <> show other)
  type_ @?= Just BoardView
  viewFilter
    @?= Just
      ( ViewFilter
          ( And
              [ PropertyFilter "Assignee" (PeopleCondition (PeopleContains "u1u1u1u1-0000-4000-8000-000000000004")),
                TimestampFilter FilterCreatedTime DatePastMonth
              ]
          )
      )
  fmap Vector.toList sorts
    @?= Just [ViewSort (TimestampSort FilterCreatedTime Descending), ViewSort (PropertySort "Due" Ascending)]
  quickFilters @?= Just (Map.fromList [("Priority", QuickFilter (SelectCondition (SelectEquals "High")))])

testUnknownViewType :: Assertion
testUnknownViewType = do
  ViewObject {type_} <-
    decodeOrFail "{\"object\":\"view\",\"id\":\"2b3c4d5e-6f70-4812-9a3b-4c5d6e7f8091\",\"type\":\"wiki_board\"}"
  type_ @?= Just (UnknownViewType "wiki_board")

-- ---------------------------------------------------------------------
-- View requests
-- ---------------------------------------------------------------------

viewRequestTests :: TestTree
viewRequestTests =
  testGroup
    "View requests"
    [ testCase "UpdateView clears, sets and removes quick filters" testUpdateViewClear,
      testCase "UpdateView with nothing set encodes to {}" testUpdateViewEmpty,
      testCase "CreateView position after_view" testCreateViewPosition,
      testCase "CreateView dashboard widget placement" testCreateViewPlacement,
      testCase "CreateView create_database" testCreateViewCreateDatabase
    ]

baseCreateView :: ViewID -> Maybe ViewPosition -> Maybe WidgetPlacement -> Maybe CreateDatabaseForView -> CreateView
baseCreateView dashboard position placement createDatabase =
  CreateView
    { dataSourceId = "ds-1",
      name = "Sato Kenji's board",
      type_ = BoardView,
      databaseId = Nothing,
      viewId = if dashboard == "" then Nothing else Just dashboard,
      filter = Nothing,
      sorts = Nothing,
      quickFilters = Nothing,
      createDatabase_ = createDatabase,
      configuration = Nothing,
      position = position,
      placement = placement
    }

objectKey :: Aeson.Key -> Aeson.Value -> Maybe Aeson.Value
objectKey k = \case
  Aeson.Object o -> KeyMap.lookup k o
  _ -> Nothing

testUpdateViewClear :: Assertion
testUpdateViewClear =
  Aeson.toJSON
    UpdateView
      { name = Nothing,
        filter = Clear,
        sorts = Set (Vector.fromList [ViewPropertySort {property = "Due", direction = Descending}]),
        quickFilters =
          Set
            ( Map.fromList
                [ ("Priority", Nothing),
                  ("Status", Just (QuickFilter (StatusCondition (StatusEquals "In progress"))))
                ]
            ),
        configuration = Nothing
      }
    @?= jsonValue
      "{\"filter\":null,\"sorts\":[{\"property\":\"Due\",\"direction\":\"descending\"}],\
      \\"quick_filters\":{\"Priority\":null,\"Status\":{\"status\":{\"equals\":\"In progress\"}}}}"

testUpdateViewEmpty :: Assertion
testUpdateViewEmpty =
  Aeson.toJSON UpdateView {name = Nothing, filter = Unset, sorts = Unset, quickFilters = Unset, configuration = Nothing}
    @?= jsonValue "{}"

testCreateViewPosition :: Assertion
testCreateViewPosition =
  objectKey "position" (Aeson.toJSON (baseCreateView "" (Just (ViewPositionAfterView "view-9")) Nothing Nothing))
    @?= Just (jsonValue "{\"type\":\"after_view\",\"view_id\":\"view-9\"}")

testCreateViewPlacement :: Assertion
testCreateViewPlacement = do
  let json = Aeson.toJSON (baseCreateView "dash-1" Nothing (Just (ExistingRow 0)) Nothing)
  objectKey "view_id" json @?= Just (Aeson.String "dash-1")
  objectKey "placement" json @?= Just (jsonValue "{\"type\":\"existing_row\",\"row_index\":0}")

testCreateViewCreateDatabase :: Assertion
testCreateViewCreateDatabase = do
  let json = Aeson.toJSON (baseCreateView "" Nothing Nothing (Just (CreateDatabaseForView "page-1" (Just "block-1"))))
  objectKey "create_database" json
    @?= Just
      ( jsonValue
          "{\"parent\":{\"type\":\"page_id\",\"page_id\":\"page-1\"},\
          \\"position\":{\"type\":\"after_block\",\"block_id\":\"block-1\"}}"
      )
  objectKey "create_database_" json @?= Nothing

-- ---------------------------------------------------------------------
-- View configuration
-- ---------------------------------------------------------------------

viewConfigTests :: TestTree
viewConfigTests =
  testGroup
    "View configuration"
    [ testCase "table configuration round-trips" (roundTrip tableFixture isTable),
      testCase "board configuration round-trips" (roundTrip boardFixture isBoard),
      testCase "calendar configuration round-trips" (roundTrip calendarFixture isCalendar),
      testCase "timeline configuration round-trips" (roundTrip timelineFixture isTimeline),
      testCase "gallery configuration round-trips" (roundTrip galleryFixture isGallery),
      testCase "list configuration round-trips" (roundTrip listFixture isList),
      testCase "chart configuration round-trips" (roundTrip chartFixture isChart),
      testCase "number chart configuration round-trips" (roundTrip numberChartFixture isChart),
      testCase "map configuration round-trips" (roundTrip mapFixture isMap),
      testCase "form configuration round-trips" (roundTrip formFixture isForm),
      testCase "dashboard configuration round-trips" (roundTrip dashboardFixture isDashboard),
      testCase "map_by_property_name is decoded and dropped" testMapResponseOnly,
      testCase "response-only property_name is decoded and dropped" testResponseOnlyStripped,
      testCase "unknown configuration type is preserved" testUnknownConfig,
      testCase "unknown enum value is preserved" testUnknownEnum,
      testCase "formula group-by round-trips" testFormulaGroupBy,
      testCase "UpdateView can clear a configuration field" testClearConfigField
    ]

-- | Decode a fixture, check its constructor, and re-encode it to the identical JSON value.
roundTrip :: L8.ByteString -> (ViewConfig -> Bool) -> Assertion
roundTrip fixture expected = do
  config <- decodeOrFail fixture
  assertBool ("unexpected constructor: " <> show config) (expected config)
  Aeson.toJSON config @?= jsonValue fixture

isTable, isBoard, isCalendar, isTimeline, isGallery, isList, isChart, isMap, isForm, isDashboard :: ViewConfig -> Bool
-- The table and board checks also require a typed (not unknown) group-by.
isTable = \case TableConfig TableViewConfig {groupBy = Set (DateGroupBy {})} -> True; _ -> False
isBoard = \case BoardConfig BoardViewConfig {groupBy = SelectGroupBy {}} -> True; _ -> False
isCalendar = \case CalendarConfig {} -> True; _ -> False
isTimeline = \case TimelineConfig {} -> True; _ -> False
isGallery = \case GalleryConfig {} -> True; _ -> False
isList = \case ListConfig {} -> True; _ -> False
isChart = \case ChartConfig ChartViewConfig {xAxis = x} -> case x of Set UnknownGroupBy {} -> False; _ -> True; _ -> False
isMap = \case MapConfig {} -> True; _ -> False
isForm = \case FormConfig {} -> True; _ -> False
isDashboard = \case DashboardConfig DashboardViewConfig {rows} -> Vector.length rows == 1; _ -> False

tableFixture :: L8.ByteString
tableFixture =
  "{\"type\":\"table\",\"properties\":[{\"property_id\":\"title\",\"visible\":true,\"width\":280,\"wrap\":false},\
  \{\"property_id\":\"d%3Aue\",\"date_format\":\"year_month_day\",\"time_format\":\"24_hour\"}],\
  \\"group_by\":{\"type\":\"date\",\"property_id\":\"d%3Aue\",\"group_by\":\"week\",\"sort\":{\"type\":\"ascending\"},\"start_day_of_week\":1},\
  \\"subtasks\":{\"property_id\":\"r%3Bx\",\"display_mode\":\"flattened\",\"filter_scope\":\"parents_and_subitems\"},\
  \\"wrap_cells\":true,\"frozen_column_index\":1,\"show_vertical_lines\":false}"

boardFixture :: L8.ByteString
boardFixture =
  "{\"type\":\"board\",\"group_by\":{\"type\":\"multi_select\",\"property_id\":\"t%3Ag\",\"sort\":{\"type\":\"manual\"},\"hide_empty_groups\":true},\
  \\"sub_group_by\":null,\"properties\":[{\"property_id\":\"title\",\"card_property_width_mode\":\"full_line\"}],\
  \\"cover\":{\"type\":\"property\",\"property_id\":\"f%3Ail\"},\"cover_size\":\"medium\",\"cover_aspect\":\"cover\",\"card_layout\":\"compact\"}"

calendarFixture :: L8.ByteString
calendarFixture = "{\"type\":\"calendar\",\"date_property_id\":\"d%3Aue\",\"view_range\":\"week\",\"show_weekends\":false}"

timelineFixture :: L8.ByteString
timelineFixture =
  "{\"type\":\"timeline\",\"date_property_id\":\"d%3Aue\",\"end_date_property_id\":null,\"show_table\":true,\
  \\"table_properties\":[{\"property_id\":\"title\"}],\"preference\":{\"zoom_level\":\"5_years\",\"center_timestamp\":1789000000000},\
  \\"arrows_by\":{\"property_id\":null},\"color_by\":false}"

galleryFixture :: L8.ByteString
galleryFixture = "{\"type\":\"gallery\",\"cover\":{\"type\":\"page_cover\"},\"cover_size\":\"large\",\"card_layout\":\"list\"}"

listFixture :: L8.ByteString
listFixture = "{\"type\":\"list\",\"properties\":[{\"property_id\":\"title\",\"visible\":true,\"status_show_as\":\"checkbox\"}]}"

chartFixture :: L8.ByteString
chartFixture =
  "{\"type\":\"chart\",\"chart_type\":\"column\",\
  \\"x_axis\":{\"type\":\"select\",\"property_id\":\"s%3Bq\",\"sort\":{\"type\":\"manual\"}},\
  \\"y_axis\":{\"aggregator\":\"sum\",\"property_id\":\"n%3Aum\"},\"sort\":\"y_descending\",\"color_theme\":\"colorful\",\
  \\"height\":\"extra_large\",\"legend_position\":\"bottom\",\"show_data_labels\":true,\"axis_labels\":\"both\",\
  \\"grid_lines\":\"horizontal\",\"group_style\":\"side_by_side\",\"y_axis_min\":0,\"y_axis_max\":null,\"stack_by\":null,\
  \\"reference_lines\":[{\"id\":\"line-1\",\"value\":75.5,\"label\":\"Target\",\"color\":\"lightgray\",\"dash_style\":\"dash\"}],\
  \\"caption\":null,\"color_by_value\":false}"

numberChartFixture :: L8.ByteString
numberChartFixture = "{\"type\":\"chart\",\"chart_type\":\"number\",\"value\":{\"aggregator\":\"count\"},\"hide_title\":true}"

mapFixture :: L8.ByteString
mapFixture = "{\"type\":\"map\",\"height\":\"large\",\"map_by\":\"l%3Boc\",\"properties\":[{\"property_id\":\"title\"}]}"

formFixture :: L8.ByteString
formFixture =
  "{\"type\":\"form\",\"is_form_closed\":false,\"anonymous_submissions\":true,\"submission_permissions\":\"read_and_write\"}"

dashboardFixture :: L8.ByteString
dashboardFixture =
  "{\"type\":\"dashboard\",\"rows\":[{\"id\":\"row-1\",\"widgets\":[\
  \{\"id\":\"w-1\",\"view_id\":\"2b3c4d5e-6f70-4812-9a3b-4c5d6e7f8091\",\"width\":6,\"row_index\":0},\
  \{\"id\":\"w-2\",\"view_id\":\"9a8b7c6d-5e4f-4321-8fed-cba987654321\",\"width\":6,\"row_index\":0}],\"height\":320}]}"

testMapResponseOnly :: Assertion
testMapResponseOnly = do
  config <- decodeOrFail "{\"type\":\"map\",\"map_by\":\"l%3Boc\",\"map_by_property_name\":\"Office\"}"
  case config of
    MapConfig MapViewConfig {mapByPropertyName} -> mapByPropertyName @?= Just "Office"
    other -> assertFailure ("expected a map configuration, got " <> show other)
  Aeson.toJSON config @?= jsonValue "{\"type\":\"map\",\"map_by\":\"l%3Boc\"}"

testResponseOnlyStripped :: Assertion
testResponseOnlyStripped = do
  ViewObject {configuration} <- decodeOrFail viewObjectFixture
  case configuration of
    Just config@(BoardConfig BoardViewConfig {groupBy = StatusGroupBy StatusGroupByConfig {propertyName, groupBy}}) -> do
      propertyName @?= Just "Status"
      groupBy @?= GroupByStatusGroup
      (objectKey "group_by" (Aeson.toJSON config) >>= objectKey "property_name") @?= Nothing
      (objectKey "group_by" (Aeson.toJSON config) >>= objectKey "type") @?= Just (Aeson.String "status")
    other -> assertFailure ("expected a status-grouped board, got " <> show other)

testUnknownConfig :: Assertion
testUnknownConfig = do
  let raw = "{\"type\":\"kanban_3d\",\"depth\":3}"
  config <- decodeOrFail raw
  case config of
    UnknownViewConfig {} -> pure ()
    other -> assertFailure ("expected UnknownViewConfig, got " <> show other)
  Aeson.toJSON config @?= jsonValue raw

testUnknownEnum :: Assertion
testUnknownEnum = do
  let raw = "{\"type\":\"list\",\"properties\":[{\"property_id\":\"title\",\"date_format\":\"iso_week\"}]}"
  config <- decodeOrFail raw
  case config of
    ListConfig ListViewConfig {properties = Set props} ->
      map (\ViewPropertyConfig {dateFormat} -> dateFormat) (Vector.toList props) @?= [Just (UnknownDateFormat "iso_week")]
    other -> assertFailure ("expected a list configuration, got " <> show other)
  Aeson.toJSON config @?= jsonValue raw

testFormulaGroupBy :: Assertion
testFormulaGroupBy = do
  let raw =
        "{\"type\":\"board\",\"group_by\":{\"type\":\"formula\",\"property_id\":\"fx\",\"group_by\":{\"type\":\"number\",\
        \\"sort\":{\"type\":\"descending\"},\"range_start\":0,\"range_end\":100,\"range_size\":10}}}"
  config <- decodeOrFail raw
  case config of
    BoardConfig BoardViewConfig {groupBy = FormulaGroupBy FormulaGroupByConfig {groupBy = FormulaNumberGroup {}}} -> pure ()
    other -> assertFailure ("expected a formula number group-by, got " <> show other)
  Aeson.toJSON config @?= jsonValue raw

testClearConfigField :: Assertion
testClearConfigField =
  objectKey
    "configuration"
    ( Aeson.toJSON
        UpdateView
          { name = Nothing,
            filter = Unset,
            sorts = Unset,
            quickFilters = Unset,
            configuration =
              Just
                ( TableConfig
                    TableViewConfig
                      { properties = Unset,
                        groupBy = Clear,
                        subtasks = Unset,
                        wrapCells = Nothing,
                        frozenColumnIndex = Nothing,
                        showVerticalLines = Nothing
                      }
                )
          }
    )
    @?= Just (jsonValue "{\"type\":\"table\",\"group_by\":null}")
