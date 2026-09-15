-- | Retry policy for Notion API requests, ported from the official JS SDK.
module Notion.V1.Retry
  ( -- * Options
    RetryOptions (..),
    defaultRetryOptions,
    noRetries,
  )
where

import Data.Time.Clock (NominalDiffTime)
import Notion.Prelude

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
