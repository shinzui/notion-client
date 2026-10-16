---
id: 18
slug: refresh-oauth-access-tokens-automatically-for-methods
title: "Refresh OAuth Access Tokens Automatically for Methods"
kind: exec-plan
created_at: 2026-10-16T11:24:45Z
intention: "intention_01m52739hkexps2gwzdp5hnn4a"
master_plan: "docs/masterplans/3-support-notion-public-integrations-with-an-oauth-login-flow.md"
provenance:
  created_by:
    model: "claude-opus-5-5"
    harness: "claude-code"
    at: 2026-10-16T11:24:45Z
---

# Refresh OAuth Access Tokens Automatically for Methods

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

A Notion *public integration* obtains two tokens through OAuth when a user installs it. The *access token* is sent as `Authorization: Bearer <token>` on every API call. The *refresh token* is traded at `POST /v1/oauth/token` (grant type `refresh_token`) for a new pair when the access token stops working. Notion's authorization guide says that refreshing "will generate a new access token and a new refresh token". The refresh token therefore *rotates*: once a refresh succeeds, the old refresh token is dead. A program that loses the new pair, or that runs two refreshes at once, locks itself out and must send the user through the login again.

Today `Methods`, the record of API calls built by `makeMethodsWith` in `src/Notion/V1.hs`, captures one access token when it is constructed. A program using OAuth has to catch the `unauthorized` error everywhere, refresh by hand, store the new pair safely, and rebuild `Methods`. Every component holding the old `Methods` value keeps failing.

After this change a program builds `Methods` once from a *token source*: something that says which access token to send now and how to get a better one. When Notion answers a request with the error code `unauthorized`, the library asks the source for a new token, retries that request once, and returns the result as if nothing had happened. For OAuth, `newOAuthTokenManager` provides such a source. It refreshes through `createOAuthToken`, runs at most one refresh at a time, saves the rotated pair through a caller-supplied `TokenStore` before using it, and throws `ReauthorizationRequired` when the refresh token itself is dead (`invalid_grant`), so the program knows to start the login again. Requests built outside Servant from `RequestContext`, such as the planned session streaming, get the same behavior through `withStandardHeaders`.

To see it working, run `cabal test --test-options='-p TokenRefresh'`. A fake Notion rejects the old token. A single refresh happens even when two threads hit the rejection at once, and both calls succeed with the new token. The live demonstration is in `docs/plans/19-demonstrate-and-document-the-public-integration-oauth-login-end-to-end.md`.

This plan is EP-3 of `docs/masterplans/3-support-notion-public-integrations-with-an-oauth-login-flow.md`.


## Progress

- [ ] Milestone 1: `Notion.V1.TokenSource` (`TokenSource`, `staticTokenSource`, `withAuthorization`) exists. `makeMethodsWithTokenSource` is in `Notion.V1`, and `RequestContext` carries a token source with `withStandardHeaders`. Every existing test passes. New tests show that the header follows the source between calls and that one renewal and retry happen on `unauthorized`. `docs/plans/14-stream-session-updates-over-server-sent-events.md` is updated for the new `RequestContext`.
- [ ] Milestone 2: `Notion.V1.OAuth.Refresh` (`OAuthTokens`, `TokenStore`, `inMemoryTokenStore`, `OAuthTokenManager`, `ReauthorizationRequired`) exists. The `TokenRefresh` tests cover refresh and retry, single-flight under concurrency, `invalid_grant`, a missing refresh token, and a failing store. README, CHANGELOG and a new ADR describe the behavior.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Attach the bearer token per request through a `TokenSource`, rather than rebuilding `Methods` after a refresh.
  Rationale: Callers keep `Methods` in long-lived state and pass it to `notion-client-effectful`'s `runNotion`, so a rebuilt value would not reach them. The fields of `Methods` stay unchanged, so the lockstep rule of ADR 7 is not triggered.
  Date: 2026-10-16

- Decision: Refresh only reactively, after a `NotionError` with code `Unauthorized`, or when the program calls `refreshTokensNow`. Never refresh on a timer.
  Rationale: Notion's token response has no `expires_in` (see `OAuthTokenResponse` in `src/Notion/V1/OAuth.hs` and the JS SDK's `OauthTokenResponse`), so the library cannot know when a token expires.
  Date: 2026-10-16

- Decision: The renewal retry is a separate layer outside ADR 2's retry loop. A request rejected as unauthorized is retried exactly once, after one renewal.
  Rationale: ADR 2 deliberately never retries `unauthorized`. One renewal-then-retry cannot loop, and it keeps ADR 2's rate-limit and 5xx policy unchanged for the retried attempt.
  Date: 2026-10-16

