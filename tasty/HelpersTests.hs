-- | Tests for URL helpers and pagination folds.
module HelpersTests (tests) where

import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Vector qualified as Vector
import Notion.V1.Common (UUID (..))
import Notion.V1.Helpers
import Notion.V1.ListOf (ListOf (..))
import Notion.V1.Pagination (paginateFoldM)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Helpers"
    [ testCase "hyphenated UUID is lowercased" $
        extractNotionId "12345678-1234-1234-1234-123456789ABC" @?= Just (UUID "12345678-1234-1234-1234-123456789abc"),
      testCase "32 hex digits are formatted" $
        extractNotionId "12345678123412341234123456789abc" @?= Just (UUID "12345678-1234-1234-1234-123456789abc"),
      testCase "page URL with a title slug" $
        extractNotionId "https://www.notion.so/tanaka/Meeting-Notes-abc123def456789012345678901234ab"
          @?= Just (UUID "abc123de-f456-7890-1234-5678901234ab"),
      testCase "database URL prefers the path ID over the view ID" $
        extractDatabaseId "https://www.notion.so/tanaka/Tasks-abc123def456789012345678901234ab?v=0123456789abcdef0123456789abcdef"
          @?= Just (UUID "abc123de-f456-7890-1234-5678901234ab"),
      testCase "query parameter beats the last-resort rule" $
        extractNotionId "https://www.notion.so/tanaka?v=11111111111111111111111111111111&p=22222222222222222222222222222222"
          @?= Just (UUID "22222222-2222-2222-2222-222222222222"),
      testCase "last resort finds any 32 hex digits" $
        extractNotionId "notion.so/ffffffffffffffffffffffffffffffff" @?= Just (UUID "ffffffff-ffff-ffff-ffff-ffffffffffff"),
      testCase "non-IDs give Nothing" $ do
        extractNotionId "not-an-id" @?= Nothing
        extractNotionId "" @?= Nothing,
      testCase "extractBlockId reads the fragment" $ do
        extractBlockId (pageUrl <> "#block-fedcba9876543210fedcba9876543210") @?= Just (UUID "fedcba98-7654-3210-fedc-ba9876543210")
        extractBlockId (pageUrl <> "#fedcba9876543210fedcba9876543210") @?= Just (UUID "fedcba98-7654-3210-fedc-ba9876543210")
        extractBlockId pageUrl @?= Nothing,
      testCase "extractPageId on a block URL gives the page ID" $
        extractPageId (pageUrl <> "#block-fedcba9876543210fedcba9876543210") @?= Just (UUID "01234567-89ab-cdef-0123-456789abcdef"),
      testCase "paginateFoldM sums across pages" $ do
        calls <- newIORef (0 :: Int)
        let page rs cursor more = List {results = Vector.fromList rs, nextCursor = cursor, hasMore = more, type_ = Nothing, object = Nothing, requestStatus = Nothing}
            fetch cursor = do
              modifyIORef' calls (+ 1)
              pure $ case cursor of
                Nothing -> page [1 :: Int, 2, 3] (Just "cursor-1") True
                Just "cursor-1" -> page [4, 5] (Just "cursor-2") True
                _ -> page [6] Nothing False
        total <- paginateFoldM (\acc x -> pure (acc + x)) 0 fetch
        total @?= 21
        readIORef calls >>= (@?= 3)
    ]
  where
    pageUrl = "https://www.notion.so/Page-0123456789abcdef0123456789abcdef"
