# Notion API Client for Haskell

A type-safe Haskell client for the [Notion API](https://developers.notion.com/reference/intro) (version `2026-03-11`).

## Features

- Type-safe API bindings using Servant
- Comprehensive coverage of Notion API endpoints
- Support for all Notion object types: Pages, Databases, Data Sources, Blocks, Users, etc.
- Simple client interface with sensible defaults
- Automatic retries of rate-limited and overloaded requests, honoring `retry-after`
- Typed error codes with request IDs for support
- OAuth token exchange and URL-to-ID helpers

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

### Configuration and retries

`makeMethods` uses sensible defaults. For control over the API version, base
URL, timeout (default 60 seconds), retries and logging, build a `ClientConfig`:

```haskell
import Network.HTTP.Client.TLS (newTlsManager)
import Notion.V1

main :: IO ()
main = do
    manager <- newTlsManager
    let config = defaultClientConfig {logger = Just stderrLogger, logLevel = LogInfo}
        methods = makeMethodsWith config manager token
    user <- retrieveMyUser methods
    print user
```

Requests that fail with `rate_limited` (HTTP 429) or `service_overload` (529)
are retried up to two times, as are `internal_server_error` and
`service_unavailable` for `GET` and `DELETE`. A `retry-after` header sets the
delay; otherwise the delay grows exponentially with jitter. Disable retries with
`defaultClientConfig {retryOptions = noRetries}`.

### Error handling

```haskell
import Control.Exception (catch)
import Data.Text qualified as Text
import Notion.V1.Error

safeRetrieve :: Methods -> PageID -> IO ()
safeRetrieve Methods{retrievePage} pageId =
    (retrievePage pageId >>= print) `catch` \(e :: NotionError) -> case code e of
        ObjectNotFound -> putStrLn "No such page"
        other ->
            putStrLn $ "Notion error: " <> Text.unpack (apiErrorCodeText other)
                <> " - " <> Text.unpack (message e)
                <> " (request " <> show (requestId e) <> ")"
```

Besides `NotionError`, a request can throw `UnknownHTTPResponseError` (a
non-2xx response that is not a Notion error, such as an HTML page from Notion's
edge proxy; `displayException` explains it and includes the Cloudflare Ray ID),
`RequestTimeoutError`, or `InvalidPathParameterError` (an ID containing `..`,
rejected before sending).

### OAuth

```haskell
import Notion.V1 (defaultBaseUrl, defaultClientConfig)
import Notion.V1.OAuth
import Servant.Client (mkClientEnv)

exchangeCode :: Manager -> Text -> IO OAuthTokenResponse
exchangeCode manager authCode = do
    let oauth = makeOAuthMethodsWith defaultClientConfig
            (mkClientEnv manager defaultBaseUrl)
            OAuthCredentials {clientId = "...", clientSecret = "..."}
    createOAuthToken oauth $ AuthorizationCode AuthorizationCodeGrant
        { code = authCode
        , redirectUri = Just "https://example.com/callback"
        , externalAccount = Nothing
        }
```

`revokeOAuthToken` and `introspectOAuthToken` take a token.

### URL helpers

```haskell
import Notion.V1.Helpers (extractBlockId, extractNotionId)

extractNotionId "https://www.notion.so/team/Tasks-abc123def456789012345678901234ab?v=..."
-- Just (UUID "abc123de-f456-7890-1234-5678901234ab")
extractBlockId "https://www.notion.so/Page-0123456789abcdef0123456789abcdef#block-fedcba9876543210fedcba9876543210"
-- Just (UUID "fedcba98-7654-3210-fedc-ba9876543210")
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

`paginateFoldM` and `paginateForM_` process every item while holding only one
page in memory.

## Usage with effectful

Callers that use the [`effectful`](https://hackage.haskell.org/package/effectful)
effect system can opt into an `Eff`-typed surface via the companion
package
[`notion-client-effectful`](./notion-client-effectful/). Every
`Notion.V1.Methods` field is re-exposed as a smart constructor of a
`Notion` effect, and a `runNotion` interpreter dispatches through a
concrete `Methods` value. `NotionError` responses surface via the
`Error NotionError` effect rather than as `IO` exceptions.

```haskell
module Demo where

import Data.Text (Text)
import Data.Text qualified as Text
import Effectful (Eff, runEff, (:>))
import Effectful.Error.Static (Error, runErrorNoCallStack)
import Notion.V1                    (getClientEnv, makeMethods)
import Notion.V1.Common             (UUID (..))
import Notion.V1.Effectful qualified as NE
import Notion.V1.Error              (NotionError)
import System.Environment qualified as Env

demo :: (NE.Notion :> es, Error NotionError :> es) => UUID -> Eff es Text
demo pid = do
  page <- NE.retrievePage pid
  pure (Text.pack (show page))

main :: IO ()
main = do
  token <- Text.pack <$> Env.getEnv "NOTION_TOKEN"
  env <- getClientEnv "https://api.notion.com/v1"
  let methods = makeMethods env token
  result <-
    runEff . runErrorNoCallStack @NotionError . NE.runNotion methods $
      demo (UUID "00000000-0000-0000-0000-000000000000")
  print result
```

See [`notion-client-effectful/README.md`](./notion-client-effectful/README.md)
for the full import pattern (qualifying one of the two `Notion.V1`
modules is required — every smart constructor shares its name with
the matching `Methods` record selector).

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
- **OAuth**: Exchange authorization codes and refresh tokens, revoke and introspect tokens

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