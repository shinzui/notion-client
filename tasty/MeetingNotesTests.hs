-- | Meeting-notes create and query endpoints (EP-3).
module MeetingNotesTests (tests) where

import Data.Aeson (Value, (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Vector qualified as Vector
import Notion.V1.Common (UUID (..))
import Notion.V1.Filter (SortDirection (..))
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
      testCase "Language codes" testLanguageCodes,
      testCase "Empty query encodes to {}" testEmptyQuery,
      testCase "Attendees filter matches the JS SDK test" testAttendeesFilter,
      testCase "Nested combinators, title and date point" testNestedFilter,
      testCase "Date range condition" testDateRange,
      testCase "Sort and limit" testSortAndLimit,
      testCase "Raw node passes through" testRawNode,
      testCase "Decode query response" testDecodeQueryResponse
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

-- | A value nested inside JSON objects, looked up by key path.
lookupPath :: [Aeson.Key] -> Value -> Maybe Value
lookupPath [] v = Just v
lookupPath (k : ks) (Aeson.Object o) = KeyMap.lookup k o >>= lookupPath ks
lookupPath _ _ = Nothing

-- | The encoded condition of a property filter node.
conditionOf :: MeetingNotesPropertyFilter -> Maybe Value
conditionOf = lookupPath ["filter"] . Aeson.toJSON

testEmptyQuery :: Assertion
testEmptyQuery = Aeson.toJSON emptyQueryMeetingNotes @?= Aeson.object []

testAttendeesFilter :: Assertion
testAttendeesFilter = do
  let QueryMeetingNotes {sort, limit} = emptyQueryMeetingNotes
      query =
        QueryMeetingNotes
          { filter = Just (mnAnd [mnAttendeesInclude (UUID "a1b2c3d4-e5f6-7890-abcd-ef1234567890")]),
            sort,
            limit
          }
  expected <-
    decodeValue
      "{\"filter\":{\"operator\":\"and\",\"filters\":[{\"property\":\"attendees\",\
      \\"filter\":{\"operator\":\"person_contains\",\"value\":[{\"type\":\"exact\",\
      \\"value\":{\"table\":\"notion_user\",\"id\":\"a1b2c3d4-e5f6-7890-abcd-ef1234567890\"}}]}}]}}"
  Aeson.toJSON query @?= expected

testNestedFilter :: Assertion
testNestedFilter = do
  let datePoint =
        MNProperty
          ( MNCreatedTime
              ( MNDateIsOnOrAfter
                  (MeetingNotesDatePoint MNExact (MNDatePointSpec (MeetingNotesDateSpec True "2026-09-01" (Just "09:30") (Just "Asia/Tokyo"))))
              )
          )
      f = mnOr [mnTitleContains "standup", MNNested (mnAnd [datePoint, MNProperty (MNTitle MNTextIsNotEmpty)])]
  title <- decodeValue "{\"property\":\"title\",\"filter\":{\"operator\":\"string_contains\",\"value\":{\"type\":\"exact\",\"value\":\"standup\"}}}"
  spec <- decodeValue "{\"type\":\"datetime\",\"start_date\":\"2026-09-01\",\"start_time\":\"09:30\",\"time_zone\":\"Asia/Tokyo\"}"
  notEmpty <- decodeValue "{\"property\":\"title\",\"filter\":{\"operator\":\"is_not_empty\"}}"
  let nested = Aeson.object ["operator" .= ("and" :: Text), "filters" .= [Aeson.toJSON datePoint, notEmpty]]
  Aeson.toJSON f @?= Aeson.object ["operator" .= ("or" :: Text), "filters" .= [title, nested]]
  lookupPath ["filter", "value", "value"] (Aeson.toJSON datePoint) @?= Just spec
  lookupPath ["filter", "operator"] (Aeson.toJSON datePoint) @?= Just (Aeson.String "date_is_on_or_after")

testDateRange :: Assertion
testDateRange = do
  relative <- decodeValue "{\"type\":\"relative\",\"value\":\"custom\",\"direction\":\"past\",\"unit\":\"week\",\"count\":2}"
  (conditionOf (MNLastEditedTime (MNDateIsWithin (MeetingNotesDateRange MNRelative (MNDateRangeText "custom") (Just MNPast) (Just MNWeek) (Just 2)))) >>= lookupPath ["value"])
    @?= Just relative
  -- mnCreatedWithinPast produces the shape Notion accepted in a live check
  within <- decodeValue "{\"operator\":\"date_is_within\",\"value\":{\"type\":\"relative\",\"value\":\"custom\",\"direction\":\"past\",\"unit\":\"year\",\"count\":1}}"
  lookupPath ["filter"] (Aeson.toJSON (mnCreatedWithinPast 1 MNYear)) @?= Just within
  exact <- decodeValue "{\"type\":\"exact\",\"value\":{\"type\":\"daterange\",\"start_date\":\"2026-09-01\"}}"
  (conditionOf (MNLastEditedTime (MNDateIsWithin (MeetingNotesDateRange MNExact (MNDateRangeSpec "2026-09-01" Nothing) Nothing Nothing Nothing))) >>= lookupPath ["value"])
    @?= Just exact

testSortAndLimit :: Assertion
testSortAndLimit = do
  expected <- decodeValue "{\"sort\":[{\"property\":\"created_time\",\"direction\":\"descending\"}],\"limit\":10}"
  Aeson.toJSON (QueryMeetingNotes Nothing (Just [MeetingNotesSort MNPropCreatedTime Descending]) (Just 10)) @?= expected

testRawNode :: Assertion
testRawNode = do
  let raw = Aeson.object ["property" .= ("title" :: Text)]
  lookupPath ["filters"] (Aeson.toJSON (mnAnd [MNRawNode raw])) @?= Just (Aeson.toJSON [raw])

testDecodeQueryResponse :: Assertion
testDecodeQueryResponse =
  case Aeson.eitherDecode ("{\"results\":[" <> blockFixture <> "],\"has_more\":false}") of
    Right QueryMeetingNotesResponse {results, hasMore} -> do
      Vector.length results @?= 1
      hasMore @?= False
    Left err -> assertFailure err
