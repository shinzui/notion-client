-- |
-- Block API demonstration showcasing typed block content.
--
-- Demonstrates creating various block types using the typed smart constructors
-- from "Notion.V1.BlockContent" instead of raw JSON.
module BlockDemo
  ( runBlockDemo,
  )
where

import Console (printHeader, runTest)
import Data.String (fromString)
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import Notion.V1 (Methods (..))
import Notion.V1.BlockContent
import Notion.V1.Blocks (AppendBlockChildren (..), Position (..))
import Notion.V1.Blocks qualified as Blocks
import Notion.V1.Common (Color (..), ExternalFile (..), Icon (..), Parent (..))
import Notion.V1.ListOf (ListOf (..))
import Notion.V1.Pages (CreatePage (..), PageObject (..), mkCreatePage)
import Notion.V1.RichText (Annotations (..), RichText (..), RichTextContent (..), TextContent (..), defaultAnnotations)
import Prelude hiding (id)

-- | Run the Block API demonstration
runBlockDemo :: Methods -> String -> IO ()
runBlockDemo methods pageIdStr = do
  let parentPageId = fromString pageIdStr

  printHeader (Text.pack "Typed Block Content Demo")
  putStrLn "Demonstrating typed block creation using smart constructors"

  -- Create a test page for block demos
  let createReq = mkCreatePage (PageParent {pageId = parentPageId}) mempty
  page <-
    runTest (Text.pack "Creating test page for block demo") $
      createPage methods createReq {children = Nothing, icon = Just (EmojiIcon "🧱")}
  let PageObject {id = testPageId} = page
  putStrLn $ "Test page created: " <> show testPageId

  -- -----------------------------------------------------------------------
  -- Section 1: Text blocks using smart constructors
  -- -----------------------------------------------------------------------
  printHeader (Text.pack "Text Blocks (Smart Constructors)")

  let textBlocks =
        Vector.fromList
          [ -- Simple paragraph from plain text
            textBlock "This paragraph was created with textBlock — the simplest way to add text.",
            -- Paragraph with rich text
            paragraphBlock (mkRichText "This paragraph uses paragraphBlock with mkRichText."),
            -- Headings at all three levels
            headingBlock 1 (mkRichText "Heading Level 1"),
            headingBlock 2 (mkRichText "Heading Level 2"),
            headingBlock 3 (mkRichText "Heading Level 3"),
            -- List items
            bulletedListItemBlock (mkRichText "First bulleted item"),
            bulletedListItemBlock (mkRichText "Second bulleted item"),
            numberedListItemBlock (mkRichText "First numbered item"),
            numberedListItemBlock (mkRichText "Second numbered item"),
            -- To-do items
            toDoBlock (mkRichText "Unchecked task") False,
            toDoBlock (mkRichText "Completed task") True,
            -- Toggle
            toggleBlock (mkRichText "Click to expand this toggle"),
            -- Quote
            quoteBlock (mkRichText "This is a quote block — great for callouts or citations."),
            -- Divider
            dividerBlock
          ]
      appendReq1 = AppendBlockChildren {children = textBlocks, position = Nothing}

  result1 <-
    runTest (Text.pack "Appending text blocks") $
      appendBlockChildren methods testPageId appendReq1
  putStrLn $ "Appended " <> show (Vector.length $ results result1) <> " text blocks"

  -- -----------------------------------------------------------------------
  -- Section 2: Code, equation, and callout blocks
  -- -----------------------------------------------------------------------
  printHeader (Text.pack "Code, Equation, and Callout Blocks")

  let specialBlocks =
        Vector.fromList
          [ headingBlock 2 (mkRichText "Code Examples"),
            -- Code block with Haskell
            codeBlock
              (mkRichText "main :: IO ()\nmain = putStrLn \"Hello from typed blocks!\"")
              Haskell,
            -- Code block with JavaScript
            codeBlock
              (mkRichText "const greet = (name) => `Hello, ${name}!`;")
              JavaScript,
            -- Code block with Python
            codeBlock
              (mkRichText "def factorial(n):\n    return 1 if n <= 1 else n * factorial(n - 1)")
              Python,
            -- Equation block
            equationBlock "E = mc^2",
            -- Callout with emoji icon
            calloutBlock
              (mkRichText "This is a callout with an emoji icon")
              (Just (EmojiIcon "💡")),
            -- Callout without icon
            calloutBlock
              (mkRichText "This is a callout without an icon")
              Nothing
          ]
      appendReq2 = AppendBlockChildren {children = specialBlocks, position = Nothing}

  result2 <-
    runTest (Text.pack "Appending code/equation/callout blocks") $
      appendBlockChildren methods testPageId appendReq2
  putStrLn $ "Appended " <> show (Vector.length $ results result2) <> " special blocks"

  -- -----------------------------------------------------------------------
  -- Section 3: Embeds and media
  -- -----------------------------------------------------------------------
  printHeader (Text.pack "Embed and Bookmark Blocks")

  let embedBlocks =
        Vector.fromList
          [ headingBlock 2 (mkRichText "Links and Embeds"),
            -- Bookmark
            bookmarkBlock "https://www.haskell.org",
            -- External image
            imageBlock (ExternalSource (ExternalFile {url = "https://www.haskell.org/img/haskell-logo.svg"})),
            dividerBlock
          ]
      appendReq3 = AppendBlockChildren {children = embedBlocks, position = Nothing}

  result3 <-
    runTest (Text.pack "Appending embed/bookmark blocks") $
      appendBlockChildren methods testPageId appendReq3
  putStrLn $ "Appended " <> show (Vector.length $ results result3) <> " embed blocks"

  -- -----------------------------------------------------------------------
  -- Section 4: Blocks with full constructor control (not smart constructors)
  -- -----------------------------------------------------------------------
  printHeader (Text.pack "Blocks with Full Control")

  let -- Rich text with annotations
      boldRichText =
        Vector.singleton
          RichText
            { plainText = "Bold and colored text",
              href = Nothing,
              annotations = defaultAnnotations {bold = True},
              type_ = "text",
              content = TextContentWrapper (TextContent {content = "Bold and colored text", link = Nothing})
            }

      -- Paragraph with non-default color
      coloredParagraph = ParagraphBlock boldRichText Blue Nothing Vector.empty

      -- Toggleable heading
      toggleableHeading = Heading2Block (mkRichText "This heading is toggleable") Default True Vector.empty

      fullControlBlocks =
        Vector.fromList
          [ headingBlock 2 (mkRichText "Full Constructor Control"),
            coloredParagraph,
            toggleableHeading,
            dividerBlock
          ]
      appendReq4 = AppendBlockChildren {children = fullControlBlocks, position = Nothing}

  result4 <-
    runTest (Text.pack "Appending blocks with full control") $
      appendBlockChildren methods testPageId appendReq4
  putStrLn $ "Appended " <> show (Vector.length $ results result4) <> " blocks with full control"

  -- -----------------------------------------------------------------------
  -- Section 5: Read blocks back and pattern match on typed content
  -- -----------------------------------------------------------------------
  printHeader (Text.pack "Reading and Pattern Matching")

  allBlocks <-
    runTest (Text.pack "Retrieving all blocks from test page") $
      listBlockChildren methods testPageId Nothing Nothing
  let List {results = allBlockResults} = allBlocks
  putStrLn $ "Total blocks on page: " <> show (Vector.length allBlockResults)

  -- Demonstrate pattern matching on typed content
  putStrLn "\nBlock types found (via pattern matching):"
  Vector.forM_ allBlockResults $ \block -> do
    let prefix = "  - "
    case Blocks.content block of
      ParagraphBlock {} -> putStrLn $ prefix <> "paragraph"
      Heading1Block {} -> putStrLn $ prefix <> "heading_1"
      Heading2Block {isToggleable} ->
        putStrLn $ prefix <> "heading_2" <> if isToggleable then " (toggleable)" else ""
      Heading3Block {} -> putStrLn $ prefix <> "heading_3"
      BulletedListItemBlock {} -> putStrLn $ prefix <> "bulleted_list_item"
      NumberedListItemBlock {listFormat} ->
        putStrLn $ prefix <> "numbered_list_item" <> maybe "" (\f -> " (format: " <> show f <> ")") listFormat
      ToDoBlock {checked} ->
        putStrLn $ prefix <> "to_do [" <> (if checked then "x" else " ") <> "]"
      ToggleBlock {} -> putStrLn $ prefix <> "toggle"
      QuoteBlock {} -> putStrLn $ prefix <> "quote"
      CalloutBlock {calloutIcon} ->
        putStrLn $ prefix <> "callout" <> maybe "" (\_ -> " (with icon)") calloutIcon
      CodeBlock {language} ->
        putStrLn $ prefix <> "code (" <> show language <> ")"
      EquationBlock {expression} ->
        putStrLn $ prefix <> "equation: " <> Text.unpack expression
      ImageBlock {} -> putStrLn $ prefix <> "image"
      BookmarkBlock {url} ->
        putStrLn $ prefix <> "bookmark: " <> Text.unpack url
      DividerBlock -> putStrLn $ prefix <> "divider"
      _ -> putStrLn $ prefix <> Text.unpack (Blocks.type_ block)

  -- -----------------------------------------------------------------------
  -- Section 6: Nested blocks — text-like parents
  -- -----------------------------------------------------------------------
  printHeader (Text.pack "Nested Blocks — Text Parents")

  let textParentBlocks =
        Vector.fromList
          [ headingBlock 2 (mkRichText "Nested Block Examples"),
            -- 1. Toggle with paragraph children (most common use case)
            toggleBlock (mkRichText "Toggle with children")
              `withChildren` Vector.fromList
                [ textBlock "First child inside toggle.",
                  textBlock "Second child inside toggle."
                ],
            -- 2. Paragraph with children
            paragraphBlock (mkRichText "Paragraph with nested content")
              `withChildren` Vector.fromList
                [ textBlock "Child of paragraph."
                ],
            -- 3. Bulleted list with nested sub-items
            bulletedListItemBlock (mkRichText "Parent bullet")
              `withChildren` Vector.fromList
                [ bulletedListItemBlock (mkRichText "Sub-bullet A"),
                  bulletedListItemBlock (mkRichText "Sub-bullet B")
                ],
            -- 4. Numbered list with nested sub-items
            numberedListItemBlock (mkRichText "Parent numbered item")
              `withChildren` Vector.fromList
                [ numberedListItemBlock (mkRichText "Sub-item 1"),
                  numberedListItemBlock (mkRichText "Sub-item 2")
                ],
            -- 5. To-do with children
            toDoBlock (mkRichText "Task with sub-tasks") False
              `withChildren` Vector.fromList
                [ toDoBlock (mkRichText "Sub-task A") True,
                  toDoBlock (mkRichText "Sub-task B") False
                ],
            -- 6. Quote with children
            quoteBlock (mkRichText "Quote with attribution")
              `withChildren` Vector.fromList
                [ textBlock "— Source of the quote"
                ],
            -- 7. Callout with children
            calloutBlock (mkRichText "Important notice") (Just (EmojiIcon "⚠️"))
              `withChildren` Vector.fromList
                [ textBlock "Additional details inside the callout.",
                  bulletedListItemBlock (mkRichText "Action item one"),
                  bulletedListItemBlock (mkRichText "Action item two")
                ],
            dividerBlock
          ]
      appendReq5 = AppendBlockChildren {children = textParentBlocks, position = Nothing}

  result5 <-
    runTest (Text.pack "Appending text-parent nested blocks") $
      appendBlockChildren methods testPageId appendReq5
  let result5List = Vector.toList (results result5)
  putStrLn $ "Appended " <> show (length result5List) <> " blocks"

  -- Verify has_children on each parent block
  putStrLn "\nVerifying has_children on returned blocks:"
  let parentIndices = [1, 2, 3, 4, 5, 6, 7] :: [Int] -- indices of blocks with children (0 = heading)
  mapM_
    ( \i -> do
        let b = result5List !! i
        putStrLn $
          "  "
            <> Text.unpack (Blocks.type_ b)
            <> ": has_children="
            <> show (Blocks.hasChildren b)
    )
    parentIndices

  -- Fetch children of the toggle and verify count
  let toggleObj = result5List !! 1
  toggleKids <-
    runTest (Text.pack "Fetching toggle children") $
      listBlockChildren methods (Blocks.id toggleObj) Nothing Nothing
  putStrLn $ "Toggle child count: " <> show (Vector.length $ results toggleKids)

  -- Fetch children of the callout and verify types
  let calloutObj = result5List !! 7
  calloutKids <-
    runTest (Text.pack "Fetching callout children") $
      listBlockChildren methods (Blocks.id calloutObj) Nothing Nothing
  putStrLn "Callout children:"
  Vector.forM_ (results calloutKids) $ \kid ->
    putStrLn $ "  - " <> Text.unpack (Blocks.type_ kid)

  -- -----------------------------------------------------------------------
  -- Section 7: Nested blocks — toggleable headings
  -- -----------------------------------------------------------------------
  printHeader (Text.pack "Nested Blocks — Toggleable Headings")

  let headingBlocks =
        Vector.fromList
          [ -- Toggleable heading 1 with children
            Heading1Block
              { richText = mkRichText "Toggleable H1 with content",
                color = Default,
                isToggleable = True,
                children =
                  Vector.fromList
                    [ textBlock "Content revealed when H1 is expanded.",
                      codeBlock (mkRichText "putStrLn \"inside heading\"") Haskell
                    ]
              },
            -- Toggleable heading 2
            Heading2Block
              { richText = mkRichText "Toggleable H2",
                color = Default,
                isToggleable = True,
                children = Vector.singleton (textBlock "H2 nested content.")
              },
            -- Toggleable heading 3
            Heading3Block
              { richText = mkRichText "Toggleable H3",
                color = Default,
                isToggleable = True,
                children = Vector.singleton (textBlock "H3 nested content.")
              },
            -- Non-toggleable heading (no children) for comparison
            headingBlock 2 (mkRichText "Normal H2 (not toggleable, no children)"),
            dividerBlock
          ]
      appendReq6 = AppendBlockChildren {children = headingBlocks, position = Nothing}

  result6 <-
    runTest (Text.pack "Appending toggleable headings") $
      appendBlockChildren methods testPageId appendReq6
  let result6List = Vector.toList (results result6)
  putStrLn "Toggleable heading results:"
  mapM_
    ( \i -> do
        let b = result6List !! i
        putStrLn $
          "  "
            <> Text.unpack (Blocks.type_ b)
            <> ": has_children="
            <> show (Blocks.hasChildren b)
    )
    [0, 1, 2, 3 :: Int]

  -- Fetch children of togglable H1
  let h1Obj = result6List !! 0
  h1Kids <-
    runTest (Text.pack "Fetching toggleable H1 children") $
      listBlockChildren methods (Blocks.id h1Obj) Nothing Nothing
  putStrLn $ "H1 child count: " <> show (Vector.length $ results h1Kids)
  Vector.forM_ (results h1Kids) $ \kid ->
    putStrLn $ "  - " <> Text.unpack (Blocks.type_ kid)

  -- -----------------------------------------------------------------------
  -- Section 8: Nested blocks — structural (columns, tables)
  -- -----------------------------------------------------------------------
  printHeader (Text.pack "Nested Blocks — Columns and Tables")

  let structuralBlocks =
        Vector.fromList
          [ headingBlock 2 (mkRichText "Column Layout"),
            -- Column list with 3 columns, each containing multiple blocks
            ColumnListBlock
              { children =
                  Vector.fromList
                    [ ColumnBlock
                        { children =
                            Vector.fromList
                              [ headingBlock 3 (mkRichText "Column A"),
                                textBlock "Content in column A."
                              ]
                        },
                      ColumnBlock
                        { children =
                            Vector.fromList
                              [ headingBlock 3 (mkRichText "Column B"),
                                textBlock "Content in column B."
                              ]
                        },
                      ColumnBlock
                        { children =
                            Vector.fromList
                              [ headingBlock 3 (mkRichText "Column C"),
                                textBlock "Content in column C."
                              ]
                        }
                    ]
              },
            headingBlock 2 (mkRichText "Table with Row Children"),
            -- Table with inline table_row children
            TableBlock
              { tableWidth = 3,
                hasColumnHeader = True,
                hasRowHeader = False,
                children =
                  Vector.fromList
                    [ TableRowBlock
                        { cells =
                            Vector.fromList
                              [ mkRichText "Name",
                                mkRichText "Language",
                                mkRichText "Year"
                              ]
                        },
                      TableRowBlock
                        { cells =
                            Vector.fromList
                              [ mkRichText "GHC",
                                mkRichText "Haskell",
                                mkRichText "1992"
                              ]
                        },
                      TableRowBlock
                        { cells =
                            Vector.fromList
                              [ mkRichText "Cabal",
                                mkRichText "Haskell",
                                mkRichText "2004"
                              ]
                        }
                    ]
              },
            dividerBlock
          ]
      appendReq7 = AppendBlockChildren {children = structuralBlocks, position = Nothing}

  result7 <-
    runTest (Text.pack "Appending columns and table") $
      appendBlockChildren methods testPageId appendReq7
  let result7List = Vector.toList (results result7)

  -- Verify column_list has children
  let columnListObj = result7List !! 1
  putStrLn $ "column_list has_children: " <> show (Blocks.hasChildren columnListObj)

  -- Fetch columns
  columnKids <-
    runTest (Text.pack "Fetching column_list children") $
      listBlockChildren methods (Blocks.id columnListObj) Nothing Nothing
  putStrLn $ "Number of columns: " <> show (Vector.length $ results columnKids)

  -- Fetch content of first column
  let firstCol = Vector.head (results columnKids)
  colContent <-
    runTest (Text.pack "Fetching first column content") $
      listBlockChildren methods (Blocks.id firstCol) Nothing Nothing
  putStrLn "First column content:"
  Vector.forM_ (results colContent) $ \kid ->
    putStrLn $ "  - " <> Text.unpack (Blocks.type_ kid)

  -- Verify table has children (rows)
  let tableObj = result7List !! 3
  putStrLn $ "\ntable has_children: " <> show (Blocks.hasChildren tableObj)

  tableKids <-
    runTest (Text.pack "Fetching table rows") $
      listBlockChildren methods (Blocks.id tableObj) Nothing Nothing
  putStrLn $ "Table row count: " <> show (Vector.length $ results tableKids)

  -- -----------------------------------------------------------------------
  -- Section 9: Nested blocks — synced block and two-level nesting
  -- -----------------------------------------------------------------------
  printHeader (Text.pack "Nested Blocks — Synced Block & Two-Level Nesting")

  let advancedBlocks =
        Vector.fromList
          [ headingBlock 2 (mkRichText "Synced Block with Children"),
            -- Original synced block with children
            SyncedBlockContent
              { syncedFrom = SyncedOriginal,
                children =
                  Vector.fromList
                    [ textBlock "Content inside the synced block.",
                      bulletedListItemBlock (mkRichText "Synced list item")
                    ]
              },
            headingBlock 2 (mkRichText "Two-Level Nesting"),
            -- Toggle containing a quote containing a paragraph (2 levels deep)
            toggleBlock (mkRichText "Outer toggle (level 1)")
              `withChildren` Vector.fromList
                [ quoteBlock (mkRichText "Inner quote (level 2)")
                    `withChildren` Vector.fromList
                      [ textBlock "Deepest content (grandchild)."
                      ],
                  textBlock "Also inside the toggle."
                ],
            -- Bulleted list with nested numbered sub-items
            bulletedListItemBlock (mkRichText "Mixed nesting: bullet parent")
              `withChildren` Vector.fromList
                [ numberedListItemBlock (mkRichText "Numbered sub-item 1"),
                  numberedListItemBlock (mkRichText "Numbered sub-item 2"),
                  toDoBlock (mkRichText "To-do sub-item") False
                ],
            dividerBlock
          ]
      appendReq8 = AppendBlockChildren {children = advancedBlocks, position = Nothing}

  result8 <-
    runTest (Text.pack "Appending synced block and two-level nesting") $
      appendBlockChildren methods testPageId appendReq8
  let result8List = Vector.toList (results result8)

  -- Verify synced block
  let syncedObj = result8List !! 1
  putStrLn $ "synced_block has_children: " <> show (Blocks.hasChildren syncedObj)
  syncedKids <-
    runTest (Text.pack "Fetching synced_block children") $
      listBlockChildren methods (Blocks.id syncedObj) Nothing Nothing
  putStrLn $ "Synced block child count: " <> show (Vector.length $ results syncedKids)
  Vector.forM_ (results syncedKids) $ \kid ->
    putStrLn $ "  - " <> Text.unpack (Blocks.type_ kid)

  -- Verify two-level nesting: outer toggle → inner quote → grandchild paragraph
  let outerToggle = result8List !! 3
  putStrLn $ "\nOuter toggle has_children: " <> show (Blocks.hasChildren outerToggle)
  outerKids <-
    runTest (Text.pack "Fetching outer toggle children") $
      listBlockChildren methods (Blocks.id outerToggle) Nothing Nothing
  putStrLn $ "Outer toggle child count: " <> show (Vector.length $ results outerKids)

  -- The first child should be the quote, which itself has children
  let innerQuote = Vector.head (results outerKids)
  putStrLn $ "Inner quote has_children: " <> show (Blocks.hasChildren innerQuote)
  grandKids <-
    runTest (Text.pack "Fetching grandchildren (quote's children)") $
      listBlockChildren methods (Blocks.id innerQuote) Nothing Nothing
  putStrLn $ "Grandchild count: " <> show (Vector.length $ results grandKids)
  Vector.forM_ (results grandKids) $ \kid ->
    putStrLn $ "  - " <> Text.unpack (Blocks.type_ kid)

  -- Verify mixed nesting bullet
  let mixedBullet = result8List !! 4
  mixedKids <-
    runTest (Text.pack "Fetching mixed-nesting bullet children") $
      listBlockChildren methods (Blocks.id mixedBullet) Nothing Nothing
  putStrLn $ "\nMixed bullet child count: " <> show (Vector.length $ results mixedKids)
  Vector.forM_ (results mixedKids) $ \kid ->
    putStrLn $ "  - " <> Text.unpack (Blocks.type_ kid)

  -- -----------------------------------------------------------------------
  -- Section 10: withChildren combinator showcase
  -- -----------------------------------------------------------------------
  printHeader (Text.pack "withChildren Combinator Showcase")

  let combinatorBlocks =
        Vector.fromList
          [ headingBlock 2 (mkRichText "withChildren Combinator"),
            -- withChildren on various block types
            paragraphBlock (mkRichText "Paragraph via withChildren")
              `withChildren` Vector.singleton (textBlock "Nested under paragraph."),
            calloutBlock (mkRichText "Callout via withChildren") (Just (EmojiIcon "📌"))
              `withChildren` Vector.fromList
                [ textBlock "Step 1: Read the docs.",
                  textBlock "Step 2: Write the code.",
                  textBlock "Step 3: Ship it."
                ],
            -- withChildren on a block that doesn't support children (no-op)
            -- codeBlock and dividerBlock are unchanged by withChildren
            codeBlock (mkRichText "-- withChildren is a no-op on code blocks") Haskell
              `withChildren` Vector.singleton (textBlock "This child is silently dropped."),
            dividerBlock
          ]
      appendReq9 = AppendBlockChildren {children = combinatorBlocks, position = Nothing}

  result9 <-
    runTest (Text.pack "Appending withChildren showcase") $
      appendBlockChildren methods testPageId appendReq9
  let result9List = Vector.toList (results result9)

  putStrLn "withChildren results:"
  putStrLn $ "  paragraph has_children: " <> show (Blocks.hasChildren (result9List !! 1))
  putStrLn $ "  callout has_children: " <> show (Blocks.hasChildren (result9List !! 2))
  putStrLn $ "  code has_children: " <> show (Blocks.hasChildren (result9List !! 3)) <> " (expected False)"

  -- -----------------------------------------------------------------------
  -- Section 11: Position-based insertion
  -- -----------------------------------------------------------------------
  printHeader (Text.pack "Position-based Insertion")

  -- Insert at the start of the page
  let startBlock = textBlock "This block was inserted at the START of the page."
      startReq = AppendBlockChildren {children = Vector.singleton startBlock, position = Just Start}
  _ <-
    runTest (Text.pack "Inserting block at start") $
      appendBlockChildren methods testPageId startReq
  putStrLn "Block inserted at start position"

  -- Verify the first block is our new paragraph
  refreshed <-
    runTest (Text.pack "Verifying insertion order") $
      listBlockChildren methods testPageId (Just 1) Nothing
  let List {results = firstResults} = refreshed
  case Vector.toList firstResults of
    (first : _) ->
      putStrLn $ "First block type: " <> Text.unpack (Blocks.type_ first)
    [] ->
      putStrLn "No blocks found (unexpected)"

  -- Clean up: move page to trash
  printHeader (Text.pack "Cleanup")
  _ <-
    runTest (Text.pack "Trashing test page") $
      deleteBlock methods testPageId
  putStrLn "Test page moved to trash"
  putStrLn "Block demo complete!"
