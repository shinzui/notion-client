-- | Typed view configuration: the layout settings of table, board, calendar,
-- timeline, gallery and list views.
--
-- One set of types serves both responses and requests. Fields Notion accepts
-- as @null@ (to clear a setting) are 'Clearable'. Response-only convenience
-- fields such as @property_name@ are decoded but dropped when encoding, so a
-- retrieved configuration can be changed and sent back as is. Every sum type
-- and enum keeps unrecognised values as raw JSON or text.
module Notion.V1.ViewConfig
  ( -- * View configuration
    ViewConfig (..),
    TableViewConfig (..),
    BoardViewConfig (..),
    CalendarViewConfig (..),
    TimelineViewConfig (..),
    GalleryViewConfig (..),
    ListViewConfig (..),
    TimelinePreference (..),
    TimelineArrowsBy (..),

    -- * Shared pieces
    ViewPropertyConfig (..),
    SubtaskConfig (..),
    CoverConfig (..),

    -- * Group by
    GroupByConfig (..),
    SelectGroupByConfig (..),
    StatusGroupByConfig (..),
    PersonGroupByConfig (..),
    RelationGroupByConfig (..),
    DateGroupByConfig (..),
    TextGroupByConfig (..),
    NumberGroupByConfig (..),
    CheckboxGroupByConfig (..),
    FormulaGroupByConfig (..),
    FormulaSubGroupBy (..),
    FormulaDateSubGroupBy (..),
    FormulaTextSubGroupBy (..),
    FormulaNumberSubGroupBy (..),
    FormulaCheckboxSubGroupBy (..),

    -- * Enumerations
    GroupSort (..),
    SelectGroupKind (..),
    PersonGroupKind (..),
    DateGroupKind (..),
    TextGroupKind (..),
    DateGranularity (..),
    TextGroupMode (..),
    StatusGroupMode (..),
    StatusShowAs (..),
    CardPropertyWidthMode (..),
    DateFormat (..),
    TimeFormat (..),
    SubtaskDisplayMode (..),
    SubtaskFilterScope (..),
    CoverType (..),
    CoverSize (..),
    CoverAspect (..),
    CardLayout (..),
    CalendarRange (..),
    TimelineZoomLevel (..),
  )
where

import Control.Applicative ((<|>))
import Data.Aeson ((.:), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Parser)
import Data.Maybe (fromMaybe)
import Data.Scientific (Scientific)
import Data.Tuple (swap)
import Notion.Prelude
import Notion.V1.Clearable (Clearable (..))

-- =====================================================================
-- Helpers
-- =====================================================================

-- | Decode a string enum from a lookup table; unknown strings go to the fallback constructor.
parseEnum :: String -> [(Text, a)] -> (Text -> a) -> Value -> Parser a
parseEnum name table unknown =
  Aeson.withText name $ \t -> pure (fromMaybe (unknown t) (lookup t table))

-- | Encode a known enum constructor via the same table (callers handle the unknown constructor).
enumToJSON :: (Eq a) => [(Text, a)] -> a -> Value
enumToJSON table a = maybe Null String (lookup a (map swap table))

-- | Add the @type@ discriminator to an encoded object.
withType :: Text -> Value -> Value
withType t = \case
  Object o -> Object (KeyMap.insert "type" (String t) o)
  other -> other

-- | Remove response-only convenience keys before sending a configuration back to Notion.
dropKeys :: [Aeson.Key] -> Value -> Value
dropKeys ks = \case
  Object o -> Object (foldr KeyMap.delete o ks)
  other -> other

-- =====================================================================
-- Enumerations
-- =====================================================================

-- | How groups are ordered. Encoded as @{"type": ...}@.
data GroupSort
  = GroupSortManual
  | GroupSortAscending
  | GroupSortDescending
  | -- | A value this library does not know yet; holds the raw string.
    UnknownGroupSort Text
  deriving stock (Eq, Show, Generic)

groupSortTable :: [(Text, GroupSort)]
groupSortTable =
  [ ("manual", GroupSortManual),
    ("ascending", GroupSortAscending),
    ("descending", GroupSortDescending)
  ]

instance FromJSON GroupSort where
  parseJSON = Aeson.withObject "GroupSort" $ \o ->
    o .: "type" >>= parseEnum "GroupSort" groupSortTable UnknownGroupSort

instance ToJSON GroupSort where
  toJSON s = Aeson.object ["type" .= typeName]
    where
      typeName = case s of
        UnknownGroupSort t -> String t
        known -> enumToJSON groupSortTable known

-- | Property type of a select group-by.
data SelectGroupKind
  = SelectKind
  | MultiSelectKind
  | -- | A value this library does not know yet; holds the raw string.
    UnknownSelectGroupKind Text
  deriving stock (Eq, Show, Generic)

