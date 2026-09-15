-- | Typed query filters and sorts for Notion database and data source queries.
--
-- This module provides a type-safe DSL for constructing filter and sort
-- conditions, replacing raw @Value@ construction.
--
-- Example usage:
--
-- @
-- let myFilter = And
--       [ PropertyFilter "Status" (SelectCondition (SelectEquals "Done"))
--       , PropertyFilter "Priority" (SelectCondition (SelectEquals "High"))
--       ]
--     mySorts = [PropertySort "Name" Ascending]
-- @
module Notion.V1.Filter
  ( -- * Filters
    Filter (..),
    PropertyCondition (..),
    TimestampType (..),

    -- * Filter conditions
    TextCondition (..),
    NumberCondition (..),
    CheckboxCondition (..),
    SelectCondition (..),
    MultiSelectCondition (..),
    DateCondition (..),
    PeopleCondition (..),
    FilesCondition (..),
    RelationCondition (..),
    StatusCondition (..),
    UniqueIdCondition (..),
    VerificationCondition (..),
    VerificationState (..),
    FormulaCondition (..),
    RollupCondition (..),

    -- * Relative dates
    RelativeDate (..),
    relativeDate,

    -- * Sorts
    Sort (..),
    SortDirection (..),
  )
where

import Control.Applicative ((<|>))
import Data.Aeson ((.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Parser)
import Data.Foldable (asum)
import Data.Scientific (Scientific)
import Notion.Prelude

-- | Timestamp type for timestamp filters and sorts.
data TimestampType
  = FilterCreatedTime
  | FilterLastEditedTime
  deriving stock (Eq, Show, Generic)

timestampTypeToText :: TimestampType -> Text
timestampTypeToText FilterCreatedTime = "created_time"
timestampTypeToText FilterLastEditedTime = "last_edited_time"

parseTimestampType :: Text -> Parser TimestampType
parseTimestampType = \case
  "created_time" -> pure FilterCreatedTime
  "last_edited_time" -> pure FilterLastEditedTime
  other -> fail ("unknown timestamp: " <> unpack other)

-- | Top-level filter type for querying databases and data sources.
--
-- Filters can be compound (@And@ / @Or@, nesting up to 2 levels per Notion API),
-- property filters (targeting a named property), or timestamp filters.
data Filter
  = And [Filter]
  | Or [Filter]
  | PropertyFilter Text PropertyCondition
  | TimestampFilter TimestampType DateCondition
  | -- | A filter shape this library does not model; the raw JSON is kept and re-sent unchanged.
    UnknownFilter Value
  deriving stock (Eq, Show, Generic)

instance ToJSON Filter where
  toJSON (UnknownFilter v) = v
  toJSON (And filters) = Aeson.object ["and" .= filters]
  toJSON (Or filters) = Aeson.object ["or" .= filters]
  toJSON (PropertyFilter propName condition) =
    let condObj = propertyConditionToObject condition
     in Aeson.object $ ["property" .= propName] <> condObj
  toJSON (TimestampFilter tsType condition) =
    let tsKey = timestampTypeToText tsType
     in Aeson.object
          [ "timestamp" .= tsKey,
            Key.fromText tsKey .= dateConditionToValue condition
          ]

-- | Inverts the 'ToJSON' encoding. Shapes the DSL cannot express decode to 'UnknownFilter'.
instance FromJSON Filter where
  parseJSON v = case v of
    Object o ->
      asum
        [ And <$> o .: "and",
          Or <$> o .: "or",
          do
            ts <- o .: "timestamp"
            tsType <- parseTimestampType ts
            cond <- o .: Key.fromText ts >>= parseDateCondition
            pure (TimestampFilter tsType cond),
          PropertyFilter <$> o .: "property" <*> parsePropertyCondition o,
          pure (UnknownFilter v)
        ]
    _ -> pure (UnknownFilter v)

-- | Property-type-specific filter condition.
--
-- Each constructor maps to the JSON key the Notion API expects
-- (e.g., 'TitleCondition' serializes under @\"title\"@).
data PropertyCondition
  = TitleCondition TextCondition
  | RichTextCondition TextCondition
  | NumberCondition NumberCondition
  | CheckboxCondition CheckboxCondition
  | SelectCondition SelectCondition
  | MultiSelectCondition MultiSelectCondition
  | DateCondition DateCondition
  | PeopleCondition PeopleCondition
  | FilesCondition FilesCondition
  | RelationCondition RelationCondition
  | StatusCondition StatusCondition
  | UniqueIdCondition UniqueIdCondition
  | VerificationCondition VerificationCondition
  | FormulaCondition FormulaCondition
  | RollupCondition RollupCondition
  | CreatedTimeCondition DateCondition
  | CreatedByCondition PeopleCondition
  | LastEditedTimeCondition DateCondition
  | LastEditedByCondition PeopleCondition
  | PhoneNumberCondition TextCondition
  | UrlCondition TextCondition
  | EmailCondition TextCondition
  | -- | A condition this library does not model: the condition key and its raw value.
    UnknownCondition Text Value
  deriving stock (Eq, Show, Generic)

-- | Convert a PropertyCondition to key-value pairs for inclusion in a JSON object.
propertyConditionToObject :: PropertyCondition -> [(Aeson.Key, Aeson.Value)]
propertyConditionToObject = \case
  TitleCondition c -> [("title", textConditionToValue c)]
  RichTextCondition c -> [("rich_text", textConditionToValue c)]
  NumberCondition c -> [("number", numberConditionToValue c)]
  CheckboxCondition c -> [("checkbox", checkboxConditionToValue c)]
  SelectCondition c -> [("select", selectConditionToValue c)]
  MultiSelectCondition c -> [("multi_select", multiSelectConditionToValue c)]
  DateCondition c -> [("date", dateConditionToValue c)]
  PeopleCondition c -> [("people", peopleConditionToValue c)]
  FilesCondition c -> [("files", filesConditionToValue c)]
  RelationCondition c -> [("relation", relationConditionToValue c)]
  StatusCondition c -> [("status", statusConditionToValue c)]
  UniqueIdCondition c -> [("unique_id", uniqueIdConditionToValue c)]
  VerificationCondition c -> [("verification", verificationConditionToValue c)]
  FormulaCondition c -> [("formula", formulaConditionToValue c)]
  RollupCondition c -> [("rollup", rollupConditionToValue c)]
  CreatedTimeCondition c -> [("created_time", dateConditionToValue c)]
  CreatedByCondition c -> [("created_by", peopleConditionToValue c)]
  LastEditedTimeCondition c -> [("last_edited_time", dateConditionToValue c)]
  LastEditedByCondition c -> [("last_edited_by", peopleConditionToValue c)]
  PhoneNumberCondition c -> [("phone_number", textConditionToValue c)]
  UrlCondition c -> [("url", textConditionToValue c)]
  EmailCondition c -> [("email", textConditionToValue c)]
  UnknownCondition k v -> [(Key.fromText k, v)]

-- | Encodes a condition as the object Notion uses for quick filters,
-- e.g. @{"select":{"equals":"High"}}@.
instance ToJSON PropertyCondition where
  toJSON c = Aeson.object (propertyConditionToObject c)

instance FromJSON PropertyCondition where
  parseJSON = Aeson.withObject "PropertyCondition" parsePropertyCondition

-- | Finds the property-type key (title, rich_text, number, …) and parses its condition.
--
-- The optional @type@ discriminator wins when present. Otherwise the first known key is used,
-- and failing that, the only key other than @property@ and @type@. A known key whose condition
-- does not parse, or an unknown key, decodes to 'UnknownCondition'. An object with no candidate
-- key fails.
parsePropertyCondition :: Aeson.Object -> Parser PropertyCondition
parsePropertyCondition o = do
  discriminator <- o .:? "type"
  let known = filter (\k -> KeyMap.member (Key.fromText k) o) (map fst conditionParsers)
      others = filter (`notElem` ["property", "type"]) (map Key.toText (KeyMap.keys o))
      chosen = case discriminator of
        Just k | KeyMap.member (Key.fromText k) o -> Just k
        _ -> case (known, others) of
          (k : _, _) -> Just k
          ([], [k]) -> Just k
          _ -> Nothing
  case chosen of
    Nothing -> fail "no filter condition key found"
    Just k -> do
      raw <- o .: Key.fromText k
      case lookup k conditionParsers of
        Just parser -> parser raw <|> pure (UnknownCondition k raw)
        Nothing -> pure (UnknownCondition k raw)

-- | Condition key and its parser, in the order keys are tried.
conditionParsers :: [(Text, Value -> Parser PropertyCondition)]
conditionParsers =
  [ ("title", fmap TitleCondition . parseTextCondition),
    ("rich_text", fmap RichTextCondition . parseTextCondition),
    ("number", fmap NumberCondition . parseNumberCondition),
    ("checkbox", fmap CheckboxCondition . parseCheckboxCondition),
    ("select", fmap SelectCondition . parseSelectCondition),
    ("multi_select", fmap MultiSelectCondition . parseMultiSelectCondition),
    ("status", fmap StatusCondition . parseStatusCondition),
    ("date", fmap DateCondition . parseDateCondition),
    ("people", fmap PeopleCondition . parsePeopleCondition),
    ("files", fmap FilesCondition . parseFilesCondition),
    ("url", fmap UrlCondition . parseTextCondition),
    ("email", fmap EmailCondition . parseTextCondition),
    ("phone_number", fmap PhoneNumberCondition . parseTextCondition),
    ("relation", fmap RelationCondition . parseRelationCondition),
    ("created_by", fmap CreatedByCondition . parsePeopleCondition),
    ("created_time", fmap CreatedTimeCondition . parseDateCondition),
    ("last_edited_by", fmap LastEditedByCondition . parsePeopleCondition),
    ("last_edited_time", fmap LastEditedTimeCondition . parseDateCondition),
    ("formula", fmap FormulaCondition . parseFormulaCondition),
    ("unique_id", fmap UniqueIdCondition . parseUniqueIdCondition),
    ("rollup", fmap RollupCondition . parseRollupCondition),
    ("verification", fmap VerificationCondition . parseVerificationCondition)
  ]

-- | Requires the flag key to hold JSON @true@ (Notion encodes @is_empty@ as @{"is_empty": true}@).
flagKey :: Aeson.Object -> Aeson.Key -> Parser ()
flagKey c k = do
  b <- c .: k
  if b then pure () else fail ("expected true for " <> show k)

-- | Requires the key to be present (relative dates are encoded as @{"next_week": {}}@).
emptyKey :: Aeson.Object -> Aeson.Key -> Parser ()
emptyKey c k = () <$ (c .: k :: Parser Value)

-- | Text filter conditions for title, rich_text, phone_number, url, and email properties.
data TextCondition
  = TextEquals Text
  | TextDoesNotEqual Text
  | TextContains Text
  | TextDoesNotContain Text
  | TextStartsWith Text
  | TextEndsWith Text
  | TextIsEmpty
  | TextIsNotEmpty
  deriving stock (Eq, Show, Generic)

textConditionToValue :: TextCondition -> Aeson.Value
textConditionToValue = \case
  TextEquals v -> Aeson.object ["equals" .= v]
  TextDoesNotEqual v -> Aeson.object ["does_not_equal" .= v]
  TextContains v -> Aeson.object ["contains" .= v]
  TextDoesNotContain v -> Aeson.object ["does_not_contain" .= v]
  TextStartsWith v -> Aeson.object ["starts_with" .= v]
  TextEndsWith v -> Aeson.object ["ends_with" .= v]
  TextIsEmpty -> Aeson.object ["is_empty" .= True]
  TextIsNotEmpty -> Aeson.object ["is_not_empty" .= True]

parseTextCondition :: Value -> Parser TextCondition
parseTextCondition = Aeson.withObject "TextCondition" $ \c ->
  asum
    [ TextEquals <$> c .: "equals",
      TextDoesNotEqual <$> c .: "does_not_equal",
      TextContains <$> c .: "contains",
      TextDoesNotContain <$> c .: "does_not_contain",
      TextStartsWith <$> c .: "starts_with",
      TextEndsWith <$> c .: "ends_with",
      TextIsEmpty <$ flagKey c "is_empty",
      TextIsNotEmpty <$ flagKey c "is_not_empty"
    ]

-- | Number filter conditions.
data NumberCondition
  = NumEquals Scientific
  | NumDoesNotEqual Scientific
  | NumGreaterThan Scientific
  | NumGreaterThanOrEqualTo Scientific
  | NumLessThan Scientific
  | NumLessThanOrEqualTo Scientific
  | NumIsEmpty
  | NumIsNotEmpty
  deriving stock (Eq, Show, Generic)

numberConditionToValue :: NumberCondition -> Aeson.Value
numberConditionToValue = \case
  NumEquals v -> Aeson.object ["equals" .= v]
  NumDoesNotEqual v -> Aeson.object ["does_not_equal" .= v]
  NumGreaterThan v -> Aeson.object ["greater_than" .= v]
  NumGreaterThanOrEqualTo v -> Aeson.object ["greater_than_or_equal_to" .= v]
  NumLessThan v -> Aeson.object ["less_than" .= v]
  NumLessThanOrEqualTo v -> Aeson.object ["less_than_or_equal_to" .= v]
  NumIsEmpty -> Aeson.object ["is_empty" .= True]
  NumIsNotEmpty -> Aeson.object ["is_not_empty" .= True]

parseNumberCondition :: Value -> Parser NumberCondition
parseNumberCondition = Aeson.withObject "NumberCondition" $ \c ->
  asum
    [ NumEquals <$> c .: "equals",
      NumDoesNotEqual <$> c .: "does_not_equal",
      NumGreaterThan <$> c .: "greater_than",
      NumGreaterThanOrEqualTo <$> c .: "greater_than_or_equal_to",
      NumLessThan <$> c .: "less_than",
      NumLessThanOrEqualTo <$> c .: "less_than_or_equal_to",
      NumIsEmpty <$ flagKey c "is_empty",
      NumIsNotEmpty <$ flagKey c "is_not_empty"
    ]

-- | Checkbox filter conditions.
data CheckboxCondition
  = CheckboxEquals Bool
  | CheckboxDoesNotEqual Bool
  deriving stock (Eq, Show, Generic)

checkboxConditionToValue :: CheckboxCondition -> Aeson.Value
checkboxConditionToValue = \case
  CheckboxEquals v -> Aeson.object ["equals" .= v]
  CheckboxDoesNotEqual v -> Aeson.object ["does_not_equal" .= v]

parseCheckboxCondition :: Value -> Parser CheckboxCondition
parseCheckboxCondition = Aeson.withObject "CheckboxCondition" $ \c ->
  asum
    [ CheckboxEquals <$> c .: "equals",
      CheckboxDoesNotEqual <$> c .: "does_not_equal"
    ]

-- | Select filter conditions.
data SelectCondition
  = SelectEquals Text
  | SelectDoesNotEqual Text
  | -- | @{"equals": [..]}@: any of the options.
    SelectEqualsAny (NonEmpty Text)
  | -- | @{"does_not_equal": [..]}@: none of the options.
    SelectDoesNotEqualAny (NonEmpty Text)
  | SelectIsEmpty
  | SelectIsNotEmpty
  deriving stock (Eq, Show, Generic)

selectConditionToValue :: SelectCondition -> Aeson.Value
selectConditionToValue = \case
  SelectEquals v -> Aeson.object ["equals" .= v]
  SelectDoesNotEqual v -> Aeson.object ["does_not_equal" .= v]
  SelectEqualsAny vs -> Aeson.object ["equals" .= vs]
  SelectDoesNotEqualAny vs -> Aeson.object ["does_not_equal" .= vs]
  SelectIsEmpty -> Aeson.object ["is_empty" .= True]
  SelectIsNotEmpty -> Aeson.object ["is_not_empty" .= True]

parseSelectCondition :: Value -> Parser SelectCondition
parseSelectCondition = Aeson.withObject "SelectCondition" $ \c ->
  asum
    [ SelectEquals <$> c .: "equals",
      SelectDoesNotEqual <$> c .: "does_not_equal",
      SelectEqualsAny <$> c .: "equals",
      SelectDoesNotEqualAny <$> c .: "does_not_equal",
      SelectIsEmpty <$ flagKey c "is_empty",
      SelectIsNotEmpty <$ flagKey c "is_not_empty"
    ]

-- | Multi-select filter conditions.
data MultiSelectCondition
  = MultiSelectContains Text
  | MultiSelectDoesNotContain Text
  | -- | @{"contains": [..]}@
    MultiSelectContainsAny (NonEmpty Text)
  | -- | @{"does_not_contain": [..]}@
    MultiSelectDoesNotContainAny (NonEmpty Text)
  | MultiSelectIsEmpty
  | MultiSelectIsNotEmpty
  deriving stock (Eq, Show, Generic)

multiSelectConditionToValue :: MultiSelectCondition -> Aeson.Value
multiSelectConditionToValue = \case
  MultiSelectContains v -> Aeson.object ["contains" .= v]
  MultiSelectDoesNotContain v -> Aeson.object ["does_not_contain" .= v]
  MultiSelectContainsAny vs -> Aeson.object ["contains" .= vs]
  MultiSelectDoesNotContainAny vs -> Aeson.object ["does_not_contain" .= vs]
  MultiSelectIsEmpty -> Aeson.object ["is_empty" .= True]
  MultiSelectIsNotEmpty -> Aeson.object ["is_not_empty" .= True]

parseMultiSelectCondition :: Value -> Parser MultiSelectCondition
parseMultiSelectCondition = Aeson.withObject "MultiSelectCondition" $ \c ->
  asum
    [ MultiSelectContains <$> c .: "contains",
      MultiSelectDoesNotContain <$> c .: "does_not_contain",
      MultiSelectContainsAny <$> c .: "contains",
      MultiSelectDoesNotContainAny <$> c .: "does_not_contain",
      MultiSelectIsEmpty <$ flagKey c "is_empty",
      MultiSelectIsNotEmpty <$ flagKey c "is_not_empty"
    ]

-- | Date filter conditions. Also used for timestamp filters and created_time/last_edited_time.
--
-- Text values are ISO 8601 date strings (e.g., @\"2024-01-15\"@ or @\"2024-01-15T00:00:00Z\"@)
-- or relative date keywords rendered with 'relativeDate'.
data DateCondition
  = DateAfter Text
  | DateBefore Text
  | DateEquals Text
  | DateOnOrAfter Text
  | DateOnOrBefore Text
  | DateIsEmpty
  | DateIsNotEmpty
  | DateNextWeek
  | DateNextMonth
  | DateNextYear
  | DateThisWeek
  | DateThisMonth
  | DateThisYear
  | DatePastWeek
  | DatePastMonth
  | DatePastYear
  deriving stock (Eq, Show, Generic)

dateConditionToValue :: DateCondition -> Aeson.Value
dateConditionToValue = \case
  DateAfter v -> Aeson.object ["after" .= v]
  DateBefore v -> Aeson.object ["before" .= v]
  DateEquals v -> Aeson.object ["equals" .= v]
  DateOnOrAfter v -> Aeson.object ["on_or_after" .= v]
  DateOnOrBefore v -> Aeson.object ["on_or_before" .= v]
  DateIsEmpty -> Aeson.object ["is_empty" .= True]
  DateIsNotEmpty -> Aeson.object ["is_not_empty" .= True]
  DateNextWeek -> Aeson.object ["next_week" .= Aeson.object []]
  DateNextMonth -> Aeson.object ["next_month" .= Aeson.object []]
  DateNextYear -> Aeson.object ["next_year" .= Aeson.object []]
  DateThisWeek -> Aeson.object ["this_week" .= Aeson.object []]
  DateThisMonth -> Aeson.object ["this_month" .= Aeson.object []]
  DateThisYear -> Aeson.object ["this_year" .= Aeson.object []]
  DatePastWeek -> Aeson.object ["past_week" .= Aeson.object []]
  DatePastMonth -> Aeson.object ["past_month" .= Aeson.object []]
  DatePastYear -> Aeson.object ["past_year" .= Aeson.object []]

parseDateCondition :: Value -> Parser DateCondition
parseDateCondition = Aeson.withObject "DateCondition" $ \c ->
  asum
    [ DateAfter <$> c .: "after",
      DateBefore <$> c .: "before",
      DateEquals <$> c .: "equals",
      DateOnOrAfter <$> c .: "on_or_after",
      DateOnOrBefore <$> c .: "on_or_before",
      DateIsEmpty <$ flagKey c "is_empty",
      DateIsNotEmpty <$ flagKey c "is_not_empty",
      DateNextWeek <$ emptyKey c "next_week",
      DateNextMonth <$ emptyKey c "next_month",
      DateNextYear <$ emptyKey c "next_year",
      DateThisWeek <$ emptyKey c "this_week",
      DateThisMonth <$ emptyKey c "this_month",
      DateThisYear <$ emptyKey c "this_year",
      DatePastWeek <$ emptyKey c "past_week",
      DatePastMonth <$ emptyKey c "past_month",
      DatePastYear <$ emptyKey c "past_year"
    ]

-- | People filter conditions. The Text value is a user UUID.
data PeopleCondition
  = PeopleContains Text
  | PeopleDoesNotContain Text
  | PeopleIsEmpty
  | PeopleIsNotEmpty
  deriving stock (Eq, Show, Generic)

peopleConditionToValue :: PeopleCondition -> Aeson.Value
peopleConditionToValue = \case
  PeopleContains v -> Aeson.object ["contains" .= v]
  PeopleDoesNotContain v -> Aeson.object ["does_not_contain" .= v]
  PeopleIsEmpty -> Aeson.object ["is_empty" .= True]
  PeopleIsNotEmpty -> Aeson.object ["is_not_empty" .= True]

parsePeopleCondition :: Value -> Parser PeopleCondition
parsePeopleCondition = Aeson.withObject "PeopleCondition" $ \c ->
  asum
    [ PeopleContains <$> c .: "contains",
      PeopleDoesNotContain <$> c .: "does_not_contain",
      PeopleIsEmpty <$ flagKey c "is_empty",
      PeopleIsNotEmpty <$ flagKey c "is_not_empty"
    ]

-- | Files filter conditions.
data FilesCondition
  = FilesIsEmpty
  | FilesIsNotEmpty
  deriving stock (Eq, Show, Generic)

filesConditionToValue :: FilesCondition -> Aeson.Value
filesConditionToValue = \case
  FilesIsEmpty -> Aeson.object ["is_empty" .= True]
  FilesIsNotEmpty -> Aeson.object ["is_not_empty" .= True]

parseFilesCondition :: Value -> Parser FilesCondition
parseFilesCondition = Aeson.withObject "FilesCondition" $ \c ->
  asum
    [ FilesIsEmpty <$ flagKey c "is_empty",
      FilesIsNotEmpty <$ flagKey c "is_not_empty"
    ]

-- | Relation filter conditions. The Text value is a page UUID.
data RelationCondition
  = RelationContains Text
  | RelationDoesNotContain Text
  | RelationIsEmpty
  | RelationIsNotEmpty
  deriving stock (Eq, Show, Generic)

relationConditionToValue :: RelationCondition -> Aeson.Value
relationConditionToValue = \case
  RelationContains v -> Aeson.object ["contains" .= v]
  RelationDoesNotContain v -> Aeson.object ["does_not_contain" .= v]
  RelationIsEmpty -> Aeson.object ["is_empty" .= True]
  RelationIsNotEmpty -> Aeson.object ["is_not_empty" .= True]

parseRelationCondition :: Value -> Parser RelationCondition
parseRelationCondition = Aeson.withObject "RelationCondition" $ \c ->
  asum
    [ RelationContains <$> c .: "contains",
      RelationDoesNotContain <$> c .: "does_not_contain",
      RelationIsEmpty <$ flagKey c "is_empty",
      RelationIsNotEmpty <$ flagKey c "is_not_empty"
    ]

-- | Status filter conditions.
data StatusCondition
  = StatusEquals Text
  | StatusDoesNotEqual Text
  | -- | @{"equals": [..]}@
    StatusEqualsAny (NonEmpty Text)
  | -- | @{"does_not_equal": [..]}@
    StatusDoesNotEqualAny (NonEmpty Text)
  | StatusIsEmpty
  | StatusIsNotEmpty
  deriving stock (Eq, Show, Generic)

statusConditionToValue :: StatusCondition -> Aeson.Value
statusConditionToValue = \case
  StatusEquals v -> Aeson.object ["equals" .= v]
  StatusDoesNotEqual v -> Aeson.object ["does_not_equal" .= v]
  StatusEqualsAny vs -> Aeson.object ["equals" .= vs]
  StatusDoesNotEqualAny vs -> Aeson.object ["does_not_equal" .= vs]
  StatusIsEmpty -> Aeson.object ["is_empty" .= True]
  StatusIsNotEmpty -> Aeson.object ["is_not_empty" .= True]

parseStatusCondition :: Value -> Parser StatusCondition
parseStatusCondition = Aeson.withObject "StatusCondition" $ \c ->
  asum
    [ StatusEquals <$> c .: "equals",
      StatusDoesNotEqual <$> c .: "does_not_equal",
      StatusEqualsAny <$> c .: "equals",
      StatusDoesNotEqualAny <$> c .: "does_not_equal",
      StatusIsEmpty <$ flagKey c "is_empty",
      StatusIsNotEmpty <$ flagKey c "is_not_empty"
    ]

-- | Unique ID filter conditions.
data UniqueIdCondition
  = UniqueIdEquals Scientific
  | UniqueIdDoesNotEqual Scientific
  | UniqueIdGreaterThan Scientific
  | UniqueIdGreaterThanOrEqualTo Scientific
  | UniqueIdLessThan Scientific
  | UniqueIdLessThanOrEqualTo Scientific
  | UniqueIdIsEmpty
  | UniqueIdIsNotEmpty
  deriving stock (Eq, Show, Generic)

uniqueIdConditionToValue :: UniqueIdCondition -> Aeson.Value
uniqueIdConditionToValue = \case
  UniqueIdEquals v -> Aeson.object ["equals" .= v]
  UniqueIdDoesNotEqual v -> Aeson.object ["does_not_equal" .= v]
  UniqueIdGreaterThan v -> Aeson.object ["greater_than" .= v]
  UniqueIdGreaterThanOrEqualTo v -> Aeson.object ["greater_than_or_equal_to" .= v]
  UniqueIdLessThan v -> Aeson.object ["less_than" .= v]
  UniqueIdLessThanOrEqualTo v -> Aeson.object ["less_than_or_equal_to" .= v]
  UniqueIdIsEmpty -> Aeson.object ["is_empty" .= True]
  UniqueIdIsNotEmpty -> Aeson.object ["is_not_empty" .= True]

parseUniqueIdCondition :: Value -> Parser UniqueIdCondition
parseUniqueIdCondition = Aeson.withObject "UniqueIdCondition" $ \c ->
  asum
    [ UniqueIdEquals <$> c .: "equals",
      UniqueIdDoesNotEqual <$> c .: "does_not_equal",
      UniqueIdGreaterThan <$> c .: "greater_than",
      UniqueIdGreaterThanOrEqualTo <$> c .: "greater_than_or_equal_to",
      UniqueIdLessThan <$> c .: "less_than",
      UniqueIdLessThanOrEqualTo <$> c .: "less_than_or_equal_to",
      UniqueIdIsEmpty <$ flagKey c "is_empty",
      UniqueIdIsNotEmpty <$ flagKey c "is_not_empty"
    ]

-- | Verification filter condition.
data VerificationCondition
  = VerificationStatus VerificationState
  | VerificationDoesNotEqual VerificationState
  deriving stock (Eq, Show, Generic)

-- | Verification states used by verification filters.
data VerificationState
  = VerificationVerified
  | VerificationExpired
  | VerificationNone
  | -- | A state this library does not know yet; holds the raw string.
    UnknownVerificationState Text
  deriving stock (Eq, Show, Generic)

instance ToJSON VerificationState where
  toJSON =
    Aeson.String . \case
      VerificationVerified -> "verified"
      VerificationExpired -> "expired"
      VerificationNone -> "none"
      UnknownVerificationState t -> t

instance FromJSON VerificationState where
  parseJSON = Aeson.withText "VerificationState" $ \case
    "verified" -> pure VerificationVerified
    "expired" -> pure VerificationExpired
    "none" -> pure VerificationNone
    other -> pure (UnknownVerificationState other)

verificationConditionToValue :: VerificationCondition -> Aeson.Value
verificationConditionToValue = \case
  VerificationStatus v -> Aeson.object ["status" .= v]
  VerificationDoesNotEqual v -> Aeson.object ["does_not_equal" .= v]

parseVerificationCondition :: Value -> Parser VerificationCondition
parseVerificationCondition = Aeson.withObject "VerificationCondition" $ \c ->
  asum
    [ VerificationStatus <$> c .: "status",
      VerificationDoesNotEqual <$> c .: "does_not_equal"
    ]

-- | Relative date keywords accepted wherever a date filter takes a date string.
data RelativeDate = Today | Tomorrow | Yesterday | OneWeekAgo | OneWeekFromNow | OneMonthAgo | OneMonthFromNow
  deriving stock (Eq, Show, Generic, Enum, Bounded)

-- | Render for use with 'DateAfter', 'DateBefore', 'DateEquals', 'DateOnOrAfter' and 'DateOnOrBefore'.
relativeDate :: RelativeDate -> Text
relativeDate = \case
  Today -> "today"
  Tomorrow -> "tomorrow"
  Yesterday -> "yesterday"
  OneWeekAgo -> "one_week_ago"
  OneWeekFromNow -> "one_week_from_now"
  OneMonthAgo -> "one_month_ago"
  OneMonthFromNow -> "one_month_from_now"

-- | Formula filter condition, wrapping a condition by the formula's return type.
data FormulaCondition
  = FormulaString TextCondition
  | FormulaNumber NumberCondition
  | FormulaDate DateCondition
  | FormulaCheckbox CheckboxCondition
  deriving stock (Eq, Show, Generic)

formulaConditionToValue :: FormulaCondition -> Aeson.Value
formulaConditionToValue = \case
  FormulaString c -> Aeson.object ["string" .= textConditionToValue c]
  FormulaNumber c -> Aeson.object ["number" .= numberConditionToValue c]
  FormulaDate c -> Aeson.object ["date" .= dateConditionToValue c]
  FormulaCheckbox c -> Aeson.object ["checkbox" .= checkboxConditionToValue c]

parseFormulaCondition :: Value -> Parser FormulaCondition
parseFormulaCondition = Aeson.withObject "FormulaCondition" $ \c ->
  asum
    [ FormulaString <$> (c .: "string" >>= parseTextCondition),
      FormulaNumber <$> (c .: "number" >>= parseNumberCondition),
      FormulaDate <$> (c .: "date" >>= parseDateCondition),
      FormulaCheckbox <$> (c .: "checkbox" >>= parseCheckboxCondition)
    ]

-- | Rollup filter condition.
data RollupCondition
  = RollupAny PropertyCondition
  | RollupEvery PropertyCondition
  | RollupNone PropertyCondition
  | RollupNumber NumberCondition
  | RollupDate DateCondition
  deriving stock (Eq, Show, Generic)

rollupConditionToValue :: RollupCondition -> Aeson.Value
rollupConditionToValue = \case
  RollupAny c -> Aeson.object ["any" .= conditionInnerValue c]
  RollupEvery c -> Aeson.object ["every" .= conditionInnerValue c]
  RollupNone c -> Aeson.object ["none" .= conditionInnerValue c]
  RollupNumber c -> Aeson.object ["number" .= numberConditionToValue c]
  RollupDate c -> Aeson.object ["date" .= dateConditionToValue c]
  where
    conditionInnerValue :: PropertyCondition -> Aeson.Value
    conditionInnerValue cond = Aeson.object (propertyConditionToObject cond)

parseRollupCondition :: Value -> Parser RollupCondition
parseRollupCondition = Aeson.withObject "RollupCondition" $ \c ->
  asum
    [ RollupAny <$> (c .: "any" >>= Aeson.withObject "RollupAny" parsePropertyCondition),
      RollupEvery <$> (c .: "every" >>= Aeson.withObject "RollupEvery" parsePropertyCondition),
      RollupNone <$> (c .: "none" >>= Aeson.withObject "RollupNone" parsePropertyCondition),
      RollupNumber <$> (c .: "number" >>= parseNumberCondition),
      RollupDate <$> (c .: "date" >>= parseDateCondition)
    ]

-- =====================================================================
-- Sorts
-- =====================================================================

-- | Sort direction for query sorts.
data SortDirection
  = Ascending
  | Descending
  deriving stock (Eq, Show, Generic)

instance ToJSON SortDirection where
  toJSON Ascending = Aeson.String "ascending"
  toJSON Descending = Aeson.String "descending"

instance FromJSON SortDirection where
  parseJSON = Aeson.withText "SortDirection" $ \case
    "ascending" -> pure Ascending
    "descending" -> pure Descending
    other -> fail ("unknown sort direction: " <> unpack other)

-- | Sort specification for querying databases and data sources.
data Sort
  = PropertySort Text SortDirection
  | TimestampSort TimestampType SortDirection
  | -- | A sort this library does not model (including unknown directions); the raw JSON is kept.
    UnknownSort Value
  deriving stock (Eq, Show, Generic)

instance ToJSON Sort where
  toJSON (UnknownSort v) = v
  toJSON (PropertySort propName dir) =
    Aeson.object
      [ "property" .= propName,
        "direction" .= dir
      ]
  toJSON (TimestampSort tsType dir) =
    Aeson.object
      [ "timestamp" .= timestampTypeToText tsType,
        "direction" .= dir
      ]

instance FromJSON Sort where
  parseJSON v = case v of
    Object o ->
      asum
        [ PropertySort <$> o .: "property" <*> o .: "direction",
          TimestampSort <$> (o .: "timestamp" >>= parseTimestampType) <*> o .: "direction",
          pure (UnknownSort v)
        ]
    _ -> pure (UnknownSort v)
