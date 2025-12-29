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

import Control.Applicative ((<|>))
import Control.Exception (SomeException, try)
import Control.Monad (when)
import Data.Aeson (Value)
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Map (fromList)
import Data.Maybe (isNothing)
import Data.String (fromString)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import Notion.V1
import Notion.V1.Blocks (AppendBlockChildren (..))
import Notion.V1.Blocks qualified as Blocks
import Notion.V1.Comments (CommentObject (..), CreateComment (..))
import Notion.V1.Common (Icon (..), ObjectType (..), Parent (..))
import Notion.V1.Databases (DatabaseObject (..), QueryDatabase (..), UpdateDatabase (..))
import Notion.V1.Databases qualified as Databases
import Notion.V1.ListOf (ListOf (..))
import Notion.V1.Pages (CreatePage (..), PageObject (..), PropertyValue (..), PropertyValueType (..))
import Notion.V1.Search (SearchFilter (..), SearchRequest (..), SearchSort (..), SearchSortDirection (..))
import System.Environment qualified as Environment
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)
import Prelude hiding (id)

-- | Print a section header
printHeader :: Text -> IO ()
printHeader title = do
  putStrLn ""
  putStrLn $ "=== " <> Text.unpack title <> " ==="
  putStrLn ""

-- | Log an error and exit
logError :: Text -> IO a
logError msg = do
  hPutStrLn stderr $ "ERROR: " <> Text.unpack msg
  exitFailure

-- | Print a success message
printSuccess :: Text -> IO ()
printSuccess msg = putStrLn $ "✓ " <> Text.unpack msg

-- | Run a test with label
runTest :: Text -> IO a -> IO a
runTest label action = do
  putStr $ Text.unpack label <> "... "
  result <- action
  printSuccess (Text.pack "Done")
  pure result

-- | Helper Functions for Block Creation
-- These functions create JSON objects that match the Notion API's block format

-- | Create a paragraph block with text content
-- @param content The text content to include in the paragraph
-- @return A JSON representation of a paragraph block
createParagraphBlock :: Text -> Aeson.Value
createParagraphBlock content =
  let -- Structure: {"text": {"content": "Your text here"}}
      textObj = Aeson.object [("content", Aeson.String content)]
      textItem = Aeson.object [("text", textObj)]
      -- Rich text is always an array of text items
      richText = Aeson.Array (Vector.singleton textItem)
      -- The paragraph property contains rich_text array
      paragraphContent = Aeson.object [("rich_text", richText)]
   in Aeson.object
        [ ("type", Aeson.String "paragraph"), -- Block type
          ("paragraph", paragraphContent) -- Block content
        ]

-- | Create a heading block with text content
-- @param content The text content for the heading
-- @param level The heading level (1-3)
-- @return A JSON representation of a heading block
createHeadingBlock :: Text -> Int -> Aeson.Value
createHeadingBlock content level =
  let -- Create the same rich text structure as paragraph
      textObj = Aeson.object [("content", Aeson.String content)]
      textItem = Aeson.object [("text", textObj)]
      richText = Aeson.Array (Vector.singleton textItem)
      -- Headings use heading_1, heading_2, or heading_3 as type
      headingType = "heading_" <> Text.pack (show level)
      headingContent = Aeson.object [("rich_text", richText)]
   in Aeson.object
        [ ("type", Aeson.String headingType), -- Block type
          (fromString (Text.unpack headingType), headingContent) -- Block content
        ]

-- | Create a bulleted list item block with text content
-- @param content The text content for the list item
-- @return A JSON representation of a bulleted list item block
createBulletedListItemBlock :: Text -> Aeson.Value
createBulletedListItemBlock content =
  let -- Create the same rich text structure as other blocks
      textObj = Aeson.object [("content", Aeson.String content)]
      textItem = Aeson.object [("text", textObj)]
      richText = Aeson.Array (Vector.singleton textItem)
      -- List items are structured the same way as paragraphs
      listContent = Aeson.object [("rich_text", richText)]
   in Aeson.object
        [ ("type", Aeson.String "bulleted_list_item"), -- Block type
          ("bulleted_list_item", listContent) -- Block content
        ]

