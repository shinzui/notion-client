module TokenHTTPTests (tests) where

import Control.Exception
import Control.Monad (void)
import Control.Monad.IO.Class qualified
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as L
import Data.Foldable qualified
import Data.IORef
import Network.HTTP.Client qualified as H
import Network.HTTP.Types qualified as T
import Network.Wai qualified as W
import Network.Wai.Handler.Warp qualified as Warp
import Notion.V1
import Notion.V1.Client (applyTimeout)
import Notion.V1.Error
import Notion.V1.FileUploads (mkSendFileUpload)
import Notion.V1.Search qualified
import Servant.Client qualified as S
import Servant.Client.Core qualified
import System.Directory (getTemporaryDirectory, removeFile)
import System.IO
import Test.Tasty
import Test.Tasty.HUnit
import TokenSourceTests (bounded)

rejection :: L.ByteString
rejection = "{\"object\":\"error\",\"code\":\"unauthorized\",\"message\":\"invalid token\"}"

tests :: TestTree
tests =
  testGroup
    "TokenSource HTTP"
    [ testCase "real acquisition closes rejection before renewal; opened callbacks never replay" $ bounded $ do
        requests <- newIORef []
        closed <- newIORef False
        renewals <- newIORef (0 :: Int)
        let app req respond = do
              atomicModifyIORef' requests (\rs -> (rs <> [W.requestHeaders req], ()))
              respond $
                if lookup "Authorization" (W.requestHeaders req) == Just "Bearer old"
                  then W.responseLBS T.status401 [("Content-Type", "application/json")] rejection
                  else W.responseLBS T.status200 [("Content-Type", "text/event-stream")] "data: ok\n\n"
        Warp.testWithApplication (pure app) $ \port -> do
          manager <- H.newManager H.defaultManagerSettings
          let base = S.BaseUrl S.Http "127.0.0.1" port "/v1"
              source =
                TokenSource
                  (pure "old")
                  ( \_ -> do
                      readIORef closed >>= assertBool "rejected response already closed"
                      modifyIORef' renewals (+ 1)
                      pure (Just "new")
                  )
              context = requestContextWithTokenSource defaultClientConfig (S.mkClientEnv manager base) source
          request <- H.parseRequest (S.showBaseUrl base <> "/sessions")
          let acquire = withStandardHeaders context $ \headers -> withRetries defaultClientConfig "POST" "sessions.stream" $ mask $ \restore -> do
                response <- restore (H.responseOpen (applyTimeout defaultClientConfig request {H.requestHeaders = headers, H.method = "POST"}) manager)
                if T.statusIsSuccessful (H.responseStatus response)
                  then pure response
                  else do
                    chunks <- restore (H.brConsume (H.responseBody response)) `finally` (H.responseClose response >> writeIORef closed True)
                    throwIO (notionErrorFromResponse (H.responseStatus response) (H.responseHeaders response) (L.fromChunks chunks))
          outcome <- try @NotionError $ bracket acquire H.responseClose $ \res -> do
            chunk <- H.brRead (H.responseBody res)
            assertBool "stream opened" (not (BS.null chunk))
            throwIO (NotionError "error" 401 Unauthorized "callback failed" Nothing Nothing Nothing Nothing)
          either (\e -> code e @?= Unauthorized) (const (assertFailure "callback should throw")) outcome
          readIORef renewals >>= (@?= 1)
          hs <- readIORef requests
          map (lookup "Authorization") hs @?= [Just "Bearer old", Just "Bearer new"]
          map (lookup "Notion-Version") hs @?= replicate 2 (Just "2026-03-11")
          assertBool "user agent on every open" (all ((/= Nothing) . lookup "User-Agent") hs),
      testCase "caller middleware and request builder retained; bytes replay identically" $ bounded $ do
        received <- newIORef []
        middle <- newIORef []
        built <- newIORef (0 :: Int)
        renewals <- newIORef (0 :: Int)
        let app req respond = do
              body <- W.strictRequestBody req
              atomicModifyIORef' received (\rs -> (rs <> [(W.requestHeaders req, body)], ()))
              respond $
                W.responseLBS
                  (if lookup "Authorization" (W.requestHeaders req) == Just "Bearer old" then T.status401 else T.status200)
                  [("Content-Type", "application/json")]
                  (if lookup "Authorization" (W.requestHeaders req) == Just "Bearer old" then rejection else "{\"object\":\"list\",\"results\":[],\"has_more\":false,\"next_cursor\":null}")
        Warp.testWithApplication (pure app) $ \port -> do
          manager <- H.newManager H.defaultManagerSettings
          let env = S.mkClientEnv manager (S.BaseUrl S.Http "127.0.0.1" port "/v1")
              custom =
                env
                  { S.makeClientRequest = \base req -> modifyIORef' built (+ 1) >> S.makeClientRequest env base req,
                    S.middleware = \next req -> do
                      Control.Monad.IO.Class.liftIO $ modifyIORef' middle (<> [Data.Foldable.toList (Servant.Client.Core.requestHeaders req)])
                      next req
                  }
              source = TokenSource (pure "old") (\_ -> modifyIORef' renewals (+ 1) >> pure (Just "new"))
          void (search (makeMethodsWithTokenSource defaultClientConfig custom source) (Notion.V1.Search.SearchRequest Nothing Nothing Nothing Nothing Nothing))
          rs <- readIORef received
          case rs of
            [(_, a), (_, b)] -> a @?= b
            _ -> assertFailure "expected two byte requests"
          length <$> readIORef middle >>= (@?= 2)
          readIORef middle >>= mapM_ (\hs -> length (filter ((== "Authorization") . fst) hs) @?= 1)
          readIORef built >>= (@?= 2)
          readIORef renewals >>= (@?= 1),
      testCase "file-backed multipart body can be replayed after rejection" $
        bounded $
          bracket (getTemporaryDirectory >>= \directory -> openBinaryTempFile directory "notion-upload") (\(path, h) -> hClose h `finally` removeFile path) $ \(path, h) -> do
            BS.hPut h "fixture bytes: Tanaka Hanako"
            hFlush h
            hClose h
            received <- newIORef []
            let app req respond = do
                  body <- W.strictRequestBody req
                  atomicModifyIORef' received (\rs -> (rs <> [body], ()))
                  respond $
                    W.responseLBS
                      (if lookup "Authorization" (W.requestHeaders req) == Just "Bearer old" then T.status401 else T.status200)
                      [("Content-Type", "application/json")]
                      (if lookup "Authorization" (W.requestHeaders req) == Just "Bearer old" then rejection else "{}")
            Warp.testWithApplication (pure app) $ \port -> do
              manager <- H.newManager H.defaultManagerSettings
              let env = S.mkClientEnv manager (S.BaseUrl S.Http "127.0.0.1" port "/v1")
                  source = TokenSource (pure "old") (const (pure (Just "new")))
              -- The deliberately partial success fixture fails decoding after acquisition.
              void (try @S.ClientError (sendFileUploadContent (makeMethodsWithTokenSource defaultClientConfig env source) "upload-id" (mkSendFileUpload path "hanako.txt" "text/plain")))
              readIORef received >>= \case
                [a, b] -> do
                  a @?= b
                  assertBool "file bytes present" ("fixture bytes: Tanaka Hanako" `BS.isInfixOf` L.toStrict b)
                _ -> assertFailure "expected multipart replay"
    ]
