-- | Tests for the client runtime: configuration, errors and retries.
module RuntimeTests (tests) where

import Control.Exception (SomeException, fromException, throwIO, toException, try)
import Data.Aeson qualified as Aeson
import Data.ByteString qualified as BS
import Data.ByteString.Lazy.Char8 qualified as L8
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import FakeNotion
import Network.HTTP.Client qualified as HTTP
import Network.HTTP.Types qualified as HTTP
import Notion.V1
import Notion.V1.Client (applyTimeout)
import Notion.V1.Common (UUID (..))
import Notion.V1.Error
import Notion.V1.ListOf (IncompleteReason (..), ListOf (..), RequestStatus (..), RequestStatusType (..))
import Notion.V1.Retry (canRetry, parseRetryAfter, retryDelay, validateRequestPath)
import Notion.V1.Search (SearchRequest (..))
import Servant.Client (ClientEnv (..), ClientError (..))
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Runtime"
    [ testGroup "Configuration" configurationTests,
      testGroup "Errors" errorTests,
      testGroup "Retry policy" retryPolicyTests,
      testGroup "Retry loop" retryLoopTests
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

------------------------------------------------------------------------------
-- Retries

retryPolicyTests :: [TestTree]
retryPolicyTests =
  [ testCase "canRetry follows the JS SDK rules" $ do
      canRetry HTTP.methodPost RateLimited @?= True
      canRetry HTTP.methodPost ServiceOverload @?= True
      canRetry HTTP.methodPost InternalServerError @?= False
      canRetry HTTP.methodGet InternalServerError @?= True
      canRetry HTTP.methodDelete ServiceUnavailable @?= True
      canRetry HTTP.methodPatch ServiceUnavailable @?= False
      canRetry HTTP.methodGet GatewayTimeout @?= False
      canRetry HTTP.methodGet (UnknownErrorCode "x") @?= False
      canRetry HTTP.methodGet ObjectNotFound @?= False,
    testCase "parseRetryAfter reads seconds and HTTP dates" $ do
      let now = UTCTime (fromGregorian 2015 10 21) (secondsToDiffTime (7 * 3600 + 27 * 60 + 30))
      parseRetryAfter now "120" @?= Just 120
      parseRetryAfter now "0" @?= Just 0
      parseRetryAfter now " 7" @?= Just 7
      parseRetryAfter now "1.5" @?= Just 1
      parseRetryAfter now "Wed, 21 Oct 2015 07:28:00 GMT" @?= Just 30
      parseRetryAfter now "Wed, 21 Oct 2015 07:00:00 GMT" @?= Just 0
      parseRetryAfter now "soon" @?= Nothing
      parseRetryAfter now "" @?= Nothing,
    testCase "retryDelay uses back-off with jitter and caps retry-after" $ do
      retryDelay defaultRetryOptions 0 0 Nothing @?= 0.5
      retryDelay defaultRetryOptions 1 0.5 Nothing @?= 2
      retryDelay defaultRetryOptions 10 0.9 Nothing @?= 60
      retryDelay defaultRetryOptions 0 0 (Just 120) @?= 60
      retryDelay defaultRetryOptions 0 0 (Just 5) @?= 5,
    testCase "validateRequestPath rejects path traversal" $ do
      validateRequestPath "/pages/5c6a28216bb14a7eb6e1c50111515c3d" @?= Right ()
      validateRequestPath "/pages/.." @?= Left (InvalidPathParameterError "/pages/..")
      validateRequestPath "/pages/%2E%2E" @?= Left (InvalidPathParameterError "/pages/%2E%2E")
      validateRequestPath "/pages/%252e%252e" @?= Right ()
  ]

-- | Retries with millisecond delays so the tests run quickly.
fastRetryConfig :: ClientConfig
fastRetryConfig =
  defaultClientConfig {retryOptions = defaultRetryOptions {initialRetryDelay = 0.001, maxRetryDelay = 0.01}}

errorReply :: Int -> Text -> FakeReply
errorReply status code =
  jsonReply status $
    "{\"object\":\"error\",\"status\":"
      <> L8.pack (show status)
      <> ",\"code\":\""
      <> L8.pack (Text.unpack code)
      <> "\",\"message\":\"scripted failure\"}"

rateLimitedReply :: FakeReply
rateLimitedReply =
  FakeReply
    429
    [("Content-Type", "application/json"), ("Retry-After", "0")]
    "{\"object\":\"error\",\"status\":429,\"code\":\"rate_limited\",\"message\":\"You have been rate limited. Please try again in a few minutes.\"}"

emptyListJson :: L8.ByteString
emptyListJson = "{\"object\":\"list\",\"results\":[],\"next_cursor\":null,\"has_more\":false}"

emptySearch :: SearchRequest
emptySearch = SearchRequest {query = Nothing, sort = Nothing, filter = Nothing, startCursor = Nothing, pageSize = Nothing}

-- | Run a call against a scripted fake and return the result and request count.
runScripted :: ClientConfig -> [FakeReply] -> (Methods -> IO a) -> IO (Either SomeException a, Int)
runScripted config script call = do
  (env, recorded) <- fakeClientEnv script
  result <- try (call (makeMethodsWithEnv config env "secret_tanaka"))
  n <- length <$> readIORef recorded
  pure (result, n)

expectCode :: APIErrorCode -> Either SomeException a -> Assertion
expectCode expected = \case
  Left ex | Just NotionError {code} <- fromException ex -> code @?= expected
  Left ex -> assertFailure ("expected NotionError, got " <> show ex)
  Right _ -> assertFailure "expected a failure"

retryLoopTests :: [TestTree]
retryLoopTests =
  [ testCase "GET retried after 429 then succeeds" $ do
      (result, n) <- runScripted fastRetryConfig [rateLimitedReply, jsonReply 200 userJson] retrieveMyUser
      either (assertFailure . show) (const (pure ())) result
      n @?= 2,
    testCase "POST retried after 529" $ do
      (result, n) <- runScripted fastRetryConfig [errorReply 529 "service_overload", jsonReply 200 emptyListJson] (`search` emptySearch)
      either (assertFailure . show) (const (pure ())) result
      n @?= 2,
    testCase "POST not retried on 500" $ do
      (result, n) <- runScripted fastRetryConfig [errorReply 500 "internal_server_error", jsonReply 200 emptyListJson] (`search` emptySearch)
      expectCode InternalServerError result
      n @?= 1,
    testCase "GET retried on 503 until maxRetries then throws" $ do
      (result, n) <- runScripted fastRetryConfig (replicate 3 (errorReply 503 "service_unavailable")) retrieveMyUser
      expectCode ServiceUnavailable result
      n @?= 3,
    testCase "noRetries disables retries" $ do
      (result, n) <- runScripted defaultClientConfig {retryOptions = noRetries} [rateLimitedReply, jsonReply 200 userJson] retrieveMyUser
      expectCode RateLimited result
      n @?= 1,
    testCase "withRetries wraps a plain IO action" $ do
      calls <- newIORef (0 :: Int)
      let failWith status = do
            modifyIORef' calls (+ 1)
            count <- readIORef calls
            if count == 1
              then throwIO (notionErrorFromResponse status [("Retry-After", "0")] (rateLimitedBodyFor status))
              else pure ("ok" :: Text)
      r <- withRetries fastRetryConfig HTTP.methodPost "/sessions" (failWith HTTP.status429)
      r @?= "ok"
      readIORef calls >>= (@?= 2)
      calls2 <- newIORef (0 :: Int)
      let alwaysFail = modifyIORef' calls2 (+ 1) >> throwIO (notionErrorFromResponse HTTP.status500 [] (rateLimitedBodyFor HTTP.status500))
      r2 <- try @NotionError (withRetries fastRetryConfig HTTP.methodPost "/sessions" (alwaysFail :: IO Text))
      either (\NotionError {code} -> code @?= InternalServerError) (const (assertFailure "expected failure")) r2
      readIORef calls2 >>= (@?= 1),
    testCase "HTML 429 is not retried" $ do
      (result, n) <- runScripted fastRetryConfig [FakeReply 429 [("Content-Type", "text/html")] "<html/>", jsonReply 200 userJson] retrieveMyUser
      case result of
        Left ex | Just (_ :: UnknownHTTPResponseError) <- fromException ex -> pure ()
        other -> assertFailure ("expected UnknownHTTPResponseError, got " <> either show (const "success") other)
      n @?= 1,
    testCase "logger sees retry lines" $ do
      logged <- newIORef []
      let config = fastRetryConfig {logger = Just (\_ msg _ -> modifyIORef' logged (<> [msg])), logLevel = LogDebug}
      (result, _) <- runScripted config [rateLimitedReply, jsonReply 200 userJson] retrieveMyUser
      either (assertFailure . show) (const (pure ())) result
      messages <- readIORef logged
      Prelude.filter (`elem` ["request start", "request fail", "retrying request", "request success"]) messages
        @?= ["request start", "request fail", "retrying request", "request success"],
    testCase "path traversal rejected before sending" $ do
      (result, n) <- runScripted fastRetryConfig [jsonReply 200 userJson] (`retrievePage` UUID "..")
      case result of
        Left ex | Just (_ :: InvalidPathParameterError) <- fromException ex -> pure ()
        other -> assertFailure ("expected InvalidPathParameterError, got " <> either show (const "success") other)
      n @?= 0
  ]
  where
    rateLimitedBodyFor status =
      let HTTP.Status {HTTP.statusCode = c} = status
          codeText :: L8.ByteString
          codeText = if c == 429 then "rate_limited" else "internal_server_error"
       in "{\"object\":\"error\",\"status\":" <> L8.pack (show c) <> ",\"code\":\"" <> codeText <> "\",\"message\":\"scripted failure\"}"