selectGroupKindTable :: [(Text, SelectGroupKind)]
selectGroupKindTable =
  [ ("select", SelectKind),
    ("multi_select", MultiSelectKind)
  ]

instance FromJSON SelectGroupKind where
  parseJSON = parseEnum "SelectGroupKind" selectGroupKindTable UnknownSelectGroupKind

instance ToJSON SelectGroupKind where
  toJSON = \case
    UnknownSelectGroupKind t -> String t
    known -> enumToJSON selectGroupKindTable known

-- | Property type of a person group-by.
data PersonGroupKind
  = PersonKind
  | CreatedByKind
  | LastEditedByKind
  | -- | A value this library does not know yet; holds the raw string.
    UnknownPersonGroupKind Text
  deriving stock (Eq, Show, Generic)

personGroupKindTable :: [(Text, PersonGroupKind)]
personGroupKindTable =
  [ ("person", PersonKind),
    ("created_by", CreatedByKind),
    ("last_edited_by", LastEditedByKind)
  ]

instance FromJSON PersonGroupKind where
  parseJSON = parseEnum "PersonGroupKind" personGroupKindTable UnknownPersonGroupKind

instance ToJSON PersonGroupKind where
  toJSON = \case
    UnknownPersonGroupKind t -> String t
    known -> enumToJSON personGroupKindTable known

-- | Property type of a date group-by.
data DateGroupKind
  = DateKind
  | CreatedTimeKind
  | LastEditedTimeKind
  | -- | A value this library does not know yet; holds the raw string.
    UnknownDateGroupKind Text
  deriving stock (Eq, Show, Generic)

dateGroupKindTable :: [(Text, DateGroupKind)]
dateGroupKindTable =
  [ ("date", DateKind),
    ("created_time", CreatedTimeKind),
    ("last_edited_time", LastEditedTimeKind)
  ]

instance FromJSON DateGroupKind where
  parseJSON = parseEnum "DateGroupKind" dateGroupKindTable UnknownDateGroupKind

instance ToJSON DateGroupKind where
  toJSON = \case
    UnknownDateGroupKind t -> String t
    known -> enumToJSON dateGroupKindTable known

-- | Property type of a text group-by.
data TextGroupKind
  = TextKind
  | TitleKind
  | UrlKind
  | EmailKind
  | PhoneNumberKind
  | -- | A value this library does not know yet; holds the raw string.
    UnknownTextGroupKind Text
  deriving stock (Eq, Show, Generic)

textGroupKindTable :: [(Text, TextGroupKind)]
textGroupKindTable =
  [ ("text", TextKind),
    ("title", TitleKind),
    ("url", UrlKind),
    ("email", EmailKind),
    ("phone_number", PhoneNumberKind)
  ]

instance FromJSON TextGroupKind where
  parseJSON = parseEnum "TextGroupKind" textGroupKindTable UnknownTextGroupKind

instance ToJSON TextGroupKind where
  toJSON = \case
    UnknownTextGroupKind t -> String t
    known -> enumToJSON textGroupKindTable known

-- | Bucket size when grouping by a date.
data DateGranularity
  = GranularityRelative
  | GranularityDay
  | GranularityWeek
  | GranularityMonth
  | GranularityYear
  | -- | A value this library does not know yet; holds the raw string.
    UnknownDateGranularity Text
  deriving stock (Eq, Show, Generic)

dateGranularityTable :: [(Text, DateGranularity)]
dateGranularityTable =
  [ ("relative", GranularityRelative),
    ("day", GranularityDay),
    ("week", GranularityWeek),
    ("month", GranularityMonth),
    ("year", GranularityYear)
  ]

instance FromJSON DateGranularity where
  parseJSON = parseEnum "DateGranularity" dateGranularityTable UnknownDateGranularity

instance ToJSON DateGranularity where
  toJSON = \case
    UnknownDateGranularity t -> String t
    known -> enumToJSON dateGranularityTable known

-- | How text values are grouped.
data TextGroupMode
  = GroupExact
  | GroupAlphabetPrefix
  | -- | A value this library does not know yet; holds the raw string.
    UnknownTextGroupMode Text
  deriving stock (Eq, Show, Generic)

textGroupModeTable :: [(Text, TextGroupMode)]
textGroupModeTable =
  [ ("exact", GroupExact),
    ("alphabet_prefix", GroupAlphabetPrefix)
  ]

instance FromJSON TextGroupMode where
  parseJSON = parseEnum "TextGroupMode" textGroupModeTable UnknownTextGroupMode

instance ToJSON TextGroupMode where
  toJSON = \case
    UnknownTextGroupMode t -> String t
    known -> enumToJSON textGroupModeTable known

