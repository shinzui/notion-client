-- |
-- Custom Emojis API demonstration.
--
-- Shows how to:
-- - List custom emojis in the workspace
-- - Filter emojis by name
-- - Paginate through results
module CustomEmojiDemo
  ( runCustomEmojiDemo,
  )
where

import Console (printHeader, runTest)
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import Notion.V1 (Methods (..))
import Notion.V1.CustomEmojis (CustomEmoji (..))
import Notion.V1.ListOf (ListOf (..))
import Prelude hiding (id)

-- | Run the Custom Emoji API demonstration
runCustomEmojiDemo :: Methods -> IO ()
runCustomEmojiDemo methods = do
  printHeader (Text.pack "Custom Emojis API")

  -- ---------------------------------------------------------------
  -- Part 1: List all custom emojis (first page)
  -- ---------------------------------------------------------------
  result <-
    runTest (Text.pack "Listing custom emojis") $
      listCustomEmojis methods Nothing Nothing (Just 10)

  let List {results = emojis, hasMore = moreEmojis} = result
  putStrLn $ "Found " <> show (Vector.length emojis) <> " custom emojis"
  putStrLn $ "Has more: " <> show moreEmojis

  -- Display each emoji
  Vector.forM_ emojis $ \emoji -> do
    let CustomEmoji {id = emojiId, name = emojiName, url = emojiUrl} = emoji
    putStrLn $ "  - :" <> Text.unpack emojiName <> ": (id: " <> show emojiId <> ")"
    putStrLn $ "    url: " <> Text.unpack emojiUrl

  -- ---------------------------------------------------------------
  -- Part 2: Filter by name (if any emojis exist)
  -- ---------------------------------------------------------------
  if Vector.null emojis
    then putStrLn "No custom emojis found — skipping name filter demo"
    else do
      let CustomEmoji {name = firstName} = Vector.head emojis
      filtered <-
        runTest (Text.pack $ "Filtering by name: " <> Text.unpack firstName) $
          listCustomEmojis methods (Just firstName) Nothing Nothing

      let List {results = filteredEmojis} = filtered
      putStrLn $ "Exact match results: " <> show (Vector.length filteredEmojis)
