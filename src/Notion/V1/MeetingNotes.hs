-- | @\/v1\/blocks\/meeting_notes@
--
-- A meeting note is a @meeting_notes@ block produced by Notion AI from a
-- recording: a title, a processing status and three child tabs (summary,
-- notes and transcript). The payload sub-types are shared with
-- 'Notion.V1.BlockContent'.
module Notion.V1.MeetingNotes
  ( -- * Responses
    MeetingNotesContent (..),
    MeetingNoteBlock (..),
    CreateMeetingNoteResponse (..),

    -- * Payload types (re-exported from "Notion.V1.BlockContent")
    MeetingNotesStatus (..),
    MeetingNotesChildren (..),
    MeetingCalendarEvent (..),
    MeetingRecording (..),

    -- * Creating
    CreateMeetingNote (..),
    MeetingNoteSource (..),
    MeetingNoteLanguage (..),
    mkCreateMeetingNote,

    -- * Querying
    QueryMeetingNotes (..),
    emptyQueryMeetingNotes,
    QueryMeetingNotesResponse (..),
    MeetingNotesSort (..),
    MeetingNotesProperty (..),

    -- * Filters
    MeetingNotesFilter (..),
    MeetingNotesCombinator (..),
    MeetingNotesFilterNode (..),
    MeetingNotesPropertyFilter (..),
    MeetingNotesTextCondition (..),
    MeetingNotesDateCondition (..),
    MeetingNotesPersonCondition (..),
    MeetingNotesDateValueType (..),
    MeetingNotesDatePoint (..),
    MeetingNotesDatePointValue (..),
    MeetingNotesDateSpec (..),
    MeetingNotesDateRange (..),
    MeetingNotesDateRangeValue (..),
    MeetingNotesDirection (..),
    MeetingNotesDateUnit (..),

    -- * Filter helpers
    mnAnd,
    mnOr,
    mnTitleContains,
    mnAttendeesInclude,
    mnCreatedOnOrAfter,
    mnCreatedWithinPast,

    -- * Servant
    API,
  )
where

