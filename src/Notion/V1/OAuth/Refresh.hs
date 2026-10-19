-- | Rotation-safe token management for one installation in one process.
-- Use exactly one manager per installation. Separate managers/processes must
-- coordinate the whole load/refresh/save transaction externally. A save-time
-- compare-and-swap cannot prevent competing remote refreshes. Process crashes
-- between remote rotation and durable save may require fresh authorization.
module Notion.V1.OAuth.Refresh
  ( OAuthTokens (..),
    oauthTokensFromResponse,
    TokenStore (..),
    inMemoryTokenStore,
    ReauthorizationRequired (..),
    TokenPersistenceError,
    RefreshOutcomeUnknown,
    OAuthTokenManager,
    newOAuthTokenManager,
    tokenManagerSource,
    currentTokens,
    refreshTokensNow,
    retryTokenPersistence,
  )
where

import Control.Concurrent.MVar
import Control.Exception
import Data.IORef
import Data.Text qualified as T
import Data.Time.Clock
import Notion.Prelude
import Notion.V1.OAuth qualified as O
import Notion.V1.TokenSource

-- | Persisted credentials. Explicit JSON contains secrets; Show never does.
data OAuthTokens = OAuthTokens
  { accessToken :: Text,
    refreshToken :: Maybe Text,
    botId :: Text,
    workspaceId :: Text,
    workspaceName :: Maybe Text,
    obtainedAt :: UTCTime
  }
  deriving stock (Eq, Generic)

instance Show OAuthTokens where show _ = "OAuthTokens <redacted>"

instance ToJSON OAuthTokens where toJSON = genericToJSON aesonOptions

instance FromJSON OAuthTokens where parseJSON = genericParseJSON aesonOptions

oauthTokensFromResponse :: UTCTime -> O.OAuthTokenResponse -> OAuthTokens
oauthTokensFromResponse obtainedAt O.OAuthTokenResponse {accessToken, refreshToken, botId, workspaceId, workspaceName} = OAuthTokens {..}

-- | Save must be idempotent for the same pair, meet the application's durability
-- contract before returning, and never call back into its manager.
data TokenStore = TokenStore {loadTokens :: IO OAuthTokens, saveTokens :: OAuthTokens -> IO ()}

inMemoryTokenStore :: OAuthTokens -> IO TokenStore
inMemoryTokenStore tokens = do
  ref <- newIORef tokens
  pure (TokenStore (readIORef ref) (atomicWriteIORef ref))

newtype ReauthorizationRequired = ReauthorizationRequired {reauthorizationCause :: Maybe O.OAuthError}
  deriving stock (Show)

instance Exception ReauthorizationRequired

data TokenPersistenceError = TokenPersistenceError deriving stock (Eq, Show)

instance Exception TokenPersistenceError where
  displayException _ = "OAuth token persistence failed; retry saving the retained pair"

data RefreshOutcomeUnknown = RefreshOutcomeUnknown deriving stock (Eq, Show)

instance Exception RefreshOutcomeUnknown where
  displayException _ = "OAuth refresh outcome unknown; authorize again without replaying the refresh token"

-- Every state retains the last known pair for explicit recovery.
data Lifecycle
  = Ready OAuthTokens
  | PendingPersistence OAuthTokens
  | NeedsReauthorization OAuthTokens (Maybe O.OAuthError)
  | UncertainOutcome OAuthTokens

data OAuthTokenManager = OAuthTokenManager (MVar Lifecycle) O.OAuthMethods TokenStore

newOAuthTokenManager :: O.OAuthMethods -> TokenStore -> IO OAuthTokenManager
newOAuthTokenManager oauth store = do
  tokens <- loadTokens store
  OAuthTokenManager <$> newMVar (Ready tokens) <*> pure oauth <*> pure store

knownTokens :: Lifecycle -> OAuthTokens
knownTokens = \case
  Ready t -> t
  PendingPersistence t -> t
  NeedsReauthorization t _ -> t
  UncertainOutcome t -> t

-- | Inspection/recovery only. This may return an unusable or unsaved pair.
-- Authorize requests through 'tokenManagerSource', which enforces lifecycle.
currentTokens :: OAuthTokenManager -> IO OAuthTokens
currentTokens (OAuthTokenManager lock _ _) = knownTokens <$> readMVar lock

