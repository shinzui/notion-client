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
  -- Section 6: Nested blocks (children)
  -- -----------------------------------------------------------------------
  printHeader (Text.pack "Nested Blocks (Children)")

  let nestedBlocks =
        Vector.fromList
          [ headingBlock 2 (mkRichText "Nested Block Examples"),
            -- Toggle with two paragraph children
            toggleBlock (mkRichText "Click to expand this toggle")
              `withChildren` Vector.fromList
                [ textBlock "First nested paragraph inside the toggle.",
                  textBlock "Second nested paragraph inside the toggle."
                ],
            -- Bulleted list with nested sub-items
            bulletedListItemBlock (mkRichText "Parent list item")
              `withChildren` Vector.fromList
                [ bulletedListItemBlock (mkRichText "Sub-item one"),
                  bulletedListItemBlock (mkRichText "Sub-item two")
                ],
            -- Column layout with two columns
            ColumnListBlock
              { children =
                  Vector.fromList
                    [ ColumnBlock
                        { children = Vector.singleton (textBlock "Left column content")
                        },
                      ColumnBlock
                        { children = Vector.singleton (textBlock "Right column content")
                        }
                    ]
              },
            dividerBlock
          ]
      appendReq5 = AppendBlockChildren {children = nestedBlocks, position = Nothing}

  result5 <-
    runTest (Text.pack "Appending nested blocks") $
      appendBlockChildren methods testPageId appendReq5
  putStrLn $ "Appended " <> show (Vector.length $ results result5) <> " nested blocks"

  -- Verify has_children on the toggle
  let toggleResult = (Vector.toList (results result5)) !! 1
  putStrLn $ "Toggle has_children: " <> show (Blocks.hasChildren toggleResult)

  -- -----------------------------------------------------------------------
  -- Section 7: Position-based insertion
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
