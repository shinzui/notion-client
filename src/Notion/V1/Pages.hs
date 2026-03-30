-- | @\/v1\/pages@
module Notion.V1.Pages
  ( -- * Main types
    PageID,
    PageObject (..),
    CreatePage (..),
    UpdatePage (..),
    PageProperties,
    mkCreatePage,
    mkUpdatePage,

    -- * Property item
    PropertyItemResponse (..),

    -- * Markdown
    PageMarkdown (..),
    UpdatePageMarkdown (..),
    UpdateContentRequest (..),
    ContentUpdate (..),
    ReplaceContentRequest (..),
    InsertContentRequest (..),
    ReplaceContentRangeRequest (..),

    -- * Move
    MovePage (..),

    -- * Templates
    Template (..),

    -- * Servant
    API,
  )
where

import Control.Applicative ((<|>))
import Data.Aeson ((.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Notion.Prelude
import Notion.V1.Blocks (Position)
import Notion.V1.Common (Cover, Icon, ObjectType (..), Parent, UUID)
import Notion.V1.ListOf (ListOf)
import Notion.V1.PropertyValue (PropertyValue)
import Notion.V1.Users (UserReference)

-- | Page ID
type PageID = UUID

-- | Notion page object
data PageObject = PageObject
  { id :: PageID,
    createdTime :: POSIXTime,
    lastEditedTime :: POSIXTime,
    createdBy :: UserReference,
    lastEditedBy :: UserReference,
    cover :: Maybe Cover,
    icon :: Maybe Icon,
    parent :: Parent,
    inTrash :: Bool,
    properties :: Map Text PropertyValue,
    url :: Text,
    publicUrl :: Maybe Text,
    object :: ObjectType
  }
  deriving stock (Generic, Show)

instance FromJSON PageObject where
  parseJSON = \case
    Object o -> do
      id <- o .: "id"
      createdTimeStr <- o .: "created_time"
      createdTime <- parseISO8601 createdTimeStr
      lastEditedTimeStr <- o .: "last_edited_time"
      lastEditedTime <- parseISO8601 lastEditedTimeStr
      createdBy <- o .: "created_by"
      lastEditedBy <- o .: "last_edited_by"
      cover <- o .:? "cover"
      icon <- o .:? "icon"
      parent <- o .: "parent"
      inTrash <- (o .: "in_trash") <|> (o .: "is_archived") <|> (o .: "archived") <|> pure False
      properties <- o .: "properties"
      url <- o .: "url"
      publicUrl <- o .:? "public_url"
      object <- o .: "object"
      return PageObject {..}
    _ -> fail "Expected object for PageObject"

instance ToJSON PageObject where
  toJSON PageObject {..} =
    Aeson.object $
      [ "id" .= id,
        "created_time" .= posixToISO8601 createdTime,
        "last_edited_time" .= posixToISO8601 lastEditedTime,
        "created_by" .= createdBy,
        "last_edited_by" .= lastEditedBy,
        "cover" .= cover,
        "icon" .= icon,
        "parent" .= parent,
        "in_trash" .= inTrash,
        "properties" .= properties,
        "url" .= url,
        "object" .= object
      ]
        <> maybe [] (\pu -> ["public_url" .= pu]) publicUrl

-- | Template configuration for page creation and updates.
--
-- When applying a template, the @children@ parameter is prohibited as
-- template processing happens asynchronously after the request completes.
data Template
  = -- | No template applied (default)
    NoTemplate
  | -- | Apply the data source's configured default template.
    -- The optional 'Text' is an IANA timezone string (e.g., "America/New_York").
    DefaultTemplate (Maybe Text)
  | -- | Apply a specific template by its page ID.
    -- The optional 'Text' is an IANA timezone string.
    TemplateById UUID (Maybe Text)
  deriving stock (Generic, Show)

instance ToJSON Template where
  toJSON NoTemplate =
    Aeson.object ["type" .= ("none" :: Text)]
  toJSON (DefaultTemplate mTz) =
    Aeson.object $
      ["type" .= ("default" :: Text)]
        <> maybe [] (\tz -> ["timezone" .= tz]) mTz
  toJSON (TemplateById templateId mTz) =
    Aeson.object $
      [ "type" .= ("template_id" :: Text),
        "template_id" .= templateId
      ]
        <> maybe [] (\tz -> ["timezone" .= tz]) mTz

-- | Create a page request
data CreatePage = CreatePage
  { parent :: Parent,
    properties :: PageProperties,
    children :: Maybe (Vector Value),
    markdown :: Maybe Text,
    icon :: Maybe Icon,
    cover :: Maybe Cover,
    template :: Maybe Template,
    position :: Maybe Position
  }
  deriving stock (Generic, Show)

instance ToJSON CreatePage where
  toJSON = genericToJSON aesonOptions

-- | Smart constructor for 'CreatePage' with required fields
mkCreatePage :: Parent -> PageProperties -> CreatePage
mkCreatePage parent properties =
  CreatePage
    { parent,
      properties,
      children = Nothing,
      markdown = Nothing,
      icon = Nothing,
      cover = Nothing,
      template = Nothing,
      position = Nothing
    }

-- | Update a page request
data UpdatePage = UpdatePage
  { properties :: PageProperties,
    inTrash :: Maybe Bool,
    icon :: Maybe Icon,
    cover :: Maybe Cover,
    template :: Maybe Template,
    eraseContent :: Maybe Bool
  }
  deriving stock (Generic, Show)

instance ToJSON UpdatePage where
  toJSON = genericToJSON aesonOptions

-- | Smart constructor for 'UpdatePage' with required fields
mkUpdatePage :: PageProperties -> UpdatePage
mkUpdatePage properties =
  UpdatePage
    { properties,
      inTrash = Nothing,
      icon = Nothing,
      cover = Nothing,
      template = Nothing,
      eraseContent = Nothing
    }

-- | Page properties map
type PageProperties = Map Text PropertyValue

-- | Response from @GET \/v1\/pages\/{page_id}\/markdown@
--
-- Contains the page content rendered as Notion-flavored enhanced markdown.
data PageMarkdown = PageMarkdown
  { id :: PageID,
    markdown :: Text,
    truncated :: Bool,
    unknownBlockIds :: Vector UUID
  }
  deriving stock (Generic, Show)

instance FromJSON PageMarkdown where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON PageMarkdown where
  toJSON = genericToJSON aesonOptions

-- | Move a page to a new parent
data MovePage = MovePage
  { parent :: Parent,
    position :: Maybe Position
  }
  deriving stock (Generic, Show)

instance ToJSON MovePage where
  toJSON = genericToJSON aesonOptions

-- | Update page markdown request
--
-- Uses the Notion markdown content API to edit page content via markdown.
-- The API accepts a discriminated union with a @type@ field.
data UpdatePageMarkdown
  = -- | Targeted search-and-replace edits (recommended)
    UpdateContent UpdateContentRequest
  | -- | Replace entire page content (recommended)
    ReplaceContent ReplaceContentRequest
  | -- | Insert content at a position (legacy)
    InsertContent InsertContentRequest
  | -- | Replace a range of content (legacy)
    ReplaceContentRange ReplaceContentRangeRequest
  deriving stock (Generic, Show)

instance ToJSON UpdatePageMarkdown where
  toJSON (UpdateContent req) =
    Aeson.object
      [ "type" .= ("update_content" :: Text),
        "update_content" .= req
      ]
  toJSON (ReplaceContent req) =
    Aeson.object
      [ "type" .= ("replace_content" :: Text),
        "replace_content" .= req
      ]
  toJSON (InsertContent req) =
    Aeson.object
      [ "type" .= ("insert_content" :: Text),
        "insert_content" .= req
      ]
  toJSON (ReplaceContentRange req) =
    Aeson.object
      [ "type" .= ("replace_content_range" :: Text),
        "replace_content_range" .= req
      ]

-- | Request body for the @update_content@ command.
-- Contains a list of search-and-replace operations (max 100).
data UpdateContentRequest = UpdateContentRequest
  { contentUpdates :: Vector ContentUpdate,
    allowDeletingContent :: Maybe Bool
  }
  deriving stock (Generic, Show)

instance ToJSON UpdateContentRequest where
  toJSON = genericToJSON aesonOptions

-- | A single search-and-replace operation
data ContentUpdate = ContentUpdate
  { oldStr :: Text,
    newStr :: Text,
    replaceAllMatches :: Maybe Bool
  }
  deriving stock (Generic, Show)

instance ToJSON ContentUpdate where
  toJSON = genericToJSON aesonOptions

-- | Request body for the @replace_content@ command.
-- Replaces the entire page content with new markdown.
data ReplaceContentRequest = ReplaceContentRequest
  { newStr :: Text,
    allowDeletingContent :: Maybe Bool
  }
  deriving stock (Generic, Show)

instance ToJSON ReplaceContentRequest where
  toJSON = genericToJSON aesonOptions

-- | Request body for the @insert_content@ command (legacy).
-- Inserts markdown content at a position specified by an ellipsis-based selector.
data InsertContentRequest = InsertContentRequest
  { content :: Text,
    after :: Maybe Text
  }
  deriving stock (Generic, Show)

instance ToJSON InsertContentRequest where
  toJSON = genericToJSON aesonOptions

-- | Request body for the @replace_content_range@ command (legacy).
-- Replaces content in a range specified by an ellipsis-based selector.
data ReplaceContentRangeRequest = ReplaceContentRangeRequest
  { content :: Text,
    contentRange :: Text,
    allowDeletingContent :: Maybe Bool
  }
  deriving stock (Generic, Show)

instance ToJSON ReplaceContentRangeRequest where
  toJSON = genericToJSON aesonOptions

-- | Response from the page property item endpoint.
--
-- The Notion API returns either a single property value (for most property types)
-- or a paginated list of items (for title, rich_text, relation, and people properties
-- that can have many items).
data PropertyItemResponse
  = -- | A single property value
    SinglePropertyItem PropertyValue
  | -- | A paginated list of property items. The 'Text' is the property type name.
    PaginatedPropertyItems (ListOf PropertyValue) Text
  deriving stock (Show)

instance FromJSON PropertyItemResponse where
  parseJSON = \case
    Object o -> do
      -- Check if this is a paginated response (has "results" key) or single item
      if KeyMap.member "results" o
        then do
          listOf <- Aeson.parseJSON (Object o)
          propType <- o .: "property_item" >>= (.: "type")
          pure $ PaginatedPropertyItems listOf propType
        else SinglePropertyItem <$> Aeson.parseJSON (Object o)
    _ -> fail "Expected object for PropertyItemResponse"

-- | Servant API
type API =
  "pages"
    :> ( Capture "page_id" PageID
           :> Get '[JSON] PageObject
           :<|> ReqBody '[JSON] CreatePage
           :> Post '[JSON] PageObject
           :<|> Capture "page_id" PageID
           :> ReqBody '[JSON] UpdatePage
           :> Patch '[JSON] PageObject
           :<|> Capture "page_id" PageID
           :> "properties"
           :> Capture "property_id" Text
           :> QueryParam "start_cursor" Text
           :> QueryParam "page_size" Natural
           :> Get '[JSON] PropertyItemResponse
           :<|> Capture "page_id" PageID
           :> "markdown"
           :> QueryParam "include_transcript" Bool
           :> Get '[JSON] PageMarkdown
           :<|> Capture "page_id" PageID
           :> "markdown"
           :> ReqBody '[JSON] UpdatePageMarkdown
           :> Patch '[JSON] PageMarkdown
           :<|> Capture "page_id" PageID
           :> "move"
           :> ReqBody '[JSON] MovePage
           :> Post '[JSON] PageObject
       )
