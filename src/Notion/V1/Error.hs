-- | Error handling for Notion API
module Notion.V1.Error
  ( -- * Error types
    NotionError (..),
  )
where

import Notion.Prelude

-- | Notion API error response
data NotionError = NotionError
  { object :: Text,
    status :: Natural,
    code :: Text,
    message :: Text,
    details :: Maybe Value
  }
  deriving stock (Generic, Show)

instance FromJSON NotionError where
  parseJSON = genericParseJSON aesonOptions