main :: IO ()
main = do
  putStrLn "Notion API Client Example"
  putStrLn "========================="

  -- Get environment variables with error handling
  token <- do
    mToken <- Environment.lookupEnv "NOTION_TOKEN"
    case mToken of
      Just t -> pure (Text.pack t)
      Nothing -> logError "NOTION_TOKEN environment variable is required"

  databaseIdEnv <- Environment.lookupEnv "NOTION_TEST_DATABASE_ID"
  pageIdEnv <- Environment.lookupEnv "NOTION_TEST_PAGE_ID"

  when (isNothing databaseIdEnv && isNothing pageIdEnv) $
    putStrLn "WARNING: Neither NOTION_TEST_DATABASE_ID nor NOTION_TEST_PAGE_ID are set.\n         Only basic user API functionality will be demonstrated."

  printHeader "Client Initialization"
  clientEnv <-
    runTest (Text.pack "Initializing client") $
      getClientEnv (Text.pack "https://api.notion.com/v1")

  let methods = makeMethods clientEnv token

  printHeader "User API"
  user <-
    runTest (Text.pack "Retrieving current user information") $
      retrieveMyUser methods
  putStrLn $ "User info: " <> show user

  -- List all users
  users <-
    runTest (Text.pack "Listing users") $
      listUsers methods Nothing Nothing
  let List {results = userResults} = users
  putStrLn $ "User count: " <> show (Vector.length userResults)

  -- Optional Database tests
  case databaseIdEnv of
    Just databaseIdStr -> do
      let databaseId = fromString databaseIdStr

      printHeader "Database API"

      -- Retrieve database and display new fields
      database <-
        runTest (Text.pack "Retrieving database") $
          retrieveDatabase methods databaseId
      putStrLn $ "Database retrieved, ID: " <> databaseIdStr

      -- Display new database fields (isInline, inTrash, publicUrl, dataSources)
      let DatabaseObject {isInline, inTrash, publicUrl, dataSources} = database
      putStrLn $ "  isInline: " <> show isInline
      putStrLn $ "  inTrash: " <> show inTrash
      putStrLn $ "  publicUrl: " <> show publicUrl
      putStrLn $ "  dataSources: " <> show dataSources

      -- Query database
      let queryParams =
            QueryDatabase
              { filter = Nothing,
                sorts = Nothing,
                startCursor = Nothing,
                pageSize = Nothing
              }
      results <-
        runTest (Text.pack "Querying database") $
          queryDatabase methods databaseId queryParams
      let List {results = queryResults} = results
      putStrLn $ "Query returned " <> show (Vector.length queryResults) <> " results"

      -- Add a new property to the database
      -- This adds a "Status" select property with predefined options
      printHeader "Adding Property to Database"

      let -- Define Status and Priority select properties with options
          -- Properties are combined into a single object for the update request
          combinedProperties =
            Aeson.object
              [ ( "Status",
                  Aeson.object
                    [ ("type", Aeson.String "select"),
                      ( "select",
                        Aeson.object
                          [ ( "options",
                              Aeson.Array $
                                Vector.fromList
                                  [ Aeson.object [("name", Aeson.String "Not Started"), ("color", Aeson.String "red")],
                                    Aeson.object [("name", Aeson.String "In Progress"), ("color", Aeson.String "yellow")],
                                    Aeson.object [("name", Aeson.String "Done"), ("color", Aeson.String "green")]
                                  ]
                            )
                          ]
                      )
                    ]
                ),
                ( "Priority",
                  Aeson.object
                    [ ("type", Aeson.String "select"),
                      ( "select",
                        Aeson.object
                          [ ( "options",
                              Aeson.Array $
                                Vector.fromList
                                  [ Aeson.object [("name", Aeson.String "High"), ("color", Aeson.String "red")],
                                    Aeson.object [("name", Aeson.String "Medium"), ("color", Aeson.String "yellow")],
                                    Aeson.object [("name", Aeson.String "Low"), ("color", Aeson.String "gray")]
                                  ]
                            )
                          ]
                      )
                    ]
                )
              ]

          updateDbRequest =
            UpdateDatabase
              { title = Nothing, -- Keep existing title
                properties = Just combinedProperties, -- Add new properties
                icon = Nothing,
                cover = Nothing,
                description = Nothing,
                archived = Nothing,
                isInline = Nothing
              }

      -- Update the database with new properties
      updatedDatabase <-
        runTest (Text.pack "Adding Status and Priority properties to database") $
          updateDatabase methods databaseId updateDbRequest

      putStrLn $ "Database updated with new properties"

      -- Create a new page in the database with initial content
      let -- Step 1: Create title property (required for database pages)
          -- The "title" key should match your database title field name
          textObj = Aeson.object [("content", Aeson.String "Test Page from API")]
          textItem = Aeson.object [("text", textObj)]
          titleArray = Aeson.Array (Vector.singleton textItem)
          titleProp = Aeson.object [("title", titleArray)]

          -- Step 2: Create select property values for Status and Priority
          -- Select properties need a "select" wrapper with a "name" field
          statusProp =
            Aeson.object
              [ ( "select",
                  Aeson.object [("name", Aeson.String "In Progress")]
                )
              ]
          priorityProp =
            Aeson.object
              [ ( "select",
                  Aeson.object [("name", Aeson.String "High")]
                )
              ]

          -- Step 3: Create page properties map with all properties
          -- Add the title and the new Status/Priority properties
          pageProperties =
            fromList
              [ ( "title", -- This must match your database's title field name
                  PropertyValue
                    { type_ = Title,
                      value = Just titleProp
                    }
                ),
                ( "Status", -- Set the Status property
                  PropertyValue
                    { type_ = Select,
                      value = Just statusProp
                    }
                ),
                ( "Priority", -- Set the Priority property
                  PropertyValue
                    { type_ = Select,
                      value = Just priorityProp
                    }
                )
              ]

          -- Step 4: Create initial blocks for the page (optional)
          -- Pages can be created with content already in them
          initialBlocks =
            Vector.fromList
              [ createHeadingBlock "Initial Content" 1,
                createParagraphBlock "This page was created with initial content via the Notion API."
              ]

          -- Step 5: Assemble the CreatePage request
          createPageRequest =
            CreatePage
              { parent = DatabaseParent {databaseId = databaseId}, -- Specify parent database
                properties = pageProperties, -- Required page properties
                children = Just initialBlocks, -- Optional initial content
                icon = Just (EmojiIcon "📝"), -- Optional page icon
                cover = Nothing -- Optional page cover
              }

      -- Debug JSON (commented out for production use)
      -- jsonString <- debugCreatePage methods createPageRequest
      -- putStrLn $ "JSON to create page: " ++ jsonString

      -- Add page to database
      newPage <-
        runTest (Text.pack "Creating new page in database") $
          createPage methods createPageRequest

      let PageObject {id = newPageId, url = newPageUrl} = newPage
      putStrLn $ "New page created. Access at: " <> Text.unpack newPageUrl

      -- Retrieve the new page
      retrievedPage <-
        runTest (Text.pack "Retrieving newly created page") $
          retrievePage methods newPageId

      let PageObject {url = retrievedPageUrl} = retrievedPage
      putStrLn $ "Retrieved page URL: " <> Text.unpack retrievedPageUrl

      -- Add blocks to the newly created page
      let additionalBlocks =
            Vector.fromList
              [ createHeadingBlock "Example Content" 1,
                createParagraphBlock "This is a paragraph with some example content created via the Notion API.",
                createHeadingBlock "Features" 2,
                createBulletedListItemBlock "Create pages in databases",
                createBulletedListItemBlock "Add rich content to pages",
                createBulletedListItemBlock "Query and retrieve data"
              ]
          appendRequest = Blocks.AppendBlockChildren {children = additionalBlocks}

      -- Add blocks to the page
      updatedPage <-
        runTest (Text.pack "Adding blocks to page") $
          appendBlockChildren methods newPageId appendRequest

      -- Fetch the blocks to verify
      pageBlocks <-
        runTest (Text.pack "Retrieving page blocks") $
          listBlockChildren methods newPageId Nothing Nothing

      let List {results = blockResults} = pageBlocks
      putStrLn $ "Page now contains " <> show (Vector.length blockResults) <> " blocks"

      -- Add a comment to the newly created page
      printHeader "Adding Comment to Page"

      let -- Create rich text content for the comment
          commentTextObj = Aeson.object [("content", Aeson.String "This is an automated comment added via the Notion API! 🎉")]
          commentTextItem = Aeson.object [("type", Aeson.String "text"), ("text", commentTextObj)]
          commentRichText = Aeson.Array (Vector.singleton commentTextItem)

          -- Create the parent reference for the comment
          -- Comments can be attached to pages using page_id
          commentParent =
            Aeson.object
              [ ("type", Aeson.String "page_id"),
                ("page_id", Aeson.toJSON newPageId)
              ]

          -- Create the comment request
          createCommentRequest =
            CreateComment
              { parent = commentParent,
                richText = commentRichText,
                discussionId = Nothing -- Creates a new discussion thread
              }

      -- Create the comment
      newComment <-
        runTest (Text.pack "Creating comment on page") $
          createComment methods createCommentRequest

      let CommentObject {id = commentId, discussionId = discId} = newComment
      putStrLn $ "Comment created with ID: " <> show commentId
      putStrLn $ "Discussion ID: " <> show discId

      -- Add a reply to the same discussion thread
      let replyTextObj = Aeson.object [("content", Aeson.String "This is a reply in the same discussion thread.")]
          replyTextItem = Aeson.object [("type", Aeson.String "text"), ("text", replyTextObj)]
          replyRichText = Aeson.Array (Vector.singleton replyTextItem)

          -- Reply to existing discussion by providing discussion_id
          replyRequest =
            CreateComment
              { parent = commentParent,
                richText = replyRichText,
                discussionId = Just discId -- Reply to the same discussion
              }

      replyComment <-
        runTest (Text.pack "Adding reply to discussion") $
          createComment methods replyRequest

      putStrLn $ "Reply added to discussion"

      -- List all comments on the page
      allComments <-
        runTest (Text.pack "Listing all comments on page") $
          listComments methods (Just newPageId) Nothing (Just 10)

      let List {results = commentResults} = allComments
      putStrLn $ "Page now has " <> show (Vector.length commentResults) <> " comments"
    Nothing ->
      putStrLn "Skipping database tests (set NOTION_TEST_DATABASE_ID to enable)"

  -- Optional Page tests
  case pageIdEnv of
    Just pageIdStr -> do
      let pageId = fromString pageIdStr

      printHeader "Page API"

      -- Retrieve page
      page <-
        runTest (Text.pack "Retrieving page") $
          retrievePage methods pageId
      putStrLn $ "Page retrieved, ID: " <> pageIdStr

      -- List blocks
      blocks <-
        runTest (Text.pack "Listing blocks") $
          listBlockChildren methods pageId Nothing Nothing
      let List {results = blockResults} = blocks
      putStrLn $ "Block count: " <> show (Vector.length blockResults)

      -- If we have blocks, retrieve the first one and add a comment to it
      when (not $ Vector.null blockResults) $ do
        let firstBlock = Vector.head blockResults
            firstBlockId = Blocks.id firstBlock
        block <-
          runTest (Text.pack "Retrieving block") $
            retrieveBlock methods firstBlockId
        putStrLn $ "Block retrieved, type: " <> Text.unpack (Blocks.type_ block)

        -- Add a comment to the specific block (not the page)
        -- This demonstrates commenting on inline content
        printHeader "Adding Comment to Block"

        let -- Create rich text content for the block comment
            blockCommentTextObj = Aeson.object [("content", Aeson.String "This comment is attached to a specific block, not the page!")]
            blockCommentTextItem = Aeson.object [("type", Aeson.String "text"), ("text", blockCommentTextObj)]
            blockCommentRichText = Aeson.Array (Vector.singleton blockCommentTextItem)

            -- Create the parent reference for the comment using block_id
            -- This is different from page comments which use page_id
            blockCommentParent =
              Aeson.object
                [ ("type", Aeson.String "block_id"),
                  ("block_id", Aeson.toJSON firstBlockId)
                ]

            -- Create the comment request for the block
            createBlockCommentRequest =
              CreateComment
                { parent = blockCommentParent,
                  richText = blockCommentRichText,
                  discussionId = Nothing -- Creates a new discussion thread on the block
                }

        -- Create the comment on the block
        blockComment <-
          runTest (Text.pack "Creating comment on block") $
            createComment methods createBlockCommentRequest

        let CommentObject {id = blockCommentId, discussionId = blockDiscId} = blockComment
        putStrLn $ "Block comment created with ID: " <> show blockCommentId
        putStrLn $ "Block discussion ID: " <> show blockDiscId

        -- List comments on the block
        blockComments <-
          runTest (Text.pack "Listing comments on block") $
            listComments methods (Just firstBlockId) Nothing (Just 10)

        let List {results = blockCommentResults} = blockComments
        putStrLn $ "Block has " <> show (Vector.length blockCommentResults) <> " comments"

      -- Add new blocks to the existing page
      let codeBlock =
            Aeson.object
              [ ("type", Aeson.String "code"),
                ( "code",
                  Aeson.object
                    [ ( "rich_text",
                        Aeson.Array
                          ( Vector.singleton $
                              Aeson.object
                                [ ("text", Aeson.object [("content", Aeson.String "const example = () => {\n  console.log('Hello from Notion API');\n};")])
                                ]
                          )
                      ),
                      ("language", Aeson.String "javascript")
                    ]
                )
              ]
          quoteBlock =
            Aeson.object
              [ ("type", Aeson.String "quote"),
                ( "quote",
                  Aeson.object
                    [ ( "rich_text",
                        Aeson.Array
                          ( Vector.singleton $
                              Aeson.object
                                [ ("text", Aeson.object [("content", Aeson.String "This is a quote block added via the API")])
                                ]
                          )
                      )
                    ]
                )
              ]
          calloutBlock =
            Aeson.object
              [ ("type", Aeson.String "callout"),
                ( "callout",
                  Aeson.object
                    [ ( "rich_text",
                        Aeson.Array
                          ( Vector.singleton $
                              Aeson.object
                                [ ("text", Aeson.object [("content", Aeson.String "This is a callout block with an emoji")])
                                ]
                          )
                      ),
                      ("icon", Aeson.object [("emoji", Aeson.String "🔥")])
                    ]
                )
              ]
          specializedBlocks = Vector.fromList [codeBlock, quoteBlock, calloutBlock]
          appendRequest = Blocks.AppendBlockChildren {children = specializedBlocks}

      -- Append blocks to the existing page
      updatedPage <-
        runTest (Text.pack "Adding specialized blocks to page") $
          appendBlockChildren methods pageId appendRequest

      -- Refresh the blocks to see all blocks now
      allBlocks <-
        runTest (Text.pack "Retrieving all page blocks") $
          listBlockChildren methods pageId Nothing Nothing

      let List {results = allBlockResults} = allBlocks
      putStrLn $ "Page now contains " <> show (Vector.length allBlockResults) <> " blocks"

      -- Comments API demonstration (using the page)
      -- Note: Pages are blocks in Notion, so we use the page ID as block_id
      printHeader "Comments API"

      -- List comments on the page using block_id (pages are blocks in Notion)
      comments <-
        runTest (Text.pack "Listing comments on page") $
          listComments methods (Just pageId) Nothing (Just 10)

      let List {results = commentResults} = comments
      putStrLn $ "Found " <> show (Vector.length commentResults) <> " comments on page"

      -- Display comment details if any exist
      when (not $ Vector.null commentResults) $ do
        let firstComment = Vector.head commentResults
            CommentObject
              { id = commentId,
                discussionId = discId,
                createdBy = createdBy,
                attachments = commentAttachments,
                displayName = displayName
              } = firstComment
        putStrLn $ "First comment details:"
        putStrLn $ "  id: " <> show commentId
        putStrLn $ "  discussionId: " <> show discId
        putStrLn $ "  createdBy: " <> show createdBy
        putStrLn $ "  attachments: " <> show commentAttachments
        putStrLn $ "  displayName: " <> show displayName
    Nothing ->
      putStrLn "Skipping page tests (set NOTION_TEST_PAGE_ID to enable)"

  -- Search API
  printHeader "Search API"

  putStrLn "Due to ongoing implementation of search support, search API examples are provided in the source code."
  putStrLn "The examples demonstrate:"
  putStrLn "- General searching (find anything matching a query)"
  putStrLn "- Filtering by object type (search only for pages)"
  putStrLn "- Filtering by object type (search only for databases)"
  putStrLn "- Sorting results by last_edited_time"

  -- Example search parameters (not executed to avoid errors)
  let searchParams =
        SearchRequest
          { query = Just "test",
            sort = Nothing,
            filter = Nothing,
            startCursor = Nothing,
            pageSize = Nothing
          }

  -- Example page search parameters
  let pageSearchParams =
        SearchRequest
          { query = Just "test",
            sort = Nothing,
            filter = Just (SearchFilter {value = Page, property = "object"}),
            startCursor = Nothing,
            pageSize = Nothing
          }

  -- Example database search parameters
  let databaseSearchParams =
        SearchRequest
          { query = Just "test",
            sort = Nothing,
            filter = Just (SearchFilter {value = Database, property = "object"}),
            startCursor = Nothing,
            pageSize = Nothing
          }

  -- Example sorted search parameters
  let sortedSearchParams =
        SearchRequest
          { query = Just "test",
            sort = Just (SearchSort {direction = Descending, timestamp = "last_edited_time"}),
            filter = Nothing,
            startCursor = Nothing,
            pageSize = Nothing
          }

  -- All done
  printHeader "Test complete"
  putStrLn "All tests completed successfully!"
