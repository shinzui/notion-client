-- |
-- Notion API Client Example
--
-- This example demonstrates using the Notion API client to interact with Notion:
-- - Retrieving users and user information
-- - Retrieving, querying, and creating databases
-- - Displaying database metadata (isInline, inTrash, publicUrl, dataSources)
-- - Adding properties to databases (select, multi-select, etc.)
-- - Creating pages with properties and content
-- - Populating database properties on pages
-- - Adding different types of blocks to pages
-- - Creating comments on pages and on specific blocks
-- - Listing and inspecting comments (with attachments and displayName)
-- - Querying and searching content
--
-- To run this example:
--
-- 1. Get a Notion API token from https://www.notion.so/my-integrations
-- 2. Set the NOTION_TOKEN environment variable with your token
-- 3. (Optional) Set NOTION_TEST_DATABASE_ID with a database ID to test database operations
-- 4. (Optional) Set NOTION_TEST_PAGE_ID with a page ID to test page operations
-- 5. Run with: cabal run notion-client-example
--
-- Note: Your integration must have access to the specified database and page.
module Main where

import Console (logError, printHeader)
import Control.Monad (when)
import Data.Maybe (isNothing)
import Data.Text qualified as Text
import DatabaseDemo (runDatabaseDemo)
import Notion.V1 (getClientEnv, makeMethods)
import Notion.V1.Common (ObjectType (..))
import Notion.V1.Search (SearchFilter (..), SearchRequest (..), SearchSort (..), SearchSortDirection (..))
import PageDemo (runPageDemo)
import System.Environment qualified as Environment
import UserDemo (runUserDemo)

main :: IO ()
main = do
  putStrLn "Notion API Client Example"
  putStrLn "========================="

  -- Get environment variables with error handling
  token <- do
    mToken <- Environment.lookupEnv "NOTION_TOKEN"
    case mToken of
      Just t -> pure (Text.pack t)
      Nothing -> logError (Text.pack "NOTION_TOKEN environment variable is required")

  databaseIdEnv <- Environment.lookupEnv "NOTION_TEST_DATABASE_ID"
  pageIdEnv <- Environment.lookupEnv "NOTION_TEST_PAGE_ID"

  when (isNothing databaseIdEnv && isNothing pageIdEnv) $
    putStrLn "WARNING: Neither NOTION_TEST_DATABASE_ID nor NOTION_TEST_PAGE_ID are set.\n         Only basic user API functionality will be demonstrated."

  printHeader (Text.pack "Client Initialization")
  clientEnv <- getClientEnv (Text.pack "https://api.notion.com/v1")
  putStrLn "Client initialized"

  let methods = makeMethods clientEnv token

  -- User API demo
  runUserDemo methods

  -- Optional Database tests
  case databaseIdEnv of
    Just databaseIdStr -> runDatabaseDemo methods databaseIdStr
    Nothing ->
      putStrLn "Skipping database tests (set NOTION_TEST_DATABASE_ID to enable)"

  -- Optional Page tests
  case pageIdEnv of
    Just pageIdStr -> runPageDemo methods pageIdStr
    Nothing ->
      putStrLn "Skipping page tests (set NOTION_TEST_PAGE_ID to enable)"

  -- Search API
  printHeader (Text.pack "Search API")

  putStrLn "Due to ongoing implementation of search support, search API examples are provided in the source code."
  putStrLn "The examples demonstrate:"
  putStrLn "- General searching (find anything matching a query)"
  putStrLn "- Filtering by object type (search only for pages)"
  putStrLn "- Filtering by object type (search only for databases)"
  putStrLn "- Sorting results by last_edited_time"

  -- Example search parameters (not executed to avoid errors)
  let _searchParams =
        SearchRequest
          { query = Just (Text.pack "test"),
            sort = Nothing,
            filter = Nothing,
            startCursor = Nothing,
            pageSize = Nothing
          }

  -- Example page search parameters
  let _pageSearchParams =
        SearchRequest
          { query = Just (Text.pack "test"),
            sort = Nothing,
            filter = Just (SearchFilter {value = Page, property = Text.pack "object"}),
            startCursor = Nothing,
            pageSize = Nothing
          }

  -- Example database search parameters
  let _databaseSearchParams =
        SearchRequest
          { query = Just (Text.pack "test"),
            sort = Nothing,
            filter = Just (SearchFilter {value = Database, property = Text.pack "object"}),
            startCursor = Nothing,
            pageSize = Nothing
          }

  -- Example sorted search parameters
  let _sortedSearchParams =
        SearchRequest
          { query = Just (Text.pack "test"),
            sort = Just (SearchSort {direction = Descending, timestamp = Text.pack "last_edited_time"}),
            filter = Nothing,
            startCursor = Nothing,
            pageSize = Nothing
          }

  -- All done
  printHeader (Text.pack "Test complete")
  putStrLn "All tests completed successfully!"
