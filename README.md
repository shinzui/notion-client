# Notion API Client for Haskell

A type-safe Haskell client for the [Notion API](https://developers.notion.com/reference/intro) (version `2026-03-11`).

## Features

- Type-safe API bindings using Servant
- Comprehensive coverage of Notion API endpoints
- Support for all Notion object types: Pages, Databases, Data Sources, Blocks, Users, etc.
- Simple client interface with sensible defaults
- Automatic retries of rate-limited and overloaded requests, honoring `retry-after`
- Typed error codes with request IDs for support
- OAuth login, automatic token refresh and URL-to-ID helpers

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

### Serializing page responses

Use the response helpers when exporting API results:

```haskell
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy (ByteString)
import Notion.V1.Pages (PageObject, pageResponseJSON)
import Notion.V1.PropertyValue (PropertyValue, propertyValueResponseJSON)

encodePageResponse :: PageObject -> ByteString
encodePageResponse = Aeson.encode . pageResponseJSON
encodePropertyResponse :: PropertyValue -> ByteString
encodePropertyResponse = Aeson.encode . propertyValueResponseJSON
```

These helpers preserve modeled page fields and property IDs, type discriminators,
full users, and nested rollup values. Existing `ToJSON` instances and create/update
builders keep their mutation encoding. Response helpers preserve modeled data;
they do not preserve unmodeled fields or the original JSON bytes. An empty property
ID is the model's absent-ID sentinel and is omitted, including inside rollups.
Nonempty IDs, including URL-encoded IDs, are emitted unchanged.

`RelationValue pid refs hasMore` retains `has_more` as `Maybe Bool`: `Just True`
means the reference list is incomplete, `Just False` means complete, and `Nothing`
means the flag was absent (or null). No state is inferred from the reference count,
and the encoder does not fetch further references. `relationValue` keeps its
existing `[UUID] -> PropertyValue` signature and supplies `Nothing` for writes.

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

Public integrations (public connections in Notion's portal) use a browser consent
flow. Create one in the [developer portal](https://www.notion.so/profile/integrations),
register an exact redirect URI, and keep its OAuth client ID and secret in your
trusted server environment. The client secret and exchange belong on a trusted
backend for distributed desktop or browser apps.

The protocol helpers build the URL, verify the callback, and exchange its code:

```haskell
import Control.Exception (throwIO)
import Data.Text (Text)
import Network.HTTP.Types.URI (Query)
import Notion.V1.OAuth
import Notion.V1.OAuth.Authorization

beginLogin :: Text -> Text -> IO AuthorizationRequest
beginLogin client redirect = do
    freshState <- newOAuthState
    pure (AuthorizationRequest client redirect freshState)

-- Run this only after claiming the initiating session's pending request once.
exchangeVerifiedCode :: OAuthMethods -> AuthorizationRequest -> OAuthCode
                     -> IO OAuthTokenResponse
exchangeVerifiedCode = exchangeAuthorizationCode

verifyCallback :: AuthorizationRequest -> Query -> IO OAuthCode
verifyCallback request query =
    either throwIO pure (verifyAuthorizationCallback (state request) query)
```

Send the browser to `authorizationUrl request`. Bind the complete request (state,
client ID and exact redirect URI) to the initiating session and expire it after a
short interval. Give the verifier an already-decoded WAI query or `parseQuery`
output; do not decode twice. After verification, atomically consume the pending
request before exchange. A state-validated `AuthorizationDenied` also consumes it;
malformed or forged callbacks leave it pending. The pure verifier supplies neither
session storage nor expiry/replay protection. Descriptions are untrusted text.

After a successful exchange, convert with `oauthTokensFromResponse now response`
and durably save the pair. If that first save fails, retain the received pair and
retry only its save; never exchange the code again. The runnable example below
implements this recovery. Then construct stable methods from your store:

```haskell
import Notion.V1 (ClientConfig, Methods, makeMethodsWithTokenSource)
import Notion.V1.OAuth.Refresh
import Servant.Client (ClientEnv)

connectInstallation :: ClientConfig -> ClientEnv -> OAuthMethods -> TokenStore
                    -> IO (OAuthTokenManager, Methods)
connectInstallation config env oauth store = do
    manager <- newOAuthTokenManager oauth store
    pure (manager, makeMethodsWithTokenSource config env (tokenManagerSource manager))
```

`TokenStore` supplies `loadTokens` and an idempotent `saveTokens`; the library also
provides `inMemoryTokenStore` for volatile use. The manager loads once, renews once
after typed `Unauthorized`, and persists the replacement before using it.
`refreshTokensNow` performs explicit refresh. Handle these IO exceptions:

- `OAuthError`: inspect `oauthErrorCode`; `OAuthInvalidClient` means client
  configuration failed, and `OAuthInvalidGrant` means a grant was rejected.
  OAuth endpoint calls never retry automatically. Default rendering/logging omits
  descriptions, raw bodies and headers; explicit metadata is available.
- `ReauthorizationRequired`: start a new login; the refresh token is absent or
  rejected. A null replacement refresh token remains absent.
- `TokenPersistenceError`: the manager retains the unsaved replacement and blocks
  requests/refresh. Call `retryTokenPersistence` to save that identical pair.
- `RefreshOutcomeUnknown`: a refresh may have succeeded remotely. Start a new login
  and construct a new manager; do not reload the old store and replay its token.

Use one manager per installation. Multiple managers/processes must coordinate the
entire load/refresh/save sequence externally; save-time compare-and-swap is too
late. Store hooks must not re-enter the manager. A crash between remote rotation
and durable save may require another login. `currentTokens` is for explicit
inspection/recovery and can return unsaved or unusable credentials. There is no
timer refresh because token responses supply no expiry.

`RequestContext` now carries `contextTokenSource`; `standardHeaders` reads current
headers in IO. Non-Servant clients use `withStandardHeaders` around replayable
response acquisition, with `withRetries` inside it. Close rejected responses before
throwing their classified error. Keep body consumption and user callbacks outside
both retry layers. Byte and file-backed multipart bodies can be replayed; arbitrary
one-shot streams cannot. OAuth methods retain Basic authentication.

The effectful adapter accepts these same `Methods`. Final `NotionError` values use
`Error NotionError`; OAuth lifecycle and persistence exceptions remain IO exceptions.

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
- **OAuth**: Browser login helpers, verified callbacks, automatic token refresh with persistence, revoke and introspect tokens

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

### OAuth example

The POSIX-only `notion-client-oauth-example` runs a trusted local confidential
client. Register `http://localhost:8765/callback` in the public connection's OAuth
configuration, then set credentials in your shell (never commit them):

```bash
export NOTION_OAUTH_CLIENT_ID=...
export NOTION_OAUTH_CLIENT_SECRET=...
cabal run notion-client-oauth-example -- login
cabal run notion-client-oauth-example -- whoami
cabal run notion-client-oauth-example -- refresh
cabal run notion-client-oauth-example -- whoami
cabal run notion-client-oauth-example -- revoke
```

`login` prints a consent URL after the listener is ready on `127.0.0.1`, validates
state, consumes the callback once, exchanges the code and saves credentials before
reporting success. It expires after ten minutes. Invalid callbacks leave it pending;
a matching-state cancellation reports cancellation without exchanging. `whoami`
prints the bot name and up to five shared results; an empty search is valid.
`refresh` prints full-value rotation comparisons as booleans and offers persistence
retry without sending a second grant. `revoke` removes local credentials only after
confirmed remote success. Subsequent commands require login; no remote token-family
invalidation is assumed.

`NOTION_OAUTH_TOKEN_FILE` defaults to `.notion-oauth-tokens.json`. The example requires
an owner-only regular token file in a directory owned by you and not writable by
group or others. It rejects token symlinks, creates private temporary files before
writing, synchronizes and atomically replaces them, and synchronizes the parent
directory. Every command holds `<token-file>.lock` across load/refresh/save. After
a crash, remove a stale lock directory manually only after checking no example
process is active. Keep the process alive to retry an unsaved pair; stopping it can
require another login. This file store is an example, not a production secret store.

If the portal refuses HTTP localhost redirects, register an HTTPS tunnel's exact
callback URL and set `NOTION_OAUTH_REDIRECT_URI` to it. Set
`NOTION_OAUTH_LISTEN_PORT` to its local target port (default `8765`). Redirect URIs
must have an absolute path and no query or fragment. The listener still binds
loopback. No framework adapter, PKCE, timer refresh, distributed store or Notion
MCP OAuth is provided. The executable and its POSIX file tests are disabled on
Windows; the core library and ordinary HTTP tests remain portable.

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
