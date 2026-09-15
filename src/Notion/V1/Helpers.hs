-- | Helpers for turning Notion URLs into IDs, ported from the official JS SDK.
module Notion.V1.Helpers
  ( extractNotionId,
    extractPageId,
    extractDatabaseId,
    extractBlockId,
  )
where

import Data.Char (isHexDigit)
import Data.List (find)
import Data.Maybe (catMaybes, listToMaybe, mapMaybe)
import Data.Text qualified as Text
import Notion.Prelude
import Notion.V1.Common (UUID (..))

-- | Extract a Notion ID from a URL or an ID in either format. Returns the
-- lowercase, hyphenated form.
--
-- Tried in order: a hyphenated UUID; 32 hex digits; a path segment ending in
-- @-\<32 hex digits\>@ (for example @.../Meeting-Notes-\<id\>@); a @p@,
-- @page_id@ or @database_id@ query parameter; the first run of 32 hex digits.
--
-- @
-- extractNotionId "https://www.notion.so/team/Tasks-abc123def456789012345678901234ab?v=..."
--   == Just (UUID "abc123de-f456-7890-1234-5678901234ab")
-- @
extractNotionId :: Text -> Maybe UUID
extractNotionId input
  | isHyphenatedUuid t = Just (UUID (Text.toLower t))
  | isHex32 t = Just (formatUuid t)
  | otherwise = formatUuid <$> firstJust [pathRule, queryRule, anyRule]
  where
    t = Text.strip input

    pathRule =
      listToMaybe
        [ Text.takeEnd 32 segment
        | rest <- afterEach (== '/') t,
          let segment = Text.takeWhile (`notElem` ("/?#" :: String)) rest,
          Text.length segment >= 33,
          Text.take 1 (Text.takeEnd 33 segment) == "-",
          isHex32 (Text.takeEnd 32 segment)
        ]

    queryRule =
      listToMaybe
        [ candidate
        | rest <- afterEach (`elem` ("?&" :: String)) t,
          prefix <- ["p=", "page_id=", "database_id="],
          Text.toLower (Text.take (Text.length prefix) rest) == prefix,
          let candidate = Text.take 32 (Text.drop (Text.length prefix) rest),
          isHex32 candidate
        ]

    anyRule = find isHex32 (map (Text.take 32) (Text.tails t))

-- | Alias of 'extractNotionId' for page URLs.
extractPageId :: Text -> Maybe UUID
extractPageId = extractNotionId

-- | Alias of 'extractNotionId' for database URLs.
extractDatabaseId :: Text -> Maybe UUID
extractDatabaseId = extractNotionId

-- | Extract a block ID from a URL fragment: @#block-\<id\>@ or @#\<id\>@.
extractBlockId :: Text -> Maybe UUID
extractBlockId input =
  formatUuid
    <$> listToMaybe
      [ candidate
      | rest <- afterEach (== '#') input,
        let afterPrefix =
              if Text.toLower (Text.take 6 rest) == "block-" then Text.drop 6 rest else rest
            candidate = Text.take 32 afterPrefix,
        isHex32 candidate
      ]

-- | The remainder of the text after each character matching the predicate, left to right.
afterEach :: (Char -> Bool) -> Text -> [Text]
afterEach p = mapMaybe after . Text.tails
  where
    after s = case Text.uncons s of
      Just (c, rest) | p c -> Just rest
      _ -> Nothing

firstJust :: [Maybe a] -> Maybe a
firstJust = listToMaybe . catMaybes

isHex32 :: Text -> Bool
isHex32 s = Text.length s == 32 && Text.all isHexDigit s

isHyphenatedUuid :: Text -> Bool
isHyphenatedUuid s =
  Text.length s == 36
    && and (zipWith valid [0 :: Int ..] (Text.unpack s))
  where
    valid i c
      | i `elem` [8, 13, 18, 23] = c == '-'
      | otherwise = isHexDigit c

-- | Lowercase 32 hex digits with hyphens in the 8-4-4-4-12 pattern.
formatUuid :: Text -> UUID
formatUuid hex =
  UUID . Text.intercalate "-" $
    [Text.take 8 l, Text.take 4 (Text.drop 8 l), Text.take 4 (Text.drop 12 l), Text.take 4 (Text.drop 16 l), Text.drop 20 l]
  where
    l = Text.toLower hex
