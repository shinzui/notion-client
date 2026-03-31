-- |
-- Database API demonstration.
module DatabaseDemo
  ( runDatabaseDemo,
  )
where

import Blocks (createBulletedListItemBlock, createHeadingBlock, createParagraphBlock)
import Console (printHeader, runTest)
import Control.Exception qualified as Exception
import Data.Map qualified as Map
import Data.String (fromString)
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import Notion.V1 (Methods (..))
import Notion.V1.Blocks qualified as Blocks
import Notion.V1.Comments (CommentObject (..), CreateComment (..))
import Notion.V1.Common (Icon (..), Parent (..), UUID (..))
import Notion.V1.DataSources qualified as DataSources
import Notion.V1.Databases (DataSource (..), DatabaseObject (..))
import Notion.V1.Error (NotionError (..))
import Notion.V1.Filter (Sort (..), SortDirection (..))
import Notion.V1.ListOf (ListOf (..))
import Notion.V1.Pages (CreatePage (..), PageObject (..), PropertyItemResponse (..))
import Notion.V1.Pagination (paginateAll)
import Notion.V1.Properties (PropertySchema (..), SelectColor (..), SelectOption (..))
import Notion.V1.PropertyValue qualified as PV
import Notion.V1.RichText (RichText (..), RichTextContent (..), TextContent (..), defaultAnnotations)
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

  -- Display database fields
  let DatabaseObject {isInline, inTrash, publicUrl, dataSources, isLocked} = database
  putStrLn $ "  isInline: " <> show isInline
  putStrLn $ "  inTrash: " <> show inTrash
  putStrLn $ "  isLocked: " <> show isLocked
  putStrLn $ "  publicUrl: " <> show publicUrl
  putStrLn $ "  dataSources: " <> show dataSources

  -- Retrieve the first data source to inspect its schema
  -- Note: In API version 2025-09-03, querying goes through data sources, not databases
  printHeader (Text.pack "Data Source API")

  let DataSource {id = dsId, name = dsName} = Vector.head dataSources
  putStrLn $ "First data source: " <> Text.unpack dsName <> " (" <> show dsId <> ")"

  dataSource <-
    runTest (Text.pack "Retrieving data source") $
      retrieveDataSource methods dsId
  let DataSources.DataSourceObject {properties = dsProperties, parent = dsParent} = dataSource
  putStrLn $ "  parent: " <> show dsParent
  putStrLn $ "  properties: " <> show dsProperties

  -- Query the data source directly (preferred over queryDatabase in 2025-09-03)
  -- Using typed sorts to order by created_time descending
  let dsQueryParams =
        DataSources.QueryDataSource
          { filter = Nothing,
            sorts = Just [PropertySort "Name" Ascending],
            startCursor = Nothing,
            pageSize = Just 5,
            inTrash = Nothing,
            filterProperties = Nothing
          }
  dsResults <-
    runTest (Text.pack "Querying data source") $
      queryDataSource methods dsId dsQueryParams
  let List {results = dsQueryResults} = dsResults
  putStrLn $ "Data source query returned " <> show (Vector.length dsQueryResults) <> " results"

  -- Create a new data source within the database
  printHeader (Text.pack "Creating Data Source")

  let newDsProperties =
        Map.fromList
          [ ("Name", TitleSchema {schemaId = "", schemaName = "Name"}),
            ("Description", RichTextSchema {schemaId = "", schemaName = "Description"})
          ]

      createDsRequest =
        DataSources.CreateDataSource
          { parent = DatabaseParent {databaseId = databaseId},
            properties = newDsProperties,
            title = Nothing,
            description = Nothing,
            icon = Nothing,
            cover = Nothing
          }

  newDataSource <-
    runTest (Text.pack "Creating new data source in database") $
      createDataSource methods createDsRequest

  let DataSources.DataSourceObject {id = newDsId, properties = newDsProps} = newDataSource
  putStrLn $ "New data source created with ID: " <> show newDsId
  putStrLn $ "  properties: " <> show newDsProps

  -- Update data source schema: add properties
  printHeader (Text.pack "Updating Data Source Schema")

  let statusOptions =
        Vector.fromList
          [ SelectOption {id = Nothing, name = "Not Started", color = Just Red},
            SelectOption {id = Nothing, name = "In Progress", color = Just Yellow},
            SelectOption {id = Nothing, name = "Done", color = Just Green}
          ]
      priorityOptions =
        Vector.fromList
          [ SelectOption {id = Nothing, name = "High", color = Just Red},
            SelectOption {id = Nothing, name = "Medium", color = Just Yellow},
            SelectOption {id = Nothing, name = "Low", color = Just Gray}
          ]
      combinedProperties =
        Map.fromList
          [ ("Status", Just (SelectSchema {schemaId = "", schemaName = "Status", selectOptions = statusOptions})),
            ("Priority", Just (SelectSchema {schemaId = "", schemaName = "Priority", selectOptions = priorityOptions}))
          ]

      updateDsRequest =
        DataSources.UpdateDataSource
          { title = Nothing,
            icon = Nothing,
            properties = Just combinedProperties,
            inTrash = Nothing,
            parent = Nothing
          }

  -- Update the data source with new properties
  _updatedDataSource <-
    runTest (Text.pack "Adding Status and Priority properties via data source") $
      updateDataSource methods dsId updateDsRequest

  putStrLn "Data source updated with new properties"

  -- Create a new page in the database with initial content
  let -- Create page properties using typed smart constructors
      titleRichText =
        Vector.singleton
          RichText
            { plainText = "Test Page from API",
              href = Nothing,
              annotations = defaultAnnotations,
              type_ = "text",
              content = TextContentWrapper (TextContent {content = "Test Page from API", link = Nothing})
            }

      pageProperties =
        Map.fromList
          [ ("title", PV.titleValue titleRichText),
            ("Status", PV.selectValue "In Progress"),
            ("Priority", PV.selectValue "High")
          ]

      -- Create initial blocks for the page (optional)
      -- Pages can be created with content already in them
      initialBlocks =
        Vector.fromList
          [ createHeadingBlock "Initial Content" 1,
            createParagraphBlock "This page was created with initial content via the Notion API."
          ]

      -- Step 5: Assemble the CreatePage request
      -- In API version 2025-09-03, pages are created under a data source
      createPageRequest =
        CreatePage
          { parent = DataSourceParent {dataSourceId = dsId, parentDatabaseId = Nothing}, -- Specify parent data source
            properties = pageProperties, -- Required page properties
            children = Just initialBlocks, -- Optional initial content
            markdown = Nothing, -- Could use markdown instead of children
            icon = Just (EmojiIcon "📝"), -- Optional page icon
            cover = Nothing, -- Optional page cover
            template = Nothing, -- No template
            position = Nothing -- Default position
          }

  -- Add page to database
  newPage <-
    runTest (Text.pack "Creating new page in database") $
      createPage methods createPageRequest

  let PageObject {id = newPageId, url = newPageUrl} = newPage
  putStrLn $ "New page created. Access at: " <> Text.unpack newPageUrl

  -- Retrieve the new page and read typed properties
  printHeader (Text.pack "Typed Property Values")

  retrievedPage <-
    runTest (Text.pack "Retrieving newly created page") $
      retrievePage methods newPageId

  let PageObject {url = retrievedPageUrl, properties = pageProps, publicUrl = pagePubUrl} = retrievedPage
  putStrLn $ "Retrieved page URL: " <> Text.unpack retrievedPageUrl
  putStrLn $ "Public URL: " <> show pagePubUrl

  -- Pattern-match on typed property values from the retrieved page
  putStrLn "Reading typed properties:"
  case Map.lookup "Status" pageProps of
    Just (PV.SelectValue _pid (Just (PV.SelectOptionValue _ optName optColor))) ->
      putStrLn $ "  Status: " <> Text.unpack optName <> " (color: " <> show optColor <> ")"
    Just (PV.SelectValue _pid Nothing) ->
      putStrLn "  Status: (empty)"
    _ ->
      putStrLn "  Status: (not found or unexpected type)"

  case Map.lookup "Priority" pageProps of
    Just (PV.SelectValue _pid (Just (PV.SelectOptionValue _ optName _))) ->
      putStrLn $ "  Priority: " <> Text.unpack optName
    _ ->
      putStrLn "  Priority: (not found)"

  case Map.lookup "title" pageProps of
    Just (PV.TitleValue _pid rts) ->
      putStrLn $ "  Title rich text count: " <> show (Vector.length rts)
    _ ->
      putStrLn "  Title: (not found)"

  -- Demonstrate retrievePageProperty endpoint
  printHeader (Text.pack "Retrieve Page Property Item")

  -- Get the property ID for "Status" from the property value
  case Map.lookup "Status" pageProps of
    Just (PV.SelectValue propId _) -> do
      propItem <-
        runTest (Text.pack "Retrieving 'Status' property item") $
          retrievePageProperty methods newPageId propId Nothing Nothing
      case propItem of
        SinglePropertyItem pv ->
          putStrLn $ "  Single property item: " <> show pv
        PaginatedPropertyItems _list propType ->
          putStrLn $ "  Paginated property items (type: " <> Text.unpack propType <> ")"
    _ ->
      putStrLn "  Skipping (Status property not found)"

  -- Demonstrate auto-pagination with paginateAll
  printHeader (Text.pack "Auto-Pagination")

  allPages <-
    runTest (Text.pack "Paginating all data source results") $
      paginateAll $ \cursor ->
        queryDataSource methods dsId $
          DataSources.QueryDataSource
            { filter = Nothing,
              sorts = Nothing,
              startCursor = cursor,
              pageSize = Just 2, -- small page size to exercise pagination
              inTrash = Nothing,
              filterProperties = Nothing
            }
  putStrLn $ "Total pages collected via paginateAll: " <> show (Vector.length allPages)

  -- Demonstrate typed error handling
  printHeader (Text.pack "Typed Error Handling")

  putStr "Requesting invalid page to trigger NotionError... "
  let badPageId = UUID "00000000-0000-0000-0000-000000000000"
  result <- Exception.try @NotionError (retrievePage methods badPageId)
  case result of
    Left notionErr -> do
      putStrLn "caught!"
      putStrLn $ "  code: " <> Text.unpack (code notionErr)
      putStrLn $ "  message: " <> Text.unpack (message notionErr)
      putStrLn $ "  status: " <> show (status notionErr)
    Right _ ->
      putStrLn "unexpectedly succeeded (page exists?)"

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
      appendRequest = Blocks.AppendBlockChildren {children = additionalBlocks, position = Nothing}

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

  let -- Create rich text content for the comment using typed RichText
      commentRichText =
        Vector.singleton
          RichText
            { plainText = "This is an automated comment added via the Notion API! 🎉",
              href = Nothing,
              annotations = defaultAnnotations,
              type_ = "text",
              content = TextContentWrapper (TextContent {content = "This is an automated comment added via the Notion API! 🎉", link = Nothing})
            }

      -- Create the parent reference using the typed Parent constructor
      commentParent = PageParent {pageId = newPageId}

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
  let -- Create reply rich text using typed RichText
      replyRichText =
        Vector.singleton
          RichText
            { plainText = "This is a reply in the same discussion thread.",
              href = Nothing,
              annotations = defaultAnnotations,
              type_ = "text",
              content = TextContentWrapper (TextContent {content = "This is a reply in the same discussion thread.", link = Nothing})
            }

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
