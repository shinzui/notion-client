-- | Object field gap tests: pages, blocks, property values, mentions, users,
-- file uploads and webhooks. Fixtures are transcribed from the official Notion
-- JS SDK types.
module ObjectFieldTests (tests) where

import Control.Exception (Exception, throwIO, try)
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (parseEither)
import Data.ByteString.Char8 qualified as B8
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Map qualified as Map
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Data.Vector qualified as Vector
import Network.HTTP.Client qualified as HTTP
import Notion.V1 (Methods (..), makeMethods)
import Notion.V1.BlockContent
  ( BlockContent (..),
    BlockUpdateContent (..),
    MediaSourceUpdate (..),
    MediaUpdate (..),
    TableUpdate (..),
    ToDoUpdate (..),
    blockUpdateFromContent,
    mkBlockUpdate,
    parseBlockContent,
    trashBlockUpdate,
  )
import Notion.V1.Clearable (Clearable (..))
import Notion.V1.Common (CustomEmojiRef (..), Icon (..), NoticonColor (..), ObjectType (..), UUID (..))
import Notion.V1.FileUploads qualified as FU
import Notion.V1.Pages
  ( CreatePage (..),
    InsertContentRequest (..),
    InsertPosition (..),
    MovePage (..),
    MovePageParent (..),
    PageMarkdown (..),
    PropertyItemList (..),
    PropertyItemResponse (..),
    UpdatePage (..),
    UpdatePageMarkdown (..),
    UpdatePageTemplate (..),
    mkUpdatePage,
  )
import Notion.V1.PropertyValue
  ( Place (..),
    PropertyValue (..),
    RollupResult (..),
    SelectOptionValue (..),
    VerificationResult (..),
    VerificationState (..),
    unverifiedValue,
  )
import Notion.V1.RichText (LinkMentionValue (..), MentionContent (..), RichText (..), RichTextContent (..))
import Notion.V1.Users (GroupObject (..), PeopleEntry (..), UserObject (..), UserType (..), UserValue (..))
import Notion.V1.Webhooks
  ( EntityType (..),
    EventType (..),
    PropertyAction (..),
    UpdatedPropertySchema (..),
    ViewField (..),
    WebhookBlockRef (..),
    WebhookEntity (..),
    WebhookEvent (..),
    WebhookEventData (..),
    WebhookParent (..),
    WebhookParentType (..),
    WebhookRefType (..),
  )
import Servant.Client qualified as Client
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Object Field Gaps"
    [ testGroup "Page and block requests" pageBlockRequestTests,
      testGroup "Property values and mentions" propertyValueMentionTests,
      testGroup "Users, file uploads, and object types" userFileUploadObjectTypeTests,
      testGroup "Webhooks" webhookTests
    ]

------------------------------------------------------------------------------
-- Helpers

-- | Decode a JSON literal or fail the test with aeson's message. Fixtures are
-- 'Text' so that non-ASCII content is encoded as UTF-8.
decodeOrFail :: (Aeson.FromJSON a) => Text -> IO a
decodeOrFail t =
  either (assertFailure . ("decode failed: " <>)) pure (Aeson.eitherDecode (LBS.fromStrict (TE.encodeUtf8 t)))

-- | Decode a JSON literal as a generic value.
value :: Text -> IO Aeson.Value
value = decodeOrFail

-- | Assert that a value encodes to exactly the given JSON.
encodesTo :: (Aeson.ToJSON a) => a -> Text -> Assertion
encodesTo x expected = do
  e <- value expected
  Aeson.toJSON x @?= e

data RequestCaptured = RequestCaptured
  deriving stock (Show)

instance Exception RequestCaptured

-- | Run a 'Methods' call and capture the HTTP request it builds, aborting
-- before any network I/O happens.
captureRequest :: (Methods -> IO a) -> IO HTTP.Request
captureRequest call = do
  ref <- newIORef Nothing
  manager <- HTTP.newManager HTTP.defaultManagerSettings
  let env0 = Client.mkClientEnv manager (Client.BaseUrl Client.Https "api.notion.com" 443 "/v1")
      env =
        env0
          { Client.makeClientRequest = \burl req -> do
              built <- Client.defaultMakeClientRequest burl req
              writeIORef ref (Just built)
              throwIO RequestCaptured
          }
  _ <- try @RequestCaptured (call (makeMethods env "secret_test_token"))
  readIORef ref >>= maybe (assertFailure "no request was built") pure

