-- | @\/v1\/pages@
module Notion.V1.Pages
  ( -- * Main types
    PageID,
    PageObject (..),
    CreatePage (..),
    UpdatePage (..),
    PageProperties,
    PropertyValue (..),
    PropertyItem (..),
    PropertyValueType (..),
    SelectOption (..),
    mkCreatePage,
    mkUpdatePage,

    -- * Servant
    API,
  )
where

import Data.Aeson ((.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Notion.Prelude hiding (Number)
import Notion.V1.Common (Cover, Icon, ObjectType (..), Parent, UUID)
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
    archived :: Bool,
    inTrash :: Bool,
    properties :: Map Text PropertyItem,
    url :: Text,
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
      archived <- o .: "archived"
      inTrash <- o .: "in_trash"
      properties <- o .: "properties"
      url <- o .: "url"
      object <- o .: "object"
      return PageObject {..}
    _ -> fail "Expected object for PageObject"

instance ToJSON PageObject where
  toJSON PageObject {..} =
    Aeson.object
      [ "id" .= id,
        "created_time" .= posixToISO8601 createdTime,
        "last_edited_time" .= posixToISO8601 lastEditedTime,
        "created_by" .= createdBy,
        "last_edited_by" .= lastEditedBy,
        "cover" .= cover,
        "icon" .= icon,
        "parent" .= parent,
        "archived" .= archived,
        "in_trash" .= inTrash,
        "properties" .= properties,
        "url" .= url,
        "object" .= object
      ]

-- | Create a page request
data CreatePage = CreatePage
  { parent :: Parent,
    properties :: PageProperties,
    children :: Maybe (Vector Value),
    icon :: Maybe Icon,
    cover :: Maybe Cover
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
      icon = Nothing,
      cover = Nothing
    }

-- | Update a page request
data UpdatePage = UpdatePage
  { properties :: PageProperties,
    archived :: Maybe Bool,
    icon :: Maybe Icon,
    cover :: Maybe Cover
  }
  deriving stock (Generic, Show)

instance ToJSON UpdatePage where
  toJSON = genericToJSON aesonOptions

-- | Smart constructor for 'UpdatePage' with required fields
mkUpdatePage :: PageProperties -> UpdatePage
mkUpdatePage properties =
  UpdatePage
    { properties,
      archived = Nothing,
      icon = Nothing,
      cover = Nothing
    }

-- | Page properties map
type PageProperties = Map Text PropertyValue

-- | Property value type for creating or updating pages
data PropertyValue = PropertyValue
  { type_ :: PropertyValueType,
    value :: Maybe Value
  }
  deriving stock (Generic, Show)

instance ToJSON PropertyValue where
  -- Direct conversion - the important part is that we're NOT nesting under "type" or "value" fields
  toJSON PropertyValue {type_ = Title, value = Just v} =
    -- For title property, directly put the array into a "title" field
    case v of
      Object o ->
        if KeyMap.member "title" o
          then Aeson.Object o -- Use this object directly, just have to wrap it
          else Aeson.object ["title" .= v] -- Otherwise wrap it
      _ -> Aeson.object ["title" .= ([] :: [Value])]
  -- Handle other property types
  toJSON PropertyValue {type_ = t, value = Just v} =
    -- Just directly use the value as the property content
    case v of
      Object o -> Aeson.Object o -- Use the object directly, but wrap it
      _ -> Aeson.object [] -- Empty object as fallback

  -- Empty property values
  toJSON PropertyValue {type_} = Aeson.object []

-- | Property item returned by API
data PropertyItem = PropertyItem
  { id :: Text,
    type_ :: PropertyValueType,
    value :: Maybe Value
  }
  deriving stock (Generic, Show)

instance FromJSON PropertyItem where
  parseJSON = \case
    Object o -> do
      id <- o .: "id"
      type_ <- o .: "type"
      -- The Notion API stores the property value under a type-specific key
      -- (e.g., "title", "select", "rich_text"), not under a generic "value" key.
      let typeKey = Key.fromText (propertyTypeToKey type_)
          value = KeyMap.lookup typeKey o >>= \v -> Just v
      return PropertyItem {..}
    _ -> fail "Expected object for PropertyItem"

instance ToJSON PropertyItem where
  toJSON PropertyItem {..} =
    let base = ["id" .= id, "type" .= type_]
        typeKey = Key.fromText (propertyTypeToKey type_)
        valueField = case value of
          Just v -> [typeKey .= v]
          Nothing -> []
     in Aeson.object (base <> valueField)

-- | Map a PropertyValueType to the JSON key the Notion API uses for its value
propertyTypeToKey :: PropertyValueType -> Text
propertyTypeToKey = \case
  Title -> "title"
  RichText -> "rich_text"
  Number -> "number"
  Select -> "select"
  MultiSelect -> "multi_select"
  Date -> "date"
  People -> "people"
  Files -> "files"
  Checkbox -> "checkbox"
  Url -> "url"
  Email -> "email"
  PhoneNumber -> "phone_number"
  Formula -> "formula"
  Relation -> "relation"
  Rollup -> "rollup"
  CreatedTime -> "created_time"
  CreatedBy -> "created_by"
  LastEditedTime -> "last_edited_time"
  LastEditedBy -> "last_edited_by"
  Status -> "status"
  UniqueId -> "unique_id"
  Place -> "place"
  Button -> "button"
  Verification -> "verification"

-- | Property value types
data PropertyValueType
  = Title
  | RichText
  | Number
  | Select
  | MultiSelect
  | Date
  | People
  | Files
  | Checkbox
  | Url
  | Email
  | PhoneNumber
  | Formula
  | Relation
  | Rollup
  | CreatedTime
  | CreatedBy
  | LastEditedTime
  | LastEditedBy
  | Status
  | UniqueId
  | Place
  | Button
  | Verification
  deriving stock (Eq, Generic, Show)

instance FromJSON PropertyValueType where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON PropertyValueType where
  toJSON = genericToJSON aesonOptions

-- | Select option
data SelectOption = SelectOption
  { id :: Maybe Text,
    name :: Text,
    color :: Maybe Text
  }
  deriving stock (Generic, Show)

instance FromJSON SelectOption where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON SelectOption where
  toJSON = genericToJSON aesonOptions

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
       )
