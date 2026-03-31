-- |
-- Data Source Templates API demonstration.
--
-- Shows how to:
-- - List templates available for a data source
-- - Filter templates by name
-- - Create a page using a template
module TemplateDemo
  ( runTemplateDemo,
  )
where

import Console (printHeader, runTest)
import Data.Map (fromList)
import Data.String (fromString)
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import Notion.V1 (Methods (..))
import Notion.V1.Common (Parent (..))
import Notion.V1.DataSources (ListTemplatesResponse (..), TemplateRef (..))
import Notion.V1.Databases (DataSource (..), DatabaseObject (..))
import Notion.V1.Pages (CreatePage (..), PageObject (..), Template (..), UpdatePage (..))
import Notion.V1.PropertyValue qualified as PV
import Notion.V1.RichText (RichText (..), RichTextContent (..), TextContent (..), defaultAnnotations)
import Prelude hiding (id)

-- | Run the Template API demonstration
runTemplateDemo :: Methods -> String -> IO ()
runTemplateDemo methods databaseIdStr = do
  let databaseId = fromString databaseIdStr

  -- Get the first data source from the database
  printHeader (Text.pack "Data Source Templates API")

  database <-
    runTest (Text.pack "Retrieving database") $
      retrieveDatabase methods databaseId
  let DatabaseObject {dataSources = dsList} = database
      DataSource {id = dsId, name = dsName} = Vector.head dsList
  putStrLn $ "Data source: " <> Text.unpack dsName <> " (" <> show dsId <> ")"

  -- ---------------------------------------------------------------
  -- Part 1: List all templates
  -- ---------------------------------------------------------------
  printHeader (Text.pack "Templates: List All")

  templatesResp <-
    runTest (Text.pack "Listing data source templates") $
      listDataSourceTemplates methods dsId Nothing Nothing Nothing

  let ListTemplatesResponse {templates = templateList, hasMore = moreTemplates} = templatesResp
  putStrLn $ "Found " <> show (Vector.length templateList) <> " templates"
  putStrLn $ "Has more: " <> show moreTemplates

  -- Display each template
  Vector.forM_ templateList $ \tmpl -> do
    let TemplateRef {id = tmplId, name = tmplName, isDefault = tmplDefault} = tmpl
    putStrLn $
      "  - "
        <> Text.unpack tmplName
        <> " (id: "
        <> show tmplId
        <> ")"
        <> if tmplDefault then " [DEFAULT]" else ""

  -- ---------------------------------------------------------------
  -- Part 2: Create a page with a template (if available)
  -- ---------------------------------------------------------------
  printHeader (Text.pack "Templates: Create Page with Template")

  -- Check if there's a default template configured
  let hasDefault = Vector.any (\t -> isDefault t) templateList

  if hasDefault
    then do
      let props = fromList [("title", PV.titleValue (Vector.singleton (mkPlainRichText "Template Demo Page")))]

          -- Create a page with the default template.
          -- The template parameter tells the API to apply the data source's
          -- default template. The optional timezone controls how @now and @today
          -- template variables resolve.
          createReq =
            CreatePage
              { parent = DataSourceParent {dataSourceId = dsId, parentDatabaseId = Nothing},
                properties = props,
                children = Nothing,
                markdown = Nothing,
                icon = Nothing,
                cover = Nothing,
                template = Just (DefaultTemplate (Just "America/New_York")),
                position = Nothing
              }

      newPage <-
        runTest (Text.pack "Creating page with default template") $
          createPage methods createReq

      let PageObject {id = newPageId, url = newPageUrl} = newPage
      putStrLn $ "Page created: " <> Text.unpack newPageUrl
      putStrLn $ "  (Template content is applied asynchronously)"

      -- Clean up
      let trashReq =
            UpdatePage
              { properties = fromList [],
                inTrash = Just True,
                icon = Nothing,
                cover = Nothing,
                template = Nothing,
                eraseContent = Nothing
              }
      _ <- updatePage methods newPageId trashReq
      putStrLn "Demo page trashed"
    else
      putStrLn "No default template configured — skipping template page creation"

  -- If there are specific templates, show how to use TemplateById
  if Vector.null templateList
    then putStrLn "No templates available — to use TemplateById, configure templates in Notion first"
    else do
      let TemplateRef {id = firstTmplId, name = firstTmplName} = Vector.head templateList
      putStrLn $ "\nTo create a page with a specific template:"
      putStrLn $ "  Use: TemplateById " <> show firstTmplId <> " (Just \"America/New_York\")"
      putStrLn $ "  Template name: " <> Text.unpack firstTmplName

-- | Helper to create a plain RichText from a string
mkPlainRichText :: Text.Text -> RichText
mkPlainRichText t =
  RichText
    { plainText = t,
      href = Nothing,
      annotations = defaultAnnotations,
      type_ = "text",
      content = TextContentWrapper (TextContent {content = t, link = Nothing})
    }
