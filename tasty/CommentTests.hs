-- | Comment retrieval, mutation and create-comment request shapes (EP-3).
module CommentTests (tests) where

import Data.Aeson (Value, (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy qualified as LBS
import Data.ByteString.Lazy.Char8 qualified as L8
import Data.IORef (readIORef)
import Data.Text (Text)
import Data.Vector qualified as Vector
import FakeNotion
import Notion.V1 (Methods (..), makeMethods)
import Notion.V1.BlockContent (mkRichText)
import Notion.V1.Comments
import Notion.V1.Common (Parent (..), UUID (..))
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Comment mutation (EP-3)"
    [ testCase "CommentResponse decodes a full comment" testFullComment,
      testCase "CommentResponse decodes a partial comment" testPartialComment,
      testCase "CommentResponse with parent but missing fields fails" testBrokenFullComment,
      testCase "CreateComment on a page with rich text" testCreateOnPage,
      testCase "CreateComment reply with Markdown" testReplyMarkdown,
      testCase "CreateComment attachments and custom display name" testAttachmentsAndDisplayName,
      testCase "Display name integration and user" testDisplayNames,
      testCase "Update comment body" testUpdateBody,
      testCase "Retrieve, update and delete use comments/{id}" testRoutes
    ]

fullCommentFixture :: LBS.ByteString
fullCommentFixture =
  L8.pack
    "{\"object\":\"comment\",\"id\":\"2b0c5f7e-0000-4000-8000-000000000001\",\
    \\"parent\":{\"type\":\"page_id\",\"page_id\":\"5c6a2821-0000-4000-8000-00000000000a\"},\
    \\"discussion_id\":\"f1d2d2f9-0000-4000-8000-00000000000b\",\
    \\"created_time\":\"2026-09-14T10:00:00.000Z\",\"last_edited_time\":\"2026-09-14T10:05:00.000Z\",\
    \\"created_by\":{\"object\":\"user\",\"id\":\"9a8b7c6d-0000-4000-8000-00000000000c\"},\
    \\"rich_text\":[{\"type\":\"text\",\"text\":{\"content\":\"Looks good\",\"link\":null},\
    \\"annotations\":{\"bold\":false,\"italic\":false,\"strikethrough\":false,\"underline\":false,\"code\":false,\"color\":\"default\"},\
    \\"plain_text\":\"Looks good\",\"href\":null}],\
    \\"display_name\":{\"type\":\"user\",\"resolved_name\":\"Tanaka Hanako\"},\
    \\"attachments\":[{\"category\":\"image\",\"file\":{\"url\":\"https://example.com/a.png\",\"expiry_time\":\"2026-09-14T11:00:00.000Z\"}}]}"

partialCommentFixture :: LBS.ByteString
partialCommentFixture = "{\"object\":\"comment\",\"id\":\"2b0c5f7e-0000-4000-8000-000000000002\"}"

decodeValue :: LBS.ByteString -> IO Value
decodeValue bs = either (assertFailure . ("fixture: " <>)) pure (Aeson.eitherDecode bs)

testFullComment :: Assertion
testFullComment =
  case Aeson.eitherDecode fullCommentFixture of
    Right (FullComment c@CommentObject {displayName = Just CommentDisplayName {resolvedName}}) -> do
      assertEqual "id" (UUID "2b0c5f7e-0000-4000-8000-000000000001") (commentResponseId (FullComment c))
      assertEqual "resolved name" (Just "Tanaka Hanako") resolvedName
    Right other -> assertFailure ("expected a full comment with display name, got " <> show other)
    Left err -> assertFailure err

testPartialComment :: Assertion
testPartialComment =
  case Aeson.eitherDecode partialCommentFixture of
    Right (PartialComment cid) -> assertEqual "id" (UUID "2b0c5f7e-0000-4000-8000-000000000002") cid
    Right other -> assertFailure ("expected PartialComment, got " <> show other)
    Left err -> assertFailure err

testBrokenFullComment :: Assertion
testBrokenFullComment =
  case Aeson.eitherDecode "{\"object\":\"comment\",\"id\":\"x\",\"parent\":{\"type\":\"page_id\",\"page_id\":\"p\"}}" :: Either String CommentResponse of
    Left _ -> pure ()
    Right r -> assertFailure ("expected a decoding failure, got " <> show r)

testCreateOnPage :: Assertion
testCreateOnPage =
  case Aeson.toJSON (mkCreateComment (PageParent (UUID "p-1")) (CommentRichText (mkRichText "Hello"))) of
    Aeson.Object o -> do
      assertBool "parent" (KeyMap.member "parent" o)
      assertBool "rich_text" (KeyMap.member "rich_text" o)
      mapM_
        (\k -> assertBool ("no " <> show k) (not (KeyMap.member k o)))
        ["discussion_id", "markdown", "attachments", "display_name"]
    other -> assertFailure ("expected object, got " <> show other)

testReplyMarkdown :: Assertion
testReplyMarkdown = do
  expected <- decodeValue "{\"discussion_id\":\"d-1\",\"markdown\":\"**Hi**\"}"
  assertEqual "body" expected (Aeson.toJSON (mkReplyComment (UUID "d-1") (CommentMarkdown "**Hi**")))

testAttachmentsAndDisplayName :: Assertion
testAttachmentsAndDisplayName = do
  let req =
        CreateComment
          { target = CommentOnParent (BlockParent (UUID "b-1")),
            content = CommentMarkdown "See file",
            attachments = Just (Vector.singleton (CommentAttachmentRequest (UUID "fu-1"))),
            displayName = Just (DisplayAsCustom "Sato Kenji")
          }
  expected <-
    decodeValue
      "{\"parent\":{\"type\":\"block_id\",\"block_id\":\"b-1\"},\"markdown\":\"See file\",\
      \\"attachments\":[{\"file_upload_id\":\"fu-1\",\"type\":\"file_upload\"}],\
      \\"display_name\":{\"type\":\"custom\",\"custom\":{\"name\":\"Sato Kenji\"}}}"
  assertEqual "body" expected (Aeson.toJSON req)

testDisplayNames :: Assertion
testDisplayNames = do
  assertEqual "integration" (Aeson.object ["type" .= ("integration" :: Text)]) (Aeson.toJSON DisplayAsIntegration)
  assertEqual "user" (Aeson.object ["type" .= ("user" :: Text)]) (Aeson.toJSON DisplayAsUser)

testUpdateBody :: Assertion
testUpdateBody = do
  assertEqual "markdown" (Aeson.object ["markdown" .= ("edited" :: Text)]) (Aeson.toJSON (CommentMarkdown "edited"))
  case Aeson.toJSON (CommentRichText (mkRichText "x")) of
    Aeson.Object o -> assertEqual "keys" ["rich_text"] (KeyMap.keys o)
    other -> assertFailure ("expected object, got " <> show other)

testRoutes :: Assertion
testRoutes = do
  (env, recorded) <-
    fakeClientEnv
      [jsonReply 200 fullCommentFixture, jsonReply 200 partialCommentFixture, jsonReply 200 partialCommentFixture]
  let Methods {retrieveComment, updateComment, deleteComment} = makeMethods env "secret_test"
      cid = UUID "2b0c5f7e-0000-4000-8000-000000000001"
  retrieved <- retrieveComment cid
  assertBool "retrieve decodes full" (case retrieved of FullComment _ -> True; _ -> False)
  updated <- updateComment cid (CommentMarkdown "edited")
  assertEqual "update id" (UUID "2b0c5f7e-0000-4000-8000-000000000002") (commentResponseId updated)
  _ <- deleteComment cid
  requests <- readIORef recorded
  assertEqual
    "methods and paths"
    [ ("GET", "/comments/2b0c5f7e-0000-4000-8000-000000000001"),
      ("PATCH", "/comments/2b0c5f7e-0000-4000-8000-000000000001"),
      ("DELETE", "/comments/2b0c5f7e-0000-4000-8000-000000000001")
    ]
    (map (\Recorded {method, path} -> (method, path)) requests)