- Decision: When `saveTokens` throws after a successful refresh, keep the new pair in memory and rethrow the exception to the request that triggered the refresh.
  Rationale: The old refresh token is already dead, so discarding the new pair would lock the program out. Rethrowing makes the persistence failure visible instead of silent.
  Date: 2026-10-16


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Work in the repository root `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`. It is a Cabal project (`cabal.project` lists `.` and `notion-client-effectful`) built with GHC 9.12 and `default-language: GHC2024`. The default extensions are `DuplicateRecordFields`, `OverloadedLabels`, `OverloadedStrings` and `RecordWildCards`. `treefmt` formats code in a pre-commit hook; re-stage files it changes. Library modules are listed under `exposed-modules` in `notion-client.cabal`.

**How a request is sent today.** `src/Notion/V1.hs` defines `makeMethodsWithEnv :: ClientConfig -> ClientEnv -> Text -> Methods`. `makeMethods` and `makeMethodsWith` both call it. It builds `context = requestContextFor config clientEnv token` and passes `contextAuthorization context` (the text `"Bearer " <> token`) as the first argument of `Client.client @API Proxy`. Servant's `hoistClient` with `run = runClientWith configuredEnv` turns each route into an `IO` function. Because the header is an argument fixed at construction, every call sends the same token. `configuredEnv = configureClientEnv config clientEnv`.

**The runtime.** "The runtime" is the request pipeline described in [ADR 2](../adr/2-client-runtime-retry-policy-and-typed-errors.md) and implemented in `src/Notion/V1/Client.hs`. `configureClientEnv` installs `notionMiddleware` as the servant-client `ClientEnv` middleware. A *middleware* here is a function of type `(Request -> ClientM Response) -> Request -> ClientM Response` that wraps the actual HTTP exchange. It can inspect or rewrite the outgoing `Request`, including its `requestHeaders :: Seq Header`, before calling the inner function. `notionMiddleware` validates the path, adds `User-Agent`, converts failures into this library's exceptions, and calls `withRetries`. `withRetries` retries a `NotionError` only for the codes `rate_limited` and `service_overload` (any method) and for `internal_server_error` and `service_unavailable` (`GET`/`DELETE` only). It never retries `unauthorized`. A `NotionError` (from `src/Notion/V1/Error.hs`) has a typed `code :: APIErrorCode`, and `Unauthorized` is the constructor for the wire code `unauthorized`, which Notion sends with HTTP 401 for an invalid or expired token. The middleware throws these exceptions with `throwIO`, so they reach the caller of a `Methods` field as ordinary IO exceptions.

**`RequestContext`.** Also in `src/Notion/V1/Client.hs`, and re-exported from `Notion.V1`:

```haskell
data RequestContext = RequestContext
  { contextConfig :: ClientConfig,
    contextManager :: HTTP.Manager,
    contextBaseUrl :: BaseUrl,
    contextAuthorization :: Text   -- "Bearer secret_..."
  }
requestContextFor :: ClientConfig -> ClientEnv -> Text -> RequestContext
standardHeaders :: RequestContext -> [Header]  -- Authorization, Notion-Version, User-Agent
```

These exist so that requests sent with plain `http-client` instead of Servant behave like `Methods`. The only planned consumer is `docs/plans/14-stream-session-updates-over-server-sent-events.md`, which has not started. It is child EP-3 of `docs/masterplans/2-add-the-custom-agents-and-sessions-api-with-sse-streaming.md`, and around its lines 121 and 507 it plans to read `contextAuthorization` and `standardHeaders`. `tasty/RuntimeTests.hs` line 70, "standardHeaders match what Methods sends", is the only existing test that uses them.

**OAuth.** `src/Notion/V1/OAuth.hs` defines `OAuthMethods {createOAuthToken, revokeOAuthToken, introspectOAuthToken}` (built by `makeOAuthMethodsWith :: ClientConfig -> ClientEnv -> OAuthCredentials -> OAuthMethods`), `OAuthTokenRequest = AuthorizationCode AuthorizationCodeGrant | RefreshToken Text`, and

```haskell
data OAuthTokenResponse = OAuthTokenResponse
  { accessToken :: Text, tokenType :: Text, refreshToken :: Maybe Text, botId :: Text,
    workspaceIcon :: Maybe Text, workspaceName :: Maybe Text, workspaceId :: Text,
    owner :: OAuthOwner, duplicatedTemplateId :: Maybe Text, requestId :: Maybe Text }
```

