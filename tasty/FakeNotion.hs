-- | A scripted stand-in for the Notion API that never touches the network.
--
-- 'fakeClientEnv' builds a 'ClientEnv' whose middleware ignores the real HTTP
-- application, records every request, and answers from a list of replies.
module FakeNotion
  ( Recorded (..),
    FakeReply (..),
    fakeClientEnv,
    fakeClientEnvWith,
    fakeBaseUrl,
    jsonReply,
    lookupRecordedHeader,
  )
where

import Control.Monad.Error.Class (throwError)
import Control.Monad.IO.Class (liftIO)
import Data.Bifunctor (bimap)
import Data.ByteString qualified as BS
import Data.ByteString.Builder (toLazyByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (toList)
import Data.IORef (IORef, atomicModifyIORef', newIORef)
import Network.HTTP.Client (defaultManagerSettings, newManager)
import Network.HTTP.Types (Header, HeaderName, Method, http11, mkStatus)
import Servant.Client (BaseUrl (..), ClientEnv (..), ClientError (..), Scheme (..), mkClientEnv)
import Servant.Client.Core (RequestF (..), ResponseF (..))

-- | A request the fake received.
data Recorded = Recorded
  { method :: Method,
    path :: LBS.ByteString,
    headers :: [Header]
  }
  deriving stock (Show)

-- | A scripted reply.
data FakeReply = FakeReply
  { status :: Int,
    replyHeaders :: [Header],
    body :: LBS.ByteString
  }

-- | A reply with a JSON content type.
jsonReply :: Int -> LBS.ByteString -> FakeReply
jsonReply s = FakeReply s [("Content-Type", "application/json")]

fakeBaseUrl :: BaseUrl
fakeBaseUrl = BaseUrl Https "api.notion.com" 443 "/v1"

-- | First value of a header in a recorded request.
lookupRecordedHeader :: HeaderName -> Recorded -> Maybe BS.ByteString
lookupRecordedHeader name Recorded {headers} = lookup name headers

-- | A 'ClientEnv' answering from the script, and the requests it records.
fakeClientEnv :: [FakeReply] -> IO (ClientEnv, IORef [Recorded])
fakeClientEnv script = do
  remaining <- newIORef script
  fakeClientEnvWith $ \_ -> do
    next <- atomicModifyIORef' remaining (\case [] -> ([], Nothing); r : rs -> (rs, Just r))
    maybe (ioError (userError "FakeNotion: script exhausted")) pure next

-- | Header-dependent replies, with an atomic request recorder.
fakeClientEnvWith :: (Recorded -> IO FakeReply) -> IO (ClientEnv, IORef [Recorded])
fakeClientEnvWith reply = do
  manager <- newManager defaultManagerSettings
  recorded <- newIORef []
  let mw _realApp req = do
        let request = Recorded (requestMethod req) (toLazyByteString (requestPath req)) (toList (requestHeaders req))
        liftIO $ atomicModifyIORef' recorded (\rs -> (rs <> [request], ()))
        FakeReply {status, replyHeaders, body} <- liftIO (reply request)
        let resp = Response (mkStatus status "") (foldMap pure replyHeaders) http11 body
        if status >= 200 && status < 300
          then pure resp
          else throwError (FailureResponse (bimap (const ()) (\p -> (fakeBaseUrl, LBS.toStrict (toLazyByteString p))) req) resp)
  pure ((mkClientEnv manager fakeBaseUrl) {middleware = mw}, recorded)