-- | Whether a status group-by uses status groups or individual options.
data StatusGroupMode
  = GroupByStatusGroup
  | GroupByStatusOption
  | -- | A value this library does not know yet; holds the raw string.
    UnknownStatusGroupMode Text
  deriving stock (Eq, Show, Generic)

statusGroupModeTable :: [(Text, StatusGroupMode)]
statusGroupModeTable =
  [ ("group", GroupByStatusGroup),
    ("option", GroupByStatusOption)
  ]

instance FromJSON StatusGroupMode where
  parseJSON = parseEnum "StatusGroupMode" statusGroupModeTable UnknownStatusGroupMode

instance ToJSON StatusGroupMode where
  toJSON = \case
    UnknownStatusGroupMode t -> String t
    known -> enumToJSON statusGroupModeTable known

-- | How a status property is displayed.
data StatusShowAs
  = ShowAsSelect
  | ShowAsCheckbox
  | -- | A value this library does not know yet; holds the raw string.
    UnknownStatusShowAs Text
  deriving stock (Eq, Show, Generic)

statusShowAsTable :: [(Text, StatusShowAs)]
statusShowAsTable =
  [ ("select", ShowAsSelect),
    ("checkbox", ShowAsCheckbox)
  ]

instance FromJSON StatusShowAs where
  parseJSON = parseEnum "StatusShowAs" statusShowAsTable UnknownStatusShowAs

instance ToJSON StatusShowAs where
  toJSON = \case
    UnknownStatusShowAs t -> String t
    known -> enumToJSON statusShowAsTable known

-- | How a property is laid out on a card.
data CardPropertyWidthMode
  = WidthFullLine
  | WidthInline
  | -- | A value this library does not know yet; holds the raw string.
    UnknownCardPropertyWidthMode Text
  deriving stock (Eq, Show, Generic)

cardPropertyWidthModeTable :: [(Text, CardPropertyWidthMode)]
cardPropertyWidthModeTable =
  [ ("full_line", WidthFullLine),
    ("inline", WidthInline)
  ]

instance FromJSON CardPropertyWidthMode where
  parseJSON = parseEnum "CardPropertyWidthMode" cardPropertyWidthModeTable UnknownCardPropertyWidthMode

instance ToJSON CardPropertyWidthMode where
  toJSON = \case
    UnknownCardPropertyWidthMode t -> String t
    known -> enumToJSON cardPropertyWidthModeTable known

-- | Display format of a date property.
data DateFormat
  = DateFormatFull
  | DateFormatShort
  | DateFormatMonthDayYear
  | DateFormatDayMonthYear
  | DateFormatYearMonthDay
  | DateFormatRelative
  | -- | A value this library does not know yet; holds the raw string.
    UnknownDateFormat Text
  deriving stock (Eq, Show, Generic)

dateFormatTable :: [(Text, DateFormat)]
dateFormatTable =
  [ ("full", DateFormatFull),
    ("short", DateFormatShort),
    ("month_day_year", DateFormatMonthDayYear),
    ("day_month_year", DateFormatDayMonthYear),
    ("year_month_day", DateFormatYearMonthDay),
    ("relative", DateFormatRelative)
  ]

instance FromJSON DateFormat where
  parseJSON = parseEnum "DateFormat" dateFormatTable UnknownDateFormat

instance ToJSON DateFormat where
  toJSON = \case
    UnknownDateFormat t -> String t
    known -> enumToJSON dateFormatTable known

-- | Display format of the time part of a date property.
data TimeFormat
  = TimeFormat12Hour
  | TimeFormat24Hour
  | TimeFormatHidden
  | -- | A value this library does not know yet; holds the raw string.
    UnknownTimeFormat Text
  deriving stock (Eq, Show, Generic)

timeFormatTable :: [(Text, TimeFormat)]
timeFormatTable =
  [ ("12_hour", TimeFormat12Hour),
    ("24_hour", TimeFormat24Hour),
    ("hidden", TimeFormatHidden)
  ]

instance FromJSON TimeFormat where
  parseJSON = parseEnum "TimeFormat" timeFormatTable UnknownTimeFormat

instance ToJSON TimeFormat where
  toJSON = \case
    UnknownTimeFormat t -> String t
    known -> enumToJSON timeFormatTable known

-- | How sub-items are shown.
data SubtaskDisplayMode
  = SubtasksShow
  | SubtasksHidden
  | SubtasksFlattened
  | SubtasksDisabled
  | -- | A value this library does not know yet; holds the raw string.
    UnknownSubtaskDisplayMode Text
  deriving stock (Eq, Show, Generic)

subtaskDisplayModeTable :: [(Text, SubtaskDisplayMode)]
subtaskDisplayModeTable =
  [ ("show", SubtasksShow),
    ("hidden", SubtasksHidden),
    ("flattened", SubtasksFlattened),
    ("disabled", SubtasksDisabled)
  ]

