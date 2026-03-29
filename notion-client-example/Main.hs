-- |
-- Notion API Client Example (API version 2026-03-11)
--
-- This example demonstrates using the Notion API client to interact with Notion:
-- - Retrieving users and user information
-- - Retrieving databases and their data sources
-- - Updating data source schema (adding properties)
-- - Creating pages under data sources with properties and content
-- - Creating pages with markdown content (instead of block JSON)
-- - Editing page content via markdown search-and-replace
-- - Moving pages between parents
-- - Listing data source templates and creating pages with templates
-- - Creating, retrieving, updating, listing, and deleting database views
-- - Listing custom emojis
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

import Console (logError, printHeader, runTest)
import Control.Monad (when)
import CustomEmojiDemo (runCustomEmojiDemo)
import Data.Maybe (isNothing)
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import DatabaseDemo (runDatabaseDemo)
import MarkdownDemo (runMarkdownDemo)
import Notion.V1 (Methods (..), getClientEnv, makeMethods)
import Notion.V1.Search (SearchRequest (..), SearchResult (..), SearchSort (..), SearchSortDirection (..), dataSourceFilter, pageFilter, parseSearchResults)
import PageDemo (runPageDemo)
import System.Environment qualified as Environment
import TemplateDemo (runTemplateDemo)
import UserDemo (runUserDemo)
import ViewDemo (runViewDemo)

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

  -- Custom Emojis demo (no setup needed)
  runCustomEmojiDemo methods

  -- Optional Page tests
  case pageIdEnv of
    Just pageIdStr -> do
      runPageDemo methods pageIdStr
      runMarkdownDemo methods pageIdStr
    Nothing ->
      putStrLn "Skipping page/markdown tests (set NOTION_TEST_PAGE_ID to enable)"

  -- Optional Database tests
  case databaseIdEnv of
    Just databaseIdStr -> do
      runDatabaseDemo methods databaseIdStr
      runViewDemo methods databaseIdStr
      runTemplateDemo methods databaseIdStr
    Nothing ->
      putStrLn "Skipping database/view/template tests (set NOTION_TEST_DATABASE_ID to enable)"

  -- Search API
  printHeader (Text.pack "Search API")

  -- General search
  let searchParams =
        SearchRequest
          { query = Nothing,
            sort = Just (SearchSort {direction = Descending, timestamp = Text.pack "last_edited_time"}),
            filter = Nothing,
            startCursor = Nothing,
            pageSize = Just 5
          }
  rawResults <-
    runTest (Text.pack "Searching (all objects, sorted by last_edited_time)") $
      search methods searchParams

  let typedResults = parseSearchResults rawResults
  putStrLn $ "  Found " <> show (Vector.length typedResults) <> " typed results"
  Vector.forM_ typedResults $ \result ->
    case result of
      PageResult _ -> putStrLn "  - page"
      DataSourceResult _ -> putStrLn "  - data_source"

  -- Search filtered to pages only
  let pageSearchParams =
        SearchRequest
          { query = Nothing,
            sort = Nothing,
            filter = Just pageFilter,
            startCursor = Nothing,
            pageSize = Just 3
          }
  pageResults <-
    runTest (Text.pack "Searching (pages only)") $
      search methods pageSearchParams
  let typedPageResults = parseSearchResults pageResults
  putStrLn $ "  Found " <> show (Vector.length typedPageResults) <> " pages"

  -- Search filtered to data sources only
  let dsSearchParams =
        SearchRequest
          { query = Nothing,
            sort = Nothing,
            filter = Just dataSourceFilter,
            startCursor = Nothing,
            pageSize = Just 3
          }
  dsResults <-
    runTest (Text.pack "Searching (data sources only)") $
      search methods dsSearchParams
  let typedDsResults = parseSearchResults dsResults
  putStrLn $ "  Found " <> show (Vector.length typedDsResults) <> " data sources"

  -- All done
  printHeader (Text.pack "Test complete")
  putStrLn "All tests completed successfully!"
