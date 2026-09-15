-- | @\/v1\/async_tasks@
--
-- Some operations run in the background: Notion answers with an
-- 'AsyncTask' instead of the finished result. Retrieve the task with
-- 'Notion.V1.retrieveAsyncTask' and wait for it with 'waitForAsyncTask'.
module Notion.V1.AsyncTasks
  ( -- * Main types
    AsyncTaskID,
    AsyncTask (..),
    AsyncTaskOperation (..),
    AsyncTaskSurface (..),
    AsyncTaskStatus (..),
    AsyncTaskError (..),

    -- * Optionally asynchronous responses
    AsyncOr (..),
    AllowAsync (..),
    AsyncVerb,
    AsyncStatuses,
    fromAsyncUnion,

    -- * Waiting
    WaitOptions (..),
    defaultWaitOptions,
    isTerminal,
    pollAfterSeconds,
    waitForAsyncTask,

    -- * Servant
    API,
  )
where

import Control.Concurrent (threadDelay)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson ((.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Pair)
import Data.Maybe (catMaybes, fromMaybe)
import Data.Proxy (Proxy (..))
import Notion.Prelude
import Notion.V1.Error (APIErrorCode)
import Servant.API (UVerb, WithStatus (..))
import Servant.API.UVerb (Union, foldMapUnion)
import Prelude hiding (id)

-- | Async task ID (an opaque string, not necessarily a UUID)
type AsyncTaskID = Text

-- | A long-running server-side job.
data AsyncTask = AsyncTask
  { id :: AsyncTaskID,
    -- | URL of the task on the API, for example
    -- @https:\/\/api.notion.com\/v1\/async_tasks\/{id}@.
    statusUrl :: Text,
    createdTime :: POSIXTime,
    operation :: AsyncTaskOperation,
    status :: AsyncTaskStatus,
    -- | Always @"async_task"@.
    object :: Text
  }
  deriving stock (Eq, Generic, Show)

-- | What started the task.
data AsyncTaskOperation = AsyncTaskOperation
  { surface :: AsyncTaskSurface,
    -- | The operation name.
    name :: Text
  }
  deriving stock (Eq, Generic, Show)

-- | The API surface the task was started from.
data AsyncTaskSurface
  = SurfaceRest
  | SurfaceMcp
  | -- | A surface this library does not know yet; holds the raw string.
    UnknownSurface Text
  deriving stock (Eq, Generic, Show)

-- | The state of a task, with the data that state carries.
data AsyncTaskStatus
  = -- | Seconds to wait before polling again.
    AsyncTaskQueued Double
  | AsyncTaskRunning Double
  | AsyncTaskRetrying Double
  | -- | The operation's result.
    AsyncTaskSucceeded Aeson.Object
  | AsyncTaskFailed AsyncTaskError
  | -- | A status this library does not know yet; holds the raw string.
    UnknownAsyncTaskStatus Text
  deriving stock (Eq, Generic, Show)

-- | Why a task failed; the same shape as a Notion error response.
data AsyncTaskError = AsyncTaskError
  { -- | Always @"error"@.
    object :: Text,
    -- | HTTP-style status, for example 400.
    status :: Natural,
    code :: APIErrorCode,
    message :: Text,
    additionalData :: Maybe Aeson.Object
  }
  deriving stock (Eq, Generic, Show)

instance FromJSON AsyncTaskSurface where
  parseJSON = Aeson.withText "AsyncTaskSurface" $ \case
    "rest" -> pure SurfaceRest
    "mcp" -> pure SurfaceMcp
    other -> pure (UnknownSurface other)

instance ToJSON AsyncTaskSurface where
  toJSON = \case
    SurfaceRest -> String "rest"
    SurfaceMcp -> String "mcp"
    UnknownSurface t -> String t

instance FromJSON AsyncTaskOperation where
  parseJSON = Aeson.withObject "AsyncTaskOperation" $ \o ->
    AsyncTaskOperation <$> o .: "surface" <*> o .: "name"

instance ToJSON AsyncTaskOperation where
  toJSON AsyncTaskOperation {..} = Aeson.object ["surface" .= surface, "name" .= name]

instance FromJSON AsyncTaskError where
  parseJSON = Aeson.withObject "AsyncTaskError" $ \o -> do
    object <- o .: "object"
    status <- o .: "status"
    code <- o .: "code"
    message <- o .: "message"
    additionalData <- o .:? "additional_data"
    pure AsyncTaskError {..}

instance ToJSON AsyncTaskError where
  toJSON AsyncTaskError {..} =
    Aeson.object $
      [ "object" .= object,
        "status" .= status,
        "code" .= code,
        "message" .= message
      ]
        <> catMaybes [("additional_data" .=) <$> additionalData]

instance FromJSON AsyncTask where
  parseJSON = Aeson.withObject "AsyncTask" $ \o -> do
    id <- o .: "id"
    statusUrl <- o .: "status_url"
    createdTime <- parseISO8601 =<< o .: "created_time"
    operation <- o .: "operation"
    object <- o .: "object"
    statusText <- o .: "status"
    status <- case statusText :: Text of
      "queued" -> AsyncTaskQueued <$> o .: "poll_after_seconds"
      "running" -> AsyncTaskRunning <$> o .: "poll_after_seconds"
      "retrying" -> AsyncTaskRetrying <$> o .: "poll_after_seconds"
      "succeeded" -> AsyncTaskSucceeded . fromMaybe mempty <$> o .:? "result"
      "failed" -> AsyncTaskFailed <$> o .: "error"
      other -> pure (UnknownAsyncTaskStatus other)
    pure AsyncTask {..}

instance ToJSON AsyncTask where
  toJSON AsyncTask {..} =
    Aeson.object $
      [ "object" .= object,
        "id" .= id,
        "status_url" .= statusUrl,
        "created_time" .= posixToISO8601 createdTime,
        "operation" .= operation
      ]
        <> case status of
          AsyncTaskQueued s -> pending "queued" s
          AsyncTaskRunning s -> pending "running" s
          AsyncTaskRetrying s -> pending "retrying" s
          AsyncTaskSucceeded r -> ["status" .= ("succeeded" :: Text), "result" .= r]
          AsyncTaskFailed e -> ["status" .= ("failed" :: Text), "error" .= e]
          UnknownAsyncTaskStatus t -> ["status" .= t]
    where
      pending :: Text -> Double -> [Pair]
      pending s secs = ["status" .= s, "poll_after_seconds" .= secs]

-- | A response that is either an accepted async task or the finished result.
data AsyncOr a
  = AcceptedAsync AsyncTask
  | CompletedSync a
  deriving stock (Eq, Generic, Show)

-- | An object whose @object@ key is @"async_task"@ is a task; anything else
-- is decoded as the synchronous result.
instance (FromJSON a) => FromJSON (AsyncOr a) where
  parseJSON v = case v of
    Object o | KeyMap.lookup "object" o == Just (String "async_task") -> AcceptedAsync <$> parseJSON v
    _ -> CompletedSync <$> parseJSON v

-- | The responses of an endpoint that may run in the background: Notion
-- answers @200 OK@ with the result when it finished synchronously and
-- @202 Accepted@ with an 'AsyncTask' when it queued the work. Either body is
-- decoded by 'AsyncOr'\'s instance.
type AsyncStatuses a = '[WithStatus 200 (AsyncOr a), WithStatus 202 (AsyncOr a)]

-- | Route verb for such an endpoint, for example @AsyncVerb 'POST PageObject@.
--
-- A plain @Post '[JSON]@ route accepts only status 200, so servant-client
-- would reject the 202 response.
type AsyncVerb method a = UVerb method '[JSON] (AsyncStatuses a)

-- | Collapse the response union of an 'AsyncVerb' route.
fromAsyncUnion :: forall a. Union (AsyncStatuses a) -> AsyncOr a
fromAsyncUnion = foldMapUnion (Proxy @(UnwrapStatus (AsyncOr a))) unwrapStatus

class UnwrapStatus a x where
  unwrapStatus :: x -> a

instance (b ~ a) => UnwrapStatus a (WithStatus n b) where
  unwrapStatus (WithStatus x) = x

-- | Request wrapper that adds @"allow_async": true@ to an object body.
-- Non-object bodies are sent unchanged.
newtype AllowAsync a = AllowAsync a
  deriving stock (Show)

instance (ToJSON a) => ToJSON (AllowAsync a) where
  toJSON (AllowAsync a) = case toJSON a of
    Object o -> Object (KeyMap.insert "allow_async" (Bool True) o)
    other -> other

-- | Limits for 'waitForAsyncTask'.
data WaitOptions = WaitOptions
  { -- | Retrieve calls before giving up.
    maxAttempts :: Natural,
    -- | Upper bound, in seconds, on any single wait.
    maxPollSeconds :: Double
  }
  deriving stock (Eq, Show)

-- | 120 attempts, waiting at most 30 seconds between them.
defaultWaitOptions :: WaitOptions
defaultWaitOptions = WaitOptions {maxAttempts = 120, maxPollSeconds = 30}

-- | Whether the task will not change any more. An unknown status counts as
-- terminal so that callers see it instead of polling a state they cannot
-- interpret.
isTerminal :: AsyncTask -> Bool
isTerminal AsyncTask {status} = case status of
  AsyncTaskQueued _ -> False
  AsyncTaskRunning _ -> False
  AsyncTaskRetrying _ -> False
  AsyncTaskSucceeded _ -> True
  AsyncTaskFailed _ -> True
  UnknownAsyncTaskStatus _ -> True

-- | The server's polling hint, for tasks that are still pending.
pollAfterSeconds :: AsyncTask -> Maybe Double
pollAfterSeconds AsyncTask {status} = case status of
  AsyncTaskQueued s -> Just s
  AsyncTaskRunning s -> Just s
  AsyncTaskRetrying s -> Just s
  _ -> Nothing

-- | Poll a task until it is terminal or 'maxAttempts' retrieve calls have
-- been made, sleeping for the task's @poll_after_seconds@ (capped by
-- 'maxPollSeconds') before each call. Returns the last task seen; check
-- 'isTerminal' on the result to detect giving up.
--
-- Pass the retrieve function: @waitForAsyncTask defaultWaitOptions
-- (retrieveAsyncTask methods) task@ in 'IO', or the @retrieveAsyncTask@
-- smart constructor from @notion-client-effectful@ in @Eff@.
waitForAsyncTask ::
  (MonadIO m) =>
  WaitOptions ->
  (AsyncTaskID -> m AsyncTask) ->
  AsyncTask ->
  m AsyncTask
waitForAsyncTask WaitOptions {..} retrieve = go 0
  where
    go attempts task
      | isTerminal task || attempts >= maxAttempts = pure task
      | otherwise = do
          let secs = min maxPollSeconds (max 0 (fromMaybe 0 (pollAfterSeconds task)))
          liftIO (threadDelay (round (secs * 1000000)))
          let AsyncTask {id = taskId} = task
          next <- retrieve taskId
          go (attempts + 1) next

-- | Servant API
type API =
  "async_tasks"
    :> Capture "task_id" AsyncTaskID
    :> Get '[JSON] AsyncTask
