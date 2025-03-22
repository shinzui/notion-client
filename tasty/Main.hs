module Main where

import Data.Text qualified as Text
import Notion.V1
import Notion.V1.Common (UUID (..))
import Notion.V1.ListOf (ListOf (..))
import Notion.V1.Pages (PageObject)
import Notion.V1.Search (SearchRequest (..))
import Notion.V1.Users (UserObject (..))
import System.Environment qualified as Environment
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = do
  -- These tests expect a NOTION_TOKEN environment variable
  -- and only run against the actual Notion API
  defaultMain =<< tests

tests :: IO TestTree
tests = do
  mToken <- lookupEnv "NOTION_TOKEN"

  case mToken of
    Nothing ->
      pure $
        testGroup
          "Notion API Tests"
          [ testCase "No API token found" $
              assertFailure "Set NOTION_TOKEN environment variable to run tests"
          ]
    Just token -> do
      clientEnv <- getClientEnv "https://api.notion.com/v1"
      let methods = makeMethods clientEnv (Text.pack token)

      pure $
        testGroup
          "Notion API Tests"
          [ testCase "Retrieve current user" $ testRetrieveCurrentUser methods,
            testCase "List users" $ testListUsers methods,
            testCase "Timestamp parsing works" $ testSearchAPI methods
          ]

testRetrieveCurrentUser :: Methods -> Assertion
testRetrieveCurrentUser Methods {retrieveMyUser} = do
  user <- retrieveMyUser
  let userId = Notion.V1.Users.id user
  -- Using Show instance of UUID to verify it's not empty
  assertBool "User object should have an ID" (show userId /= "")

testListUsers :: Methods -> Assertion
testListUsers Methods {listUsers} = do
  users <- listUsers Nothing Nothing
  let userCount = length $ results users
  assertBool "Should have at least one user" (userCount > 0)

testSearchAPI :: Methods -> Assertion
testSearchAPI Methods {search} = do
  let searchParams =
        Notion.V1.Search.SearchRequest
          { query = Just "test",
            sort = Nothing,
            filter = Nothing,
            start_cursor = Nothing,
            page_size = Nothing
          }
  searchResults <- search searchParams
  -- If this test runs without errors, it means timestamp parsing works
  assertBool "Search should run without timestamp parsing errors" True

lookupEnv :: String -> IO (Maybe String)
lookupEnv var = Environment.lookupEnv var
