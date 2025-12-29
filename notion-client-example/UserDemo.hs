-- |
-- User API demonstration.
module UserDemo
  ( runUserDemo,
  )
where

import Console (printHeader, runTest)
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import Notion.V1 (Methods (..))
import Notion.V1.ListOf (ListOf (..))

-- | Run the User API demonstration
runUserDemo :: Methods -> IO ()
runUserDemo methods = do
  printHeader (Text.pack "User API")

  user <-
    runTest (Text.pack "Retrieving current user information") $
      retrieveMyUser methods
  putStrLn $ "User info: " <> show user

  -- List all users
  users <-
    runTest (Text.pack "Listing users") $
      listUsers methods Nothing Nothing
  let List {results = userResults} = users
  putStrLn $ "User count: " <> show (Vector.length userResults)
