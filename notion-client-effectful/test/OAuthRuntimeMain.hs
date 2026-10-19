{-# LANGUAGE GHC2024 #-}
{-# LANGUAGE AllowAmbiguousTypes #-}

module Main (main) where

import Control.Exception
import Control.Monad (void)
import Data.Aeson qualified as A
import Data.Time.Clock
import Effectful (runEff)
import Effectful.Error.Static (runErrorNoCallStack)
import FakeNotion
import Notion.V1
import Notion.V1.Effectful qualified as E
import Notion.V1.Error
import Notion.V1.OAuth qualified as O
import Notion.V1.OAuth.Refresh qualified as R
import OAuthTests (personOwner, tokenJson)
import Test.Tasty
import Test.Tasty.HUnit
import TokenSourceTests (unauthorized, userJson)

main :: IO ()
main =
  defaultMain $
    testGroup
      "Effectful OAuth"
      [ testCase "refreshing Methods succeeds and final API error uses Error effect" $ do
          (old, response) <- fixture
          store <- R.inMemoryTokenStore old
          manager <- R.newOAuthTokenManager (oauth (pure response)) store
          (env, _) <- fakeClientEnv [unauthorized, jsonReply 200 userJson, unauthorized, unauthorized]
          let api = makeMethodsWithTokenSource defaultClientConfig env (R.tokenManagerSource manager)
              call = runEff . runErrorNoCallStack @NotionError . E.runNotion api $ E.retrieveMyUser
          call >>= either (assertFailure . show) (const (pure ()))
          call >>= either (\e -> code e @?= Unauthorized) (const (assertFailure "expected final API error")),
        testCase "reauthorization stays an IO exception" $ do
          (old, response) <- fixture
          store <- R.inMemoryTokenStore old {R.refreshToken = Nothing}
          manager <- R.newOAuthTokenManager (oauth (pure response)) store
          expect @R.ReauthorizationRequired (run manager),
        testCase "pending persistence stays an IO exception" $ do
          (old, response) <- fixture
          manager <- R.newOAuthTokenManager (oauth (pure response)) (R.TokenStore (pure old) (\_ -> ioError (userError "storage")))
          expect @R.TokenPersistenceError (R.refreshTokensNow manager)
          expect @R.TokenPersistenceError (run manager),
        testCase "uncertain refresh stays an IO exception" $ do
          (old, _) <- fixture
          store <- R.inMemoryTokenStore old
          manager <- R.newOAuthTokenManager (oauth (ioError (userError "lost response"))) store
          expect @IOException (R.refreshTokensNow manager)
          expect @R.RefreshOutcomeUnknown (run manager)
      ]

expect :: forall e a. (Exception e) => IO a -> IO ()
expect action = try @e action >>= either (const (pure ())) (const (assertFailure "expected IO exception"))

run :: R.OAuthTokenManager -> IO ()
run manager = do
  (env, _) <- fakeClientEnv [unauthorized]
  let api = makeMethodsWithTokenSource defaultClientConfig env (R.tokenManagerSource manager)
  void $ runEff . runErrorNoCallStack @NotionError . E.runNotion api $ E.retrieveMyUser

oauth :: IO O.OAuthTokenResponse -> O.OAuthMethods
oauth action = O.OAuthMethods (const action) (const (pure (O.OAuthRevokeResponse Nothing))) (const (pure (O.OAuthIntrospectResponse False Nothing Nothing Nothing)))

fixture :: IO (R.OAuthTokens, O.OAuthTokenResponse)
fixture = do
  response <- either assertFailure pure (A.eitherDecode (tokenJson personOwner))
  now <- getCurrentTime
  pure ((R.oauthTokensFromResponse now response) {R.accessToken = "old", R.refreshToken = Just "old-refresh"}, response)
