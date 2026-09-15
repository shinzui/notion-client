-- | Client runtime: configuration, timeout, retries and logging.
--
-- 'Notion.V1.makeMethodsWith' builds 'Notion.V1.Methods' from a 'ClientConfig'.
-- The building blocks below ('RequestContext', 'standardHeaders',
-- 'responseTimeoutFor', 'withRetries') are exported so requests made outside
-- Servant, such as streaming responses, behave exactly like 'Notion.V1.Methods'.
module Notion.V1.Client
  ( -- * Configuration
    ClientConfig (..),
    defaultClientConfig,
    legacyClientConfig,
    defaultBaseUrl,
    defaultNotionVersion,
    defaultUserAgent,
    RetryOptions (..),
    defaultRetryOptions,
    noRetries,

    -- * Logging
    LogLevel (..),
    Logger,
    stderrLogger,
    logWith,

    -- * Runtime building blocks
    RequestContext (..),
    requestContextFor,
    standardHeaders,
    configureClientEnv,
    notionMiddleware,
    applyTimeout,
    responseTimeoutFor,
    runClientWith,
    withRetries,
  )
where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, fromException)
import Control.Exception qualified as Exception
import Control.Monad (unless, when)
import Control.Monad.Error.Class (throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import Data.Aeson qualified as Aeson
import Data.ByteString.Builder (toLazyByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (toList)
import Data.Sequence qualified as Seq
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Time.Clock (NominalDiffTime, getCurrentTime)
import Data.Version (showVersion)
import Network.HTTP.Client qualified as HTTP
import Network.HTTP.Types (Header, Method)
import Notion.Prelude hiding (ByteString)
import Notion.V1.Error
  ( HttpErrorResponse (..),
    NotionError (..),
    RequestTimeoutError,
    UnknownHTTPResponseError (..),
    apiErrorCodeText,
    fromClientError,
    lookupHeader,
    unknownResponseMessage,
  )
import Notion.V1.Retry (RetryOptions (..), canRetry, defaultRetryOptions, noRetries, parseRetryAfter, retryDelay, validateRequestPath)
import Paths_notion_client qualified
import Servant.Client (BaseUrl (..), ClientEnv (..), ClientM, Scheme (..))
import Servant.Client qualified as Client
import Servant.Client.Core (Request, RequestF (..), Response, ResponseF (..))
import System.IO (stderr)
import System.Random (randomRIO)

-- | Severity of a log message.
data LogLevel = LogDebug | LogInfo | LogWarn | LogError
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | Receives a level, a message, and structured extra fields. The keys match
-- the JS SDK: @method@, @path@, @attempt@, @delayMs@, @code@, @message@, @requestId@.
type Logger = LogLevel -> Text -> [(Text, Value)] -> IO ()

-- | Configuration of the client runtime.
data ClientConfig = ClientConfig
  { -- | Base URL including the @/v1@ path. Used by 'Notion.V1.makeMethodsWith';
    -- ignored by 'Notion.V1.makeMethodsWithEnv', whose 'ClientEnv' already has one.
    apiBaseUrl :: BaseUrl,
    -- | Value of the @Notion-Version@ header.
    notionVersion :: Text,
    -- | Timeout for connecting and receiving response headers. 'Nothing' keeps
    -- the connection manager's own setting.
    timeout :: Maybe NominalDiffTime,
    retryOptions :: RetryOptions,
    -- | Sent as @User-Agent@ when 'Just'.
    userAgent :: Maybe Text,
    logger :: Maybe Logger,
    -- | Messages below this level are not passed to 'logger'.
    logLevel :: LogLevel
  }

-- | @https://api.notion.com/v1@
defaultBaseUrl :: BaseUrl
defaultBaseUrl = BaseUrl Https "api.notion.com" 443 "/v1"

-- | The Notion API version this library is written against.
defaultNotionVersion :: Text
defaultNotionVersion = "2026-03-11"

-- | @notion-client-haskell/<package version>@
defaultUserAgent :: Text
defaultUserAgent = "notion-client-haskell/" <> Text.pack (showVersion Paths_notion_client.version)

-- | Default base URL and API version, 60 second timeout, two retries, a
-- @User-Agent@ header and no logger.
defaultClientConfig :: ClientConfig
defaultClientConfig =
  ClientConfig
    { apiBaseUrl = defaultBaseUrl,
      notionVersion = defaultNotionVersion,
      timeout = Just 60,
      retryOptions = defaultRetryOptions,
      userAgent = Just defaultUserAgent,
      logger = Nothing,
      logLevel = LogWarn
    }

-- | What 'Notion.V1.makeMethods' uses: 'defaultClientConfig', but it keeps the
-- connection manager's timeout.
legacyClientConfig :: ClientConfig
legacyClientConfig = defaultClientConfig {timeout = Nothing}

-- | Writes @notion-client <level>: <message> <extra fields as JSON>@ to stderr.
stderrLogger :: Logger
stderrLogger level msg extra =
  Text.IO.hPutStrLn stderr $
    "notion-client "
      <> Text.pack (show level)
      <> ": "
      <> msg
      <> if null extra
        then ""
        else " " <> Text.decodeUtf8Lenient (LBS.toStrict (Aeson.encode (Aeson.object [(fromString (Text.unpack k), v) | (k, v) <- extra])))

-- | Pass a message to the configured logger if its level is high enough.
logWith :: ClientConfig -> LogLevel -> Text -> [(Text, Value)] -> IO ()
logWith ClientConfig {logger, logLevel} level msg extra = case logger of
  Just write | level >= logLevel -> write level msg extra
  _ -> pure ()

-- | Everything needed to send a request the same way 'Notion.V1.Methods' does,
-- whether through Servant or a hand-written http-client request.
data RequestContext = RequestContext
  { contextConfig :: ClientConfig,
    contextManager :: HTTP.Manager,
    -- | The effective base URL, for example @https://api.notion.com/v1@.
    contextBaseUrl :: BaseUrl,
    -- | Full @Authorization@ header value, for example @Bearer secret_...@.
    contextAuthorization :: Text
  }

-- | Build the context from the same inputs as 'Notion.V1.makeMethodsWithEnv':
-- manager and base URL from the 'ClientEnv', and a bearer token.
requestContextFor :: ClientConfig -> ClientEnv -> Text -> RequestContext
requestContextFor config ClientEnv {manager = m, baseUrl = b} token =
  RequestContext
    { contextConfig = config,
      contextManager = m,
      contextBaseUrl = b,
      contextAuthorization = "Bearer " <> token
    }

-- | The @Authorization@, @Notion-Version@ and (when configured) @User-Agent@ headers.
standardHeaders :: RequestContext -> [Header]
standardHeaders RequestContext {contextConfig = ClientConfig {notionVersion, userAgent}, contextAuthorization} =
  [ ("Authorization", Text.encodeUtf8 contextAuthorization),
    ("Notion-Version", Text.encodeUtf8 notionVersion)
  ]
    <> userAgentHeader userAgent

userAgentHeader :: Maybe Text -> [Header]
userAgentHeader = maybe [] (\ua -> [("User-Agent", Text.encodeUtf8 ua)])

-- | The http-client timeout for a configuration.
responseTimeoutFor :: ClientConfig -> HTTP.ResponseTimeout
responseTimeoutFor ClientConfig {timeout} = case timeout of
  Just t -> HTTP.responseTimeoutMicro (round (t * 1000000))
  Nothing -> HTTP.responseTimeoutDefault

-- | Set the request's timeout when the configuration has one; otherwise leave
-- the request unchanged.
applyTimeout :: ClientConfig -> HTTP.Request -> HTTP.Request
applyTimeout config@ClientConfig {timeout} req = case timeout of
  Just _ -> req {HTTP.responseTimeout = responseTimeoutFor config}
  Nothing -> req

-- | Install the runtime (timeout and middleware) into a 'ClientEnv', keeping the
-- caller's own request builder and middleware. The caller's middleware runs
-- inside ours.
configureClientEnv :: ClientConfig -> ClientEnv -> ClientEnv
configureClientEnv config env =
  env
    { makeClientRequest = \base req -> applyTimeout config <$> makeClientRequest env base req,
      middleware = \app -> notionMiddleware config (middleware env app)
    }

-- | Servant middleware implementing the runtime for every request: rejects path
-- traversal, adds the @User-Agent@ header, converts failures into this
-- library's exceptions, retries per 'retryOptions', and logs.
notionMiddleware :: ClientConfig -> (Request -> ClientM Response) -> Request -> ClientM Response
notionMiddleware config@ClientConfig {userAgent} app req0 = do
  let path = Text.decodeUtf8Lenient (LBS.toStrict (toLazyByteString (requestPath req0)))
      method = requestMethod req0
      req = req0 {requestHeaders = requestHeaders req0 <> Seq.fromList (userAgentHeader userAgent)}
      methodField = ("method", String (Text.decodeUtf8Lenient method))
  either (liftIO . Exception.throwIO) pure (validateRequestPath path)
  liftIO $ logWith config LogInfo "request start" [methodField, ("path", String path)]
  env <- ask
  result <- liftIO $ withRetries config method path $ do
    r <- Client.runClientM (app req) env
    case r of
      Right resp -> pure (Right resp)
      Left clientErr -> do
        let ex = fromClientError clientErr
        case classify ex of
          Nothing -> pure (Left clientErr)
          Just notRetried -> do
            -- NotionError is logged by withRetries; the others are never retried.
            unless (isNotionError ex) $
              logWith config LogWarn "request fail" [methodField, ("path", String path), ("message", String notRetried)]
            Exception.throwIO ex
  case result of
    Left clientErr -> throwError clientErr
    Right resp -> do
      liftIO $
        logWith
          config
          LogInfo
          "request success"
          [ methodField,
            ("path", String path),
            ("requestId", maybe Null String (lookupHeader "x-notion-request-id" (toList (responseHeaders resp))))
          ]
      pure resp
  where
    isNotionError ex = case fromException ex of
      Just (_ :: NotionError) -> True
      Nothing -> False
    -- A description for exceptions this library throws, Nothing for other client errors.
    classify :: SomeException -> Maybe Text
    classify ex
      | Just NotionError {message} <- fromException ex = Just message
      | Just (e :: UnknownHTTPResponseError) <- fromException ex = Just (unknownResponseMessage e)
      | Just (_ :: RequestTimeoutError) <- fromException ex = Just "Request to Notion API has timed out"
      | otherwise = Nothing

-- | Run an action that signals API failures by throwing 'NotionError', retrying
-- per 'retryOptions'. @method@ and @path@ are used for the retry rule and log
-- lines. Other exceptions propagate immediately. Usable outside Servant, for
-- example before opening a streaming response.
withRetries :: ClientConfig -> Method -> Text -> IO a -> IO a
withRetries config@ClientConfig {retryOptions} method path action = go 0
  where
    go attempt = do
      result <- Exception.try action
      case result of
        Right a -> pure a
        Left err@NotionError {code, message, requestId, response} -> do
          logWith
            config
            LogWarn
            "request fail"
            [ ("code", String (apiErrorCodeText code)),
              ("message", String message),
              ("attempt", Aeson.toJSON attempt),
              ("requestId", maybe Null String requestId)
            ]
          case response of
            Just HttpErrorResponse {errorBody} ->
              logWith config LogDebug "failed response body" [("body", String (Text.decodeUtf8Lenient (LBS.toStrict errorBody)))]
            Nothing -> pure ()
          when (attempt >= maxRetries retryOptions || not (canRetry method code)) $
            Exception.throwIO err
          now <- getCurrentTime
          jitter <- randomRIO (0, 0.999999)
          let retryAfter = parseRetryAfter now =<< (lookup "retry-after" . errorHeaders =<< response)
              delay = retryDelay retryOptions attempt jitter retryAfter
              delayMs = round (delay * 1000) :: Integer
          logWith
            config
            LogInfo
            "retrying request"
            [ ("method", String (Text.decodeUtf8Lenient method)),
              ("path", String path),
              ("attempt", Aeson.toJSON (attempt + 1)),
              ("delayMs", Aeson.toJSON delayMs)
            ]
          threadDelay (fromInteger (delayMs * 1000))
          go (attempt + 1)

-- | Run a client action in an already configured environment, throwing failures
-- as exceptions.
runClientWith :: ClientEnv -> ClientM a -> IO a
runClientWith env clientM = do
  result <- Client.runClientM clientM env
  -- throwIO on a SomeException rethrows the wrapped exception, so callers can
  -- catch NotionError and friends by their own types.
  either (Exception.throwIO . fromClientError) pure result
