-- |
-- Helper functions for creating Notion block objects.
--
-- These functions create typed block objects using the smart constructors
-- from "Notion.V1.BlockContent".
module Blocks
  ( createParagraphBlock,
    createHeadingBlock,
    createBulletedListItemBlock,
  )
where

import Data.Text (Text)
import Notion.V1.BlockContent

-- | Create a paragraph block with text content
createParagraphBlock :: Text -> BlockContent
createParagraphBlock = textBlock

-- | Create a heading block with text content
createHeadingBlock :: Text -> Int -> BlockContent
createHeadingBlock t level = headingBlock level (mkRichText t)

-- | Create a bulleted list item block with text content
createBulletedListItemBlock :: Text -> BlockContent
createBulletedListItemBlock = bulletedListItemBlock . mkRichText
