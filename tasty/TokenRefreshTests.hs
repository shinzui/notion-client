{-# LANGUAGE GHC2024 #-}
{-# LANGUAGE AllowAmbiguousTypes #-}

module TokenRefreshTests (tests) where

import Control.Concurrent
import Control.Exception
import Control.Monad (forM_, void)
import Data.Aeson qualified as A
import Data.IORef
import Data.List (isInfixOf)
import Data.Time.Clock
import FakeNotion
import Notion.V1
import Notion.V1.Error (NotionError)
import Notion.V1.OAuth qualified as O
import Notion.V1.OAuth.Refresh qualified as R
import OAuthTests (credentials, personOwner, tokenJson)
import Test.Tasty
import Test.Tasty.HUnit
import TokenSourceTests (bounded, unauthorized, userJson)

fixture :: IO (R.OAuthTokens, O.OAuthTokenResponse)
fixture = do
  response <- either assertFailure pure (A.eitherDecode (tokenJson personOwner))
  now <- getCurrentTime
  let old = (R.oauthTokensFromResponse now response) {R.accessToken = "old", R.refreshToken = Just "old-refresh"}
  pure (old, response)

methods :: (O.OAuthTokenRequest -> IO O.OAuthTokenResponse) -> O.OAuthMethods
methods f = O.OAuthMethods f (const (pure (O.OAuthRevokeResponse Nothing))) (const (pure (O.OAuthIntrospectResponse False Nothing Nothing Nothing)))

forkResult :: IO a -> IO (ThreadId, MVar (Either SomeException a))
forkResult action = do
  result <- newEmptyMVar
  tid <- forkFinally action (putMVar result)
  pure (tid, result)

succeeds :: MVar (Either SomeException a) -> IO a
succeeds result = bounded (takeMVar result) >>= either (assertFailure . displayException) pure

expect :: forall e a. (Exception e) => IO a -> IO ()
expect action = try @e action >>= either (const (pure ())) (const (assertFailure "expected exception"))

counting :: O.OAuthTokenResponse -> IO (O.OAuthMethods, IO Int)
counting response = do
  ref <- newIORef (0 :: Int)
  pure (methods (\_ -> atomicModifyIORef' ref (\n -> (n + 1, ())) >> pure response), readIORef ref)

tests :: TestTree
tests =
  testGroup
    "TokenRefresh"
    [ testCase "reject refresh persist retry and timestamp" $ do
        (old, response) <- fixture
        (oauthEnv, grants) <- fakeClientEnv [jsonReply 200 (tokenJson personOwner)]
        store <- R.inMemoryTokenStore old
        manager <- R.newOAuthTokenManager (O.makeOAuthMethodsWith defaultClientConfig oauthEnv credentials) store
        (env, recorded) <- fakeClientEnvWith $ \request ->
          pure $
            if lookupRecordedHeader "Authorization" request == Just "Bearer old" then unauthorized else jsonReply 200 userJson
        before <- getCurrentTime
        void (retrieveMyUser (makeMethodsWithTokenSource defaultClientConfig env (R.tokenManagerSource manager)))
        after <- getCurrentTime
        tokens <- R.currentTokens manager
        R.accessToken tokens @?= O.accessToken response
        R.botId tokens @?= R.botId old
        R.workspaceId tokens @?= R.workspaceId old
        assertBool "obtained at response" (R.obtainedAt tokens >= before && R.obtainedAt tokens <= after)
        R.loadTokens store >>= (@?= tokens)
        length <$> readIORef grants >>= (@?= 1)
        map (lookupRecordedHeader "Authorization") <$> readIORef recorded >>= (@?= [Just "Bearer old", Just "Bearer secret_tanaka_access"]),
      testCase "concurrent old rejections share rotation and wait for durable save" $ bounded $ do
        (old, response) <- fixture
        (oauth, count) <- counting response
        bothOld <- newEmptyMVar
        reject <- newEmptyMVar
        saving <- newEmptyMVar
        durable <- newEmptyMVar
        seenOld <- newIORef (0 :: Int)
        let store = R.TokenStore (pure old) (\_ -> putMVar saving () >> readMVar durable)
        manager <- R.newOAuthTokenManager oauth store
        (env, recorded) <- fakeClientEnvWith $ \request ->
          if lookupRecordedHeader "Authorization" request == Just "Bearer old"
            then do
              n <- atomicModifyIORef' seenOld (\n -> (n + 1, n + 1))
              if n == 2 then putMVar bothOld () else pure ()
              readMVar reject
              pure unauthorized
            else pure (jsonReply 200 userJson)
        let call = retrieveMyUser (makeMethodsWithTokenSource defaultClientConfig env (R.tokenManagerSource manager))
        (_, a) <- forkResult call
        (_, b) <- forkResult call
        takeMVar bothOld
        putMVar reject ()
        takeMVar saving
        rs <- readIORef recorded
        length rs @?= 2
        map (lookupRecordedHeader "Authorization") rs @?= replicate 2 (Just "Bearer old")
        count >>= (@?= 1)
        putMVar durable ()
        void (succeeds a)
        void (succeeds b)
        renewToken (R.tokenManagerSource manager) "old" >>= (@?= Just "secret_tanaka_access")
        count >>= (@?= 1),
      testCase "invalid grant and missing refresh become remembered terminal states" $ do
        (old, _) <- fixture
        forM_ [False, True] $ \missing -> do
          attempts <- newIORef (0 :: Int)
          let failure = O.OAuthError O.OAuthInvalidGrant Nothing Nothing Nothing Nothing
              oauth = methods (\_ -> modifyIORef' attempts (+ 1) >> throwIO failure)
          store <- R.inMemoryTokenStore (if missing then old {R.refreshToken = Nothing} else old)
          manager <- R.newOAuthTokenManager oauth store
          expect @R.ReauthorizationRequired (R.refreshTokensNow manager)
          expect @R.ReauthorizationRequired (currentToken (R.tokenManagerSource manager))
          expect @R.ReauthorizationRequired (R.refreshTokensNow manager)
          expect @R.ReauthorizationRequired (renewToken (R.tokenManagerSource manager) "old")
          readIORef attempts >>= (@?= if missing then 0 else 1),
      testCase "save failure retains exact pair and persistence retry never rotates" $ do
        (old, response) <- fixture
        (oauth, count) <- counting response
        broken <- newIORef True
        saved <- newIORef []
        manager <-
          R.newOAuthTokenManager
            oauth
            ( R.TokenStore
                (pure old)
                ( \t -> do
                    modifyIORef' saved (<> [t])
                    readIORef broken >>= \b -> if b then ioError (userError "SENTINEL") else pure ()
                )
            )
        expect @R.TokenPersistenceError (R.refreshTokensNow manager)
        pending <- R.currentTokens manager
        R.accessToken pending @?= O.accessToken response
        expect @R.TokenPersistenceError (currentToken (R.tokenManagerSource manager))
        expect @R.TokenPersistenceError (R.refreshTokensNow manager)
        count >>= (@?= 1)
        writeIORef broken False
        R.retryTokenPersistence manager >>= (@?= pending)
        R.retryTokenPersistence manager >>= (@?= pending)
        readIORef saved >>= (@?= [pending, pending])
        currentToken (R.tokenManagerSource manager) >>= (@?= O.accessToken response)
        count >>= (@?= 1),
      testCase "lost response blocks reuse and preserves last known credentials" $ do
        (old, _) <- fixture
        calls <- newIORef (0 :: Int)
        store <- R.inMemoryTokenStore old
        manager <- R.newOAuthTokenManager (methods (\_ -> modifyIORef' calls (+ 1) >> ioError (userError "lost response"))) store
        expect @IOException (R.refreshTokensNow manager)
        expect @R.RefreshOutcomeUnknown (currentToken (R.tokenManagerSource manager))
        expect @R.RefreshOutcomeUnknown (R.refreshTokensNow manager)
        expect @R.RefreshOutcomeUnknown (R.retryTokenPersistence manager)
        R.currentTokens manager >>= (@?= old)
        readIORef calls >>= (@?= 1),
      testCase "cancellation during exchange publishes uncertainty and releases lock" $ bounded $ do
        (old, _) <- fixture
        started <- newEmptyMVar
        blocked <- newEmptyMVar
        store <- R.inMemoryTokenStore old
        manager <- R.newOAuthTokenManager (methods (\_ -> putMVar started () >> takeMVar blocked)) store
        (tid, result) <- forkResult (R.refreshTokensNow manager)
        takeMVar started
        killThread tid
        bounded (takeMVar result) >>= \r -> assertBool "cancelled" (either (const True) (const False) r)
        expect @R.RefreshOutcomeUnknown (R.refreshTokensNow manager)
        R.currentTokens manager >>= (@?= old),
      testCase "cancellation after response during save retains pending pair" $ bounded $ do
        (old, response) <- fixture
        (oauth, count) <- counting response
        started <- newEmptyMVar
        blocked <- newEmptyMVar
        broken <- newIORef True
        let save _ = readIORef broken >>= \b -> if b then putMVar started () >> takeMVar blocked else pure ()
        manager <- R.newOAuthTokenManager oauth (R.TokenStore (pure old) save)
        (tid, result) <- forkResult (R.refreshTokensNow manager)
        takeMVar started
        killThread tid
        takeMVar result >>= \r -> assertBool "persistence error" (either (maybe False (const True) . fromException @R.TokenPersistenceError) (const False) r)
        pending <- R.currentTokens manager
        R.accessToken pending @?= O.accessToken response
        expect @R.TokenPersistenceError (currentToken (R.tokenManagerSource manager))
        writeIORef broken False
        R.retryTokenPersistence manager >>= (@?= pending)
        count >>= (@?= 1),
      testCase "null refresh stays absent; invalid identity or type cannot authorize" $ do
        (old, response) <- fixture
        (oauth, count) <- counting response {O.refreshToken = Nothing}
        store <- R.inMemoryTokenStore old
        manager <- R.newOAuthTokenManager oauth store
        replacement <- R.refreshTokensNow manager
        R.refreshToken replacement @?= Nothing
        expect @R.ReauthorizationRequired (R.refreshTokensNow manager)
        count >>= (@?= 1)
        forM_ [response {O.tokenType = "mac"}, response {O.botId = "other"}, response {O.workspaceId = "other"}, response {O.accessToken = ""}] $ \invalid -> do
          (badOAuth, _) <- counting invalid
          freshStore <- R.inMemoryTokenStore old
          bad <- R.newOAuthTokenManager badOAuth freshStore
          expect @R.RefreshOutcomeUnknown (R.refreshTokensNow bad)
          expect @R.RefreshOutcomeUnknown (currentToken (R.tokenManagerSource bad)),
      testCase "explicit OAuth rejection remains distinguishable without invalidating pair" $ do
        (old, _) <- fixture
        store <- R.inMemoryTokenStore old
        let failure = O.OAuthError O.OAuthInvalidClient Nothing Nothing Nothing Nothing
        manager <- R.newOAuthTokenManager (methods (\_ -> throwIO failure)) store
        expect @O.OAuthError (R.refreshTokensNow manager)
        currentToken (R.tokenManagerSource manager) >>= (@?= "old"),
      testCase "JSON roundtrip, load once, and redacted rendering" $ do
        (old, response) <- fixture
        A.decode (A.encode old) @?= Just old
        assertBool "tokens redacted" (not ("old-refresh" `isInfixOf` show old))
        loaded <- newIORef (0 :: Int)
        (oauth, _) <- counting response
        manager <- R.newOAuthTokenManager oauth (R.TokenStore (modifyIORef' loaded (+ 1) >> pure old) (const (pure ())))
        void (currentToken (R.tokenManagerSource manager))
        void (R.refreshTokensNow manager)
        readIORef loaded >>= (@?= 1)
    ]
