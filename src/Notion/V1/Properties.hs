-- | Typed property schema definitions for Notion databases and data sources.
--
-- A property schema describes the "shape" of a database column — for example,
-- a select property schema defines which options are available (names and colors),
-- while a page's select property value is which option was chosen.
--
-- This module is used by both 'Notion.V1.Databases' and 'Notion.V1.DataSources'
-- for typed @properties@ fields.
module Notion.V1.Properties
  ( -- * Property schema
    PropertySchema (..),

    -- * Supporting types
    SelectColor (..),
    SelectOption (..),
    StatusGroup (..),
    NumberFormat (..),
    RollupFunction (..),
    RelationType (..),

    -- * Data source property updates
    PropertyUpdate (..),
    OptionUpdate (..),
    OptionTarget (..),
  )
where

import Data.Aeson (object, (.!=), (.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Parser)
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import Notion.Prelude
import Notion.V1.Common (UUID)
import Prelude hiding (id)

-- | Colors available for select, multi-select, and status property options.
--
-- This is distinct from 'Notion.V1.Common.Color' which covers text annotation
-- colors including background variants.
data SelectColor
  = DefaultColor
  | Gray
  | Brown
  | Orange
  | Yellow
  | Green
  | Blue
  | Purple
  | Pink
  | Red
  deriving stock (Eq, Show, Generic)

instance FromJSON SelectColor where
  parseJSON = Aeson.withText "SelectColor" $ \case
    "default" -> pure DefaultColor
    "gray" -> pure Gray
    "brown" -> pure Brown
    "orange" -> pure Orange
    "yellow" -> pure Yellow
    "green" -> pure Green
    "blue" -> pure Blue
    "purple" -> pure Purple
    "pink" -> pure Pink
    "red" -> pure Red
    other -> fail $ "Unknown SelectColor: " <> unpack other

instance ToJSON SelectColor where
  toJSON DefaultColor = Aeson.String "default"
  toJSON Gray = Aeson.String "gray"
  toJSON Brown = Aeson.String "brown"
  toJSON Orange = Aeson.String "orange"
  toJSON Yellow = Aeson.String "yellow"
  toJSON Green = Aeson.String "green"
  toJSON Blue = Aeson.String "blue"
  toJSON Purple = Aeson.String "purple"
  toJSON Pink = Aeson.String "pink"
  toJSON Red = Aeson.String "red"

-- | A select or multi-select option in a property schema.
data SelectOption = SelectOption
  { id :: Maybe Text,
    name :: Text,
    color :: Maybe SelectColor,
    description :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON SelectOption where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON SelectOption where
  toJSON = genericToJSON aesonOptions

-- | A status group in a status property schema.
data StatusGroup = StatusGroup
  { id :: Maybe Text,
    name :: Text,
    color :: Maybe SelectColor,
    optionIds :: Vector Text
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON StatusGroup where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON StatusGroup where
  toJSON = genericToJSON aesonOptions

-- | Number format for number property schemas.
data NumberFormat
  = NumberPlain
  | NumberWithCommas
  | Percent
  | Dollar
  | CanadianDollar
  | Euro
  | Pound
  | Yen
  | Ruble
  | Rupee
  | Won
  | Yuan
  | Real
  | Lira
  | Rupiah
  | Franc
  | HongKongDollar
  | NewZealandDollar
  | Krona
  | NorwegianKrone
  | MexicanPeso
  | Rand
  | NewTaiwanDollar
  | DanishKrone
  | Zloty
  | Baht
  | Forint
  | Koruna
  | Shekel
  | ChileanPeso
  | PhilippinePeso
  | Dirham
  | ColombianPeso
  | Riyal
  | Ringgit
  | Leu
  | ArgentinePeso
  | UruguayanPeso
  | SingaporeDollar
  | -- | A format this library does not know yet; Notion treats the set as open.
    OtherNumberFormat Text
  deriving stock (Eq, Show, Generic)

instance FromJSON NumberFormat where
  parseJSON = Aeson.withText "NumberFormat" $ \case
    "number" -> pure NumberPlain
    "number_with_commas" -> pure NumberWithCommas
    "percent" -> pure Percent
    "dollar" -> pure Dollar
    "canadian_dollar" -> pure CanadianDollar
    "euro" -> pure Euro
    "pound" -> pure Pound
    "yen" -> pure Yen
    "ruble" -> pure Ruble
    "rupee" -> pure Rupee
    "won" -> pure Won
    "yuan" -> pure Yuan
    "real" -> pure Real
    "lira" -> pure Lira
    "rupiah" -> pure Rupiah
    "franc" -> pure Franc
    "hong_kong_dollar" -> pure HongKongDollar
    "new_zealand_dollar" -> pure NewZealandDollar
    "krona" -> pure Krona
    "norwegian_krone" -> pure NorwegianKrone
    "mexican_peso" -> pure MexicanPeso
    "rand" -> pure Rand
    "new_taiwan_dollar" -> pure NewTaiwanDollar
    "danish_krone" -> pure DanishKrone
    "zloty" -> pure Zloty
    "baht" -> pure Baht
    "forint" -> pure Forint
    "koruna" -> pure Koruna
    "shekel" -> pure Shekel
    "chilean_peso" -> pure ChileanPeso
    "philippine_peso" -> pure PhilippinePeso
    "dirham" -> pure Dirham
    "colombian_peso" -> pure ColombianPeso
    "riyal" -> pure Riyal
    "ringgit" -> pure Ringgit
    "leu" -> pure Leu
    "argentine_peso" -> pure ArgentinePeso
    "uruguayan_peso" -> pure UruguayanPeso
    "singapore_dollar" -> pure SingaporeDollar
    other -> pure (OtherNumberFormat other)

instance ToJSON NumberFormat where
  toJSON NumberPlain = Aeson.String "number"
  toJSON NumberWithCommas = Aeson.String "number_with_commas"
  toJSON Percent = Aeson.String "percent"
  toJSON Dollar = Aeson.String "dollar"
  toJSON CanadianDollar = Aeson.String "canadian_dollar"
  toJSON Euro = Aeson.String "euro"
  toJSON Pound = Aeson.String "pound"
  toJSON Yen = Aeson.String "yen"
  toJSON Ruble = Aeson.String "ruble"
  toJSON Rupee = Aeson.String "rupee"
  toJSON Won = Aeson.String "won"
  toJSON Yuan = Aeson.String "yuan"
  toJSON Real = Aeson.String "real"
  toJSON Lira = Aeson.String "lira"
  toJSON Rupiah = Aeson.String "rupiah"
  toJSON Franc = Aeson.String "franc"
  toJSON HongKongDollar = Aeson.String "hong_kong_dollar"
  toJSON NewZealandDollar = Aeson.String "new_zealand_dollar"
  toJSON Krona = Aeson.String "krona"
  toJSON NorwegianKrone = Aeson.String "norwegian_krone"
  toJSON MexicanPeso = Aeson.String "mexican_peso"
  toJSON Rand = Aeson.String "rand"
  toJSON NewTaiwanDollar = Aeson.String "new_taiwan_dollar"
  toJSON DanishKrone = Aeson.String "danish_krone"
  toJSON Zloty = Aeson.String "zloty"
  toJSON Baht = Aeson.String "baht"
  toJSON Forint = Aeson.String "forint"
  toJSON Koruna = Aeson.String "koruna"
  toJSON Shekel = Aeson.String "shekel"
  toJSON ChileanPeso = Aeson.String "chilean_peso"
  toJSON PhilippinePeso = Aeson.String "philippine_peso"
  toJSON Dirham = Aeson.String "dirham"
  toJSON ColombianPeso = Aeson.String "colombian_peso"
  toJSON Riyal = Aeson.String "riyal"
  toJSON Ringgit = Aeson.String "ringgit"
  toJSON Leu = Aeson.String "leu"
  toJSON ArgentinePeso = Aeson.String "argentine_peso"
  toJSON UruguayanPeso = Aeson.String "uruguayan_peso"
  toJSON SingaporeDollar = Aeson.String "singapore_dollar"
  toJSON (OtherNumberFormat t) = Aeson.String t

-- | Rollup aggregation function.
data RollupFunction
  = CountAll
  | CountValues
  | CountUniqueValues
  | CountEmpty
  | CountNotEmpty
  | PercentEmpty
  | PercentNotEmpty
  | Sum
  | Average
  | Median
  | Min
  | Max
  | Range
  | ShowOriginal
  | Checked
  | Unchecked
  | PercentChecked
  | PercentUnchecked
  | DateRange
  | EarliestDate
  | LatestDate
  | ShowUnique
  | Count
  | Empty
  | NotEmpty
  | CountPerGroup
  | PercentPerGroup
  | Unique
  deriving stock (Eq, Show, Generic)

instance FromJSON RollupFunction where
  parseJSON = Aeson.withText "RollupFunction" $ \case
    "count_all" -> pure CountAll
    "count_values" -> pure CountValues
    "count_unique_values" -> pure CountUniqueValues
    "count_empty" -> pure CountEmpty
    "count_not_empty" -> pure CountNotEmpty
    "percent_empty" -> pure PercentEmpty
    "percent_not_empty" -> pure PercentNotEmpty
    "sum" -> pure Sum
    "average" -> pure Average
    "median" -> pure Median
    "min" -> pure Min
    "max" -> pure Max
    "range" -> pure Range
    "show_original" -> pure ShowOriginal
    "checked" -> pure Checked
    "unchecked" -> pure Unchecked
    "percent_checked" -> pure PercentChecked
    "percent_unchecked" -> pure PercentUnchecked
    "date_range" -> pure DateRange
    "earliest_date" -> pure EarliestDate
    "latest_date" -> pure LatestDate
    "show_unique" -> pure ShowUnique
    "count" -> pure Count
    "empty" -> pure Empty
    "not_empty" -> pure NotEmpty
    "count_per_group" -> pure CountPerGroup
    "percent_per_group" -> pure PercentPerGroup
    "unique" -> pure Unique
    other -> fail $ "Unknown RollupFunction: " <> unpack other

instance ToJSON RollupFunction where
  toJSON CountAll = Aeson.String "count_all"
  toJSON CountValues = Aeson.String "count_values"
  toJSON CountUniqueValues = Aeson.String "count_unique_values"
  toJSON CountEmpty = Aeson.String "count_empty"
  toJSON CountNotEmpty = Aeson.String "count_not_empty"
  toJSON PercentEmpty = Aeson.String "percent_empty"
  toJSON PercentNotEmpty = Aeson.String "percent_not_empty"
  toJSON Sum = Aeson.String "sum"
  toJSON Average = Aeson.String "average"
  toJSON Median = Aeson.String "median"
  toJSON Min = Aeson.String "min"
  toJSON Max = Aeson.String "max"
  toJSON Range = Aeson.String "range"
  toJSON ShowOriginal = Aeson.String "show_original"
  toJSON Checked = Aeson.String "checked"
  toJSON Unchecked = Aeson.String "unchecked"
  toJSON PercentChecked = Aeson.String "percent_checked"
  toJSON PercentUnchecked = Aeson.String "percent_unchecked"
  toJSON DateRange = Aeson.String "date_range"
  toJSON EarliestDate = Aeson.String "earliest_date"
  toJSON LatestDate = Aeson.String "latest_date"
  toJSON ShowUnique = Aeson.String "show_unique"
  toJSON Count = Aeson.String "count"
  toJSON Empty = Aeson.String "empty"
  toJSON NotEmpty = Aeson.String "not_empty"
  toJSON CountPerGroup = Aeson.String "count_per_group"
  toJSON PercentPerGroup = Aeson.String "percent_per_group"
  toJSON Unique = Aeson.String "unique"

-- | Relation property type configuration.
data RelationType
  = SingleProperty
  | -- | Both synced fields are optional in requests; Notion fills them in responses.
    DualProperty
      { syncedPropertyId :: Maybe Text,
        syncedPropertyName :: Maybe Text
      }
  deriving stock (Eq, Show, Generic)

instance FromJSON RelationType where
  parseJSON = \case
    Object o -> do
      relType <- o .: "type"
      case relType of
        "single_property" -> pure SingleProperty
        "dual_property" -> do
          dp <- o .:? "dual_property" .!= KeyMap.empty
          syncedPropertyId <- dp .:? "synced_property_id"
          syncedPropertyName <- dp .:? "synced_property_name"
          pure DualProperty {..}
        other -> fail $ "Unknown RelationType: " <> unpack other
    _ -> fail "Expected object for RelationType"

instance ToJSON RelationType where
  toJSON relType = object (relationTypeFields relType)

relationTypeFields :: RelationType -> [(Aeson.Key, Value)]
relationTypeFields = \case
  SingleProperty ->
    [ "type" .= ("single_property" :: Text),
      "single_property" .= object []
    ]
  DualProperty {..} ->
    [ "type" .= ("dual_property" :: Text),
      "dual_property"
        .= object
          ( maybe [] (\v -> ["synced_property_id" .= v]) syncedPropertyId
              <> maybe [] (\v -> ["synced_property_name" .= v]) syncedPropertyName
          )
    ]

-- | Typed property schema for a database or data source property.
--
-- Each constructor carries the common envelope fields (@schemaId@, @schemaName@,
-- @schemaDescription@) plus any type-specific configuration. The JSON representation uses a
-- @type@ discriminator with the configuration nested under a key matching the type name.
--
-- Request bodies may leave @schemaId@ empty; an empty id is not sent.
data PropertySchema
  = TitleSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text}
  | RichTextSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text}
  | NumberSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text, numberFormat :: NumberFormat}
  | SelectSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text, selectOptions :: Vector SelectOption}
  | MultiSelectSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text, multiSelectOptions :: Vector SelectOption}
  | DateSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text}
  | PeopleSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text}
  | FilesSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text}
  | CheckboxSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text}
  | UrlSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text}
  | EmailSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text}
  | PhoneNumberSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text}
  | FormulaSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text, formulaExpression :: Text}
  | RelationSchema
      { schemaId :: Text,
        schemaName :: Text,
        schemaDescription :: Maybe Text,
        relationDataSourceId :: UUID,
        -- | The database containing the related data source (response only).
        relationDatabaseId :: Maybe UUID,
        relationType :: RelationType
      }
  | RollupSchema
      { schemaId :: Text,
        schemaName :: Text,
        schemaDescription :: Maybe Text,
        rollupFunction :: RollupFunction,
        rollupRelationPropertyName :: Maybe Text,
        rollupRelationPropertyId :: Maybe Text,
        rollupPropertyName :: Maybe Text,
        rollupPropertyId :: Maybe Text
      }
  | CreatedTimeSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text}
  | CreatedBySchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text}
  | LastEditedTimeSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text}
  | LastEditedBySchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text}
  | -- | A status schema. Creation requests may only send options; 'statusGroups' is omitted
    -- when empty.
    StatusSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text, statusOptions :: Vector SelectOption, statusGroups :: Vector StatusGroup}
  | UniqueIdSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text, uniqueIdPrefix :: Maybe Text}
  | PlaceSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text}
  | ButtonSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text}
  | VerificationSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text}
  | LocationSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text}
  | LastVisitedTimeSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text}
  | -- | A property type this client does not model; @schemaConfig@ is the raw value under the type key.
    UnknownSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text, schemaType :: Text, schemaConfig :: Value}
  deriving stock (Eq, Show, Generic)

