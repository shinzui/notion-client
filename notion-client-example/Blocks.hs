-- |
-- Helper functions for creating Notion block JSON objects.
--
-- These functions create JSON objects that match the Notion API's block format.
module Blocks
  ( createParagraphBlock,
    createHeadingBlock,
    createBulletedListItemBlock,
  )
where

import Data.Aeson qualified as Aeson
import Data.String (fromString)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector qualified as Vector

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
