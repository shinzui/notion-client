-- | Protocol helpers for confidential-client OAuth login. The application must
-- bind each request to its initiating session, expire it, and atomically consume
-- it once on verified success or denial, before exchanging the code. This pure
-- verifier does not provide session storage, expiry or replay protection.
module Notion.V1.OAuth.Authorization
  ( OAuthState (..),
    newOAuthState,
    sameOAuthState,
    AuthorizationRequest (..),
    authorizationUrl,
    authorizationUrlWith,
    OAuthCode (..),
    AuthorizationCallbackError (..),
    verifyAuthorizationCallback,
    authorizationCodeGrant,
    exchangeAuthorizationCode,
  )
where

import Control.Exception (Exception)
import Control.Monad (forM, when)
import Data.ByteArray (constEq)
import Data.ByteString.Base64.URL qualified as Base64
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as T
import Network.HTTP.Types.URI (Query, renderQuery)
import Notion.V1.Client (defaultBaseUrl)
import Notion.V1.OAuth (AuthorizationCodeGrant (..), OAuthErrorCode (..), OAuthMethods (..), OAuthTokenRequest (..), OAuthTokenResponse, parseOAuthErrorCode)
import Servant.Client (BaseUrl, showBaseUrl)
import System.Entropy (getEntropy)

-- | Serialize explicitly with 'oauthStateText'; default rendering is redacted.
newtype OAuthState = OAuthState {oauthStateText :: Text}

instance Show OAuthState where show _ = "OAuthState <redacted>"

-- | 32 bytes of operating-system entropy, encoded as 43 URL-safe characters.
newOAuthState :: IO OAuthState
newOAuthState = OAuthState . T.decodeUtf8 . Base64.encodeUnpadded <$> getEntropy 32

-- | Constant-time byte comparison for equal-length values.
sameOAuthState :: OAuthState -> OAuthState -> Bool
sameOAuthState (OAuthState a) (OAuthState b) = constEq (T.encodeUtf8 a) (T.encodeUtf8 b)

data AuthorizationRequest = AuthorizationRequest
  {clientId :: Text, redirectUri :: Text, state :: OAuthState}

-- | Build the consent URL. The redirect URI must exactly match registration.
authorizationUrl :: AuthorizationRequest -> Text
authorizationUrl = authorizationUrlWith defaultBaseUrl

authorizationUrlWith :: BaseUrl -> AuthorizationRequest -> Text
authorizationUrlWith base AuthorizationRequest {clientId, redirectUri, state} =
  T.pack (showBaseUrl base)
    <> "/oauth/authorize"
    <> T.decodeUtf8
      ( renderQuery
          True
          [ ("client_id", Just (T.encodeUtf8 clientId)),
            ("response_type", Just "code"),
            ("owner", Just "user"),
            ("redirect_uri", Just (T.encodeUtf8 redirectUri)),
            ("state", Just (T.encodeUtf8 (oauthStateText state)))
          ]
      )

-- | A convenience wrapper, not proof that a caller verified the callback.
newtype OAuthCode = OAuthCode {oauthCodeText :: Text} deriving stock (Eq)

instance Show OAuthCode where show _ = "OAuthCode <redacted>"

data AuthorizationCallbackError
  = AuthorizationDenied OAuthErrorCode (Maybe Text)
  | StateMismatch
  | MissingCode
  | MalformedCallback
  deriving stock (Eq)

instance Show AuthorizationCallbackError where
  show (AuthorizationDenied code _) =
    "AuthorizationDenied " <> case code of
      UnknownOAuthErrorCode _ -> "<unknown code>"
      _ -> show code
  show StateMismatch = "StateMismatch"
  show MissingCode = "MissingCode"
  show MalformedCallback = "MalformedCallback"

instance Exception AuthorizationCallbackError

-- | Input values are already percent-decoded by WAI or parseQuery. Unknown
-- fields are ignored. Descriptions are untrusted display data.
verifyAuthorizationCallback :: OAuthState -> Query -> Either AuthorizationCallbackError OAuthCode
verifyAuthorizationCallback expected query = do
  fields <- forM ["state", "code", "error", "error_description", "error_uri"] $ \key -> do
    value <- case [v | (k, v) <- query, k == key] of
      [] -> Right Nothing
      [Just bytes] -> either (const (Left MalformedCallback)) (Right . Just) (T.decodeUtf8' bytes)
      _ -> Left MalformedCallback
    pure (key, value)
  let get key = lookup key fields >>= id
      returnedState = get "state"
      code = get "code"
      err = get "error"
  when (code /= Nothing && err /= Nothing) (Left MalformedCallback)
  case returnedState of
    Just s | not (T.null s), not (T.null (oauthStateText expected)), sameOAuthState expected (OAuthState s) -> pure ()
    _ -> Left StateMismatch
  case err of
    Just "" -> Left MalformedCallback
    Just e -> Left (AuthorizationDenied (parseOAuthErrorCode e) (get "error_description"))
    Nothing -> case code of
      Just c | not (T.null c) -> Right (OAuthCode c)
      _ -> Left MissingCode

-- | Sends the exact redirect URI from the initiating request.
authorizationCodeGrant :: AuthorizationRequest -> OAuthCode -> OAuthTokenRequest
authorizationCodeGrant AuthorizationRequest {redirectUri} (OAuthCode code) =
  AuthorizationCode AuthorizationCodeGrant {code, redirectUri = Just redirectUri, externalAccount = Nothing}

exchangeAuthorizationCode :: OAuthMethods -> AuthorizationRequest -> OAuthCode -> IO OAuthTokenResponse
exchangeAuthorizationCode oauth req = createOAuthToken oauth . authorizationCodeGrant req
