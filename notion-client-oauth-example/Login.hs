-- | A single local login session, with ten-minute expiry and atomic single use.
module Login
  ( LoginResult (..),
    newLoginApplication,
    runLogin,
    callbackPath,
  )
where

import Control.Concurrent
import Control.Exception
import Control.Monad (void)
import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as B8
import Data.ByteString.Lazy qualified as L
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as T
import Data.Time.Clock
import Network.HTTP.Types
import Network.Wai qualified as W
import Network.Wai.Handler.Warp qualified as Warp
import Notion.V1.OAuth (OAuthErrorCode (OAuthAccessDenied), OAuthMethods)
import Notion.V1.OAuth.Authorization
import Notion.V1.OAuth.Refresh
import System.Timeout qualified as Timeout

-- Secrets are retained only for explicit save recovery; Show is redacted.
data LoginResult = Connected OAuthTokens | SavePending OAuthTokens | Cancelled | LoginFailed | LoginExpired

instance Show LoginResult where
  show (Connected _) = "Connected"
  show (SavePending _) = "SavePending"
  show Cancelled = "Cancelled"
  show LoginFailed = "LoginFailed"
  show LoginExpired = "LoginExpired"

-- | Validate an absolute HTTP(S) redirect and use its exact encoded path.
-- No query, fragment or user-info is accepted. The exact URI still goes to Notion.
callbackPath :: Text -> Either Text ByteString
callbackPath uri = do
  rest <-
    maybe
      (Left "Redirect URI must be absolute HTTP(S)")
      Right
      (T.stripPrefix "http://" uri `orElse` T.stripPrefix "https://" uri)
  let (authority, path) = T.breakOn "/" rest
  if T.null authority
    || T.null path
    || T.any (`elem` ("?#@\\" :: String)) authority
    || T.any (`elem` ("?#\\" :: String)) path
    || T.any (<= ' ') uri
    then Left "Redirect URI needs an absolute path and no query or fragment"
    else Right (T.encodeUtf8 path)
  where
    orElse (Just a) _ = Just a
    orElse Nothing b = b

-- | Inject methods/store for network-free callback tests. Invalid requests leave
-- the login pending. A valid success or denial claims it once before exchange.
-- The caller keeps the application lifetime within the expiry interval.
newLoginApplication ::
  OAuthMethods ->
  TokenStore ->
  AuthorizationRequest ->
  ByteString ->
  IO (W.Application, IO LoginResult)
newLoginApplication oauth store request path = do
  claim <- newMVar False
  completed <- newEmptyMVar
  let complete result = void (tryPutMVar completed result)
      application req respond
        | W.requestMethod req /= methodGet || W.rawPathInfo req /= path = respond (page status404 "Not found")
        | otherwise = case verifyAuthorizationCallback (state request) (W.queryString req) of
            Left StateMismatch -> respond (page status400 "Invalid callback")
            Left MissingCode -> respond (page status400 "Invalid callback")
            Left MalformedCallback -> respond (page status400 "Invalid callback")
            verified -> mask $ \restore -> do
              already <- modifyMVar claim (\used -> pure (True, used))
              if already
                then respond (page status409 "Callback already used")
                else case verified of
                  Left (AuthorizationDenied OAuthAccessDenied _) -> do
                    response <- respond (page status200 "Consent was cancelled") `finally` complete Cancelled
                    pure response
                  Left (AuthorizationDenied _ _) -> do
                    response <- respond (page status400 "Authorization failed") `finally` complete LoginFailed
                    pure response
                  Right code -> do
                    exchange <- try @SomeException (restore (exchangeAuthorizationCode oauth request code))
                    case exchange of
                      Left _ -> do
                        response <- respond (page status500 "Connection failed; start login again") `finally` complete LoginFailed
                        pure response
                      Right tokenResponse -> do
                        now <- getCurrentTime
                        let tokens = oauthTokensFromResponse now tokenResponse
                        saved <- try @SomeException (restore (saveTokens store tokens))
                        case saved of
                          Left _ -> do
                            response <- respond (page status500 "Credentials received but storage failed; return to the console") `finally` complete (SavePending tokens)
                            pure response
                          Right () -> do
                            response <- respond (page status200 "Connected") `finally` complete (Connected tokens)
                            pure response
  pure (application, takeMVar completed)

page :: Status -> B8.ByteString -> W.Response
page status message =
  W.responseLBS
    status
    [(hContentType, "text/plain; charset=utf-8"), (hCacheControl, "no-store"), ("Referrer-Policy", "no-referrer")]
    (L.fromStrict message)

-- | Bind explicitly to loopback, propagate startup errors, announce only after
-- readiness, and bracket listener lifetime. Timeout also covers exchange/save.
-- A pending initial save can be retried by the caller using the retained pair.
runLogin :: Int -> Int -> OAuthMethods -> TokenStore -> AuthorizationRequest -> IO () -> IO LoginResult
runLogin port timeoutMicros oauth store request announce = do
  path <- either (ioError . userError . T.unpack) pure (callbackPath (redirectUri request))
  (application, awaitResult) <- newLoginApplication oauth store request path
  ready <- newEmptyMVar
  stopped <- newEmptyMVar
  let settings =
        Warp.setHost "127.0.0.1" $
          Warp.setPort port $
            Warp.setBeforeMainLoop (void (tryPutMVar ready (Right ()))) $
              Warp.setOnException (\_ _ -> pure ()) Warp.defaultSettings
      start = forkFinally (Warp.runSettings settings application) $ \outcome -> do
        void (tryPutMVar ready outcome)
        putMVar stopped outcome
      stop tid = killThread tid >> takeMVar stopped >> pure ()
  bracket start stop $ \_ -> do
    takeMVar ready >>= either throwIO pure
    announce
    Timeout.timeout timeoutMicros awaitResult >>= maybe (pure LoginExpired) pure
