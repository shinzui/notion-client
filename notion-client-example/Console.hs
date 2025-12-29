-- |
-- Console output helpers for the example application.
module Console
  ( printHeader,
    logError,
    printSuccess,
    runTest,
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

-- | Print a section header
printHeader :: Text -> IO ()
printHeader title = do
  putStrLn ""
  putStrLn $ "=== " <> Text.unpack title <> " ==="
  putStrLn ""

-- | Log an error and exit
logError :: Text -> IO a
logError msg = do
  hPutStrLn stderr $ "ERROR: " <> Text.unpack msg
  exitFailure

-- | Print a success message
printSuccess :: Text -> IO ()
printSuccess msg = putStrLn $ "✓ " <> Text.unpack msg

-- | Run a test with label
runTest :: Text -> IO a -> IO a
runTest label action = do
  putStr $ Text.unpack label <> "... "
  result <- action
  printSuccess (Text.pack "Done")
  pure result