instance FromJSON PropertySchema where
  parseJSON = \case
    Object o -> do
      sid <- o .:? "id" .!= ""
      sname <- o .:? "name" .!= ""
      sdesc <- o .:? "description"
      propType <- o .: "type"
      parseByType sid sname sdesc propType o
    _ -> fail "Expected object for PropertySchema"
    where
      parseByType :: Text -> Text -> Maybe Text -> Text -> Aeson.Object -> Parser PropertySchema
      parseByType sid sname sdesc = \case
        "title" -> \_ -> pure TitleSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc}
        "rich_text" -> \_ -> pure RichTextSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc}
        "number" -> \o -> do
          cfg <- o .: "number"
          fmt <- cfg .: "format"
          pure NumberSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc, numberFormat = fmt}
        "select" -> \o -> do
          cfg <- o .: "select"
          opts <- cfg .: "options"
          pure SelectSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc, selectOptions = opts}
        "multi_select" -> \o -> do
          cfg <- o .: "multi_select"
          opts <- cfg .: "options"
          pure MultiSelectSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc, multiSelectOptions = opts}
        "date" -> \_ -> pure DateSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc}
        "people" -> \_ -> pure PeopleSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc}
        "files" -> \_ -> pure FilesSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc}
        "checkbox" -> \_ -> pure CheckboxSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc}
        "url" -> \_ -> pure UrlSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc}
        "email" -> \_ -> pure EmailSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc}
        "phone_number" -> \_ -> pure PhoneNumberSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc}
        "formula" -> \o -> do
          cfg <- o .: "formula"
          expr <- cfg .: "expression"
          pure FormulaSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc, formulaExpression = expr}
        "relation" -> \o -> do
          cfg <- o .: "relation"
          dsId <- cfg .: "data_source_id"
          dbId <- cfg .:? "database_id"
          relType <- Aeson.parseJSON (Object cfg)
          pure RelationSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc, relationDataSourceId = dsId, relationDatabaseId = dbId, relationType = relType}
        "rollup" -> \o -> do
          cfg <- o .: "rollup"
          fn <- cfg .: "function"
          relPropName <- cfg .:? "relation_property_name"
          relPropId <- cfg .:? "relation_property_id"
          propName <- cfg .:? "rollup_property_name"
          propId <- cfg .:? "rollup_property_id"
          pure
            RollupSchema
              { schemaId = sid,
                schemaName = sname,
                schemaDescription = sdesc,
                rollupFunction = fn,
                rollupRelationPropertyName = relPropName,
                rollupRelationPropertyId = relPropId,
                rollupPropertyName = propName,
                rollupPropertyId = propId
              }
        "created_time" -> \_ -> pure CreatedTimeSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc}
        "created_by" -> \_ -> pure CreatedBySchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc}
        "last_edited_time" -> \_ -> pure LastEditedTimeSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc}
        "last_edited_by" -> \_ -> pure LastEditedBySchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc}
        "status" -> \o -> do
          cfg <- o .: "status"
          opts <- cfg .: "options"
          grps <- cfg .:? "groups" .!= mempty
          pure StatusSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc, statusOptions = opts, statusGroups = grps}
        "unique_id" -> \o -> do
          cfg <- o .: "unique_id"
          prefix <- cfg .:? "prefix"
          pure UniqueIdSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc, uniqueIdPrefix = prefix}
        "place" -> \_ -> pure PlaceSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc}
        "button" -> \_ -> pure ButtonSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc}
        "verification" -> \_ -> pure VerificationSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc}
        "location" -> \_ -> pure LocationSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc}
        "last_visited_time" -> \_ -> pure LastVisitedTimeSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc}
        other -> \o -> do
          cfg <- o .:? Key.fromText other .!= object []
          pure UnknownSchema {schemaId = sid, schemaName = sname, schemaDescription = sdesc, schemaType = other, schemaConfig = cfg}

