-- | Tests for the OAuth endpoints.
module OAuthTests (tests, tokenJson, personOwner, credentials) where

import Control.Exception (SomeException, displayException, fromException, throwIO, try)
import Control.Monad (forM_)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy.Char8 qualified as L8
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (isInfixOf)
import FakeNotion
import Notion.V1 (defaultClientConfig)
import Notion.V1.Client (ClientConfig (..), LogLevel (..))
import Notion.V1.Error qualified as E
import Notion.V1.OAuth
import Servant.Client (ClientEnv (..))
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "OAuth"
    ( errorTests
        <> [ testCase "basicAuthorization encodes client_id:client_secret" $
               basicAuthorization credentials @?= "Basic Y2xpZW50OnNlY3JldA==",
             testCase "authorization_code request encodes" $ do
               let grant = AuthorizationCodeGrant "code-123" (Just "https://example.com/callback") Nothing
               Aeson.toJSON (AuthorizationCode grant)
                 @?= Aeson.object
                   [ "grant_type" Aeson..= ("authorization_code" :: String),
                     "code" Aeson..= ("code-123" :: String),
                     "redirect_uri" Aeson..= ("https://example.com/callback" :: String)
                   ]
               Aeson.toJSON (AuthorizationCode grant {externalAccount = Just (ExternalAccount "acct-1" "Tanaka Hanako")})
                 @?= Aeson.object
                   [ "grant_type" Aeson..= ("authorization_code" :: String),
                     "code" Aeson..= ("code-123" :: String),
                     "redirect_uri" Aeson..= ("https://example.com/callback" :: String),
                     "external_account" Aeson..= Aeson.object ["key" Aeson..= ("acct-1" :: String), "name" Aeson..= ("Tanaka Hanako" :: String)]
                   ],
             testCase "refresh_token request encodes" $
               Aeson.toJSON (RefreshToken "nrt_abc")
                 @?= Aeson.object ["grant_type" Aeson..= ("refresh_token" :: String), "refresh_token" Aeson..= ("nrt_abc" :: String)],
             testCase "token response with person owner decodes" $ do
               OAuthTokenResponse {owner, refreshToken} <- decodeOrFail (tokenJson personOwner)
               refreshToken @?= Just "nrt_tanaka_refresh"
               case owner of
                 OAuthUserOwner OAuthOwnerUser {email, name} -> do
                   email @?= Just "hanako@example.com"
                   name @?= Just "Tanaka Hanako"
                 other -> assertFailure ("expected a user owner, got " <> show other),
             testCase "partial user owner and workspace owner decode" $ do
               OAuthTokenResponse {owner = partial} <-
                 decodeOrFail (tokenJson "{\"type\":\"user\",\"user\":{\"id\":\"0e1d2c3b-4a59-4687-b7a6-958473625140\",\"object\":\"user\"}}")
               case partial of
                 OAuthUserOwner OAuthOwnerUser {email, type_} -> do
                   email @?= Nothing
                   type_ @?= Nothing
                 other -> assertFailure ("expected a user owner, got " <> show other)
               OAuthTokenResponse {owner = workspace} <- decodeOrFail (tokenJson "{\"type\":\"workspace\",\"workspace\":true}")
               workspace @?= OAuthWorkspaceOwner
               OAuthTokenResponse {owner = team} <- decodeOrFail (tokenJson "{\"type\":\"team\"}")
               case team of
                 UnknownOAuthOwner _ -> pure ()
                 other -> assertFailure ("expected UnknownOAuthOwner, got " <> show other),
             testCase "introspect response decodes" $ do
               r1 <- decodeOrFail "{\"active\":true,\"scope\":\"read_content\",\"iat\":1757890000,\"request_id\":\"r-1\"}"
               r1 @?= OAuthIntrospectResponse True (Just "read_content") (Just 1757890000) (Just "r-1")
               r2 <- decodeOrFail "{\"active\":false}"
               r2 @?= OAuthIntrospectResponse False Nothing Nothing Nothing,
             testCase "createOAuthToken sends Basic auth to POST /oauth/token" $ do
               (env, recorded) <- fakeClientEnv [jsonReply 200 (tokenJson personOwner)]
               let oauth = makeOAuthMethodsWith defaultClientConfig env credentials
               _ <- createOAuthToken oauth (RefreshToken "nrt_tanaka_refresh")
               readIORef recorded >>= \case
                 [r@Recorded {method, path}] -> do
                   method @?= "POST"
                   path @?= "/oauth/token"
                   lookupRecordedHeader "Authorization" r @?= Just "Basic Y2xpZW50OnNlY3JldA=="
                   length [() | ("Authorization", _) <- headers r] @?= 1
                 rs -> assertFailure ("expected one request, got " <> show (length rs))
           ]
    )

credentials :: OAuthCredentials
credentials = OAuthCredentials {clientId = "client", clientSecret = "secret"}

decodeOrFail :: (Aeson.FromJSON a) => L8.ByteString -> IO a
decodeOrFail bytes = either (assertFailure . ("decode failed: " <>)) pure (Aeson.eitherDecode bytes)

personOwner :: L8.ByteString
personOwner =
  "{\"type\":\"user\",\"user\":{\"type\":\"person\",\"person\":{\"email\":\"hanako@example.com\"},\"name\":\"Tanaka Hanako\",\"avatar_url\":null,\"id\":\"0e1d2c3b-4a59-4687-b7a6-958473625140\",\"object\":\"user\"}}"

