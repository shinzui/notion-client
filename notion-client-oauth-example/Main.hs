-- | Public integration login example (POSIX only).
-- Create a public connection in https://www.notion.so/profile/integrations and
-- register http://localhost:8765/callback. Export NOTION_OAUTH_CLIENT_ID and
-- NOTION_OAUTH_CLIENT_SECRET, then run with login, whoami, refresh or revoke.
-- If localhost HTTP is refused, register an HTTPS tunnel URL and set
-- NOTION_OAUTH_REDIRECT_URI; keep its target listener port configured separately.
-- This confidential-client example runs in a trusted process. Distributed apps
-- must keep the client secret and exchange on a trusted backend.
module Main (main) where

import Control.Exception
import Control.Monad (unless, when)
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import Data.Vector qualified as V
import FileTokenStore
import Login
import Network.HTTP.Client.TLS (newTlsManager)
import Notion.V1
import Notion.V1.Common (UUID (..))
import Notion.V1.DataSources qualified as D
import Notion.V1.Error qualified as E
import Notion.V1.ListOf (ListOf (..))
import Notion.V1.OAuth qualified as O
import Notion.V1.OAuth.Authorization qualified as A
import Notion.V1.OAuth.Refresh qualified as R
import Notion.V1.Pages qualified as P
import Notion.V1.Search
import Notion.V1.Users qualified as U
import Servant.Client (mkClientEnv)
import System.Environment
import System.Exit
import System.IO
import Text.Read (readMaybe)

main :: IO ()
main =
  program `catch` \(e :: SomeException) -> case fromException e of
    Just (exit :: ExitCode) -> throwIO exit
    Nothing | Just (_ :: AsyncException) <- fromException e -> throwIO e
    Nothing -> hPutStrLn stderr (diagnostic e) >> exitFailure

program :: IO ()
program = do
  args <- getArgs
  command <- case args of
    [c] | c `elem` ["login", "whoami", "refresh", "revoke"] -> pure c
    _ -> usage
  cid <- required "NOTION_OAUTH_CLIENT_ID"
  secret <- required "NOTION_OAUTH_CLIENT_SECRET"
  redirect <- T.pack . fromMaybe "http://localhost:8765/callback" <$> lookupEnv "NOTION_OAUTH_REDIRECT_URI"
  portText <- fromMaybe "8765" <$> lookupEnv "NOTION_OAUTH_LISTEN_PORT"
  port <- case readMaybe portText of
    Just p | p > 0 && p <= 65535 -> pure p
    _ -> usage
  path <- fromMaybe ".notion-oauth-tokens.json" <$> lookupEnv "NOTION_OAUTH_TOKEN_FILE"
  withTokenFileLock path $ do
    http <- newTlsManager
    let env = mkClientEnv http defaultBaseUrl
        oauth = O.makeOAuthMethodsWith defaultClientConfig env (O.OAuthCredentials cid secret)
        store = fileTokenStore path
    case command of
      "login" -> do
        state <- A.newOAuthState
        let request = A.AuthorizationRequest cid redirect state
        result <- runLogin port (10 * 60 * 1000000) oauth store request $ do
          putStrLn "Open this URL in your browser:"
          T.putStrLn (A.authorizationUrl request)
          T.putStrLn ("Waiting for the redirect on " <> redirect)
        case result of
          Connected tokens -> connected path tokens
          SavePending tokens -> do
            putStrLn "Credentials received but storage failed. Keep this process open to retain them."
            retrySave (R.saveTokens store tokens)
            connected path tokens
          Cancelled -> putStrLn "Consent was cancelled"
          LoginExpired -> hPutStrLn stderr "Login timed out. Start login again" >> exitFailure
          LoginFailed -> hPutStrLn stderr "Connection failed. Check client credentials and start login again" >> exitFailure
      _ -> do
        exists <- tokenFileExists path
        unless exists (hPutStrLn stderr "Run login again" >> exitFailure)
        manager <- R.newOAuthTokenManager oauth store
        case command of
          "whoami" -> do
            let api = makeMethodsWithTokenSource defaultClientConfig env (R.tokenManagerSource manager)
                who = do
                  U.UserObject {name} <- retrieveMyUser api
                  T.putStrLn ("Bot: " <> fromMaybe "(unnamed)" name)
                  List {results} <- search api _SearchRequest {pageSize = Just 5}
                  if V.null results then putStrLn "No shared search results" else mapM_ (T.putStrLn . resultLabel) (V.toList (V.take 5 results))
            who `catch` \(_ :: R.TokenPersistenceError) -> do
              putStrLn "Refresh succeeded but its credentials were not saved."
              _ <- retrySave (R.retryTokenPersistence manager)
              who
          "refresh" -> do
            old <- R.currentTokens manager
            result <- try @R.TokenPersistenceError (R.refreshTokensNow manager)
            new <- either (const (retrySave (R.retryTokenPersistence manager))) pure result
            putStrLn ("access token changed: " <> show (R.accessToken old /= R.accessToken new))
            putStrLn ("refresh token changed: " <> maybe "not returned" (\_ -> show (R.refreshToken old /= R.refreshToken new)) (R.refreshToken new))
          "revoke" -> do
            tokens <- R.currentTokens manager
            _ <- O.revokeOAuthToken oauth (R.accessToken tokens)
            removeTokenFile path
            putStrLn "Local credentials removed. Run login again"
          _ -> usage

