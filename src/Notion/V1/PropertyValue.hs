-- | Typed property values for Notion pages.
--
-- A property value represents the actual data stored in a page's property —
-- for example, the selected option in a select property, or the text in a title.
-- This is distinct from 'Notion.V1.Properties.PropertySchema' which describes
-- the shape/configuration of the property column.
--
-- This module provides:
--
-- * A 'PropertyValue' sum type for reading page properties via pattern matching
-- * Smart constructors ('titleValue', 'selectValue', etc.) for writing properties
-- * Supporting types ('SelectOptionValue', 'FileValue', 'RelationRef', etc.)
module Notion.V1.PropertyValue
  ( -- * Property value
    PropertyValue (..),

    -- * Supporting types
    SelectOptionValue (..),
    FileValue (..),
    RelationRef (..),
    FormulaResult (..),
    RollupResult (..),
    UniqueIdResult (..),
    VerificationResult (..),

    -- * Smart constructors
    titleValue,
    richTextValue,
    numberValue,
    selectValue,
    multiSelectValue,
    dateValue,
    checkboxValue,
    urlValue,
    emailValue,
    phoneNumberValue,
    relationValue,
    statusValue,
    peopleValue,
    filesValue,
  )
where

import Data.Aeson ((.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Scientific (Scientific)
import Data.Vector qualified as Vector
import Notion.Prelude
import Notion.V1.Common (ExternalFile (..), File, UUID (..))
import Notion.V1.Properties (RollupFunction)
import Notion.V1.RichText (Date (..), RichText)
import Notion.V1.Users (UserReference (..))
import Prelude hiding (id)

-- | A typed property value from a Notion page.
--
-- Each constructor carries the property's schema ID as its first 'Text' field.
-- When reading from the API this is the property's internal ID (e.g., @\"abc\"@).
-- When constructing values for writes, use @\"\"@ (the smart constructors do this).
--
-- Read-only variants ('FormulaValue', 'RollupValue', 'UniqueIdValue',
-- 'CreatedTimeValue', 'CreatedByValue', 'LastEditedTimeValue', 'LastEditedByValue',
-- 'VerificationValue') only appear in API responses.
data PropertyValue
  = TitleValue Text (Vector RichText)
  | RichTextValue Text (Vector RichText)
  | NumberValue Text (Maybe Scientific)
  | SelectValue Text (Maybe SelectOptionValue)
  | MultiSelectValue Text (Vector SelectOptionValue)
  | DateValue Text (Maybe Date)
  | PeopleValue Text (Vector UserReference)
  | FilesValue Text (Vector FileValue)
  | CheckboxValue Text Bool
  | UrlValue Text (Maybe Text)
  | EmailValue Text (Maybe Text)
  | PhoneNumberValue Text (Maybe Text)
  | FormulaValue Text FormulaResult
  | RelationValue Text (Vector RelationRef)
  | RollupValue Text RollupResult
  | CreatedTimeValue Text Text
  | CreatedByValue Text UserReference
  | LastEditedTimeValue Text Text
  | LastEditedByValue Text UserReference
  | StatusValue Text (Maybe SelectOptionValue)
  | UniqueIdValue Text UniqueIdResult
  | PlaceValue Text (Maybe Value)
  | ButtonValue Text (Maybe Value)
  | VerificationValue Text (Maybe VerificationResult)
  deriving stock (Show)

instance FromJSON PropertyValue where
  parseJSON = \case
    Object o -> do
      pid <- o .: "id"
      propType <- o .: "type"
      let key = Key.fromText propType
      case propType of
        "title" -> TitleValue pid <$> o .: key
        "rich_text" -> RichTextValue pid <$> o .: key
        "number" -> NumberValue pid <$> o .: key
        "select" -> SelectValue pid <$> o .:? key
        "multi_select" -> MultiSelectValue pid <$> o .: key
        "date" -> DateValue pid <$> o .:? key
        "people" -> PeopleValue pid <$> o .: key
        "files" -> FilesValue pid <$> o .: key
        "checkbox" -> CheckboxValue pid <$> o .: key
        "url" -> UrlValue pid <$> o .:? key
        "email" -> EmailValue pid <$> o .:? key
        "phone_number" -> PhoneNumberValue pid <$> o .:? key
        "formula" -> FormulaValue pid <$> o .: key
        "relation" -> RelationValue pid <$> o .: key
        "rollup" -> RollupValue pid <$> o .: key
        "created_time" -> CreatedTimeValue pid <$> o .: key
        "created_by" -> CreatedByValue pid <$> o .: key
        "last_edited_time" -> LastEditedTimeValue pid <$> o .: key
        "last_edited_by" -> LastEditedByValue pid <$> o .: key
        "status" -> StatusValue pid <$> o .:? key
        "unique_id" -> UniqueIdValue pid <$> o .: key
        "place" -> PlaceValue pid <$> o .:? key
        "button" -> ButtonValue pid <$> o .:? key
        "verification" -> VerificationValue pid <$> o .:? key
        other -> fail $ "Unknown property value type: " <> unpack other
    _ -> fail "Expected object for PropertyValue"

instance ToJSON PropertyValue where
  toJSON = \case
    TitleValue _ v -> Aeson.object ["title" .= v]
    RichTextValue _ v -> Aeson.object ["rich_text" .= v]
    NumberValue _ v -> Aeson.object ["number" .= v]
    SelectValue _ v -> Aeson.object ["select" .= v]
    MultiSelectValue _ v -> Aeson.object ["multi_select" .= v]
    DateValue _ v -> Aeson.object ["date" .= v]
    PeopleValue _ v -> Aeson.object ["people" .= v]
    FilesValue _ v -> Aeson.object ["files" .= v]
    CheckboxValue _ v -> Aeson.object ["checkbox" .= v]
    UrlValue _ v -> Aeson.object ["url" .= v]
    EmailValue _ v -> Aeson.object ["email" .= v]
    PhoneNumberValue _ v -> Aeson.object ["phone_number" .= v]
    FormulaValue _ v -> Aeson.object ["formula" .= v]
    RelationValue _ v -> Aeson.object ["relation" .= v]
    RollupValue _ v -> Aeson.object ["rollup" .= v]
    CreatedTimeValue _ v -> Aeson.object ["created_time" .= v]
    CreatedByValue _ v -> Aeson.object ["created_by" .= v]
    LastEditedTimeValue _ v -> Aeson.object ["last_edited_time" .= v]
    LastEditedByValue _ v -> Aeson.object ["last_edited_by" .= v]
    StatusValue _ v -> Aeson.object ["status" .= v]
    UniqueIdValue _ v -> Aeson.object ["unique_id" .= v]
    PlaceValue _ v -> Aeson.object ["place" .= v]
    ButtonValue _ v -> Aeson.object ["button" .= v]
    VerificationValue _ v -> Aeson.object ["verification" .= v]

-- ---------------------------------------------------------------------------
-- Supporting types
-- ---------------------------------------------------------------------------

-- | A select/multi-select/status option value as it appears in page properties.
--
-- Note: 'color' is @Maybe Text@ (not 'SelectColor') because the API returns
-- color names as strings in property values, and the set may differ from schema colors.
data SelectOptionValue = SelectOptionValue
  { id :: Maybe Text,
    name :: Text,
    color :: Maybe Text
  }
  deriving stock (Generic, Show)

instance FromJSON SelectOptionValue where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON SelectOptionValue where
  toJSON = genericToJSON aesonOptions

-- | A file value in a files property. Can be an internal (Notion-hosted) file
-- or an external URL.
data FileValue
  = InternalFileValue {name :: Text, file :: File}
  | ExternalFileValue {name :: Text, external :: ExternalFile}
  deriving stock (Show)

instance FromJSON FileValue where
  parseJSON = \case
    Object o -> do
      fileType <- o .: "type"
      n <- o .: "name"
      case fileType of
        "file" -> InternalFileValue n <$> o .: "file"
        "external" -> ExternalFileValue n <$> o .: "external"
        other -> fail $ "Unknown file value type: " <> unpack other
    _ -> fail "Expected object for FileValue"

instance ToJSON FileValue where
  toJSON (InternalFileValue n f) =
    Aeson.object ["type" .= ("file" :: Text), "name" .= n, "file" .= f]
  toJSON (ExternalFileValue n e) =
    Aeson.object ["type" .= ("external" :: Text), "name" .= n, "external" .= e]

-- | A relation reference (just a page ID).
newtype RelationRef = RelationRef {id :: UUID}
  deriving stock (Show)

instance FromJSON RelationRef where
  parseJSON = \case
    Object o -> RelationRef <$> o .: "id"
    _ -> fail "Expected object for RelationRef"

instance ToJSON RelationRef where
  toJSON (RelationRef rid) = Aeson.object ["id" .= rid]

-- | The result of a formula property (read-only).
data FormulaResult
  = FormulaStringResult (Maybe Text)
  | FormulaNumberResult (Maybe Scientific)
  | FormulaBooleanResult (Maybe Bool)
  | FormulaDateResult (Maybe Date)
  deriving stock (Show)

instance FromJSON FormulaResult where
  parseJSON = \case
    Object o -> do
      formulaType <- o .: "type"
      case formulaType of
        "string" -> FormulaStringResult <$> o .:? "string"
        "number" -> FormulaNumberResult <$> o .:? "number"
        "boolean" -> FormulaBooleanResult <$> o .:? "boolean"
        "date" -> FormulaDateResult <$> o .:? "date"
        other -> fail $ "Unknown formula result type: " <> unpack other
    _ -> fail "Expected object for FormulaResult"

instance ToJSON FormulaResult where
  toJSON = \case
    FormulaStringResult v -> Aeson.object ["type" .= ("string" :: Text), "string" .= v]
    FormulaNumberResult v -> Aeson.object ["type" .= ("number" :: Text), "number" .= v]
    FormulaBooleanResult v -> Aeson.object ["type" .= ("boolean" :: Text), "boolean" .= v]
    FormulaDateResult v -> Aeson.object ["type" .= ("date" :: Text), "date" .= v]

-- | The result of a rollup property (read-only).
data RollupResult
  = RollupNumberResult (Maybe Scientific) RollupFunction
  | RollupDateResult (Maybe Date) RollupFunction
  | RollupArrayResult (Vector Value) RollupFunction
  | RollupIncompleteResult RollupFunction
  | RollupUnsupportedResult RollupFunction
  deriving stock (Show)

instance FromJSON RollupResult where
  parseJSON = \case
    Object o -> do
      rollupType <- o .: "type"
      fn <- o .: "function"
      case rollupType of
        "number" -> RollupNumberResult <$> o .:? "number" <*> pure fn
        "date" -> RollupDateResult <$> o .:? "date" <*> pure fn
        "array" -> RollupArrayResult <$> o .: "array" <*> pure fn
        "incomplete" -> pure $ RollupIncompleteResult fn
        "unsupported" -> pure $ RollupUnsupportedResult fn
        other -> fail $ "Unknown rollup result type: " <> unpack other
    _ -> fail "Expected object for RollupResult"

instance ToJSON RollupResult where
  toJSON = \case
    RollupNumberResult v fn -> Aeson.object ["type" .= ("number" :: Text), "number" .= v, "function" .= fn]
    RollupDateResult v fn -> Aeson.object ["type" .= ("date" :: Text), "date" .= v, "function" .= fn]
    RollupArrayResult v fn -> Aeson.object ["type" .= ("array" :: Text), "array" .= v, "function" .= fn]
    RollupIncompleteResult fn -> Aeson.object ["type" .= ("incomplete" :: Text), "function" .= fn]
    RollupUnsupportedResult fn -> Aeson.object ["type" .= ("unsupported" :: Text), "function" .= fn]

-- | Unique ID property value (read-only).
data UniqueIdResult = UniqueIdResult
  { number :: Natural,
    prefix :: Maybe Text
  }
  deriving stock (Generic, Show)

instance FromJSON UniqueIdResult where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON UniqueIdResult where
  toJSON = genericToJSON aesonOptions

-- | Verification property value (read-only).
data VerificationResult = VerificationResult
  { state :: Text,
    verifiedBy :: Maybe UserReference,
    date :: Maybe Date
  }
  deriving stock (Generic, Show)

instance FromJSON VerificationResult where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON VerificationResult where
  toJSON = genericToJSON aesonOptions

-- ---------------------------------------------------------------------------
-- Smart constructors
-- ---------------------------------------------------------------------------

-- | Create a title property value.
titleValue :: Vector RichText -> PropertyValue
titleValue = TitleValue ""

-- | Create a rich text property value.
richTextValue :: Vector RichText -> PropertyValue
richTextValue = RichTextValue ""

-- | Create a number property value.
numberValue :: Scientific -> PropertyValue
numberValue n = NumberValue "" (Just n)

-- | Create a select property value by option name.
selectValue :: Text -> PropertyValue
selectValue name = SelectValue "" (Just (SelectOptionValue Nothing name Nothing))

-- | Create a multi-select property value from a list of option names.
multiSelectValue :: [Text] -> PropertyValue
multiSelectValue names = MultiSelectValue "" (Vector.fromList (map (\n -> SelectOptionValue Nothing n Nothing) names))

-- | Create a date property value.
dateValue :: Text -> Maybe Text -> PropertyValue
dateValue start end = DateValue "" (Just (Date start end Nothing))

-- | Create a checkbox property value.
checkboxValue :: Bool -> PropertyValue
checkboxValue = CheckboxValue ""

-- | Create a URL property value.
urlValue :: Text -> PropertyValue
urlValue t = UrlValue "" (Just t)

-- | Create an email property value.
emailValue :: Text -> PropertyValue
emailValue t = EmailValue "" (Just t)

-- | Create a phone number property value.
phoneNumberValue :: Text -> PropertyValue
phoneNumberValue t = PhoneNumberValue "" (Just t)

-- | Create a relation property value from a list of page IDs.
relationValue :: [UUID] -> PropertyValue
relationValue ids = RelationValue "" (Vector.fromList (map RelationRef ids))

-- | Create a status property value by option name.
statusValue :: Text -> PropertyValue
statusValue name = StatusValue "" (Just (SelectOptionValue Nothing name Nothing))

-- | Create a people property value from a list of user IDs.
peopleValue :: [UUID] -> PropertyValue
peopleValue ids = PeopleValue "" (Vector.fromList (map (\i -> UserReference i "user") ids))

-- | Create a files property value from a list of external URLs.
filesValue :: [Text] -> PropertyValue
filesValue urls = FilesValue "" (Vector.fromList (map (\u -> ExternalFileValue "" (ExternalFile u)) urls))
