-- | The `ListOf` type constructor for handling paginated Notion API responses
module Notion.V1.ListOf
  ( -- * Types
    ListOf (..),
    RequestStatus (..),
    RequestStatusType (..),
    IncompleteReason (..),
  )
where

import Data.Aeson ((.!=), (.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Notion.Prelude

-- | Notion API typically returns paginated results with this structure
data ListOf a = List
  { results :: Vector a,
    nextCursor :: Maybe Text,
    hasMore :: Bool,
    type_ :: Maybe Text,
    object :: Maybe Text,
    -- | Present on query and list responses that may be truncated server-side.
    requestStatus :: Maybe RequestStatus
  }
  deriving stock (Generic, Show)

instance (FromJSON a) => FromJSON (ListOf a) where
  parseJSON = \case
    Object o -> do
      results <- o .: "results"
      nextCursor <- o .:? "next_cursor"
      hasMore <- o .:? "has_more" .!= False
      type_ <- o .:? "type"
      object <- o .:? "object"
      requestStatus <- o .:? "request_status"
      return $ List {..}
    _ -> fail "Expected object for ListOf"

-- | Whether a list response contains every matching result.
data RequestStatus = RequestStatus
  { type_ :: RequestStatusType,
    incompleteReason :: Maybe IncompleteReason
  }
  deriving stock (Eq, Generic, Show)

data RequestStatusType
  = RequestComplete
  | RequestIncomplete
  | -- | A status this library does not know yet; holds the raw string.
    UnknownRequestStatusType Text
  deriving stock (Eq, Show)

data IncompleteReason
  = QueryResultLimitReached
  | -- | A reason this library does not know yet; holds the raw string.
    UnknownIncompleteReason Text
  deriving stock (Eq, Show)

instance FromJSON RequestStatus where
  parseJSON = Aeson.withObject "RequestStatus" $ \o -> do
    type_ <- o .: "type"
    incompleteReason <- o .:? "incomplete_reason"
    pure RequestStatus {..}

instance ToJSON RequestStatus where
  toJSON RequestStatus {..} =
    Aeson.object $
      ["type" .= type_] <> maybe [] (\r -> ["incomplete_reason" .= r]) incompleteReason

instance FromJSON RequestStatusType where
  parseJSON = Aeson.withText "RequestStatusType" $ \case
    "complete" -> pure RequestComplete
    "incomplete" -> pure RequestIncomplete
    other -> pure (UnknownRequestStatusType other)

instance ToJSON RequestStatusType where
  toJSON = \case
    RequestComplete -> String "complete"
    RequestIncomplete -> String "incomplete"
    UnknownRequestStatusType t -> String t

instance FromJSON IncompleteReason where
  parseJSON = Aeson.withText "IncompleteReason" $ \case
    "query_result_limit_reached" -> pure QueryResultLimitReached
    other -> pure (UnknownIncompleteReason other)

instance ToJSON IncompleteReason where
  toJSON = \case
    QueryResultLimitReached -> String "query_result_limit_reached"
    UnknownIncompleteReason t -> String t