required :: String -> IO T.Text
required key =
  lookupEnv key >>= \case
    Just value | not (null value) -> pure (T.pack value)
    _ -> usage

usage :: IO a
usage = do
  hPutStrLn stderr "usage: notion-client-oauth-example (login | whoami | refresh | revoke)"
  hPutStrLn stderr "  requires NOTION_OAUTH_CLIENT_ID and NOTION_OAUTH_CLIENT_SECRET"
  exitWith (ExitFailure 2)

-- This action may save the same pair repeatedly, but must never exchange a grant.
retrySave :: IO a -> IO a
retrySave action = do
  putStrLn "Press Enter to retry persistence, or q to stop (unsaved credentials may require a new login)."
  hFlush stdout
  eof <- hIsEOF stdin
  when eof exitFailure
  answer <- getLine
  when (answer == "q") exitFailure
  attempt <- try @SomeException action
  case attempt of
    Right a -> pure a
    Left e | Just (_ :: AsyncException) <- fromException e -> throwIO e
    Left _ -> putStrLn "Persistence still failed; credentials are retained in this process." >> retrySave action

connected :: FilePath -> R.OAuthTokens -> IO ()
connected path R.OAuthTokens {workspaceName, workspaceId, botId} = do
  T.putStrLn ("Connected to workspace " <> fromMaybe "(unnamed)" workspaceName <> " (workspace " <> workspaceId <> ", bot " <> botId <> ")")
  putStrLn ("Tokens saved to " <> path)

resultLabel :: PageOrDataSource -> T.Text
resultLabel = \case
  PageResult P.PageObject {id = UUID value} -> "page " <> value
  PartialPageResult P.PartialPageObject {id = UUID value} -> "page " <> value
  DataSourceResult D.DataSourceObject {id = UUID value} -> "data source " <> value
  PartialDataSourceResult D.PartialDataSourceObject {id = UUID value} -> "data source " <> value
  UnknownResult _ -> "Unknown search result type"

diagnostic :: SomeException -> String
diagnostic e
  | Just (_ :: R.TokenPersistenceError) <- fromException e = "Token persistence failed; retain this process and retry the save"
  | Just (_ :: R.RefreshOutcomeUnknown) <- fromException e = "Refresh outcome unknown. Run login again; do not reuse the old refresh token"
  | Just (_ :: R.ReauthorizationRequired) <- fromException e = "Authorization required. Run login again"
  | Just oe@O.OAuthError {oauthErrorCode = O.OAuthInvalidClient} <- fromException e = "Check OAuth client credentials: " <> displayException oe
  | Just (oe :: O.OAuthError) <- fromException e = displayException oe
  | Just E.NotionError {code} <- fromException e = "Notion API request failed (" <> safeCode code <> ")"
  | Just (_ :: IOException) <- fromException e = "Local storage or listener failed; check the token directory, permissions, lock and port"
  | otherwise = "OAuth operation failed; start login again"
  where
    safeCode (E.UnknownErrorCode _) = "unknown_error"
    safeCode c = T.unpack (E.apiErrorCodeText c)
