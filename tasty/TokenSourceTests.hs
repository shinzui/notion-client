module TokenSourceTests (tests, unauthorized, userJson, bounded) where

import Control.Exception
import Control.Monad (forM_, void)
import Data.ByteString.Lazy qualified as L
import Data.IORef
import FakeNotion
import Notion.V1
import Notion.V1.Error
import Notion.V1.OAuth qualified as O
import Notion.V1.TokenSource (withAuthorization)
import OAuthTests (credentials)
import System.Timeout qualified as Timeout
import Test.Tasty
import Test.Tasty.HUnit

unauthorized :: FakeReply
unauthorized = jsonReply 401 "{\"object\":\"error\",\"code\":\"unauthorized\",\"message\":\"invalid token\"}"

userJson :: L.ByteString
userJson = "{\"object\":\"user\",\"id\":\"6f1c2b9e-4d3a-4e8f-9b7c-2a1d0e5f3c4b\",\"name\":\"Sato Kenji\",\"type\":\"bot\",\"bot\":{\"owner\":{\"type\":\"workspace\",\"workspace\":true}}}"

bounded :: IO a -> IO a
bounded action = Timeout.timeout 5000000 action >>= maybe (assertFailure "timed out") pure

tests :: TestTree
tests =
  testGroup
    "TokenSource"
    [ testCase "source follows changes on every call with one Authorization header" $ do
        ref <- newIORef "t1"
        (env, recorded) <- fakeClientEnv (replicate 2 (jsonReply 200 userJson))
        let api = makeMethodsWithTokenSource defaultClientConfig env (TokenSource (readIORef ref) (const (pure Nothing)))
        void (retrieveMyUser api)
        writeIORef ref "t2"
        void (retrieveMyUser api)
        rs <- readIORef recorded
        map (lookupRecordedHeader "Authorization") rs @?= [Just "Bearer t1", Just "Bearer t2"]
        map (length . filter ((== "Authorization") . fst) . headers) rs @?= [1, 1],
      testCase "renewal once, static rejection, and second rejection do not loop" $ do
        forM_ [False, True] $ \secondFails -> do
          (env, recorded) <- fakeClientEnv [unauthorized, if secondFails then unauthorized else jsonReply 200 userJson]
          calls <- newIORef []
          let source = TokenSource (pure "old") (\old -> modifyIORef' calls (<> [old]) >> pure (Just "new"))
          result <- try @NotionError (retrieveMyUser (makeMethodsWithTokenSource defaultClientConfig env source))
          either (\e -> code e @?= Unauthorized) (const (assertBool "successful" (not secondFails))) result
          readIORef calls >>= (@?= ["old"])
          map (lookupRecordedHeader "Authorization") <$> readIORef recorded >>= (@?= [Just "Bearer old", Just "Bearer new"])
        (env, rs) <- fakeClientEnv [unauthorized]
        result <- try @NotionError (retrieveMyUser (makeMethodsWithEnv defaultClientConfig env "old"))
        either (\e -> code e @?= Unauthorized) (const (assertFailure "expected rejection")) result
        length <$> readIORef rs >>= (@?= 1),
      testCase "ordinary retry budget runs independently before and after renewal" $ do
        let rateLimited = jsonReply 429 "{\"object\":\"error\",\"code\":\"rate_limited\",\"message\":\"slow down\"}"
            config = defaultClientConfig {retryOptions = RetryOptions 1 0.000001 0.000001}
        (env, recorded) <- fakeClientEnv [rateLimited, unauthorized, rateLimited, jsonReply 200 userJson]
        renewals <- newIORef (0 :: Int)
        let source = TokenSource (pure "old") (\_ -> modifyIORef' renewals (+ 1) >> pure (Just "new"))
        void (retrieveMyUser (makeMethodsWithTokenSource config env source))
        length <$> readIORef recorded >>= (@?= 4)
        readIORef renewals >>= (@?= 1),
      testCase "decode timeout untyped 401 and failed POST never renew" $ do
        renewals <- newIORef (0 :: Int)
        let source = TokenSource (pure "old") (\_ -> modifyIORef' renewals (+ 1) >> pure (Just "new"))
        forM_ [jsonReply 401 "{}", jsonReply 200 "{}", jsonReply 500 "{\"object\":\"error\",\"code\":\"internal_server_error\",\"message\":\"bad\"}"] $ \reply -> do
          (env, _) <- fakeClientEnv [reply]
          void (try @SomeException (retrieveMyUser (makeMethodsWithTokenSource defaultClientConfig {retryOptions = noRetries} env source)))
        void (try @RequestTimeoutError (withAuthorization source (\_ -> throwIO RequestTimeoutError)))
        readIORef renewals >>= (@?= 0),
      testCase "Basic OAuth authentication bypasses bearer source" $ do
        (env, recorded) <- fakeClientEnv [jsonReply 200 "{\"active\":false}"]
        void (O.introspectOAuthToken (O.makeOAuthMethodsWith defaultClientConfig env credentials) "token")
        map (lookupRecordedHeader "Authorization") <$> readIORef recorded >>= (@?= [Just "Basic Y2xpZW50OnNlY3JldA=="])
    ]