------------------------------------------------------------------------------
-- Milestone 1: page and block requests

emptyCreatePage :: CreatePage
emptyCreatePage =
  CreatePage
    { parent = Nothing,
      properties = Map.empty,
      children = Nothing,
      markdown = Nothing,
      icon = Nothing,
      cover = Nothing,
      template = Nothing,
      position = Nothing
    }

trashOnlyUpdatePage :: UpdatePage
trashOnlyUpdatePage =
  let UpdatePage {..} = mkUpdatePage Map.empty
   in UpdatePage {inTrash = Just True, ..}

pageBlockRequestTests :: [TestTree]
pageBlockRequestTests =
  [ testCase "CreatePage without parent or properties omits both keys" $ do
      let CreatePage {..} = emptyCreatePage
      CreatePage {markdown = Just "# こんにちは", ..} `encodesTo` "{\"markdown\":\"# こんにちは\"}",
    testCase "UpdatePage with only in_trash encodes exactly that key" $
      trashOnlyUpdatePage `encodesTo` "{\"in_trash\":true}",
    testCase "UpdatePage clears icon and cover with null" $ do
      let UpdatePage {..} = mkUpdatePage Map.empty
      UpdatePage {icon = Clear, cover = Clear, ..} `encodesTo` "{\"icon\":null,\"cover\":null}",
    testCase "UpdatePageTemplate by ID has no none variant" $
      UpdateTemplateById (UUID "tpl-1") Nothing `encodesTo` "{\"type\":\"template_id\",\"template_id\":\"tpl-1\"}",
    testCase "MovePage to a data source has no position" $
      MovePage {parent = MoveToDataSource (UUID "ds-1")}
        `encodesTo` "{\"parent\":{\"type\":\"data_source_id\",\"data_source_id\":\"ds-1\"}}",
    testCase "insert_content at start encodes position" $
      InsertContent (InsertContentRequest "- item" Nothing (Just InsertAtStart))
        `encodesTo` "{\"type\":\"insert_content\",\"insert_content\":{\"content\":\"- item\",\"position\":{\"type\":\"start\"}}}",
    testCase "createPageFiltered sends filter_properties as query parameters" $ do
      req <- captureRequest $ \m -> createPageFiltered m ["title", "Xy12"] emptyCreatePage
      assertBool
        ("query string: " <> B8.unpack (HTTP.queryString req))
        ("filter_properties=title&filter_properties=Xy12" `B8.isInfixOf` HTTP.queryString req)
      HTTP.method req @?= "POST",
    testCase "updatePageFiltered sends filter_properties as query parameters" $ do
      req <- captureRequest $ \m -> updatePageFiltered m (UUID "p-1") ["title"] trashOnlyUpdatePage
      assertBool
        ("query string: " <> B8.unpack (HTTP.queryString req))
        ("filter_properties=title" `B8.isInfixOf` HTTP.queryString req)
      HTTP.method req @?= "PATCH",
    testCase "to_do update with only checked" $
      mkBlockUpdate (UpdateToDo (ToDoUpdate Nothing (Just True) Nothing))
        `encodesTo` "{\"to_do\":{\"checked\":true}}",
    testCase "table update carries only header flags" $
      mkBlockUpdate (UpdateTable (TableUpdate (Just True) Nothing))
        `encodesTo` "{\"table\":{\"has_column_header\":true}}",
    testCase "blockUpdateFromContent drops table_width and children" $ do
      let table = TableBlock 3 True False (Vector.singleton (TableRowBlock Vector.empty))
      case blockUpdateFromContent table of
        Just c -> mkBlockUpdate c `encodesTo` "{\"table\":{\"has_column_header\":true,\"has_row_header\":false}}"
        Nothing -> assertFailure "tables are updatable",
    testCase "trashBlockUpdate encodes in_trash only" $
      trashBlockUpdate `encodesTo` "{\"in_trash\":true}",
    testCase "image update via file upload" $
      mkBlockUpdate (UpdateImage (MediaUpdate Nothing (Just (UpdateFileUploadSource (UUID "fu-1")))))
        `encodesTo` "{\"image\":{\"file_upload\":{\"id\":\"fu-1\"}}}",
    testCase "blockUpdateFromContent rejects child pages" $
      blockUpdateFromContent (ChildPageBlock "x") @?= Nothing,
    testCase "audio block decodes caption" $ do
      empty <- value "{\"type\":\"external\",\"external\":{\"url\":\"https://example.com/a.mp3\"},\"caption\":[]}"
      case parseEither (parseBlockContent "audio") empty of
        Right AudioBlock {caption} -> Vector.length caption @?= 0
        other -> assertFailure ("expected AudioBlock, got " <> show other)
      one <-
        value
          "{\"type\":\"external\",\"external\":{\"url\":\"https://example.com/a.mp3\"},\"caption\":[{\"type\":\"text\",\"text\":{\"content\":\"録音\",\"link\":null},\"annotations\":{\"bold\":false,\"italic\":false,\"strikethrough\":false,\"underline\":false,\"code\":false,\"color\":\"default\"},\"plain_text\":\"録音\",\"href\":null}]}"
      case parseEither (parseBlockContent "audio") one of
        Right AudioBlock {caption} -> Vector.length caption @?= 1
        other -> assertFailure ("expected AudioBlock, got " <> show other),
    testCase "embed block decodes caption" $ do
      v <- value "{\"url\":\"https://example.com\",\"caption\":[]}"
      case parseEither (parseBlockContent "embed") v of
        Right EmbedBlock {url} -> url @?= "https://example.com"
        other -> assertFailure ("expected EmbedBlock, got " <> show other),
    testCase "unsupported block keeps block_type" $ do
      v <- value "{\"block_type\":\"form\"}"
      parseEither (parseBlockContent "unsupported") v @?= Right (UnsupportedBlock (Just "form"))
  ]

