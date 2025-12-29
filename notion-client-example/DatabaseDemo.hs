-- |
-- Database API demonstration.
module DatabaseDemo
  ( runDatabaseDemo,
  )
where

import Blocks (createBulletedListItemBlock, createHeadingBlock, createParagraphBlock)
import Console (printHeader, runTest)
import Data.Aeson qualified as Aeson
import Data.Map (fromList)
import Data.String (fromString)
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import Notion.V1 (Methods (..))
import Notion.V1.Blocks qualified as Blocks
import Notion.V1.Comments (CommentObject (..), CreateComment (..))
import Notion.V1.Common (Icon (..), Parent (..))
import Notion.V1.Databases (DatabaseObject (..), QueryDatabase (..), UpdateDatabase (..))
import Notion.V1.ListOf (ListOf (..))
import Notion.V1.Pages (CreatePage (..), PageObject (..), PropertyValue (..), PropertyValueType (..))
import Prelude hiding (id)

-- | Run the Database API demonstration
runDatabaseDemo :: Methods -> String -> IO ()
runDatabaseDemo methods databaseIdStr = do
  let databaseId = fromString databaseIdStr

  printHeader (Text.pack "Database API")

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
  printHeader (Text.pack "Adding Property to Database")

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
  _updatedDatabase <-
    runTest (Text.pack "Adding Status and Priority properties to database") $
      updateDatabase methods databaseId updateDbRequest

  putStrLn "Database updated with new properties"

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
  _updatedPage <-
    runTest (Text.pack "Adding blocks to page") $
      appendBlockChildren methods newPageId appendRequest

  -- Fetch the blocks to verify
  pageBlocks <-
    runTest (Text.pack "Retrieving page blocks") $
      listBlockChildren methods newPageId Nothing Nothing

  let List {results = blockResults} = pageBlocks
  putStrLn $ "Page now contains " <> show (Vector.length blockResults) <> " blocks"

  -- Add a comment to the newly created page
  printHeader (Text.pack "Adding Comment to Page")

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

  _replyComment <-
    runTest (Text.pack "Adding reply to discussion") $
      createComment methods replyRequest

  putStrLn "Reply added to discussion"

  -- List all comments on the page
  allComments <-
    runTest (Text.pack "Listing all comments on page") $
      listComments methods (Just newPageId) Nothing (Just 10)

  let List {results = commentResults} = allComments
  putStrLn $ "Page now has " <> show (Vector.length commentResults) <> " comments"