instance FromJSON SubtaskDisplayMode where
  parseJSON = parseEnum "SubtaskDisplayMode" subtaskDisplayModeTable UnknownSubtaskDisplayMode

instance ToJSON SubtaskDisplayMode where
  toJSON = \case
    UnknownSubtaskDisplayMode t -> String t
    known -> enumToJSON subtaskDisplayModeTable known

-- | Which rows a filter applies to when sub-items are shown.
data SubtaskFilterScope
  = ScopeParents
  | ScopeParentsAndSubitems
  | ScopeSubitems
  | -- | A value this library does not know yet; holds the raw string.
    UnknownSubtaskFilterScope Text
  deriving stock (Eq, Show, Generic)

subtaskFilterScopeTable :: [(Text, SubtaskFilterScope)]
subtaskFilterScopeTable =
  [ ("parents", ScopeParents),
    ("parents_and_subitems", ScopeParentsAndSubitems),
    ("subitems", ScopeSubitems)
  ]

instance FromJSON SubtaskFilterScope where
  parseJSON = parseEnum "SubtaskFilterScope" subtaskFilterScopeTable UnknownSubtaskFilterScope

instance ToJSON SubtaskFilterScope where
  toJSON = \case
    UnknownSubtaskFilterScope t -> String t
    known -> enumToJSON subtaskFilterScopeTable known

-- | Source of a card cover image. @page_content_first@ appears only in responses.
data CoverType
  = CoverPageCover
  | CoverPageContent
  | CoverPageContentFirst
  | CoverProperty
  | -- | A value this library does not know yet; holds the raw string.
    UnknownCoverType Text
  deriving stock (Eq, Show, Generic)

coverTypeTable :: [(Text, CoverType)]
coverTypeTable =
  [ ("page_cover", CoverPageCover),
    ("page_content", CoverPageContent),
    ("page_content_first", CoverPageContentFirst),
    ("property", CoverProperty)
  ]

instance FromJSON CoverType where
  parseJSON = parseEnum "CoverType" coverTypeTable UnknownCoverType

instance ToJSON CoverType where
  toJSON = \case
    UnknownCoverType t -> String t
    known -> enumToJSON coverTypeTable known

-- | Card cover size.
data CoverSize
  = CoverSmall
  | CoverMedium
  | CoverLarge
  | -- | A value this library does not know yet; holds the raw string.
    UnknownCoverSize Text
  deriving stock (Eq, Show, Generic)

coverSizeTable :: [(Text, CoverSize)]
coverSizeTable =
  [ ("small", CoverSmall),
    ("medium", CoverMedium),
    ("large", CoverLarge)
  ]

instance FromJSON CoverSize where
  parseJSON = parseEnum "CoverSize" coverSizeTable UnknownCoverSize

instance ToJSON CoverSize where
  toJSON = \case
    UnknownCoverSize t -> String t
    known -> enumToJSON coverSizeTable known

-- | How a cover image is fitted.
data CoverAspect
  = AspectContain
  | AspectCover
  | -- | A value this library does not know yet; holds the raw string.
    UnknownCoverAspect Text
  deriving stock (Eq, Show, Generic)

coverAspectTable :: [(Text, CoverAspect)]
coverAspectTable =
  [ ("contain", AspectContain),
    ("cover", AspectCover)
  ]

instance FromJSON CoverAspect where
  parseJSON = parseEnum "CoverAspect" coverAspectTable UnknownCoverAspect

instance ToJSON CoverAspect where
  toJSON = \case
    UnknownCoverAspect t -> String t
    known -> enumToJSON coverAspectTable known

-- | Card layout of a board or gallery.
data CardLayout
  = CardLayoutList
  | CardLayoutCompact
  | -- | A value this library does not know yet; holds the raw string.
    UnknownCardLayout Text
  deriving stock (Eq, Show, Generic)

cardLayoutTable :: [(Text, CardLayout)]
cardLayoutTable =
  [ ("list", CardLayoutList),
    ("compact", CardLayoutCompact)
  ]

instance FromJSON CardLayout where
  parseJSON = parseEnum "CardLayout" cardLayoutTable UnknownCardLayout

instance ToJSON CardLayout where
  toJSON = \case
    UnknownCardLayout t -> String t
    known -> enumToJSON cardLayoutTable known

-- | Range shown by a calendar view.
data CalendarRange
  = RangeWeek
  | RangeMonth
  | -- | A value this library does not know yet; holds the raw string.
    UnknownCalendarRange Text
  deriving stock (Eq, Show, Generic)

calendarRangeTable :: [(Text, CalendarRange)]
calendarRangeTable =
  [ ("week", RangeWeek),
    ("month", RangeMonth)
  ]

