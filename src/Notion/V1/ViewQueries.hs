-- | Convenience helpers for the view-query flow.
module Notion.V1.ViewQueries
  ( queryAllViewPages,
  )
where

import Control.Exception qualified as Exception
import Notion.Prelude
import Notion.V1 (Methods (..))
import Notion.V1.ListOf (ListOf (..))
import Notion.V1.Pages (PartialPageObject)
import Notion.V1.Views (CreateViewQuery (..), ViewID, ViewQuery (..))
import Prelude hiding (id)

-- | Create a view query, collect every result page, then delete the query.
--
-- The page size (max 100) applies to every request. Errors from the final
-- delete are swallowed: the cached query expires on its own.
queryAllViewPages :: Methods -> ViewID -> Maybe Natural -> IO (Vector PartialPageObject)
queryAllViewPages Methods {createViewQuery, getViewQueryResults, deleteViewQuery} viewId pageSize = do
  ViewQuery {id = queryId, results = firstPage, nextCursor, hasMore} <-
    createViewQuery viewId CreateViewQuery {pageSize}
  let cleanup = do
        _ <- Exception.try @Exception.SomeException (deleteViewQuery viewId queryId)
        pure ()
      go acc (Just cursor) True = do
        List {results, nextCursor = next, hasMore = more} <-
          getViewQueryResults viewId queryId (Just cursor) pageSize
        go (acc <> results) next more
      go acc _ _ = pure acc
  go firstPage nextCursor hasMore `Exception.finally` cleanup
