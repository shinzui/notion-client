-- |
-- File Uploads API demonstration.
--
-- Shows how to:
-- - Create a single-part file upload
-- - Send file content
-- - Retrieve file upload status
-- - List file uploads
module FileUploadDemo
  ( runFileUploadDemo,
  )
where

import Console (printHeader, runTest)
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import Notion.V1 (Methods (..))
import Notion.V1.FileUploads (FileUploadObject (..), FileUploadStatus (..), mkSendFileUpload, mkSinglePartUpload)
import Notion.V1.ListOf (ListOf (..))
import Prelude hiding (id)

-- | Run the File Upload API demonstration
runFileUploadDemo :: Methods -> FilePath -> IO ()
runFileUploadDemo methods testFilePath = do
  printHeader (Text.pack "File Uploads API")

  -- ---------------------------------------------------------------
  -- Part 1: Create a single-part file upload
  -- ---------------------------------------------------------------
  upload <-
    runTest (Text.pack "Creating single-part file upload") $
      createFileUpload methods (mkSinglePartUpload (Just "test-upload.txt"))

  putStrLn $ "  Upload ID: " <> show (id upload)
  putStrLn $ "  Status: " <> show (status upload)

  -- ---------------------------------------------------------------
  -- Part 2: Send file content
  -- ---------------------------------------------------------------
  updated <-
    runTest (Text.pack "Sending file content") $
      sendFileUploadContent methods (id upload) (mkSendFileUpload testFilePath "test-upload.txt" "text/plain")

  putStrLn $ "  Status after send: " <> show (status updated)

  -- ---------------------------------------------------------------
  -- Part 3: Retrieve file upload
  -- ---------------------------------------------------------------
  retrieved <-
    runTest (Text.pack "Retrieving file upload") $
      retrieveFileUpload methods (id upload)

  putStrLn $ "  Status: " <> show (status retrieved)
  putStrLn $ "  Filename: " <> show (filename retrieved)
  putStrLn $ "  Content type: " <> show (contentType retrieved)

  -- ---------------------------------------------------------------
  -- Part 4: List file uploads
  -- ---------------------------------------------------------------
  result <-
    runTest (Text.pack "Listing file uploads (uploaded)") $
      listFileUploads methods (Just Uploaded) Nothing (Just 5)

  let List {results = uploads} = result
  putStrLn $ "  Found " <> show (Vector.length uploads) <> " uploaded file(s)"
  Vector.forM_ uploads $ \fu ->
    putStrLn $ "    - " <> show (id fu) <> " (" <> show (filename fu) <> ")"
