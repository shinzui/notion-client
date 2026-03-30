-- | Pagination utilities for Notion API
module Notion.V1.Pagination
  ( -- * Pagination types
    PaginationParams (..),
    defaultPaginationParams,

    -- * Auto-pagination
    paginateAll,
    paginateCollect,
    PaginationResult (..),
  )
where

import Data.Vector qualified as Vector
import Notion.Prelude
import Notion.V1.ListOf (ListOf (..))

-- | Pagination parameters for Notion API requests
data PaginationParams = PaginationParams
  { pageSize :: Maybe Natural,
    startCursor :: Maybe Text
  }
  deriving stock (Generic, Show)

instance ToJSON PaginationParams where
  toJSON = genericToJSON aesonOptions

-- | Default pagination parameters
defaultPaginationParams :: PaginationParams
defaultPaginationParams =
  PaginationParams
    { pageSize = Nothing,
      startCursor = Nothing
    }

-- | Result of auto-pagination, including all collected results and page count.
data PaginationResult a = PaginationResult
  { allResults :: Vector a,
    totalPages :: Natural
  }
  deriving stock (Show)

-- | Automatically paginate through all results by following cursors.
--
-- The callback receives an optional cursor ('Nothing' for the first page)
-- and returns a paginated response. The function calls the callback
-- repeatedly until 'hasMore' is 'False' or 'nextCursor' is 'Nothing',
-- collecting all results into a single 'Vector'.
--
-- Example:
--
-- @
-- allPages <- paginateAll $ \\cursor ->
--   queryDataSource methods dsId QueryDataSource
--     { filter = Nothing
--     , sorts = Nothing
--     , startCursor = cursor
--     , pageSize = Just 100
--     , inTrash = Nothing
--     , filterProperties = Nothing
--     }
-- @
paginateAll :: (Maybe Text -> IO (ListOf a)) -> IO (Vector a)
paginateAll fetch = allResults <$> paginateCollect fetch

-- | Like 'paginateAll' but also returns the number of pages fetched.
paginateCollect :: (Maybe Text -> IO (ListOf a)) -> IO (PaginationResult a)
paginateCollect fetch = go Nothing Vector.empty 0
  where
    go cursor acc pages = do
      List {results, nextCursor, hasMore} <- fetch cursor
      let acc' = acc <> results
          pages' = pages + 1
      if hasMore
        then case nextCursor of
          Just nc -> go (Just nc) acc' pages'
          Nothing -> pure PaginationResult {allResults = acc', totalPages = pages'}
        else pure PaginationResult {allResults = acc', totalPages = pages'}
