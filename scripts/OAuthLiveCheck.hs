{-# LANGUAGE GHC2024 #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

-- | Explicit live acceptance harness, never invoked by the offline suite.
-- Run after login/refresh with a current refresh-capable installation. It replaces
-- only the in-memory access token, keeps the current refresh token, and durably
-- saves the one replacement pair. It never probes a superseded refresh token.
module Main (main) where

import Control.Exception
import Control.Monad (unless)
import Data.IORef
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import FileTokenStore
import Network.HTTP.Client.TLS (newTlsManager)
import Notion.V1
import Notion.V1.OAuth qualified as O
import Notion.V1.OAuth.Refresh qualified as R
import Servant.Client (mkClientEnv)
import System.Environment
import System.Exit

main :: IO ()
main =
  run `catch` \(e :: SomeException) -> case fromException e of
    Just (exit :: ExitCode) -> throwIO exit
    Nothing | Just (_ :: AsyncException) <- fromException e -> throwIO e
    Nothing -> putStrLn "Live check failed; reauthorize after an uncertain exchange. No credentials printed." >> exitFailure

run :: IO ()
run = do
  client <- T.pack <$> getEnv "NOTION_OAUTH_CLIENT_ID"
  secret <- T.pack <$> getEnv "NOTION_OAUTH_CLIENT_SECRET"
  path <- fromMaybe ".notion-oauth-tokens.json" <$> lookupEnv "NOTION_OAUTH_TOKEN_FILE"
  withTokenFileLock path $ do
    let fileStore = fileTokenStore path
    old <- R.loadTokens fileStore
    unless (R.refreshToken old /= Nothing) (putStrLn "Live check requires a current refresh token" >> exitFailure)
    http <- newTlsManager
    let env = mkClientEnv http defaultBaseUrl
        baseOAuth = O.makeOAuthMethodsWith defaultClientConfig env (O.OAuthCredentials client secret)
    calls <- newIORef (0 :: Int)
    let oauth =
          baseOAuth
            { O.createOAuthToken = \grant -> do
                modifyIORef' calls (+ 1)
                O.createOAuthToken baseOAuth grant
            }
        -- Do not write the intentionally invalid access token to disk.
        injectedStore = fileStore {R.loadTokens = pure old {R.accessToken = "intentionally-invalid-live-acceptance-token"}}
    manager <- R.newOAuthTokenManager oauth injectedStore
    let api = makeMethodsWithTokenSource defaultClientConfig env (R.tokenManagerSource manager)
    result <- try @R.TokenPersistenceError (retrieveMyUser api)
    case result of
      Right _ -> pure ()
      Left _ -> do
        retryPersistence manager
        _ <- retrieveMyUser api
        pure ()
    count <- readIORef calls
    saved <- R.loadTokens fileStore
    current <- R.currentTokens manager
    unless
      (count == 1 && saved == current && R.accessToken saved /= "intentionally-invalid-live-acceptance-token")
      (putStrLn "Live reactive-refresh assertions failed" >> exitFailure)
    unless (R.refreshToken saved /= Nothing) (putStrLn "No replacement refresh token; refreshing-installation gate remains pending" >> exitFailure)
    putStrLn "live unauthorized -> refresh -> retry succeeded: True"
    putStrLn "refresh requests: 1"
    putStrLn "persisted replacement: True"
    putStrLn ("access token changed: " <> show (R.accessToken old /= R.accessToken saved))
    putStrLn ("refresh token changed: " <> maybe "not returned" (\_ -> show (R.refreshToken old /= R.refreshToken saved)) (R.refreshToken saved))

retryPersistence :: R.OAuthTokenManager -> IO ()
retryPersistence manager = do
  putStrLn "Replacement retained in memory. Fix storage, then press Enter to retry saving; stopping may require login again."
  _ <- getLine
  result <- try @R.TokenPersistenceError (R.retryTokenPersistence manager)
  either (const (retryPersistence manager)) (const (pure ())) result
