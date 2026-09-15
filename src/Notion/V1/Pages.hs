-- | @\/v1\/pages@
module Notion.V1.Pages
  ( -- * Main types
    PageID,
    PageObject (..),
    PartialPageObject (..),
    CreatePage (..),
    PagePosition (..),
    UpdatePage (..),
    UpdatePageTemplate (..),
    PageProperties,
    mkCreatePage,
    mkUpdatePage,

    -- * Property item
    PropertyItemResponse (..),
    PropertyItemList (..),

    -- * Markdown
    PageMarkdown (..),
    UpdatePageMarkdown (..),
    UpdateContentRequest (..),
    ContentUpdate (..),
    ReplaceContentRequest (..),
    InsertContentRequest (..),
    InsertPosition (..),
    ReplaceContentRangeRequest (..),

    -- * Move
    MovePage (..),
    MovePageParent (..),

    -- * Templates
    Template (..),

    -- * Servant
    API,
  )
where

import Control.Applicative ((<|>))
import Data.Aeson ((.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key (Key)
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Pair)
import Data.Map qualified as Map
import Data.Maybe (fromMaybe)
import Notion.Prelude
import Notion.V1.AsyncTasks (AllowAsync, AsyncVerb)
import Notion.V1.BlockContent (BlockContent)
import Notion.V1.Clearable (Clearable (..))
import Notion.V1.Common (Cover, Icon, ObjectType (..), Parent, UUID)
import Notion.V1.ListOf (ListOf)
import Notion.V1.PropertyValue (PropertyValue, RollupResult)
import Notion.V1.Users (UserReference)
import Servant.API (QueryParams, StdMethod (PATCH, POST))

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
    isLocked :: Maybe Bool,
    isArchived :: Maybe Bool,
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
      isLocked <- o .:? "is_locked"
      isArchived <- o .:? "is_archived"
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
        <> maybe [] (\v -> ["is_locked" .= v]) isLocked
        <> maybe [] (\v -> ["is_archived" .= v]) isArchived
        <> maybe [] (\pu -> ["public_url" .= pu]) publicUrl

-- | @{"object":"page","id":...}@
--
-- A reference to a page returned where Notion sends only the ID, for example
-- view query results.
newtype PartialPageObject = PartialPageObject {id :: PageID}
  deriving stock (Generic, Show)

instance FromJSON PartialPageObject where
  parseJSON = \case
    Object o -> PartialPageObject <$> o .: "id"
    _ -> fail "Expected object for PartialPageObject"

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

-- | Where to place a new page among its parent's content (@POST /v1/pages@).
-- Distinct from 'InsertPosition' and 'Notion.V1.Blocks.Position', which use @start@/@end@.
data PagePosition
  = PageAfterBlock UUID
  | PageStart
  | PageEnd
  deriving stock (Eq, Generic, Show)

instance ToJSON PagePosition where
  toJSON (PageAfterBlock blockId) =
    Aeson.object ["type" .= ("after_block" :: Text), "after_block" .= Aeson.object ["id" .= blockId]]
  toJSON PageStart = Aeson.object ["type" .= ("page_start" :: Text)]
  toJSON PageEnd = Aeson.object ["type" .= ("page_end" :: Text)]

-- | Template choice when updating a page. Unlike 'Template', there is no
-- "none" option: the API rejects @{"type":"none"}@ on update.
data UpdatePageTemplate
  = -- | Apply the data source's default template; optional IANA timezone.
    UpdateDefaultTemplate (Maybe Text)
  | -- | Apply a specific template page; optional IANA timezone.
    UpdateTemplateById UUID (Maybe Text)
  deriving stock (Eq, Generic, Show)

instance ToJSON UpdatePageTemplate where
  toJSON (UpdateDefaultTemplate mTz) =
    Aeson.object (["type" .= ("default" :: Text)] <> maybe [] (\tz -> ["timezone" .= tz]) mTz)
  toJSON (UpdateTemplateById tid mTz) =
    Aeson.object
      ( ["type" .= ("template_id" :: Text), "template_id" .= tid]
          <> maybe [] (\tz -> ["timezone" .= tz]) mTz
      )

-- | Create a page request.
--
-- Every field is optional on the wire. Without a 'parent' the page is created
-- as a private workspace page. 'properties' is omitted when the map is empty.
data CreatePage = CreatePage
  { parent :: Maybe Parent,
    properties :: PageProperties,
    children :: Maybe (Vector BlockContent),
    markdown :: Maybe Text,
    icon :: Maybe Icon,
    cover :: Maybe Cover,
    template :: Maybe Template,
    position :: Maybe PagePosition
  }
  deriving stock (Generic, Show)

instance ToJSON CreatePage where
  toJSON CreatePage {..} =
    Aeson.object $
      optionalPair "parent" parent
        <> propertiesPair properties
        <> optionalPair "children" children
        <> optionalPair "markdown" markdown
        <> optionalPair "icon" icon
        <> optionalPair "cover" cover
        <> optionalPair "template" template
        <> optionalPair "position" position

-- | Smart constructor for 'CreatePage' with required fields
mkCreatePage :: Parent -> PageProperties -> CreatePage
mkCreatePage parent properties =
  CreatePage
    { parent = Just parent,
      properties,
      children = Nothing,
      markdown = Nothing,
      icon = Nothing,
      cover = Nothing,
      template = Nothing,
      position = Nothing
    }

-- | Update a page request.
--
-- 'properties' is omitted when the map is empty. 'icon' and 'cover' can be
-- removed from the page with 'Clear'.
data UpdatePage = UpdatePage
  { properties :: PageProperties,
    inTrash :: Maybe Bool,
    isLocked :: Maybe Bool,
    isArchived :: Maybe Bool,
    icon :: Clearable Icon,
    cover :: Clearable Cover,
    template :: Maybe UpdatePageTemplate,
    eraseContent :: Maybe Bool
  }
  deriving stock (Generic, Show)

instance ToJSON UpdatePage where
  toJSON UpdatePage {..} =
    Aeson.object $
      propertiesPair properties
        <> optionalPair "in_trash" inTrash
        <> optionalPair "is_locked" isLocked
        <> optionalPair "is_archived" isArchived
        <> clearablePair "icon" icon
        <> clearablePair "cover" cover
        <> optionalPair "template" template
        <> optionalPair "erase_content" eraseContent

-- | Smart constructor for 'UpdatePage' with required fields
mkUpdatePage :: PageProperties -> UpdatePage
mkUpdatePage properties =
  UpdatePage
    { properties,
      inTrash = Nothing,
      isLocked = Nothing,
      isArchived = Nothing,
      icon = Unset,
      cover = Unset,
      template = Nothing,
      eraseContent = Nothing
    }

optionalPair :: (ToJSON a) => Key -> Maybe a -> [Pair]
optionalPair k = maybe [] (\v -> [k .= v])

clearablePair :: (ToJSON a) => Key -> Clearable a -> [Pair]
clearablePair k = \case
  Unset -> []
  Clear -> [k .= Aeson.Null]
  Set v -> [k .= v]

propertiesPair :: PageProperties -> [Pair]
propertiesPair ps
  | Map.null ps = []
  | otherwise = ["properties" .= ps]

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

-- | Destination of a page move. Only pages and data sources are valid targets.
data MovePageParent
  = MoveToPage UUID
  | MoveToDataSource UUID
  deriving stock (Eq, Generic, Show)

instance ToJSON MovePageParent where
  toJSON (MoveToPage pid) = Aeson.object ["type" .= ("page_id" :: Text), "page_id" .= pid]
  toJSON (MoveToDataSource dsid) =
    Aeson.object ["type" .= ("data_source_id" :: Text), "data_source_id" .= dsid]

-- | Move a page to a new parent
newtype MovePage = MovePage {parent :: MovePageParent}
  deriving stock (Generic, Show)

instance ToJSON MovePage where
  toJSON (MovePage p) = Aeson.object ["parent" .= p]

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
    after :: Maybe Text,
    -- | Insert at the start or end of the page. Cannot be combined with 'after'.
    position :: Maybe InsertPosition
  }
  deriving stock (Generic, Show)