instance ToJSON PropertySchema where
  toJSON schema =
    let (sid, sname, typeName, typeConfig) = schemaFields schema
     in object $
          (if Text.null sid then [] else ["id" .= sid])
            <> ["name" .= sname, "type" .= typeName]
            <> maybe [] (\d -> ["description" .= d]) (schemaDescription schema)
            <> [typeName .= typeConfig]

schemaFields :: PropertySchema -> (Text, Text, Aeson.Key, Value)
schemaFields = \case
  TitleSchema {..} -> (schemaId, schemaName, "title", object [])
  RichTextSchema {..} -> (schemaId, schemaName, "rich_text", object [])
  NumberSchema {..} -> (schemaId, schemaName, "number", object ["format" .= numberFormat])
  SelectSchema {..} -> (schemaId, schemaName, "select", object ["options" .= selectOptions])
  MultiSelectSchema {..} -> (schemaId, schemaName, "multi_select", object ["options" .= multiSelectOptions])
  DateSchema {..} -> (schemaId, schemaName, "date", object [])
  PeopleSchema {..} -> (schemaId, schemaName, "people", object [])
  FilesSchema {..} -> (schemaId, schemaName, "files", object [])
  CheckboxSchema {..} -> (schemaId, schemaName, "checkbox", object [])
  UrlSchema {..} -> (schemaId, schemaName, "url", object [])
  EmailSchema {..} -> (schemaId, schemaName, "email", object [])
  PhoneNumberSchema {..} -> (schemaId, schemaName, "phone_number", object [])
  FormulaSchema {..} -> (schemaId, schemaName, "formula", object ["expression" .= formulaExpression])
  RelationSchema {..} ->
    let relObj =
          object $
            maybe [] (\v -> ["database_id" .= v]) relationDatabaseId
              <> ["data_source_id" .= relationDataSourceId]
              <> relationTypeFields relationType
     in (schemaId, schemaName, "relation", relObj)
  RollupSchema {..} ->
    ( schemaId,
      schemaName,
      "rollup",
      object $
        ["function" .= rollupFunction]
          <> maybe [] (\v -> ["relation_property_name" .= v]) rollupRelationPropertyName
          <> maybe [] (\v -> ["relation_property_id" .= v]) rollupRelationPropertyId
          <> maybe [] (\v -> ["rollup_property_name" .= v]) rollupPropertyName
          <> maybe [] (\v -> ["rollup_property_id" .= v]) rollupPropertyId
    )
  CreatedTimeSchema {..} -> (schemaId, schemaName, "created_time", object [])
  CreatedBySchema {..} -> (schemaId, schemaName, "created_by", object [])
  LastEditedTimeSchema {..} -> (schemaId, schemaName, "last_edited_time", object [])
  LastEditedBySchema {..} -> (schemaId, schemaName, "last_edited_by", object [])
  StatusSchema {..} ->
    ( schemaId,
      schemaName,
      "status",
      object (["options" .= statusOptions] <> (if Vector.null statusGroups then [] else ["groups" .= statusGroups]))
    )
  UniqueIdSchema {..} ->
    ( schemaId,
      schemaName,
      "unique_id",
      object $ maybe [] (\v -> ["prefix" .= v]) uniqueIdPrefix
    )
  PlaceSchema {..} -> (schemaId, schemaName, "place", object [])
  ButtonSchema {..} -> (schemaId, schemaName, "button", object [])
  VerificationSchema {..} -> (schemaId, schemaName, "verification", object [])
  LocationSchema {..} -> (schemaId, schemaName, "location", object [])
  LastVisitedTimeSchema {..} -> (schemaId, schemaName, "last_visited_time", object [])
  UnknownSchema {..} -> (schemaId, schemaName, Key.fromText schemaType, schemaConfig)

