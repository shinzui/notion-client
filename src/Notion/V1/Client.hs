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
  )
where

import Control.Exception qualified as Exception
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Sequence qualified as Seq
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Time.Clock (NominalDiffTime)
import Data.Version (showVersion)
import Network.HTTP.Client qualified as HTTP
import Network.HTTP.Types (Header)
import Notion.Prelude hiding (ByteString)
import Notion.V1.Error (fromClientError)
import Notion.V1.Retry (RetryOptions (..), defaultRetryOptions, noRetries)
import Paths_notion_client qualified
import Servant.Client (BaseUrl (..), ClientEnv (..), ClientM, Scheme (..))
import Servant.Client qualified as Client
import Servant.Client.Core (Request, RequestF (..), Response)
import System.IO (stderr)

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

-- | Servant middleware that adds the @User-Agent@ header.
notionMiddleware :: ClientConfig -> (Request -> ClientM Response) -> Request -> ClientM Response
notionMiddleware ClientConfig {userAgent} app req =
  app req {requestHeaders = requestHeaders req <> Seq.fromList (userAgentHeader userAgent)}

-- | Run a client action in an already configured environment, throwing failures
-- as exceptions.
runClientWith :: ClientEnv -> ClientM a -> IO a
runClientWith env clientM = do
  result <- Client.runClientM clientM env
  -- throwIO on a SomeException rethrows the wrapped exception, so callers can
  -- catch NotionError and friends by their own types.
  either (Exception.throwIO . fromClientError) pure result
