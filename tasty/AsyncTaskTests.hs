-- | Async task decoding, @allow_async@ requests and polling (EP-3).
module AsyncTaskTests (tests) where

import Control.Exception (Exception, throwIO, try)
import Data.Aeson (Value)
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (atomicModifyIORef', newIORef, readIORef, writeIORef)
import Data.Map qualified as Map
import FakeNotion
import Network.HTTP.Client qualified as HTTP
import Notion.V1 (Methods (..), makeMethods)
import Notion.V1.AsyncTasks
import Notion.V1.Common (Parent (..), UUID (..))
import Notion.V1.Error (APIErrorCode (..))
import Notion.V1.Pages (CreatePage (..), ReplaceContentRequest (..), UpdatePageMarkdown (..), mkCreatePage)
import Servant.Client qualified as Client
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Async tasks (EP-3)"
    [ testCase "Decode running task" testRunning,
      testCase "Decode succeeded task" testSucceeded,
      testCase "Decode failed task" testFailed,
      testCase "Unknown status and surface are tolerated" testUnknown,
      testCase "AsyncTask round-trips" testRoundTrip,
      testCase "AsyncOr picks async_task" testAsyncOr,
      testCase "AllowAsync adds the flag" testAllowAsync,
      testCase "waitForAsyncTask polls until terminal" testWaitUntilTerminal,
      testCase "waitForAsyncTask stops at maxAttempts" testWaitMaxAttempts,
      testCase "createPageAsync sends allow_async to POST /pages" testCreatePageAsyncRequest,
      testCase "retrieveAsyncTask and updatePageMarkdownAsync (202) routes" testRoutes
    ]

runningFixture :: LBS.ByteString
runningFixture =
  "{\"object\":\"async_task\",\"id\":\"task_01\",\
  \\"status_url\":\"https://api.notion.com/v1/async_tasks/task_01\",\
  \\"created_time\":\"2026-09-14T10:00:00.000Z\",\
  \\"operation\":{\"surface\":\"rest\",\"name\":\"pages.create\"},\
  \\"status\":\"running\",\"poll_after_seconds\":2}"

succeededFixture :: LBS.ByteString
succeededFixture =
  "{\"object\":\"async_task\",\"id\":\"task_01\",\
  \\"status_url\":\"https://api.notion.com/v1/async_tasks/task_01\",\
  \\"created_time\":\"2026-09-14T10:00:00.000Z\",\
  \\"operation\":{\"surface\":\"rest\",\"name\":\"pages.create\"},\
  \\"status\":\"succeeded\",\"result\":{\"page_id\":\"5c6a2821-0000-4000-8000-00000000000a\"}}"

failedFixture :: LBS.ByteString
failedFixture =
  "{\"object\":\"async_task\",\"id\":\"task_02\",\
  \\"status_url\":\"https://api.notion.com/v1/async_tasks/task_02\",\
  \\"created_time\":\"2026-09-14T10:00:00.000Z\",\
  \\"operation\":{\"surface\":\"mcp\",\"name\":\"pages.update_markdown\"},\
  \\"status\":\"failed\",\"error\":{\"object\":\"error\",\"status\":400,\
  \\"code\":\"validation_error\",\"message\":\"markdown is required\",\
  \\"additional_data\":{\"field\":[\"markdown\"]}}}"

unknownFixture :: LBS.ByteString
unknownFixture =
  "{\"object\":\"async_task\",\"id\":\"task_03\",\
  \\"status_url\":\"https://api.notion.com/v1/async_tasks/task_03\",\
  \\"created_time\":\"2026-09-14T10:00:00.000Z\",\
  \\"operation\":{\"surface\":\"cli\",\"name\":\"pages.create\"},\
  \\"status\":\"cancelled\"}"

decodeTask :: LBS.ByteString -> IO AsyncTask
decodeTask bs = either (assertFailure . ("decode: " <>)) pure (Aeson.eitherDecode bs)

testRunning :: Assertion
testRunning = do
  AsyncTask {status, operation = AsyncTaskOperation {surface, name}} <- decodeTask runningFixture
  status @?= AsyncTaskRunning 2.0
  surface @?= SurfaceRest
  name @?= "pages.create"

testSucceeded :: Assertion
testSucceeded = do
  AsyncTask {status} <- decodeTask succeededFixture
  case status of
    AsyncTaskSucceeded result -> assertBool "page_id in result" (KeyMap.member "page_id" result)
    other -> assertFailure ("expected AsyncTaskSucceeded, got " <> show other)

testFailed :: Assertion
testFailed = do
  AsyncTask {status, operation = AsyncTaskOperation {surface}} <- decodeTask failedFixture
  surface @?= SurfaceMcp
  case status of
    AsyncTaskFailed AsyncTaskError {status = errStatus, code, additionalData} -> do
      errStatus @?= 400
      code @?= ValidationError
      assertBool "additional_data.field" (maybe False (KeyMap.member "field") additionalData)
    other -> assertFailure ("expected AsyncTaskFailed, got " <> show other)

testUnknown :: Assertion
testUnknown = do
  task@AsyncTask {status, operation = AsyncTaskOperation {surface}} <- decodeTask unknownFixture
  status @?= UnknownAsyncTaskStatus "cancelled"
  surface @?= UnknownSurface "cli"
  assertBool "unknown status is terminal" (isTerminal task)

testRoundTrip :: Assertion
testRoundTrip =
  mapM_
    ( \fixture -> do
        task <- decodeTask fixture
        Aeson.eitherDecode (Aeson.encode task) @?= Right task
    )
    [runningFixture, succeededFixture, failedFixture, unknownFixture]

testAsyncOr :: Assertion
testAsyncOr = do
  case Aeson.eitherDecode runningFixture :: Either String (AsyncOr Value) of
    Right (AcceptedAsync _) -> pure ()
    other -> assertFailure ("expected AcceptedAsync, got " <> show other)
  case Aeson.eitherDecode "{\"object\":\"page\",\"id\":\"p\"}" :: Either String (AsyncOr Value) of
    Right (CompletedSync _) -> pure ()
    other -> assertFailure ("expected CompletedSync, got " <> show other)

testAllowAsync :: Assertion
testAllowAsync = do
  expected <-
    either assertFailure pure $
      Aeson.eitherDecode
        "{\"type\":\"replace_content\",\"replace_content\":{\"new_str\":\"new\"},\"allow_async\":true}"
  Aeson.toJSON (AllowAsync (ReplaceContent (ReplaceContentRequest "new" Nothing))) @?= (expected :: Value)

-- | A pending task that asks to be polled again immediately.
pendingTask :: IO AsyncTask
pendingTask = do
  AsyncTask {id = taskId, statusUrl, createdTime, operation, object} <- decodeTask runningFixture
  pure AsyncTask {id = taskId, statusUrl, createdTime, operation, object, status = AsyncTaskRunning 0}

testWaitUntilTerminal :: Assertion
testWaitUntilTerminal = do
  start <- pendingTask
  done <- decodeTask succeededFixture
  script <- newIORef [start, done]
  calls <- newIORef (0 :: Int)
  let retrieve _ = do
        atomicModifyIORef' calls (\n -> (n + 1, ()))
        atomicModifyIORef' script (\case t : ts -> (ts, t); [] -> ([], done))
  AsyncTask {status} <- waitForAsyncTask defaultWaitOptions retrieve start
  case status of
    AsyncTaskSucceeded _ -> pure ()
    other -> assertFailure ("expected AsyncTaskSucceeded, got " <> show other)
  readIORef calls >>= (@?= 2)

testWaitMaxAttempts :: Assertion
testWaitMaxAttempts = do
  start <- pendingTask
  calls <- newIORef (0 :: Int)
  let retrieve _ = atomicModifyIORef' calls (\n -> (n + 1, start))
  result <- waitForAsyncTask WaitOptions {maxAttempts = 3, maxPollSeconds = 1} retrieve start
  assertBool "result is still pending" (not (isTerminal result))
  readIORef calls >>= (@?= 3)

data RequestCaptured = RequestCaptured deriving stock (Show)

instance Exception RequestCaptured

-- | Build a request through 'Methods' without sending it.
captureRequest :: (Methods -> IO a) -> IO HTTP.Request
captureRequest call = do
  ref <- newIORef Nothing
  manager <- HTTP.newManager HTTP.defaultManagerSettings
  let env0 = Client.mkClientEnv manager fakeBaseUrl
      env =
        env0
          { Client.makeClientRequest = \burl req -> do
              built <- Client.defaultMakeClientRequest burl req
              writeIORef ref (Just built)
              throwIO RequestCaptured
          }
  _ <- try @RequestCaptured (call (makeMethods env "secret_test_token"))
  readIORef ref >>= maybe (assertFailure "no request was built") pure

testCreatePageAsyncRequest :: Assertion
testCreatePageAsyncRequest = do
  let CreatePage {..} = mkCreatePage (PageParent (UUID "p-1")) Map.empty
      page = CreatePage {markdown = Just "# Hello", ..}
  req <- captureRequest (\m -> createPageAsync m page)
  HTTP.method req @?= "POST"
  HTTP.path req @?= "/v1/pages"
  case HTTP.requestBody req of
    HTTP.RequestBodyLBS lbs -> case Aeson.decode lbs of
      Just (Aeson.Object o) -> do
        KeyMap.lookup "allow_async" o @?= Just (Aeson.Bool True)
        KeyMap.lookup "markdown" o @?= Just (Aeson.String "# Hello")
      other -> assertFailure ("expected a JSON object body, got " <> show other)
    _ -> assertFailure "expected a lazy ByteString body"

testRoutes :: Assertion
testRoutes = do
  (env, recorded) <- fakeClientEnv [jsonReply 200 succeededFixture, jsonReply 202 runningFixture]
  let Methods {retrieveAsyncTask, updatePageMarkdownAsync} = makeMethods env "secret_test"
  AsyncTask {id = taskId} <- retrieveAsyncTask "task_01"
  taskId @?= "task_01"
  updated <- updatePageMarkdownAsync (UUID "p-1") (ReplaceContent (ReplaceContentRequest "new" Nothing))
  case updated of
    AcceptedAsync _ -> pure ()
    CompletedSync _ -> assertFailure "expected AcceptedAsync"
  requests <- readIORef recorded
  map (\Recorded {method, path} -> (method, path)) requests
    @?= [("GET", "/async_tasks/task_01"), ("PATCH", "/pages/p-1/markdown")]
