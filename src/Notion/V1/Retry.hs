-- | Retry policy for Notion API requests, ported from the official JS SDK.
--
-- Everything here is pure; 'Notion.V1.Client.withRetries' runs the loop.
module Notion.V1.Retry
  ( -- * Options
    RetryOptions (..),
    defaultRetryOptions,
    noRetries,

    -- * Policy
    canRetry,
    parseRetryAfter,
    retryDelay,
    validateRequestPath,
  )
where

import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.Char (isDigit, isSpace)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Time.Clock (NominalDiffTime, UTCTime, diffUTCTime)
import Data.Time.Format (defaultTimeLocale, parseTimeM)
import Network.HTTP.Types (Method, methodDelete, methodGet, urlDecode)
import Notion.Prelude hiding (ByteString)
import Notion.V1.Error (APIErrorCode (..), InvalidPathParameterError (..))

-- | How failed requests are retried.
data RetryOptions = RetryOptions
  { -- | Maximum number of retries after the first attempt; 0 disables retries.
    maxRetries :: Natural,
    -- | Base of the exponential back-off.
    initialRetryDelay :: NominalDiffTime,
    -- | Upper bound for both @retry-after@ and back-off delays.
    maxRetryDelay :: NominalDiffTime
  }
  deriving stock (Eq, Show)

-- | Two retries, starting at one second and capped at one minute (the JS SDK defaults).
defaultRetryOptions :: RetryOptions
defaultRetryOptions = RetryOptions {maxRetries = 2, initialRetryDelay = 1, maxRetryDelay = 60}

-- | Never retry.
noRetries :: RetryOptions
noRetries = RetryOptions {maxRetries = 0, initialRetryDelay = 0, maxRetryDelay = 0}

-- | Whether a failed request may be retried. @rate_limited@ and
-- @service_overload@ are retried for any method; @internal_server_error@ and
-- @service_unavailable@ only for @GET@ and @DELETE@.
canRetry :: Method -> APIErrorCode -> Bool
canRetry method = \case
  RateLimited -> True
  ServiceOverload -> True
  InternalServerError -> idempotent
  ServiceUnavailable -> idempotent
  _ -> False
  where
    idempotent = method == methodGet || method == methodDelete

-- | Parse a @retry-after@ header value at time @now@.
--
-- Leading ASCII digits (after skipping spaces) are delta-seconds, like
-- JavaScript's @parseInt@ (@"1.5"@ is one second). Otherwise the value may be
-- an HTTP date such as @Wed, 21 Oct 2015 07:28:00 GMT@; a date in the past
-- gives 0. Anything else gives 'Nothing'.
parseRetryAfter :: UTCTime -> BS.ByteString -> Maybe NominalDiffTime
parseRetryAfter now raw
  | not (BS.null digits) = fromInteger <$> readInteger digits
  | otherwise = do
      date <- parseTimeM False defaultTimeLocale "%a, %d %b %Y %H:%M:%S GMT" (BS8.unpack trimmed)
      pure (max 0 (diffUTCTime date now))
  where
    trimmed = BS8.dropWhileEnd isSpace (BS8.dropWhile isSpace raw)
    digits = BS8.takeWhile isDigit trimmed
    readInteger bs = case BS8.readInteger bs of
      Just (n, rest) | BS.null rest -> Just n
      _ -> Nothing

-- | Delay before retry number @attempt + 1@ (@attempt@ counts from 0).
-- A @retry-after@ value wins, capped at 'maxRetryDelay'. Otherwise exponential
-- back-off with @jitter@ in [0, 1): @base * jitter + base / 2@, where
-- @base = initialRetryDelay * 2 ^ attempt@.
retryDelay :: RetryOptions -> Natural -> Double -> Maybe NominalDiffTime -> NominalDiffTime
retryDelay RetryOptions {initialRetryDelay, maxRetryDelay} attempt jitter = \case
  Just retryAfter -> min retryAfter maxRetryDelay
  Nothing ->
    let base = initialRetryDelay * 2 ^ attempt
     in min (base * realToFrac jitter + base / 2) maxRetryDelay

-- | Reject request paths containing a path traversal sequence (@..@), plain or
-- percent-encoded.
validateRequestPath :: Text -> Either InvalidPathParameterError ()
validateRequestPath path
  | ".." `Text.isInfixOf` path = Left (InvalidPathParameterError path)
  | "%2e" `Text.isInfixOf` Text.toLower path,
    ".." `BS.isInfixOf` urlDecode False (Text.encodeUtf8 path) =
      Left (InvalidPathParameterError path)
  | otherwise = Right ()
