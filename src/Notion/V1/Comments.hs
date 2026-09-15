-- | @\/v1\/comments@
module Notion.V1.Comments
  ( -- * Main types
    CommentID,
    CommentObject (..),
    CommentAttachment (..),
    CommentDisplayName (..),
    CommentResponse (..),
    commentResponseId,
    commentResponseObject,

    -- * Requests
    CreateComment (..),
    CommentTarget (..),
    CommentContent (..),
    CommentAttachmentRequest (..),
    CommentDisplayNameRequest (..),
    mkCreateComment,
    mkReplyComment,

    -- * Servant
    API,
  )
where

import Data.Aeson ((.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Pair)
import Data.Maybe (catMaybes)
import Notion.Prelude
import Notion.V1.Common (BlockID, ExternalFile, File, ObjectType (..), Parent, UUID)
import Notion.V1.ListOf (ListOf)
import Notion.V1.RichText (RichText)
import Notion.V1.Users (UserReference)
import Prelude hiding (id)

-- | Comment ID
type CommentID = UUID

-- | Comment attachment (files attached to comments), as read from responses.
--
-- Read responses (@GET \/v1\/comments@) contain @category@ + @file@; an
-- older @name@ + @type@ + @external@\/@file@ shape is also accepted. To attach
-- files to a new comment use 'CommentAttachmentRequest'.
data CommentAttachment = CommentAttachment
  { name :: Maybe Text,
    type_ :: Maybe Text,
    category :: Maybe Text,
    external :: Maybe ExternalFile,
    file :: Maybe File
  }
  deriving stock (Generic, Show)

instance FromJSON CommentAttachment where
  parseJSON = Aeson.withObject "CommentAttachment" $ \o ->
    CommentAttachment
      <$> o .:? "name"
      <*> o .:? "type"
      <*> o .:? "category"
      <*> o .:? "external"
      <*> o .:? "file"

instance ToJSON CommentAttachment where
  toJSON CommentAttachment {..} =
    Aeson.object $
      catMaybes
        [ ("name" .=) <$> name,
          ("type" .=) <$> type_,
          ("category" .=) <$> category,
          ("external" .=) <$> external,
          ("file" .=) <$> file
        ]

-- | Comment display name, as read from responses.
--
-- Read responses include @resolved_name@ (the rendered author label). To
-- choose the display name of a new comment use 'CommentDisplayNameRequest'.
data CommentDisplayName = CommentDisplayName
  { type_ :: Text,
    emoji :: Maybe Text,
    displayName :: Maybe Text,
    resolvedName :: Maybe Text
  }
  deriving stock (Generic, Show)

instance FromJSON CommentDisplayName where
  parseJSON = Aeson.withObject "CommentDisplayName" $ \o ->
    CommentDisplayName
      <$> o .: "type"
      <*> o .:? "emoji"
      <*> o .:? "display_name"
      <*> o .:? "resolved_name"

instance ToJSON CommentDisplayName where
  toJSON CommentDisplayName {..} =
    Aeson.object $
      ("type" .= type_)
        : catMaybes
          [ ("emoji" .=) <$> emoji,
            ("display_name" .=) <$> displayName,
            ("resolved_name" .=) <$> resolvedName
          ]

-- | Notion comment object
data CommentObject = CommentObject
  { id :: CommentID,
    parent :: Parent,
    discussionId :: UUID,
    createdTime :: POSIXTime,
    lastEditedTime :: POSIXTime,
    createdBy :: UserReference,
    richText :: Vector RichText,
    attachments :: Maybe (Vector CommentAttachment),
    displayName :: Maybe CommentDisplayName,
    object :: ObjectType
  }
  deriving stock (Generic, Show)

instance FromJSON CommentObject where
  parseJSON = \case
    Object o -> do
      id <- o .: "id"
      parent <- o .: "parent"
      discussionId <- o .: "discussion_id"
      createdTimeStr <- o .: "created_time"
      createdTime <- parseISO8601 createdTimeStr
      lastEditedTimeStr <- o .: "last_edited_time"
      lastEditedTime <- parseISO8601 lastEditedTimeStr
      createdBy <- o .: "created_by"
      richText <- o .: "rich_text"
      attachments <- o .:? "attachments"
      displayName <- o .:? "display_name"
      object <- o .: "object"
      return CommentObject {..}
    _ -> fail "Expected object for CommentObject"

-- | A comment endpoint response: Notion may return the full comment or only
-- its id.
data CommentResponse
  = FullComment CommentObject
  | PartialComment CommentID
  deriving stock (Generic, Show)

-- | A response is full when it carries @parent@; a full response with other
-- required fields missing fails to decode rather than becoming partial.
instance FromJSON CommentResponse where
  parseJSON = Aeson.withObject "CommentResponse" $ \o ->
    if KeyMap.member "parent" o
      then FullComment <$> parseJSON (Object o)
      else PartialComment <$> o .: "id"

-- | The id carried by either response shape.
commentResponseId :: CommentResponse -> CommentID
commentResponseId = \case
  FullComment CommentObject {id} -> id
  PartialComment cid -> cid

-- | The full comment, if Notion returned one.
commentResponseObject :: CommentResponse -> Maybe CommentObject
commentResponseObject = \case
  FullComment c -> Just c
  PartialComment _ -> Nothing

-- | Where a new comment goes.
data CommentTarget
  = -- | Start a new discussion on a page ('Notion.V1.Common.PageParent') or
    -- block ('Notion.V1.Common.BlockParent'). Notion rejects other parents.
    CommentOnParent Parent
  | -- | Reply in an existing discussion.
    CommentInDiscussion UUID
  deriving stock (Generic, Show)

-- | The body of a comment: rich text or inline Markdown.
--
-- Also the request body of @PATCH \/v1\/comments\/{comment_id}@.
data CommentContent
  = CommentRichText (Vector RichText)
  | -- | Inline formatting, equations and mentions only; block-level Markdown
    -- does not become blocks.
    CommentMarkdown Text
  deriving stock (Generic, Show)

instance ToJSON CommentContent where
  toJSON c = Aeson.object [commentContentPair c]

commentContentPair :: CommentContent -> Pair
commentContentPair = \case
  CommentRichText rt -> "rich_text" .= rt
  CommentMarkdown md -> "markdown" .= md

-- | Attach a completed file upload to a new comment. Encodes as
-- @{"file_upload_id": "...", "type": "file_upload"}@.
newtype CommentAttachmentRequest = CommentAttachmentRequest {fileUploadId :: UUID}
  deriving stock (Generic, Show)

instance ToJSON CommentAttachmentRequest where
  toJSON CommentAttachmentRequest {fileUploadId} =
    Aeson.object ["file_upload_id" .= fileUploadId, "type" .= ("file_upload" :: Text)]

-- | How the author of a new comment is displayed.
data CommentDisplayNameRequest
  = -- | @{"type":"integration"}@
    DisplayAsIntegration
  | -- | @{"type":"user"}@
    DisplayAsUser
  | -- | @{"type":"custom","custom":{"name":...}}@
    DisplayAsCustom Text
  deriving stock (Generic, Show)

instance ToJSON CommentDisplayNameRequest where
  toJSON = \case
    DisplayAsIntegration -> Aeson.object ["type" .= ("integration" :: Text)]
    DisplayAsUser -> Aeson.object ["type" .= ("user" :: Text)]
    DisplayAsCustom n ->
      Aeson.object
        [ "type" .= ("custom" :: Text),
          "custom" .= Aeson.object ["name" .= n]
        ]

-- | Create comment request
data CreateComment = CreateComment
  { target :: CommentTarget,
    content :: CommentContent,
    -- | At most three attachments.
    attachments :: Maybe (Vector CommentAttachmentRequest),
    displayName :: Maybe CommentDisplayNameRequest
  }
  deriving stock (Generic, Show)

instance ToJSON CreateComment where
  toJSON CreateComment {..} =
    Aeson.object $
      [ case target of
          CommentOnParent p -> "parent" .= p
          CommentInDiscussion d -> "discussion_id" .= d,
        commentContentPair content
      ]
        <> catMaybes
          [ ("attachments" .=) <$> attachments,
            ("display_name" .=) <$> displayName
          ]

-- | Start a new discussion on a page or block.
mkCreateComment :: Parent -> CommentContent -> CreateComment
mkCreateComment p c = CreateComment (CommentOnParent p) c Nothing Nothing

-- | Reply in an existing discussion.
mkReplyComment :: UUID -> CommentContent -> CreateComment
mkReplyComment d c = CreateComment (CommentInDiscussion d) c Nothing Nothing

-- | Servant API
-- Note: To list comments on a page, use the page ID as block_id (pages are blocks in Notion)
type API =
  "comments"
    :> ( ReqBody '[JSON] CreateComment
           :> Post '[JSON] CommentResponse
           :<|> QueryParam "block_id" BlockID
           :> QueryParam "start_cursor" Text
           :> QueryParam "page_size" Natural
           :> Get '[JSON] (ListOf CommentObject)
           :<|> Capture "comment_id" CommentID
           :> Get '[JSON] CommentResponse
           :<|> Capture "comment_id" CommentID
           :> ReqBody '[JSON] CommentContent
           :> Patch '[JSON] CommentResponse
           :<|> Capture "comment_id" CommentID
           :> Delete '[JSON] CommentResponse
       )
