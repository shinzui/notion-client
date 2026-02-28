-- |
-- Page API demonstration.
module PageDemo
  ( runPageDemo,
  )
where

import Console (printHeader, runTest)
import Control.Monad (when)
import Data.Aeson qualified as Aeson
import Data.String (fromString)
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import Notion.V1 (Methods (..))
import Notion.V1.Blocks qualified as Blocks
import Notion.V1.Comments (CommentObject (..), CreateComment (..))
import Notion.V1.Common (Parent (..))
import Notion.V1.ListOf (ListOf (..))
import Notion.V1.RichText (RichText (..), RichTextContent (..), TextContent (..), defaultAnnotations)
import Prelude hiding (id)

-- | Run the Page API demonstration
runPageDemo :: Methods -> String -> IO ()
runPageDemo methods pageIdStr = do
  let pageId = fromString pageIdStr

  printHeader (Text.pack "Page API")

  -- Retrieve page
  _page <-
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
    printHeader (Text.pack "Adding Comment to Block")

    let -- Create rich text content for the block comment using typed RichText
        blockCommentRichText =
          Vector.singleton
            RichText
              { plainText = "This comment is attached to a specific block, not the page!",
                href = Nothing,
                annotations = defaultAnnotations,
                type_ = "text",
                content = TextContentWrapper (TextContent {content = "This comment is attached to a specific block, not the page!", link = Nothing})
              }

        -- Create the parent reference using the typed Parent constructor
        -- This is different from page comments which use PageParent
        blockCommentParent = BlockParent {blockId = firstBlockId}

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
  _updatedPage <-
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
  printHeader (Text.pack "Comments API")

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
    putStrLn "First comment details:"
    putStrLn $ "  id: " <> show commentId
    putStrLn $ "  discussionId: " <> show discId
    putStrLn $ "  createdBy: " <> show createdBy
    putStrLn $ "  attachments: " <> show commentAttachments
    putStrLn $ "  displayName: " <> show displayName
