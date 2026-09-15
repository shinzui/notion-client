-- | Object field gap tests: pages, blocks, property values, mentions, users,
-- file uploads and webhooks. Fixtures are transcribed from the official Notion
-- JS SDK types.
module ObjectFieldTests (tests) where

import Control.Exception (Exception, throwIO, try)
import Data.Aeson qualified as Aeson
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
import Notion.V1.Common (UUID (..))
import Notion.V1.Pages
  ( CreatePage (..),
    InsertContentRequest (..),
    InsertPosition (..),
    MovePage (..),
    MovePageParent (..),
    UpdatePage (..),
    UpdatePageMarkdown (..),
    UpdatePageTemplate (..),
    mkUpdatePage,
  )
import Servant.Client qualified as Client
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Object Field Gaps"
    [ testGroup "Page and block requests" pageBlockRequestTests,
      testGroup "Property values and mentions" [],
      testGroup "Users, file uploads, and object types" [],
      testGroup "Webhooks" []
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
