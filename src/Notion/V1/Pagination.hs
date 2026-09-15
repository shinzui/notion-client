-- | Pagination utilities for Notion API
module Notion.V1.Pagination
  ( -- * Pagination types
    PaginationParams (..),
    defaultPaginationParams,

    -- * Auto-pagination
    paginateAll,
    paginateCollect,
    paginateFoldM,
    paginateForM_,
    PaginationResult (..),
  )
where

import Control.Monad (foldM)
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

-- | Fold over every item of a paginated endpoint, holding one page in memory at
-- a time. Follows cursors like 'paginateAll'.
paginateFoldM :: (b -> a -> IO b) -> b -> (Maybe Text -> IO (ListOf a)) -> IO b
paginateFoldM step initial fetch = go Nothing initial
  where
    go cursor acc = do
      List {results, nextCursor, hasMore} <- fetch cursor
      acc' <- foldM step acc results
      case nextCursor of
        Just nc | hasMore -> go (Just nc) acc'
        _ -> pure acc'

-- | Run an action for every item of a paginated endpoint.
paginateForM_ :: (Maybe Text -> IO (ListOf a)) -> (a -> IO ()) -> IO ()
paginateForM_ fetch action = paginateFoldM (\() a -> action a) () fetch

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
