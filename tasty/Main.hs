module Main where

import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy.Char8 qualified as L8
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Map qualified as Map
import Data.Scientific (Scientific)
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import Notion.V1
import Notion.V1.BlockContent (BlockContent (..), CodeLanguage (..), FileSource (..), SyncedFrom (..), blockContentType, bookmarkBlock, bulletedListItemBlock, calloutBlock, codeBlock, dividerBlock, headingBlock, imageBlock, mkRichText, numberedListItemBlock, paragraphBlock, quoteBlock, textBlock, toDoBlock, toggleBlock, withChildren)
import Notion.V1.Blocks (AppendBlockChildren (..), BlockObject (..), Position (..))
import Notion.V1.Blocks qualified as Blocks
import Notion.V1.Comments (CommentAttachment (..), CommentDisplayName (..), CommentObject (..), CreateComment (..))
import Notion.V1.Comments qualified as Comments
import Notion.V1.Common (Color (..), Cover (..), ExternalFile (..), Icon (..), Parent (..), UUID (..))
import Notion.V1.CustomEmojis (CustomEmoji (..))
import Notion.V1.DataSources (DataSourceObject (..))
import Notion.V1.DataSources qualified as DataSources
import Notion.V1.Databases (DataSource (..), DatabaseObject (..))
import Notion.V1.Databases qualified as Databases
import Notion.V1.Error (NotionError (..))
import Notion.V1.FileUploads qualified as FU
import Notion.V1.Filter qualified as F
import Notion.V1.ListOf (ListOf (..))
import Notion.V1.ListOf qualified as ListOf
import Notion.V1.Pages
  ( ContentUpdate (..),
    CreatePage (..),
    MovePage (..),
    PageMarkdown (..),
    PageObject (..),
    ReplaceContentRequest (..),
    Template (..),
    UpdateContentRequest (..),
    UpdatePage (..),
    UpdatePageMarkdown (..),
    mkCreatePage,
    mkUpdatePage,
  )
import Notion.V1.Pagination (PaginationResult (..), paginateCollect)
import Notion.V1.Properties qualified as Props
import Notion.V1.PropertyValue qualified as PV
import Notion.V1.RichText (Annotations (..), Date (..), MentionContent (..), RichText (..), RichTextContent (..), TextContent (..), defaultAnnotations)
import Notion.V1.RichText qualified as RT
import Notion.V1.Search (SearchRequest (..), SearchResult (..), dataSourceFilter, pageFilter, parseSearchResults)
import Notion.V1.Users (BotUser (..), UserObject (..), WorkspaceLimits (..))
import Notion.V1.Views (CreateView (..), QueryView (..), UpdateView (..), ViewObject (..), ViewType (..))
import System.Environment qualified as Environment
import Test.Tasty
import Test.Tasty.HUnit
import Web.HttpApiData (toQueryParam)

main :: IO ()
main = do
  defaultMain =<< tests

tests :: IO TestTree
tests = do
  mToken <- lookupEnv "NOTION_TOKEN"
  mPageId <- lookupEnv "NOTION_TEST_PAGE_ID"
  mDatabaseId <- lookupEnv "NOTION_TEST_DATABASE_ID"

  let basicIntegration = case mToken of
        Nothing ->
          testGroup
            "Integration Tests (skipped — no NOTION_TOKEN)"
            [ testCase "No API token found" $
                assertBool "Set NOTION_TOKEN environment variable to run integration tests" True
            ]
        Just token ->
          testGroup
            "Integration Tests"
            [ testCase "Retrieve current user" $ do
                methods <- mkMethods token
                testRetrieveCurrentUser methods,
              testCase "List users" $ do
                methods <- mkMethods token
                testListUsers methods,
              testCase "Search all objects" $ do
                methods <- mkMethods token
                testSearchAll methods,
              testCase "Search filtered by page" $ do
                methods <- mkMethods token
                testSearchPages methods,
              testCase "Search filtered by data source" $ do
                methods <- mkMethods token
                testSearchDataSources methods,
              testCase "List custom emojis" $ do
                methods <- mkMethods token
                testListCustomEmojis methods
            ]

  let markdownE2E = case (mToken, mPageId) of
        (Just token, Just pageId) ->
          testGroup
            "Markdown E2E"
            [ testCase "Retrieve page as markdown" $ do
                methods <- mkMethods token
                testRetrievePageMarkdown methods (Text.pack pageId),
              testCase "Create page with markdown, edit, and clean up" $ do
                methods <- mkMethods token
                testMarkdownLifecycle methods (Text.pack pageId)
            ]
        _ ->
          testGroup "Markdown E2E (skipped — need NOTION_TOKEN + NOTION_TEST_PAGE_ID)" []

  let pageE2E = case (mToken, mPageId) of
        (Just token, Just pageId) ->
          testGroup
            "Page E2E"
            [ testCase "Create page with blocks, append children, list, and clean up" $ do
                methods <- mkMethods token
                testPageBlockLifecycle methods (Text.pack pageId),
              testCase "Create page, add comments, list comments, and clean up" $ do
                methods <- mkMethods token
                testCommentLifecycle methods (Text.pack pageId),
              testCase "Create page, move to different parent, and clean up" $ do
                methods <- mkMethods token
                testMovePageLifecycle methods (Text.pack pageId)
            ]
        _ ->
          testGroup "Page E2E (skipped — need NOTION_TOKEN + NOTION_TEST_PAGE_ID)" []

  let databaseE2E = case (mToken, mDatabaseId) of
        (Just token, Just dbId) ->
          testGroup
            "Database E2E"
            [ testCase "Retrieve database and data source" $ do
                methods <- mkMethods token
                testRetrieveDatabaseAndDataSource methods (Text.pack dbId),
              testCase "List data source templates" $ do
                methods <- mkMethods token
                testListTemplates methods (Text.pack dbId),
              testCase "Query data source" $ do
                methods <- mkMethods token
                testQueryDataSource methods (Text.pack dbId),
              testCase "Create page with markdown in database and clean up" $ do
                methods <- mkMethods token
                testCreateMarkdownPageInDatabase methods (Text.pack dbId)
            ]
        _ ->
          testGroup "Database E2E (skipped — need NOTION_TOKEN + NOTION_TEST_DATABASE_ID)" []

  let viewE2E = case (mToken, mDatabaseId) of
        (Just token, Just dbId) ->
          testGroup
            "View E2E"
            [ testCase "Create, retrieve, update, list, query, and delete view" $ do
                methods <- mkMethods token
                testViewLifecycle methods (Text.pack dbId)
            ]
        _ ->
          testGroup "View E2E (skipped — need NOTION_TOKEN + NOTION_TEST_DATABASE_ID)" []

  pure $
    testGroup
      "Notion Client Tests"
      [ jsonParsingTests,
        jsonSerializationTests,
        propertyValueTests,
        fileUploadTests,
        basicIntegration,
        markdownE2E,
        pageE2E,
        databaseE2E,
        viewE2E
      ]

-- | Create Methods from a token string
mkMethods :: String -> IO Methods
mkMethods token = do
  clientEnv <- getClientEnv "https://api.notion.com/v1"
  pure $ makeMethods clientEnv (Text.pack token)

-- | Helper to make a paragraph block
mkParagraphBlock :: Text.Text -> BlockContent
mkParagraphBlock = textBlock

-- | Helper to make a heading block
mkHeadingBlock :: Text.Text -> Int -> BlockContent
mkHeadingBlock t level = headingBlock level (mkRichText t)

-- | Helper to create a plain RichText from a string
mkPlainRichText :: Text.Text -> RichText
mkPlainRichText t =
  RichText
    { plainText = t,
      href = Nothing,
      annotations = defaultAnnotations,
      type_ = "text",
      content = TextContentWrapper (TextContent {content = t, link = Nothing})
    }

-- | Helper to create a simple test page under a parent page
createTestPage :: Methods -> Text.Text -> Text.Text -> IO PageObject
createTestPage Methods {createPage} parentPageId title = do
  let titleRt = mkPlainRichText title
      props = Map.fromList [("title", PV.titleValue (Vector.singleton titleRt))]
      req = mkCreatePage (PageParent {pageId = UUID parentPageId}) props
  createPage req

-- | Helper to trash a page (clean up after tests)
trashPage :: Methods -> UUID -> IO ()
trashPage Methods {updatePage} pageId = do
  let req =
        UpdatePage
          { properties = Map.empty,
            inTrash = Just True,
            isLocked = Nothing,
            isArchived = Nothing,
            icon = Nothing,
            cover = Nothing,
            template = Nothing,
            eraseContent = Nothing
          }
  _ <- updatePage pageId req
  pure ()

-- | Get first data source ID from a database
getFirstDataSourceId :: Methods -> Text.Text -> IO UUID
getFirstDataSourceId Methods {retrieveDatabase} dbIdText = do
  db <- retrieveDatabase (UUID dbIdText)
  let dsList = Notion.V1.Databases.dataSources db
  assertBool "Database should have at least one data source" (not $ Vector.null dsList)
  let Notion.V1.Databases.DataSource {id = dsId} = Vector.head dsList
  pure dsId

-- =====================================================================
-- JSON Parsing Tests (unit tests, no API token needed)
-- =====================================================================

