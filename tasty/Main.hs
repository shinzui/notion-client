module Main where

import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy qualified as LBS
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import Notion.V1
import Notion.V1.Blocks (AppendBlockChildren (..), BlockObject (..), Position (..))
import Notion.V1.Common (UUID (..))
import Notion.V1.DataSources (DataSourceObject (..))
import Notion.V1.Databases (DatabaseObject (..))
import Notion.V1.ListOf (ListOf (..))
import Notion.V1.Pages (PageMarkdown (..), PageObject (..))
import Notion.V1.Search (SearchRequest (..))
import Notion.V1.Users (UserObject (..))
import System.Environment qualified as Environment
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = do
  defaultMain =<< tests

tests :: IO TestTree
tests = do
  mToken <- lookupEnv "NOTION_TOKEN"

  let integrationTests = case mToken of
        Nothing ->
          testGroup
            "Integration Tests (skipped — no NOTION_TOKEN)"
            [ testCase "No API token found" $
                assertBool "Set NOTION_TOKEN environment variable to run integration tests" True
            ]
        Just token -> unsafePerformIOTestTree token

  mPageId <- lookupEnv "NOTION_TEST_PAGE_ID"

  let markdownTests = case (mToken, mPageId) of
        (Just token, Just pageId) ->
          testGroup
            "Markdown Tests"
            [ testCase "Retrieve page as markdown" $ do
                clientEnv <- getClientEnv "https://api.notion.com/v1"
                let methods = makeMethods clientEnv (Text.pack token)
                testRetrievePageMarkdown methods (Text.pack pageId)
            ]
        _ ->
          testGroup "Markdown Tests (skipped)" []

  pure $
    testGroup
      "Notion Client Tests"
      [ jsonParsingTests,
        jsonSerializationTests,
        integrationTests,
        markdownTests
      ]

unsafePerformIOTestTree :: String -> TestTree
unsafePerformIOTestTree token =
  testGroup
    "Integration Tests"
    [ testCase "Retrieve current user" $ do
        clientEnv <- getClientEnv "https://api.notion.com/v1"
        let methods = makeMethods clientEnv (Text.pack token)
        testRetrieveCurrentUser methods,
      testCase "List users" $ do
        clientEnv <- getClientEnv "https://api.notion.com/v1"
        let methods = makeMethods clientEnv (Text.pack token)
        testListUsers methods,
      testCase "Timestamp parsing works" $ do
        clientEnv <- getClientEnv "https://api.notion.com/v1"
        let methods = makeMethods clientEnv (Text.pack token)
        testSearchAPI methods
    ]

-- ---------------------------------------------------------------------
-- JSON Parsing Tests (unit tests, no API token needed)
-- ---------------------------------------------------------------------

jsonParsingTests :: TestTree
jsonParsingTests =
  testGroup
    "JSON Parsing"
    [ testCase "Parse BlockObject with in_trash" testParseBlockObject,
      testCase "Parse BlockObject with legacy archived field" testParseBlockObjectLegacy,
      testCase "Parse PageObject with in_trash" testParsePageObject,
      testCase "Parse DatabaseObject with in_trash" testParseDatabaseObject,
      testCase "Parse DataSourceObject with in_trash" testParseDataSourceObject
    ]

testParseBlockObject :: Assertion
testParseBlockObject = do
  let json =
        "{\"object\":\"block\",\"id\":\"abc-123\",\"parent\":{\"type\":\"page_id\",\"page_id\":\"parent-1\"}"
          <> ",\"created_time\":\"2025-10-01T12:00:00.000+00:00\""
          <> ",\"last_edited_time\":\"2025-10-01T12:30:00.000+00:00\""
          <> ",\"created_by\":{\"object\":\"user\",\"id\":\"user-1\"}"
          <> ",\"last_edited_by\":{\"object\":\"user\",\"id\":\"user-2\"}"
          <> ",\"has_children\":false"
          <> ",\"in_trash\":false"
          <> ",\"type\":\"paragraph\""
          <> ",\"paragraph\":{\"rich_text\":[]}}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse BlockObject: " <> err
    Right block -> do
      assertEqual "inTrash should be False" False (Notion.V1.Blocks.inTrash block)
      assertEqual "type should be paragraph" "paragraph" (Notion.V1.Blocks.type_ block)