-- | Which existing option an option update addresses.
data OptionTarget
  = -- | @{"name": ...}@: match (or create) by name.
    OptionNamed Text
  | -- | @{"id": ..., "name"?: ...}@: match by id, optionally renaming.
    OptionWithId Text (Maybe Text)
  deriving stock (Eq, Show, Generic)

-- | One entry of a select, multi-select or status @options@ list in a data source update.
data OptionUpdate = OptionUpdate
  { target :: OptionTarget,
    color :: Maybe SelectColor,
    description :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)

instance ToJSON OptionUpdate where
  toJSON OptionUpdate {..} =
    object $
      ( case target of
          OptionNamed n -> ["name" .= n]
          OptionWithId i mn -> ["id" .= i] <> maybe [] (\n -> ["name" .= n]) mn
      )
        <> maybe [] (\c -> ["color" .= c]) color
        <> maybe [] (\d -> ["description" .= d]) description

-- | One entry of @UpdateDataSource.properties@.
data PropertyUpdate
  = -- | @null@: remove the property.
    RemoveProperty
  | -- | @{"name": ...}@: rename only.
    RenameProperty Text
  | -- | A full property configuration.
    SetPropertySchema PropertySchema
  | -- | @{"name"?:..., "select": {"options": [...]}}@
    UpdateSelectOptions {newName :: Maybe Text, optionUpdates :: Vector OptionUpdate}
  | -- | @{"name"?:..., "multi_select": {"options": [...]}}@
    UpdateMultiSelectOptions {newName :: Maybe Text, optionUpdates :: Vector OptionUpdate}
  | -- | @{"name"?:..., "status": {"options": [...]}}@
    UpdateStatusOptions {newName :: Maybe Text, optionUpdates :: Vector OptionUpdate}
  deriving stock (Eq, Show, Generic)

instance ToJSON PropertyUpdate where
  toJSON = \case
    RemoveProperty -> Null
    RenameProperty n -> object ["name" .= n]
    SetPropertySchema s -> toJSON s
    UpdateSelectOptions {..} -> opts "select" newName optionUpdates
    UpdateMultiSelectOptions {..} -> opts "multi_select" newName optionUpdates
    UpdateStatusOptions {..} -> opts "status" newName optionUpdates
    where
      opts :: Aeson.Key -> Maybe Text -> Vector OptionUpdate -> Value
      opts key mName us = object $ maybe [] (\n -> ["name" .= n]) mName <> [key .= object ["options" .= us]]
