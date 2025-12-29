-- | Pagination utilities for Notion API
module Notion.V1.Pagination
  ( -- * Pagination types
    PaginationParams (..),
    defaultPaginationParams,
  )
where

import Notion.Prelude

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