testParseBlockObjectLegacy :: Assertion
testParseBlockObjectLegacy = do
  -- Test backward compatibility: old "archived" field still parses
  let json =
        "{\"object\":\"block\",\"id\":\"abc-123\",\"parent\":{\"type\":\"page_id\",\"page_id\":\"parent-1\"}"
          <> ",\"created_time\":\"2025-10-01T12:00:00.000+00:00\""
          <> ",\"last_edited_time\":\"2025-10-01T12:30:00.000+00:00\""
          <> ",\"created_by\":{\"object\":\"user\",\"id\":\"user-1\"}"
          <> ",\"last_edited_by\":{\"object\":\"user\",\"id\":\"user-2\"}"
          <> ",\"has_children\":false"
          <> ",\"archived\":true"
          <> ",\"type\":\"paragraph\""
          <> ",\"paragraph\":{\"rich_text\":[]}}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse BlockObject with legacy archived: " <> err
    Right block -> do
      assertEqual "inTrash should be True (from legacy archived)" True (Notion.V1.Blocks.inTrash block)

testParsePageObject :: Assertion
testParsePageObject = do
  let json =
        "{\"object\":\"page\",\"id\":\"page-123\""
          <> ",\"created_time\":\"2025-08-07T10:11:07.504+00:00\""
          <> ",\"last_edited_time\":\"2025-08-10T15:53:11.386+00:00\""
          <> ",\"created_by\":{\"object\":\"user\",\"id\":\"user-1\"}"
          <> ",\"last_edited_by\":{\"object\":\"user\",\"id\":\"user-2\"}"
          <> ",\"cover\":null,\"icon\":null"
          <> ",\"parent\":{\"type\":\"page_id\",\"page_id\":\"parent-1\"}"
          <> ",\"in_trash\":false"
          <> ",\"properties\":{}"
          <> ",\"url\":\"https://www.notion.so/page-123\"}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse PageObject: " <> err
    Right page -> do
      assertEqual "inTrash should be False" False (Notion.V1.Pages.inTrash page)
      assertEqual "url should match" "https://www.notion.so/page-123" (Notion.V1.Pages.url page)

testParseDatabaseObject :: Assertion
testParseDatabaseObject = do
  let json =
        "{\"object\":\"database\",\"id\":\"db-123\""
          <> ",\"created_time\":\"2025-08-07T10:11:07.504+00:00\""
          <> ",\"last_edited_time\":\"2025-08-10T15:53:11.386+00:00\""
          <> ",\"title\":[],\"url\":\"https://www.notion.so/db-123\""
          <> ",\"parent\":{\"type\":\"page_id\",\"page_id\":\"parent-1\"}"
          <> ",\"in_trash\":false"
          <> ",\"data_sources\":[]}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse DatabaseObject: " <> err
    Right db -> do
      assertEqual "inTrash should be Just False" (Just False) (Notion.V1.Databases.inTrash db)

testParseDataSourceObject :: Assertion
testParseDataSourceObject = do
  let json =
        "{\"object\":\"data_source\",\"id\":\"ds-123\""
          <> ",\"created_time\":\"2025-08-07T10:11:07.504+00:00\""
          <> ",\"last_edited_time\":\"2025-08-10T15:53:11.386+00:00\""
          <> ",\"created_by\":{\"object\":\"user\",\"id\":\"user-1\"}"
          <> ",\"last_edited_by\":{\"object\":\"user\",\"id\":\"user-2\"}"
          <> ",\"title\":[],\"description\":[],\"properties\":{}"
          <> ",\"url\":\"https://www.notion.so/ds-123\""
          <> ",\"parent\":{\"type\":\"database_id\",\"database_id\":\"db-1\"}"
          <> ",\"in_trash\":false}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse DataSourceObject: " <> err
    Right ds -> do
      assertEqual "inTrash should be Just False" (Just False) (Notion.V1.DataSources.inTrash ds)

-- ---------------------------------------------------------------------
-- JSON Serialization Tests
-- ---------------------------------------------------------------------

