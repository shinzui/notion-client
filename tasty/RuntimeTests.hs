-- | Tests for the client runtime: configuration, errors and retries.
module RuntimeTests (tests) where

import Data.ByteString qualified as BS
import Data.ByteString.Lazy.Char8 qualified as L8
import Data.IORef (readIORef)
import FakeNotion
import Network.HTTP.Client qualified as HTTP
import Notion.V1
import Notion.V1.Client (applyTimeout)
import Servant.Client (ClientEnv (..))
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Runtime"
    [ testGroup "Configuration" configurationTests
    ]

-- | A bot user fixture (made-up name).
userJson :: L8.ByteString
userJson =
  "{\"object\":\"user\",\"id\":\"6f1c2b9e-4d3a-4e8f-9b7c-2a1d0e5f3c4b\",\"name\":\"Sato Kenji Bot\",\"avatar_url\":null,\"type\":\"bot\",\"bot\":{\"owner\":{\"type\":\"workspace\",\"workspace\":true},\"workspace_name\":\"Sato Kenji's Workspace\"}}"

-- | Run one call against a fake that answers with the user fixture.
singleRequest :: (ClientEnv -> Methods) -> IO Recorded
singleRequest mk = do
  (env, recorded) <- fakeClientEnv [jsonReply 200 userJson]
  _ <- retrieveMyUser (mk env)
  readIORef recorded >>= \case
    [r] -> pure r
    rs -> assertFailure ("expected one request, got " <> show (length rs))

configurationTests :: [TestTree]
configurationTests =
  [ testCase "makeMethods sends default Notion-Version, Bearer token and User-Agent" $ do
      r <- singleRequest (`makeMethods` "secret_tanaka")
      lookupRecordedHeader "Authorization" r @?= Just "Bearer secret_tanaka"
      lookupRecordedHeader "Notion-Version" r @?= Just "2026-03-11"
      case lookupRecordedHeader "User-Agent" r of
        Just ua -> assertBool ("User-Agent: " <> show ua) ("notion-client-haskell/" `BS.isPrefixOf` ua)
        Nothing -> assertFailure "no User-Agent header"
      path r @?= "/users/me",
    testCase "makeMethodsWithEnv honors a configured Notion-Version" $ do
      r <- singleRequest (\env -> makeMethodsWithEnv defaultClientConfig {notionVersion = "2025-09-03"} env "secret_tanaka")
      lookupRecordedHeader "Notion-Version" r @?= Just "2025-09-03",
    testCase "applyTimeout sets responseTimeout" $ do
      -- ResponseTimeout has no Eq instance; compare its Show output.
      show (HTTP.responseTimeout (applyTimeoutFor (Just 5)))
        @?= show (HTTP.responseTimeoutMicro 5000000)
      show (HTTP.responseTimeout (applyTimeoutFor Nothing))
        @?= show HTTP.responseTimeoutDefault,
    testCase "standardHeaders match what Methods sends" $ do
      r <- singleRequest (`makeMethods` "secret_tanaka")
      (env, _) <- fakeClientEnv []
      let context = requestContextFor legacyClientConfig env "secret_tanaka"
          sent = [(n, v) | (n, v) <- headers r, n `elem` ["Authorization", "Notion-Version", "User-Agent"]]
      standardHeaders context @?= sent
      contextBaseUrl context @?= fakeBaseUrl
  ]
  where
    applyTimeoutFor t = applyTimeout defaultClientConfig {timeout = t} HTTP.defaultRequest
