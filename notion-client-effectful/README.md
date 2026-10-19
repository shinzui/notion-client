# notion-client-effectful

An [effectful][effectful] surface for
[`notion-client`](https://hackage.haskell.org/package/notion-client).

[effectful]: https://hackage.haskell.org/package/effectful

This package wraps the `Notion.V1.Methods` record as a dynamic
effect — so code written against `effectful` does not have to
thread the `Methods` value through every call site and does not
have to drop into `IO` at each API boundary.

## Purpose

`notion-client` exposes a single `Methods` record whose fields
are `IO`-typed API calls. That is ergonomic for a plain-`IO`
program but awkward for an `effectful`-based caller: every call
requires `liftIO` and escapes the ambient `Error` / `Reader` /
`Log` stack.

`notion-client-effectful` gives that caller an equivalent set of
operations surfaced as an `Effect` so the stack is preserved.

## Import pattern

Every smart constructor shares its name with the matching
`Notion.V1.Methods` record selector. That is on purpose — it
keeps migration from IO mechanical — but it means a file that
imports both modules unqualified will see name clashes. Import
one of the two qualified:

```haskell
import Notion.V1                    (Methods, getClientEnv, makeMethods)
import Notion.V1.Effectful qualified as NE
```

Then `NE.retrievePage`, `NE.search`, `NE.runNotion`, and so on.

The umbrella module exposes the common operations. For the complete surface,
including filtered page requests, background operations, meeting notes and
comment retrieval/update/deletion, import the effect and interpreter directly:

```haskell
import Notion.V1.Effectful.Effect qualified as NE
import Notion.V1.Effectful.Interpreter (runNotion)
```

Use `NE.createPageFiltered`, `NE.createPageAsync`, `NE.retrieveAsyncTask`, and
the other effect operations with the unqualified `runNotion` interpreter.

## Error handling

`runNotion` catches `Notion.V1.Error.NotionError` thrown by the
underlying `Methods` and re-raises it via the `Error NotionError`
effect, so callers can branch on API error shapes
(`object_not_found`, validation failures, etc.) without reaching
for `IO`-level exception handling.

Other `Servant.Client.ClientError` values — network failures,
decoding errors — are *not* caught and remain `IO` exceptions.
This preserves the contract of the underlying `notion-client`
library and lets callers layer their own `Error ClientError`
interpretation on top later. The same applies to
`UnknownHTTPResponseError`, `RequestTimeoutError` and
`InvalidPathParameterError` from `Notion.V1.Error`. Retries of rate-limited
requests and reactive OAuth renewal happen inside `Methods`, before an error
reaches `runNotion`.

### OAuth installations

Build `Methods` with core `makeMethodsWithTokenSource` and pass it to `runNotion`;
existing effect operations need no changes. See the core
[OAuth walkthrough](https://github.com/shinzui/notion-client#oauth) for browser
login and token-store setup.

`OAuthError`, `ReauthorizationRequired`, `TokenPersistenceError` and
`RefreshOutcomeUnknown` propagate as IO exceptions. Handle them at the application
boundary outside `runEff`; `Error NotionError` catches only final Notion API errors.
For a persistence failure, call `retryTokenPersistence` on the same manager to
save its retained pair without another refresh. Reauthorization or an uncertain
remote outcome requires a new login and manager. Use one manager per installation;
multiple processes must coordinate the entire load/refresh/save sequence.

## Minimum viable usage

Use `GHC2024` with `OverloadedStrings` for this example.

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

demo ::
  (NE.Notion :> es, Error NotionError :> es) =>
  UUID ->
  Eff es Text
demo pid = do
  page <- NE.retrievePage pid
  pure (Text.pack (show page))

main :: IO ()
main = do
  token <- Text.pack <$> Env.getEnv "NOTION_TOKEN"
  env <- getClientEnv "https://api.notion.com/v1"
  let methods = makeMethods env token
  result <-
    runEff
      . runErrorNoCallStack @NotionError
      . NE.runNotion methods
      $ demo (UUID "00000000-0000-0000-0000-000000000000")
  print result
```

## What you get

One smart constructor per field of `Notion.V1.Methods`. The
argument types and order match the underlying field, so an
existing call like

```haskell
page <- retrievePage methods pid
```

becomes

```haskell
page <- NE.retrievePage pid
```

with no other change to the call site.

## Versioning

Use compatible versions of both packages:

| `notion-client-effectful` | Required `notion-client` |
|---|---|
| 0.4.x | `>=0.10 && <0.11` |
| 0.3.x | `>=0.9 && <0.10` |
| 0.2.x | `>=0.8 && <0.9` |

The prepared release is `notion-client-effectful-0.4.0.0` with
`notion-client-0.10.0.0`. The companion's core bound moves with each breaking core
release, even when `Methods` fields are unchanged. See the
[changelog](CHANGELOG.md) for migration details and the repository's
[release preparation](https://github.com/shinzui/notion-client#release-preparation)
for validation.