jsonSerializationTests :: TestTree
jsonSerializationTests =
  testGroup
    "JSON Serialization"
    [ testCase "AppendBlockChildren without position" testSerializeAppendNoPosition,
      testCase "AppendBlockChildren with AfterBlock position" testSerializeAppendAfterBlock,
      testCase "AppendBlockChildren with Start position" testSerializeAppendStart,
      testCase "AppendBlockChildren with End position" testSerializeAppendEnd
    ]

testSerializeAppendNoPosition :: Assertion
testSerializeAppendNoPosition = do
  let req = AppendBlockChildren {children = Vector.empty, position = Nothing}
      json = Aeson.toJSON req
  case json of
    Aeson.Object o -> do
      assertBool "should have children key" (KeyMap.member "children" o)
      assertBool "should not have position key" (not $ KeyMap.member "position" o)
    _ -> assertFailure "Expected JSON object"

testSerializeAppendAfterBlock :: Assertion
testSerializeAppendAfterBlock = do
  let req = AppendBlockChildren {children = Vector.empty, position = Just (AfterBlock (UUID "block-42"))}
      json = Aeson.toJSON req
  case json of
    Aeson.Object o -> do
      assertBool "should have position key" (KeyMap.member "position" o)
      case KeyMap.lookup "position" o of
        Just (Aeson.Object pos) -> do
          assertEqual "position type" (Just (Aeson.String "after_block")) (KeyMap.lookup "type" pos)
          case KeyMap.lookup "after_block" pos of
            Just (Aeson.Object ab) ->
              assertEqual "after_block id" (Just (Aeson.String "block-42")) (KeyMap.lookup "id" ab)
            _ -> assertFailure "Expected after_block object"
        _ -> assertFailure "Expected position object"
    _ -> assertFailure "Expected JSON object"

testSerializeAppendStart :: Assertion
testSerializeAppendStart = do
  let req = AppendBlockChildren {children = Vector.empty, position = Just Start}
      json = Aeson.toJSON req
  case json of
    Aeson.Object o ->
      case KeyMap.lookup "position" o of
        Just (Aeson.Object pos) ->
          assertEqual "position type" (Just (Aeson.String "start")) (KeyMap.lookup "type" pos)
        _ -> assertFailure "Expected position object"
    _ -> assertFailure "Expected JSON object"

testSerializeAppendEnd :: Assertion
testSerializeAppendEnd = do
  let req = AppendBlockChildren {children = Vector.empty, position = Just End}
      json = Aeson.toJSON req
  case json of
    Aeson.Object o ->
      case KeyMap.lookup "position" o of
        Just (Aeson.Object pos) ->
          assertEqual "position type" (Just (Aeson.String "end")) (KeyMap.lookup "type" pos)
        _ -> assertFailure "Expected position object"
    _ -> assertFailure "Expected JSON object"

-- ---------------------------------------------------------------------
-- Integration test helpers
-- ---------------------------------------------------------------------

testRetrieveCurrentUser :: Methods -> Assertion
testRetrieveCurrentUser Methods {retrieveMyUser} = do
  user <- retrieveMyUser
  let UserObject {id = userId} = user
  assertBool "User object should have an ID" (show userId /= "")

testListUsers :: Methods -> Assertion
testListUsers Methods {listUsers} = do
  users <- listUsers Nothing Nothing
  let userCount = length $ results users
  assertBool "Should have at least one user" (userCount > 0)

testSearchAPI :: Methods -> Assertion
testSearchAPI Methods {search} = do
  let searchParams =
        Notion.V1.Search.SearchRequest
          { query = Just "test",
            sort = Nothing,
            filter = Nothing,
            startCursor = Nothing,
            pageSize = Nothing
          }
  _ <- search searchParams
  assertBool "Search should run without timestamp parsing errors" True

testRetrievePageMarkdown :: Methods -> Text.Text -> Assertion
testRetrievePageMarkdown Methods {retrievePageMarkdown} pageId = do
  result <- retrievePageMarkdown (UUID pageId) Nothing
  let PageMarkdown {markdown = md} = result
  assertBool "Markdown content should not be empty" (not $ Text.null md)

lookupEnv :: String -> IO (Maybe String)
lookupEnv var = Environment.lookupEnv var