------------------------------------------------------------------------------
-- Milestone 2: property values and mentions

-- | A rich-text item wrapping the given mention object.
mentionRichText :: Text -> Text
mentionRichText mention =
  "{\"type\":\"mention\",\"mention\":"
    <> mention
    <> ",\"annotations\":{\"bold\":false,\"italic\":false,\"strikethrough\":false,\"underline\":false,\"code\":false,\"color\":\"default\"},\"plain_text\":\"@\",\"href\":null}"

-- | Decode a rich-text mention fixture and return its mention.
decodeMention :: Text -> IO MentionContent
decodeMention mention = do
  rt <- decodeOrFail (mentionRichText mention)
  case rt of
    RichText {content = MentionContentWrapper m} -> pure m
    other -> assertFailure ("expected a mention, got " <> show other)

propertyValueMentionTests :: [TestTree]
propertyValueMentionTests =
  [ testCase "select option with description encodes" $
      SelectValue "" (Just (SelectOptionValue Nothing "急ぎ" Nothing (Just "今日中")))
        `encodesTo` "{\"select\":{\"name\":\"急ぎ\",\"description\":\"今日中\"}}",
    testCase "people with partial user, full user and group decodes" $ do
      pv <-
        decodeOrFail
          "{\"id\":\"p1\",\"type\":\"people\",\"people\":[{\"object\":\"user\",\"id\":\"u1\"},{\"object\":\"user\",\"id\":\"u2\",\"type\":\"person\",\"name\":\"Tanaka Hanako\",\"avatar_url\":null,\"person\":{\"email\":\"hanako@example.com\"}},{\"object\":\"group\",\"id\":\"g1\",\"name\":\"Design Team\"}]}"
      case pv of
        PeopleValue "p1" entries -> case Vector.toList entries of
          [PersonEntry (PartialUser (UUID "u1")), PersonEntry (FullUser UserObject {name}), GroupEntry GroupObject {name = groupName}] -> do
            name @?= Just "Tanaka Hanako"
            groupName @?= Just "Design Team"
          other -> assertFailure ("unexpected entries: " <> show other)
        other -> assertFailure ("expected PeopleValue, got " <> show other),
    testCase "group people entry encodes" $
      GroupEntry (GroupObject (UUID "g1") (Just "Design Team"))
        `encodesTo` "{\"object\":\"group\",\"id\":\"g1\",\"name\":\"Design Team\"}",
    testCase "place decodes" $ do
      pv <-
        decodeOrFail
          "{\"id\":\"p2\",\"type\":\"place\",\"place\":{\"lat\":35.6812,\"lon\":139.7671,\"name\":\"東京駅\",\"address\":null,\"google_place_id\":\"abc\"}}"
      case pv of
        PlaceValue _ (Just Place {lat, name, googlePlaceId}) -> do
          lat @?= 35.6812
          name @?= Just "東京駅"
          googlePlaceId @?= Just "abc"
        other -> assertFailure ("expected PlaceValue, got " <> show other),
    testCase "verification decodes state, date and verifier" $ do
      pv <-
        decodeOrFail
          "{\"id\":\"p3\",\"type\":\"verification\",\"verification\":{\"state\":\"expired\",\"date\":{\"start\":\"2026-01-01\",\"end\":null,\"time_zone\":null},\"verified_by\":{\"object\":\"user\",\"id\":\"u3\"}}}"
      case pv of
        VerificationValue _ (Just VerificationResult {state, verifiedBy}) -> do
          state @?= Expired
          verifiedBy @?= Just (PartialUser (UUID "u3"))
        other -> assertFailure ("expected VerificationValue, got " <> show other)
      unknown <- decodeOrFail "{\"id\":\"p4\",\"type\":\"verification\",\"verification\":{\"state\":\"pending_review\",\"date\":null,\"verified_by\":null}}"
      case unknown of
        VerificationValue _ (Just VerificationResult {state}) -> state @?= UnknownVerificationState "pending_review"
        other -> assertFailure ("expected VerificationValue, got " <> show other),
    testCase "unverifiedValue encodes the request shape" $
      unverifiedValue `encodesTo` "{\"verification\":{\"state\":\"unverified\"}}",
    testCase "rollup array decodes typed property values" $ do
      pv <-
        decodeOrFail
          "{\"id\":\"p5\",\"type\":\"rollup\",\"rollup\":{\"type\":\"array\",\"function\":\"show_original\",\"array\":[{\"type\":\"number\",\"number\":3},{\"type\":\"title\",\"title\":[]}]}}"
      case pv of
        RollupValue _ (RollupArrayResult values _) -> case Vector.toList values of
          [NumberValue "" (Just 3), TitleValue "" _] -> pure ()
          other -> assertFailure ("unexpected rollup values: " <> show other)
        other -> assertFailure ("expected RollupValue, got " <> show other),
    testCase "unknown property type decodes to UnknownPropertyValue" $ do
      pv <- decodeOrFail "{\"id\":\"p6\",\"type\":\"hologram\",\"hologram\":{\"x\":1}}"
      case pv of
        UnknownPropertyValue "p6" "hologram" _ -> pv `encodesTo` "{\"hologram\":{\"x\":1}}"
        other -> assertFailure ("expected UnknownPropertyValue, got " <> show other),
    testCase "paginated rollup property item decodes next_url and summary" $ do
      r <-
        decodeOrFail
          "{\"object\":\"list\",\"type\":\"property_item\",\"results\":[],\"next_cursor\":null,\"has_more\":false,\"property_item\":{\"id\":\"r1\",\"type\":\"rollup\",\"next_url\":\"https://api.notion.com/v1/pages/x/properties/r1?start_cursor=abc\",\"rollup\":{\"type\":\"number\",\"number\":7,\"function\":\"count\"}}}"
      case r of
        PaginatedPropertyItems PropertyItemList {propertyType, propertyId, nextUrl, rollup} -> do
          propertyType @?= "rollup"
          propertyId @?= "r1"
          nextUrl @?= Just "https://api.notion.com/v1/pages/x/properties/r1?start_cursor=abc"
          case rollup of
            Just (RollupNumberResult (Just 7) _) -> pure ()
            other -> assertFailure ("unexpected rollup: " <> show other)
        other -> assertFailure ("expected PaginatedPropertyItems, got " <> show other),
    testCase "link_mention decodes" $ do
      m <- decodeMention "{\"type\":\"link_mention\",\"link_mention\":{\"href\":\"https://github.com\",\"title\":\"GitHub\",\"padding_top\":12}}"
      case m of
        LinkMention LinkMentionValue {href, title, paddingTop} -> do
          href @?= "https://github.com"
          title @?= Just "GitHub"
          paddingTop @?= Just 12
        other -> assertFailure ("expected LinkMention, got " <> show other),
    testCase "custom_emoji mention decodes and re-encodes" $ do
      m <- decodeMention "{\"type\":\"custom_emoji\",\"custom_emoji\":{\"id\":\"e1\",\"name\":\"bufo\",\"url\":\"https://example.com/bufo.png\"}}"
      m @?= CustomEmojiMention (CustomEmojiRef (UUID "e1") (Just "bufo") (Just "https://example.com/bufo.png"))
      m `encodesTo` "{\"type\":\"custom_emoji\",\"custom_emoji\":{\"id\":\"e1\",\"name\":\"bufo\",\"url\":\"https://example.com/bufo.png\"}}",
    testCase "user mention keeps the full user" $ do
      m <- decodeMention "{\"type\":\"user\",\"user\":{\"object\":\"user\",\"id\":\"u9\",\"type\":\"person\",\"name\":\"Sato Kenji\",\"avatar_url\":null,\"person\":{}}}"
      case m of
        UserMention (FullUser UserObject {name}) -> name @?= Just "Sato Kenji"
        other -> assertFailure ("expected a full user mention, got " <> show other)
      partial <- decodeMention "{\"type\":\"user\",\"user\":{\"object\":\"user\",\"id\":\"u10\"}}"
      partial @?= UserMention (PartialUser (UUID "u10"))
  ]

