-- | View queries and typed view configuration (EP-4).
module ViewTests (tests) where

import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy.Char8 qualified as L8
import Data.IORef (readIORef)
import Data.Vector qualified as Vector
import FakeNotion
import Notion.V1 (makeMethods)
import Notion.V1.Common (UUID (..))
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
    [ viewQueryTests
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
