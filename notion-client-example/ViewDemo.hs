-- |
-- Views API demonstration.
--
-- Shows how to:
-- - Create a table view on a database
-- - Retrieve a view
-- - Update a view (rename, add sorts)
-- - List all views on a database
-- - Delete a view
module ViewDemo
  ( runViewDemo,
  )
where

import Console (printHeader, printSuccess, runTest)
import Data.Aeson qualified as Aeson
import Data.String (fromString)
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import Notion.V1 (Methods (..))
import Notion.V1.Common (UUID (..))
import Notion.V1.Databases (DataSource (..), DatabaseObject (..))
import Notion.V1.ListOf (ListOf (..))
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
  -- Part 5: Delete the view
  -- ---------------------------------------------------------------
  printHeader (Text.pack "Views: Delete View")

  deleted <-
    runTest (Text.pack "Deleting the demo view") $
      deleteView methods viewId

  let ViewObject {id = deletedId} = deleted
  putStrLn $ "Deleted view: " <> show deletedId
  printSuccess (Text.pack "View lifecycle complete")