instance FromJSON CalendarRange where
  parseJSON = parseEnum "CalendarRange" calendarRangeTable UnknownCalendarRange

instance ToJSON CalendarRange where
  toJSON = \case
    UnknownCalendarRange t -> String t
    known -> enumToJSON calendarRangeTable known

-- | Zoom level of a timeline view.
data TimelineZoomLevel
  = ZoomHours
  | ZoomDay
  | ZoomWeek
  | ZoomBiWeek
  | ZoomMonth
  | ZoomQuarter
  | ZoomYear
  | ZoomFiveYears
  | -- | A value this library does not know yet; holds the raw string.
    UnknownTimelineZoomLevel Text
  deriving stock (Eq, Show, Generic)

timelineZoomLevelTable :: [(Text, TimelineZoomLevel)]
timelineZoomLevelTable =
  [ ("hours", ZoomHours),
    ("day", ZoomDay),
    ("week", ZoomWeek),
    ("bi_week", ZoomBiWeek),
    ("month", ZoomMonth),
    ("quarter", ZoomQuarter),
    ("year", ZoomYear),
    ("5_years", ZoomFiveYears)
  ]

instance FromJSON TimelineZoomLevel where
  parseJSON = parseEnum "TimelineZoomLevel" timelineZoomLevelTable UnknownTimelineZoomLevel

instance ToJSON TimelineZoomLevel where
  toJSON = \case
    UnknownTimelineZoomLevel t -> String t
    known -> enumToJSON timelineZoomLevelTable known

-- =====================================================================
-- Shared pieces
-- =====================================================================

