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
  )
where

import Data.Aeson (object, (.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Types (Parser)
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
    color :: Maybe SelectColor
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
    other -> fail $ "Unknown NumberFormat: " <> unpack other

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
  | DualProperty
      { syncedPropertyId :: Text,
        syncedPropertyName :: Text
      }
  deriving stock (Eq, Show, Generic)

instance FromJSON RelationType where
  parseJSON = \case
    Object o -> do
      relType <- o .: "type"
      case relType of
        "single_property" -> pure SingleProperty
        "dual_property" -> do
          dp <- o .: "dual_property"
          syncedPropertyId <- dp .: "synced_property_id"
          syncedPropertyName <- dp .: "synced_property_name"
          pure DualProperty {..}
        other -> fail $ "Unknown RelationType: " <> unpack other
    _ -> fail "Expected object for RelationType"

instance ToJSON RelationType where
  toJSON SingleProperty =
    object ["type" .= ("single_property" :: Text)]
  toJSON DualProperty {..} =
    object
      [ "type" .= ("dual_property" :: Text),
        "dual_property"
          .= object
            [ "synced_property_id" .= syncedPropertyId,
              "synced_property_name" .= syncedPropertyName
            ]
      ]

-- | Typed property schema for a database or data source property.
--
-- Each constructor carries the common envelope fields (@schemaId@, @schemaName@)
-- plus any type-specific configuration. The JSON representation uses a @type@
-- discriminator with the configuration nested under a key matching the type name.
data PropertySchema
  = TitleSchema {schemaId :: Text, schemaName :: Text}
  | RichTextSchema {schemaId :: Text, schemaName :: Text}
  | NumberSchema {schemaId :: Text, schemaName :: Text, numberFormat :: NumberFormat}
  | SelectSchema {schemaId :: Text, schemaName :: Text, selectOptions :: Vector SelectOption}
  | MultiSelectSchema {schemaId :: Text, schemaName :: Text, multiSelectOptions :: Vector SelectOption}
  | DateSchema {schemaId :: Text, schemaName :: Text}
  | PeopleSchema {schemaId :: Text, schemaName :: Text}
  | FilesSchema {schemaId :: Text, schemaName :: Text}
  | CheckboxSchema {schemaId :: Text, schemaName :: Text}
  | UrlSchema {schemaId :: Text, schemaName :: Text}
  | EmailSchema {schemaId :: Text, schemaName :: Text}
  | PhoneNumberSchema {schemaId :: Text, schemaName :: Text}
  | FormulaSchema {schemaId :: Text, schemaName :: Text, formulaExpression :: Text}
  | RelationSchema {schemaId :: Text, schemaName :: Text, relationDataSourceId :: UUID, relationType :: RelationType}
  | RollupSchema
      { schemaId :: Text,
        schemaName :: Text,
        rollupFunction :: RollupFunction,
        rollupRelationPropertyName :: Maybe Text,
        rollupRelationPropertyId :: Maybe Text,
        rollupPropertyName :: Maybe Text,
        rollupPropertyId :: Maybe Text
      }
  | CreatedTimeSchema {schemaId :: Text, schemaName :: Text}
  | CreatedBySchema {schemaId :: Text, schemaName :: Text}
  | LastEditedTimeSchema {schemaId :: Text, schemaName :: Text}
  | LastEditedBySchema {schemaId :: Text, schemaName :: Text}
  | StatusSchema {schemaId :: Text, schemaName :: Text, statusOptions :: Vector SelectOption, statusGroups :: Vector StatusGroup}
  | UniqueIdSchema {schemaId :: Text, schemaName :: Text, uniqueIdPrefix :: Maybe Text}
  | PlaceSchema {schemaId :: Text, schemaName :: Text}
  | ButtonSchema {schemaId :: Text, schemaName :: Text}
  | VerificationSchema {schemaId :: Text, schemaName :: Text}
  deriving stock (Eq, Show, Generic)

instance FromJSON PropertySchema where
  parseJSON = \case
    Object o -> do
      sid <- o .: "id"
      sname <- o .: "name"
      propType <- o .: "type"
      parseByType sid sname propType o
    _ -> fail "Expected object for PropertySchema"
    where
      parseByType :: Text -> Text -> Text -> Aeson.Object -> Parser PropertySchema
      parseByType sid sname = \case
        "title" -> \_ -> pure TitleSchema {schemaId = sid, schemaName = sname}
        "rich_text" -> \_ -> pure RichTextSchema {schemaId = sid, schemaName = sname}
        "number" -> \o -> do
          cfg <- o .: "number"
          fmt <- cfg .: "format"
          pure NumberSchema {schemaId = sid, schemaName = sname, numberFormat = fmt}
        "select" -> \o -> do
          cfg <- o .: "select"
          opts <- cfg .: "options"
          pure SelectSchema {schemaId = sid, schemaName = sname, selectOptions = opts}
        "multi_select" -> \o -> do
          cfg <- o .: "multi_select"
          opts <- cfg .: "options"
          pure MultiSelectSchema {schemaId = sid, schemaName = sname, multiSelectOptions = opts}
        "date" -> \_ -> pure DateSchema {schemaId = sid, schemaName = sname}
        "people" -> \_ -> pure PeopleSchema {schemaId = sid, schemaName = sname}
        "files" -> \_ -> pure FilesSchema {schemaId = sid, schemaName = sname}
        "checkbox" -> \_ -> pure CheckboxSchema {schemaId = sid, schemaName = sname}
        "url" -> \_ -> pure UrlSchema {schemaId = sid, schemaName = sname}
        "email" -> \_ -> pure EmailSchema {schemaId = sid, schemaName = sname}
        "phone_number" -> \_ -> pure PhoneNumberSchema {schemaId = sid, schemaName = sname}
        "formula" -> \o -> do
          cfg <- o .: "formula"
          expr <- cfg .: "expression"
          pure FormulaSchema {schemaId = sid, schemaName = sname, formulaExpression = expr}
        "relation" -> \o -> do
          cfg <- o .: "relation"
          dsId <- cfg .: "data_source_id"
          relType <- Aeson.parseJSON (Object cfg)
          pure RelationSchema {schemaId = sid, schemaName = sname, relationDataSourceId = dsId, relationType = relType}
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
                rollupFunction = fn,
                rollupRelationPropertyName = relPropName,
                rollupRelationPropertyId = relPropId,
                rollupPropertyName = propName,
                rollupPropertyId = propId
              }
        "created_time" -> \_ -> pure CreatedTimeSchema {schemaId = sid, schemaName = sname}
        "created_by" -> \_ -> pure CreatedBySchema {schemaId = sid, schemaName = sname}
        "last_edited_time" -> \_ -> pure LastEditedTimeSchema {schemaId = sid, schemaName = sname}
        "last_edited_by" -> \_ -> pure LastEditedBySchema {schemaId = sid, schemaName = sname}
        "status" -> \o -> do
          cfg <- o .: "status"
          opts <- cfg .: "options"
          grps <- cfg .: "groups"
          pure StatusSchema {schemaId = sid, schemaName = sname, statusOptions = opts, statusGroups = grps}
        "unique_id" -> \o -> do
          cfg <- o .: "unique_id"
          prefix <- cfg .:? "prefix"
          pure UniqueIdSchema {schemaId = sid, schemaName = sname, uniqueIdPrefix = prefix}
        "place" -> \_ -> pure PlaceSchema {schemaId = sid, schemaName = sname}
        "button" -> \_ -> pure ButtonSchema {schemaId = sid, schemaName = sname}
        "verification" -> \_ -> pure VerificationSchema {schemaId = sid, schemaName = sname}
        other -> \_ -> fail $ "Unknown property type: " <> unpack other

instance ToJSON PropertySchema where
  toJSON schema =
    let (sid, sname, typeName, typeConfig) = schemaFields schema
     in object $
          [ "id" .= sid,
            "name" .= sname,
            "type" .= typeName
          ]
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
    let relObj = case relationType of
          SingleProperty -> object ["data_source_id" .= relationDataSourceId, "type" .= ("single_property" :: Text)]
          DualProperty {..} ->
            object
              [ "data_source_id" .= relationDataSourceId,
                "type" .= ("dual_property" :: Text),
                "dual_property" .= object ["synced_property_id" .= syncedPropertyId, "synced_property_name" .= syncedPropertyName]
              ]
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
  StatusSchema {..} -> (schemaId, schemaName, "status", object ["options" .= statusOptions, "groups" .= statusGroups])
  UniqueIdSchema {..} ->
    ( schemaId,
      schemaName,
      "unique_id",
      object $ maybe [] (\v -> ["prefix" .= v]) uniqueIdPrefix
    )
  PlaceSchema {..} -> (schemaId, schemaName, "place", object [])
  ButtonSchema {..} -> (schemaId, schemaName, "button", object [])
  VerificationSchema {..} -> (schemaId, schemaName, "verification", object [])
