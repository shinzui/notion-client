-- | Tests for the client runtime: configuration, errors and retries.
module RuntimeTests (tests) where

import Control.Exception (SomeException, fromException, toException, try)
import Data.Aeson qualified as Aeson
import Data.ByteString qualified as BS
import Data.ByteString.Lazy.Char8 qualified as L8
import Data.IORef (readIORef)
import Data.Text (Text)
import FakeNotion
import Network.HTTP.Client qualified as HTTP
import Network.HTTP.Types qualified as HTTP
import Notion.V1
import Notion.V1.Client (applyTimeout)
import Notion.V1.Error
import Notion.V1.ListOf (IncompleteReason (..), ListOf (..), RequestStatus (..), RequestStatusType (..))
import Servant.Client (ClientEnv (..), ClientError (..))
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Runtime"
    [ testGroup "Configuration" configurationTests,
      testGroup "Errors" errorTests
    ]

-- | A bot user fixture (made-up name).
userJson :: L8.ByteString
userJson =
  "{\"object\":\"user\",\"id\":\"6f1c2b9e-4d3a-4e8f-9b7c-2a1d0e5f3c4b\",\"name\":\"Sato Kenji Bot\",\"avatar_url\":null,\"type\":\"bot\",\"bot\":{\"owner\":{\"type\":\"workspace\",\"workspace\":true},\"workspace_name\":\"Sato Kenji's Workspace\"}}"

-- | Run one call against a fake that answers with the user fixture.
singleRequest :: (ClientEnv -> Methods) -> IO Recorded
singleRequest mk = do
  (env, recorded) <- fakeClientEnv [jsonReply 200 userJson]
  _ <- retrieveMyUser (mk env)
  readIORef recorded >>= \case
    [r] -> pure r
    rs -> assertFailure ("expected one request, got " <> show (length rs))

configurationTests :: [TestTree]
configurationTests =
  [ testCase "makeMethods sends default Notion-Version, Bearer token and User-Agent" $ do
      r <- singleRequest (`makeMethods` "secret_tanaka")
      lookupRecordedHeader "Authorization" r @?= Just "Bearer secret_tanaka"
      lookupRecordedHeader "Notion-Version" r @?= Just "2026-03-11"
      case lookupRecordedHeader "User-Agent" r of
        Just ua -> assertBool ("User-Agent: " <> show ua) ("notion-client-haskell/" `BS.isPrefixOf` ua)
        Nothing -> assertFailure "no User-Agent header"
      path r @?= "/users/me",
    testCase "makeMethodsWithEnv honors a configured Notion-Version" $ do
      r <- singleRequest (\env -> makeMethodsWithEnv defaultClientConfig {notionVersion = "2025-09-03"} env "secret_tanaka")
      lookupRecordedHeader "Notion-Version" r @?= Just "2025-09-03",
    testCase "applyTimeout sets responseTimeout" $ do
      -- ResponseTimeout has no Eq instance; compare its Show output.
      show (HTTP.responseTimeout (applyTimeoutFor (Just 5)))
        @?= show (HTTP.responseTimeoutMicro 5000000)
      show (HTTP.responseTimeout (applyTimeoutFor Nothing))
        @?= show HTTP.responseTimeoutDefault,
    testCase "standardHeaders match what Methods sends" $ do
      r <- singleRequest (`makeMethods` "secret_tanaka")
      (env, _) <- fakeClientEnv []
      let context = requestContextFor legacyClientConfig env "secret_tanaka"
          sent = [(n, v) | (n, v) <- headers r, n `elem` ["Authorization", "Notion-Version", "User-Agent"]]
      standardHeaders context @?= sent
      contextBaseUrl context @?= fakeBaseUrl
  ]
  where
    applyTimeoutFor t = applyTimeout defaultClientConfig {timeout = t} HTTP.defaultRequest

allCodeStrings :: [Text]
allCodeStrings =
  [ "unauthorized",
    "restricted_resource",
    "object_not_found",
    "rate_limited",
    "invalid_json",
    "invalid_request_url",
    "invalid_request",
    "invalid_beta",
    "validation_error",
    "conflict_error",
    "internal_server_error",
    "service_overload",
    "service_unavailable",
    "gateway_timeout"
  ]

notFoundBody :: Bool -> L8.ByteString
notFoundBody withRequestId =
  "{\"object\":\"error\",\"status\":404,\"code\":\"object_not_found\",\"message\":\"Could not find page with ID: 5c6a2821-6bb1-4a7e-b6e1-c50111515c3d.\""
    <> (if withRequestId then ",\"request_id\":\"b1e0a4c2-7f3d-4e21-9a55-1c2d3e4f5a6b\"" else "")
    <> ",\"additional_data\":{\"integration_name\":\"Tanaka Hanako Integration\"}}"

notFoundHeaders :: [(HTTP.HeaderName, BS.ByteString)]
notFoundHeaders =
  [("Content-Type", "application/json"), ("x-notion-request-id", "req-header-1"), ("cf-ray", "8a1b2c3d4e5f-NRT")]

