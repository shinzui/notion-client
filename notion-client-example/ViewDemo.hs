-- |
-- Views API demonstration.
--
-- Shows how to:
-- - Create a table view on a database
-- - Retrieve a view
-- - Update a view (rename, add sorts)
-- - List all views on a database
-- - Query a view's rows
-- - Delete a view
module ViewDemo
  ( runViewDemo,
  )
where

import Console (printHeader, printSuccess, runTest)
import Control.Monad (when)
import Data.Aeson qualified as Aeson
import Data.String (fromString)
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import Notion.V1 (Methods (..))
import Notion.V1.Databases (DataSource (..), DatabaseObject (..))
import Notion.V1.ListOf (ListOf (..))
import Notion.V1.ViewQueries (queryAllViewPages)
import Notion.V1.Views
import Prelude hiding (id)

-- | Run the Views API demonstration
runViewDemo :: Methods -> String -> IO ()
runViewDemo methods databaseIdStr = do
  let databaseId = fromString databaseIdStr

  -- Get the first data source from the database
  printHeader (Text.pack "Views API")

  database <-
    runTest (Text.pack "Retrieving database for views demo") $
      retrieveDatabase methods databaseId
  let DatabaseObject {dataSources = dsList} = database
      DataSource {id = dsId} = Vector.head dsList
  putStrLn $ "Using data source: " <> show dsId

  -- ---------------------------------------------------------------
  -- Part 1: Create a table view
  -- ---------------------------------------------------------------
  printHeader (Text.pack "Views: Create Table View")

  let createReq =
        CreateView
          { dataSourceId = dsId,
            name = "API Demo - Table View",
            type_ = TableView,
            databaseId = Just databaseId,
            viewId = Nothing,
            filter = Nothing,
            sorts = Nothing,
            quickFilters = Nothing,
            configuration = Nothing,
            position = Nothing
          }

  view <-
    runTest (Text.pack "Creating table view") $
      createView methods createReq

  let ViewObject {id = viewId, type_ = viewType, name = viewName, url = viewUrl} = view
  putStrLn $ "View created: " <> show viewId
  putStrLn $ "  type: " <> show viewType
  putStrLn $ "  name: " <> show viewName
  putStrLn $ "  url: " <> show viewUrl

  -- ---------------------------------------------------------------
  -- Part 2: Retrieve the view
  -- ---------------------------------------------------------------
  printHeader (Text.pack "Views: Retrieve View")

  retrieved <-
    runTest (Text.pack "Retrieving view by ID") $
      retrieveView methods viewId

  let ViewObject
        { name = rName,
          type_ = rType,
          createdBy = rCreatedBy,
          filter = rFilter,
          sorts = rSorts,
          configuration = rConfig
        } = retrieved
  putStrLn $ "  name: " <> show rName
  putStrLn $ "  type: " <> show rType
  putStrLn $ "  createdBy: " <> show rCreatedBy
  putStrLn $ "  filter: " <> show rFilter
  putStrLn $ "  sorts: " <> show rSorts
  putStrLn $ "  configuration: " <> show rConfig

  -- ---------------------------------------------------------------
  -- Part 3: Update the view
  -- ---------------------------------------------------------------
  printHeader (Text.pack "Views: Update View")

  let updateReq =
        UpdateView
          { name = Just "API Demo - Table View (Updated)",
            filter = Nothing,
            sorts =
              Just $
                Vector.singleton $
                  Aeson.object
                    [ ("property", Aeson.String "title"),
                      ("direction", Aeson.String "ascending")
                    ],
            quickFilters = Nothing,
            configuration = Nothing
          }

  updated <-
    runTest (Text.pack "Updating view name and adding sort") $
      updateView methods viewId updateReq

  let ViewObject {name = updatedName, sorts = updatedSorts} = updated
  putStrLn $ "  name: " <> show updatedName
  putStrLn $ "  sorts: " <> show updatedSorts

  -- ---------------------------------------------------------------
  -- Part 4: List views on the database
  -- ---------------------------------------------------------------
  printHeader (Text.pack "Views: List Views")

  viewList <-
    runTest (Text.pack "Listing all views on database") $
      listViews methods (Just databaseId) Nothing Nothing Nothing

  let List {results = viewResults, hasMore = moreViews} = viewList
  putStrLn $ "Found " <> show (Vector.length viewResults) <> " views"
  putStrLn $ "Has more: " <> show moreViews

  -- Show each view's ID and type
  Vector.forM_ viewResults $ \v -> do
    let ViewObject {id = vid, type_ = vtype} = v
    putStrLn $ "  - " <> show vid <> " (type: " <> show vtype <> ")"

  -- ---------------------------------------------------------------
  -- Part 5: Query the view's rows
  -- ---------------------------------------------------------------
  printHeader (Text.pack "Views: Query View Rows")

  query <-
    runTest (Text.pack "Creating view query") $
      createViewQuery methods viewId CreateViewQuery {pageSize = Just 5}

  let ViewQuery
        { id = queryId,
          totalCount = qTotal,
          expiresAt = qExpires,
          results = qResults,
          nextCursor = qCursor,
          hasMore = qMore
        } = query
  putStrLn $ "  query id: " <> show queryId
  putStrLn $ "  totalCount: " <> show qTotal
  putStrLn $ "  expiresAt: " <> show qExpires
  putStrLn $ "  first page: " <> show (Vector.length qResults) <> " results"

  when qMore $ do
    nextPage <-
      runTest (Text.pack "Fetching the next page of results") $
        getViewQueryResults methods viewId queryId qCursor (Just 5)
    let List {results = nextResults} = nextPage
    putStrLn $ "  next page: " <> show (Vector.length nextResults) <> " results"

  deletedQuery <-
    runTest (Text.pack "Deleting view query") $
      deleteViewQuery methods viewId queryId
  let DeletedViewQuery {deleted = queryDeleted} = deletedQuery
  putStrLn $ "  deleted: " <> show queryDeleted

  allPages <-
    runTest (Text.pack "Collecting all rows with queryAllViewPages") $
      queryAllViewPages methods viewId (Just 100)
  putStrLn $ "  queryAllViewPages: " <> show (Vector.length allPages) <> " page references"

  -- ---------------------------------------------------------------
  -- Part 6: Delete the view
  -- ---------------------------------------------------------------
  printHeader (Text.pack "Views: Delete View")

  deleted <-
    runTest (Text.pack "Deleting the demo view") $
      deleteView methods viewId

  let ViewObject {id = deletedId} = deleted
  putStrLn $ "Deleted view: " <> show deletedId
  printSuccess (Text.pack "View lifecycle complete")
