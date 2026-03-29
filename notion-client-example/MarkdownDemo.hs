-- |
-- Markdown Content API demonstration.
--
-- Shows how to:
-- - Create a page with markdown content instead of block JSON
-- - Retrieve page content as markdown
-- - Edit content with targeted search-and-replace (update_content)
-- - Replace entire page content (replace_content)
-- - Move a page to a different parent
module MarkdownDemo
  ( runMarkdownDemo,
  )
where

import Console (printHeader, printSuccess, runTest)
import Data.Aeson qualified as Aeson
import Data.Map (fromList)
import Data.String (fromString)
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import Notion.V1 (Methods (..))
import Notion.V1.Common (Parent (..), UUID (..))
import Notion.V1.Pages
import Prelude hiding (id)

-- | Run the Markdown API demonstration
runMarkdownDemo :: Methods -> String -> IO ()
runMarkdownDemo methods pageIdStr = do
  let parentPageId = fromString pageIdStr

  -- ---------------------------------------------------------------
  -- Part 1: Create a page with markdown content
  -- ---------------------------------------------------------------
  printHeader (Text.pack "Markdown: Create Page with Markdown")

  let titleProp = mkTitleProp "Markdown Demo Page"
      props = fromList [("title", PropertyValue {type_ = Title, value = Just titleProp})]

      -- Use 'markdown' instead of 'children' to set initial content.
      -- This is much simpler than constructing block JSON manually.
      createReq =
        CreatePage
          { parent = PageParent {pageId = parentPageId},
            properties = props,
            children = Nothing,
            markdown = Just markdownContent,
            icon = Nothing,
            cover = Nothing,
            template = Nothing,
            position = Nothing
          }

  page <-
    runTest (Text.pack "Creating page with markdown content") $
      createPage methods createReq

  let PageObject {id = newPageId, url = pageUrl} = page
  putStrLn $ "Page created: " <> Text.unpack pageUrl

  -- ---------------------------------------------------------------
  -- Part 2: Retrieve page content as markdown
  -- ---------------------------------------------------------------
  printHeader (Text.pack "Markdown: Retrieve Page as Markdown")

  md <-
    runTest (Text.pack "Retrieving page as markdown") $
      retrievePageMarkdown methods newPageId Nothing

  let PageMarkdown {markdown = mdText, truncated = isTruncated} = md
  putStrLn $ "Truncated: " <> show isTruncated
  putStrLn "Content:"
  putStrLn $ Text.unpack mdText

  -- ---------------------------------------------------------------
  -- Part 3: Replace entire page content
  -- ---------------------------------------------------------------
  printHeader (Text.pack "Markdown: Replace Content")

  let replaceReq =
        ReplaceContent
          ReplaceContentRequest
            { newStr = replacementContent,
              allowDeletingContent = Just True
            }

  mdAfterReplace <-
    runTest (Text.pack "Replacing entire page content") $
      updatePageMarkdown methods newPageId replaceReq

  let PageMarkdown {markdown = replacedText} = mdAfterReplace
  putStrLn "New content:"
  putStrLn $ Text.unpack replacedText

  -- ---------------------------------------------------------------
  -- Part 4: Targeted search-and-replace edit
  -- ---------------------------------------------------------------
  printHeader (Text.pack "Markdown: Search-and-Replace Edit")

  let editReq =
        UpdateContent
          UpdateContentRequest
            { contentUpdates =
                Vector.fromList
                  [ ContentUpdate
                      { oldStr = "World",
                        newStr = "Notion API",
                        replaceAllMatches = Nothing
                      },
                    ContentUpdate
                      { oldStr = "will be edited",
                        newStr = "was edited successfully",
                        replaceAllMatches = Nothing
                      }
                  ],
              allowDeletingContent = Nothing
            }

  mdAfterEdit <-
    runTest (Text.pack "Applying search-and-replace edits") $
      updatePageMarkdown methods newPageId editReq

  let PageMarkdown {markdown = editedText} = mdAfterEdit
  putStrLn "Content after edits:"
  putStrLn $ Text.unpack editedText

  -- ---------------------------------------------------------------
  -- Part 5: Retrieve with include_transcript
  -- ---------------------------------------------------------------
  printHeader (Text.pack "Markdown: Retrieve with Transcript")

  mdWithTranscript <-
    runTest (Text.pack "Retrieving markdown (include_transcript=True)") $
      retrievePageMarkdown methods newPageId (Just True)

  let PageMarkdown {markdown = transcriptText} = mdWithTranscript
  putStrLn $ "Content length: " <> show (Text.length transcriptText) <> " chars"

  -- ---------------------------------------------------------------
  -- Part 6: Move page to a different parent
  -- ---------------------------------------------------------------
  printHeader (Text.pack "Move Page API")

  -- Create a target page to move into
  let targetProps = fromList [("title", PropertyValue {type_ = Title, value = Just (mkTitleProp "Move Target")})]
      targetReq = mkCreatePage (PageParent {pageId = parentPageId}) targetProps
  targetPage <-
    runTest (Text.pack "Creating target parent page") $
      createPage methods targetReq
  let PageObject {id = targetId} = targetPage

  -- Move the demo page under the target
  let moveReq = MovePage {parent = PageParent {pageId = targetId}, position = Nothing}
  _movedPage <-
    runTest (Text.pack "Moving page to new parent") $
      movePage methods newPageId moveReq

  -- Verify the parent changed
  verifiedPage <-
    runTest (Text.pack "Verifying page parent changed") $
      retrievePage methods newPageId
  let PageObject {parent = newParent} = verifiedPage
  case newParent of
    PageParent {pageId = actualParent} ->
      putStrLn $ "New parent: " <> show actualParent
    other ->
      putStrLn $ "Unexpected parent type: " <> show other

  -- Move it back to the original parent
  let moveBackReq = MovePage {parent = PageParent {pageId = parentPageId}, position = Nothing}
  _ <-
    runTest (Text.pack "Moving page back to original parent") $
      movePage methods newPageId moveBackReq

  -- Clean up target page
  let trashReq =
        UpdatePage
          { properties = fromList [],
            inTrash = Just True,
            icon = Nothing,
            cover = Nothing,
            template = Nothing,
            eraseContent = Nothing
          }
  _ <- updatePage methods targetId trashReq
  printSuccess (Text.pack "Target page trashed")

  putStrLn ""
  putStrLn $ "Demo page still available at: " <> Text.unpack pageUrl