validationBody :: L8.ByteString
validationBody =
  "{\"object\":\"error\",\"status\":400,\"code\":\"validation_error\",\"message\":\"body failed validation.\"}"

errorTests :: [TestTree]
errorTests =
  [ testCase "APIErrorCode round-trips all 14 codes" $ do
      length allCodeStrings @?= 14
      mapM_ (\t -> apiErrorCodeText (parseAPIErrorCode t) @?= t) allCodeStrings
      assertBool "all 14 are known" (all (not . isUnknown . parseAPIErrorCode) allCodeStrings)
      parseAPIErrorCode "brand_new_code" @?= UnknownErrorCode "brand_new_code",
    testCase "buildRequestError parses a Notion error with headers" $
      case buildRequestError 404 notFoundHeaders (notFoundBody True) of
        Right NotionError {code, requestId, additionalData, response} -> do
          code @?= ObjectNotFound
          requestId @?= Just "b1e0a4c2-7f3d-4e21-9a55-1c2d3e4f5a6b"
          additionalData @?= Just (Aeson.object ["integration_name" Aeson..= ("Tanaka Hanako Integration" :: Text)])
          fmap rayId response @?= Just (Just "8a1b2c3d4e5f-NRT")
          fmap httpStatus response @?= Just 404
        Left e -> assertFailure ("expected NotionError, got " <> show e),
    testCase "request_id falls back to the x-notion-request-id header" $
      case buildRequestError 404 notFoundHeaders (notFoundBody False) of
        Right NotionError {requestId} -> requestId @?= Just "req-header-1"
        Left e -> assertFailure ("expected NotionError, got " <> show e),
    testCase "Cloudflare HTML 403 becomes UnknownHTTPResponseError" $
      case buildRequestError 403 [("content-type", "text/html"), ("cf-ray", "8a1b2c3d4e5f-NRT")] "<html>blocked</html>" of
        Left e ->
          unknownResponseMessage e
            @?= "Request to Notion API failed with status: 403. The response was returned by Notion's edge proxy before reaching the Notion API (content-type: text/html). This may mean the request was blocked by a network security rule. Cloudflare Ray ID: 8a1b2c3d4e5f-NRT. Include this ID when contacting Notion support."
        Right e -> assertFailure ("expected UnknownHTTPResponseError, got " <> show e),
    testCase "non-JSON 502 without cf-ray has the short message" $
      case buildRequestError 502 [("content-type", "text/plain")] "Bad Gateway" of
        Left e -> unknownResponseMessage e @?= "Request to Notion API failed with status: 502"
        Right e -> assertFailure ("expected UnknownHTTPResponseError, got " <> show e),
    testCase "timeouts become RequestTimeoutError" $ do
      let timeoutErr = ConnectionError (toException (HTTP.HttpExceptionRequest HTTP.defaultRequest HTTP.ResponseTimeout))
      fromExceptionOf (fromClientError timeoutErr) @?= Just RequestTimeoutError,
    testCase "makeMethods throws a typed NotionError" $ do
      (env, _) <- fakeClientEnv [FakeReply 400 [("Content-Type", "application/json"), ("x-notion-request-id", "req-9")] validationBody]
      result <- try @NotionError (retrieveMyUser (makeMethodsWithEnv defaultClientConfig {retryOptions = noRetries} env "secret_tanaka"))
      case result of
        Left NotionError {code, requestId, response} -> do
          code @?= ValidationError
          requestId @?= Just "req-9"
          fmap httpStatus response @?= Just 400
        Right _ -> assertFailure "expected a NotionError",
    testCase "ListOf decodes request_status" $ do
      let listWith extra =
            "{\"object\":\"list\",\"results\":[],\"next_cursor\":null,\"has_more\":false,\"type\":\"page_or_data_source\",\"page_or_data_source\":{}"
              <> extra
              <> "}"
          decodeStatus :: L8.ByteString -> Either String (Maybe RequestStatus)
          decodeStatus bytes = (\List {requestStatus} -> requestStatus) <$> (Aeson.eitherDecode bytes :: Either String (ListOf Aeson.Value))
      decodeStatus (listWith ",\"request_status\":{\"type\":\"incomplete\",\"incomplete_reason\":\"query_result_limit_reached\"}")
        @?= Right (Just (RequestStatus RequestIncomplete (Just QueryResultLimitReached)))
      decodeStatus (listWith "") @?= Right Nothing
      decodeStatus (listWith ",\"request_status\":{\"type\":\"partial\"}")
        @?= Right (Just (RequestStatus (UnknownRequestStatusType "partial") Nothing))
  ]
  where
    isUnknown = \case
      UnknownErrorCode _ -> True
      _ -> False
    fromExceptionOf :: SomeException -> Maybe RequestTimeoutError
    fromExceptionOf = fromException
