# Notion API Client for Haskell

A type-safe Haskell client for the [Notion API](https://developers.notion.com/reference/intro) (version `2025-09-03`).

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

### Creating a page

```haskell
import Notion.V1
import Notion.V1.Common (Parent(..))
import Notion.V1.Pages
import Data.Map qualified as Map
import Data.Aeson (toJSON)

createNewPage :: Methods -> IO PageObject
createNewPage Methods{createPage} = do
    let pageProperties = Map.fromList
            [ ("title", PropertyValue
                { type_ = Title
                , value = Just $ toJSON [-- rich text objects --]
                })
            ]

        newPage = mkCreatePage
            (DataSourceParent { dataSourceId = "data-source-id-here" })
            pageProperties

    createPage newPage
```

## API Coverage

- Databases: Create, retrieve, and update databases
- Data Sources: Create, retrieve, update, and query data sources
- Pages: Create, retrieve, and update pages
- Blocks: Retrieve, update, append children, and delete blocks
- Users: List, retrieve users and bot users
- Search: Search for pages and data sources
- Comments: Create and list comments
- Webhooks: Event types and signature verification

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

BSD-3-Clause