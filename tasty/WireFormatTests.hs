-- | Wire-format regression tests: JSON fixtures transcribed from the official
-- Notion JS SDK types, and requests captured before they reach the network.
module WireFormatTests (tests) where

import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy.Char8 qualified as L8
import Notion.V1.Common (Color (..), Icon (..), Parent (..), UUID (..))
import Notion.V1.RichText (Annotations (..), MentionContent (..), RichText (..), RichTextContent (..))
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "WireFormat"
    [ testGroup "Common and rich text" commonTests
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