usable :: Lifecycle -> Either SomeException OAuthTokens
usable = \case
  Ready t -> Right t
  PendingPersistence _ -> Left (toException TokenPersistenceError)
  NeedsReauthorization _ cause -> Left (toException (ReauthorizationRequired cause))
  UncertainOutcome _ -> Left (toException RefreshOutcomeUnknown)

tokenManagerSource :: OAuthTokenManager -> TokenSource
tokenManagerSource manager@(OAuthTokenManager lock _ _) =
  TokenSource
    { currentToken = do
        state <- readMVar lock
        accessToken <$> either throwIO pure (usable state),
      renewToken = \rejected ->
        Just . accessToken
          <$> transition
            manager
            ( \restore state ->
                case usable state of
                  Left e -> pure (state, Left e)
                  Right tokens | accessToken tokens /= rejected -> pure (state, Right tokens)
                  Right tokens -> rotate manager restore tokens
            )
    }

-- The result is rethrown only after the new lifecycle has been published.
-- A surprise exception must never restore Ready with a possibly consumed grant.
transition ::
  OAuthTokenManager ->
  ((forall a. IO a -> IO a) -> Lifecycle -> IO (Lifecycle, Either SomeException b)) ->
  IO b
transition (OAuthTokenManager lock _ _) action = do
  result <- mask $ \restore -> do
    old <- takeMVar lock
    (new, outcome) <-
      action restore old `catch` \(e :: SomeException) ->
        pure (UncertainOutcome (knownTokens old), Left e)
    putMVar lock new
    pure outcome
  either throwIO pure result

rotate ::
  OAuthTokenManager ->
  (forall a. IO a -> IO a) ->
  OAuthTokens ->
  IO (Lifecycle, Either SomeException OAuthTokens)
rotate manager@(OAuthTokenManager _ oauth _) restore old = case refreshToken old of
  Nothing -> pure (NeedsReauthorization old Nothing, Left (toException (ReauthorizationRequired Nothing)))
  Just rt -> do
    response <- try @SomeException (restore (O.createOAuthToken oauth (O.RefreshToken rt)))
    case response of
      Left e
        | Just oe@O.OAuthError {oauthErrorCode = O.OAuthInvalidGrant} <- fromException e ->
            pure (NeedsReauthorization old (Just oe), Left (toException (ReauthorizationRequired (Just oe))))
      Left e | Just (_ :: O.OAuthError) <- fromException e -> pure (Ready old, Left e)
      Left e -> pure (UncertainOutcome old, Left e)
      Right r@O.OAuthTokenResponse {accessToken = access, tokenType, botId = bot, workspaceId = workspace}
        | T.null access || T.toLower tokenType /= "bearer" || bot /= botId old || workspace /= workspaceId old ->
            pure (UncertainOutcome old, Left (toException RefreshOutcomeUnknown))
        | otherwise -> do
            now <- getCurrentTime
            persist manager restore (oauthTokensFromResponse now r)

persist ::
  OAuthTokenManager ->
  (forall a. IO a -> IO a) ->
  OAuthTokens ->
  IO (Lifecycle, Either SomeException OAuthTokens)
persist (OAuthTokenManager _ _ store) restore tokens = do
  saved <- try @SomeException (restore (saveTokens store tokens))
  pure $ case saved of
    Right () -> (Ready tokens, Right tokens)
    Left _ -> (PendingPersistence tokens, Left (toException TokenPersistenceError))

-- | Explicit calls serialize, but each may rotate. Automatic rejections share
-- a completed rotation by comparing the rejected access token under the lock.
refreshTokensNow :: OAuthTokenManager -> IO OAuthTokens
refreshTokensNow manager = transition manager $ \restore state -> case usable state of
  Left e -> pure (state, Left e)
  Right t -> rotate manager restore t

-- | Save the identical retained pair without making another OAuth request.
retryTokenPersistence :: OAuthTokenManager -> IO OAuthTokens
retryTokenPersistence manager = transition manager $ \restore state -> case state of
  PendingPersistence t -> persist manager restore t
  _ -> pure (state, usable state)
