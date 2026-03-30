# Notion API Client for Haskell

A type-safe Haskell client for the [Notion API](https://developers.notion.com/reference/intro) (version `2026-03-11`).

## Features

- Type-safe API bindings using Servant
- Comprehensive coverage of Notion API endpoints
- Support for all Notion object types: Pages, Databases, Data Sources, Blocks, Users, etc.
- Simple client interface with sensible defaults

## Installation

Add to your `package.yaml` or `.cabal` file:

```yaml
dependencies:
  - notion-client
```

## Usage

Here's a simple example of retrieving a Notion page:

```haskell
module Main where

import Notion.V1
import Notion.V1.Pages
import Data.Text qualified as Text
import System.Environment qualified as Environment

main :: IO ()
main = do
    token <- Environment.getEnv "NOTION_TOKEN"

    clientEnv <- getClientEnv "https://api.notion.com/v1"

    let Methods{ retrievePage } = makeMethods clientEnv (Text.pack token)

    page <- retrievePage "page-id-here"

    print page
```

### Creating a page with typed properties

```haskell
import Notion.V1
import Notion.V1.Common (Parent(..))
import Notion.V1.Pages
import Notion.V1.PropertyValue qualified as PV
import Data.Map qualified as Map
import Data.Vector qualified as Vector

createNewPage :: Methods -> IO PageObject
createNewPage Methods{createPage} = do
    let pageProperties = Map.fromList
            [ ("title", PV.titleValue (Vector.singleton titleRichText))
            , ("Status", PV.selectValue "In Progress")
            , ("Priority", PV.selectValue "High")
            , ("Due", PV.dateValue "2024-06-01" Nothing)
            , ("Score", PV.numberValue 42)
            , ("Done", PV.checkboxValue False)
            ]

        newPage = mkCreatePage
            (DataSourceParent { dataSourceId = "data-source-id-here" })
            pageProperties

    createPage newPage
```

### Reading typed properties

```haskell
import Notion.V1.PropertyValue

readPageStatus :: PageObject -> Maybe Text
readPageStatus page =
    case Map.lookup "Status" (properties page) of
        Just (SelectValue _ (Just opt)) -> Just (name opt)
        _ -> Nothing
```

### Creating a page with markdown

```haskell
import Notion.V1
import Notion.V1.Common (Parent(..))
import Notion.V1.Pages

createMarkdownPage :: Methods -> IO PageObject
createMarkdownPage Methods{createPage} = do
    let newPage = (mkCreatePage
            (DataSourceParent { dataSourceId = "data-source-id" })
            mempty)
            { markdown = Just "# Hello\n\nThis page was created with **markdown**." }

    createPage newPage
```

### Editing page content with markdown

```haskell
import Notion.V1
import Notion.V1.Pages

editPage :: Methods -> PageID -> IO PageMarkdown
editPage Methods{updatePageMarkdown} pageId =
    updatePageMarkdown pageId $
        UpdateContent UpdateContentRequest
            { contentUpdates = fromList
                [ ContentUpdate
                    { oldStr = "old text"
                    , newStr = "new text"
                    , replaceAllMatches = Nothing
                    }
                ]
            , allowDeletingContent = Nothing
            }
```

### Error handling

```haskell
import Control.Exception (catch)
import Notion.V1.Error (NotionError(..))

safeRetrieve :: Methods -> PageID -> IO ()
safeRetrieve Methods{retrievePage} pageId =
    retrievePage pageId `catch` \(e :: NotionError) ->
        putStrLn $ "Notion error: " <> code e <> " - " <> message e
```

### Auto-pagination

```haskell
import Notion.V1.Pagination (paginateAll)
import Notion.V1.DataSources (QueryDataSource(..))

allPages <- paginateAll $ \cursor ->
    queryDataSource methods dsId QueryDataSource
        { filter = Nothing, sorts = Nothing
        , startCursor = cursor, pageSize = Just 100
        , inTrash = Nothing, filterProperties = Nothing
        }
```

## API Coverage

- **Databases**: Create, retrieve, update, and query databases
- **Data Sources**: Create, retrieve, update, query data sources; list templates
- **Pages**: Create (with blocks or markdown), retrieve, update, move pages; retrieve and update page markdown
- **Blocks**: Retrieve, update, append children (with position control), and delete blocks
- **Users**: List, retrieve users and bot users
- **Views**: Create, retrieve, update, delete, list, and query database views (all 10 view types)
- **Search**: Search for pages and data sources
- **Comments**: Create and list comments
- **Custom Emojis**: List workspace custom emojis
- **Webhooks**: Event types (including view events) and signature verification

## Running the Example

The repository includes a comprehensive example in the `notion-client-example` directory that demonstrates how to use most API endpoints.

To run the example:

```bash
# Set required environment variables
export NOTION_TOKEN="your-integration-token"

# Optional: Set these if you want to test specific database/page endpoints
export NOTION_TEST_DATABASE_ID="your-database-id"
export NOTION_TEST_PAGE_ID="your-page-id"

# Run the example
cabal run notion-client-example
```

### Obtaining API Credentials

1. Create a Notion integration at [https://www.notion.so/my-integrations](https://www.notion.so/my-integrations)
2. Get your integration token from the integration settings
3. Share any Notion pages or databases you want to access with your integration
   - Open the page/database in Notion
   - Click "Share" in the top right
   - Enter your integration name and click "Invite"
4. Get the page/database IDs from their URLs:
   - Page URL: `https://www.notion.so/Your-Page-Title-83715d7c1111424aaa11d7fc1111bd2a`
   - Page ID: `83715d7c1111424aaa11d7fc1111bd2a` (the last part of the URL)

## License

MIT