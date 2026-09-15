-- | Wire-format regression tests: JSON fixtures transcribed from the official
-- Notion JS SDK types, and requests captured before they reach the network.
module WireFormatTests (tests) where

import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy.Char8 qualified as L8
import Data.Vector qualified as Vector
import Notion.V1.BlockContent
  ( BlockContent (..),
    CodeLanguage (..),
    MeetingCalendarEvent (..),
    MeetingNotesChildren (..),
    MeetingNotesStatus (..),
  )
import Notion.V1.Blocks (BlockObject (..))
import Notion.V1.Common (Color (..), Icon (..), Parent (..), UUID (..))
import Notion.V1.Properties (NumberFormat (..))
import Notion.V1.PropertyValue (FormulaResult (..), PropertyValue (..), UniqueIdResult (..))
import Notion.V1.RichText (Annotations (..), MentionContent (..), RichText (..), RichTextContent (..))
import Notion.V1.Users (BotUser (..), PersonUser (..), UserObject (..), UserOwner (..))
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "WireFormat"
    [ testGroup "Common and rich text" commonTests,
      testGroup "Blocks, users and property values" blockUserPropertyTests
    ]

-- | Decode a lazy ByteString literal or fail the test with aeson's message.
decodeOrFail :: (Aeson.FromJSON a) => L8.ByteString -> IO a
decodeOrFail bytes = either (assertFailure . ("decode failed: " <>)) pure (Aeson.eitherDecode bytes)

-- | A text rich-text item with the given annotation color.
richTextWithColor :: L8.ByteString -> L8.ByteString
richTextWithColor color =
  "{\"type\":\"text\",\"text\":{\"content\":\"Hello\",\"link\":null},\"annotations\":{\"bold\":false,\"italic\":false,\"strikethrough\":false,\"underline\":false,\"code\":false,\"color\":\""
    <> color
    <> "\"},\"plain_text\":\"Hello\",\"href\":null}"

------------------------------------------------------------------------------
-- Common and rich text

commonTests :: [TestTree]
commonTests =
  [ testCase "Color default_background decodes and round-trips" $ do
      c <- decodeOrFail "\"default_background\""
      c @?= DefaultBackground
      Aeson.encode DefaultBackground @?= "\"default_background\"",
    testCase "Color unknown value falls back to UnknownColor" $ do
      c <- decodeOrFail "\"ultraviolet_background\""
      c @?= UnknownColor "ultraviolet_background"
      Aeson.encode c @?= "\"ultraviolet_background\"",
    testCase "RichText with default_background annotation decodes" $ do
      rt <- decodeOrFail (richTextWithColor "default_background") :: IO RichText
      let RichText {annotations = Annotations {color = c}} = rt
      c @?= DefaultBackground,
    testCase "Parent agent_id decodes to AgentParent" $ do
      p <- decodeOrFail "{\"type\":\"agent_id\",\"agent_id\":\"aaaaaaaa-0000-4000-8000-000000000001\"}"
      case p of
        AgentParent aid -> aid @?= UUID "aaaaaaaa-0000-4000-8000-000000000001"
        other -> assertFailure ("expected AgentParent, got " <> show other),
    testCase "Parent unknown type falls back to UnknownParent" $ do
      p <- decodeOrFail "{\"type\":\"team_id\",\"team_id\":\"x\"}"
      case p of
        UnknownParent v -> v @?= Aeson.object ["type" Aeson..= ("team_id" :: String), "team_id" Aeson..= ("x" :: String)]
        other -> assertFailure ("expected UnknownParent, got " <> show other),
    testCase "Custom emoji icon decodes nested object" $ do
      i <- decodeOrFail "{\"type\":\"custom_emoji\",\"custom_emoji\":{\"id\":\"bbbbbbbb-0000-4000-8000-000000000002\",\"name\":\"sakura\",\"url\":\"https://example.com/sakura.png\"}}"
      i @?= CustomEmojiIcon (UUID "bbbbbbbb-0000-4000-8000-000000000002"),
    testCase "Custom emoji icon encodes nested object" $
      Aeson.toJSON (CustomEmojiIcon (UUID "bbbbbbbb-0000-4000-8000-000000000002"))
        @?= Aeson.object
          [ "type" Aeson..= ("custom_emoji" :: String),
            "custom_emoji" Aeson..= Aeson.object ["id" Aeson..= ("bbbbbbbb-0000-4000-8000-000000000002" :: String)]
          ],
    testCase "Unknown icon type falls back to UnknownIcon" $ do
      i <- decodeOrFail "{\"type\":\"sticker\",\"sticker\":{}}"
      case i of
        UnknownIcon _ -> pure ()
        other -> assertFailure ("expected UnknownIcon, got " <> show other),
    testCase "Unknown mention type falls back to UnknownMention" $ do
      let mention = "{\"type\":\"future_mention\",\"future_mention\":{\"href\":\"https://example.com\",\"title\":\"Example\"}}"
          fixture =
            "{\"type\":\"mention\",\"mention\":"
              <> mention
              <> ",\"annotations\":{\"bold\":false,\"italic\":false,\"strikethrough\":false,\"underline\":false,\"code\":false,\"color\":\"default\"},\"plain_text\":\"Example\",\"href\":\"https://example.com\"}"
      rt <- decodeOrFail fixture :: IO RichText
      expected <- decodeOrFail mention :: IO Aeson.Value
      case rt of
        RichText {content = MentionContentWrapper m@(UnknownMention _)} -> Aeson.toJSON m @?= expected
        other -> assertFailure ("expected UnknownMention, got " <> show other),
    testCase "Unknown mention decodes directly as MentionContent" $ do
      m <- decodeOrFail "{\"type\":\"future_emoji\",\"future_emoji\":{\"id\":\"bbbbbbbb-0000-4000-8000-000000000002\",\"name\":\"sakura\",\"url\":\"https://example.com/sakura.png\"}}"
      case m of
        UnknownMention _ -> pure ()
        other -> assertFailure ("expected UnknownMention, got " <> show other)
  ]