instance ToJSON InsertContentRequest where
  toJSON = genericToJSON aesonOptions

-- | Where @insert_content@ places new markdown.
data InsertPosition = InsertAtStart | InsertAtEnd
  deriving stock (Eq, Generic, Show)

instance ToJSON InsertPosition where
  toJSON InsertAtStart = Aeson.object ["type" .= ("start" :: Text)]
  toJSON InsertAtEnd = Aeson.object ["type" .= ("end" :: Text)]

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
  | -- | A paginated list of property items
    PaginatedPropertyItems PropertyItemList
  deriving stock (Show)

-- | A paginated property item response (title, rich_text, people, relation,
-- rollup). 'nextUrl' is the URL of the next page of items, if any; 'rollup'
-- is the rollup summary Notion attaches to paginated rollup properties.
data PropertyItemList = PropertyItemList
  { items :: ListOf PropertyValue,
    propertyType :: Text,
    propertyId :: Text,
    nextUrl :: Maybe Text,
    rollup :: Maybe RollupResult
  }
  deriving stock (Show)

instance FromJSON PropertyItemResponse where
  parseJSON = \case
    Object o -> do
      -- Check if this is a paginated response (has "results" key) or single item
      if KeyMap.member "results" o
        then do
          items <- Aeson.parseJSON (Object o)
          propertyItem <- o .: "property_item"
          propertyType <- propertyItem .: "type"
          propertyId <- fromMaybe "" <$> propertyItem .:? "id"
          nextUrl <- propertyItem .:? "next_url"
          rollup <- propertyItem .:? "rollup"
          pure $ PaginatedPropertyItems PropertyItemList {..}
        else SinglePropertyItem <$> Aeson.parseJSON (Object o)
    _ -> fail "Expected object for PropertyItemResponse"

-- | Servant API
type API =
  "pages"
    :> ( Capture "page_id" PageID
           :> QueryParams "filter_properties" Text
           :> Get '[JSON] PageObject
           :<|> QueryParams "filter_properties" Text
           :> ReqBody '[JSON] CreatePage
           :> Post '[JSON] PageObject
           :<|> Capture "page_id" PageID
           :> QueryParams "filter_properties" Text
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
           :<|> ReqBody '[JSON] (AllowAsync CreatePage)
           :> AsyncVerb 'POST PageObject
           :<|> Capture "page_id" PageID
           :> "markdown"
           :> ReqBody '[JSON] (AllowAsync UpdatePageMarkdown)
           :> AsyncVerb 'PATCH PageMarkdown
       )