------------------------------------------------------------------------------
-- Milestone 3: users, file uploads, icons and object types

userFileUploadObjectTypeTests :: [TestTree]
userFileUploadObjectTypeTests =
  [ testCase "custom emoji icon keeps name and url" $ do
      let fixture = "{\"type\":\"custom_emoji\",\"custom_emoji\":{\"id\":\"e2\",\"name\":\"sakura\",\"url\":\"https://example.com/sakura.png\"}}"
      i <- decodeOrFail fixture
      i @?= CustomEmojiIcon (CustomEmojiRef (UUID "e2") (Just "sakura") (Just "https://example.com/sakura.png"))
      i `encodesTo` fixture,
    testCase "native icon with an unknown color" $ do
      i <- decodeOrFail "{\"type\":\"icon\",\"icon\":{\"name\":\"pizza\",\"color\":\"teal\"}}"
      i @?= NativeIcon "pizza" (Just (UnknownNoticonColor "teal")),
    testCase "ObjectType new and unknown values" $ do
      let known =
            [ (FileUploadObjectType, "file_upload"),
              (PageMarkdownObjectType, "page_markdown"),
              (AsyncTaskObjectType, "async_task"),
              (GroupObjectType, "group"),
              (DataSource, "data_source")
            ]
      mapM_
        ( \(ot, str) -> do
            decoded <- decodeOrFail ("\"" <> str <> "\"")
            decoded @?= ot
            Aeson.toJSON ot @?= Aeson.String str
        )
        known
      unknown <- decodeOrFail "\"meeting_room\""
      unknown @?= UnknownObjectType "meeting_room",
    testCase "PageMarkdown decodes object, with or without the key" $ do
      md <- decodeOrFail "{\"object\":\"page_markdown\",\"id\":\"p1\",\"markdown\":\"# hi\",\"truncated\":false,\"unknown_block_ids\":[]}"
      let PageMarkdown {object} = md
      object @?= PageMarkdownObjectType
      legacy <- decodeOrFail "{\"id\":\"p1\",\"markdown\":\"# hi\",\"truncated\":false,\"unknown_block_ids\":[]}"
      let PageMarkdown {object = legacyObject} = legacy
      legacyObject @?= PageMarkdownObjectType,
    testCase "file upload with URLs and an agent creator" $ do
      fu <-
        decodeOrFail
          "{\"object\":\"file_upload\",\"id\":\"fu1\",\"created_time\":\"2026-09-14T10:00:00.000Z\",\"last_edited_time\":\"2026-09-14T10:00:00.000Z\",\"created_by\":{\"id\":\"a1\",\"type\":\"agent\"},\"in_trash\":false,\"archived\":false,\"expiry_time\":null,\"status\":\"pending\",\"filename\":null,\"content_type\":null,\"content_length\":null,\"upload_url\":\"https://api.notion.com/v1/file_uploads/fu1/send\",\"complete_url\":\"https://api.notion.com/v1/file_uploads/fu1/complete\"}"
      let FU.FileUploadObject {createdBy, uploadUrl, completeUrl} = fu
      createdBy @?= FU.FileUploadCreator (UUID "a1") FU.CreatorAgent
      uploadUrl @?= Just "https://api.notion.com/v1/file_uploads/fu1/send"
      completeUrl @?= Just "https://api.notion.com/v1/file_uploads/fu1/complete",
    testCase "CreateFileUpload encodes a typed mode" $
      case Aeson.toJSON (FU.mkMultiPartUpload "動画.mp4" 3 Nothing) of
        Aeson.Object o -> KeyMap.lookup "mode" o @?= Just (Aeson.String "multi_part")
        other -> assertFailure ("expected object, got " <> show other),
    testCase "bot user with an empty bot object decodes" $ do
      u <- decodeOrFail "{\"object\":\"user\",\"id\":\"b1\",\"type\":\"bot\",\"name\":\"Kaizen Bot\",\"avatar_url\":null,\"bot\":{}}"
      let UserObject {type_} = u
      type_ @?= Bot
  ]