------------------------------------------------------------------------------
-- Blocks, users and property values

newCodeLanguages :: [CodeLanguage]
newCodeLanguages =
  [ Abc,
    Agda,
    AsciiArt,
    Assembly,
    Bnf,
    Coq,
    Dhall,
    Ebnf,
    Hcl,
    Idris,
    LlvmIr,
    Mathematica,
    NotionFormula,
    PureScript,
    Racket,
    Smalltalk,
    Solidity,
    Toml
  ]

-- | A meeting-notes (or deprecated transcription) block object fixture.
meetingNotesBlockObject :: L8.ByteString -> L8.ByteString
meetingNotesBlockObject blockType =
  "{\"object\":\"block\",\"id\":\"dddddddd-0000-4000-8000-000000000004\","
    <> "\"parent\":{\"type\":\"page_id\",\"page_id\":\"eeeeeeee-0000-4000-8000-000000000005\"},"
    <> "\"created_time\":\"2026-09-01T10:00:00.000Z\",\"last_edited_time\":\"2026-09-01T11:00:00.000Z\","
    <> "\"created_by\":{\"object\":\"user\",\"id\":\"cccccccc-0000-4000-8000-000000000003\"},"
    <> "\"last_edited_by\":{\"object\":\"user\",\"id\":\"cccccccc-0000-4000-8000-000000000003\"},"
    <> "\"has_children\":true,\"in_trash\":false,\"archived\":false,"
    <> "\"type\":\""
    <> blockType
    <> "\",\""
    <> blockType
    <> "\":{\"title\":["
    <> richTextWithColor "default"
    <> "],\"status\":\"notes_ready\","
    <> "\"children\":{\"summary_block_id\":\"11111111-0000-4000-8000-000000000011\","
    <> "\"notes_block_id\":\"22222222-0000-4000-8000-000000000022\","
    <> "\"transcript_block_id\":\"33333333-0000-4000-8000-000000000033\"},"
    <> "\"calendar_event\":{\"start_time\":\"2026-09-01T10:00:00.000Z\",\"end_time\":\"2026-09-01T10:30:00.000Z\","
    <> "\"attendees\":[\"cccccccc-0000-4000-8000-000000000003\"]},"
    <> "\"recording\":{\"start_time\":\"2026-09-01T10:01:00.000Z\",\"end_time\":\"2026-09-01T10:29:00.000Z\"}}}"