-- | Display settings of one property in a view.
data ViewPropertyConfig = ViewPropertyConfig
  { propertyId :: Text,
    -- | Response only; dropped when encoding
    propertyName :: Maybe Text,
    visible :: Maybe Bool,
    width :: Maybe Int,
    wrap :: Maybe Bool,
    statusShowAs :: Maybe StatusShowAs,
    cardPropertyWidthMode :: Maybe CardPropertyWidthMode,
    dateFormat :: Maybe DateFormat,
    timeFormat :: Maybe TimeFormat
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON ViewPropertyConfig where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON ViewPropertyConfig where
  toJSON = dropKeys ["property_name"] . genericToJSON aesonOptions

-- | Sub-item settings of a table view.
data SubtaskConfig = SubtaskConfig
  { propertyId :: Maybe Text,
    displayMode :: Maybe SubtaskDisplayMode,
    filterScope :: Maybe SubtaskFilterScope,
    toggleColumnId :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON SubtaskConfig where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON SubtaskConfig where
  toJSON = genericToJSON aesonOptions

-- | Card cover of a board or gallery view.
data CoverConfig = CoverConfig
  { type_ :: CoverType,
    -- | The files property to use when the type is 'CoverProperty'
    propertyId :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON CoverConfig where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON CoverConfig where
  toJSON = genericToJSON aesonOptions

-- =====================================================================
-- Group by
-- =====================================================================

-- | Group by a select or multi-select property.
data SelectGroupByConfig = SelectGroupByConfig
  { type_ :: SelectGroupKind,
    propertyId :: Text,
    sort :: GroupSort,
    -- | Response only; dropped when encoding
    propertyName :: Maybe Text,
    hideEmptyGroups :: Maybe Bool
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON SelectGroupByConfig where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON SelectGroupByConfig where
  toJSON = dropKeys ["property_name"] . genericToJSON aesonOptions

-- | Group by a status property.
data StatusGroupByConfig = StatusGroupByConfig
  { propertyId :: Text,
    groupBy :: StatusGroupMode,
    sort :: GroupSort,
    -- | Response only; dropped when encoding
    propertyName :: Maybe Text,
    hideEmptyGroups :: Maybe Bool
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON StatusGroupByConfig where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON StatusGroupByConfig where
  toJSON = dropKeys ["property_name"] . genericToJSON aesonOptions

-- | Group by a person, created-by or last-edited-by property.
data PersonGroupByConfig = PersonGroupByConfig
  { type_ :: PersonGroupKind,
    propertyId :: Text,
    sort :: GroupSort,
    -- | Response only; dropped when encoding
    propertyName :: Maybe Text,
    hideEmptyGroups :: Maybe Bool
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON PersonGroupByConfig where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON PersonGroupByConfig where
  toJSON = dropKeys ["property_name"] . genericToJSON aesonOptions

-- | Group by a relation property.
data RelationGroupByConfig = RelationGroupByConfig
  { propertyId :: Text,
    sort :: GroupSort,
    -- | Response only; dropped when encoding
    propertyName :: Maybe Text,
    hideEmptyGroups :: Maybe Bool
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON RelationGroupByConfig where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON RelationGroupByConfig where
  toJSON = dropKeys ["property_name"] . genericToJSON aesonOptions

-- | Group by a date, created-time or last-edited-time property.
data DateGroupByConfig = DateGroupByConfig
  { type_ :: DateGroupKind,
    propertyId :: Text,
    groupBy :: DateGranularity,
    sort :: GroupSort,
    -- | Response only; dropped when encoding
    propertyName :: Maybe Text,
    hideEmptyGroups :: Maybe Bool,
    -- | 0 (Sunday) or 1 (Monday)
    startDayOfWeek :: Maybe Int
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON DateGroupByConfig where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON DateGroupByConfig where
  toJSON = dropKeys ["property_name"] . genericToJSON aesonOptions

-- | Group by a text, title, URL, email or phone number property.
data TextGroupByConfig = TextGroupByConfig
  { type_ :: TextGroupKind,
    propertyId :: Text,
    groupBy :: TextGroupMode,
    sort :: GroupSort,
    -- | Response only; dropped when encoding
    propertyName :: Maybe Text,
    hideEmptyGroups :: Maybe Bool
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON TextGroupByConfig where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON TextGroupByConfig where
  toJSON = dropKeys ["property_name"] . genericToJSON aesonOptions

-- | Group by a number property, in ranges.
data NumberGroupByConfig = NumberGroupByConfig
  { propertyId :: Text,
    sort :: GroupSort,
    -- | Response only; dropped when encoding
    propertyName :: Maybe Text,
    hideEmptyGroups :: Maybe Bool,
    rangeStart :: Maybe Scientific,
    rangeEnd :: Maybe Scientific,
    rangeSize :: Maybe Scientific
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON NumberGroupByConfig where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON NumberGroupByConfig where
  toJSON = dropKeys ["property_name"] . genericToJSON aesonOptions

-- | Group by a checkbox property.
data CheckboxGroupByConfig = CheckboxGroupByConfig
  { propertyId :: Text,
    sort :: GroupSort,
    -- | Response only; dropped when encoding
    propertyName :: Maybe Text,
    hideEmptyGroups :: Maybe Bool
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON CheckboxGroupByConfig where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON CheckboxGroupByConfig where
  toJSON = dropKeys ["property_name"] . genericToJSON aesonOptions

-- | Group by a formula property, according to its result type.
data FormulaGroupByConfig = FormulaGroupByConfig
  { propertyId :: Text,
    groupBy :: FormulaSubGroupBy,
    -- | Response only; dropped when encoding
    propertyName :: Maybe Text,
    hideEmptyGroups :: Maybe Bool
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON FormulaGroupByConfig where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON FormulaGroupByConfig where
  toJSON = dropKeys ["property_name"] . genericToJSON aesonOptions

-- | Grouping of a date-valued formula.
data FormulaDateSubGroupBy = FormulaDateSubGroupBy
  { groupBy :: DateGranularity,
    sort :: GroupSort,
    startDayOfWeek :: Maybe Int
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON FormulaDateSubGroupBy where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON FormulaDateSubGroupBy where
  toJSON = genericToJSON aesonOptions

-- | Grouping of a text-valued formula.
data FormulaTextSubGroupBy = FormulaTextSubGroupBy
  { groupBy :: TextGroupMode,
    sort :: GroupSort
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON FormulaTextSubGroupBy where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON FormulaTextSubGroupBy where
  toJSON = genericToJSON aesonOptions

-- | Grouping of a number-valued formula.
data FormulaNumberSubGroupBy = FormulaNumberSubGroupBy
  { sort :: GroupSort,
    rangeStart :: Maybe Scientific,
    rangeEnd :: Maybe Scientific,
    rangeSize :: Maybe Scientific
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON FormulaNumberSubGroupBy where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON FormulaNumberSubGroupBy where
  toJSON = genericToJSON aesonOptions

-- | Grouping of a checkbox-valued formula.
newtype FormulaCheckboxSubGroupBy = FormulaCheckboxSubGroupBy
  { sort :: GroupSort
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON FormulaCheckboxSubGroupBy where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON FormulaCheckboxSubGroupBy where
  toJSON = genericToJSON aesonOptions

-- | How a formula group-by buckets values, by the formula's result type.
data FormulaSubGroupBy
  = FormulaDateGroup FormulaDateSubGroupBy
  | FormulaTextGroup FormulaTextSubGroupBy
  | FormulaNumberGroup FormulaNumberSubGroupBy
  | FormulaCheckboxGroup FormulaCheckboxSubGroupBy
  | -- | An unrecognised type or shape; sent back verbatim.
    UnknownFormulaGroup Value
  deriving stock (Eq, Show, Generic)

instance FromJSON FormulaSubGroupBy where
  parseJSON v = typed <|> pure (UnknownFormulaGroup v)
    where
      typed = flip (Aeson.withObject "FormulaSubGroupBy") v $ \o -> do
        t <- o .: "type"
        case (t :: Text) of
          "date" -> FormulaDateGroup <$> parseJSON v
          "text" -> FormulaTextGroup <$> parseJSON v
          "number" -> FormulaNumberGroup <$> parseJSON v
          "checkbox" -> FormulaCheckboxGroup <$> parseJSON v
          other -> fail ("unknown formula group-by type: " <> unpack other)

instance ToJSON FormulaSubGroupBy where
  toJSON = \case
    FormulaDateGroup c -> withType "date" (toJSON c)
    FormulaTextGroup c -> withType "text" (toJSON c)
    FormulaNumberGroup c -> withType "number" (toJSON c)
    FormulaCheckboxGroup c -> withType "checkbox" (toJSON c)
    UnknownFormulaGroup raw -> raw

-- | How a view groups its rows, by the grouped property's type.
data GroupByConfig
  = -- | @select@, @multi_select@
    SelectGroupBy SelectGroupByConfig
  | -- | @status@
    StatusGroupBy StatusGroupByConfig
  | -- | @person@, @created_by@, @last_edited_by@
    PersonGroupBy PersonGroupByConfig
  | -- | @relation@
    RelationGroupBy RelationGroupByConfig
  | -- | @date@, @created_time@, @last_edited_time@
    DateGroupBy DateGroupByConfig
  | -- | @text@, @title@, @url@, @email@, @phone_number@
    TextGroupBy TextGroupByConfig
  | -- | @number@
    NumberGroupBy NumberGroupByConfig
  | -- | @checkbox@
    CheckboxGroupBy CheckboxGroupByConfig
  | -- | @formula@
    FormulaGroupBy FormulaGroupByConfig
  | -- | An unrecognised type or shape; sent back verbatim.
    UnknownGroupBy Value
  deriving stock (Eq, Show, Generic)

instance FromJSON GroupByConfig where
  parseJSON v = typed <|> pure (UnknownGroupBy v)
    where
      typed = flip (Aeson.withObject "GroupByConfig") v $ \o -> do
        t <- o .: "type"
        case (t :: Text) of
          "select" -> SelectGroupBy <$> parseJSON v
          "multi_select" -> SelectGroupBy <$> parseJSON v
          "status" -> StatusGroupBy <$> parseJSON v
          "person" -> PersonGroupBy <$> parseJSON v
          "created_by" -> PersonGroupBy <$> parseJSON v
          "last_edited_by" -> PersonGroupBy <$> parseJSON v
          "relation" -> RelationGroupBy <$> parseJSON v
          "date" -> DateGroupBy <$> parseJSON v
          "created_time" -> DateGroupBy <$> parseJSON v
          "last_edited_time" -> DateGroupBy <$> parseJSON v
          "text" -> TextGroupBy <$> parseJSON v
          "title" -> TextGroupBy <$> parseJSON v
          "url" -> TextGroupBy <$> parseJSON v
          "email" -> TextGroupBy <$> parseJSON v
          "phone_number" -> TextGroupBy <$> parseJSON v
          "number" -> NumberGroupBy <$> parseJSON v
          "checkbox" -> CheckboxGroupBy <$> parseJSON v
          "formula" -> FormulaGroupBy <$> parseJSON v
          other -> fail ("unknown group-by type: " <> unpack other)

instance ToJSON GroupByConfig where
  toJSON = \case
    -- The multi-kind records write "type" from their own type_ field
    SelectGroupBy c -> toJSON c
    StatusGroupBy c -> withType "status" (toJSON c)
    PersonGroupBy c -> toJSON c
    RelationGroupBy c -> withType "relation" (toJSON c)
    DateGroupBy c -> toJSON c
    TextGroupBy c -> toJSON c
    NumberGroupBy c -> withType "number" (toJSON c)
    CheckboxGroupBy c -> withType "checkbox" (toJSON c)
    FormulaGroupBy c -> withType "formula" (toJSON c)
    UnknownGroupBy raw -> raw

-- =====================================================================
-- View configurations
-- =====================================================================

-- | Table view settings.
data TableViewConfig = TableViewConfig
  { properties :: Clearable (Vector ViewPropertyConfig),
    groupBy :: Clearable GroupByConfig,
    subtasks :: Clearable SubtaskConfig,
    wrapCells :: Maybe Bool,
    frozenColumnIndex :: Maybe Int,
    showVerticalLines :: Maybe Bool
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON TableViewConfig where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON TableViewConfig where
  toJSON = genericToJSON aesonOptions

-- | Board view settings.
data BoardViewConfig = BoardViewConfig
  { groupBy :: GroupByConfig,
    subGroupBy :: Clearable GroupByConfig,
    properties :: Clearable (Vector ViewPropertyConfig),
    cover :: Clearable CoverConfig,
    coverSize :: Clearable CoverSize,
    coverAspect :: Clearable CoverAspect,
    cardLayout :: Clearable CardLayout
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON BoardViewConfig where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON BoardViewConfig where
  toJSON = genericToJSON aesonOptions

-- | Calendar view settings.
data CalendarViewConfig = CalendarViewConfig
  { datePropertyId :: Text,
    -- | Response only; dropped when encoding
    datePropertyName :: Maybe Text,
    properties :: Clearable (Vector ViewPropertyConfig),
    viewRange :: Clearable CalendarRange,
    showWeekends :: Clearable Bool
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON CalendarViewConfig where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON CalendarViewConfig where
  toJSON = dropKeys ["date_property_name"] . genericToJSON aesonOptions

-- | Zoom and scroll position of a timeline.
data TimelinePreference = TimelinePreference
  { zoomLevel :: TimelineZoomLevel,
    -- | Milliseconds since the Unix epoch
    centerTimestamp :: Maybe Integer
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON TimelinePreference where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON TimelinePreference where
  toJSON = genericToJSON aesonOptions

-- | Dependency arrows of a timeline.
newtype TimelineArrowsBy = TimelineArrowsBy
  { -- | 'Clear' disables arrows
    propertyId :: Clearable Text
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON TimelineArrowsBy where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON TimelineArrowsBy where
  toJSON = genericToJSON aesonOptions

-- | Timeline view settings.
data TimelineViewConfig = TimelineViewConfig
  { datePropertyId :: Text,
    -- | Response only; dropped when encoding
    datePropertyName :: Maybe Text,
    endDatePropertyId :: Clearable Text,
    -- | Response only; dropped when encoding
    endDatePropertyName :: Maybe Text,
    properties :: Clearable (Vector ViewPropertyConfig),
    showTable :: Clearable Bool,
    tableProperties :: Clearable (Vector ViewPropertyConfig),
    preference :: Clearable TimelinePreference,
    arrowsBy :: Clearable TimelineArrowsBy,
    colorBy :: Clearable Bool
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON TimelineViewConfig where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON TimelineViewConfig where
  toJSON = dropKeys ["date_property_name", "end_date_property_name"] . genericToJSON aesonOptions

-- | Gallery view settings.
data GalleryViewConfig = GalleryViewConfig
  { properties :: Clearable (Vector ViewPropertyConfig),
    cover :: Clearable CoverConfig,
    coverSize :: Clearable CoverSize,
    coverAspect :: Clearable CoverAspect,
    cardLayout :: Clearable CardLayout
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON GalleryViewConfig where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON GalleryViewConfig where
  toJSON = genericToJSON aesonOptions

-- | List view settings.
newtype ListViewConfig = ListViewConfig
  { properties :: Clearable (Vector ViewPropertyConfig)
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON ListViewConfig where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON ListViewConfig where
  toJSON = genericToJSON aesonOptions

-- | A view's layout configuration, discriminated by @type@.
data ViewConfig
  = TableConfig TableViewConfig
  | BoardConfig BoardViewConfig
  | CalendarConfig CalendarViewConfig
  | TimelineConfig TimelineViewConfig
  | GalleryConfig GalleryViewConfig
  | ListConfig ListViewConfig
  | -- | Any other type, or a shape the typed parse rejected; sent back verbatim.
    UnknownViewConfig Value
  deriving stock (Eq, Show, Generic)

instance FromJSON ViewConfig where
  parseJSON v = typed <|> pure (UnknownViewConfig v)
    where
      typed = flip (Aeson.withObject "ViewConfig") v $ \o -> do
        t <- o .: "type"
        case (t :: Text) of
          "table" -> TableConfig <$> parseJSON v
          "board" -> BoardConfig <$> parseJSON v
          "calendar" -> CalendarConfig <$> parseJSON v
          "timeline" -> TimelineConfig <$> parseJSON v
          "gallery" -> GalleryConfig <$> parseJSON v
          "list" -> ListConfig <$> parseJSON v
          other -> fail ("unknown view configuration type: " <> unpack other)

instance ToJSON ViewConfig where
  toJSON = \case
    TableConfig c -> withType "table" (toJSON c)
    BoardConfig c -> withType "board" (toJSON c)
    CalendarConfig c -> withType "calendar" (toJSON c)
    TimelineConfig c -> withType "timeline" (toJSON c)
    GalleryConfig c -> withType "gallery" (toJSON c)
    ListConfig c -> withType "list" (toJSON c)
    UnknownViewConfig raw -> raw