------------------------------------------------------------------------------
-- Milestone 4: webhooks

-- | Decode a webhook event built from a shared base payload plus the given
-- @type@, @entity@ and (optionally) @data@ JSON fragments.
decodeEvent :: Text -> Text -> Maybe Text -> IO WebhookEvent
decodeEvent eventType entity mData =
  decodeOrFail $
    "{\"id\":\"evt-1\",\"timestamp\":\"2026-09-14T10:00:00.000Z\",\"workspace_id\":\"ws-1\",\"workspace_name\":\"Yamada Lab\",\"subscription_id\":\"sub-1\",\"integration_id\":\"int-1\",\"authors\":[{\"id\":\"u1\",\"type\":\"person\"}],\"attempt_number\":1,\"api_version\":\"2026-03-11\",\"type\":\""
      <> eventType
      <> "\",\"entity\":"
      <> entity
      <> maybe "" (",\"data\":" <>) mData
      <> "}"

webhookTests :: [TestTree]
webhookTests =
  [ testCase "file_upload.upload_failed" $ do
      e <-
        decodeEvent
          "file_upload.upload_failed"
          "{\"id\":\"fu-1\",\"type\":\"file_upload\"}"
          (Just "{\"file_import_result\":{\"type\":\"error\",\"imported_time\":\"2026-09-14T10:00:00.000Z\",\"error\":{\"type\":\"download_error\",\"code\":\"timeout\",\"message\":\"Download timed out\",\"parameter\":null,\"status_code\":504}}}")
      let WebhookEvent {type_, entity = WebhookEntity {type_ = entityType}, workspaceName, apiVersion, data_} = e
      type_ @?= FileUploadUploadFailed
      entityType @?= FileUploadEntity
      workspaceName @?= Just "Yamada Lab"
      apiVersion @?= Just "2026-03-11"
      case data_ of
        Just (FileUploadFailedData FU.FileImportError {errorCode, errorStatusCode}) -> do
          errorCode @?= "timeout"
          errorStatusCode @?= Just 504
        other -> assertFailure ("expected FileUploadFailedData, got " <> show other),
    testCase "file_upload.created has no data" $ do
      e <- decodeEvent "file_upload.created" "{\"id\":\"fu-1\",\"type\":\"file_upload\"}" Nothing
      let WebhookEvent {type_, data_} = e
      type_ @?= FileUploadCreated
      case data_ of
        Nothing -> pure ()
        other -> assertFailure ("expected no data, got " <> show other),
    testCase "page.transcription_block.transcript_deleted" $ do
      e <-
        decodeEvent
          "page.transcription_block.transcript_deleted"
          "{\"id\":\"b1\",\"type\":\"page\"}"
          (Just "{\"target\":{\"id\":\"b1\",\"type\":\"block\"},\"transcript_id\":null}")
      let WebhookEvent {type_, data_} = e
      type_ @?= PageTranscriptBlockTranscriptDeleted
      case data_ of
        Just (TranscriptDeletedData ref tid) -> do
          ref @?= WebhookBlockRef (UUID "b1") WebhookRefBlock
          tid @?= Nothing
        other -> assertFailure ("expected TranscriptDeletedData, got " <> show other),
    testCase "database.content_updated on a linked database block" $ do
      e <-
        decodeEvent
          "database.content_updated"
          "{\"id\":\"d1\",\"type\":\"block\"}"
          (Just "{\"parent\":{\"id\":\"p1\",\"type\":\"page\"},\"updated_blocks\":[{\"id\":\"b2\",\"type\":\"block\"}]}")
      let WebhookEvent {entity = WebhookEntity {type_ = entityType}, data_} = e
      entityType @?= BlockEntity
      case data_ of
        Just (ContentUpdatedData WebhookParent {type_ = parentType} refs) -> do
          parentType @?= WebhookParentPage
          Vector.toList refs @?= [WebhookBlockRef (UUID "b2") WebhookRefBlock]
        other -> assertFailure ("expected ContentUpdatedData, got " <> show other),
    testCase "data_source.schema_updated" $ do
      e <-
        decodeEvent
          "data_source.schema_updated"
          "{\"id\":\"ds1\",\"type\":\"data_source\"}"
          (Just "{\"parent\":{\"id\":\"db1\",\"type\":\"database\",\"data_source_id\":\"ds1\"},\"updated_properties\":[{\"id\":\"abc\",\"name\":null,\"action\":\"deleted\"}]}")
      case e of
        WebhookEvent {data_ = Just (SchemaUpdatedData WebhookParent {dataSourceId} props)} -> do
          dataSourceId @?= Just (UUID "ds1")
          Vector.toList props @?= [UpdatedPropertySchema "abc" Nothing PropertyDeleted]
        other -> assertFailure ("expected SchemaUpdatedData, got " <> show other),
    testCase "page.properties_updated" $ do
      e <-
        decodeEvent
          "page.properties_updated"
          "{\"id\":\"p1\",\"type\":\"page\"}"
          (Just "{\"parent\":{\"id\":\"s1\",\"type\":\"space\"},\"updated_properties\":[\"title\",\"xyz\"]}")
      case e of
        WebhookEvent {data_ = Just (PagePropertiesUpdatedData WebhookParent {type_ = parentType} props)} -> do
          parentType @?= WebhookParentSpace
          Vector.toList props @?= ["title", "xyz"]
        other -> assertFailure ("expected PagePropertiesUpdatedData, got " <> show other),
    testCase "view.updated" $ do
      e <-
        decodeEvent
          "view.updated"
          "{\"id\":\"v1\",\"type\":\"view\"}"
          (Just "{\"parent\":{\"id\":\"db1\",\"type\":\"database\"},\"updated_fields\":[\"filter\",\"sorts\"]}")
      case e of
        WebhookEvent {data_ = Just (ViewUpdatedData _ fields)} -> Vector.toList fields @?= [ViewFieldFilter, ViewFieldSorts]
        other -> assertFailure ("expected ViewUpdatedData, got " <> show other),
    testCase "comment.created" $ do
      e <-
        decodeEvent
          "comment.created"
          "{\"id\":\"c1\",\"type\":\"comment\"}"
          (Just "{\"parent\":{\"id\":\"p1\",\"type\":\"page\"},\"page_id\":\"p1\"}")
      case e of
        WebhookEvent {data_ = Just (CommentEventData ref pid)} -> do
          ref @?= WebhookBlockRef (UUID "p1") WebhookRefPage
          pid @?= UUID "p1"
        other -> assertFailure ("expected CommentEventData, got " <> show other),
    testCase "mismatched data falls back to RawEventData" $ do
      e <- decodeEvent "page.created" "{\"id\":\"p1\",\"type\":\"page\"}" (Just "{\"unexpected\":true}")
      case e of
        WebhookEvent {data_ = Just (RawEventData raw)} -> raw `encodesTo` "{\"unexpected\":true}"
        other -> assertFailure ("expected RawEventData, got " <> show other),
    testCase "typed event data re-encodes to the wire shape" $
      ContentUpdatedData (WebhookParent (UUID "p1") WebhookParentPage Nothing) (Vector.singleton (WebhookBlockRef (UUID "b2") WebhookRefBlock))
        `encodesTo` "{\"parent\":{\"id\":\"p1\",\"type\":\"page\"},\"updated_blocks\":[{\"id\":\"b2\",\"type\":\"block\"}]}"
  ]