assertMeetingNotes :: BlockContent -> Assertion
assertMeetingNotes = \case
  MeetingNotesBlock {meetingTitle, meetingStatus, calendarEvent, meetingChildren} -> do
    fmap (Vector.map (\RichText {plainText} -> plainText)) meetingTitle @?= Just (Vector.singleton "Hello")
    meetingStatus @?= Just NotesReady
    (meetingChildren >>= \MeetingNotesChildren {summaryBlockId} -> summaryBlockId)
      @?= Just (UUID "11111111-0000-4000-8000-000000000011")
    (calendarEvent >>= \MeetingCalendarEvent {calendarAttendees} -> calendarAttendees)
      @?= Just (Vector.singleton (UUID "cccccccc-0000-4000-8000-000000000003"))
  other -> assertFailure ("expected MeetingNotesBlock, got " <> show other)

blockUserPropertyTests :: [TestTree]
blockUserPropertyTests =
  [ testCase "Code block with toml language decodes" $ do
      b <- decodeOrFail "{\"type\":\"code\",\"code\":{\"rich_text\":[],\"caption\":[],\"language\":\"toml\"}}"
      case b of
        CodeBlock {language} -> language @?= Toml
        other -> assertFailure ("expected CodeBlock, got " <> show other),
    testCase "All 18 new code languages round-trip" $ do
      length newCodeLanguages @?= 18
      mapM_ (\l -> Aeson.fromJSON (Aeson.toJSON l) @?= Aeson.Success l) newCodeLanguages,
    testCase "Unknown code language falls back to OtherLanguage" $ do
      l <- decodeOrFail "\"brainfuck\""
      l @?= OtherLanguage "brainfuck"
      Aeson.encode l @?= "\"brainfuck\"",
    testCase "Meeting notes block object decodes" $ do
      BlockObject {content, type_} <- decodeOrFail (meetingNotesBlockObject "meeting_notes")
      type_ @?= "meeting_notes"
      assertMeetingNotes content,
    testCase "Deprecated transcription block decodes as meeting notes" $ do
      BlockObject {content, type_} <- decodeOrFail (meetingNotesBlockObject "transcription")
      type_ @?= "transcription"
      assertMeetingNotes content,
    testCase "Person user without email decodes" $ do
      UserObject {person} <-
        decodeOrFail "{\"object\":\"user\",\"id\":\"cccccccc-0000-4000-8000-000000000003\",\"name\":\"Tanaka Hanako\",\"avatar_url\":null,\"type\":\"person\",\"person\":{}}"
      case person of
        Just PersonUser {email} -> email @?= Nothing
        Nothing -> assertFailure "expected a person object",
    testCase "Bot user owned by a user object decodes" $ do
      UserObject {bot} <-
        decodeOrFail
          "{\"object\":\"user\",\"id\":\"ffffffff-0000-4000-8000-000000000007\",\"name\":\"Sakura Bot\",\"avatar_url\":null,\"type\":\"bot\",\"bot\":{\"owner\":{\"type\":\"user\",\"user\":{\"object\":\"user\",\"id\":\"cccccccc-0000-4000-8000-000000000003\",\"name\":\"Sato Kenji\",\"avatar_url\":null,\"type\":\"person\",\"person\":{\"email\":\"sato.kenji@example.com\"}}},\"workspace_name\":\"Sakura Studio\",\"workspace_id\":\"ws-1\",\"workspace_limits\":{\"max_file_upload_size_in_bytes\":5368709120}}}"
      case bot of
        Just BotUser {owner = Just UserOwner {type_, user}} -> do
          type_ @?= "user"
          user @?= UUID "cccccccc-0000-4000-8000-000000000003"
        other -> assertFailure ("expected a user-owned bot, got " <> show other),
    testCase "Unknown number format falls back to OtherNumberFormat" $ do
      f <- decodeOrFail "\"kenyan_shilling\""
      f @?= OtherNumberFormat "kenyan_shilling",
    testCase "Unique ID with null number decodes" $ do
      v <- decodeOrFail "{\"id\":\"a%3Db\",\"type\":\"unique_id\",\"unique_id\":{\"prefix\":\"TASK\",\"number\":null}}"
      case v of
        UniqueIdValue _ UniqueIdResult {number, prefix} -> do
          number @?= Nothing
          prefix @?= Just "TASK"
        other -> assertFailure ("expected UniqueIdValue, got " <> show other),
    testCase "Formula unsupported result decodes" $ do
      v <- decodeOrFail "{\"id\":\"f%3Dx\",\"type\":\"formula\",\"formula\":{\"type\":\"unsupported\",\"unsupported\":{}}}"
      case v of
        FormulaValue _ FormulaUnsupportedResult -> pure ()
        other -> assertFailure ("expected an unsupported formula, got " <> show other)
  ]
