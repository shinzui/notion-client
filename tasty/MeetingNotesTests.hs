-- | Meeting-notes create and query endpoints (EP-3).
module MeetingNotesTests (tests) where

import Data.Aeson (Value)
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Vector qualified as Vector
import Notion.V1.Common (UUID (..))
import Notion.V1.MeetingNotes
import Notion.V1.RichText (RichText (..))
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Meeting notes (EP-3)"
    [ testCase "Decode full meeting note block" testDecodeFull,
      testCase "Decode partial create response" testDecodePartial,
      testCase "Unknown meeting-notes status is tolerated" testUnknownStatus,
      testCase "Minimal payload decodes" testMinimalPayload,
      testCase "CreateMeetingNote from file upload" testCreateFromFileUpload,
      testCase "CreateMeetingNote from block has no parent" testCreateFromBlock,
      testCase "Language codes" testLanguageCodes
    ]

blockWithPayload :: LBS.ByteString -> LBS.ByteString
blockWithPayload payload =
  "{\"object\":\"block\",\"id\":\"7e3f0a1b-0000-4000-8000-000000000101\",\"type\":\"meeting_notes\",\
  \\"meeting_notes\":"
    <> payload
    <> ",\"created_time\":\"2026-09-14T00:00:00.000Z\",\"last_edited_time\":\"2026-09-14T00:40:00.000Z\",\
       \\"created_by\":{\"object\":\"user\",\"id\":\"9a8b7c6d-0000-4000-8000-00000000000c\"},\
       \\"last_edited_by\":{\"object\":\"user\",\"id\":\"9a8b7c6d-0000-4000-8000-00000000000c\"},\
       \\"has_children\":true,\"in_trash\":false,\"archived\":false}"

fullPayload :: LBS.ByteString
fullPayload =
  "{\"title\":[{\"type\":\"text\",\"text\":{\"content\":\"Weekly sync\",\"link\":null},\
  \\"annotations\":{\"bold\":false,\"italic\":false,\"strikethrough\":false,\"underline\":false,\"code\":false,\"color\":\"default\"},\
  \\"plain_text\":\"Weekly sync\",\"href\":null}],\
  \\"status\":\"notes_ready\",\
  \\"children\":{\"summary_block_id\":\"7e3f0a1b-0000-4000-8000-000000000102\",\
  \\"notes_block_id\":\"7e3f0a1b-0000-4000-8000-000000000103\",\
  \\"transcript_block_id\":\"7e3f0a1b-0000-4000-8000-000000000104\"},\
  \\"calendar_event\":{\"start_time\":\"2026-09-14T09:00:00.000+09:00\",\"end_time\":\"2026-09-14T09:30:00.000+09:00\",\
  \\"attendees\":[\"9a8b7c6d-0000-4000-8000-00000000000c\"]},\
  \\"recording\":{\"start_time\":\"2026-09-14T09:01:00.000+09:00\"}}"

-- | The meeting-note block fixture used by the create and query tests.
blockFixture :: LBS.ByteString
blockFixture = blockWithPayload fullPayload

decodeContent :: LBS.ByteString -> IO MeetingNotesContent
decodeContent bs = case Aeson.eitherDecode bs of
  Right (FullMeetingNote MeetingNoteBlock {meetingNotes}) -> pure meetingNotes
  Right other -> assertFailure ("expected FullMeetingNote, got " <> show other)
  Left err -> assertFailure err

decodeValue :: LBS.ByteString -> IO Value
decodeValue bs = either (assertFailure . ("fixture: " <>)) pure (Aeson.eitherDecode bs)

testDecodeFull :: Assertion
testDecodeFull = do
  MeetingNotesContent {contentTitle, contentStatus, contentCalendarEvent} <- decodeContent blockFixture
  contentStatus @?= Just NotesReady
  fmap (fmap (\RichText {plainText} -> plainText) . Vector.toList) contentTitle @?= Just ["Weekly sync"]
  fmap (\MeetingCalendarEvent {calendarAttendees} -> fmap Vector.length calendarAttendees) contentCalendarEvent
    @?= Just (Just 1)

testDecodePartial :: Assertion
testDecodePartial =
  case Aeson.eitherDecode "{\"object\":\"block\",\"id\":\"7e3f0a1b-0000-4000-8000-000000000101\"}" of
    Right (PartialMeetingNote bid) -> bid @?= UUID "7e3f0a1b-0000-4000-8000-000000000101"
    Right other -> assertFailure ("expected PartialMeetingNote, got " <> show other)
    Left err -> assertFailure err

testUnknownStatus :: Assertion
testUnknownStatus = do
  MeetingNotesContent {contentStatus = archiving} <- decodeContent (blockWithPayload "{\"status\":\"archiving\"}")
  archiving @?= Just (UnknownMeetingNotesStatus "archiving")
  MeetingNotesContent {contentStatus = failed} <- decodeContent (blockWithPayload "{\"status\":\"transcription_failed\"}")
  failed @?= Just TranscriptionFailed

testMinimalPayload :: Assertion
testMinimalPayload = do
  content <- decodeContent (blockWithPayload "{}")
  content @?= MeetingNotesContent Nothing Nothing Nothing Nothing Nothing

testCreateFromFileUpload :: Assertion
testCreateFromFileUpload = do
  let req =
        CreateMeetingNote
          { source =
              FromFileUpload
                (UUID "a02fc1d3-db8b-45c5-a222-27595b15aea7")
                (UUID "c02fc1d3-db8b-45c5-a222-27595b15aea7"),
            title = Just "Weekly sync",
            language = Just LanguageEn,
            kickoffSummary = Just True
          }
  expected <-
    decodeValue
      "{\"source\":{\"type\":\"file_upload\",\"file_upload_id\":\"a02fc1d3-db8b-45c5-a222-27595b15aea7\"},\
      \\"parent\":{\"type\":\"page_id\",\"page_id\":\"c02fc1d3-db8b-45c5-a222-27595b15aea7\"},\
      \\"title\":\"Weekly sync\",\"language\":\"en\",\"options\":{\"kickoff_summary\":true}}"
  Aeson.toJSON req @?= expected

testCreateFromBlock :: Assertion
testCreateFromBlock = do
  expected <- decodeValue "{\"source\":{\"type\":\"block\",\"block_id\":\"b-1\"}}"
  Aeson.toJSON (mkCreateMeetingNote (FromBlock (UUID "b-1"))) @?= expected

testLanguageCodes :: Assertion
testLanguageCodes =
  map Aeson.toJSON [LanguageZhCN, LanguageZhTW, LanguageNo, LanguageOther "tl"]
    @?= map Aeson.String ["zh-CN", "zh-TW", "no", "tl"]