tokenJson :: L8.ByteString -> L8.ByteString
tokenJson owner =
  "{\"access_token\":\"secret_tanaka_access\",\"token_type\":\"bearer\",\"refresh_token\":\"nrt_tanaka_refresh\",\"bot_id\":\"2f8e6d4c-1b3a-4c5d-8e7f-9a0b1c2d3e4f\",\"workspace_icon\":null,\"workspace_name\":\"Tanaka Hanako's Workspace\",\"workspace_id\":\"7a6b5c4d-3e2f-4a1b-9c8d-7e6f5a4b3c2d\",\"owner\":"
    <> owner
    <> ",\"duplicated_template_id\":null,\"request_id\":\"5d4c3b2a-1f0e-4d9c-8b7a-6f5e4d3c2b1a\"}"

errorTests :: [TestTree]
errorTests =
  [ testCase "OAuth timeout propagates with one attempt" $ do
      (env, _) <- fakeClientEnv []
      calls <- newIORef (0 :: Int)
      let failing = env {middleware = \_ _ -> liftIO (modifyIORef' calls (+ 1) >> throwIO E.RequestTimeoutError)}
      result <- try @E.RequestTimeoutError (createOAuthToken (makeOAuthMethodsWith defaultClientConfig failing credentials) (RefreshToken "secret"))
      assertBool "timeout" (either (const True) (const False) result)
      readIORef calls >>= (@?= 1),
    testCase "OAuth errors retain metadata and redact secrets" $ do
      (env, recorded) <- fakeClientEnv [FakeReply 400 [("Content-Type", "application/json"), ("x-notion-request-id", "r-oauth-2"), ("Secret", "SENTINEL")] "{\"error\":\"invalid_grant\",\"error_description\":\"SENTINEL\"}"]
      logs <- newIORef []
      let config = defaultClientConfig {logger = Just (\_ msg fields -> modifyIORef' logs (<> [show (msg, fields)])), logLevel = LogDebug}
      r <- try @OAuthError (createOAuthToken (makeOAuthMethodsWith config env credentials) (RefreshToken "SENTINEL"))
      case r of
        Left e@OAuthError {oauthErrorCode, errorDescription, requestId, response} -> do
          oauthErrorCode @?= OAuthInvalidGrant
          errorDescription @?= Just "SENTINEL"
          requestId @?= Just "r-oauth-2"
          fmap E.httpStatus response @?= Just 400
          assertBool "show redacted" (not ("SENTINEL" `isInfixOf` (show e <> displayException e)))
        Right _ -> assertFailure "expected OAuthError"
      readIORef logs >>= assertBool "debug logs redacted" . all (not . isInfixOf "SENTINEL")
      length <$> readIORef recorded >>= (@?= 1),
    testCase "OAuth and documented Notion envelopes normalize locally" $ do
      forM_
        [ ("{\"error\":\"invalid_client\",\"request_id\":\"body-id\"}", OAuthInvalidClient),
          ("{\"object\":\"error\",\"code\":\"invalid_grant\",\"message\":\"bad\"}", OAuthInvalidGrant),
          ("{\"error\":\"slow_down\"}", UnknownOAuthErrorCode "slow_down")
        ]
        $ \(body, expected) -> do
          (env, _) <- fakeClientEnv [jsonReply 401 body]
          result <- try @OAuthError (revokeOAuthToken (makeOAuthMethodsWith defaultClientConfig env credentials) "token")
          case result of
            Left OAuthError {oauthErrorCode, response} -> do
              oauthErrorCode @?= expected
              fmap E.httpStatus response @?= Just 401
            Right _ -> assertFailure "expected OAuthError",
    testCase "ordinary and malformed errors retain original exception" $ do
      forM_ ["validation_error", "brand_new_code"] $ \c -> do
        (env, _) <- fakeClientEnv [jsonReply 400 ("{\"object\":\"error\",\"code\":\"" <> c <> "\",\"message\":\"bad\"}")]
        result <- try @E.NotionError (revokeOAuthToken (makeOAuthMethodsWith defaultClientConfig env credentials) "token")
        assertBool "NotionError" (either (const True) (const False) result)
      forM_ ["oops", "{\"error\":\"\"}", "{\"error\":17}", "{}"] $ \body -> do
        (env, _) <- fakeClientEnv [jsonReply 502 body]
        r <- try @E.UnknownHTTPResponseError (introspectOAuthToken (makeOAuthMethodsWith defaultClientConfig env credentials) "token")
        assertBool "UnknownHTTPResponseError" (either (const True) (const False) r),
    testCase "OAuth never retries grants revoke or introspect" $ do
      forM_ ["rate_limited", "service_overload"] $ \code ->
        forM_
          [ \o -> () <$ createOAuthToken o (AuthorizationCode (AuthorizationCodeGrant "c" Nothing Nothing)),
            \o -> () <$ createOAuthToken o (RefreshToken "r"),
            \o -> () <$ revokeOAuthToken o "t",
            \o -> () <$ introspectOAuthToken o "t"
          ]
          $ \call -> do
            (env, recorded) <- fakeClientEnv [jsonReply 429 ("{\"object\":\"error\",\"code\":\"" <> code <> "\",\"message\":\"bad\"}")]
            r <- try @SomeException (call (makeOAuthMethodsWith defaultClientConfig env credentials))
            assertBool "original NotionError" (either (maybe False (const True) . fromException @E.NotionError) (const False) r)
            length <$> readIORef recorded >>= (@?= 1),
    testCase "all known codes and JSON roundtrip" $
      forM_ [OAuthInvalidRequest, OAuthInvalidClient, OAuthInvalidGrant, OAuthUnauthorizedClient, OAuthUnsupportedGrantType, OAuthInvalidScope, OAuthAccessDenied, OAuthUnsupportedResponseType, OAuthServerError, OAuthTemporarilyUnavailable, UnknownOAuthErrorCode "future"] $ \c -> do
        parseOAuthErrorCode (oauthErrorCodeText c) @?= c
        Aeson.decode (Aeson.encode c) @?= Just c
  ]
