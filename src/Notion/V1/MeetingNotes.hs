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

    -- * Servant
    API,
  )
where

import Control.Applicative ((<|>))
import Data.Aeson ((.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Maybe (catMaybes)
import Notion.Prelude
import Notion.V1.BlockContent (MeetingCalendarEvent (..), MeetingNotesChildren (..), MeetingNotesStatus (..), MeetingRecording (..))
import Notion.V1.Common (BlockID, ObjectType (..), UUID)
import Notion.V1.RichText (RichText)
import Notion.V1.Users (UserReference)
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

-- | Servant API
type API =
  "blocks"
    :> "meeting_notes"
    :> ( ReqBody '[JSON] CreateMeetingNote
           :> Post '[JSON] CreateMeetingNoteResponse
       )
