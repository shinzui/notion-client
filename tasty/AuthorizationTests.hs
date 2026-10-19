module AuthorizationTests (tests) where

import Data.Aeson qualified as A
import Data.ByteString qualified as BS
import Data.IORef (readIORef)
import Data.Text qualified as T
import FakeNotion
import Network.HTTP.Types.URI (parseQuery)
import Notion.V1 (defaultClientConfig)
import Notion.V1.OAuth
import Notion.V1.OAuth.Authorization
import OAuthTests (credentials, personOwner, tokenJson)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Authorization"
    [ testCase "authorization URL is exact" $
        authorizationUrl req @?= "https://api.notion.com/v1/oauth/authorize?client_id=client&response_type=code&owner=user&redirect_uri=http%3A%2F%2Flocalhost%3A8765%2Fcallback&state=s-123",
      testCase "secure state is 43 URL-safe characters and rendering redacts" $ do
        a <- newOAuthState
        b <- newOAuthState
        T.length (oauthStateText a) @?= 43
        assertBool "URL safe" (T.all (`elem` (['A' .. 'Z'] <> ['a' .. 'z'] <> ['0' .. '9'] <> "-_")) (oauthStateText a))
        assertBool "fresh" (not (sameOAuthState a b))
        show a @?= "OAuthState <redacted>"
        show (OAuthCode "secret") @?= "OAuthCode <redacted>"
        show (AuthorizationDenied (UnknownOAuthErrorCode "SECRET") (Just "SECRET")) @?= "AuthorizationDenied <unknown code>",
      testCase "constant-time primitive rejects differing bytes and lengths" $ do
        assertBool "equal" (sameOAuthState (OAuthState "aa") (OAuthState "aa"))
        mapM_ (\s -> assertBool "different" (not (sameOAuthState (OAuthState "aa") (OAuthState s)))) ["ab", "a", "bb"],
      testCase "callback success and one decoding pass" $ do
        verify "?code=c-1&state=s-123" @?= Right (OAuthCode "c-1")
        verify "?code=a%2Bb&state=s-123&unknown=x" @?= Right (OAuthCode "a+b"),
      testCase "denial requires state and preserves unknown codes" $ do
        verify "?error=access_denied&state=s-123" @?= Left (AuthorizationDenied OAuthAccessDenied Nothing)
        verify "?error=access_denied&state=s-123&error_description=User%20cancelled" @?= Left (AuthorizationDenied OAuthAccessDenied (Just "User cancelled"))
        verify "?error=slow_down&state=s-123" @?= Left (AuthorizationDenied (UnknownOAuthErrorCode "slow_down") Nothing)
        mapM_ (\q -> verify q @?= Left StateMismatch) ["?error=access_denied", "?error=access_denied&state=other", "?code=c-1", "?code=c-1&state=other"]
        verifyAuthorizationCallback (OAuthState "") (parseQuery "?code=c&state=") @?= Left StateMismatch,
      testCase "missing and empty code" $
        mapM_ (\q -> verify q @?= Left MissingCode) ["?state=s-123", "?code=&state=s-123"],
      testCase "malformed ambiguous callbacks rejected" $
        mapM_
          (\q -> verify q @?= Left MalformedCallback)
          [ "?code=a&code=a&state=s-123",
            "?state=s-123&state=s-123",
            "?error=x&error=x&state=s-123",
            "?code=c&error=x&state=s-123",
            "?code&state=s-123",
            "?state=s-123&error=",
            "?state=s-123&error_uri",
            "?state=s-123&code=%FF",
            "?state=s-123&error_description=%FF",
            "?state=s-123&error_uri=x&error_uri=x"
          ],
      testCase "code exchange includes redirect URI and Basic authentication" $ do
        A.toJSON (authorizationCodeGrant req (OAuthCode "c-1"))
          @?= A.object
            ["grant_type" A..= ("authorization_code" :: T.Text), "code" A..= ("c-1" :: T.Text), "redirect_uri" A..= ("http://localhost:8765/callback" :: T.Text)]
        (env, recorded) <- fakeClientEnv [jsonReply 200 (tokenJson personOwner)]
        _ <- exchangeAuthorizationCode (makeOAuthMethodsWith defaultClientConfig env credentials) req (OAuthCode "c-1")
        rs <- readIORef recorded
        map method rs @?= ["POST"]
        map path rs @?= ["/oauth/token"]
        map (lookupRecordedHeader "Authorization") rs @?= [Just "Basic Y2xpZW50OnNlY3JldA=="]
    ]
  where
    verify :: BS.ByteString -> Either AuthorizationCallbackError OAuthCode
    verify = verifyAuthorizationCallback (OAuthState "s-123") . parseQuery
    req = AuthorizationRequest "client" "http://localhost:8765/callback" (OAuthState "s-123")
