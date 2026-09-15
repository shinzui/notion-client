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

    -- * Event data
    WebhookEventData (..),
    WebhookParent (..),
    WebhookParentType (..),
    WebhookBlockRef (..),
    WebhookRefType (..),
    UpdatedPropertySchema (..),
    PropertyAction (..),
    ViewField (..),
    parseEventData,

    -- * Verification
    VerificationPayload (..),
    verifySignature,
    computeSignature,
  )
where

import Control.Applicative ((<|>))
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson (object, withObject, withText, (.!=), (.:), (.:?), (.=))
import Data.Aeson.Types (Parser)
import Data.Bits (xor, (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as Base16
import Data.Char (isHexDigit)
import Data.Text qualified as T
import Data.Text.Encoding qualified as Text
import Notion.Prelude hiding (ByteString)
import Notion.V1.Common (UUID (..))
import Notion.V1.FileUploads (FileImportResult)

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
  | -- | View events (new in 2026-03-19)
    ViewCreated
  | ViewUpdated
  | ViewDeleted
  | -- | File upload events
    FileUploadCreated
  | FileUploadCompleted
  | FileUploadExpired
  | FileUploadUploadFailed
  | -- | A meeting transcript was deleted
    PageTranscriptBlockTranscriptDeleted
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
    String "view.created" -> pure ViewCreated
    String "view.updated" -> pure ViewUpdated
    String "view.deleted" -> pure ViewDeleted
    String "file_upload.created" -> pure FileUploadCreated
    String "file_upload.completed" -> pure FileUploadCompleted
    String "file_upload.expired" -> pure FileUploadExpired
    String "file_upload.upload_failed" -> pure FileUploadUploadFailed
    String "page.transcription_block.transcript_deleted" -> pure PageTranscriptBlockTranscriptDeleted
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
    ViewCreated -> String "view.created"
    ViewUpdated -> String "view.updated"
    ViewDeleted -> String "view.deleted"
    FileUploadCreated -> String "file_upload.created"
    FileUploadCompleted -> String "file_upload.completed"
    FileUploadExpired -> String "file_upload.expired"
    FileUploadUploadFailed -> String "file_upload.upload_failed"
    PageTranscriptBlockTranscriptDeleted -> String "page.transcription_block.transcript_deleted"
    UnknownEvent t -> String t

-- | Entity types in webhook events
data EntityType
  = PageEntity
  | DatabaseEntity
  | DataSourceEntity
  | CommentEntity
  | ViewEntity
  | FileUploadEntity
  | -- | A linked database block (database events)
    BlockEntity
  | UnknownEntityType Text
  deriving stock (Eq, Show, Generic)

instance FromJSON EntityType where
  parseJSON = \case
    String "page" -> pure PageEntity
    String "database" -> pure DatabaseEntity
    String "data_source" -> pure DataSourceEntity
    String "comment" -> pure CommentEntity
    String "view" -> pure ViewEntity
    String "file_upload" -> pure FileUploadEntity
    String "block" -> pure BlockEntity
    String other -> pure $ UnknownEntityType other
    _ -> fail "Expected string for EntityType"

instance ToJSON EntityType where
  toJSON = \case
    PageEntity -> String "page"
    DatabaseEntity -> String "database"
    DataSourceEntity -> String "data_source"
    CommentEntity -> String "comment"
    ViewEntity -> String "view"
    FileUploadEntity -> String "file_upload"
    BlockEntity -> String "block"
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
    workspaceId :: UUID,
    -- | Name of that workspace
    workspaceName :: Maybe Text,
    -- | Associated webhook subscription
    subscriptionId :: UUID,
    -- | Integration that owns the subscription
    integrationId :: UUID,
    -- | Type of event
    type_ :: EventType,
    -- | Users/bots who triggered the action
    authors :: Vector Author,
    -- | Users/bots with access to the entity
    accessibleBy :: Vector AccessibleBy,
    -- | Delivery attempt number (1-8)
    attemptNumber :: Int,
    -- | Entity that triggered the event
    entity :: WebhookEntity,
    -- | Event-specific data, typed by event family
    data_ :: Maybe WebhookEventData,
    -- | API version the subscription uses, for example @2026-03-11@
    apiVersion :: Maybe Text
  }
  deriving stock (Show, Generic)

instance FromJSON WebhookEvent where
  parseJSON = \case
    Object o -> do
      id <- o .: "id"
      timestampText <- o .: "timestamp"
      timestamp <- parseISO8601 timestampText
      workspaceId <- o .: "workspace_id"
      workspaceName <- o .:? "workspace_name"
      subscriptionId <- o .: "subscription_id"
      integrationId <- o .: "integration_id"
      type_ <- o .: "type"
      authors <- o .: "authors"
      -- Only present for public integrations
      accessibleBy <- o .:? "accessible_by" .!= mempty
      attemptNumber <- o .: "attempt_number"
      entity <- o .: "entity"
      mRaw <- o .:? "data"
      data_ <- traverse (parseEventData type_) mRaw
      apiVersion <- o .:? "api_version"
      pure WebhookEvent {..}
    _ -> fail "Expected object for WebhookEvent"

instance ToJSON WebhookEvent where
  toJSON = genericToJSON aesonOptions

-- | Kind of an event entity's parent
data WebhookParentType
  = WebhookParentSpace
  | WebhookParentBlock
  | WebhookParentPage
  | WebhookParentDatabase
  | WebhookParentTeam
  | WebhookParentAgent
  | UnknownWebhookParentType Text
  deriving stock (Eq, Show, Generic)

instance FromJSON WebhookParentType where
  parseJSON = withText "WebhookParentType" $ \case
    "space" -> pure WebhookParentSpace
    "block" -> pure WebhookParentBlock
    "page" -> pure WebhookParentPage
    "database" -> pure WebhookParentDatabase
    "team" -> pure WebhookParentTeam
    "agent" -> pure WebhookParentAgent
    other -> pure (UnknownWebhookParentType other)

instance ToJSON WebhookParentType where
  toJSON = \case
    WebhookParentSpace -> String "space"
    WebhookParentBlock -> String "block"
    WebhookParentPage -> String "page"
    WebhookParentDatabase -> String "database"
    WebhookParentTeam -> String "team"
    WebhookParentAgent -> String "agent"
    UnknownWebhookParentType t -> String t

-- | The parent of the entity an event is about.
data WebhookParent = WebhookParent
  { id :: UUID,
    type_ :: WebhookParentType,
    dataSourceId :: Maybe UUID
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON WebhookParent where
  parseJSON = withObject "WebhookParent" $ \o ->
    WebhookParent <$> o .: "id" <*> o .: "type" <*> o .:? "data_source_id"

instance ToJSON WebhookParent where
  toJSON (WebhookParent pid ptype dsId) =
    object (["id" .= pid, "type" .= ptype] <> maybe [] (\d -> ["data_source_id" .= d]) dsId)

-- | Kind of a page, database or block referenced by an event
data WebhookRefType
  = WebhookRefPage
  | WebhookRefDatabase
  | WebhookRefBlock
  | UnknownWebhookRefType Text
  deriving stock (Eq, Show, Generic)

instance FromJSON WebhookRefType where
  parseJSON = withText "WebhookRefType" $ \case
    "page" -> pure WebhookRefPage
    "database" -> pure WebhookRefDatabase
    "block" -> pure WebhookRefBlock
    other -> pure (UnknownWebhookRefType other)

instance ToJSON WebhookRefType where
  toJSON = \case
    WebhookRefPage -> String "page"
    WebhookRefDatabase -> String "database"
    WebhookRefBlock -> String "block"
    UnknownWebhookRefType t -> String t

-- | A page, database, or block referenced by an event (updated blocks,
-- comment parents, transcript targets).
data WebhookBlockRef = WebhookBlockRef
  { id :: UUID,
    type_ :: WebhookRefType
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON WebhookBlockRef where
  parseJSON = withObject "WebhookBlockRef" $ \o ->
    WebhookBlockRef <$> o .: "id" <*> o .: "type"

instance ToJSON WebhookBlockRef where
  toJSON (WebhookBlockRef rid rtype) = object ["id" .= rid, "type" .= rtype]

-- | What happened to a property in a schema update
data PropertyAction
  = PropertyCreated
  | PropertyUpdated
  | PropertyDeleted
  | UnknownPropertyAction Text
  deriving stock (Eq, Show, Generic)

instance FromJSON PropertyAction where
  parseJSON = withText "PropertyAction" $ \case
    "created" -> pure PropertyCreated
    "updated" -> pure PropertyUpdated
    "deleted" -> pure PropertyDeleted
    other -> pure (UnknownPropertyAction other)

instance ToJSON PropertyAction where
  toJSON = \case
    PropertyCreated -> String "created"
    PropertyUpdated -> String "updated"
    PropertyDeleted -> String "deleted"
    UnknownPropertyAction t -> String t

-- | A property changed by a database or data source schema update
data UpdatedPropertySchema = UpdatedPropertySchema
  { id :: Text,
    name :: Maybe Text,
    action :: PropertyAction
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON UpdatedPropertySchema where
  parseJSON = withObject "UpdatedPropertySchema" $ \o ->
    UpdatedPropertySchema <$> o .: "id" <*> o .:? "name" <*> o .: "action"

instance ToJSON UpdatedPropertySchema where
  toJSON (UpdatedPropertySchema pid pname act) =
    object ["id" .= pid, "name" .= pname, "action" .= act]

-- | A view setting changed by a @view.updated@ event
data ViewField
  = ViewFieldName
  | ViewFieldFilter
  | ViewFieldSorts
  | ViewFieldConfiguration
  | UnknownViewField Text
  deriving stock (Eq, Show, Generic)

instance FromJSON ViewField where
  parseJSON = withText "ViewField" $ \case
    "name" -> pure ViewFieldName
    "filter" -> pure ViewFieldFilter
    "sorts" -> pure ViewFieldSorts
    "configuration" -> pure ViewFieldConfiguration
    other -> pure (UnknownViewField other)

instance ToJSON ViewField where
  toJSON = \case
    ViewFieldName -> String "name"
    ViewFieldFilter -> String "filter"
    ViewFieldSorts -> String "sorts"
    ViewFieldConfiguration -> String "configuration"
    UnknownViewField t -> String t

-- | Event-specific data, typed by event family.
data WebhookEventData
  = -- | created / deleted / undeleted / moved / locked / unlocked, and @view.deleted@
    ParentData WebhookParent
  | -- | @*.content_updated@
    ContentUpdatedData WebhookParent (Vector WebhookBlockRef)
  | -- | @page.properties_updated@: IDs of the changed properties
    PagePropertiesUpdatedData WebhookParent (Vector Text)
  | -- | @database.schema_updated@ / @data_source.schema_updated@
    SchemaUpdatedData WebhookParent (Vector UpdatedPropertySchema)
  | -- | @view.created@: the view type (for example @table@ or @board@)
    ViewCreatedData WebhookParent Text
  | -- | @view.updated@: the settings that changed
    ViewUpdatedData WebhookParent (Vector ViewField)
  | -- | @comment.*@: the comment's parent and the containing page ID
    CommentEventData WebhookBlockRef UUID
  | -- | @file_upload.upload_failed@
    FileUploadFailedData FileImportResult
  | -- | @page.transcription_block.transcript_deleted@: the transcript block
    -- and the deleted transcript's ID
    TranscriptDeletedData WebhookBlockRef (Maybe Text)
  | -- | Any data the typed decoder does not recognize, kept verbatim.
    RawEventData Value
  deriving stock (Show, Generic)

-- | Encodes the inner @data@ object, without any tag.
instance ToJSON WebhookEventData where
  toJSON = \case
    ParentData p -> object ["parent" .= p]
    ContentUpdatedData p bs -> object ["parent" .= p, "updated_blocks" .= bs]
    PagePropertiesUpdatedData p ps -> object ["parent" .= p, "updated_properties" .= ps]
    SchemaUpdatedData p ps -> object ["parent" .= p, "updated_properties" .= ps]
    ViewCreatedData p vt -> object ["parent" .= p, "view_type" .= vt]
    ViewUpdatedData p fs -> object ["parent" .= p, "updated_fields" .= fs]
    CommentEventData p pid -> object ["parent" .= p, "page_id" .= pid]
    FileUploadFailedData r -> object ["file_import_result" .= r]
    TranscriptDeletedData t tid -> object ["target" .= t, "transcript_id" .= tid]
    RawEventData v -> v

-- | Decode an event's @data@ according to its event type. Never fails: if the
-- typed shape does not match, the raw value is returned as 'RawEventData'.
parseEventData :: EventType -> Value -> Parser WebhookEventData
parseEventData evType v = typed <|> pure (RawEventData v)
  where
    typed = case v of
      Object o ->
        let parent = o .: "parent"
         in case evType of
              _
                | evType `elem` parentOnlyEvents -> ParentData <$> parent
              PageContentUpdated -> contentUpdated o parent
              DatabaseContentUpdated -> contentUpdated o parent
              DataSourceContentUpdated -> contentUpdated o parent
              PagePropertiesUpdated -> PagePropertiesUpdatedData <$> parent <*> o .: "updated_properties"
              DatabaseSchemaUpdated -> schemaUpdated o parent
              DataSourceSchemaUpdated -> schemaUpdated o parent
              ViewCreated -> ViewCreatedData <$> parent <*> o .: "view_type"
              ViewUpdated -> ViewUpdatedData <$> parent <*> o .: "updated_fields"
              CommentCreated -> commentData o
              CommentUpdated -> commentData o
              CommentDeleted -> commentData o
              FileUploadUploadFailed -> FileUploadFailedData <$> o .: "file_import_result"
              PageTranscriptBlockTranscriptDeleted -> TranscriptDeletedData <$> o .: "target" <*> o .:? "transcript_id"
              _ -> fail "untyped event data"
      _ -> fail "event data is not an object"
    contentUpdated o parent = ContentUpdatedData <$> parent <*> o .: "updated_blocks"
    schemaUpdated o parent = SchemaUpdatedData <$> parent <*> (o .:? "updated_properties" .!= mempty)
    commentData o = CommentEventData <$> o .: "parent" <*> o .: "page_id"
    parentOnlyEvents =
      [ PageCreated,
        PageDeleted,
        PageUndeleted,
        PageMoved,
        PageLocked,
        PageUnlocked,
        DatabaseCreated,
        DatabaseDeleted,
        DatabaseUndeleted,
        DatabaseMoved,
        DataSourceCreated,
        DataSourceDeleted,
        DataSourceUndeleted,
        DataSourceMoved,
        ViewDeleted
      ]

-- | Verification payload sent by Notion when setting up a webhook
-- Your endpoint should receive this and confirm the token in the Notion UI
data VerificationPayload = VerificationPayload
  { verificationToken :: Text
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
-- Uses constant-time comparison to prevent timing attacks. The header must
-- start with @sha256=@ followed by exactly 64 hex digits; the hex digits are
-- compared case-insensitively.
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
  case T.stripPrefix "sha256=" headerSignature of
    Nothing -> False
    Just provided ->
      let providedHex = T.toLower provided
          computedHex = Base16.encode (SHA256.hmac (Text.encodeUtf8 verificationToken) body)
       in T.length providedHex == 64
            && T.all isHexDigit providedHex
            && constantTimeCompare (Text.encodeUtf8 providedHex) computedHex

-- | Constant-time comparison to prevent timing attacks
constantTimeCompare :: ByteString -> ByteString -> Bool
constantTimeCompare a b
  | BS.length a /= BS.length b = False
  | otherwise = 0 == BS.foldl' (\acc w -> acc .|. w) 0 (BS.packZipWith xor a b)