import Control.Applicative ((<|>))
import Data.Aeson ((.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (catMaybes)
import Notion.Prelude
import Notion.V1.BlockContent (MeetingCalendarEvent (..), MeetingNotesChildren (..), MeetingNotesStatus (..), MeetingRecording (..))
import Notion.V1.Common (BlockID, ObjectType (..), UUID)
import Notion.V1.Filter (SortDirection (..))
import Notion.V1.RichText (RichText)
import Notion.V1.Users (UserID, UserReference)
import Prelude hiding (id)

-- | The @meeting_notes@ payload returned by the create and query endpoints.
--
-- Field names are prefixed so they do not clash with the fields of the
-- 'Notion.V1.BlockContent.MeetingNotesBlock' constructor.
data MeetingNotesContent = MeetingNotesContent
  { contentTitle :: Maybe (Vector RichText),
    contentStatus :: Maybe MeetingNotesStatus,
    contentChildren :: Maybe MeetingNotesChildren,
    contentCalendarEvent :: Maybe MeetingCalendarEvent,
    contentRecording :: Maybe MeetingRecording
  }
  deriving stock (Eq, Generic, Show)

instance FromJSON MeetingNotesContent where
  parseJSON = Aeson.withObject "MeetingNotesContent" $ \o -> do
    contentTitle <- o .:? "title"
    contentStatus <- o .:? "status"
    contentChildren <- o .:? "children"
    contentCalendarEvent <- o .:? "calendar_event"
    contentRecording <- o .:? "recording"
    pure MeetingNotesContent {..}

instance ToJSON MeetingNotesContent where
  toJSON MeetingNotesContent {..} =
    Aeson.object $
      catMaybes
        [ ("title" .=) <$> contentTitle,
          ("status" .=) <$> contentStatus,
          ("children" .=) <$> contentChildren,
          ("calendar_event" .=) <$> contentCalendarEvent,
          ("recording" .=) <$> contentRecording
        ]

-- | A meeting-notes block as returned by the create and query endpoints.
-- Unlike 'Notion.V1.Blocks.BlockObject' it carries no @parent@.
data MeetingNoteBlock = MeetingNoteBlock
  { id :: BlockID,
    meetingNotes :: MeetingNotesContent,
    createdTime :: POSIXTime,
    lastEditedTime :: POSIXTime,
    createdBy :: UserReference,
    lastEditedBy :: UserReference,
    hasChildren :: Bool,
    inTrash :: Bool,
    object :: ObjectType
  }
  deriving stock (Generic, Show)

instance FromJSON MeetingNoteBlock where
  parseJSON = Aeson.withObject "MeetingNoteBlock" $ \o -> do
    id <- o .: "id"
    meetingNotes <- o .: "meeting_notes"
    createdTime <- parseISO8601 =<< o .: "created_time"
    lastEditedTime <- parseISO8601 =<< o .: "last_edited_time"
    createdBy <- o .: "created_by"
    lastEditedBy <- o .: "last_edited_by"
    hasChildren <- o .: "has_children"
    inTrash <- (o .: "in_trash") <|> (o .: "archived") <|> pure False
    object <- o .: "object"
    pure MeetingNoteBlock {..}

instance ToJSON MeetingNoteBlock where
  toJSON MeetingNoteBlock {..} =
    Aeson.object
      [ "object" .= object,
        "id" .= id,
        "type" .= ("meeting_notes" :: Text),
        "meeting_notes" .= meetingNotes,
        "created_time" .= posixToISO8601 createdTime,
        "last_edited_time" .= posixToISO8601 lastEditedTime,
        "created_by" .= createdBy,
        "last_edited_by" .= lastEditedBy,
        "has_children" .= hasChildren,
        "in_trash" .= inTrash
      ]

-- | Response of 'Notion.V1.createMeetingNote': the full block or only its id.
data CreateMeetingNoteResponse
  = FullMeetingNote MeetingNoteBlock
  | PartialMeetingNote BlockID
  deriving stock (Generic, Show)

-- | Full when the @meeting_notes@ key is present.
instance FromJSON CreateMeetingNoteResponse where
  parseJSON = Aeson.withObject "CreateMeetingNoteResponse" $ \o ->
    if KeyMap.member "meeting_notes" o
      then FullMeetingNote <$> parseJSON (Object o)
      else PartialMeetingNote <$> o .: "id"

instance ToJSON CreateMeetingNoteResponse where
  toJSON = \case
    FullMeetingNote b -> toJSON b
    PartialMeetingNote bid -> Aeson.object ["object" .= ("block" :: Text), "id" .= bid]

-- | Transcription language hint.
data MeetingNoteLanguage
  = LanguageAuto
  | LanguageEn
  | LanguageZhCN
  | LanguageZhTW
  | LanguageEs
  | LanguageFr
  | LanguageDe
  | LanguageJa
  | LanguageKo
  | LanguagePt
  | LanguageRu
  | LanguageTh
  | LanguageVi
  | LanguageId
  | LanguageDa
  | LanguageFi
  | LanguageNo
  | LanguageNl
  | LanguageIt
  | LanguageSv
  | LanguageAr
  | LanguageHe
  | LanguagePl
  | -- | A language code this library does not list; sent verbatim.
    LanguageOther Text
  deriving stock (Eq, Generic, Show)

instance ToJSON MeetingNoteLanguage where
  toJSON =
    String . \case
      LanguageAuto -> "auto"
      LanguageEn -> "en"
      LanguageZhCN -> "zh-CN"
      LanguageZhTW -> "zh-TW"
      LanguageEs -> "es"
      LanguageFr -> "fr"
      LanguageDe -> "de"
      LanguageJa -> "ja"
      LanguageKo -> "ko"
      LanguagePt -> "pt"
      LanguageRu -> "ru"
      LanguageTh -> "th"
      LanguageVi -> "vi"
      LanguageId -> "id"
      LanguageDa -> "da"
      LanguageFi -> "fi"
      LanguageNo -> "no"
      LanguageNl -> "nl"
      LanguageIt -> "it"
      LanguageSv -> "sv"
      LanguageAr -> "ar"
      LanguageHe -> "he"
      LanguagePl -> "pl"
      LanguageOther t -> t

-- | The recording a meeting note is made from.
data MeetingNoteSource
  = -- | A completed audio or video file upload, and the page to create the
    -- note in.
    FromFileUpload {fileUploadId :: UUID, parentPageId :: UUID}
  | -- | An existing audio, video or file block. No parent is sent.
    FromBlock {sourceBlockId :: BlockID}
  deriving stock (Eq, Generic, Show)

-- | Request body of 'Notion.V1.createMeetingNote'.
data CreateMeetingNote = CreateMeetingNote
  { source :: MeetingNoteSource,
    title :: Maybe Text,
    language :: Maybe MeetingNoteLanguage,
    -- | Sent as @options.kickoff_summary@: start summary generation after
    -- transcription.
    kickoffSummary :: Maybe Bool
  }
  deriving stock (Eq, Generic, Show)

instance ToJSON CreateMeetingNote where
  toJSON CreateMeetingNote {..} =
    Aeson.object $
      sourcePairs
        <> catMaybes
          [ ("title" .=) <$> title,
            ("language" .=) <$> language,
            (\b -> "options" .= Aeson.object ["kickoff_summary" .= b]) <$> kickoffSummary
          ]
    where
      sourcePairs = case source of
        FromFileUpload {fileUploadId, parentPageId} ->
          [ "source" .= Aeson.object ["type" .= ("file_upload" :: Text), "file_upload_id" .= fileUploadId],
            "parent" .= Aeson.object ["type" .= ("page_id" :: Text), "page_id" .= parentPageId]
          ]
        FromBlock {sourceBlockId} ->
          ["source" .= Aeson.object ["type" .= ("block" :: Text), "block_id" .= sourceBlockId]]

-- | A request with only a source.
mkCreateMeetingNote :: MeetingNoteSource -> CreateMeetingNote
mkCreateMeetingNote source =
  CreateMeetingNote {source, title = Nothing, language = Nothing, kickoffSummary = Nothing}

-- | A combinator filter: all ('MNAnd') or any ('MNOr') of its nodes match.
-- Nodes nest to any depth; the server decides the maximum.
data MeetingNotesFilter = MeetingNotesFilter
  { operator :: MeetingNotesCombinator,
    filters :: [MeetingNotesFilterNode]
  }
  deriving stock (Eq, Generic, Show)

data MeetingNotesCombinator = MNAnd | MNOr
  deriving stock (Eq, Generic, Show)

-- | One entry of a combinator's @filters@.
data MeetingNotesFilterNode
  = MNNested MeetingNotesFilter
  | MNProperty MeetingNotesPropertyFilter
  | -- | Escape hatch for filter shapes this library does not model; sent verbatim.
    MNRawNode Value
  deriving stock (Eq, Generic, Show)

-- | A condition on one of the filterable properties.
data MeetingNotesPropertyFilter
  = MNTitle MeetingNotesTextCondition
  | MNCreatedTime MeetingNotesDateCondition
  | MNLastEditedTime MeetingNotesDateCondition
  | MNCreatedBy MeetingNotesPersonCondition
  | MNLastEditedBy MeetingNotesPersonCondition
  | MNAttendees MeetingNotesPersonCondition
  deriving stock (Eq, Generic, Show)

data MeetingNotesTextCondition
  = MNStringIs Text
  | MNStringIsNot Text
  | MNStringContains Text
  | MNStringDoesNotContain Text
  | MNStringStartsWith Text
  | MNStringEndsWith Text
  | MNTextIsEmpty
  | MNTextIsNotEmpty
  deriving stock (Eq, Generic, Show)

data MeetingNotesDateCondition
  = MNDateIs MeetingNotesDatePoint
  | MNDateIsBefore MeetingNotesDatePoint
  | MNDateIsAfter MeetingNotesDatePoint
  | MNDateIsOnOrBefore MeetingNotesDatePoint
  | MNDateIsOnOrAfter MeetingNotesDatePoint
  | MNDateIsWithin MeetingNotesDateRange
  | MNDateIsRelativeTo MeetingNotesDateRange
  | MNDateIsEmpty
  | MNDateIsNotEmpty
  deriving stock (Eq, Generic, Show)

-- | Person conditions always encode their users as a JSON array.
data MeetingNotesPersonCondition
  = MNPersonContains (NonEmpty UserID)
  | MNPersonDoesNotContain (NonEmpty UserID)
  | MNPersonIsEmpty
  | MNPersonIsNotEmpty
  deriving stock (Eq, Generic, Show)

data MeetingNotesDateValueType = MNRelative | MNExact
  deriving stock (Eq, Generic, Show)

-- | Value of a point date condition (@date_is@, @date_is_before@, ...).
data MeetingNotesDatePoint = MeetingNotesDatePoint
  { valueType :: MeetingNotesDateValueType,
    value :: MeetingNotesDatePointValue
  }
  deriving stock (Eq, Generic, Show)

data MeetingNotesDatePointValue
  = -- | @"value": "<string>"@. With 'MNRelative', Notion accepts @today@,
    -- @tomorrow@, @yesterday@, @one_week_ago@, @one_week_from_now@,
    -- @one_month_ago@ and @one_month_from_now@.
    MNDatePointText Text
  | -- | @"value": {"type": "date" | "datetime", ...}@
    MNDatePointSpec MeetingNotesDateSpec
  deriving stock (Eq, Generic, Show)

data MeetingNotesDateSpec = MeetingNotesDateSpec
  { -- | 'False' sends @"date"@, 'True' sends @"datetime"@.
    withTime :: Bool,
    -- | For example @"2026-09-01"@.
    startDate :: Text,
    -- | For example @"09:30"@.
    startTime :: Maybe Text,
    -- | IANA name, for example @"Asia/Tokyo"@.
    timeZone :: Maybe Text
  }
  deriving stock (Eq, Generic, Show)

-- | Value of a range date condition (@date_is_within@, @date_is_relative_to@).
data MeetingNotesDateRange = MeetingNotesDateRange
  { valueType :: MeetingNotesDateValueType,
    value :: MeetingNotesDateRangeValue,
    direction :: Maybe MeetingNotesDirection,
    unit :: Maybe MeetingNotesDateUnit,
    count :: Maybe Natural
  }
  deriving stock (Eq, Generic, Show)

data MeetingNotesDateRangeValue
  = -- | @"value": "<string>"@. With 'MNRelative', Notion accepts
    -- @the_past_week@, @the_past_month@, @the_past_year@, @the_next_week@,
    -- @the_next_month@, @the_next_year@ and @this_week@, or @custom@ (and
    -- @surrounding@) together with 'unit' and 'count'.
    MNDateRangeText Text
  | -- | @{"type": "daterange", "start_date": ..., "end_date"?: ...}@
    MNDateRangeSpec Text (Maybe Text)
  deriving stock (Eq, Generic, Show)

data MeetingNotesDirection = MNPast | MNFuture
  deriving stock (Eq, Generic, Show)

data MeetingNotesDateUnit = MNDay | MNWeek | MNMonth | MNYear
  deriving stock (Eq, Generic, Show)

-- | Properties meeting notes can be filtered and sorted by.
data MeetingNotesProperty
  = MNPropTitle
  | MNPropCreatedTime
  | MNPropLastEditedTime
  | MNPropCreatedBy
  | MNPropLastEditedBy
  | MNPropAttendees
  deriving stock (Eq, Generic, Show)

data MeetingNotesSort = MeetingNotesSort
  { property :: MeetingNotesProperty,
    direction :: SortDirection
  }
  deriving stock (Eq, Generic, Show)

-- | Request body of 'Notion.V1.queryMeetingNotes'.
data QueryMeetingNotes = QueryMeetingNotes
  { filter :: Maybe MeetingNotesFilter,
    sort :: Maybe [MeetingNotesSort],
    -- | The server default is 50.
    limit :: Maybe Natural
  }
  deriving stock (Eq, Generic, Show)

-- | A query with no filter, sort or limit; encodes as @{}@.
emptyQueryMeetingNotes :: QueryMeetingNotes
emptyQueryMeetingNotes = QueryMeetingNotes Nothing Nothing Nothing

-- | Response of 'Notion.V1.queryMeetingNotes'. There is no cursor.
data QueryMeetingNotesResponse = QueryMeetingNotesResponse
  { results :: Vector MeetingNoteBlock,
    hasMore :: Bool
  }
  deriving stock (Generic, Show)

instance FromJSON QueryMeetingNotesResponse where
  parseJSON = Aeson.withObject "QueryMeetingNotesResponse" $ \o ->
    QueryMeetingNotesResponse <$> o .: "results" <*> o .: "has_more"

instance ToJSON QueryMeetingNotesResponse where
  toJSON (QueryMeetingNotesResponse rs more) = Aeson.object ["results" .= rs, "has_more" .= more]

instance ToJSON MeetingNotesCombinator where
  toJSON MNAnd = String "and"
  toJSON MNOr = String "or"

instance ToJSON MeetingNotesFilter where
  toJSON (MeetingNotesFilter op nodes) = Aeson.object ["operator" .= op, "filters" .= nodes]

instance ToJSON MeetingNotesFilterNode where
  toJSON = \case
    MNNested f -> toJSON f
    MNProperty p -> toJSON p
    MNRawNode v -> v

instance ToJSON MeetingNotesPropertyFilter where
  toJSON pf = Aeson.object ["property" .= prop, "filter" .= condition]
    where
      (prop, condition) = case pf of
        MNTitle c -> (MNPropTitle, toJSON c)
        MNCreatedTime c -> (MNPropCreatedTime, toJSON c)
        MNLastEditedTime c -> (MNPropLastEditedTime, toJSON c)
        MNCreatedBy c -> (MNPropCreatedBy, toJSON c)
        MNLastEditedBy c -> (MNPropLastEditedBy, toJSON c)
        MNAttendees c -> (MNPropAttendees, toJSON c)

instance ToJSON MeetingNotesProperty where
  toJSON =
    String . \case
      MNPropTitle -> "title"
      MNPropCreatedTime -> "created_time"
      MNPropLastEditedTime -> "last_edited_time"
      MNPropCreatedBy -> "created_by"
      MNPropLastEditedBy -> "last_edited_by"
      MNPropAttendees -> "attendees"

-- | @{"operator": op}@
noValue :: Text -> Value
noValue op = Aeson.object ["operator" .= op]

-- | @{"operator": op, "value": v}@
withValue :: (ToJSON v) => Text -> v -> Value
withValue op v = Aeson.object ["operator" .= op, "value" .= v]

instance ToJSON MeetingNotesTextCondition where
  toJSON = \case
    MNStringIs t -> exact "string_is" t
    MNStringIsNot t -> exact "string_is_not" t
    MNStringContains t -> exact "string_contains" t
    MNStringDoesNotContain t -> exact "string_does_not_contain" t
    MNStringStartsWith t -> exact "string_starts_with" t
    MNStringEndsWith t -> exact "string_ends_with" t
    MNTextIsEmpty -> noValue "is_empty"
    MNTextIsNotEmpty -> noValue "is_not_empty"
    where
      exact op t = withValue op (Aeson.object ["type" .= ("exact" :: Text), "value" .= t])

instance ToJSON MeetingNotesDateCondition where
  toJSON = \case
    MNDateIs p -> withValue "date_is" p
    MNDateIsBefore p -> withValue "date_is_before" p
    MNDateIsAfter p -> withValue "date_is_after" p
    MNDateIsOnOrBefore p -> withValue "date_is_on_or_before" p
    MNDateIsOnOrAfter p -> withValue "date_is_on_or_after" p
    MNDateIsWithin r -> withValue "date_is_within" r
    MNDateIsRelativeTo r -> withValue "date_is_relative_to" r
    MNDateIsEmpty -> noValue "is_empty"
    MNDateIsNotEmpty -> noValue "is_not_empty"

instance ToJSON MeetingNotesPersonCondition where
  toJSON = \case
    MNPersonContains users -> withValue "person_contains" (personValues users)
    MNPersonDoesNotContain users -> withValue "person_does_not_contain" (personValues users)
    MNPersonIsEmpty -> noValue "is_empty"
    MNPersonIsNotEmpty -> noValue "is_not_empty"
    where
      personValues = map personValue . NonEmpty.toList
      personValue uid =
        Aeson.object
          [ "type" .= ("exact" :: Text),
            "value" .= Aeson.object ["table" .= ("notion_user" :: Text), "id" .= uid]
          ]

instance ToJSON MeetingNotesDateValueType where
  toJSON MNRelative = String "relative"
  toJSON MNExact = String "exact"

instance ToJSON MeetingNotesDatePoint where
  toJSON (MeetingNotesDatePoint vt v) = Aeson.object ["type" .= vt, "value" .= v]

instance ToJSON MeetingNotesDatePointValue where
  toJSON = \case
    MNDatePointText t -> String t
    MNDatePointSpec spec -> toJSON spec

instance ToJSON MeetingNotesDateSpec where
  toJSON MeetingNotesDateSpec {..} =
    Aeson.object $
      [ "type" .= (if withTime then "datetime" else "date" :: Text),
        "start_date" .= startDate
      ]
        <> catMaybes [("start_time" .=) <$> startTime, ("time_zone" .=) <$> timeZone]

instance ToJSON MeetingNotesDateRange where
  toJSON (MeetingNotesDateRange vt v dir u n) =
    Aeson.object $
      ["type" .= vt, "value" .= v]
        <> catMaybes [("direction" .=) <$> dir, ("unit" .=) <$> u, ("count" .=) <$> n]

instance ToJSON MeetingNotesDateRangeValue where
  toJSON = \case
    MNDateRangeText t -> String t
    MNDateRangeSpec start end ->
      Aeson.object $
        ["type" .= ("daterange" :: Text), "start_date" .= start]
          <> catMaybes [("end_date" .=) <$> end]

instance ToJSON MeetingNotesDirection where
  toJSON MNPast = String "past"
  toJSON MNFuture = String "future"

instance ToJSON MeetingNotesDateUnit where
  toJSON =
    String . \case
      MNDay -> "day"
      MNWeek -> "week"
      MNMonth -> "month"
      MNYear -> "year"

instance ToJSON MeetingNotesSort where
  toJSON (MeetingNotesSort prop dir) = Aeson.object ["property" .= prop, "direction" .= dir]

instance ToJSON QueryMeetingNotes where
  toJSON (QueryMeetingNotes f s l) =
    Aeson.object $
      catMaybes
        [ ("filter" .=) <$> f,
          ("sort" .=) <$> s,
          ("limit" .=) <$> l
        ]

-- | All of the nodes match.
mnAnd :: [MeetingNotesFilterNode] -> MeetingNotesFilter
mnAnd = MeetingNotesFilter MNAnd

-- | Any of the nodes matches.
mnOr :: [MeetingNotesFilterNode] -> MeetingNotesFilter
mnOr = MeetingNotesFilter MNOr

-- | The title contains the text.
mnTitleContains :: Text -> MeetingNotesFilterNode
mnTitleContains = MNProperty . MNTitle . MNStringContains

-- | The attendees include the user.
mnAttendeesInclude :: UserID -> MeetingNotesFilterNode
mnAttendeesInclude uid = MNProperty (MNAttendees (MNPersonContains (uid :| [])))

-- | Created on or after a @YYYY-MM-DD@ date.
mnCreatedOnOrAfter :: Text -> MeetingNotesFilterNode
mnCreatedOnOrAfter day =
  MNProperty . MNCreatedTime . MNDateIsOnOrAfter $
    MeetingNotesDatePoint MNExact (MNDatePointSpec (MeetingNotesDateSpec False day Nothing Nothing))

-- | Created within the past @count@ units, relative to now.
mnCreatedWithinPast :: Natural -> MeetingNotesDateUnit -> MeetingNotesFilterNode
mnCreatedWithinPast n u =
  MNProperty . MNCreatedTime . MNDateIsWithin $
    MeetingNotesDateRange MNRelative (MNDateRangeText "custom") (Just MNPast) (Just u) (Just n)

-- | Servant API
type API =
  "blocks"
    :> "meeting_notes"
    :> ( ReqBody '[JSON] CreateMeetingNote
           :> Post '[JSON] CreateMeetingNoteResponse
           :<|> "query"
           :> ReqBody '[JSON] QueryMeetingNotes
           :> Post '[JSON] QueryMeetingNotesResponse
       )
