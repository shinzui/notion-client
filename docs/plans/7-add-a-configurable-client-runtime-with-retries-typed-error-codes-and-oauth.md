---
id: 7
slug: add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth
title: "Add a Configurable Client Runtime with Retries, Typed Error Codes, and OAuth"
kind: exec-plan
created_at: 2026-09-14T18:46:51Z
intention: intention_01m2jjvjgpef9tyyp50524jfwq
master_plan: "docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md"
provenance:
  created_by:
    model: "claude-opus-5"
    harness: "claude-code"
    at: 2026-09-14T18:46:51Z
  revisions:
    - model: "claude-opus-5[1m]"
      harness: "claude-code"
      at: 2026-09-15T13:29:07Z
      mode: "implement"
      note: "Implementing EP-2 milestones"
---

# Add a Configurable Client Runtime with Retries, Typed Error Codes, and OAuth

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.

This plan is child EP-2 of `docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md`.


## Purpose / Big Picture

Today every Haskell program using `notion-client` gets a fixed request pipeline: the `Notion-Version` header is hard-coded, there is no request timeout beyond the HTTP library's 30-second default, a single HTTP 429 ("rate limited") response from Notion immediately becomes an exception, error codes are untyped strings, and there is no way to complete Notion's OAuth flow. Notion's official TypeScript SDK (`@notionhq/client` v5.26.0, checked out at `/Users/shinzui/Keikaku/hub/notion-sdk-js`, called "the JS SDK" below) has all of these.

After this plan a Haskell user can:

