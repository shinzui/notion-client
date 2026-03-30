-- | Error handling for Notion API
module Notion.V1.Error
  ( -- * Error types
    NotionError (..),
    parseNotionError,
  )
where

import Control.Exception (Exception)
import Data.Aeson qualified as Aeson
import Notion.Prelude
import Servant.Client qualified as Client

-- | Notion API error response
data NotionError = NotionError
  { object :: Text,
    status :: Natural,
    code :: Text,
    message :: Text,
    details :: Maybe Value
  }
  deriving stock (Generic, Show)

instance Exception NotionError

instance FromJSON NotionError where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON NotionError where
  toJSON = genericToJSON aesonOptions

-- | Try to parse a 'NotionError' from a Servant 'Client.ClientError'.
--
-- Returns 'Just' if the error is a 'Client.FailureResponse' with a JSON body
-- that can be decoded as a 'NotionError'. Returns 'Nothing' for network errors,
-- non-JSON responses, or responses that don't match the Notion error format.
parseNotionError :: Client.ClientError -> Maybe NotionError
parseNotionError = \case
  Client.FailureResponse _req resp ->
    Aeson.decode (Client.responseBody resp)
  _ -> Nothing