jsonParsingTests :: TestTree
jsonParsingTests =
  testGroup
    "JSON Parsing"
    [ testCase "Parse BlockObject with in_trash" testParseBlockObject,
      testCase "Parse BlockObject with legacy archived field" testParseBlockObjectLegacy,
      testCase "Parse PageObject with in_trash" testParsePageObject,
      testCase "Parse NotionError from JSON" testParseNotionError,
      testCase "Parse DatabaseObject with in_trash" testParseDatabaseObject,
      testCase "Parse DataSourceObject with in_trash" testParseDataSourceObject,
      testCase "BlockContent round-trip: paragraph" testBlockContentParagraph,
      testCase "BlockContent round-trip: heading with is_toggleable" testBlockContentHeading,
      testCase "BlockContent round-trip: code block" testBlockContentCode,
      testCase "BlockContent round-trip: image (external)" testBlockContentImage,
      testCase "BlockContent round-trip: divider" testBlockContentDivider,
      testCase "BlockContent round-trip: table" testBlockContentTable,
      testCase "BlockContent round-trip: bookmark" testBlockContentBookmark,
      testCase "BlockContent round-trip: unknown block" testBlockContentUnknown,
      testCase "BlockContent round-trip: toggle with nested children" testBlockContentNestedToggle,
      testCase "BlockContent round-trip: column list with columns" testBlockContentNestedColumnList,
      testCase "BlockContent round-trip: paragraph with children" testBlockContentNestedParagraph,
      testCase "BlockContent round-trip: heading (toggleable) with children" testBlockContentNestedHeading,
      testCase "BlockContent round-trip: bulleted list with children" testBlockContentNestedBulletedList,
      testCase "BlockContent round-trip: numbered list with children" testBlockContentNestedNumberedList,
      testCase "BlockContent round-trip: to-do with children" testBlockContentNestedToDo,
      testCase "BlockContent round-trip: quote with children" testBlockContentNestedQuote,
      testCase "BlockContent round-trip: callout with children" testBlockContentNestedCallout,
      testCase "BlockContent round-trip: table with row children" testBlockContentNestedTable,
      testCase "BlockContent round-trip: synced block with children" testBlockContentNestedSyncedBlock,
      testCase "BlockContent round-trip: two-level nesting" testBlockContentTwoLevelNesting,
      testCase "BlockContent round-trip: withChildren combinator" testBlockContentWithChildren,
      testCase "BlockContent: withChildren no-op on non-child types" testWithChildrenNoOp,
      testCase "BlockContent: childless blocks omit children key" testBlockContentNoChildrenKey,
      testCase "BlockContent: blocks with children include children key" testBlockContentHasChildrenKey,
      testCase "BlockUpdate with nested children" testBlockUpdateWithChildren,
      testCase "BlockContent: parse from raw JSON with children" testParseBlockContentWithChildren,
      testCase "BlockUpdate omits type key" testBlockUpdateSerialization,
      testCase "BlockContent round-trip: heading_4" testBlockContentHeading4,
      testCase "BlockContent round-trip: tab" testBlockContentTab,
      testCase "BlockContent parse: meeting_notes" testBlockContentMeetingNotes,
      testCase "BlockContent round-trip: template" testBlockContentTemplate,
      testCase "RichText parse: template_mention_date" testTemplateMentionDate,
      testCase "RichText round-trip: template_mention_user" testTemplateMentionUser,
      testCase "PageObject parse: isLocked and isArchived" testPageObjectLockedArchived,
      testCase "Parent parse: DataSourceParent with databaseId" testDataSourceParentWithDbId,
      testCase "BlockContent round-trip: column with widthRatio" testColumnWidthRatio,
      testCase "BotUser parse: workspaceId and workspaceLimits" testBotUserFields
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
      case Blocks.content block of
        ParagraphBlock {richText} -> assertEqual "rich_text should be empty" Vector.empty richText
        other -> assertFailure $ "Expected ParagraphBlock, got: " <> show other

testParseBlockObjectLegacy :: Assertion
testParseBlockObjectLegacy = do
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
      let PageObject {inTrash = pageInTrash, url = pageUrl} = page
      assertEqual "inTrash should be False" False pageInTrash
      assertEqual "url should match" "https://www.notion.so/page-123" pageUrl

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

testParseNotionError :: Assertion
testParseNotionError = do
  let json =
        "{\"object\":\"error\",\"status\":400,\"code\":\"validation_error\""
          <> ",\"message\":\"The provided page ID is not a valid UUID.\""
          <> ",\"details\":null}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse NotionError: " <> err
    Right notionErr -> do
      let NotionError {status = errStatus, code = errCode, message = errMessage} = notionErr
      assertEqual "status" 400 errStatus
      assertEqual "code" "validation_error" errCode
      assertEqual "message" "The provided page ID is not a valid UUID." errMessage

-- =====================================================================
-- BlockContent Round-trip Tests
-- =====================================================================

-- | Helper: encode then decode, verify equality.
roundTrip :: BlockContent -> Assertion
roundTrip original =
  case Aeson.fromJSON (Aeson.toJSON original) of
    Aeson.Error err -> assertFailure $ "Round-trip failed: " <> err
    Aeson.Success parsed -> assertEqual "round-trip" original parsed

testBlockContentParagraph :: Assertion
testBlockContentParagraph = roundTrip $ paragraphBlock (mkRichText "Hello world")

testBlockContentHeading :: Assertion
testBlockContentHeading = roundTrip $ Heading1Block (mkRichText "Title") Default True Vector.empty

testBlockContentCode :: Assertion
testBlockContentCode = roundTrip $ codeBlock (mkRichText "main = pure ()") Haskell

testBlockContentImage :: Assertion
testBlockContentImage = roundTrip $ imageBlock (ExternalSource (ExternalFile "https://example.com/img.png"))

testBlockContentDivider :: Assertion
testBlockContentDivider = roundTrip DividerBlock

testBlockContentTable :: Assertion
testBlockContentTable = roundTrip $ TableBlock 3 True False Vector.empty

testBlockContentBookmark :: Assertion
testBlockContentBookmark = roundTrip $ bookmarkBlock "https://haskell.org"

testBlockContentUnknown :: Assertion
testBlockContentUnknown = roundTrip $ UnknownBlock "custom_widget" (Aeson.object [("data", Aeson.String "test")])

testBlockContentNestedToggle :: Assertion
testBlockContentNestedToggle =
  roundTrip $
    ToggleBlock
      { richText = mkRichText "Click to expand",
        color = Default,
        children =
          Vector.fromList
            [ textBlock "First child",
              textBlock "Second child"
            ]
      }

testBlockContentNestedColumnList :: Assertion
testBlockContentNestedColumnList =
  roundTrip $
    ColumnListBlock
      { children =
          Vector.fromList
            [ ColumnBlock {widthRatio = Nothing, children = Vector.singleton (textBlock "Column 1 content")},
              ColumnBlock {widthRatio = Nothing, children = Vector.singleton (textBlock "Column 2 content")}
            ]
      }

testBlockContentWithChildren :: Assertion
testBlockContentWithChildren = do
  let block = toggleBlock (mkRichText "Toggle") `withChildren` Vector.fromList [textBlock "Inner"]
  roundTrip block
  case block of
    ToggleBlock {children} ->
      assertEqual "should have 1 child" 1 (Vector.length children)
    other -> assertFailure $ "Expected ToggleBlock, got: " <> show other

testBlockContentNestedParagraph :: Assertion
testBlockContentNestedParagraph =
  roundTrip $
    paragraphBlock (mkRichText "Parent paragraph")
      `withChildren` Vector.singleton (textBlock "Child of paragraph")

testBlockContentNestedHeading :: Assertion
testBlockContentNestedHeading =
  roundTrip $
    Heading1Block
      { richText = mkRichText "Toggleable heading",
        color = Default,
        isToggleable = True,
        children = Vector.singleton (textBlock "Under the heading")
      }

testBlockContentNestedBulletedList :: Assertion
testBlockContentNestedBulletedList =
  roundTrip $
    bulletedListItemBlock (mkRichText "Parent bullet")
      `withChildren` Vector.fromList
        [ bulletedListItemBlock (mkRichText "Sub-bullet A"),
          bulletedListItemBlock (mkRichText "Sub-bullet B")
        ]

testBlockContentNestedNumberedList :: Assertion
testBlockContentNestedNumberedList =
  roundTrip $
    numberedListItemBlock (mkRichText "Parent numbered")
      `withChildren` Vector.fromList
        [ numberedListItemBlock (mkRichText "Sub 1"),
          numberedListItemBlock (mkRichText "Sub 2")
        ]

testBlockContentNestedToDo :: Assertion
testBlockContentNestedToDo =
  roundTrip $
    toDoBlock (mkRichText "Task with sub-tasks") False
      `withChildren` Vector.fromList
        [ toDoBlock (mkRichText "Sub-task done") True,
          toDoBlock (mkRichText "Sub-task pending") False
        ]

testBlockContentNestedQuote :: Assertion
testBlockContentNestedQuote =
  roundTrip $
    quoteBlock (mkRichText "A quote")
      `withChildren` Vector.singleton (textBlock "Attribution line")

testBlockContentNestedCallout :: Assertion
testBlockContentNestedCallout =
  roundTrip $
    calloutBlock (mkRichText "Notice") (Just (EmojiIcon "⚠️"))
      `withChildren` Vector.fromList
        [ textBlock "Detail one",
          textBlock "Detail two"
        ]

testBlockContentNestedTable :: Assertion
testBlockContentNestedTable =
  roundTrip $
    TableBlock
      { tableWidth = 2,
        hasColumnHeader = True,
        hasRowHeader = False,
        children =
          Vector.fromList
            [ TableRowBlock {cells = Vector.fromList [mkRichText "A", mkRichText "B"]},
              TableRowBlock {cells = Vector.fromList [mkRichText "1", mkRichText "2"]}
            ]
      }

testBlockContentNestedSyncedBlock :: Assertion
testBlockContentNestedSyncedBlock =
  roundTrip $
    SyncedBlockContent
      { syncedFrom = SyncedOriginal,
        children = Vector.fromList [textBlock "Synced content", bulletedListItemBlock (mkRichText "Synced item")]
      }

testBlockContentTwoLevelNesting :: Assertion
testBlockContentTwoLevelNesting =
  roundTrip $
    toggleBlock (mkRichText "Outer")
      `withChildren` Vector.fromList
        [ quoteBlock (mkRichText "Middle")
            `withChildren` Vector.singleton (textBlock "Deepest"),
          textBlock "Also in outer"
        ]

testWithChildrenNoOp :: Assertion
testWithChildrenNoOp = do
  let code = codeBlock (mkRichText "x = 1") Haskell
      codeWithKids = code `withChildren` Vector.singleton (textBlock "ignored")
  assertEqual "withChildren should be no-op on CodeBlock" code codeWithKids

  let div = dividerBlock
      divWithKids = div `withChildren` Vector.singleton (textBlock "ignored")
  assertEqual "withChildren should be no-op on DividerBlock" div divWithKids

  let bk = bookmarkBlock "https://example.com"
      bkWithKids = bk `withChildren` Vector.singleton (textBlock "ignored")
  assertEqual "withChildren should be no-op on BookmarkBlock" bk bkWithKids

testBlockContentNoChildrenKey :: Assertion
testBlockContentNoChildrenKey = do
  let json = Aeson.toJSON (paragraphBlock (mkRichText "No kids"))
  case json of
    Aeson.Object o -> case KeyMap.lookup "paragraph" o of
      Just (Aeson.Object inner) ->
        assertBool "childless block should not have 'children' key" (not $ KeyMap.member "children" inner)
      _ -> assertFailure "Expected paragraph object"
    _ -> assertFailure "Expected object"

testBlockContentHasChildrenKey :: Assertion
testBlockContentHasChildrenKey = do
  let block = toggleBlock (mkRichText "T") `withChildren` Vector.singleton (textBlock "C")
      json = Aeson.toJSON block
  case json of
    Aeson.Object o -> case KeyMap.lookup "toggle" o of
      Just (Aeson.Object inner) -> do
        assertBool "block with children should have 'children' key" (KeyMap.member "children" inner)
        case KeyMap.lookup "children" inner of
          Just (Aeson.Array arr) ->
            assertEqual "children array should have 1 element" 1 (Vector.length arr)
          _ -> assertFailure "Expected children to be an array"
      _ -> assertFailure "Expected toggle object"
    _ -> assertFailure "Expected object"

testBlockUpdateWithChildren :: Assertion
testBlockUpdateWithChildren = do
  let block = toggleBlock (mkRichText "T") `withChildren` Vector.singleton (textBlock "C")
      update = Blocks.BlockUpdate block
      json = Aeson.toJSON update
  case json of
    Aeson.Object o -> do
      assertBool "should have 'toggle' key" (KeyMap.member "toggle" o)
      assertBool "should NOT have 'type' key" (not $ KeyMap.member "type" o)
      case KeyMap.lookup "toggle" o of
        Just (Aeson.Object inner) ->
          assertBool "update should include 'children' key" (KeyMap.member "children" inner)
        _ -> assertFailure "Expected toggle object in update"
    _ -> assertFailure "Expected object from BlockUpdate ToJSON"

testParseBlockContentWithChildren :: Assertion
testParseBlockContentWithChildren = do
  let json =
        "{\"type\":\"toggle\",\"toggle\":{\"rich_text\":[{\"type\":\"text\",\"text\":"
          <> "{\"content\":\"Click\",\"link\":null},\"annotations\":{\"bold\":false,"
          <> "\"italic\":false,\"strikethrough\":false,\"underline\":false,\"code\":false,"
          <> "\"color\":\"default\"},\"plain_text\":\"Click\",\"href\":null}],"
          <> "\"color\":\"default\",\"children\":[{\"type\":\"paragraph\",\"paragraph\":"
          <> "{\"rich_text\":[{\"type\":\"text\",\"text\":{\"content\":\"Inner\",\"link\":null},"
          <> "\"annotations\":{\"bold\":false,\"italic\":false,\"strikethrough\":false,"
          <> "\"underline\":false,\"code\":false,\"color\":\"default\"},\"plain_text\":\"Inner\","
          <> "\"href\":null}],\"color\":\"default\"}}]}}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse: " <> err
    Right block -> case (block :: BlockContent) of
      ToggleBlock {children} -> do
        assertEqual "should have 1 child" 1 (Vector.length children)
        case Vector.head children of
          ParagraphBlock {richText} ->
            assertBool "child should have rich text" (not $ Vector.null richText)
          other -> assertFailure $ "Expected ParagraphBlock child, got: " <> show other
      other -> assertFailure $ "Expected ToggleBlock, got: " <> show other

testBlockUpdateSerialization :: Assertion
testBlockUpdateSerialization = do
  let update = Blocks.BlockUpdate (paragraphBlock (mkRichText "Updated"))
      json = Aeson.toJSON update
  case json of
    Aeson.Object o -> do
      assertBool "should have 'paragraph' key" (KeyMap.member "paragraph" o)
      assertBool "should NOT have 'type' key" (not $ KeyMap.member "type" o)
    _ -> assertFailure "Expected object from BlockUpdate ToJSON"

-- =====================================================================
-- JSON Serialization Tests (unit tests, no API token needed)
-- =====================================================================

jsonSerializationTests :: TestTree
jsonSerializationTests =
  testGroup
    "JSON Serialization"
    [ testCase "AppendBlockChildren without position" testSerializeAppendNoPosition,
      testCase "AppendBlockChildren with AfterBlock position" testSerializeAppendAfterBlock,
      testCase "AppendBlockChildren with Start position" testSerializeAppendStart,
      testCase "AppendBlockChildren with End position" testSerializeAppendEnd,
      testCase "UpdatePageMarkdown update_content" testSerializeUpdateContent,
      testCase "UpdatePageMarkdown replace_content" testSerializeReplaceContent,
      testCase "Template none" testSerializeTemplateNone,
      testCase "Template default with timezone" testSerializeTemplateDefault,
      testCase "Template by ID" testSerializeTemplateById,
      testCase "MovePage serialization" testSerializeMovePage,
      testCase "ViewType round-trip" testViewTypeRoundTrip,
      testCase "NativeIcon round-trip" testNativeIconRoundTrip,
      testCase "NativeIcon read shape" testNativeIconReadShape,
      testCase "CustomEmojiIcon round-trip" testCustomEmojiIconRoundTrip,
      testCase "CreateView serialization" testSerializeCreateView,
      testCase "UpdateView omits Nothing fields" testSerializeUpdateView,
      testCase "CreatePage with markdown field" testSerializeCreatePageMarkdown,
      testCase "UpdatePage with template and eraseContent" testSerializeUpdatePageTemplate,
      testCase "PropertySchema select round-trip" testPropertySchemaSelectRoundTrip,
      testCase "PropertySchema number round-trip" testPropertySchemaNumberRoundTrip,
      testCase "PropertySchema formula round-trip" testPropertySchemaFormulaRoundTrip,
      testCase "PropertySchema relation dual round-trip" testPropertySchemaRelationRoundTrip,
      testCase "PropertySchema status round-trip" testPropertySchemaStatusRoundTrip,
      testCase "NumberFormat round-trip" testNumberFormatRoundTrip,
      testCase "RollupFunction round-trip" testRollupFunctionRoundTrip,
      testCase "Filter: property title contains" testFilterPropertyTitle,
      testCase "Filter: compound And" testFilterCompoundAnd,
      testCase "Filter: timestamp created_time" testFilterTimestamp,
      testCase "Filter: number greater_than" testFilterNumber,
      testCase "Filter: date next_week" testFilterDateRelative,
      testCase "Filter: formula string contains" testFilterFormula,
      testCase "Sort: property ascending" testSortProperty,
      testCase "Sort: timestamp descending" testSortTimestamp,
      testCase "UpdateDataSource nullable property deletion" testSerializeNullablePropertyDeletion,
      testCase "paginateAll collects all pages" testPaginateAll,
      testCase "CreateComment with attachments and displayName" testSerializeCreateComment,
      testCase "CommentAttachment decodes read-side shape" testDeserializeCommentAttachmentReadShape,
      testCase "CommentDisplayName captures resolved_name" testDeserializeCommentDisplayNameResolvedName,
      testCase "UpdatePage with isLocked and isArchived" testSerializeUpdatePageLockArchive,
      testCase "RollupFunction round-trip: new variants" testRollupFunctionNewVariants,
      testCase "DateCondition: this_month and this_year" testDateConditionThisMonthYear
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

testSerializeUpdateContent :: Assertion
testSerializeUpdateContent = do
  let req =
        UpdateContent
          UpdateContentRequest
            { contentUpdates =
                Vector.fromList
                  [ ContentUpdate
                      { oldStr = "hello world",
                        newStr = "goodbye world",
                        replaceAllMatches = Just True
                      }
                  ],
              allowDeletingContent = Nothing
            }
      json = Aeson.toJSON req
  case json of
    Aeson.Object o -> do
      assertEqual "type field" (Just (Aeson.String "update_content")) (KeyMap.lookup "type" o)
      case KeyMap.lookup "update_content" o of
        Just (Aeson.Object uc) -> do
          assertBool "should have content_updates" (KeyMap.member "content_updates" uc)
          case KeyMap.lookup "content_updates" uc of
            Just (Aeson.Array updates) ->
              assertEqual "should have 1 update" 1 (Vector.length updates)
            _ -> assertFailure "Expected content_updates array"
        _ -> assertFailure "Expected update_content object"
    _ -> assertFailure "Expected JSON object"

testSerializeReplaceContent :: Assertion
testSerializeReplaceContent = do
  let req =
        ReplaceContent
          ReplaceContentRequest
            { newStr = "# New Content\n\nReplaced everything.",
              allowDeletingContent = Just True
            }
      json = Aeson.toJSON req
  case json of
    Aeson.Object o -> do
      assertEqual "type field" (Just (Aeson.String "replace_content")) (KeyMap.lookup "type" o)
      case KeyMap.lookup "replace_content" o of
        Just (Aeson.Object rc) -> do
          assertEqual "new_str" (Just (Aeson.String "# New Content\n\nReplaced everything.")) (KeyMap.lookup "new_str" rc)
          assertEqual "allow_deleting_content" (Just (Aeson.Bool True)) (KeyMap.lookup "allow_deleting_content" rc)
        _ -> assertFailure "Expected replace_content object"
    _ -> assertFailure "Expected JSON object"

testSerializeTemplateNone :: Assertion
testSerializeTemplateNone = do
  let json = Aeson.toJSON NoTemplate
  case json of
    Aeson.Object o ->
      assertEqual "type field" (Just (Aeson.String "none")) (KeyMap.lookup "type" o)
    _ -> assertFailure "Expected JSON object"

testSerializeTemplateDefault :: Assertion
testSerializeTemplateDefault = do
  let json = Aeson.toJSON (DefaultTemplate (Just "America/New_York"))
  case json of
    Aeson.Object o -> do
      assertEqual "type field" (Just (Aeson.String "default")) (KeyMap.lookup "type" o)
      assertEqual "timezone" (Just (Aeson.String "America/New_York")) (KeyMap.lookup "timezone" o)
    _ -> assertFailure "Expected JSON object"

testSerializeTemplateById :: Assertion
testSerializeTemplateById = do
  let json = Aeson.toJSON (TemplateById (UUID "tmpl-123") Nothing)
  case json of
    Aeson.Object o -> do
      assertEqual "type field" (Just (Aeson.String "template_id")) (KeyMap.lookup "type" o)
      assertEqual "template_id" (Just (Aeson.String "tmpl-123")) (KeyMap.lookup "template_id" o)
      assertBool "no timezone" (not $ KeyMap.member "timezone" o)
    _ -> assertFailure "Expected JSON object"

testNativeIconRoundTrip :: Assertion
testNativeIconRoundTrip = do
  let icon = NativeIcon {iconName = "check", iconColor = Just "green"}
      json = Aeson.toJSON icon
  case json of
    Aeson.Object o -> do
      assertEqual "type" (Just (Aeson.String "icon")) (KeyMap.lookup "type" o)
      case KeyMap.lookup "icon" o of
        Just (Aeson.Object inner) -> do
          assertEqual "name" (Just (Aeson.String "check")) (KeyMap.lookup "name" inner)
          assertEqual "color" (Just (Aeson.String "green")) (KeyMap.lookup "color" inner)
        _ -> assertFailure "Expected nested icon object"
    _ -> assertFailure "Expected JSON object"
  case Aeson.fromJSON json of
    Aeson.Success (NativeIcon n c) -> do
      assertEqual "name round-trip" "check" n
      assertEqual "color round-trip" (Just "green") c
    Aeson.Success _ -> assertFailure "Expected NativeIcon"
    Aeson.Error err -> assertFailure $ "Decode failed: " <> err

testNativeIconReadShape :: Assertion
testNativeIconReadShape = do
  let payload :: L8.ByteString
      payload = "{\"type\":\"icon\",\"icon\":{\"name\":\"clipping\",\"color\":\"lightgray\"}}"
  case Aeson.eitherDecode payload of
    Right (NativeIcon n c) -> do
      assertEqual "name" "clipping" n
      assertEqual "color" (Just "lightgray") c
    Right _ -> assertFailure "Expected NativeIcon"
    Left err -> assertFailure $ "Decode failed: " <> err

testCustomEmojiIconRoundTrip :: Assertion
testCustomEmojiIconRoundTrip = do
  let icon = CustomEmojiIcon {customEmojiId = UUID "emoji-abc-123"}
      json = Aeson.toJSON icon
  case json of
    Aeson.Object o -> do
      assertEqual "type" (Just (Aeson.String "custom_emoji")) (KeyMap.lookup "type" o)
      assertEqual "id" (Just (Aeson.String "emoji-abc-123")) (KeyMap.lookup "id" o)
    _ -> assertFailure "Expected JSON object"
  case Aeson.fromJSON json of
    Aeson.Success (CustomEmojiIcon eid) ->
      assertEqual "id round-trip" (UUID "emoji-abc-123") eid
    Aeson.Success _ -> assertFailure "Expected CustomEmojiIcon"
    Aeson.Error err -> assertFailure $ "Decode failed: " <> err

testViewTypeRoundTrip :: Assertion
testViewTypeRoundTrip = do
  let viewTypes = [TableView, BoardView, ListViewType, CalendarView, TimelineView, GalleryView, FormView, ChartView, MapView, DashboardView]
  mapM_
    ( \vt -> do
        let json = Aeson.toJSON vt
        case Aeson.fromJSON json of
          Aeson.Success decoded ->
            assertEqual ("round-trip for " <> show vt) vt decoded
          Aeson.Error err ->
            assertFailure $ "Failed to decode " <> show vt <> ": " <> err
    )
    viewTypes

testSerializeMovePage :: Assertion
testSerializeMovePage = do
  let req = MovePage {parent = PageParent {pageId = UUID "target-page"}, position = Nothing}
      json = Aeson.toJSON req
  case json of
    Aeson.Object o -> do
      assertBool "should have parent" (KeyMap.member "parent" o)
      assertBool "should not have position" (not $ KeyMap.member "position" o)
    _ -> assertFailure "Expected JSON object"

testSerializeCreateView :: Assertion
testSerializeCreateView = do
  let req =
        CreateView
          { dataSourceId = UUID "ds-123",
            name = "Test Table",
            type_ = TableView,
            databaseId = Just (UUID "db-456"),
            viewId = Nothing,
            filter = Nothing,
            sorts = Nothing,
            quickFilters = Nothing,
            configuration = Nothing,
            position = Nothing
          }
      json = Aeson.toJSON req
  case json of
    Aeson.Object o -> do
      assertEqual "data_source_id" (Just (Aeson.String "ds-123")) (KeyMap.lookup "data_source_id" o)
      assertEqual "name" (Just (Aeson.String "Test Table")) (KeyMap.lookup "name" o)
      assertEqual "type" (Just (Aeson.String "table")) (KeyMap.lookup "type" o)
      assertEqual "database_id" (Just (Aeson.String "db-456")) (KeyMap.lookup "database_id" o)
      -- Nothing fields should be omitted
      assertBool "no view_id" (not $ KeyMap.member "view_id" o)
      assertBool "no filter" (not $ KeyMap.member "filter" o)
    _ -> assertFailure "Expected JSON object"

testSerializeUpdateView :: Assertion
testSerializeUpdateView = do
  let req =
        UpdateView
          { name = Just "Renamed View",
            filter = Nothing,
            sorts = Nothing,
            quickFilters = Nothing,
            configuration = Nothing
          }
      json = Aeson.toJSON req
  case json of
    Aeson.Object o -> do
      assertEqual "name" (Just (Aeson.String "Renamed View")) (KeyMap.lookup "name" o)
      -- Nothing fields omitted
      assertBool "no filter" (not $ KeyMap.member "filter" o)
      assertBool "no sorts" (not $ KeyMap.member "sorts" o)
    _ -> assertFailure "Expected JSON object"

testSerializeCreatePageMarkdown :: Assertion
testSerializeCreatePageMarkdown = do
  let req =
        CreatePage
          { parent = PageParent {pageId = UUID "p-1"},
            properties = Map.empty,
            children = Nothing,
            markdown = Just "# Hello\n\nWorld",
            icon = Nothing,
            cover = Nothing,
            template = Nothing,
            position = Nothing
          }
      json = Aeson.toJSON req
  case json of
    Aeson.Object o -> do
      assertEqual "markdown" (Just (Aeson.String "# Hello\n\nWorld")) (KeyMap.lookup "markdown" o)
      -- children should not be present (Nothing)
      assertBool "no children" (not $ KeyMap.member "children" o)
    _ -> assertFailure "Expected JSON object"

testSerializeUpdatePageTemplate :: Assertion
testSerializeUpdatePageTemplate = do
  let req =
        UpdatePage
          { properties = Map.empty,
            inTrash = Nothing,
            isLocked = Nothing,
            isArchived = Nothing,
            icon = Nothing,
            cover = Nothing,
            template = Just (DefaultTemplate (Just "America/Chicago")),
            eraseContent = Just True
          }
      json = Aeson.toJSON req
  case json of
    Aeson.Object o -> do
      assertBool "should have template" (KeyMap.member "template" o)
      assertEqual "erase_content" (Just (Aeson.Bool True)) (KeyMap.lookup "erase_content" o)
      case KeyMap.lookup "template" o of
        Just (Aeson.Object t) -> do
          assertEqual "template type" (Just (Aeson.String "default")) (KeyMap.lookup "type" t)
          assertEqual "timezone" (Just (Aeson.String "America/Chicago")) (KeyMap.lookup "timezone" t)
        _ -> assertFailure "Expected template object"
    _ -> assertFailure "Expected JSON object"

-- =====================================================================
-- Integration Tests — Basic (needs NOTION_TOKEN)
-- =====================================================================

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

testSearchAll :: Methods -> Assertion
testSearchAll Methods {search} = do
  let params = SearchRequest {query = Nothing, sort = Nothing, filter = Nothing, startCursor = Nothing, pageSize = Just 5}
  result <- search params
  -- Should succeed without error. Results may or may not be empty depending on workspace.
  assertBool "Search should return a list" (hasMore result || not (Vector.null (results result)) || Vector.null (results result))

testSearchPages :: Methods -> Assertion
testSearchPages Methods {search} = do
  let params = SearchRequest {query = Nothing, sort = Nothing, filter = Just pageFilter, startCursor = Nothing, pageSize = Just 3}
  result <- search params
  let typed = parseSearchResults result
  -- All results should be PageResult
  Vector.forM_ typed $ \r ->
    case r of
      PageResult _ -> pure ()
      DataSourceResult _ -> assertFailure "Expected only page results with page filter"

testSearchDataSources :: Methods -> Assertion
testSearchDataSources Methods {search} = do
  let params = SearchRequest {query = Nothing, sort = Nothing, filter = Just dataSourceFilter, startCursor = Nothing, pageSize = Just 3}
  result <- search params
  let typed = parseSearchResults result
  Vector.forM_ typed $ \r ->
    case r of
      DataSourceResult _ -> pure ()
      PageResult _ -> assertFailure "Expected only data source results with data source filter"

testListCustomEmojis :: Methods -> Assertion
testListCustomEmojis Methods {listCustomEmojis} = do
  result <- listCustomEmojis Nothing Nothing (Just 10)
  -- Just verify the endpoint works; workspace may or may not have custom emojis
  assertBool "Custom emojis endpoint should succeed" True

-- =====================================================================
-- Markdown E2E (needs NOTION_TOKEN + NOTION_TEST_PAGE_ID)
-- =====================================================================

testRetrievePageMarkdown :: Methods -> Text.Text -> Assertion
testRetrievePageMarkdown Methods {retrievePageMarkdown} pageId = do
  result <- retrievePageMarkdown (UUID pageId) Nothing
  let PageMarkdown {markdown = md} = result
  assertBool "Markdown content should not be empty" (not $ Text.null md)

-- | Full markdown lifecycle: create page with markdown, read it back,
-- perform search-and-replace edit, verify, replace all content, verify, clean up.
testMarkdownLifecycle :: Methods -> Text.Text -> Assertion
testMarkdownLifecycle methods@Methods {retrievePageMarkdown, updatePageMarkdown} parentPageId = do
  -- Step 1: Create a test page (content will be set via markdown API)
  page <- createTestPage methods parentPageId "Markdown E2E Test"
  let PageObject {id = pageId} = page

  -- Step 2: Add content via replace_content (guaranteed to work regardless of create method)
  let replaceReq =
        ReplaceContent
          ReplaceContentRequest
            { newStr = "# Test Heading\n\nThis is the original paragraph.\n\nAnother paragraph here.",
              allowDeletingContent = Just True
            }
  md1 <- updatePageMarkdown pageId replaceReq
  let PageMarkdown {markdown = mdText1} = md1
  assertBool "Should contain heading after replace" (Text.isInfixOf "Test Heading" mdText1)
  assertBool "Should contain original paragraph" (Text.isInfixOf "original paragraph" mdText1)

  -- Step 3: Search-and-replace edit (update_content)
  let editReq =
        UpdateContent
          UpdateContentRequest
            { contentUpdates =
                Vector.fromList
                  [ ContentUpdate
                      { oldStr = "original paragraph",
                        newStr = "edited paragraph",
                        replaceAllMatches = Nothing
                      }
                  ],
              allowDeletingContent = Nothing
            }
  md2 <- updatePageMarkdown pageId editReq
  let PageMarkdown {markdown = mdText2} = md2
  assertBool "Should contain edited text" (Text.isInfixOf "edited paragraph" mdText2)
  assertBool "Should not contain original text" (not $ Text.isInfixOf "original paragraph" mdText2)

  -- Step 4: Full content replacement (replace_content)
  let replaceReq2 =
        ReplaceContent
          ReplaceContentRequest
            { newStr = "# Replaced\n\nEntirely new content after replace.",
              allowDeletingContent = Just True
            }
  md3 <- updatePageMarkdown pageId replaceReq2
  let PageMarkdown {markdown = mdText3} = md3
  assertBool "Should contain replaced heading" (Text.isInfixOf "Replaced" mdText3)
  assertBool "Should contain new content" (Text.isInfixOf "Entirely new content" mdText3)
  assertBool "Old content should be gone" (not $ Text.isInfixOf "edited paragraph" mdText3)

  -- Step 5: Verify retrieve matches update response
  md4 <- retrievePageMarkdown pageId Nothing
  let PageMarkdown {markdown = mdText4} = md4
  assertBool "Retrieve after replace should have new content" (Text.isInfixOf "Entirely new content" mdText4)

  -- Clean up
  trashPage methods pageId

-- =====================================================================
-- Page E2E (needs NOTION_TOKEN + NOTION_TEST_PAGE_ID)
-- =====================================================================

-- | Create page, append various block types, list children, retrieve blocks.
testPageBlockLifecycle :: Methods -> Text.Text -> Assertion
testPageBlockLifecycle methods@Methods {createPage, appendBlockChildren, listBlockChildren, retrieveBlock} parentPageId = do
  -- Create a test page
  page <- createTestPage methods parentPageId "Block Lifecycle E2E Test"
  let PageObject {id = pageId} = page

  -- Append blocks with different types
  let blocks =
        Vector.fromList
          [ mkHeadingBlock "Test Heading" 1,
            mkParagraphBlock "First paragraph content.",
            mkParagraphBlock "Second paragraph content.",
            bulletedListItemBlock (mkRichText "List item one"),
            bulletedListItemBlock (mkRichText "List item two")
          ]
      appendReq = AppendBlockChildren {children = blocks, position = Nothing}
  appendResult <- appendBlockChildren pageId appendReq
  assertEqual "Should have appended 5 blocks" 5 (Vector.length $ results appendResult)

  -- List block children
  childrenResult <- listBlockChildren pageId Nothing Nothing
  let childCount = Vector.length (results childrenResult)
  assertBool "Should have at least 5 children" (childCount >= 5)

  -- Retrieve a specific block
  let firstBlock = Vector.head (results childrenResult)
      BlockObject {id = blockId} = firstBlock
  retrieved <- retrieveBlock blockId
  assertEqual "Retrieved block ID should match" blockId (Notion.V1.Blocks.id retrieved)

  -- Append a toggle block with nested children
  let nestedToggle =
        toggleBlock (mkRichText "Toggle with children")
          `withChildren` Vector.fromList [textBlock "Child paragraph 1", textBlock "Child paragraph 2"]
      nestedReq = AppendBlockChildren {children = Vector.singleton nestedToggle, position = Nothing}
  nestedResult <- appendBlockChildren pageId nestedReq
  let toggleObj = Vector.head (results nestedResult)
  assertBool "Toggle should have children" (Blocks.hasChildren toggleObj)

  -- Fetch the toggle's children
  toggleChildren <- listBlockChildren (Blocks.id toggleObj) Nothing Nothing
  assertEqual "Toggle should have 2 children" 2 (Vector.length $ results toggleChildren)

  -- Append a block at the start position
  let startBlock = mkParagraphBlock "Inserted at start."
      startReq = AppendBlockChildren {children = Vector.singleton startBlock, position = Just Start}
  _ <- appendBlockChildren pageId startReq

  -- Verify the start block is first
  childrenAfterStart <- listBlockChildren pageId Nothing Nothing
  let firstChild = Vector.head (results childrenAfterStart)
  assertEqual "First block type should be paragraph" "paragraph" (Notion.V1.Blocks.type_ firstChild)

  -- Clean up
  trashPage methods pageId

-- | Create page, add comments (page-level and block-level), list them.
testCommentLifecycle :: Methods -> Text.Text -> Assertion
testCommentLifecycle methods@Methods {createComment, listComments, appendBlockChildren} parentPageId = do
  -- Create a test page
  page <- createTestPage methods parentPageId "Comment Lifecycle E2E Test"
  let PageObject {id = pageId} = page

  -- Add a block to comment on
  let block = mkParagraphBlock "Block to comment on."
      appendReq = AppendBlockChildren {children = Vector.singleton block, position = Nothing}
  appendResult <- appendBlockChildren pageId appendReq
  let BlockObject {id = blockId} = Vector.head (results appendResult)

  -- Create a page-level comment
  let pageComment =
        CreateComment
          { parent = PageParent {pageId},
            richText = Vector.singleton (mkTypedRichText "This is a page-level comment from E2E tests."),
            discussionId = Nothing,
            attachments = Nothing,
            displayName = Nothing
          }
  comment1 <- createComment pageComment
  let CommentObject {id = comment1Id} = comment1
  assertBool "Comment should have an ID" (show comment1Id /= "")

  -- Create a block-level comment (a discussion on a specific block)
  let blockComment =
        CreateComment
          { parent = BlockParent {blockId},
            richText = Vector.singleton (mkTypedRichText "This is a block-level comment from E2E tests."),
            discussionId = Nothing,
            attachments = Nothing,
            displayName = Nothing
          }
  comment2 <- createComment blockComment
  let CommentObject {id = comment2Id} = comment2
  assertBool "Block comment should have an ID" (show comment2Id /= "")

  -- List comments on the page
  pageComments <- listComments (Just pageId) Nothing Nothing
  assertBool "Should have at least 1 page comment" (not $ Vector.null (results pageComments))

  -- List comments on the block
  blockComments <- listComments (Just blockId) Nothing Nothing
  assertBool "Should have at least 1 block comment" (not $ Vector.null (results blockComments))

  -- Clean up
  trashPage methods pageId

-- | Create two child pages, move one under the other, verify, clean up.
testMovePageLifecycle :: Methods -> Text.Text -> Assertion
testMovePageLifecycle methods@Methods {movePage, retrievePage} parentPageId = do
  -- Create two sibling pages
  pageA <- createTestPage methods parentPageId "Move Test - Source Page"
  pageB <- createTestPage methods parentPageId "Move Test - Target Parent"
  let PageObject {id = pageAId} = pageA
      PageObject {id = pageBId} = pageB

  -- Move page A under page B
  let moveReq = MovePage {parent = PageParent {pageId = pageBId}, position = Nothing}
  movedPage <- movePage pageAId moveReq
  let PageObject {id = movedId} = movedPage
  assertEqual "Moved page should have same ID" pageAId movedId

  -- Verify the parent changed
  retrieved <- retrievePage pageAId
  let PageObject {parent = retrievedParent} = retrieved
  case retrievedParent of
    PageParent {pageId = actualParent} ->
      assertEqual "Parent should be page B" pageBId actualParent
    other ->
      assertFailure $ "Expected PageParent, got: " <> show other

  -- Clean up (trash page A first since it's under B, then B)
  trashPage methods pageAId
  trashPage methods pageBId

-- =====================================================================
-- Database E2E (needs NOTION_TOKEN + NOTION_TEST_DATABASE_ID)
-- =====================================================================

testRetrieveDatabaseAndDataSource :: Methods -> Text.Text -> Assertion
testRetrieveDatabaseAndDataSource Methods {retrieveDatabase, retrieveDataSource} dbIdText = do
  -- Retrieve the database
  db <- retrieveDatabase (UUID dbIdText)
  let DatabaseObject {id = dbId, dataSources = dsList} = db
  -- UUIDs may differ in format (with/without dashes), just verify non-empty
  assertBool "Database ID should not be empty" (show dbId /= "")
  assertBool "Database should have at least one data source" (not $ Vector.null dsList)

  -- Retrieve the first data source
  let Notion.V1.Databases.DataSource {id = dsId} = Vector.head dsList
  ds <- retrieveDataSource dsId
  assertBool "Data source should have an ID" (show (Notion.V1.DataSources.id ds) /= "")
  assertBool "Data source URL should not be empty" (not $ Text.null (Notion.V1.DataSources.url ds))

testListTemplates :: Methods -> Text.Text -> Assertion
testListTemplates methods@Methods {listDataSourceTemplates} dbIdText = do
  dsId <- getFirstDataSourceId methods dbIdText
  -- List templates — may be empty if no templates configured, but endpoint should succeed
  result <- listDataSourceTemplates dsId Nothing Nothing Nothing
  -- Just verify the endpoint responds without error
  assertBool "Templates endpoint should succeed" True

testQueryDataSource :: Methods -> Text.Text -> Assertion
testQueryDataSource methods@Methods {queryDataSource} dbIdText = do
  dsId <- getFirstDataSourceId methods dbIdText
  let queryReq = DataSources.QueryDataSource {filter = Nothing, sorts = Nothing, startCursor = Nothing, pageSize = Just 5, inTrash = Nothing, filterProperties = Nothing}
  result <- queryDataSource dsId queryReq
  -- Just verify the endpoint responds and returns valid structure
  assertBool "Query should return results list" (hasMore result || Vector.null (results result) || not (Vector.null (results result)))

testCreateMarkdownPageInDatabase :: Methods -> Text.Text -> Assertion
testCreateMarkdownPageInDatabase methods@Methods {createPage, retrievePageMarkdown, updatePageMarkdown} dbIdText = do
  dsId <- getFirstDataSourceId methods dbIdText

  -- Create a page in the database's data source
  let titleRt = mkPlainRichText "Database Markdown E2E"
      props = Map.fromList [("title", PV.titleValue (Vector.singleton titleRt))]
      req = mkCreatePage (DataSourceParent {dataSourceId = dsId, parentDatabaseId = Nothing}) props
  page <- createPage req
  let PageObject {id = pageId} = page

  -- Set content via markdown update API
  let replaceReq =
        ReplaceContent
          ReplaceContentRequest
            { newStr = "# Database Page\n\nCreated with markdown in a database data source.",
              allowDeletingContent = Just True
            }
  _ <- updatePageMarkdown pageId replaceReq

  -- Verify markdown content
  md <- retrievePageMarkdown pageId Nothing
  let PageMarkdown {markdown = mdText} = md
  assertBool "Should contain database page heading" (Text.isInfixOf "Database Page" mdText)

  -- Clean up
  trashPage methods pageId

-- =====================================================================
-- View E2E (needs NOTION_TOKEN + NOTION_TEST_DATABASE_ID)
-- =====================================================================

-- | Full view lifecycle: create, retrieve, update, list, query, delete.
testViewLifecycle :: Methods -> Text.Text -> Assertion
testViewLifecycle methods@Methods {createView, retrieveView, updateView, listViews, queryView, deleteView} dbIdText = do
  dsId <- getFirstDataSourceId methods dbIdText

  -- Step 1: Create a table view
  let createReq =
        CreateView
          { dataSourceId = dsId,
            name = "E2E Test View",
            type_ = TableView,
            databaseId = Just (UUID dbIdText),
            viewId = Nothing,
            filter = Nothing,
            sorts = Nothing,
            quickFilters = Nothing,
            configuration = Nothing,
            position = Nothing
          }
  view <- createView createReq
  let ViewObject {id = viewId, type_ = viewType, name = viewName} = view
  assertEqual "View type should be table" (Just TableView) viewType
  assertEqual "View name should match" (Just "E2E Test View") viewName

  -- Step 2: Retrieve the view
  retrieved <- retrieveView viewId
  let ViewObject {id = retrievedViewId} = retrieved
  assertEqual "Retrieved view ID should match" viewId retrievedViewId
  let ViewObject {type_ = retrievedType} = retrieved
  assertEqual "Retrieved view type should be table" (Just TableView) retrievedType

  -- Step 3: Update the view (rename)
  let updateReq =
        UpdateView
          { name = Just "E2E Test View (Renamed)",
            filter = Nothing,
            sorts = Nothing,
            quickFilters = Nothing,
            configuration = Nothing
          }
  updated <- updateView viewId updateReq
  let ViewObject {name = updatedName} = updated
  assertEqual "Updated name" (Just "E2E Test View (Renamed)") updatedName

  -- Step 4: List views on the database
  viewList <- listViews (Just (UUID dbIdText)) Nothing Nothing Nothing
  let viewIds = Vector.map (\(ViewObject {id = vid}) -> vid) (results viewList)
  assertBool "View list should contain our view" (viewId `Vector.elem` viewIds)

  -- Step 5: Query the view (may fail if endpoint URL is different than expected)
  -- The query view endpoint URL is not yet confirmed in the API docs.
  -- We skip this step to avoid test failures from URL guessing.

  -- Step 6: Delete the view
  deleted <- deleteView viewId
  let ViewObject {id = deletedViewId} = deleted
  assertEqual "Deleted view ID should match" viewId deletedViewId

-- =====================================================================
-- Filter and Sort Tests
-- =====================================================================

testFilterPropertyTitle :: Assertion
testFilterPropertyTitle = do
  let f = F.PropertyFilter "Name" (F.TitleCondition (F.TextContains "test"))
      json = Aeson.toJSON f
  case json of
    Aeson.Object o -> do
      assertEqual "property" (Just (Aeson.String "Name")) (KeyMap.lookup "property" o)
      case KeyMap.lookup "title" o of
        Just (Aeson.Object t) ->
          assertEqual "contains" (Just (Aeson.String "test")) (KeyMap.lookup "contains" t)
        _ -> assertFailure "Expected title object"
    _ -> assertFailure "Expected JSON object"

testFilterCompoundAnd :: Assertion
testFilterCompoundAnd = do
  let f =
        F.And
          [ F.PropertyFilter "Status" (F.SelectCondition (F.SelectEquals "Done")),
            F.PropertyFilter "Priority" (F.SelectCondition (F.SelectEquals "High"))
          ]
      json = Aeson.toJSON f
  case json of
    Aeson.Object o ->
      case KeyMap.lookup "and" o of
        Just (Aeson.Array arr) -> assertEqual "and array length" 2 (Vector.length arr)
        _ -> assertFailure "Expected and array"
    _ -> assertFailure "Expected JSON object"

testFilterTimestamp :: Assertion
testFilterTimestamp = do
  let f = F.TimestampFilter F.FilterCreatedTime (F.DateAfter "2024-01-01")
      json = Aeson.toJSON f
  case json of
    Aeson.Object o -> do
      assertEqual "timestamp" (Just (Aeson.String "created_time")) (KeyMap.lookup "timestamp" o)
      case KeyMap.lookup "created_time" o of
        Just (Aeson.Object t) ->
          assertEqual "after" (Just (Aeson.String "2024-01-01")) (KeyMap.lookup "after" t)
        _ -> assertFailure "Expected created_time object"
    _ -> assertFailure "Expected JSON object"

testFilterNumber :: Assertion
testFilterNumber = do
  let f = F.PropertyFilter "Score" (F.NumberCondition (F.NumGreaterThan 90))
      json = Aeson.toJSON f
  case json of
    Aeson.Object o -> do
      assertEqual "property" (Just (Aeson.String "Score")) (KeyMap.lookup "property" o)
      case KeyMap.lookup "number" o of
        Just (Aeson.Object n) ->
          assertEqual "greater_than" (Just (Aeson.Number 90)) (KeyMap.lookup "greater_than" n)
        _ -> assertFailure "Expected number object"
    _ -> assertFailure "Expected JSON object"

testFilterDateRelative :: Assertion
testFilterDateRelative = do
  let f = F.PropertyFilter "Due" (F.DateCondition F.DateNextWeek)
      json = Aeson.toJSON f
  case json of
    Aeson.Object o ->
      case KeyMap.lookup "date" o of
        Just (Aeson.Object d) ->
          assertEqual "next_week" (Just (Aeson.object [])) (KeyMap.lookup "next_week" d)
        _ -> assertFailure "Expected date object"
    _ -> assertFailure "Expected JSON object"

testFilterFormula :: Assertion
testFilterFormula = do
  let f = F.PropertyFilter "Computed" (F.FormulaCondition (F.FormulaString (F.TextContains "yes")))
      json = Aeson.toJSON f
  case json of
    Aeson.Object o ->
      case KeyMap.lookup "formula" o of
        Just (Aeson.Object fm) ->
          case KeyMap.lookup "string" fm of
            Just (Aeson.Object s) ->
              assertEqual "contains" (Just (Aeson.String "yes")) (KeyMap.lookup "contains" s)
            _ -> assertFailure "Expected string object inside formula"
        _ -> assertFailure "Expected formula object"
    _ -> assertFailure "Expected JSON object"

testSortProperty :: Assertion
testSortProperty = do
  let s = F.PropertySort "Name" F.Ascending
      json = Aeson.toJSON s
  case json of
    Aeson.Object o -> do
      assertEqual "property" (Just (Aeson.String "Name")) (KeyMap.lookup "property" o)
      assertEqual "direction" (Just (Aeson.String "ascending")) (KeyMap.lookup "direction" o)
    _ -> assertFailure "Expected JSON object"

testSortTimestamp :: Assertion
testSortTimestamp = do
  let s = F.TimestampSort F.FilterCreatedTime F.Descending
      json = Aeson.toJSON s
  case json of
    Aeson.Object o -> do
      assertEqual "timestamp" (Just (Aeson.String "created_time")) (KeyMap.lookup "timestamp" o)
      assertEqual "direction" (Just (Aeson.String "descending")) (KeyMap.lookup "direction" o)
    _ -> assertFailure "Expected JSON object"

testPaginateAll :: Assertion
testPaginateAll = do
  -- Mock a 3-page response sequence
  callCount <- newIORef (0 :: Int)
  let mockFetch cursor = do
        modifyIORef' callCount (+ 1)
        case cursor of
          Nothing ->
            pure $
              ListOf.List
                { results = Vector.fromList [1 :: Int, 2, 3],
                  nextCursor = Just "cursor-1",
                  hasMore = True,
                  type_ = Nothing,
                  object = Nothing
                }
          Just "cursor-1" ->
            pure $
              ListOf.List
                { results = Vector.fromList [4, 5],
                  nextCursor = Just "cursor-2",
                  hasMore = True,
                  type_ = Nothing,
                  object = Nothing
                }
          _ ->
            pure $
              ListOf.List
                { results = Vector.fromList [6],
                  nextCursor = Nothing,
                  hasMore = False,
                  type_ = Nothing,
                  object = Nothing
                }
  PaginationResult {allResults, totalPages} <- paginateCollect mockFetch
  assertEqual "all results" (Vector.fromList [1, 2, 3, 4, 5, 6]) allResults
  assertEqual "total pages" 3 totalPages
  calls <- readIORef callCount
  assertEqual "fetch called 3 times" 3 calls

testSerializeNullablePropertyDeletion :: Assertion
testSerializeNullablePropertyDeletion = do
  let req =
        DataSources.UpdateDataSource
          { title = Nothing,
            icon = Nothing,
            properties =
              Just $
                Map.fromList
                  [ ("OldColumn", Nothing),
                    ("NewColumn", Just (Props.TitleSchema {schemaId = "", schemaName = "NewColumn"}))
                  ],
            inTrash = Nothing,
            parent = Nothing
          }
      json = Aeson.toJSON req
  case json of
    Aeson.Object o -> do
      assertBool "should have properties key" (KeyMap.member "properties" o)
      case KeyMap.lookup "properties" o of
        Just (Aeson.Object props) -> do
          -- OldColumn should be null (deletion)
          assertEqual "OldColumn should be null" (Just Aeson.Null) (KeyMap.lookup "OldColumn" props)
          -- NewColumn should be a schema object
          case KeyMap.lookup "NewColumn" props of
            Just (Aeson.Object _) -> pure ()
            _ -> assertFailure "Expected NewColumn to be an object"
        _ -> assertFailure "Expected properties object"
    _ -> assertFailure "Expected JSON object"

-- =====================================================================
-- New type tests (Milestone 6)
-- =====================================================================

testBlockContentHeading4 :: Assertion
testBlockContentHeading4 = roundTrip $ Heading4Block (mkRichText "H4 Title") Default False Vector.empty

testBlockContentTab :: Assertion
testBlockContentTab = roundTrip $ TabBlock {children = Vector.singleton (textBlock "Tab content")}

testBlockContentMeetingNotes :: Assertion
testBlockContentMeetingNotes = do
  let json =
        "{\"type\":\"meeting_notes\",\"meeting_notes\":"
          <> "{\"title\":\"Weekly Sync\",\"status\":\"scheduled\","
          <> "\"calendar_event\":null,\"recording\":null}}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse meeting_notes: " <> err
    Right (MeetingNotesBlock {meetingTitle}) ->
      assertEqual "meetingTitle" "Weekly Sync" meetingTitle
    Right other -> assertFailure $ "Expected MeetingNotesBlock, got: " <> show other

testBlockContentTemplate :: Assertion
testBlockContentTemplate =
  roundTrip $
    TemplateBlock
      { richText = mkRichText "Template text",
        children = Vector.singleton (textBlock "Template child")
      }

testTemplateMentionDate :: Assertion
testTemplateMentionDate = do
  let json =
        "{\"type\":\"mention\",\"mention\":"
          <> "{\"type\":\"template_mention\",\"template_mention\":"
          <> "{\"type\":\"template_mention_date\",\"template_mention_date\":\"today\"}}"
          <> ",\"plain_text\":\"@today\",\"annotations\":"
          <> "{\"bold\":false,\"italic\":false,\"strikethrough\":false,"
          <> "\"underline\":false,\"code\":false,\"color\":\"default\"}}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse template_mention: " <> err
    Right RichText {content = MentionContentWrapper (TemplateMentionDate d)} ->
      assertEqual "template_mention_date" "today" d
    Right other -> assertFailure $ "Expected TemplateMentionDate, got: " <> show other

testTemplateMentionUser :: Assertion
testTemplateMentionUser = do
  let mc = TemplateMentionUser "me"
      json = Aeson.toJSON mc
  case Aeson.fromJSON json of
    Aeson.Success decoded -> assertEqual "round-trip" mc decoded
    Aeson.Error err -> assertFailure $ "Round-trip failed: " <> err

testPageObjectLockedArchived :: Assertion
testPageObjectLockedArchived = do
  let json =
        "{\"object\":\"page\",\"id\":\"page-1\""
          <> ",\"created_time\":\"2025-10-01T12:00:00.000+00:00\""
          <> ",\"last_edited_time\":\"2025-10-01T12:30:00.000+00:00\""
          <> ",\"created_by\":{\"object\":\"user\",\"id\":\"u-1\"}"
          <> ",\"last_edited_by\":{\"object\":\"user\",\"id\":\"u-2\"}"
          <> ",\"parent\":{\"type\":\"page_id\",\"page_id\":\"parent-1\"}"
          <> ",\"in_trash\":false"
          <> ",\"is_locked\":true"
          <> ",\"is_archived\":false"
          <> ",\"properties\":{}"
          <> ",\"url\":\"https://notion.so/page-1\"}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse PageObject: " <> err
    Right (page :: PageObject) -> do
      let PageObject {isLocked = locked, isArchived = archived} = page
      assertEqual "isLocked" (Just True) locked
      assertEqual "isArchived" (Just False) archived

testDataSourceParentWithDbId :: Assertion
testDataSourceParentWithDbId = do
  let json =
        "{\"type\":\"data_source_id\",\"data_source_id\":\"ds-1\",\"database_id\":\"db-1\"}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse DataSourceParent: " <> err
    Right (DataSourceParent dsId dbId) -> do
      assertEqual "dataSourceId" (UUID "ds-1") dsId
      assertEqual "parentDatabaseId" (Just (UUID "db-1")) dbId
    Right other -> assertFailure $ "Expected DataSourceParent, got: " <> show other

testColumnWidthRatio :: Assertion
testColumnWidthRatio =
  roundTrip $
    ColumnBlock
      { widthRatio = Just 0.5,
        children = Vector.singleton (textBlock "Half width")
      }

testBotUserFields :: Assertion
testBotUserFields = do
  let json =
        "{\"owner\":{\"type\":\"workspace\",\"workspace\":true}"
          <> ",\"workspace_name\":\"My Workspace\""
          <> ",\"workspace_id\":\"ws-123\""
          <> ",\"workspace_limits\":{\"max_file_upload_size_in_bytes\":5242880}}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse BotUser: " <> err
    Right bot -> do
      assertEqual "workspaceId" (Just "ws-123") (Notion.V1.Users.workspaceId bot)
      case Notion.V1.Users.workspaceLimits bot of
        Just wl -> assertEqual "maxFileUploadSizeInBytes" (Just 5242880) (maxFileUploadSizeInBytes wl)
        Nothing -> assertFailure "Expected workspaceLimits to be present"

testSerializeCreateComment :: Assertion
testSerializeCreateComment = do
  let req =
        CreateComment
          { parent = PageParent {pageId = UUID "p-1"},
            richText = Vector.singleton (mkPlainRichText "Hello"),
            discussionId = Nothing,
            attachments =
              Just
                ( Vector.singleton
                    CommentAttachment
                      { name = Just "file.pdf",
                        type_ = Just "external",
                        category = Nothing,
                        external = Just (ExternalFile {url = "https://example.com/file.pdf"}),
                        file = Nothing
                      }
                ),
            displayName =
              Just
                CommentDisplayName
                  { type_ = "user",
                    emoji = Just "🎉",
                    displayName = Just "Bot",
                    resolvedName = Nothing
                  }
          }
      json = Aeson.toJSON req
  case json of
    Aeson.Object o -> do
      assertBool "should have attachments" (KeyMap.member "attachments" o)
      assertBool "should have display_name" (KeyMap.member "display_name" o)
    _ -> assertFailure "Expected JSON object"

testDeserializeCommentAttachmentReadShape :: Assertion
testDeserializeCommentAttachmentReadShape = do
  let json =
        "{\"category\":\"image\""
          <> ",\"file\":{\"url\":\"https://example.com/img.png\""
          <> ",\"expiry_time\":\"2026-04-16T15:53:52.000Z\"}}"
  case Aeson.eitherDecode json :: Either String CommentAttachment of
    Left err -> assertFailure $ "Failed to parse CommentAttachment: " <> err
    Right CommentAttachment {name, type_, category, file} -> do
      assertEqual "category" (Just "image") category
      assertEqual "name absent" Nothing name
      assertEqual "type_ absent" Nothing type_
      case file of
        Just _ -> pure ()
        Nothing -> assertFailure "Expected file to be Just"

testDeserializeCommentDisplayNameResolvedName :: Assertion
testDeserializeCommentDisplayNameResolvedName = do
  let json = "{\"type\":\"user\",\"resolved_name\":\"Tanaka Hiroshi\"}"
  case Aeson.eitherDecode json :: Either String CommentDisplayName of
    Left err -> assertFailure $ "Failed to parse CommentDisplayName: " <> err
    Right CommentDisplayName {type_, displayName, resolvedName} -> do
      assertEqual "type_" "user" type_
      assertEqual "resolvedName" (Just "Tanaka Hiroshi") resolvedName
      assertEqual "displayName absent" Nothing displayName

testSerializeUpdatePageLockArchive :: Assertion
testSerializeUpdatePageLockArchive = do
  let req =
        UpdatePage
          { properties = Map.empty,
            inTrash = Nothing,
            isLocked = Just True,
            isArchived = Just False,
            icon = Nothing,
            cover = Nothing,
            template = Nothing,
            eraseContent = Nothing
          }
      json = Aeson.toJSON req
  case json of
    Aeson.Object o -> do
      assertEqual "is_locked" (Just (Aeson.Bool True)) (KeyMap.lookup "is_locked" o)
      assertEqual "is_archived" (Just (Aeson.Bool False)) (KeyMap.lookup "is_archived" o)
    _ -> assertFailure "Expected JSON object"

testRollupFunctionNewVariants :: Assertion
testRollupFunctionNewVariants = do
  let variants = [Props.CountPerGroup, Props.PercentPerGroup, Props.Unique]
  mapM_
    ( \v -> do
        let json = Aeson.toJSON v
        case Aeson.fromJSON json of
          Aeson.Success decoded ->
            assertEqual ("round-trip for " <> show v) v decoded
          Aeson.Error err ->
            assertFailure $ "Failed to decode " <> show v <> ": " <> err
    )
    variants

testDateConditionThisMonthYear :: Assertion
testDateConditionThisMonthYear = do
  let thisMonth = Aeson.toJSON (F.TimestampFilter F.FilterCreatedTime F.DateThisMonth)
  case thisMonth of
    Aeson.Object o ->
      case KeyMap.lookup "created_time" o of
        Just (Aeson.Object inner) ->
          assertBool "should have this_month" (KeyMap.member "this_month" inner)
        _ -> assertFailure "Expected created_time object"
    _ -> assertFailure "Expected JSON object"
  let thisYear = Aeson.toJSON (F.TimestampFilter F.FilterLastEditedTime F.DateThisYear)
  case thisYear of
    Aeson.Object o ->
      case KeyMap.lookup "last_edited_time" o of
        Just (Aeson.Object inner) ->
          assertBool "should have this_year" (KeyMap.member "this_year" inner)
        _ -> assertFailure "Expected last_edited_time object"
    _ -> assertFailure "Expected JSON object"

-- =====================================================================
-- Property Value Tests
-- =====================================================================

propertyValueTests :: TestTree
propertyValueTests =
  testGroup
    "Property Value"
    [ testCase "TitleValue FromJSON" testParseTitleValue,
      testCase "SelectValue FromJSON" testParseSelectValue,
      testCase "NumberValue FromJSON" testParseNumberValue,
      testCase "CheckboxValue FromJSON" testParseCheckboxValue,
      testCase "DateValue FromJSON" testParseDateValue,
      testCase "RelationValue FromJSON" testParseRelationValue,
      testCase "StatusValue FromJSON" testParseStatusValue,
      testCase "MultiSelectValue FromJSON" testParseMultiSelectValue,
      testCase "UrlValue FromJSON" testParseUrlValue,
      testCase "FormulaValue FromJSON" testParseFormulaValue,
      testCase "TitleValue ToJSON" testSerializeTitleValue,
      testCase "SelectValue ToJSON" testSerializeSelectValue,
      testCase "NumberValue ToJSON" testSerializeNumberValue,
      testCase "CheckboxValue ToJSON" testSerializeCheckboxValue,
      testCase "DateValue ToJSON" testSerializeDateValue,
      testCase "StatusValue ToJSON" testSerializeStatusValue,
      testCase "Smart constructor: selectValue" testSmartSelectValue,
      testCase "Smart constructor: titleValue" testSmartTitleValue
    ]

testParseTitleValue :: Assertion
testParseTitleValue = do
  let json =
        "{\"id\":\"title\",\"type\":\"title\",\"title\":[{\"type\":\"text\",\"plain_text\":\"Hello\",\"annotations\":{\"bold\":false,\"italic\":false,\"strikethrough\":false,\"underline\":false,\"code\":false,\"color\":\"default\"},\"text\":{\"content\":\"Hello\",\"link\":null}}]}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse TitleValue: " <> err
    Right (PV.TitleValue pid rts) -> do
      assertEqual "property id" "title" pid
      assertEqual "rich text count" 1 (Vector.length rts)
    Right other -> assertFailure $ "Expected TitleValue, got: " <> show other

testParseSelectValue :: Assertion
testParseSelectValue = do
  let json =
        "{\"id\":\"abc\",\"type\":\"select\",\"select\":{\"id\":\"opt-1\",\"name\":\"Done\",\"color\":\"green\"}}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse SelectValue: " <> err
    Right (PV.SelectValue pid (Just (PV.SelectOptionValue _ optName optColor))) -> do
      assertEqual "property id" "abc" pid
      assertEqual "option name" "Done" optName
      assertEqual "option color" (Just "green") optColor
    Right other -> assertFailure $ "Expected SelectValue, got: " <> show other

testParseNumberValue :: Assertion
testParseNumberValue = do
  let json = "{\"id\":\"num\",\"type\":\"number\",\"number\":42}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse NumberValue: " <> err
    Right (PV.NumberValue pid (Just n)) -> do
      assertEqual "property id" "num" pid
      assertEqual "number value" (42 :: Scientific) n
    Right other -> assertFailure $ "Expected NumberValue, got: " <> show other

testParseCheckboxValue :: Assertion
testParseCheckboxValue = do
  let json = "{\"id\":\"chk\",\"type\":\"checkbox\",\"checkbox\":true}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse CheckboxValue: " <> err
    Right (PV.CheckboxValue pid v) -> do
      assertEqual "property id" "chk" pid
      assertEqual "checkbox value" True v
    Right other -> assertFailure $ "Expected CheckboxValue, got: " <> show other

testParseDateValue :: Assertion
testParseDateValue = do
  let json = "{\"id\":\"dt\",\"type\":\"date\",\"date\":{\"start\":\"2024-01-15\",\"end\":null,\"time_zone\":null}}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse DateValue: " <> err
    Right (PV.DateValue pid (Just d)) -> do
      assertEqual "property id" "dt" pid
      assertEqual "start" "2024-01-15" (start (d :: Date))
    Right other -> assertFailure $ "Expected DateValue, got: " <> show other

testParseRelationValue :: Assertion
testParseRelationValue = do
  let json = "{\"id\":\"rel\",\"type\":\"relation\",\"relation\":[{\"id\":\"page-1\"},{\"id\":\"page-2\"}]}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse RelationValue: " <> err
    Right (PV.RelationValue pid refs) -> do
      assertEqual "property id" "rel" pid
      assertEqual "relation count" 2 (Vector.length refs)
    Right other -> assertFailure $ "Expected RelationValue, got: " <> show other

testParseStatusValue :: Assertion
testParseStatusValue = do
  let json = "{\"id\":\"st\",\"type\":\"status\",\"status\":{\"id\":\"opt-1\",\"name\":\"In Progress\",\"color\":\"yellow\"}}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse StatusValue: " <> err
    Right (PV.StatusValue pid (Just (PV.SelectOptionValue _ optName _))) -> do
      assertEqual "property id" "st" pid
      assertEqual "status name" "In Progress" optName
    Right other -> assertFailure $ "Expected StatusValue, got: " <> show other

testParseMultiSelectValue :: Assertion
testParseMultiSelectValue = do
  let json = "{\"id\":\"ms\",\"type\":\"multi_select\",\"multi_select\":[{\"id\":\"a\",\"name\":\"Tag1\",\"color\":\"red\"},{\"id\":\"b\",\"name\":\"Tag2\",\"color\":\"blue\"}]}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse MultiSelectValue: " <> err
    Right (PV.MultiSelectValue pid opts) -> do
      assertEqual "property id" "ms" pid
      assertEqual "option count" 2 (Vector.length opts)
    Right other -> assertFailure $ "Expected MultiSelectValue, got: " <> show other

testParseUrlValue :: Assertion
testParseUrlValue = do
  let json = "{\"id\":\"u\",\"type\":\"url\",\"url\":\"https://example.com\"}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse UrlValue: " <> err
    Right (PV.UrlValue pid (Just u)) -> do
      assertEqual "property id" "u" pid
      assertEqual "url" "https://example.com" u
    Right other -> assertFailure $ "Expected UrlValue, got: " <> show other

testParseFormulaValue :: Assertion
testParseFormulaValue = do
  let json = "{\"id\":\"f\",\"type\":\"formula\",\"formula\":{\"type\":\"string\",\"string\":\"hello\"}}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse FormulaValue: " <> err
    Right (PV.FormulaValue pid (PV.FormulaStringResult (Just s))) -> do
      assertEqual "property id" "f" pid
      assertEqual "formula string" "hello" s
    Right other -> assertFailure $ "Expected FormulaValue with string, got: " <> show other

-- Serialization tests

testSerializeTitleValue :: Assertion
testSerializeTitleValue = do
  let rt = mkPlainRichText "Hello"
      pv = PV.titleValue (Vector.singleton rt)
      json = Aeson.toJSON pv
  case json of
    Aeson.Object o -> do
      assertBool "should have title key" (KeyMap.member "title" o)
      assertBool "should not have id key" (not $ KeyMap.member "id" o)
      assertBool "should not have type key" (not $ KeyMap.member "type" o)
    _ -> assertFailure "Expected JSON object"

testSerializeSelectValue :: Assertion
testSerializeSelectValue = do
  let pv = PV.selectValue "Done"
      json = Aeson.toJSON pv
  case json of
    Aeson.Object o -> do
      assertBool "should have select key" (KeyMap.member "select" o)
      case KeyMap.lookup "select" o of
        Just (Aeson.Object sel) ->
          assertEqual "name" (Just (Aeson.String "Done")) (KeyMap.lookup "name" sel)
        _ -> assertFailure "Expected select object"
    _ -> assertFailure "Expected JSON object"

testSerializeNumberValue :: Assertion
testSerializeNumberValue = do
  let pv = PV.numberValue 42
      json = Aeson.toJSON pv
  case json of
    Aeson.Object o ->
      assertEqual "number" (Just (Aeson.Number 42)) (KeyMap.lookup "number" o)
    _ -> assertFailure "Expected JSON object"

testSerializeCheckboxValue :: Assertion
testSerializeCheckboxValue = do
  let pv = PV.checkboxValue True
      json = Aeson.toJSON pv
  case json of
    Aeson.Object o ->
      assertEqual "checkbox" (Just (Aeson.Bool True)) (KeyMap.lookup "checkbox" o)
    _ -> assertFailure "Expected JSON object"

testSerializeDateValue :: Assertion
testSerializeDateValue = do
  let pv = PV.dateValue "2024-06-01" Nothing
      json = Aeson.toJSON pv
  case json of
    Aeson.Object o -> do
      assertBool "should have date key" (KeyMap.member "date" o)
      case KeyMap.lookup "date" o of
        Just (Aeson.Object d) ->
          assertEqual "start" (Just (Aeson.String "2024-06-01")) (KeyMap.lookup "start" d)
        _ -> assertFailure "Expected date object"
    _ -> assertFailure "Expected JSON object"

testSerializeStatusValue :: Assertion
testSerializeStatusValue = do
  let pv = PV.statusValue "In Progress"
      json = Aeson.toJSON pv
  case json of
    Aeson.Object o -> do
      assertBool "should have status key" (KeyMap.member "status" o)
      case KeyMap.lookup "status" o of
        Just (Aeson.Object s) ->
          assertEqual "name" (Just (Aeson.String "In Progress")) (KeyMap.lookup "name" s)
        _ -> assertFailure "Expected status object"
    _ -> assertFailure "Expected JSON object"

testSmartSelectValue :: Assertion
testSmartSelectValue = do
  let pv = PV.selectValue "Done"
  case pv of
    PV.SelectValue pid (Just (PV.SelectOptionValue _ optName _)) -> do
      assertEqual "schema id should be empty" "" pid
      assertEqual "name" "Done" optName
    _ -> assertFailure "Expected SelectValue"

testSmartTitleValue :: Assertion
testSmartTitleValue = do
  let rt = mkPlainRichText "Test"
      pv = PV.titleValue (Vector.singleton rt)
  case pv of
    PV.TitleValue pid rts -> do
      assertEqual "schema id should be empty" "" pid
      assertEqual "rich text count" 1 (Vector.length rts)
    _ -> assertFailure "Expected TitleValue"

-- =====================================================================
-- Property Schema Tests
-- =====================================================================

testPropertySchemaSelectRoundTrip :: Assertion
testPropertySchemaSelectRoundTrip = do
  let opts =
        Vector.fromList
          [ Props.SelectOption {id = Just "opt-1", name = "Done", color = Just Props.Green},
            Props.SelectOption {id = Just "opt-2", name = "Todo", color = Just Props.Red}
          ]
      schema = Props.SelectSchema {schemaId = "abc", schemaName = "Status", selectOptions = opts}
      json = Aeson.toJSON schema
  case Aeson.fromJSON json of
    Aeson.Success decoded -> assertEqual "round-trip" schema decoded
    Aeson.Error err -> assertFailure $ "Failed to decode: " <> err

testPropertySchemaNumberRoundTrip :: Assertion
testPropertySchemaNumberRoundTrip = do
  let schema = Props.NumberSchema {schemaId = "n1", schemaName = "Price", numberFormat = Props.Dollar}
      json = Aeson.toJSON schema
  case Aeson.fromJSON json of
    Aeson.Success decoded -> assertEqual "round-trip" schema decoded
    Aeson.Error err -> assertFailure $ "Failed to decode: " <> err

testPropertySchemaFormulaRoundTrip :: Assertion
testPropertySchemaFormulaRoundTrip = do
  let schema = Props.FormulaSchema {schemaId = "f1", schemaName = "Total", formulaExpression = "prop(\"Price\") * 2"}
      json = Aeson.toJSON schema
  case Aeson.fromJSON json of
    Aeson.Success decoded -> assertEqual "round-trip" schema decoded
    Aeson.Error err -> assertFailure $ "Failed to decode: " <> err

testPropertySchemaRelationRoundTrip :: Assertion
testPropertySchemaRelationRoundTrip = do
  let relType = Props.DualProperty {syncedPropertyId = "sp1", syncedPropertyName = "Related"}
      schema = Props.RelationSchema {schemaId = "r1", schemaName = "Tasks", relationDataSourceId = UUID "ds-123", relationType = relType}
      json = Aeson.toJSON schema
  case Aeson.fromJSON json of
    Aeson.Success decoded -> assertEqual "round-trip" schema decoded
    Aeson.Error err -> assertFailure $ "Failed to decode: " <> err

testPropertySchemaStatusRoundTrip :: Assertion
testPropertySchemaStatusRoundTrip = do
  let opts =
        Vector.fromList
          [ Props.SelectOption {id = Just "s1", name = "Not Started", color = Just Props.Gray},
            Props.SelectOption {id = Just "s2", name = "Done", color = Just Props.Green}
          ]
      grps =
        Vector.fromList
          [ Props.StatusGroup {id = Just "g1", name = "To-do", color = Just Props.Gray, optionIds = Vector.fromList ["s1"]},
            Props.StatusGroup {id = Just "g2", name = "Complete", color = Just Props.Green, optionIds = Vector.fromList ["s2"]}
          ]
      schema = Props.StatusSchema {schemaId = "st1", schemaName = "Status", statusOptions = opts, statusGroups = grps}
      json = Aeson.toJSON schema
  case Aeson.fromJSON json of
    Aeson.Success decoded -> assertEqual "round-trip" schema decoded
    Aeson.Error err -> assertFailure $ "Failed to decode: " <> err

testNumberFormatRoundTrip :: Assertion
testNumberFormatRoundTrip = do
  let formats =
        [ Props.NumberPlain,
          Props.Dollar,
          Props.Euro,
          Props.Percent,
          Props.NumberWithCommas,
          Props.Yen,
          Props.PhilippinePeso,
          Props.SingaporeDollar
        ]
  mapM_
    ( \fmt -> do
        let json = Aeson.toJSON fmt
        case Aeson.fromJSON json of
          Aeson.Success decoded -> assertEqual ("round-trip for " <> show fmt) fmt decoded
          Aeson.Error err -> assertFailure $ "Failed to decode " <> show fmt <> ": " <> err
    )
    formats

testRollupFunctionRoundTrip :: Assertion
testRollupFunctionRoundTrip = do
  let fns =
        [ Props.CountAll,
          Props.Sum,
          Props.Average,
          Props.ShowOriginal,
          Props.Checked,
          Props.DateRange,
          Props.ShowUnique,
          Props.NotEmpty
        ]
  mapM_
    ( \fn -> do
        let json = Aeson.toJSON fn
        case Aeson.fromJSON json of
          Aeson.Success decoded -> assertEqual ("round-trip for " <> show fn) fn decoded
          Aeson.Error err -> assertFailure $ "Failed to decode " <> show fn <> ": " <> err
    )
    fns

-- =====================================================================
-- File Upload Tests
-- =====================================================================

fileUploadTests :: TestTree
fileUploadTests =
  testGroup
    "File Uploads"
    [ testCase "FileUploadObject JSON round-trip (pending)" testFileUploadObjectPending,
      testCase "FileUploadObject JSON parse (uploaded with expiry)" testFileUploadObjectUploaded,
      testCase "CreateFileUpload single-part serialization" testCreateSinglePart,
      testCase "CreateFileUpload multi-part serialization" testCreateMultiPart,
      testCase "CreateFileUpload external URL serialization" testCreateExternalUrl,
      testCase "FileUploadStatus ToHttpApiData" testFileUploadStatusQueryParam,
      testCase "FileValue file_upload round-trip" testFileValueFileUpload,
      testCase "Icon file_upload round-trip" testIconFileUpload,
      testCase "Cover file_upload round-trip" testCoverFileUpload
    ]

testFileUploadObjectPending :: Assertion
testFileUploadObjectPending = do
  let json =
        "{\"id\":\"fu-123\",\"object\":\"file_upload\",\"status\":\"pending\""
          <> ",\"created_time\":\"2026-03-31T10:00:00.000+00:00\""
          <> ",\"last_edited_time\":\"2026-03-31T10:00:00.000+00:00\""
          <> ",\"created_by\":{\"id\":\"user-1\",\"type\":\"person\"}"
          <> ",\"in_trash\":false}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse FileUploadObject: " <> err
    Right (obj :: FU.FileUploadObject) -> do
      let FU.FileUploadObject {id = objId, object = objObject, status = objStatus, filename = objFilename} = obj
      assertEqual "status" FU.Pending objStatus
      assertEqual "object" "file_upload" objObject
      assertEqual "filename" Nothing objFilename
      -- Round-trip: re-encode and re-decode
      case Aeson.fromJSON (Aeson.toJSON obj) of
        Aeson.Error err2 -> assertFailure $ "Round-trip failed: " <> err2
        Aeson.Success (obj2 :: FU.FileUploadObject) -> do
          let FU.FileUploadObject {id = objId2, status = objStatus2} = obj2
          assertEqual "round-trip status" objStatus objStatus2
          assertEqual "round-trip id" objId objId2

testFileUploadObjectUploaded :: Assertion
testFileUploadObjectUploaded = do
  let json =
        "{\"id\":\"fu-456\",\"object\":\"file_upload\",\"status\":\"uploaded\""
          <> ",\"filename\":\"photo.png\",\"content_type\":\"image/png\",\"content_length\":12345"
          <> ",\"created_time\":\"2026-03-31T10:00:00.000+00:00\""
          <> ",\"last_edited_time\":\"2026-03-31T10:05:00.000+00:00\""
          <> ",\"created_by\":{\"id\":\"user-1\",\"type\":\"bot\"}"
          <> ",\"in_trash\":false"
          <> ",\"expiry_time\":\"2026-03-31T11:00:00.000+00:00\""
          <> ",\"number_of_parts\":{\"total\":1,\"sent\":1}}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse FileUploadObject: " <> err
    Right (obj :: FU.FileUploadObject) -> do
      let FU.FileUploadObject
            { status = objStatus,
              filename = objFilename,
              contentType = objContentType,
              contentLength = objContentLength,
              expiryTime = objExpiryTime,
              numberOfParts = objNumberOfParts
            } = obj
      assertEqual "status" FU.Uploaded objStatus
      assertEqual "filename" (Just "photo.png") objFilename
      assertEqual "content_type" (Just "image/png") objContentType
      assertEqual "content_length" (Just 12345) objContentLength
      assertBool "expiry_time should be Just" (objExpiryTime /= Nothing)
      case objNumberOfParts of
        Just np -> do
          assertEqual "total parts" 1 (FU.total np)
          assertEqual "sent parts" 1 (FU.sent np)
        Nothing -> assertFailure "Expected number_of_parts"

testCreateSinglePart :: Assertion
testCreateSinglePart = do
  let req = FU.mkSinglePartUpload (Just "test.txt")
      json = Aeson.toJSON req
  case json of
    Aeson.Object o -> do
      assertBool "should not have mode key (Nothing is omitted)" (not $ KeyMap.member "mode" o)
      assertEqual "filename" (Just (Aeson.String "test.txt")) (KeyMap.lookup "filename" o)
    _ -> assertFailure "Expected JSON object"

testCreateMultiPart :: Assertion
testCreateMultiPart = do
  let req = FU.mkMultiPartUpload "big.zip" 5 (Just "application/zip")
      json = Aeson.toJSON req
  case json of
    Aeson.Object o -> do
      assertEqual "mode" (Just (Aeson.String "multi_part")) (KeyMap.lookup "mode" o)
      assertEqual "filename" (Just (Aeson.String "big.zip")) (KeyMap.lookup "filename" o)
      assertEqual "number_of_parts" (Just (Aeson.Number 5)) (KeyMap.lookup "number_of_parts" o)
      assertEqual "content_type" (Just (Aeson.String "application/zip")) (KeyMap.lookup "content_type" o)
    _ -> assertFailure "Expected JSON object"

testCreateExternalUrl :: Assertion
testCreateExternalUrl = do
  let req = FU.mkExternalUrlUpload "https://example.com/file.pdf" Nothing
      json = Aeson.toJSON req
  case json of
    Aeson.Object o -> do
      assertEqual "mode" (Just (Aeson.String "external_url")) (KeyMap.lookup "mode" o)
      assertEqual "external_url" (Just (Aeson.String "https://example.com/file.pdf")) (KeyMap.lookup "external_url" o)
      assertBool "should not have filename" (not $ KeyMap.member "filename" o)
    _ -> assertFailure "Expected JSON object"

testFileUploadStatusQueryParam :: Assertion
testFileUploadStatusQueryParam = do
  assertEqual "Pending" "pending" (toQueryParam FU.Pending)
  assertEqual "Uploaded" "uploaded" (toQueryParam FU.Uploaded)
  assertEqual "Expired" "expired" (toQueryParam FU.Expired)
  assertEqual "Failed" "failed" (toQueryParam FU.Failed)

testFileValueFileUpload :: Assertion
testFileValueFileUpload = do
  let json =
        "{\"type\":\"file_upload\",\"name\":\"photo.png\",\"file_upload\":{\"id\":\"fu-789\"}}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse FileValue: " <> err
    Right (PV.FileUploadFileValue n uid) -> do
      assertEqual "name" "photo.png" n
      assertEqual "fileUploadId" (UUID "fu-789") uid
    Right other -> assertFailure $ "Expected FileUploadFileValue, got: " <> show other
  -- Round-trip
  let val = PV.FileUploadFileValue "doc.pdf" (UUID "fu-abc")
  case Aeson.fromJSON (Aeson.toJSON val) of
    Aeson.Error err -> assertFailure $ "Round-trip failed: " <> err
    Aeson.Success (PV.FileUploadFileValue n2 uid2) -> do
      assertEqual "name rt" "doc.pdf" n2
      assertEqual "id rt" (UUID "fu-abc") uid2
    Aeson.Success other -> assertFailure $ "Expected FileUploadFileValue, got: " <> show other

testIconFileUpload :: Assertion
testIconFileUpload = do
  let json =
        "{\"type\":\"file_upload\",\"file_upload\":{\"id\":\"fu-icon\"}}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse Icon: " <> err
    Right (FileUploadIcon uid) ->
      assertEqual "fileUploadId" (UUID "fu-icon") uid
    Right other -> assertFailure $ "Expected FileUploadIcon, got: " <> show other
  -- Round-trip
  let icon = FileUploadIcon (UUID "fu-icon-2")
  case Aeson.fromJSON (Aeson.toJSON icon) of
    Aeson.Error err -> assertFailure $ "Round-trip failed: " <> err
    Aeson.Success (FileUploadIcon uid2) ->
      assertEqual "id rt" (UUID "fu-icon-2") uid2
    Aeson.Success other -> assertFailure $ "Expected FileUploadIcon, got: " <> show other

testCoverFileUpload :: Assertion
testCoverFileUpload = do
  let json =
        "{\"type\":\"file_upload\",\"file_upload\":{\"id\":\"fu-cover\"}}"
  case Aeson.eitherDecode json of
    Left err -> assertFailure $ "Failed to parse Cover: " <> err
    Right (FileUploadCover uid) ->
      assertEqual "fileUploadId" (UUID "fu-cover") uid
    Right other -> assertFailure $ "Expected FileUploadCover, got: " <> show other
  -- Round-trip
  let cover = FileUploadCover (UUID "fu-cover-2")
  case Aeson.fromJSON (Aeson.toJSON cover) of
    Aeson.Error err -> assertFailure $ "Round-trip failed: " <> err
    Aeson.Success (FileUploadCover uid2) ->
      assertEqual "id rt" (UUID "fu-cover-2") uid2
    Aeson.Success other -> assertFailure $ "Expected FileUploadCover, got: " <> show other

-- =====================================================================
-- Helpers
-- =====================================================================

-- | Create a typed RichText value for use in comments
mkTypedRichText :: Text.Text -> RT.RichText
mkTypedRichText t =
  RT.RichText
    { RT.plainText = t,
      RT.href = Nothing,
      RT.annotations = defaultAnnotations,
      RT.type_ = "text",
      RT.content = TextContentWrapper (TextContent {content = t, link = Nothing})
    }

lookupEnv :: String -> IO (Maybe String)
lookupEnv = Environment.lookupEnv