1. Build a client from a configuration record (`ClientConfig`) that sets the API version, base URL, timeout (default 60 seconds), retry policy, `User-Agent`, and an optional logging callback, using `makeMethodsWith`. The existing `makeMethods clientEnv token` keeps working with the same type.
2. Rely on the client to retry rate-limited (429 `rate_limited`) and overloaded (529 `service_overload`) responses on every request, and 500/503 on `GET`/`DELETE` requests, honoring Notion's `retry-after` header, exactly like the JS SDK.
3. Pattern-match on a typed `APIErrorCode` (for example `ObjectNotFound`, `RateLimited`) in a `NotionError` that also carries the `request_id`, `additional_data`, HTTP status and the `x-notion-request-id` / `cf-ray` response headers. Non-JSON failures (for example an HTML page from Notion's Cloudflare edge) become an `UnknownHTTPResponseError` with a diagnosable message, and timeouts become a `RequestTimeoutError`.
4. See whether a list response is complete via `ListOf.requestStatus`.
5. Exchange an OAuth authorization code or refresh token for an access token, revoke a token, and introspect a token, using HTTP Basic authentication with the integration's client ID and secret.
6. Turn a Notion URL into an ID with `extractNotionId`, `extractPageId`, `extractDatabaseId` and `extractBlockId`.

It is visible through new unit tests in the `tasty` suite that run without network access (a scripted fake Notion answers requests, so a 429-then-200 sequence can be observed being retried), and optionally live with a token via a GHCi session that prints the client's log lines.


## Progress

- [x] Milestone 1: Add dependencies and `Paths_notion_client` to `notion-client.cabal`. (2026-09-15)
- [x] Milestone 1: Create `src/Notion/V1/Client.hs` with `ClientConfig`, `LogLevel`, `Logger`, `defaultClientConfig`, `RequestContext`/`requestContextFor`/`standardHeaders`, `responseTimeoutFor`, `configureClientEnv` (timeout + `User-Agent` middleware). (2026-09-15)
- [x] Milestone 1: Add `makeMethodsWith` / `makeMethodsWithEnv` in `src/Notion/V1.hs`; re-implement `makeMethods` as a wrapper; thread `notionVersion` from the config. (2026-09-15)
- [x] Milestone 1: Create `tasty/FakeNotion.hs` and `tasty/RuntimeTests.hs` (config tests); register in cabal and `tasty/Main.hs`; `cabal test` green. (2026-09-15)
- [x] Milestone 2: Rewrite `src/Notion/V1/Error.hs` (`APIErrorCode`, extended `NotionError`, `HttpErrorResponse`, `UnknownHTTPResponseError`, `RequestTimeoutError`, `InvalidPathParameterError`, `buildRequestError`, `notionErrorFromResponse`, `fromClientError`). (2026-09-15)
- [x] Milestone 2: Convert errors in the runtime; add `RequestStatus` to `src/Notion/V1/ListOf.hs`; fix `requestStatus` in existing test fixtures and the example app. (2026-09-15)
- [x] Milestone 2: Error and `RequestStatus` tests in `tasty/RuntimeTests.hs`; `cabal test` green. (2026-09-15)
- [x] Milestone 3: Create `src/Notion/V1/Retry.hs` (pure `canRetry`, `parseRetryAfter`, `retryDelay`, `validateRequestPath`). (2026-09-15)
- [x] Milestone 3: Add `withRetries`, logging and the path guard to the middleware in `src/Notion/V1/Client.hs`. (2026-09-15)
- [x] Milestone 3: Pure retry tests and fake-server retry tests; `cabal test` green. (2026-09-15)
- [ ] Milestone 4: Create `src/Notion/V1/OAuth.hs` (types, Servant API, `OAuthMethods`, `makeOAuthMethods`, `makeOAuthMethodsWith`) and `tasty/OAuthTests.hs`.
- [ ] Milestone 4: Create `src/Notion/V1/Helpers.hs` (`extractNotionId` family) and `tasty/HelpersTests.hs`; add `paginateFoldM`/`paginateForM_` to `src/Notion/V1/Pagination.hs`.
- [ ] Milestone 4: Update `README.md`, `notion-client-example/DatabaseDemo.hs`, effectful docs, and `CHANGELOG.md`; `cabal build all && cabal test` green.


## Surprises & Discoveries

- The servant-client resolved in the Nix shell is 0.20.3.0, so `ClientEnv.middleware` is available and the fallback in Idempotence and Recovery was not needed. In `servant-client/src/Servant/Client/Internal/HttpClient.hs`, `performRequest` calls `makeClientRequest` *outside* `catchConnectionError`, so an exception thrown from a custom `makeClientRequest` escapes as a plain `IO` exception. That is why EP-1's `captureRequest` helper in `tasty/WireFormatTests.hs` keeps working unchanged under the new middleware; all 27 of its tests passed after Milestone 1.
- `Network.HTTP.Client.ResponseTimeout` has no `Eq` instance, so "applyTimeout sets responseTimeout" compares `show` output instead of using `@?=` on the values.
- tasty's `-p` pattern containing `||` must be passed through `cabal test` as two `--test-option=` arguments; `--test-options='-p /A/ || /B/'` splits on spaces and fails with ``Invalid argument `||'``.
- Retrying a multipart upload is safe. servant-client builds a fresh http-client request for every attempt through `makeClientRequest`. `convertBody` turns a `RequestBodySource` into `RequestBodyStreamChunked` with a new popper that re-runs `unSourceT sourceIO` (`servant-client/src/Servant/Client/Internal/HttpClient.hs`, `convertBody`). A retried `sendFileUploadContent` therefore regenerates its body instead of reusing a consumed stream, and the `RequestBodySource` exclusion anticipated in Idempotence and Recovery is not needed.
- `Notion.V1` must re-export `withRetries`, as the interface contract for plan 14 requires. `tasty/RuntimeTests.hs` failed to compile until it did (`Variable not in scope: withRetries`).
- One of four full `cabal test` runs after Milestone 3 reported `1 out of 181 tests failed (35.59s)`, with the live `NOTION_TOKEN` E2E groups enabled. It did not recur in the next three runs (`All 181 tests passed`), and the network-free runtime tests are deterministic, so it was most likely a transient live-API failure. The failing test name was not captured.


## Decision Log

- Decision: Create `src/Notion/V1/Retry.hs` in Milestone 1 holding only `RetryOptions`, `defaultRetryOptions` and `noRetries`; `Notion.V1.Client` re-exports them. Export `withRetries` from `Notion.V1.Client` in Milestone 3, when it exists, rather than stubbing it in Milestone 1.
  Rationale: The plan allowed either placement. Creating the module early avoids moving the type later, and an unimplemented `withRetries` stub would be misleading.
  Date: 2026-09-15

- Decision: Also export `defaultUserAgent :: Text` from `Notion.V1.Client`.
  Rationale: `defaultClientConfig` needs the value, and callers who set `userAgent` to add a suffix can reuse it. It is purely additive.
  Date: 2026-09-15

- Decision: In Milestone 2, convert servant errors only in `runClientWith` (via `fromClientError`). The conversion inside `notionMiddleware` is added in Milestone 3, together with the retry loop that needs it.
  Rationale: Before retries exist, converting in the middleware would duplicate `runClientWith`'s work and change nothing observable. Milestone 3 has to restructure the middleware anyway.
  Date: 2026-09-15

- Decision: The retry loop, timeout, `User-Agent` header and path guard are installed as a servant-client `ClientEnv` middleware (the `middleware` field added in servant-client 0.20.2), not by re-running whole `ClientM` actions inside `run`.
  Rationale: The middleware receives the servant `Request`, so the HTTP method (needed by the JS rule "retry 500/503 only for GET/DELETE") and the path are known before the first attempt. Only the HTTP exchange is retried; response decoding happens after the middleware. The lower bound of `servant-client` must rise from 0.20 to 0.20.2 (verified in `servant-client/CHANGELOG.md` of the Mori-registered servant checkout: "Clients now support real middleware ... which can be configured in `ClientEnv`" under 0.20.2).
  Date: 2026-09-14

- Decision: Implement the timeout with http-client's per-request `responseTimeout`, set by wrapping `ClientEnv.makeClientRequest`, not with `System.Timeout.timeout`.
  Rationale: In http-client 0.7.19 (`Network/HTTP/Client/Core.hs`, `getConnectionWrapper`) `responseTimeout` bounds connection establishment plus the wait for response headers, throwing `ConnectionTimeout` or `ResponseTimeout`. That matches the JS SDK, whose `RequestTimeoutError.rejectAfterTimeout` wraps only the `fetch` promise, which resolves when headers arrive. It also works unchanged for the SSE streaming plan (`docs/plans/14-stream-session-updates-over-server-sent-events.md`), where `System.Timeout` would wrongly kill a long-lived open stream. It does not require us to own the `Manager`.
  Date: 2026-09-14

- Decision: `makeMethods :: ClientEnv -> Text -> Methods` keeps its type and becomes `makeMethodsWithEnv legacyClientConfig`, where `legacyClientConfig = defaultClientConfig {timeout = Nothing}`. It therefore gains the default retry policy, typed errors and a `User-Agent` header, but keeps whatever timeout the caller's `Manager` already has (30 seconds for `getClientEnv`).
  Rationale: The MasterPlan's vision is that users "rely on the client to retry rate-limited requests"; making retries opt-in would leave existing users without that. Retries can only turn a failure into a success or delay a failure. Not overriding the timeout avoids silently changing a caller-tuned `Manager`. Opt-out is `makeMethodsWithEnv defaultClientConfig {retryOptions = noRetries}`.
  Date: 2026-09-14

- Decision: `NotionError` keeps its name and existing fields; `code` changes from `Text` to `APIErrorCode`, which has an `IsString` instance so string literals such as `"validation_error"` still type-check. Unknown codes decode to `UnknownErrorCode Text` and stay a `NotionError` (the JS SDK instead turns them into `UnknownHTTPResponseError`).
  Rationale: Minimizes breakage for `catch \(e :: NotionError)` users and the effectful interpreter, and follows the MasterPlan's tolerant-decoding rule (a new Notion error code must not demote a well-formed error to "unknown response").
  Date: 2026-09-14

- Decision: Three new exception types (`UnknownHTTPResponseError`, `RequestTimeoutError`, `InvalidPathParameterError`) instead of one sum type.
  Rationale: Existing handlers and the effectful interpreter catch `NotionError` by type; a sum type would force every catch site to change. Separate types keep `NotionError` handlers working and let callers opt in to the others.
  Date: 2026-09-14

- Decision: Implement the JS `validateRequestPath` guard (reject request paths containing `..`).
  Rationale: The MasterPlan brief assumed Servant `Capture` encoding makes it irrelevant, but http-api-data 0.7's default `toEncodedUrlPiece` is `urlEncodeBuilder False . encodeUtf8 . toUrlPiece`, which percent-encodes `/` but leaves `.` unencoded (it is an RFC 3986 unreserved character). `UUID` has an `IsString` instance and uses the default encoding, so `retrievePage methods ".."` would send `GET /v1/pages/..`, which a proxy may normalize to `/v1/`. The check is a few lines in the middleware.
  Date: 2026-09-14

- Decision: OAuth gets its own Servant API type and methods record (`Notion.V1.OAuth.API`, `OAuthMethods`) instead of new fields on `Methods`.
  Rationale: `Notion.V1.API` applies a `Bearer` token header to every route; OAuth routes need `Basic base64(client_id:client_secret)` and are called before any token exists. A separate record also means the `notion-client-effectful` lockstep rule is not triggered. OAuth is not exposed through the effectful package in this plan: token exchange is a one-shot setup step usually performed in a web handler, and callers can use `IO` directly.
  Date: 2026-09-14

- Decision: Milestone order is configuration, then typed errors, then retries, then OAuth and helpers (the MasterPlan's Progress lists retries before errors).
  Rationale: The retry decision reads the typed `APIErrorCode` and the response headers stored on `NotionError`, so errors must exist first.
  Date: 2026-09-14

- Decision: Add `paginateFoldM` and `paginateForM_` next to `paginateAll`.
  Rationale: The JS SDK's `iteratePaginatedAPI` yields items without holding every page in memory; `paginateAll` accumulates a `Vector`. A fold is ten lines and lets callers process a large data source in constant memory. `iterateAllDataSourceRows` stays with EP-5 as the MasterPlan assigns.
  Date: 2026-09-14

- Decision: Expose the runtime to non-Servant callers through explicit, exported interfaces: `withRetries :: ClientConfig -> Method -> Text -> IO a -> IO a` (retries any `IO` action that throws `NotionError`), `notionErrorFromResponse :: Status -> ResponseHeaders -> ByteString -> SomeException` and `buildRequestError` (typed error from raw status, headers and body, shared with the Servant path through `fromClientError`), `responseTimeoutFor :: ClientConfig -> ResponseTimeout`, and a `RequestContext` record (config, `Manager`, `BaseUrl`, full `Authorization` value) with `requestContextFor` and `standardHeaders`, which `makeMethodsWithEnv` also uses internally.
  Rationale: `docs/plans/14-stream-session-updates-over-server-sent-events.md` opens SSE streams with plain http-client and fills a `StreamEnv {manager, baseUrl, authorization, notionVersion, openTimeout, extraHeaders, retryOpen, responseError}`; each of those fields must come from this plan without copying logic. The coordinator requested exact names. `Method` is http-types' `ByteString` alias (use `methodPost`), not `StdMethod`, because servant's `requestMethod` already has that type.
  Date: 2026-09-14

- Decision: No default logger (the JS SDK logs WARN to the console by default); `stderrLogger` is provided for opt-in.
  Rationale: A Haskell library should not write to stderr unless asked.
  Date: 2026-09-14


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

### The repository

`notion-client` is a Haskell library at the repository root (Cabal package file `notion-client.cabal`, version 0.7.0.2, GHC 9.12, language `GHC2024`). `cabal.project` lists two packages: `.` and `notion-client-effectful`. Build everything with `cabal build all`; run the test suite with `cabal test`. A pre-commit hook runs `treefmt` (ormolu-style formatting) and may rewrite files, which then need re-staging.

All library modules use the default extensions `DuplicateRecordFields`, `OverloadedLabels`, `OverloadedStrings` and `RecordWildCards` (see the `library` stanza of `notion-client.cabal`). JSON instances are either generic with `aesonOptions` from `src/Notion/Prelude.hs` (which converts `camelCase` field names to `snake_case` and strips a trailing underscore, so `type_` becomes `"type"` and `requestId` becomes `"request_id"`) or hand-written with `LambdaCase` and `Object o -> ... o .: "field"` patterns. Modules with a record field named `id` import `Prelude hiding (id)`. `Notion.Prelude` re-exports `Text`, `Value`, `Natural`, `Vector`, `ByteString` (lazy), `Generic`, `FromJSON`/`ToJSON`, and the Servant combinators (`:>`, `:<|>`, `Capture`, `ReqBody`, `Post`, `Header'`, `Required`, `Strict`, `JSON`, ...).

### How requests are made today

Servant is a library in which an HTTP API is described as a Haskell type; `servant-client` derives one client function per route from that type. In `src/Notion/V1.hs`:

- `type API` (line 297) is `Header' [Required, Strict] "Authorization" Text :> Header' [Required, Strict] "Notion-Version" Text :> (Databases.API :<|> DataSources.API :<|> ...)`. Because both headers are required, the derived client takes two `Text` arguments before any route.
- `getClientEnv :: Text -> IO ClientEnv` (line 69) parses a base URL such as `"https://api.notion.com/v1"` and creates a TLS connection `Manager`. A `ClientEnv` (from `Servant.Client`) bundles the `Manager`, the `BaseUrl`, an optional cookie jar, a `makeClientRequest :: BaseUrl -> Request -> IO Network.HTTP.Client.Request` hook and a `middleware :: (Request -> ClientM Response) -> Request -> ClientM Response` hook.
- `makeMethods :: ClientEnv -> Text -> Methods` (line 79) hard-codes `notionVersion = "2026-03-11"` (line 86), builds `authorization = "Bearer " <> token` (line 138), and pattern-binds every route function out of `Client.hoistClient @API Proxy run (Client.client @API Proxy) authorization notionVersion` (line 136). The nesting of the `:<|>` pattern mirrors the `API` type exactly.
- `run :: Client.ClientM a -> IO a` (line 140) calls `runClientM`; on `Left err` it throws `NotionError` if `parseNotionError err` succeeds, otherwise it rethrows the servant `ClientError`.
- `data Methods` (line 166) is a record of `IO` functions, one per endpoint. This plan does not add, remove or change any `Methods` field.

`src/Notion/V1/Error.hs` defines:

```haskell
data NotionError = NotionError
  { object :: Text,
    status :: Natural,
    code :: Text,
    message :: Text,
    details :: Maybe Value
  }
  deriving stock (Generic, Show)
instance Exception NotionError
-- FromJSON / ToJSON are generic with aesonOptions
parseNotionError :: Client.ClientError -> Maybe NotionError  -- decodes FailureResponse bodies only
```

`src/Notion/V1/ListOf.hs` defines the paginated envelope `data ListOf a = List {results :: Vector a, nextCursor :: Maybe Text, hasMore :: Bool, type_ :: Maybe Text, object :: Maybe Text}` with a hand-written `FromJSON`. `src/Notion/V1/Pagination.hs` exports `paginateAll :: (Maybe Text -> IO (ListOf a)) -> IO (Vector a)` and `paginateCollect`.

Relevant servant-client facts, verified in the servant checkout registered in Mori (`mori registry show haskell-servant/servant --full`, version 0.20.3.0, files `servant-client-core/src/Servant/Client/Core/ClientError.hs`, `Request.hs`, `Response.hs`, `servant-client/src/Servant/Client/Internal/HttpClient.hs`):

- `data ClientError = FailureResponse (RequestF () (BaseUrl, ByteString)) Response | DecodeFailure Text Response | UnsupportedContentType MediaType Response | InvalidContentTypeHeader Response | ConnectionError SomeException`.
- `RequestF` has fields `requestPath`, `requestQueryString`, `requestBody`, `requestAccept`, `requestHeaders :: Seq Header`, `requestHttpVersion`, `requestMethod :: Method` (`Method` is a `ByteString` such as `"GET"` from `http-types`). It has a `Bifunctor` instance. `Servant.Client.Core.Request` is `RequestF RequestBody Builder`; `defaultRequest` is exported from `Servant.Client.Core`.
- `ResponseF a` has `responseStatusCode :: Status`, `responseHeaders :: Seq Header`, `responseHttpVersion`, `responseBody :: a`.
- `performRequest` throws `FailureResponse` for any non-2xx status before looking at content type, so a Cloudflare HTML 403 arrives as `FailureResponse`. http-client exceptions are wrapped as `ConnectionError (SomeException (e :: HttpException))`.
- `runRequestAcceptStatus` calls the `ClientEnv`'s `middleware` around the real request; response-body decoding (`DecodeFailure`) happens afterwards, outside the middleware.
- `ClientM` derives `MonadIO`, `MonadError ClientError` and `MonadReader ClientEnv` (use `Control.Monad.Reader.ask` and `Control.Monad.Error.Class.throwError`/`catchError` from `mtl`).
- `ClientMiddleware` is not re-exported by `Servant.Client`; write its type out.

### The effectful companion package

`notion-client-effectful/src/Notion/V1/Effectful/Effect.hs` defines a `Notion` GADT with one constructor per `Methods` field; `Interpreter.hs` has `runNotion :: (IOE :> es, Error NotionError :> es) => Methods -> Eff (Notion : es) a -> Eff es a`, which runs each `Methods` function under `Exception.try` and re-raises only `NotionError` through the `Error` effect (function `runIO`). The lockstep rule (every change to a `Methods` field is mirrored there in the same commit) is not triggered by this plan because `Methods` does not change. Only its Haddock and `notion-client-effectful/README.md` need a sentence about the new exception types, which remain `IO` exceptions.

### Tests

`tasty/Main.hs` (2298 lines) assembles `tests :: IO TestTree` ending in `testGroup "Notion Client Tests" [jsonParsingTests, jsonSerializationTests, propertyValueTests, fileUploadTests, basicIntegration, markdownE2E, pageE2E, databaseE2E, viewE2E]` (around line 159). Per the MasterPlan, this plan adds new modules `tasty/RuntimeTests.hs`, `tasty/OAuthTests.hs` and `tasty/HelpersTests.hs`, each exporting `tests :: TestTree`, plus a non-test helper module `tasty/FakeNotion.hs`. Each is listed under a new `other-modules` field of `test-suite tasty` in `notion-client.cabal`, and each `tests` value is added to that list in `tasty/Main.hs` as `RuntimeTests.tests`, etc. (imported qualified). Existing tests that touch this plan: `testParseNotionError` (line 374, asserts `code` equals `"validation_error"`), and `testPaginateAll` (line 1462, constructs `ListOf.List` records).

Other callers to update: `notion-client-example/DatabaseDemo.hs` line 266–275 prints `Text.unpack (code notionErr)`; `README.md` line 128–134 concatenates `code e` as `Text`.

### The JS SDK behavior to port (verified against `/Users/shinzui/Keikaku/hub/notion-sdk-js`, commit 978d690, package version 5.26.0)

Defaults, from `src/constants.ts`:

```typescript
export const DEFAULT_BASE_URL = "https://api.notion.com"      // client appends "/v1/"
export const DEFAULT_TIMEOUT_MS = 60_000
export const DEFAULT_MAX_RETRIES = 2
export const DEFAULT_INITIAL_RETRY_DELAY_MS = 1_000
export const DEFAULT_MAX_RETRY_DELAY_MS = 60_000
```

From `src/Client.ts`: options are `{auth, timeoutMs, baseUrl, logLevel (default WARN), logger, notionVersion, fetch, agent, retry?: RetryOptions | false}`; `retry: false` sets all three retry numbers to 0. Every request sends `Notion-Version` and `user-agent: notionhq-client/<version>` (line 184). The retry loop (`executeWithRetry`, line 435) catches only client errors, logs `"request fail"` at WARN with `{code, message, attempt, requestId}`, and if `attempt < maxRetries && canRetry(error, method)` logs `"retrying request"` at INFO with `{method, path, attempt: attempt + 1, delayMs}`, sleeps, and tries again. The retry rules (lines 573–650):

```typescript
private canRetry(error: unknown, method: Method): boolean {
  if (!APIResponseError.isAPIResponseError(error)) return false
  if (error.code === APIErrorCode.RateLimited || error.code === APIErrorCode.ServiceOverload) return true
  const isIdempotent = method === "get" || method === "delete"
  if (isIdempotent) {
    return error.code === APIErrorCode.InternalServerError || error.code === APIErrorCode.ServiceUnavailable
  }
  return false
}
private calculateRetryDelay(error: unknown, attempt: number): number {
  if (APIResponseError.isAPIResponseError(error)) {
    const retryAfterMs = this.parseRetryAfterHeader(error.headers)
    if (retryAfterMs !== undefined) return Math.min(retryAfterMs, this.#maxRetryDelayMs)
  }
  const baseDelay = this.#initialRetryDelayMs * Math.pow(2, attempt)
  const jitter = Math.random()                       // in [0, 1)
  return Math.min(baseDelay * jitter + baseDelay / 2, this.#maxRetryDelayMs)
}
private parseRetryAfterHeader(headers: unknown): number | undefined {
  const retryAfterValue = getResponseHeader(headers, "retry-after")
  if (!retryAfterValue) return undefined
  const seconds = parseInt(retryAfterValue, 10)       // leading-digits parse: "1.5" -> 1
  if (!isNaN(seconds) && seconds >= 0) return seconds * 1000
  const date = Date.parse(retryAfterValue)            // HTTP-date
  if (!isNaN(date)) { const delayMs = date - Date.now(); return delayMs > 0 ? delayMs : 0 }
  return undefined
}
```

Note that the decision is keyed on the error code in the JSON body, not the HTTP status, and that `gateway_timeout`, unknown codes, non-JSON responses and timeouts are never retried.

From `src/errors.ts`: the 14 API error codes are `unauthorized`, `restricted_resource`, `object_not_found`, `rate_limited`, `invalid_json`, `invalid_request_url`, `invalid_request`, `invalid_beta`, `validation_error`, `conflict_error`, `internal_server_error`, `service_overload`, `service_unavailable`, `gateway_timeout`. `buildRequestError` (line 362) parses the body; if it is a JSON object with a string `message` and a known `code`, it builds an `APIResponseError` with `status` (HTTP), `headers`, `body` (raw text), `additional_data` (`Record<string, string | string[]>`), `request_id` (body `request_id`, else the `x-notion-request-id` header) and `ray_id` (the `cf-ray` header). Otherwise it builds an `UnknownHTTPResponseError` whose default message is (line 393):

```typescript
const base = `Request to Notion API failed with status: ${status}`
if (ray_id === undefined || request_id !== undefined) return base
const contentTypeNote = contentType !== undefined ? ` (content-type: ${contentType})` : ""
const blockedRequestNote = status === 403 ? " This may mean the request was blocked by a network security rule." : ""
return `${base}. The response was returned by Notion's edge proxy before reaching ` +
  `the Notion API${contentTypeNote}.${blockedRequestNote} Cloudflare Ray ID: ` +
  `${ray_id}. Include this ID when contacting Notion support.`
```

`RequestTimeoutError` has message `"Request to Notion API has timed out"`. `validateRequestPath` (line 156) throws `InvalidPathParameterError` if the path contains `..`, or if it matches `/%2e/i` and its `decodeURIComponent` contains `..`; the message is `Request path "<path>" contains path traversal sequence ".."` (or `... contains encoded path traversal sequence`).

`RequestStatusResponse`, from `src/api-endpoints/common.ts` line 1998 (used by comments, file uploads, views, data-source queries and search lists):

```typescript
export type RequestStatusResponse = {
  type: "complete" | "incomplete"
  incomplete_reason?: "query_result_limit_reached"
}
```

OAuth, from `src/api-endpoints/oauth.ts` (all `POST`, paths relative to `/v1/`) and `src/Client.ts` lines 1000–1060 (each call passes `auth: {client_id, client_secret}`, which `buildAuthHeader` turns into `authorization: Basic base64("<client_id>:<client_secret>")`; the normal retry loop and `Notion-Version` header still apply):

```typescript
// POST oauth/token
type OauthTokenBodyParameters =
  | { grant_type: "authorization_code"; code: string; redirect_uri?: string; external_account?: { key: string; name: string } }
  | { grant_type: "refresh_token"; refresh_token: string }
export type OauthTokenResponse = {
  access_token: string
  token_type: "bearer"
  refresh_token: string | null
  bot_id: string
  workspace_icon: string | null
  workspace_name: string | null
  workspace_id: string
  owner:
    | { type: "user"
        user:
          | { type: "person"; person: { email: string }; name: string | null; avatar_url: string | null; id: string; object: "user" }
          | { id: string; object: "user" } }            // PartialUserObjectResponse
    | { type: "workspace"; workspace: true }
  duplicated_template_id: string | null
  request_id?: string
}
// POST oauth/revoke      body { token: string }  response { request_id?: string }
// POST oauth/introspect  body { token: string }  response { active: boolean; scope?: string; iat?: number; request_id?: string }
```

ID helpers, from `src/helpers.ts` lines 483–572:

```typescript
export function extractNotionId(urlOrId: string): string | null {
  const trimmed = urlOrId.trim()
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(trimmed)) return trimmed.toLowerCase()
  if (/^[0-9a-f]{32}$/i.test(trimmed)) return formatUuid(trimmed)
  const pathMatch = trimmed.match(/\/[^/?#]*-([0-9a-f]{32})(?:[/?#]|$)/i)
  if (pathMatch && pathMatch[1]) return formatUuid(pathMatch[1])
  const queryMatch = trimmed.match(/[?&](?:p|page_id|database_id)=([0-9a-f]{32})/i)
  if (queryMatch && queryMatch[1]) return formatUuid(queryMatch[1])
  const anyMatch = trimmed.match(/([0-9a-f]{32})/i)
  if (anyMatch && anyMatch[1]) return formatUuid(anyMatch[1])
  return null
}
// formatUuid lowercases and inserts hyphens 8-4-4-4-12
export function extractDatabaseId(databaseUrl: string) { return extractNotionId(databaseUrl) }
export function extractPageId(pageUrl: string) { return extractNotionId(pageUrl) }
export function extractBlockId(urlWithBlock: string): string | null {
  const blockMatch = urlWithBlock.match(/#(?:block-)?([0-9a-f]{32})/i)   // note: not trimmed
  return blockMatch && blockMatch[1] ? formatUuid(blockMatch[1]) : null
}
```

JS-only mechanics this plan deliberately does not port (per the MasterPlan's exclusions): `warnUnknownParams`, `fetch`/`agent` injection, per-request `auth` override on every endpoint (callers can build a second `Methods` with another token cheaply), and the `isFull*` guards.

### Downstream consumers of this plan

- `docs/plans/8-add-comment-mutation-async-task-and-meeting-notes-endpoints.md` (EP-3) reuses `APIErrorCode` for the failed `AsyncTask` error object.
- `docs/plans/9-add-view-queries-and-typed-view-configuration.md` (EP-4) and `docs/plans/10-type-data-source-database-and-search-results-and-close-query-and-filter-gaps.md` (EP-5) consume `ListOf.requestStatus` and `RequestStatus`.
- `docs/plans/14-stream-session-updates-over-server-sent-events.md` (MasterPlan 2, EP-3) opens an SSE stream with a hand-written http-client request and must reuse this plan's `ClientConfig`, `notionVersion`, `userAgent`, `applyTimeout`, `withRetries` (retry before the stream opens) and `buildRequestError`. The runtime is therefore designed so none of these need a servant `ClientM`.

### ADRs

This repository has no `docs/adr/` directory; no relevant ADR exists (verified with `ls docs`). The MasterPlan lists "the retry policy" as a future ADR; this plan records the needed facts in its Decision Log for that distillation.


## Plan of Work

The work adds four library modules (`Notion.V1.Client`, `Notion.V1.Retry`, `Notion.V1.OAuth`, `Notion.V1.Helpers`), rewrites `Notion.V1.Error`, and makes small edits to `Notion.V1`, `Notion.V1.ListOf` and `Notion.V1.Pagination`. Module dependencies are acyclic: `Error` imports nothing new; `Retry` imports `Error`; `Client` imports `Error` and `Retry`; `Notion.V1` and `OAuth` import `Client`; `Helpers` imports only `Common`.


### Milestone 1: Configuration record and `makeMethodsWith`

Scope: introduce `ClientConfig` and constructors that honor it for API version, base URL, timeout and `User-Agent`, with no change to error handling yet. At the end, `makeMethodsWith defaultClientConfig {notionVersion = "2025-09-03"} manager token` sends `Notion-Version: 2025-09-03`, and existing code using `makeMethods` compiles unchanged. Proof: `cabal test` shows new `Runtime / Configuration` tests passing, which record the headers a scripted fake received.

First edit `notion-client.cabal`. In the `library` stanza raise `servant-client` to `>=0.20.2 && <0.21` and add these `build-depends` (versions checked against the local Hackage index on 2026-09-14: http-client 0.7.19, http-types 0.12.6, random 1.3.1, base64-bytestring 1.2.1.0, servant-client-core 0.20.3.0, mtl 2.3.2 ships with GHC 9.12):

```text
    , base64-bytestring         >=1.2      && <1.3
    , http-client               >=0.7.16   && <0.8
    , http-types                >=0.12     && <0.13
    , mtl                       >=2.2      && <2.4
    , random                    >=1.2      && <1.4
    , servant-client-core       >=0.20.2   && <0.21
```

Add `Notion.V1.Client`, `Notion.V1.Retry` (created in Milestone 3; add it then), `Notion.V1.OAuth` and `Notion.V1.Helpers` (Milestone 4) to `exposed-modules` as each is created, and add `Paths_notion_client` to both `other-modules` and a new `autogen-modules:` field so the version is available for the `User-Agent`. In `test-suite tasty` add `other-modules: FakeNotion RuntimeTests` (later also `OAuthTests HelpersTests`) and `build-depends` `http-types`, `mtl`, `servant-client-core`, `time`.

Create `src/Notion/V1/Client.hs`:

```haskell
-- | Client runtime: configuration, timeout, retries, logging.
module Notion.V1.Client
  ( -- * Configuration
    ClientConfig (..),
    defaultClientConfig,
    legacyClientConfig,
    defaultBaseUrl,
    defaultNotionVersion,
    RetryOptions (..),
    defaultRetryOptions,
    noRetries,

    -- * Logging
    LogLevel (..),
    Logger,
    stderrLogger,

    -- * Runtime building blocks (also used by non-Servant requests)
    RequestContext (..),
    requestContextFor,
    standardHeaders,
    configureClientEnv,
    notionMiddleware,
    applyTimeout,
    responseTimeoutFor,
    runClientWith,
    withRetries,
    logWith,
  )
where

data LogLevel = LogDebug | LogInfo | LogWarn | LogError
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | Receives a level, a message, and structured extra fields
-- (keys match the JS SDK: "method", "path", "attempt", "delayMs", "code", "message", "requestId").
type Logger = LogLevel -> Text -> [(Text, Value)] -> IO ()

data ClientConfig = ClientConfig
  { -- | Base URL including the @/v1@ path. Used by 'makeMethodsWith'; ignored by
    -- 'makeMethodsWithEnv', where the 'ClientEnv' already carries a base URL.
    apiBaseUrl :: BaseUrl,
    -- | Value of the @Notion-Version@ header.
    notionVersion :: Text,
    -- | Connect + response-header timeout. 'Nothing' leaves the Manager's own setting.
    timeout :: Maybe NominalDiffTime,
    retryOptions :: RetryOptions,
    -- | Sent as @User-Agent@ when 'Just'.
    userAgent :: Maybe Text,
    logger :: Maybe Logger,
    -- | Messages below this level are not passed to 'logger'.
    logLevel :: LogLevel
  }

defaultBaseUrl :: BaseUrl
defaultBaseUrl = BaseUrl Https "api.notion.com" 443 "/v1"

defaultNotionVersion :: Text
defaultNotionVersion = "2026-03-11"

defaultClientConfig :: ClientConfig
defaultClientConfig =
  ClientConfig
    { apiBaseUrl = defaultBaseUrl,
      notionVersion = defaultNotionVersion,
      timeout = Just 60,
      retryOptions = defaultRetryOptions,
      userAgent = Just ("notion-client-haskell/" <> Text.pack (showVersion Paths_notion_client.version)),
      logger = Nothing,
      logLevel = LogWarn
    }

-- | What 'makeMethods' uses: like the default but keeps the Manager's timeout.
legacyClientConfig :: ClientConfig
legacyClientConfig = defaultClientConfig {timeout = Nothing}
```

Field names avoid `baseUrl` and `manager`, because `Servant.Client` exports `ClientEnv (..)` with those field names and, with `DuplicateRecordFields` on GHC 9.12, a record update such as `cfg {baseUrl = ...}` would be ambiguous in user code that imports both.

`RetryOptions` is defined in `Notion.V1.Retry` (Milestone 3) and re-exported here. To keep Milestone 1 compiling on its own, define it in `Client.hs` first and move it in Milestone 3, or create `Retry.hs` with just the record now; either is fine:

```haskell
data RetryOptions = RetryOptions
  { maxRetries :: Natural,               -- 0 disables retries
    initialRetryDelay :: NominalDiffTime, -- base of exponential back-off
    maxRetryDelay :: NominalDiffTime      -- caps retry-after and back-off
  }
  deriving stock (Eq, Show)

defaultRetryOptions :: RetryOptions
defaultRetryOptions = RetryOptions {maxRetries = 2, initialRetryDelay = 1, maxRetryDelay = 60}

noRetries :: RetryOptions
noRetries = RetryOptions {maxRetries = 0, initialRetryDelay = 0, maxRetryDelay = 0}
```

`stderrLogger` writes one line per call: `notion-client <level>: <message> <extra as a JSON object>` using `Data.Text.IO.hPutStrLn stderr`. `logWith :: ClientConfig -> LogLevel -> Text -> [(Text, Value)] -> IO ()` calls `logger` only when it is `Just` and the level is `>= logLevel`.

`responseTimeoutFor :: ClientConfig -> ResponseTimeout` returns `responseTimeoutMicro (round (t * 1000000))` when `timeout = Just t` and `responseTimeoutDefault` when `Nothing`. `applyTimeout :: ClientConfig -> Network.HTTP.Client.Request -> Network.HTTP.Client.Request` sets `responseTimeout = responseTimeoutFor cfg` when `timeout` is `Just`, otherwise returns the request unchanged (so a timeout set by the caller's own `makeClientRequest` survives).

`RequestContext` bundles everything needed to send a request identically to `Methods`, whether through Servant or a hand-written http-client request (the SSE plan):

```haskell
data RequestContext = RequestContext
  { contextConfig :: ClientConfig,
    contextManager :: Manager,
    -- | The effective base URL (the ClientEnv's), e.g. https://api.notion.com/v1
    contextBaseUrl :: BaseUrl,
    -- | Full Authorization header value, e.g. "Bearer secret_..." or "Basic ..."
    contextAuthorization :: Text
  }

-- | Build the context from the same inputs as 'makeMethodsWithEnv'
-- (manager and base URL from the ClientEnv; authorization = "Bearer " <> token).
requestContextFor :: ClientConfig -> ClientEnv -> Text -> RequestContext

-- | Authorization, Notion-Version and (when configured) User-Agent headers.
standardHeaders :: RequestContext -> [Header]
```

Field names carry a `context` prefix so they do not collide with `ClientEnv`'s `manager`/`baseUrl` or servant `RequestF`'s `request*` fields.

`configureClientEnv :: ClientConfig -> ClientEnv -> ClientEnv` returns the environment with two fields replaced, preserving the caller's customizations:

```haskell
configureClientEnv cfg env =
  env
    { makeClientRequest = \base req -> applyTimeout cfg <$> makeClientRequest env base req,
      middleware = \app -> notionMiddleware cfg (middleware env app)
    }
```

The caller's own middleware runs inside ours, so our retries re-invoke it; that is what makes the fake server in the tests work.

In Milestone 1 `notionMiddleware :: ClientConfig -> ((Request -> ClientM Response) -> Request -> ClientM Response)` only adds the `User-Agent` header (`req {requestHeaders = requestHeaders req Seq.|> ("User-Agent", encodeUtf8 ua)}`) and calls `app`. Milestones 2 and 3 extend it.

`runClientWith :: ClientEnv -> ClientM a -> IO a` takes an already configured environment, runs `runClientM`, and in Milestone 1 behaves like today's `run` (throw `NotionError` if `parseNotionError` succeeds, else the `ClientError`).

Edit `src/Notion/V1.hs`:

- Export `makeMethodsWith`, `makeMethodsWithEnv`, and re-export `ClientConfig (..)`, `defaultClientConfig`, `legacyClientConfig`, `defaultBaseUrl`, `defaultNotionVersion`, `RetryOptions (..)`, `defaultRetryOptions`, `noRetries`, `LogLevel (..)`, `Logger`, `stderrLogger`, `RequestContext (..)`, `requestContextFor`, `standardHeaders`, `responseTimeoutFor`, `withRetries` from `Notion.V1.Client`.
- Rename the body of `makeMethods` to `makeMethodsWithEnv :: ClientConfig -> ClientEnv -> Text -> Methods`. In its `where` block bind `context = requestContextFor config clientEnv token`; replace `notionVersion = "2026-03-11"` with the config's `notionVersion` and `authorization = "Bearer " <> token` with `contextAuthorization context` (so the SSE plan can later build its `StreamEnv` from the same `context`), and replace the local `run` with `run = runClientWith (configureClientEnv config clientEnv)`. Bind the configured environment once in a `where` so it is not rebuilt per call. The big `:<|>` pattern is untouched.
- Add:

```haskell
-- | Build 'Methods' from a configuration, a connection manager (for example
-- from 'Network.HTTP.Client.TLS.newTlsManager') and an API token.
makeMethodsWith :: ClientConfig -> Manager -> Text -> Methods
makeMethodsWith config manager = makeMethodsWithEnv config (Client.mkClientEnv manager config.apiBaseUrl)

-- | Unchanged type; now retries and uses typed errors (see CHANGELOG).
makeMethods :: ClientEnv -> Text -> Methods
makeMethods = makeMethodsWithEnv legacyClientConfig
```

`getClientEnv` is unchanged. Update the module header example to show `makeMethodsWith`.

Create `tasty/FakeNotion.hs`, a scripted stand-in for Notion that never touches the network. It builds a `ClientEnv` whose `middleware` ignores the real HTTP application, records each request, and answers from a list:

```haskell
module FakeNotion (Recorded (..), FakeReply (..), fakeClientEnv, jsonReply) where

data Recorded = Recorded {method :: Method, path :: LBS.ByteString, headers :: [Header]}
data FakeReply = FakeReply {status :: Int, replyHeaders :: [Header], body :: LBS.ByteString}

jsonReply :: Int -> LBS.ByteString -> FakeReply
jsonReply s = FakeReply s [("Content-Type", "application/json")]

fakeClientEnv :: [FakeReply] -> IO (ClientEnv, IORef [Recorded])
fakeClientEnv script = do
  manager <- newManager defaultManagerSettings
  remaining <- newIORef script
  recorded <- newIORef []
  let base = BaseUrl Https "api.notion.com" 443 "/v1"
      mw _realApp req = do
        liftIO $ modifyIORef' recorded (<> [Recorded (requestMethod req) (toLazyByteString (requestPath req)) (toList (requestHeaders req))])
        next <- liftIO $ atomicModifyIORef' remaining (\case [] -> ([], Nothing); r : rs -> (rs, Just r))
        FakeReply {..} <- maybe (liftIO (ioError (userError "FakeNotion: script exhausted"))) pure next
        let resp = Response (mkStatus status "") (Seq.fromList replyHeaders) http11 body
        if status >= 200 && status < 300
          then pure resp
          else throwError (FailureResponse (bimap (const ()) (\p -> (base, LBS.toStrict (toLazyByteString p))) req) resp)
  pure ((mkClientEnv manager base) {middleware = mw}, recorded)
```

Create `tasty/RuntimeTests.hs` with `tests = testGroup "Runtime" [configurationTests]` where `configurationTests` contains:

- "makeMethods sends default Notion-Version, Bearer token and User-Agent": fake replies `jsonReply 200 userJson` (a bot user fixture, below); call `retrieveMyUser (makeMethods env "secret_tanaka")`; assert the recorded headers contain `("Authorization", "Bearer secret_tanaka")`, `("Notion-Version", "2026-03-11")`, and a `User-Agent` starting with `notion-client-haskell/`; assert the path is `/users/me`.
- "makeMethodsWithEnv honors a configured Notion-Version": same with `defaultClientConfig {notionVersion = "2025-09-03"}`.
- "applyTimeout sets responseTimeout": `responseTimeout (applyTimeout defaultClientConfig {timeout = Just 5} defaultRequest) @?= responseTimeoutMicro 5000000`, and `timeout = Nothing` leaves `responseTimeoutDefault` (here `defaultRequest` is `Network.HTTP.Client.defaultRequest`, imported qualified to avoid the servant name).
- "standardHeaders match what Methods sends": for `requestContextFor defaultClientConfig env "secret_tanaka"`, `standardHeaders` contains exactly the `Authorization`, `Notion-Version` and `User-Agent` values recorded in the first test, and `contextBaseUrl` equals the fake env's base URL.

User fixture (made-up name):

```json
{"object":"user","id":"6f1c2b9e-4d3a-4e8f-9b7c-2a1d0e5f3c4b","name":"Sato Kenji Bot","avatar_url":null,"type":"bot","bot":{"owner":{"type":"workspace","workspace":true},"workspace_name":"Sato Kenji's Workspace"}}
```

Register in `tasty/Main.hs`: `import RuntimeTests qualified` and add `RuntimeTests.tests,` to the top-level list.


### Milestone 2: Typed errors and `RequestStatus`

Scope: every failed request surfaces as `NotionError` (with typed code and response metadata), `UnknownHTTPResponseError`, `RequestTimeoutError`, or (unchanged) a servant `ClientError` for decoding problems. `ListOf` exposes `requestStatus`. Proof: `Runtime / Errors` tests pass, including a 403 HTML Cloudflare response that produces the edge-proxy message.

Rewrite `src/Notion/V1/Error.hs`:

```haskell
module Notion.V1.Error
  ( APIErrorCode (..),
    apiErrorCodeText,
    parseAPIErrorCode,
    NotionError (..),
    HttpErrorResponse (..),
    UnknownHTTPResponseError (..),
    RequestTimeoutError (..),
    InvalidPathParameterError (..),
    unknownResponseMessage,
    buildRequestError,
    notionErrorFromResponse,
    fromClientError,
    parseNotionError,
    lookupHeader,
  )
where

data APIErrorCode
  = Unauthorized
  | RestrictedResource
  | ObjectNotFound
  | RateLimited
  | InvalidJSON
  | InvalidRequestURL
  | InvalidRequest
  | InvalidBeta
  | ValidationError
  | ConflictError
  | InternalServerError
  | ServiceOverload
  | ServiceUnavailable
  | GatewayTimeout
  | -- | A code this library does not know yet, carried verbatim.
    UnknownErrorCode Text
  deriving stock (Eq, Show)

apiErrorCodeText :: APIErrorCode -> Text      -- Unauthorized -> "unauthorized", ..., UnknownErrorCode t -> t
parseAPIErrorCode :: Text -> APIErrorCode     -- inverse; unrecognized -> UnknownErrorCode
instance IsString APIErrorCode where fromString = parseAPIErrorCode . Text.pack
instance FromJSON APIErrorCode  -- withText, never fails on a string
instance ToJSON APIErrorCode    -- String . apiErrorCodeText

-- | Metadata of the HTTP response an error came from.
data HttpErrorResponse = HttpErrorResponse
  { httpStatus :: Int,
    errorHeaders :: ResponseHeaders,       -- from http-types; header names are case-insensitive
    notionRequestId :: Maybe Text,         -- "x-notion-request-id" header
    rayId :: Maybe Text,                   -- "cf-ray" header
    errorBody :: ByteString                -- raw body (lazy)
  }
  deriving stock (Eq, Show)

-- | A well-formed Notion API error response.
data NotionError = NotionError
  { object :: Text,                        -- "error"
    status :: Natural,                     -- body "status", else HTTP status
    code :: APIErrorCode,
    message :: Text,
    requestId :: Maybe Text,               -- body "request_id", else x-notion-request-id header
    additionalData :: Maybe Value,         -- body "additional_data"
    details :: Maybe Value,                -- legacy field, kept for compatibility
    response :: Maybe HttpErrorResponse    -- Nothing when decoded from bare JSON
  }
  deriving stock (Eq, Show)
instance Exception NotionError

newtype UnknownHTTPResponseError = UnknownHTTPResponseError {unknownResponse :: HttpErrorResponse}
  deriving stock (Eq, Show)
instance Exception UnknownHTTPResponseError where
  displayException = Text.unpack . unknownResponseMessage   -- see below

data RequestTimeoutError = RequestTimeoutError deriving stock (Eq, Show)
instance Exception RequestTimeoutError where displayException _ = "Request to Notion API has timed out"

newtype InvalidPathParameterError = InvalidPathParameterError {invalidPath :: Text} deriving stock (Eq, Show)
instance Exception InvalidPathParameterError
```

Also export `unknownResponseMessage :: UnknownHTTPResponseError -> Text`, a direct port of `buildUnknownResponseMessage` above (content type from the `content-type` header).

`NotionError`'s `FromJSON` becomes hand-written: require `code` (string, parsed with `parseAPIErrorCode`) and `message` (string); `object` defaults to `"error"`, `status` to `0`, the rest are optional (`request_id`, `additional_data`, `details`), `response = Nothing`. `ToJSON` emits the body fields in snake_case and omits `response` and `Nothing` fields.

`buildRequestError :: Int -> ResponseHeaders -> ByteString -> Either UnknownHTTPResponseError NotionError` builds `HttpErrorResponse` (header lookup via `lookupHeader :: HeaderName -> ResponseHeaders -> Maybe Text`, which decodes UTF-8 leniently), tries `Aeson.decode` into `NotionError`, and on success fills `response = Just meta`, replaces `status` with the HTTP status when the body had none (`0`), and sets `requestId` to the body value or else `notionRequestId`. On failure it returns `Left (UnknownHTTPResponseError meta)`. It takes plain http-types values so the SSE plan can call it on a raw http-client response. Also export the exception-valued convenience the SSE plan's `StreamEnv.responseError` needs:

```haskell
-- | Typed exception for a non-2xx response: a NotionError when the body is a Notion
-- error envelope, else an UnknownHTTPResponseError. 'throwIO' on the result can be
-- caught as either type (and is retried by 'withRetries' when it is a NotionError).
notionErrorFromResponse :: Status -> ResponseHeaders -> ByteString -> SomeException
notionErrorFromResponse s hs b = either toException toException (buildRequestError (statusCode s) hs b)
```

`fromClientError :: ClientError -> SomeException`:

- `FailureResponse _ resp` → `notionErrorFromResponse (responseStatusCode resp) (toList (responseHeaders resp)) (responseBody resp)` (the Servant path and the raw path share one builder).
- `ConnectionError e` where `fromException e` is `Just (HttpExceptionRequest _ c)` and `c` is `ResponseTimeout` or `ConnectionTimeout` → `toException RequestTimeoutError`.
- anything else → `toException` of the original `ClientError`.

`parseNotionError :: ClientError -> Maybe NotionError` stays exported (now implemented via `buildRequestError`, returning `Just` only for the `Right` case).

In `src/Notion/V1/Client.hs`, change `runClientWith` to `runClientM m env >>= either (Exception.throwIO . fromClientError) pure` (`throwIO` on a `SomeException` rethrows the wrapped exception, so `catch @NotionError` still matches). Extend `notionMiddleware` so it converts inside the middleware as well: run `app req`, and on a `ClientError` whose conversion is a `NotionError`, `UnknownHTTPResponseError` or `RequestTimeoutError`, throw that with `liftIO (throwIO ...)`; rethrow other `ClientError`s with `throwError`. (Milestone 3 wraps this in the retry loop; doing the conversion here keeps `withRetries` independent of servant.)

Edit `src/Notion/V1/ListOf.hs`:

```haskell
data ListOf a = List
  { results :: Vector a,
    nextCursor :: Maybe Text,
    hasMore :: Bool,
    type_ :: Maybe Text,
    object :: Maybe Text,
    -- | Present on query/list responses that may be truncated server-side.
    requestStatus :: Maybe RequestStatus
  }

data RequestStatus = RequestStatus
  { type_ :: RequestStatusType,
    incompleteReason :: Maybe IncompleteReason
  }
  deriving stock (Eq, Generic, Show)

data RequestStatusType = RequestComplete | RequestIncomplete | UnknownRequestStatusType Text
  deriving stock (Eq, Show)

data IncompleteReason = QueryResultLimitReached | UnknownIncompleteReason Text
  deriving stock (Eq, Show)
```

Hand-written `FromJSON` (and `ToJSON`, so EP-4/EP-5 fixtures can round-trip) for the three new types: `"complete"`/`"incomplete"`/other text, `"query_result_limit_reached"`/other text, object with `type` and optional `incomplete_reason`. In `ListOf`'s parser add `requestStatus <- o .:? "request_status"`. Export `RequestStatus (..)`, `RequestStatusType (..)`, `IncompleteReason (..)`. Constructor names are prefixed (`RequestComplete`) to avoid clashing with other `Complete` constructors elsewhere in the library.

Fix callers: add `requestStatus = Nothing` to the three `ListOf.List` literals in `testPaginateAll` (`tasty/Main.hs` around line 1472); in `notion-client-example/DatabaseDemo.hs` line 271 use `Text.unpack (apiErrorCodeText (code notionErr))` and additionally print `requestId`. `testParseNotionError` needs no change (it compiles through `IsString APIErrorCode`); keep it as the backward-compatibility proof.

Add `errorTests` to `tasty/RuntimeTests.hs`:

- "APIErrorCode round-trips all 14 codes": for each of the 14 wire strings listed above, `apiErrorCodeText (parseAPIErrorCode s) == s`, and `parseAPIErrorCode "brand_new_code" == UnknownErrorCode "brand_new_code"`.
- "buildRequestError parses a Notion error with headers": status 404, headers `[("Content-Type","application/json"),("x-notion-request-id","req-header-1"),("cf-ray","8a1b2c3d4e5f-NRT")]`, body `{"object":"error","status":404,"code":"object_not_found","message":"Could not find page with ID: 5c6a2821-6bb1-4a7e-b6e1-c50111515c3d.","request_id":"b1e0a4c2-7f3d-4e21-9a55-1c2d3e4f5a6b","additional_data":{"integration_name":"Tanaka Hanako Integration"}}` → `Right` with `code = ObjectNotFound`, `requestId = Just "b1e0a4c2-..."` (body wins), `rayId = Just "8a1b2c3d4e5f-NRT"`, `additionalData` present.
- "request_id falls back to the x-notion-request-id header": same without body `request_id` → `requestId = Just "req-header-1"`.
- "Cloudflare HTML 403 becomes UnknownHTTPResponseError": status 403, headers `[("content-type","text/html"),("cf-ray","8a1b2c3d4e5f-NRT")]`, body `<html>blocked</html>` → `Left e` and `unknownResponseMessage e` equals `Request to Notion API failed with status: 403. The response was returned by Notion's edge proxy before reaching the Notion API (content-type: text/html). This may mean the request was blocked by a network security rule. Cloudflare Ray ID: 8a1b2c3d4e5f-NRT. Include this ID when contacting Notion support.`
- "non-JSON 502 without cf-ray has the short message": `Request to Notion API failed with status: 502`.
- "timeouts become RequestTimeoutError": `fromException (fromClientError (ConnectionError (toException (HttpExceptionRequest defaultRequest ResponseTimeout))))` is `Just RequestTimeoutError`.
- "makeMethods throws a typed NotionError": fake script `[FakeReply 400 [json, ("x-notion-request-id","req-9")] validationBody]`; `try @NotionError (retrieveMyUser ...)` gives `code = ValidationError` and `response` with `httpStatus = 400`.
- "ListOf decodes request_status": `{"object":"list","results":[],"next_cursor":null,"has_more":false,"type":"page_or_data_source","page_or_data_source":{},"request_status":{"type":"incomplete","incomplete_reason":"query_result_limit_reached"}}` → `requestStatus = Just (RequestStatus RequestIncomplete (Just QueryResultLimitReached))`; without the key → `Nothing`; `{"type":"partial"}` → `UnknownRequestStatusType "partial"`.


### Milestone 3: Retries, logging and the path guard

Scope: the JS retry policy, implemented as pure functions plus one `IO` combinator reused by both the servant middleware and future non-servant requests. Proof: `Runtime / Retry policy` (pure) and `Runtime / Retry loop` (fake server) tests pass; for example a scripted `429, 200` sequence returns the user and records two requests.

Create `src/Notion/V1/Retry.hs` (move `RetryOptions`, `defaultRetryOptions`, `noRetries` here if they were put in `Client.hs`):

```haskell
module Notion.V1.Retry
  ( RetryOptions (..), defaultRetryOptions, noRetries,
    canRetry, parseRetryAfter, retryDelay, validateRequestPath,
  )
where

-- | JS canRetry: rate_limited and service_overload for any method;
-- internal_server_error and service_unavailable only for GET and DELETE.
canRetry :: Method -> APIErrorCode -> Bool
canRetry method = \case
  RateLimited -> True
  ServiceOverload -> True
  InternalServerError -> idempotent
  ServiceUnavailable -> idempotent
  _ -> False
  where
    idempotent = method == methodGet || method == methodDelete

-- | Parse a retry-after header value at time @now@.
-- Leading ASCII digits (after trimming spaces) are delta-seconds, mirroring JS parseInt
-- ("1.5" -> 1s). Otherwise an IMF-fixdate such as "Wed, 21 Oct 2015 07:28:00 GMT"
-- (format "%a, %d %b %Y %H:%M:%S GMT"); a date in the past gives 0. Anything else: Nothing.
parseRetryAfter :: UTCTime -> ByteString.Strict.ByteString -> Maybe NominalDiffTime

-- | JS calculateRetryDelay. @attempt@ counts from 0; @jitter@ must be in [0, 1).
retryDelay :: RetryOptions -> Natural -> Double -> Maybe NominalDiffTime -> NominalDiffTime
retryDelay RetryOptions {..} attempt jitter = \case
  Just retryAfter -> min retryAfter maxRetryDelay
  Nothing ->
    let base = initialRetryDelay * 2 ^ attempt
     in min (base * realToFrac jitter + base / 2) maxRetryDelay

-- | JS validateRequestPath on the encoded request path.
validateRequestPath :: Text -> Either InvalidPathParameterError ()
```

`validateRequestPath` returns `Left` if the text contains `".."`, or if it contains `%2e` case-insensitively and `Network.HTTP.Types.URI.urlDecode False` of it contains `".."`.

In `src/Notion/V1/Client.hs` add:

```haskell
-- | Run an action that signals API failures by throwing 'NotionError', retrying per
-- 'retryOptions'. @method@ and @path@ are used for the retry rule and log lines.
-- Other exceptions propagate immediately. Usable outside servant (e.g. SSE before the stream opens).
withRetries :: ClientConfig -> Method -> Text -> IO a -> IO a
```

Its loop, starting at `attempt = 0`: `try @NotionError action`. On `Right` return. On `Left e`: log WARN `"request fail"` with `code`, `message`, `attempt`, `requestId`; log DEBUG `"failed response body"` with the body when `response` is present; if `attempt < maxRetries` and `canRetry method e.code`, compute `now <- getCurrentTime`, `jitter <- randomRIO (0, 0.999999)`, `retryAfter = parseRetryAfter now =<< (lookup "retry-after" . errorHeaders =<< e.response)` (http-types header names are case-insensitive `CI ByteString`, so the literal matches `Retry-After`), `delay = retryDelay opts attempt jitter retryAfter`; log INFO `"retrying request"` with `method`, `path`, `attempt + 1`, `delayMs`; `threadDelay (round (delay * 1000000))`; loop with `attempt + 1`. Otherwise rethrow `e`.

Rewrite `notionMiddleware cfg app req`:

1. Render `path = decodeUtf8Lenient (toStrict (toLazyByteString (requestPath req)))`. If `validateRequestPath path` is `Left err`, `liftIO (throwIO err)`.
2. Add the `User-Agent` header (Milestone 1).
3. Log INFO `"request start"` with `method` and `path`.
4. `env <- ask`; then

```haskell
result <- liftIO $ withRetries cfg (requestMethod req') path $ do
  r <- runClientM (app req') env
  case r of
    Right resp -> pure (Right resp)
    Left clientErr ->
      let ex = fromClientError clientErr
       in if isNotionFailure ex then throwIO ex else pure (Left clientErr)
either throwError (\resp -> liftIO (logSuccess resp) >> pure resp) result
```

where `isNotionFailure` is true when `fromException` succeeds at `NotionError`, `UnknownHTTPResponseError` or `RequestTimeoutError`, and `logSuccess` logs INFO `"request success"` with `method`, `path` and `requestId` from the `x-notion-request-id` response header. Also log WARN `"request fail"` for timeouts and unknown responses before throwing them (they are not retried, matching JS).

Add to `tasty/RuntimeTests.hs` a `retryPolicyTests` group (pure, no IO):

- `canRetry`: `POST`+`RateLimited` True; `POST`+`ServiceOverload` True; `POST`+`InternalServerError` False; `GET`+`InternalServerError` True; `DELETE`+`ServiceUnavailable` True; `PATCH`+`ServiceUnavailable` False; `GET`+`GatewayTimeout` False; `GET`+`UnknownErrorCode "x"` False; `GET`+`ObjectNotFound` False.
- `parseRetryAfter` with `now = 2015-10-21 07:27:30 UTC`: `"120"` → `Just 120`; `"0"` → `Just 0`; `" 7"` → `Just 7`; `"1.5"` → `Just 1`; `"Wed, 21 Oct 2015 07:28:00 GMT"` → `Just 30`; `"Wed, 21 Oct 2015 07:00:00 GMT"` → `Just 0`; `"soon"` → `Nothing`; `""` → `Nothing`.
- `retryDelay defaultRetryOptions`: attempt 0, jitter 0, no header → `0.5`; attempt 1, jitter 0.5 → `2` (base 2: 1 + 1); attempt 10, jitter 0.9 → `60` (capped); header 120 → `60`; header 5 → `5`.
- `validateRequestPath`: `"/pages/5c6a28216bb14a7eb6e1c50111515c3d"` → `Right ()`; `"/pages/.."` → `Left`; `"/pages/%2E%2E"` → `Left`; `"/pages/%252e%252e"` → `Right ()`.

And a `retryLoopTests` group using `FakeNotion` with `cfg = defaultClientConfig {retryOptions = defaultRetryOptions {initialRetryDelay = 0.001, maxRetryDelay = 0.01}}` so tests run in milliseconds:

- "GET retried after 429 then succeeds": script `[FakeReply 429 [json, ("Retry-After","0")] rateLimitedBody, jsonReply 200 userJson]` → `retrieveMyUser` succeeds; two requests recorded. `rateLimitedBody` is `{"object":"error","status":429,"code":"rate_limited","message":"You have been rate limited. Please try again in a few minutes."}`.
- "POST retried after 529": `search` with an empty `SearchRequest` against `[529 service_overload, 200 list]` → succeeds, two requests.
- "POST not retried on 500": `search` against `[500 internal_server_error]` → throws `NotionError` with `InternalServerError`; one request recorded (a second script entry, if present, is untouched).
- "GET retried on 503 until maxRetries then throws": `[503, 503, 503]` with default `maxRetries = 2` → throws `ServiceUnavailable`; three requests.
- "noRetries disables retries": `[429, 200]` with `retryOptions = noRetries` → throws `RateLimited`; one request.
- "withRetries wraps a plain IO action": without Servant, an `IORef` counter action that throws `notionErrorFromResponse status429 [("Retry-After","0")] rateLimitedBody` on its first call and returns `"ok"` on its second; `withRetries cfg methodPost "/sessions" action` returns `"ok"` and the counter is 2. With `status500` and `methodPost` it throws after one call.
- "HTML 429 is not retried": `[FakeReply 429 [("Content-Type","text/html")] "<html/>"]` → throws `UnknownHTTPResponseError`; one request.
- "logger sees retry lines": `logger = Just` an `IORef`-appending logger, `logLevel = LogDebug`; after the 429-then-200 test, the recorded messages include `"request start"`, `"request fail"`, `"retrying request"`, `"request success"` in that order.
- "path traversal rejected before sending": `retrievePage methods (UUID "..")` throws `InvalidPathParameterError`; zero requests recorded.


### Milestone 4: OAuth, ID helpers, pagination fold, documentation

Scope: the three OAuth endpoints with Basic auth, the URL-to-ID helpers, a constant-memory pagination fold, and user-facing documentation. Proof: `OAuth` and `Helpers` test groups pass, and the full `cabal build all && cabal test` is green.

Create `src/Notion/V1/OAuth.hs`:

```haskell
module Notion.V1.OAuth
  ( OAuthCredentials (..),
    OAuthTokenRequest (..),
    AuthorizationCodeGrant (..),
    ExternalAccount (..),
    OAuthTokenResponse (..),
    OAuthOwner (..),
    OAuthOwnerUser (..),
    OAuthRevokeResponse (..),
    OAuthIntrospectResponse (..),
    TokenBody (..),
    OAuthMethods (..),
    makeOAuthMethods,
    makeOAuthMethodsWith,
    basicAuthorization,
    API,
  )
where

data OAuthCredentials = OAuthCredentials {clientId :: Text, clientSecret :: Text}

data OAuthTokenRequest
  = AuthorizationCode AuthorizationCodeGrant
  | RefreshToken Text

data AuthorizationCodeGrant = AuthorizationCodeGrant
  { code :: Text,
    redirectUri :: Maybe Text,
    externalAccount :: Maybe ExternalAccount
  }

data ExternalAccount = ExternalAccount {key :: Text, name :: Text}

data OAuthTokenResponse = OAuthTokenResponse
  { accessToken :: Text,
    tokenType :: Text,                 -- "bearer"
    refreshToken :: Maybe Text,
    botId :: Text,
    workspaceIcon :: Maybe Text,
    workspaceName :: Maybe Text,
    workspaceId :: Text,
    owner :: OAuthOwner,
    duplicatedTemplateId :: Maybe Text,
    requestId :: Maybe Text
  }

data OAuthOwner
  = OAuthUserOwner OAuthOwnerUser
  | OAuthWorkspaceOwner
  | UnknownOAuthOwner Value

-- | Full person user or partial user ({id, object}); person-only fields are Maybe.
data OAuthOwnerUser = OAuthOwnerUser
  { id :: UUID,
    object :: Text,
    type_ :: Maybe Text,
    name :: Maybe Text,
    avatarUrl :: Maybe Text,
    email :: Maybe Text            -- from person.email
  }

newtype OAuthRevokeResponse = OAuthRevokeResponse {requestId :: Maybe Text}

data OAuthIntrospectResponse = OAuthIntrospectResponse
  { active :: Bool,
    scope :: Maybe Text,
    iat :: Maybe Integer,
    requestId :: Maybe Text
  }

newtype TokenBody = TokenBody {token :: Text}   -- ToJSON {"token": ...}

type API =
  Header' [Required, Strict] "Authorization" Text
    :> Header' [Required, Strict] "Notion-Version" Text
    :> "oauth"
    :> ( "token" :> ReqBody '[JSON] OAuthTokenRequest :> Post '[JSON] OAuthTokenResponse
           :<|> "revoke" :> ReqBody '[JSON] TokenBody :> Post '[JSON] OAuthRevokeResponse
           :<|> "introspect" :> ReqBody '[JSON] TokenBody :> Post '[JSON] OAuthIntrospectResponse
       )

data OAuthMethods = OAuthMethods
  { createOAuthToken :: OAuthTokenRequest -> IO OAuthTokenResponse,
    revokeOAuthToken :: Text -> IO OAuthRevokeResponse,
    introspectOAuthToken :: Text -> IO OAuthIntrospectResponse
  }

-- | "Basic " <> base64 (client_id <> ":" <> client_secret)
basicAuthorization :: OAuthCredentials -> Text

makeOAuthMethodsWith :: ClientConfig -> ClientEnv -> OAuthCredentials -> OAuthMethods
makeOAuthMethods :: ClientEnv -> OAuthCredentials -> OAuthMethods   -- = makeOAuthMethodsWith legacyClientConfig
```

`makeOAuthMethodsWith` mirrors `makeMethodsWithEnv`: `createOAuthToken :<|> revoke_ :<|> introspect_ = Client.hoistClient @API Proxy run (Client.client @API Proxy) (basicAuthorization creds) config.notionVersion`, with `run = runClientWith (configureClientEnv config env)`, `revokeOAuthToken = revoke_ . TokenBody`, and `introspectOAuthToken = introspect_ . TokenBody`. The path `oauth/token` is relative to the same `/v1` base URL as other routes, as in the JS SDK. JSON: `OAuthTokenRequest`'s `ToJSON` writes `{"grant_type":"authorization_code","code":...}` plus `redirect_uri`/`external_account` only when `Just`, or `{"grant_type":"refresh_token","refresh_token":...}`. `OAuthOwner`'s `FromJSON` dispatches on `type`: `"user"` parses `user` into `OAuthOwnerUser` (reading `email` from the nested `person` object when present), `"workspace"` gives `OAuthWorkspaceOwner`, anything else `UnknownOAuthOwner` with the whole object. The existing `Notion.V1.Users.UserObject` is not reused because its generic parser requires `type`, which the partial user shape lacks.

Create `tasty/OAuthTests.hs` (`tests = testGroup "OAuth" [...]`):

- "basicAuthorization encodes client_id:client_secret": `basicAuthorization (OAuthCredentials "client" "secret") @?= "Basic Y2xpZW50OnNlY3JldA=="`.
- "authorization_code request encodes": `AuthorizationCode (AuthorizationCodeGrant "code-123" (Just "https://example.com/callback") Nothing)` encodes to `{"grant_type":"authorization_code","code":"code-123","redirect_uri":"https://example.com/callback"}`; with `externalAccount = Just (ExternalAccount "acct-1" "Tanaka Hanako")` the object also has `"external_account":{"key":"acct-1","name":"Tanaka Hanako"}`.
- "refresh_token request encodes": `{"grant_type":"refresh_token","refresh_token":"nrt_abc"}`.
- "token response with person owner decodes":

```json
{"access_token":"secret_tanaka_access","token_type":"bearer","refresh_token":"nrt_tanaka_refresh","bot_id":"2f8e6d4c-1b3a-4c5d-8e7f-9a0b1c2d3e4f","workspace_icon":null,"workspace_name":"Tanaka Hanako's Workspace","workspace_id":"7a6b5c4d-3e2f-4a1b-9c8d-7e6f5a4b3c2d","owner":{"type":"user","user":{"type":"person","person":{"email":"hanako@example.com"},"name":"Tanaka Hanako","avatar_url":null,"id":"0e1d2c3b-4a59-4687-b7a6-958473625140","object":"user"}},"duplicated_template_id":null,"request_id":"5d4c3b2a-1f0e-4d9c-8b7a-6f5e4d3c2b1a"}
```

  → `owner` is `OAuthUserOwner` with `email = Just "hanako@example.com"`, `refreshToken = Just "nrt_tanaka_refresh"`.
- "partial user owner and workspace owner decode": `"owner":{"type":"user","user":{"id":"0e1d2c3b-4a59-4687-b7a6-958473625140","object":"user"}}` → `email = Nothing`; `"owner":{"type":"workspace","workspace":true}` → `OAuthWorkspaceOwner`; `"owner":{"type":"team"}` → `UnknownOAuthOwner`.
- "introspect response decodes": `{"active":true,"scope":"read_content","iat":1757890000,"request_id":"r-1"}` and `{"active":false}`.
- "createOAuthToken sends Basic auth to POST /oauth/token": via `FakeNotion`, script `[jsonReply 200 tokenJson]`; recorded method `POST`, path `/oauth/token`, `Authorization` header `Basic Y2xpZW50OnNlY3JldA==`, and no `Bearer` header.

Create `src/Notion/V1/Helpers.hs` exporting `extractNotionId`, `extractPageId`, `extractDatabaseId`, `extractBlockId :: Text -> Maybe UUID` (import `UUID` from `Notion.V1.Common`). Implement without a regex library, as straightforward scans that are equivalent to the JS regular expressions:

1. `t = Text.strip input`. If `t` is 36 characters with hyphens at indices 8, 13, 18, 23 and hex digits elsewhere, return `Text.toLower t`.
2. If `t` is exactly 32 hex digits, return `formatUuid t` (lowercase, hyphens after 8, 12, 16, 20 characters).
3. Path rule: for each `/` in `t` from left to right, take the segment after it up to (not including) the next `/`, `?` or `#`, or the end. If the segment has length at least 33 and ends with `-` followed by exactly 32 hex digits, return those digits formatted. (Because `[^/?#]*` cannot cross a delimiter and the ID must be followed by a delimiter or the end, the ID can only be the tail of a segment; the leftmost qualifying segment wins.)
4. Query rule: for each index of `?` or `&` from left to right, if the rest of `t`, compared case-insensitively, starts with `p=`, `page_id=` or `database_id=` followed by 32 hex digits, return those digits formatted.
5. Otherwise return the leftmost run of 32 consecutive hex digits, formatted, or `Nothing`.

`extractPageId = extractNotionId`, `extractDatabaseId = extractNotionId`. `extractBlockId` scans the untrimmed input: for each `#` from left to right, skip an optional case-insensitive `block-`, then if 32 hex digits follow, return them formatted.

Create `tasty/HelpersTests.hs` (`tests = testGroup "Helpers" [...]`) with these cases (IDs are made up):

- `"12345678-1234-1234-1234-123456789ABC"` → `Just "12345678-1234-1234-1234-123456789abc"`.
- `"12345678123412341234123456789abc"` → `Just "12345678-1234-1234-1234-123456789abc"`.
- `"https://www.notion.so/tanaka/Meeting-Notes-abc123def456789012345678901234ab"` → `Just "abc123de-f456-7890-1234-5678901234ab"`.
- `"https://www.notion.so/tanaka/Tasks-abc123def456789012345678901234ab?v=0123456789abcdef0123456789abcdef"` → database ID `"abc123de-f456-7890-1234-5678901234ab"`, not the view ID.
- `"https://www.notion.so/tanaka?v=11111111111111111111111111111111&p=22222222222222222222222222222222"` → `"22222222-2222-2222-2222-222222222222"` (query rule beats the last-resort rule).
- `"notion.so/ffffffffffffffffffffffffffffffff"` → `"ffffffff-ffff-ffff-ffff-ffffffffffff"` (last resort).
- `"not-an-id"` and `""` → `Nothing`.
- `extractBlockId "https://www.notion.so/Page-0123456789abcdef0123456789abcdef#block-fedcba9876543210fedcba9876543210"` → `"fedcba98-7654-3210-fedc-ba9876543210"`; with `#fedcba98...` (no `block-`) the same; with no fragment → `Nothing`.
- `extractPageId` on the block URL above → the page ID `"01234567-89ab-cdef-0123-456789abcdef"`.

Edit `src/Notion/V1/Pagination.hs` to add and export:

```haskell
-- | Fold over every item of a paginated endpoint, one page in memory at a time.
paginateFoldM :: (b -> a -> IO b) -> b -> (Maybe Text -> IO (ListOf a)) -> IO b

-- | Run an action for every item of a paginated endpoint.
paginateForM_ :: (Maybe Text -> IO (ListOf a)) -> (a -> IO ()) -> IO ()
```

They follow the same cursor rule as `paginateCollect` (continue while `hasMore` and `nextCursor` is `Just`). Add a test "paginateFoldM sums across pages" to `tasty/HelpersTests.hs` reusing a three-page mock like `testPaginateAll`, asserting the sum `21`.

Documentation and changelog:

- `README.md`: in "Error handling" use `apiErrorCodeText (code e)`, show matching on `ObjectNotFound`, and mention `UnknownHTTPResponseError` and `RequestTimeoutError`; add a "Configuration and retries" section showing `makeMethodsWith defaultClientConfig {logger = Just stderrLogger, logLevel = LogInfo} manager token`; add an "OAuth" section and a "URL helpers" example.
- `notion-client-effectful/src/Notion/V1/Effectful/Interpreter.hs` module Haddock and `notion-client-effectful/README.md`: state that `UnknownHTTPResponseError`, `RequestTimeoutError` and `InvalidPathParameterError` remain `IO` exceptions like other client errors. No code change.
- `CHANGELOG.md`: create a `## Unreleased` heading at the top (above `## 0.7.0.2`) if it does not exist; add under it:

```text
### Breaking Changes
* `NotionError.code` is now `APIErrorCode` (was `Text`); `NotionError` gains `requestId`, `additionalData` and `response` fields. String literals still work via `IsString`; use `apiErrorCodeText` to get `Text`.
* Failure responses whose body is not a Notion error (for example Cloudflare HTML pages) now throw `UnknownHTTPResponseError` instead of servant's `ClientError` (`FailureResponse`).
* Connection and response timeouts now throw `RequestTimeoutError` instead of `ClientError` (`ConnectionError`).
* `makeMethods` now retries `rate_limited` (429) and `service_overload` (529) responses for all requests and `internal_server_error`/`service_unavailable` for GET/DELETE, up to 2 times with back-off honoring `retry-after`. Use `makeMethodsWithEnv defaultClientConfig {retryOptions = noRetries}` for the old behavior.
* Requests now send a `User-Agent: notion-client-haskell/<version>` header.
* Request paths containing `..` throw `InvalidPathParameterError` before any request is sent.
* `ListOf` gains a `requestStatus` field; record construction must supply it.
* Minimum `servant-client` is now 0.20.2.

### New Features
* `ClientConfig`, `defaultClientConfig`, `makeMethodsWith` and `makeMethodsWithEnv`: configurable Notion-Version, base URL, timeout (default 60s), retries, User-Agent and logging.
* `APIErrorCode` with all 14 Notion error codes plus `UnknownErrorCode`.
* `RequestStatus` on list responses.
* OAuth: `Notion.V1.OAuth` with `createOAuthToken`, `revokeOAuthToken`, `introspectOAuthToken` using HTTP Basic auth.
* `Notion.V1.Helpers`: `extractNotionId`, `extractPageId`, `extractDatabaseId`, `extractBlockId`.
* `paginateFoldM` and `paginateForM_`.
* Runtime building blocks `withRetries`, `applyTimeout`, `buildRequestError` for non-Servant requests.
```

Do not change the package version; the MasterPlan bumps it after all child plans land.


## Concrete Steps

All commands run from the repository root, `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`, inside the Nix dev shell (entered automatically by direnv, or with `nix develop`).

Before starting, confirm the tree builds and tests pass:

```bash
cabal build all
cabal test
```

Expected tail of the test output (integration groups are skipped without `NOTION_TOKEN`):

```text
All NNN tests passed (X.XXs)
Test suite tasty: PASS
```

Milestone 1, after editing the cabal file, `src/Notion/V1/Client.hs`, `src/Notion/V1.hs`, `tasty/FakeNotion.hs`, `tasty/RuntimeTests.hs` and `tasty/Main.hs`:

```bash
cabal build all
cabal test --test-options='-p Runtime'
```

Expected:

```text
Notion Client Tests
  Runtime
    Configuration
      makeMethods sends default Notion-Version, Bearer token and User-Agent: OK
      makeMethodsWithEnv honors a configured Notion-Version:                  OK
      applyTimeout sets responseTimeout:                                     OK
```

If cabal reports that `servant-client-0.20.2` or newer cannot be found, run `cabal update` and retry; if the Nix shell pins an older servant-client, see Idempotence and Recovery.

Milestone 2:

```bash
cabal build all
cabal test --test-options='-p Runtime'
cabal test --test-options='-p "Parse NotionError"'
```

Expected: the `Errors` subgroup lists the eight cases above as `OK`, and the pre-existing `Parse NotionError from JSON: OK` still passes unchanged. Also run `cabal build notion-client-example` to confirm the demo compiles.

Milestone 3:

```bash
cabal test --test-options='-p Retry'
```

Expected: `Retry policy` and `Retry loop` subgroups all `OK`, finishing in well under a second (delays are milliseconds in tests).

Milestone 4:

```bash
cabal build all
cabal test
```

Expected: `OAuth` and `Helpers` groups all `OK`, and `Test suite tasty: PASS`.

Commit after each milestone (the pre-commit hook runs `treefmt`; if it rewrites files, `git add` them and commit again). Example message:

```text
feat(runtime): add ClientConfig and makeMethodsWith

Introduce Notion.V1.Client with a configuration record (Notion-Version,
base URL, timeout, User-Agent, logging) and servant middleware. makeMethods
keeps its type as a wrapper over makeMethodsWithEnv.

MasterPlan: docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md
ExecPlan: docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md
```

Use `feat!:` (or a `BREAKING CHANGE:` footer) for the Milestone 2 and 3 commits, which change exception types and retry behavior.


## Validation and Acceptance

Acceptance is behavioral:

1. `cabal build all` succeeds for both `notion-client` and `notion-client-effectful` with no new warnings in the new modules.
2. `cabal test` passes, including every test named in the milestones. In particular, the fake-server test "GET retried after 429 then succeeds" shows that a request which previously threw now returns the decoded user after exactly two HTTP exchanges, and "POST not retried on 500" shows exactly one exchange.
3. The pre-existing tests `Parse NotionError from JSON` and `paginateAll` pass (after adding `requestStatus = Nothing` to the latter's literals), demonstrating source compatibility for common uses.

Optional live check when `NOTION_TOKEN` is set (use a real integration token; nothing is modified):

```bash
cabal repl notion-client
```

```haskell
import Data.Text qualified as T
import Network.HTTP.Client.TLS (newTlsManager)
import System.Environment (getEnv)
import Control.Exception (try)
import Notion.V1
import Notion.V1.Error
m <- newTlsManager
tok <- T.pack <$> getEnv "NOTION_TOKEN"
let methods = makeMethodsWith defaultClientConfig {logger = Just stderrLogger, logLevel = LogInfo} m tok
retrieveMyUser methods
```

Observe on stderr lines like `notion-client LogInfo: request start {"method":"GET","path":"/users/me"}` and `request success` with a `requestId`, followed by the bot user. Then:

```haskell
r <- try @NotionError (retrieveMyUser (makeMethodsWith defaultClientConfig m "bogus"))
either (\e -> print (code e, requestId e)) (const (putStrLn "unexpected")) r
```

Expect `(Unauthorized,Just "<uuid>")` and no retry lines (401 is not retryable). Running `cabal run notion-client-example` with a token still completes its demos; the "Typed Error Handling" section prints `code: object_not_found` and a request ID.

If OAuth credentials are available as `NOTION_OAUTH_CLIENT_ID`/`NOTION_OAUTH_CLIENT_SECRET`, `introspectOAuthToken (makeOAuthMethodsWith defaultClientConfig env creds) "not-a-real-token"` must reach Notion with Basic auth: either an `OAuthIntrospectResponse {active = False}` or a `NotionError` whose code is not `Unauthorized` proves the credentials were accepted; `Unauthorized` means the client ID/secret are wrong.


## Idempotence and Recovery

All steps are additive edits to source files and can be re-run; `cabal build` and `cabal test` are safe to repeat. No data is written to Notion by the unit tests; the fake server never opens a socket (`newManager defaultManagerSettings` only allocates a connection pool).

If the resolved `servant-client` is older than 0.20.2 (no `middleware` field on `ClientEnv`), do not downgrade the design silently. Either add a `constraints: servant-client >= 0.20.2` line to `cabal.project.local` and `cabal update`, or, if that is impossible in the Nix shell, fall back to running the retry loop in `runClientWith`: re-run the whole `ClientM` action and take the HTTP method from the `FailureResponse`'s `requestMethod`. Record the choice in the Decision Log.

Retrying re-sends the same servant `Request`. For `sendFileUploadContent` (multipart, `POST`) this re-reads the request body source; only 429/529 trigger it. If a test or live run shows the multipart body cannot be replayed, record it in Surprises & Discoveries and exclude requests whose `requestBody` is a `RequestBodySource` from retries.

If a milestone is abandoned halfway, `git stash` or `git checkout -- <files>` restores the last green commit; each milestone ends with a commit so there is always one.


## Interfaces and Dependencies

New library dependencies and why: `http-client` (the `Request.responseTimeout` field and `HttpException`/`HttpExceptionContent` to detect timeouts), `http-types` (`Method`, `methodGet`, `methodDelete`, `ResponseHeaders`, `HeaderName`, `urlDecode`), `servant-client-core` (`Request`, `RequestF (..)`, `defaultRequest` for the middleware and tests), `mtl` (`ask`, `throwError` in `ClientM`), `random` (`randomRIO` for back-off jitter), `base64-bytestring` (Basic auth header). `servant-client` lower bound rises to 0.20.2 for `ClientEnv.middleware`.

At the end of Milestone 1:

```haskell
-- Notion.V1.Client
data ClientConfig = ClientConfig {apiBaseUrl :: BaseUrl, notionVersion :: Text, timeout :: Maybe NominalDiffTime, retryOptions :: RetryOptions, userAgent :: Maybe Text, logger :: Maybe Logger, logLevel :: LogLevel}
defaultClientConfig, legacyClientConfig :: ClientConfig
data LogLevel = LogDebug | LogInfo | LogWarn | LogError
type Logger = LogLevel -> Text -> [(Text, Value)] -> IO ()
stderrLogger :: Logger
data RequestContext = RequestContext {contextConfig :: ClientConfig, contextManager :: Manager, contextBaseUrl :: BaseUrl, contextAuthorization :: Text}
requestContextFor :: ClientConfig -> ClientEnv -> Text -> RequestContext
standardHeaders :: RequestContext -> [Header]
responseTimeoutFor :: ClientConfig -> ResponseTimeout
applyTimeout :: ClientConfig -> Network.HTTP.Client.Request -> Network.HTTP.Client.Request
configureClientEnv :: ClientConfig -> ClientEnv -> ClientEnv
notionMiddleware :: ClientConfig -> (Servant.Client.Core.Request -> ClientM Response) -> Servant.Client.Core.Request -> ClientM Response
runClientWith :: ClientEnv -> ClientM a -> IO a
logWith :: ClientConfig -> LogLevel -> Text -> [(Text, Value)] -> IO ()

-- Notion.V1
makeMethodsWith :: ClientConfig -> Manager -> Text -> Methods
makeMethodsWithEnv :: ClientConfig -> ClientEnv -> Text -> Methods
makeMethods :: ClientEnv -> Text -> Methods          -- unchanged type
getClientEnv :: Text -> IO ClientEnv                  -- unchanged
```

At the end of Milestone 2:

```haskell
-- Notion.V1.Error
data APIErrorCode = Unauthorized | RestrictedResource | ObjectNotFound | RateLimited | InvalidJSON | InvalidRequestURL | InvalidRequest | InvalidBeta | ValidationError | ConflictError | InternalServerError | ServiceOverload | ServiceUnavailable | GatewayTimeout | UnknownErrorCode Text
apiErrorCodeText :: APIErrorCode -> Text
parseAPIErrorCode :: Text -> APIErrorCode
data NotionError = NotionError {object :: Text, status :: Natural, code :: APIErrorCode, message :: Text, requestId :: Maybe Text, additionalData :: Maybe Value, details :: Maybe Value, response :: Maybe HttpErrorResponse}
data HttpErrorResponse = HttpErrorResponse {httpStatus :: Int, errorHeaders :: ResponseHeaders, notionRequestId :: Maybe Text, rayId :: Maybe Text, errorBody :: ByteString}
newtype UnknownHTTPResponseError = UnknownHTTPResponseError {unknownResponse :: HttpErrorResponse}
unknownResponseMessage :: UnknownHTTPResponseError -> Text
data RequestTimeoutError = RequestTimeoutError
newtype InvalidPathParameterError = InvalidPathParameterError {invalidPath :: Text}
buildRequestError :: Int -> ResponseHeaders -> ByteString -> Either UnknownHTTPResponseError NotionError
notionErrorFromResponse :: Status -> ResponseHeaders -> ByteString -> SomeException
fromClientError :: ClientError -> SomeException
parseNotionError :: ClientError -> Maybe NotionError
lookupHeader :: HeaderName -> ResponseHeaders -> Maybe Text

-- Notion.V1.ListOf
data ListOf a = List {results :: Vector a, nextCursor :: Maybe Text, hasMore :: Bool, type_ :: Maybe Text, object :: Maybe Text, requestStatus :: Maybe RequestStatus}
data RequestStatus = RequestStatus {type_ :: RequestStatusType, incompleteReason :: Maybe IncompleteReason}
data RequestStatusType = RequestComplete | RequestIncomplete | UnknownRequestStatusType Text
data IncompleteReason = QueryResultLimitReached | UnknownIncompleteReason Text
```

At the end of Milestone 3:

```haskell
-- Notion.V1.Retry
data RetryOptions = RetryOptions {maxRetries :: Natural, initialRetryDelay :: NominalDiffTime, maxRetryDelay :: NominalDiffTime}
defaultRetryOptions, noRetries :: RetryOptions
canRetry :: Method -> APIErrorCode -> Bool
parseRetryAfter :: UTCTime -> Data.ByteString.ByteString -> Maybe NominalDiffTime
retryDelay :: RetryOptions -> Natural -> Double -> Maybe NominalDiffTime -> NominalDiffTime
validateRequestPath :: Text -> Either InvalidPathParameterError ()

-- Notion.V1.Client
withRetries :: ClientConfig -> Method -> Text -> IO a -> IO a
```

### Interfaces exported for non-Servant requests (consumed by `docs/plans/14-stream-session-updates-over-server-sent-events.md`)

These names are a contract; if implementation forces a rename, update this section and tell the owner of plan 14 through its Decision Log.

```haskell
-- Notion.V1.Client (re-exported from Notion.V1)
data RequestContext = RequestContext
  { contextConfig :: ClientConfig,
    contextManager :: Network.HTTP.Client.Manager,
    contextBaseUrl :: Servant.Client.BaseUrl,
    contextAuthorization :: Text
  }
requestContextFor :: ClientConfig -> ClientEnv -> Text -> RequestContext
standardHeaders :: RequestContext -> [Network.HTTP.Types.Header]   -- Authorization, Notion-Version, User-Agent
responseTimeoutFor :: ClientConfig -> Network.HTTP.Client.ResponseTimeout
withRetries :: ClientConfig -> Network.HTTP.Types.Method -> Text -> IO a -> IO a
logWith :: ClientConfig -> LogLevel -> Text -> [(Text, Value)] -> IO ()

-- Notion.V1.Error
notionErrorFromResponse :: Network.HTTP.Types.Status -> Network.HTTP.Types.ResponseHeaders -> Data.ByteString.Lazy.ByteString -> SomeException
buildRequestError :: Int -> Network.HTTP.Types.ResponseHeaders -> Data.ByteString.Lazy.ByteString -> Either UnknownHTTPResponseError NotionError
```

Mapping onto plan 14's `StreamEnv`, built in the `where` block of `makeMethodsWithEnv` from `context = requestContextFor config clientEnv token`:

```haskell
StreamEnv
  { manager = contextManager context,
    baseUrl = contextBaseUrl context,
    authorization = contextAuthorization context,
    notionVersion = config.notionVersion,
    openTimeout = responseTimeoutFor config,
    extraHeaders = [h | h@(name, _) <- standardHeaders context, name == "User-Agent"],
    retryOpen = withRetries config methodPost "/sessions",
    responseError = \res -> notionErrorFromResponse (responseStatus res) (responseHeaders res) (responseBody res)
  }
```

`withRetries` catches only `NotionError`, so the stream's `openOnce` must throw the value produced by `notionErrorFromResponse` (with `throwIO`) for 429/529 to be retried; an `UnknownHTTPResponseError` or `RequestTimeoutError` propagates immediately, as in the JS SDK. Once the stream is open nothing is retried.

At the end of Milestone 4:

```haskell
-- Notion.V1.OAuth
data OAuthCredentials = OAuthCredentials {clientId :: Text, clientSecret :: Text}
data OAuthTokenRequest = AuthorizationCode AuthorizationCodeGrant | RefreshToken Text
data OAuthMethods = OAuthMethods {createOAuthToken :: OAuthTokenRequest -> IO OAuthTokenResponse, revokeOAuthToken :: Text -> IO OAuthRevokeResponse, introspectOAuthToken :: Text -> IO OAuthIntrospectResponse}
makeOAuthMethods :: ClientEnv -> OAuthCredentials -> OAuthMethods
makeOAuthMethodsWith :: ClientConfig -> ClientEnv -> OAuthCredentials -> OAuthMethods
basicAuthorization :: OAuthCredentials -> Text

-- Notion.V1.Helpers
extractNotionId, extractPageId, extractDatabaseId, extractBlockId :: Text -> Maybe UUID

-- Notion.V1.Pagination
paginateFoldM :: (b -> a -> IO b) -> b -> (Maybe Text -> IO (ListOf a)) -> IO b
paginateForM_ :: (Maybe Text -> IO (ListOf a)) -> (a -> IO ()) -> IO ()
```

`Methods` and the `notion-client-effectful` `Notion` GADT are unchanged by this plan.
