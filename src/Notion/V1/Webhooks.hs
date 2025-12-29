-- | Notion Webhook types and utilities
--
-- This module provides types for handling incoming webhook events from Notion.
-- Webhook subscriptions are created via the Notion integration UI, not via API.
--
-- Usage:
--
-- @
-- import Notion.V1.Webhooks
-- import Data.Aeson (eitherDecode)
--
-- handleWebhook :: ByteString -> Text -> Text -> IO ()
-- handleWebhook body signature verificationToken = do
--   -- Verify the signature
--   case verifySignature verificationToken body signature of
--     False -> error "Invalid signature"
--     True -> do
--       -- Parse the event
--       case eitherDecode body of
--         Left err -> error err
--         Right event -> processEvent event
--
-- processEvent :: WebhookEvent -> IO ()
-- processEvent event = case event.type_ of
--   PageCreated -> putStrLn "Page created!"
--   CommentCreated -> putStrLn "Comment created!"
--   _ -> putStrLn "Other event"
-- @
module Notion.V1.Webhooks
  ( -- * Event types
    WebhookEvent (..),
    EventType (..),
    WebhookEntity (..),
    EntityType (..),
    Author (..),
    AccessibleBy (..),

    -- * Verification
    VerificationPayload (..),
    verifySignature,
    computeSignature,
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson (object, (.:), (.:?), (.=))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as Base16
import Data.List qualified
import Data.Text.Encoding qualified as Text
import Notion.Prelude hiding (ByteString)
import Notion.V1.Common (UUID (..))

-- | Webhook event types supported by Notion
data EventType
  = -- | Page events
    PageCreated
  | PageDeleted
  | PageUndeleted
  | PagePropertiesUpdated
  | PageContentUpdated
  | PageMoved
  | PageLocked
  | PageUnlocked
  | -- | Database events (deprecated as of 2025-09-03)
    DatabaseCreated
  | DatabaseDeleted
  | DatabaseUndeleted
  | DatabaseContentUpdated
  | DatabaseSchemaUpdated
  | DatabaseMoved
  | -- | Data source events (new in 2025-09-03)
    DataSourceCreated
  | DataSourceDeleted
  | DataSourceUndeleted
  | DataSourceContentUpdated
  | DataSourceSchemaUpdated
  | DataSourceMoved
  | -- | Comment events
    CommentCreated
  | CommentUpdated
  | CommentDeleted
  | -- | Unknown event type (for forward compatibility)
    UnknownEvent Text
  deriving stock (Eq, Show, Generic)

instance FromJSON EventType where
  parseJSON = \case
    String "page.created" -> pure PageCreated
    String "page.deleted" -> pure PageDeleted
    String "page.undeleted" -> pure PageUndeleted
    String "page.properties_updated" -> pure PagePropertiesUpdated
    String "page.content_updated" -> pure PageContentUpdated
    String "page.moved" -> pure PageMoved
    String "page.locked" -> pure PageLocked
    String "page.unlocked" -> pure PageUnlocked
    String "database.created" -> pure DatabaseCreated
    String "database.deleted" -> pure DatabaseDeleted
    String "database.undeleted" -> pure DatabaseUndeleted
    String "database.content_updated" -> pure DatabaseContentUpdated
    String "database.schema_updated" -> pure DatabaseSchemaUpdated
    String "database.moved" -> pure DatabaseMoved
    String "data_source.created" -> pure DataSourceCreated
    String "data_source.deleted" -> pure DataSourceDeleted
    String "data_source.undeleted" -> pure DataSourceUndeleted
    String "data_source.content_updated" -> pure DataSourceContentUpdated
    String "data_source.schema_updated" -> pure DataSourceSchemaUpdated
    String "data_source.moved" -> pure DataSourceMoved
    String "comment.created" -> pure CommentCreated
    String "comment.updated" -> pure CommentUpdated
    String "comment.deleted" -> pure CommentDeleted
    String other -> pure $ UnknownEvent other
    _ -> fail "Expected string for EventType"

instance ToJSON EventType where
  toJSON = \case
    PageCreated -> String "page.created"
    PageDeleted -> String "page.deleted"
    PageUndeleted -> String "page.undeleted"
    PagePropertiesUpdated -> String "page.properties_updated"
    PageContentUpdated -> String "page.content_updated"
    PageMoved -> String "page.moved"
    PageLocked -> String "page.locked"
    PageUnlocked -> String "page.unlocked"
    DatabaseCreated -> String "database.created"
    DatabaseDeleted -> String "database.deleted"
    DatabaseUndeleted -> String "database.undeleted"
    DatabaseContentUpdated -> String "database.content_updated"
    DatabaseSchemaUpdated -> String "database.schema_updated"
    DatabaseMoved -> String "database.moved"
    DataSourceCreated -> String "data_source.created"
    DataSourceDeleted -> String "data_source.deleted"
    DataSourceUndeleted -> String "data_source.undeleted"
    DataSourceContentUpdated -> String "data_source.content_updated"
    DataSourceSchemaUpdated -> String "data_source.schema_updated"
    DataSourceMoved -> String "data_source.moved"
    CommentCreated -> String "comment.created"
    CommentUpdated -> String "comment.updated"
    CommentDeleted -> String "comment.deleted"
    UnknownEvent t -> String t

-- | Entity types in webhook events
data EntityType
  = PageEntity
  | DatabaseEntity
  | DataSourceEntity
  | CommentEntity
  | UnknownEntityType Text
  deriving stock (Eq, Show, Generic)

instance FromJSON EntityType where
  parseJSON = \case
    String "page" -> pure PageEntity
    String "database" -> pure DatabaseEntity
    String "data_source" -> pure DataSourceEntity
    String "comment" -> pure CommentEntity
    String other -> pure $ UnknownEntityType other
    _ -> fail "Expected string for EntityType"

instance ToJSON EntityType where
  toJSON = \case
    PageEntity -> String "page"
    DatabaseEntity -> String "database"
    DataSourceEntity -> String "data_source"
    CommentEntity -> String "comment"
    UnknownEntityType t -> String t

-- | Entity that triggered the webhook event
data WebhookEntity = WebhookEntity
  { id :: UUID,
    type_ :: EntityType
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON WebhookEntity where
  parseJSON = \case
    Object o -> do
      id <- o .: "id"
      type_ <- o .: "type"
      pure WebhookEntity {..}
    _ -> fail "Expected object for WebhookEntity"

instance ToJSON WebhookEntity where
  toJSON WebhookEntity {..} =
    object
      [ "id" .= id,
        "type" .= type_
      ]

-- | Author who triggered the event (user or bot)
data Author = Author
  { id :: UUID,
    type_ :: Text
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON Author where
  parseJSON = \case
    Object o -> do
      id <- o .: "id"
      type_ <- o .: "type"
      pure Author {..}
    _ -> fail "Expected object for Author"

instance ToJSON Author where
  toJSON Author {..} =
    object
      [ "id" .= id,
        "type" .= type_
      ]

-- | User or bot with access to the affected entity
data AccessibleBy = AccessibleBy
  { id :: UUID,
    type_ :: Text
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON AccessibleBy where
  parseJSON = \case
    Object o -> do
      id <- o .: "id"
      type_ <- o .: "type"
      pure AccessibleBy {..}
    _ -> fail "Expected object for AccessibleBy"

instance ToJSON AccessibleBy where
  toJSON AccessibleBy {..} =
    object
      [ "id" .= id,
        "type" .= type_
      ]

-- | A webhook event sent by Notion to your endpoint
data WebhookEvent = WebhookEvent
  { -- | Unique identifier for this event
    id :: UUID,
    -- | When the event occurred (ISO 8601)
    timestamp :: POSIXTime,
    -- | Workspace where the event originated
    workspace_id :: UUID,
    -- | Associated webhook subscription
    subscription_id :: UUID,
    -- | Integration that owns the subscription
    integration_id :: UUID,
    -- | Type of event
    type_ :: EventType,
    -- | Users/bots who triggered the action
    authors :: Vector Author,
    -- | Users/bots with access to the entity
    accessible_by :: Vector AccessibleBy,
    -- | Delivery attempt number (1-8)
    attempt_number :: Int,
    -- | Entity that triggered the event
    entity :: WebhookEntity,
    -- | Event-specific data (varies by event type)
    data_ :: Maybe Value
  }
  deriving stock (Show, Generic)

instance FromJSON WebhookEvent where
  parseJSON = \case
    Object o -> do
      id <- o .: "id"
      timestampText <- o .: "timestamp"
      timestamp <- parseISO8601 timestampText
      workspace_id <- o .: "workspace_id"
      subscription_id <- o .: "subscription_id"
      integration_id <- o .: "integration_id"
      type_ <- o .: "type"
      authors <- o .: "authors"
      accessible_by <- o .: "accessible_by"
      attempt_number <- o .: "attempt_number"
      entity <- o .: "entity"
      data_ <- o .:? "data"
      pure WebhookEvent {..}
    _ -> fail "Expected object for WebhookEvent"

instance ToJSON WebhookEvent where
  toJSON = genericToJSON aesonOptions

-- | Verification payload sent by Notion when setting up a webhook
-- Your endpoint should receive this and confirm the token in the Notion UI
data VerificationPayload = VerificationPayload
  { verification_token :: Text
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON VerificationPayload where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON VerificationPayload where
  toJSON = genericToJSON aesonOptions

-- | Compute HMAC-SHA256 signature for webhook payload validation
--
-- The signature is computed as: sha256=HMAC-SHA256(verification_token, body)
computeSignature ::
  -- | Verification token (used as HMAC key)
  Text ->
  -- | Request body (minified JSON)
  ByteString ->
  -- | Computed signature in "sha256=..." format
  Text
computeSignature verificationToken body =
  "sha256=" <> Text.decodeUtf8 (Base16.encode hmacDigest)
  where
    key = Text.encodeUtf8 verificationToken
    hmacDigest = SHA256.hmac key body

-- | Verify webhook signature from X-Notion-Signature header
--
-- Uses constant-time comparison to prevent timing attacks.
--
-- Example:
--
-- @
-- isValid = verifySignature myToken requestBody headerSignature
-- @
verifySignature ::
  -- | Verification token (from webhook setup)
  Text ->
  -- | Request body (minified JSON as received)
  ByteString ->
  -- | Signature from X-Notion-Signature header
  Text ->
  -- | True if signature is valid
  Bool
verifySignature verificationToken body headerSignature =
  constantTimeCompare expected actual
  where
    expected = Text.encodeUtf8 $ computeSignature verificationToken body
    actual = Text.encodeUtf8 headerSignature

-- | Constant-time comparison to prevent timing attacks
constantTimeCompare :: ByteString -> ByteString -> Bool
constantTimeCompare a b
  | BS.length a /= BS.length b = False
  | otherwise = foldl' (\acc (x, y) -> acc && x == y) True (BS.zip a b)
  where
    foldl' = Data.List.foldl'
