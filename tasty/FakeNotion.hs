-- | A scripted stand-in for the Notion API that never touches the network.
--
-- 'fakeClientEnv' builds a 'ClientEnv' whose middleware ignores the real HTTP
-- application, records every request, and answers from a list of replies.
module FakeNotion
  ( Recorded (..),
    FakeReply (..),
    fakeClientEnv,
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
import Data.IORef (IORef, atomicModifyIORef', modifyIORef', newIORef)
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
  manager <- newManager defaultManagerSettings
  remaining <- newIORef script
  recorded <- newIORef []
  let mw _realApp req = do
        liftIO $
          modifyIORef'
            recorded
            (<> [Recorded (requestMethod req) (toLazyByteString (requestPath req)) (toList (requestHeaders req))])
        next <- liftIO $ atomicModifyIORef' remaining (\case [] -> ([], Nothing); r : rs -> (rs, Just r))
        FakeReply {status, replyHeaders, body} <-
          maybe (liftIO (ioError (userError "FakeNotion: script exhausted"))) pure next
        let resp = Response (mkStatus status "") (foldMap pure replyHeaders) http11 body
        if status >= 200 && status < 300
          then pure resp
          else
            throwError
              (FailureResponse (bimap (const ()) (\p -> (fakeBaseUrl, LBS.toStrict (toLazyByteString p))) req) resp)
  pure ((mkClientEnv manager fakeBaseUrl) {middleware = mw}, recorded)