The prerequisite `docs/plans/16-decode-oauth-token-endpoint-errors-into-a-typed-exception.md` (Milestone 1 must be merged before this plan's Milestone 2) adds `OAuthError {oauthErrorCode :: OAuthErrorCode, errorDescription, errorUri, requestId, response}` and `OAuthErrorCode` (including `OAuthInvalidGrant`) to `Notion.V1.OAuth`. With it, `createOAuthToken` throws `OAuthError` when Notion rejects a refresh token. Confirm with `grep -n OAuthInvalidGrant src/Notion/V1/OAuth.hs`.

**The effectful package.** `notion-client-effectful/src/Notion/V1/Effectful/Interpreter.hs` exports `runNotion :: (IOE :> es, Error NotionError :> es) => Methods -> Eff (Notion : es) a -> Eff es a`. It takes a ready `Methods` value, so a `Methods` built from a token source works there without changes. [ADR 7](../adr/7-effectful-package-mirrors-methods-in-lockstep.md) requires lockstep edits only when `Methods` *fields* change, and this plan adds a constructor function, not a field.

**Tests.** `tasty/FakeNotion.hs` exports `fakeClientEnv :: [FakeReply] -> IO (ClientEnv, IORef [Recorded])`. Its `ClientEnv` middleware ignores the network, records `Recorded {method, path, headers}` for each request, and answers from a fixed script. Non-2xx replies are raised as Servant `FailureResponse`, so they pass through the real `notionMiddleware` and become `NotionError` exactly as live responses would. Because a fixed script cannot react to which token a request carries, this plan adds `fakeClientEnvWith :: (Recorded -> IO FakeReply) -> IO (ClientEnv, IORef [Recorded])`, which chooses each reply by calling a function. `fakeClientEnv` keeps its signature and can be reimplemented on top of it. Register new test modules in `tasty/Main.hs` and in the test suite's `other-modules` in `notion-client.cabal`. Fixtures use made-up Japanese names. A Notion `unauthorized` body is `{"object":"error","status":401,"code":"unauthorized","message":"API token is invalid."}`.

Relevant ADRs: [ADR 2](../adr/2-client-runtime-retry-policy-and-typed-errors.md) (the runtime this plan extends; its retry policy must not change) and [ADR 7](../adr/7-effectful-package-mirrors-methods-in-lockstep.md) (not triggered, as explained above). [ADR 1](../adr/1-tolerant-response-decoders.md) does not apply, because no decoded enum is added. No other ADR applies.


## Plan of Work

### Milestone 1: per-request authorization

Create `src/Notion/V1/TokenSource.hs` (module `Notion.V1.TokenSource`, exposed). It imports `Notion.V1.Error` and nothing from `Notion.V1.Client`, so that `Client` can import it.

```haskell
-- | Where the bearer token for each request comes from.
data TokenSource = TokenSource
  { -- | The access token to send now (without the "Bearer " prefix).
    currentToken :: IO Text,
    -- | Called with a token Notion rejected as unauthorized. 'Just' a token to retry
    -- with (which may be a token another thread already obtained), or 'Nothing' when
    -- nothing better is available. May throw, for example 'ReauthorizationRequired'.
    renewToken :: Text -> IO (Maybe Text)
  }

-- | A fixed token that is never renewed: today's behaviour.
staticTokenSource :: Text -> TokenSource

-- | Run an action with the current @Authorization@ value (@"Bearer " <> token@). If it throws a
-- 'NotionError' whose code is 'Unauthorized', renew once and run it once more with the new value;
-- if renewal gives 'Nothing', rethrow the original error.
withAuthorization :: TokenSource -> (Text -> IO a) -> IO a
```

In `src/Notion/V1/Client.hs`, replace the field `contextAuthorization :: Text` of `RequestContext` with `contextTokenSource :: TokenSource`. Keep `requestContextFor :: ClientConfig -> ClientEnv -> Text -> RequestContext`, now using `staticTokenSource`. Add `requestContextWithTokenSource :: ClientConfig -> ClientEnv -> TokenSource -> RequestContext`. Change `standardHeaders` to `standardHeaders :: RequestContext -> IO [Header]`, which reads the current token. Add

```haskell
-- | Run a non-Servant request with the standard headers; on 'Unauthorized' renew the token once
-- and rerun with fresh headers (see 'withAuthorization'). Put 'withRetries' inside the action.
withStandardHeaders :: RequestContext -> ([Header] -> IO a) -> IO a
```

Export the new names from `Notion.V1.Client`, and re-export `requestContextWithTokenSource`, `withStandardHeaders`, `TokenSource (..)` and `staticTokenSource` from `Notion.V1`.

In `src/Notion/V1.hs`, add `makeMethodsWithTokenSource :: ClientConfig -> ClientEnv -> TokenSource -> Methods`, and redefine `makeMethodsWithEnv config env token = makeMethodsWithTokenSource config env (staticTokenSource token)`. Inside the new function, still pass a fixed placeholder header value to `Client.client @API Proxy`. Replace it per call by changing `run` to

```haskell
run clientM = withAuthorization source $ \auth ->
  runClientWith (configureClientEnv config (withAuthorizationHeader auth clientEnv)) clientM
```

where `withAuthorizationHeader auth env` returns `env` with a middleware that removes any `Authorization` header from the request and adds `("Authorization", encodeUtf8 auth)` before calling the inner function. Keep a small helper in `Notion.V1.Client` for this, and wrap the caller's existing middleware rather than replacing it. Because renewal reruns the whole `ClientM` action, the request body is rebuilt, which matters for multipart file uploads. Update the Haddock comments of `makeMethods*` and the module header example.

Update `tasty/RuntimeTests.hs` line 70 for `standardHeaders` now returning `IO`. Add tests in a new module `tasty/TokenSourceTests.hs` (group "TokenSource"):

1. A `TokenSource` backed by an `IORef` makes two consecutive `retrieveMyUser` calls carry `Bearer t1` and then `Bearer t2` after the `IORef` changes. Exactly one `Authorization` header is recorded per request.
2. With replies `[401 unauthorized, 200 user]` and a source whose `renewToken "old"` returns `Just "new"`, one call succeeds. It records two requests, carrying `Bearer old` and then `Bearer new`, and `renewToken` is called exactly once.
3. With `staticTokenSource`, a 401 `unauthorized` surfaces as `NotionError` with code `Unauthorized` after exactly one request.
4. With replies `[401, 401]` and a renewing source, the second `NotionError` propagates. There are exactly two requests, which proves there is no loop.
5. A 429 `rate_limited` reply is still retried by the runtime, independent of renewal. Use `RetryOptions` with a tiny delay, as `tasty/RuntimeTests.hs` does.
6. The producer/consumer check that stands in for plan 14's streaming. `withStandardHeaders ctx action`, where `action` records the headers and throws a hand-built `NotionError {code = Unauthorized, ...}` on its first run, reruns `action` once with `Authorization: Bearer new`, and its headers include `Notion-Version` and `User-Agent`.

Cascade to the dependent plan in the same commit. In `docs/plans/14-stream-session-updates-over-server-sent-events.md`, change the descriptions of `RequestContext` and `standardHeaders` (around lines 121–122) and the `StreamEnv` construction (around line 507) so that the authorization comes from `withStandardHeaders` per stream open, with `withRetries` inside it, instead of a fixed `authorization` field. Add a revision note at the bottom of that plan. Add an entry to the Surprises & Discoveries of `docs/masterplans/2-add-the-custom-agents-and-sessions-api-with-sse-streaming.md` that names this plan's path.

### Milestone 2: OAuth token manager

Before starting, confirm that the prerequisite from `docs/plans/16-decode-oauth-token-endpoint-errors-into-a-typed-exception.md` Milestone 1 exists.

Create `src/Notion/V1/OAuth/Refresh.hs` (module `Notion.V1.OAuth.Refresh`, exposed). It imports `Notion.V1.OAuth` and `Notion.V1.TokenSource`. Do not edit the export list of `Notion.V1.OAuth`; the parent MasterPlan assigns it to EP-1, and re-exporting this module from there would create an import cycle.

```haskell
-- | What a program persists for one installation of a public integration.
data OAuthTokens = OAuthTokens
  { accessToken :: Text,
    refreshToken :: Maybe Text,
    botId :: Text,
    workspaceId :: Text,
    workspaceName :: Maybe Text,
    -- | When this pair was received.
    obtainedAt :: UTCTime
  }
  deriving stock (Eq, Show, Generic)
-- ToJSON/FromJSON with Notion.Prelude.aesonOptions (snake_case keys).

oauthTokensFromResponse :: UTCTime -> OAuthTokenResponse -> OAuthTokens

-- | Persistence supplied by the program (a database row, a file, a secret manager).
data TokenStore = TokenStore
  { loadTokens :: IO OAuthTokens,
    saveTokens :: OAuthTokens -> IO ()
  }

inMemoryTokenStore :: OAuthTokens -> IO TokenStore

-- | The refresh token is missing or Notion rejected it; send the user through the login again.
newtype ReauthorizationRequired = ReauthorizationRequired {reauthorizationCause :: Maybe OAuthError}
  deriving stock (Show)
instance Exception ReauthorizationRequired

data OAuthTokenManager -- abstract: an MVar OAuthTokens, the OAuthMethods and the TokenStore

newOAuthTokenManager :: OAuthMethods -> TokenStore -> IO OAuthTokenManager -- calls loadTokens once
tokenManagerSource :: OAuthTokenManager -> TokenSource
currentTokens :: OAuthTokenManager -> IO OAuthTokens
-- | Refresh now regardless of the current token (for example before a long batch job).
refreshTokensNow :: OAuthTokenManager -> IO OAuthTokens
```

Renewal semantics, all under the `MVar` (use `modifyMVar` so that waiting threads queue behind one refresh):

1. If the stored access token differs from the rejected one, another thread already refreshed. Return `Just` the stored token and make no request.
2. If `refreshToken` is `Nothing`, throw `ReauthorizationRequired Nothing`.
3. Call `createOAuthToken oauth (RefreshToken rt)`. On `OAuthError` with `oauthErrorCode = OAuthInvalidGrant`, throw `ReauthorizationRequired (Just e)`, leaving the state unchanged. Any other exception propagates, and the state is unchanged.
4. On success, build the new value with `oauthTokensFromResponse` and the current time. If the response's `refresh_token` is `null`, keep the previous refresh token, and record in Surprises & Discoveries whether the live run (`docs/plans/19-demonstrate-and-document-the-public-integration-oauth-login-end-to-end.md`) ever saw that.
5. Call `saveTokens new` with `try`. Put `new` into the `MVar` whether or not it succeeded. Then rethrow a save failure, or return `Just (accessToken new)`.

`refreshTokensNow` follows the same steps 2–5 unconditionally. `currentToken` reads the `MVar` without blocking a refresh in progress (`readMVar`).

Add `tasty/TokenRefreshTests.hs` (group "TokenRefresh"). Use `fakeClientEnvWith` for the API, answering 200 with a user fixture when the `Authorization` header is `Bearer secret_new` and 401 `unauthorized` otherwise. Use a second fake `ClientEnv` for `OAuthMethods`, answering a token response with `access_token = "secret_new"` and `refresh_token = "nrt_new"`. Tests:

1. Refresh and retry: a manager loaded with `secret_old`/`nrt_old` makes `retrieveMyUser` succeed. The OAuth fake records exactly one `POST /oauth/token`. The in-memory store now holds `secret_new`/`nrt_new`.
2. Single flight: two threads call `retrieveMyUser` concurrently, released together by an `MVar` barrier, with a 50 ms `threadDelay` inside the OAuth fake's reply function. Both calls succeed and exactly one token request is recorded.
3. `invalid_grant`: the OAuth fake answers 400 `{"error":"invalid_grant"}`, and the call throws `ReauthorizationRequired (Just OAuthError {oauthErrorCode = OAuthInvalidGrant})`.
4. A missing refresh token throws `ReauthorizationRequired Nothing` with no token request.
5. A failing store: `saveTokens` throws `userError "disk full"`. The call rethrows that error, `currentTokens` returns the new pair, and a second `retrieveMyUser` succeeds without another refresh.
6. `OAuthTokens` round-trips through JSON with snake_case keys (`access_token`, `obtained_at`).

Documentation: in `README.md`'s "### OAuth" section, show `newOAuthTokenManager` and `makeMethodsWithTokenSource`, and explain `ReauthorizationRequired` and the single-process scope of the lock (see Interfaces). In `CHANGELOG.md`, under `## Unreleased` (create it at the top if absent), add a `### Breaking Changes` entry for `RequestContext.contextAuthorization` being replaced by `contextTokenSource` and `standardHeaders` now returning `IO [Header]`, and `### New Features` entries for token sources and the token manager. Create the next ADR in `docs/adr/` (`ls docs/adr` and take the next number; at drafting time that was 9). Use the existing format, a title line plus `Status:` and `Date:` lines followed by `## Context`, `## Decision` and `## Consequences`, and follow `agents/skills/exec-plan/ADR.md`. The ADR records the per-request token source, reactive single-flight refresh, persistence of the new pair before use, the one-retry rule outside ADR 2's loop, and the single-process scope. Then add a one-line cross-reference in ADR 2's Consequences.


## Concrete Steps

From `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`:

```bash
cabal build all
cabal test --test-show-details=direct --test-options='-p TokenSource'
cabal test --test-show-details=direct --test-options='-p TokenRefresh'
cabal test --test-show-details=direct
```

Expected after Milestone 2 (abridged):

```text
    TokenRefresh
      refreshes once and retries with the new token:     OK
      concurrent rejections share one refresh:           OK
      invalid_grant raises ReauthorizationRequired:       OK
  All N tests passed
```

Run the concurrency test several times (`--test-options='-p concurrent --num-threads 4'` or a shell loop of 20 runs) to show that it is not flaky. Commit at each milestone with Conventional Commits and trailers, for example:

```text
feat(client)!: attach bearer tokens per request through a TokenSource

MasterPlan: docs/masterplans/3-support-notion-public-integrations-with-an-oauth-login-flow.md
ExecPlan: docs/plans/18-refresh-oauth-access-tokens-automatically-for-methods.md
Intention: intention_01m52739hkexps2gwzdp5hnn4a
```


## Validation and Acceptance

Milestone 1 is accepted when the six `TokenSource` tests pass, every pre-existing test passes unchanged except the one `standardHeaders` adaptation, `cabal build all` builds `notion-client-effectful` without source changes, and plan 14 and its MasterPlan carry the cascade notes. Milestone 2 is accepted when the six `TokenRefresh` tests pass, the concurrency test passes 20 consecutive runs, and the README example type-checks.

A live refresh against Notion is not required here. It needs real OAuth tokens and is the acceptance of `docs/plans/19-demonstrate-and-document-the-public-integration-oauth-login-end-to-end.md`. If that plan's live run contradicts an assumption here (for example, the old access token keeps working after a refresh, or the response omits `refresh_token`), it records the finding in the MasterPlan, and this plan's semantics must be revisited.


## Idempotence and Recovery

The changes are code and tests and can be re-run. The breaking change to `RequestContext` is confined to one record field and one function signature. If it proves too disruptive, an alternative is to keep `contextAuthorization :: Text` as a deprecated field holding the initial value alongside `contextTokenSource`. Record that choice in the Decision Log, because it would leave non-Servant callers unable to refresh. Do not bump the package version; the parent MasterPlan assigns the `0.10.0.0` bump to `docs/plans/19-demonstrate-and-document-the-public-integration-oauth-login-end-to-end.md`.


## Interfaces and Dependencies

No new package dependencies. `Control.Concurrent.MVar` and `Control.Exception` come from `base`, and `time` and `aeson` are already library dependencies.

Produced for other plans:

- `Notion.V1.TokenSource`: `TokenSource (..)`, `staticTokenSource`, `withAuthorization`.
- `Notion.V1` / `Notion.V1.Client`: `makeMethodsWithTokenSource :: ClientConfig -> ClientEnv -> TokenSource -> Methods`, `requestContextWithTokenSource`, `withStandardHeaders :: RequestContext -> ([Header] -> IO a) -> IO a`, and `RequestContext {contextConfig, contextManager, contextBaseUrl, contextTokenSource}`. `docs/plans/14-stream-session-updates-over-server-sent-events.md` consumes these.
- `Notion.V1.OAuth.Refresh`: `OAuthTokens (..)`, `oauthTokensFromResponse`, `TokenStore (..)`, `inMemoryTokenStore`, `ReauthorizationRequired (..)`, `OAuthTokenManager`, `newOAuthTokenManager`, `tokenManagerSource`, `currentTokens`, `refreshTokensNow`. `docs/plans/19-demonstrate-and-document-the-public-integration-oauth-login-end-to-end.md` implements a file-backed `TokenStore` against these and uses them in its example.
- `tasty/FakeNotion.hs`: `fakeClientEnvWith`.

Scope limit to document: the manager serializes refreshes within one process. Several processes sharing one store must coordinate refreshes themselves, for example with a store whose `saveTokens` performs a compare-and-swap. The parent MasterPlan excludes multi-tenant and cross-process stores.

Prerequisites: none for Milestone 1. Milestone 2 requires Milestone 1 of `docs/plans/16-decode-oauth-token-endpoint-errors-into-a-typed-exception.md` (`OAuthError` and `OAuthInvalidGrant`). This plan does not depend on `docs/plans/17-build-authorization-urls-and-exchange-codes-from-verified-oauth-callbacks.md`.