-- | Markdown content for initial page creation
markdownContent :: Text.Text
markdownContent =
  "# Hello, World!\n\
  \\n\
  \This page was created entirely using **markdown** instead of block JSON.\n\
  \\n\
  \## Features\n\
  \\n\
  \- Bold text: **like this**\n\
  \- Italic text: *like this*\n\
  \- Code: `inline code`\n\
  \\n\
  \> This is a blockquote created from markdown.\n\
  \\n\
  \```python\n\
  \def hello():\n\
  \    print(\"Hello from markdown!\")\n\
  \```\n\
  \\n\
  \This paragraph will be edited later via the API."

-- | Replacement content for the replace_content demo
replacementContent :: Text.Text
replacementContent =
  "# Hello, World!\n\
  \\n\
  \This content was set using **replace_content**.\n\
  \\n\
  \The entire page was replaced in a single API call.\n\
  \\n\
  \This paragraph will be edited via **update_content** next."

-- | Helper to create a title property value
mkTitleProp :: Text.Text -> Aeson.Value
mkTitleProp t =
  let textObj = Aeson.object [("content", Aeson.String t)]
      textItem = Aeson.object [("text", textObj)]
      titleArray = Aeson.Array (Vector.singleton textItem)
   in Aeson.object [("title", titleArray)]
