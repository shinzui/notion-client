-- | Iterate every row of a data source, including rows past Notion's per-query result limit.
--
-- A single data source query stops paginating once it has returned a fixed number of rows
-- (10,000 by default) and marks the response @request_status: incomplete@. These helpers
-- work around that limit the same way the official JS SDK's @iterateAllDataSourceRows@ does:
-- they sort by @created_time@ ascending and, whenever a query window hits the limit, start
-- a new window filtered to @created_time on_or_after@ the last row seen, skipping rows
-- already visited.
--
-- @
-- rows <- collectAllDataSourceRows (queryDataSource methods dsId) _QueryDataSource Nothing
-- @
module Notion.V1.DataSourceRows
  ( AllRowsFilter (..),
    DataSourceRowsError (..),
    createdTimeLowerBound,
    foldAllDataSourceRows,
    iterateAllDataSourceRows,
    collectAllDataSourceRows,
  )
where

import Control.Exception (Exception, throwIO)
import Control.Monad (foldM)
import Data.Set qualified as Set
import Data.Vector qualified as Vector
import Notion.Prelude
import Notion.V1.DataSources (PageOrDataSource, QueryDataSource (..), resultCreatedTime, resultId)
import Notion.V1.Filter (DateCondition (..), Filter (..), PropertyCondition, Sort (..), SortDirection (..), TimestampType (..))
import Notion.V1.ListOf (ListOf (..), RequestStatus (..), RequestStatusType (..))
import Prelude hiding (filter)

-- | Filters the helpers can combine with their @created_time@ bound.
--
-- A top-level 'Or' is deliberately not representable: adding the bound would need a third
-- nesting level, and Notion allows only two.
data AllRowsFilter
  = AllRowsPropertyFilter Text PropertyCondition
  | AllRowsTimestampFilter TimestampType DateCondition
  | AllRowsAnd [Filter]
  deriving stock (Eq, Show)

data DataSourceRowsError
  = -- | The limit was reached but the window could not advance past this @created_time@:
    -- more rows share one timestamp than a single query can return, or no row carried one.
    CannotMakeProgress (Maybe POSIXTime)
  deriving stock (Show)

instance Exception DataSourceRowsError

-- | Combine the caller filter with @created_time on_or_after windowStart@.
createdTimeLowerBound :: Maybe AllRowsFilter -> Maybe POSIXTime -> Maybe Filter
createdTimeLowerBound mFilter Nothing = toFilter <$> mFilter
createdTimeLowerBound mFilter (Just start) =
  Just $ case mFilter of
    Nothing -> bound
    Just (AllRowsAnd xs) -> And (xs <> [bound])
    Just other -> And [toFilter other, bound]
  where
    bound = TimestampFilter FilterCreatedTime (DateOnOrAfter (posixToISO8601 start))

toFilter :: AllRowsFilter -> Filter
toFilter = \case
  AllRowsPropertyFilter p c -> PropertyFilter p c
  AllRowsTimestampFilter t c -> TimestampFilter t c
  AllRowsAnd xs -> And xs

isIncomplete :: ListOf a -> Bool
isIncomplete List {requestStatus = Just RequestStatus {type_ = RequestIncomplete}} = True
isIncomplete _ = False

-- | Fold over every row of a data source, each row visited once.
foldAllDataSourceRows ::
  -- | The query, e.g. @queryDataSource methods dsId@.
  (QueryDataSource -> IO (ListOf PageOrDataSource)) ->
  -- | Base request; its @filter@, @sorts@ and @startCursor@ are overwritten.
  QueryDataSource ->
  Maybe AllRowsFilter ->
  acc ->
  (acc -> PageOrDataSource -> IO acc) ->
  IO acc
foldAllDataSourceRows query base mFilter acc0 step = go Set.empty Nothing acc0
  where
    go seen windowStart acc = do
      (seen', acc', limitReached, lastCreated) <- window seen windowStart acc
      if not limitReached
        then pure acc'
        else
          if lastCreated == Nothing || lastCreated == windowStart
            then throwIO (CannotMakeProgress lastCreated)
            else go seen' lastCreated acc'

    window seen windowStart acc = page seen acc False Nothing Nothing
      where
        page seen1 acc1 limit1 last1 cursor = do
          response <-
            query
              base
                { filter = createdTimeLowerBound mFilter windowStart,
                  sorts = Just [TimestampSort FilterCreatedTime Ascending],
                  startCursor = cursor
                }
          (seen2, acc2, last2) <- foldM visit (seen1, acc1, last1) (results response)
          let limit2 = limit1 || isIncomplete response
          case nextCursor response of
            Just c -> page seen2 acc2 limit2 last2 (Just c)
            Nothing -> pure (seen2, acc2, limit2, last2)

    visit (seen, acc, lastCreated) row = do
      let lastCreated' = maybe lastCreated Just (resultCreatedTime row)
      case resultId row of
        Just rid
          | Set.member rid seen -> pure (seen, acc, lastCreated')
          | otherwise -> do
              acc' <- step acc row
              pure (Set.insert rid seen, acc', lastCreated')
        Nothing -> do
          acc' <- step acc row
          pure (seen, acc', lastCreated')

-- | Run an action on every row of a data source, each row visited once.
iterateAllDataSourceRows ::
  (QueryDataSource -> IO (ListOf PageOrDataSource)) ->
  QueryDataSource ->
  Maybe AllRowsFilter ->
  (PageOrDataSource -> IO ()) ->
  IO ()
iterateAllDataSourceRows query base mFilter visit = foldAllDataSourceRows query base mFilter () (const visit)

-- | Collect every row into memory. Check that the data source fits in memory first.
collectAllDataSourceRows ::
  (QueryDataSource -> IO (ListOf PageOrDataSource)) ->
  QueryDataSource ->
  Maybe AllRowsFilter ->
  IO (Vector PageOrDataSource)
collectAllDataSourceRows query base mFilter =
  Vector.fromList . reverse <$> foldAllDataSourceRows query base mFilter [] (\acc r -> pure (r : acc))
