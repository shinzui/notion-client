{-# LANGUAGE GHC2024 #-}

module OAuthExampleTests (tests) where

import Control.Concurrent
import Control.Exception
import Data.Aeson qualified as A
import Data.Bits ((.&.))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as L
import Data.IORef
import Data.Time.Clock
import FileTokenStore
import Login
import Network.HTTP.Client qualified as H
import Network.HTTP.Types qualified as T
import Network.Wai qualified as W
import Network.Wai.Handler.Warp qualified as Warp
import Notion.V1.OAuth qualified as O
import Notion.V1.OAuth.Authorization qualified as Auth
import Notion.V1.OAuth.Refresh qualified as R
import OAuthTests (personOwner, tokenJson)
import System.Directory qualified as D
import System.FilePath
import System.Posix.Files qualified as F
import System.Posix.Temp (mkdtemp)
import Test.Tasty
import Test.Tasty.HUnit
import TokenSourceTests (bounded)

request :: Auth.AuthorizationRequest
request = Auth.AuthorizationRequest "client" "http://localhost:8765/callback" (Auth.OAuthState "fixed-state")

fixture :: IO (R.OAuthTokens, O.OAuthTokenResponse)
fixture = do
  response <- either assertFailure pure (A.eitherDecode (tokenJson personOwner))
  now <- getCurrentTime
  pure (R.oauthTokensFromResponse now response, response)

oauth :: IO O.OAuthTokenResponse -> O.OAuthMethods
oauth action = O.OAuthMethods (const action) (const (pure (O.OAuthRevokeResponse Nothing))) (const (pure (O.OAuthIntrospectResponse False Nothing Nothing Nothing)))

get :: H.Manager -> Int -> String -> IO (H.Response L.ByteString)
get manager port query = H.parseRequest ("http://127.0.0.1:" <> show port <> query) >>= \r -> H.httpLbs r manager

withDirectory :: (FilePath -> IO a) -> IO a
withDirectory = bracket (mkdtemp "/tmp/notion-oauth-tests-") D.removePathForcibly

tests :: TestTree
tests =
  testGroup
    "OAuthExample"
    [ testCase "invalid callback leaves login pending; valid callback saves before success" $ bounded $ do
        (tokens, response) <- fixture
        store <- R.inMemoryTokenStore tokens
        calls <- newIORef (0 :: Int)
        let exchange = modifyIORef' calls (+ 1) >> pure response
        (app, result) <- newLoginApplication (oauth exchange) store request "/callback"
        Warp.testWithApplication (pure app) $ \port -> do
          manager <- H.newManager H.defaultManagerSettings
          bad <- get manager port "/callback?code=secret-code&state=forged"
          H.responseStatus bad @?= T.status400
          readIORef calls >>= (@?= 0)
          success <- get manager port "/callback?code=secret-code&state=fixed-state"
          H.responseStatus success @?= T.status200
          H.responseBody success @?= "Connected"
          lookup "Cache-Control" (H.responseHeaders success) @?= Just "no-store"
          lookup "Referrer-Policy" (H.responseHeaders success) @?= Just "no-referrer"
          result >>= \case Connected _ -> pure (); other -> assertFailure (show other)
          readIORef calls >>= (@?= 1)
          duplicate <- get manager port "/callback?code=secret-code&state=fixed-state"
          H.responseStatus duplicate @?= T.status409
          readIORef calls >>= (@?= 1),
      testCase "denial requires state, consumes once, and never exchanges" $ bounded $ do
        (tokens, _) <- fixture
        store <- R.inMemoryTokenStore tokens
        (app, result) <- newLoginApplication (oauth (assertFailure "must not exchange")) store request "/callback"
        Warp.testWithApplication (pure app) $ \port -> do
          manager <- H.newManager H.defaultManagerSettings
          bad <- get manager port "/callback?error=access_denied"
          H.responseStatus bad @?= T.status400
          cancelled <- get manager port "/callback?error=access_denied&state=fixed-state&error_description=%3Cscript%3Esecret%3C%2Fscript%3E"
          H.responseBody cancelled @?= "Consent was cancelled"
          result >>= \case Cancelled -> pure (); other -> assertFailure (show other)
          duplicate <- get manager port "/callback?error=access_denied&state=fixed-state"
          H.responseStatus duplicate @?= T.status409,
      testCase "concurrent duplicates exchange once; no success before save returns" $ bounded $ do
        (tokens, response) <- fixture
        calls <- newIORef (0 :: Int)
        saving <- newEmptyMVar
        release <- newEmptyMVar
        first <- newEmptyMVar
        let store = R.TokenStore (pure tokens) (\_ -> putMVar saving () >> takeMVar release)
        (app, _) <- newLoginApplication (oauth (modifyIORef' calls (+ 1) >> pure response)) store request "/callback"
        Warp.testWithApplication (pure app) $ \port -> do
          manager <- H.newManager H.defaultManagerSettings
          _ <- forkFinally (get manager port "/callback?code=one&state=fixed-state") (putMVar first)
          takeMVar saving
          isEmptyMVar first >>= assertBool "no response before persistence"
          duplicate <- get manager port "/callback?code=two&state=fixed-state"
          H.responseStatus duplicate @?= T.status409
          readIORef calls >>= (@?= 1)
          putMVar release ()
          takeMVar first >>= either (assertFailure . displayException) (\r -> H.responseBody r @?= "Connected"),
      testCase "initial save failure retains credentials for retry without another exchange" $ bounded $ do
        (tokens, response) <- fixture
        broken <- newIORef True
        saved <- newIORef []
        calls <- newIORef (0 :: Int)
        let store =
              R.TokenStore
                (pure tokens)
                ( \pair -> do
                    modifyIORef' saved (<> [pair])
                    readIORef broken >>= \b -> if b then ioError (userError "SECRET") else pure ()
                )
        (app, result) <- newLoginApplication (oauth (modifyIORef' calls (+ 1) >> pure response)) store request "/callback"
        Warp.testWithApplication (pure app) $ \port -> do
          manager <- H.newManager H.defaultManagerSettings
          failed <- get manager port "/callback?code=SECRET&state=fixed-state"
          H.responseStatus failed @?= T.status500
          assertBool "no reflected secret" (not ("SECRET" `BS.isInfixOf` L.toStrict (H.responseBody failed)))
          result >>= \case
            SavePending pair -> do
              show (SavePending pair) @?= "SavePending"
              writeIORef broken False
              R.saveTokens store pair
              readIORef saved >>= (@?= [pair, pair])
            other -> assertFailure (show other)
          readIORef calls >>= (@?= 1),
      testCase "exchange failures and unrelated paths produce generic pages" $ bounded $ do
        (tokens, _) <- fixture
        store <- R.inMemoryTokenStore tokens
        (app, result) <- newLoginApplication (oauth (ioError (userError "SECRET <script>"))) store request "/callback"
        Warp.testWithApplication (pure app) $ \port -> do
          manager <- H.newManager H.defaultManagerSettings
          notFound <- get manager port "/other?code=SECRET&state=fixed-state"
          H.responseStatus notFound @?= T.status404
          failed <- get manager port "/callback?code=SECRET&state=fixed-state"
          H.responseBody failed @?= "Connection failed; start login again"
          result >>= \case LoginFailed -> pure (); other -> assertFailure (show other),
      testCase "startup failure propagates before announcement; timeout closes listener" $ bounded $ do
        (tokens, response) <- fixture
        store <- R.inMemoryTokenStore tokens
        announced <- newIORef False
        let emptyApp _ respond = respond (W.responseLBS T.status200 [] "")
        Warp.testWithApplication (pure emptyApp) $ \busy -> do
          failure <- try @IOException (runLogin busy 20000 (oauth (pure response)) store request (writeIORef announced True))
          assertBool "bind failure" (either (const True) (const False) failure)
          readIORef announced >>= (@?= False)
        free <- Warp.testWithApplication (pure emptyApp) pure
        runLogin free 20000 (oauth (pure response)) store request (writeIORef announced True) >>= \case
          LoginExpired -> pure ()
          other -> assertFailure (show other)
        readIORef announced >>= (@?= True)
        -- Rebinding the same port after timeout proves the listener was released.
        runLogin free 1000 (oauth (pure response)) store request (pure ()) >>= \case
          LoginExpired -> pure ()
          other -> assertFailure (show other),
      testCase "redirect configuration requires a path without query or fragment" $ do
        Auth.oauthStateText (Auth.state request) @?= "fixed-state"
        callbackPath "http://localhost:8765/callback" @?= Right "/callback"
        callbackPath "https://tunnel.example/cb/path" @?= Right "/cb/path"
        mapM_ (\uri -> assertBool "rejected" (either (const True) (const False) (callbackPath uri))) ["/relative", "http://localhost", "http://localhost/cb?x=y", "http://localhost/cb#f", "http://user@localhost/cb"],
      testCase "file replacement is private complete and loads on restart" $ withDirectory $ \directory -> do
        (tokens, _) <- fixture
        let path = directory </> "tokens.json"
            store = fileTokenStore path
            replacement = tokens {R.accessToken = "new-access", R.refreshToken = Just "new-refresh"}
        tokenFileExists path >>= (@?= False)
        R.saveTokens store tokens
        mode <- F.fileMode <$> F.getFileStatus path
        mode .&. 0o077 @?= 0
        R.saveTokens store replacement
        R.loadTokens (fileTokenStore path) >>= (@?= replacement)
        L.readFile path >>= \bytes -> A.decode bytes @?= Just replacement
        D.listDirectory directory >>= (@?= ["tokens.json"]),
      testCase "pre-rename failure preserves old destination and cleans owned temporary" $ withDirectory $ \directory -> do
        (tokens, _) <- fixture
        let path = directory </> "tokens.json"
            store = fileTokenStore path
        R.saveTokens store tokens
        failed <- try @SomeException (R.saveTokens store tokens {R.workspaceName = Just (error "injected encoding failure")})
        assertBool "failed" (either (const True) (const False) failed)
        R.loadTokens store >>= (@?= tokens)
        D.listDirectory directory >>= (@?= ["tokens.json"]),
      testCase "reject symlink token paths and unsafe destination directories" $ withDirectory $ \directory -> do
        (tokens, _) <- fixture
        let target = directory </> "target.json"
            link = directory </> "tokens.json"
        R.saveTokens (fileTokenStore target) tokens
        F.createSymbolicLink target link
        failure <- try @IOException (R.saveTokens (fileTokenStore link) tokens)
        assertBool "symlink rejected" (either (const True) (const False) failure)
        R.loadTokens (fileTokenStore target) >>= (@?= tokens)
        F.setFileMode directory 0o777
        unsafe <- try @IOException (R.saveTokens (fileTokenStore target) tokens)
        F.setFileMode directory 0o700
        assertBool "unsafe directory rejected" (either (const True) (const False) unsafe),
      testCase "command lock excludes a second command and confirmed logout clears file" $ withDirectory $ \directory -> do
        (tokens, _) <- fixture
        let path = directory </> "tokens.json"
        withTokenFileLock path $ do
          R.saveTokens (fileTokenStore path) tokens
          second <- try @IOException (withTokenFileLock path (assertFailure "must not acquire"))
          assertBool "second command refused" (either (const True) (const False) second)
          R.loadTokens (fileTokenStore path) >>= (@?= tokens)
        withTokenFileLock path (removeTokenFile path)
        tokenFileExists path >>= (@?= False)
    ]
