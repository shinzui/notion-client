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
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-16T11:53:13Z
      mode: "update"
      note: "Correct callback verification, OAuth replay policy, token lifecycle recovery and integration acceptance after source review."
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-19T20:28:11Z
      mode: "implement"
      note: "Implement per-request authorization and serialized rotation with pending and terminal lifecycle states."
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-16T11:53:13Z
      verdict: "approved"
      note: "Revised design reviewed against code, relevant ADRs and current upstream contracts; implementation and live OAuth acceptance remain pending."
---

# Refresh OAuth Access Tokens Automatically for Methods


This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture


A Notion *public integration* obtains two tokens through OAuth when a user installs it. The *access token* is sent as `Authorization: Bearer <token>` on every API call. The *refresh token* is traded at `POST /v1/oauth/token` (grant type `refresh_token`) for a new pair when the access token stops working. Notion's authorization guide says that refreshing "will generate a new access token and a new refresh token". The response therefore contains a replacement pair. The guide does not specify when older tokens stop working or whether reuse revokes a token family. Treat an attempted refresh as potentially consuming its input token. Losing the response or racing another refresh can require a new login; the library must not promise an atomic transaction across Notion and local storage.

Today `Methods`, the record of API calls built by `makeMethodsWith` in `src/Notion/V1.hs`, captures one access token when it is constructed. A program using OAuth has to catch the `unauthorized` error everywhere, refresh by hand, store the new pair safely, and rebuild `Methods`. Every component holding the old `Methods` value keeps failing.

After this change a program builds `Methods` once from a *token source*: something that says which access token to send now and how to get a better one. When Notion answers a request with the error code `unauthorized`, the library asks the source for a new token, retries that request once, and returns the result as if nothing had happened. For OAuth, `newOAuthTokenManager` provides such a source. It refreshes through `createOAuthToken`, runs at most one refresh at a time, saves the rotated pair through a caller-supplied `TokenStore` before using it, and throws `ReauthorizationRequired` when the refresh token itself is dead (`invalid_grant`), so the program knows to start the login again. Requests built outside Servant from `RequestContext`, such as the planned session streaming, get the same behavior through `withStandardHeaders`.

To see it working, run `cabal test --test-options='-p TokenRefresh'`. A fake Notion rejects the old token. A single refresh happens even when two threads hit the rejection at once, and both calls succeed with the new token. The live demonstration is in `docs/plans/19-demonstrate-and-document-the-public-integration-oauth-login-end-to-end.md`.

This plan is EP-3 of `docs/masterplans/3-support-notion-public-integrations-with-an-oauth-login-flow.md`.


## Progress


- [x] (2026-10-19) Milestone 1: `Notion.V1.TokenSource` (`TokenSource`, `staticTokenSource`, `withAuthorization`) exists. `makeMethodsWithTokenSource` is in `Notion.V1`, and `RequestContext` carries a token source with `withStandardHeaders`. Every existing test passes. New tests show that the header follows the source between calls and that one renewal and retry happen on `unauthorized`. `docs/plans/14-stream-session-updates-over-server-sent-events.md` is updated for the new `RequestContext`.
- [x] (2026-10-19) Milestone 2: `Notion.V1.OAuth.Refresh` (`OAuthTokens`, `TokenStore`, `inMemoryTokenStore`, `OAuthTokenManager`, `ReauthorizationRequired`, `TokenPersistenceError`, `RefreshOutcomeUnknown`) exists. The `TokenRefresh` tests cover refresh and retry, single-flight under concurrency, `invalid_grant`, a missing refresh token, a failing store, a lost response, and asynchronous cancellation. README, CHANGELOG and ADR 9 describe the behavior.


## Surprises & Discoveries


- Real multipart replay initially hung because the test kept its temporary file open for writing. Closing the fixture handle before upload makes both attempts read the same complete bytes; the real HTTP test now compares complete multipart request bodies.
- On 2026-10-19, Hackage reports WAI 3.2.5 and Warp 3.4.16; upstream release tags include Warp 3.4.15 but not the latest registry release yet. Existing compatible bounds admit current registry releases; Cabal resolved Warp 3.4.16. Source in `mori://yesodweb/wai/packages/warp` confirmed bracketed server lifetime; `mori://snoyberg/http-client/packages/http-client` confirmed response acquisition APIs. No compatibility workaround or pin was added.


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

- Decision: When `saveTokens` throws after a successful refresh, retain the new pair as pending persistence, block use and further refresh, and expose a retry of that same save.
  Rationale: The old refresh token may already be unusable. Retaining the new pair permits recovery; letting later calls silently use unsaved credentials would violate persistence-before-use.
  Date: 2026-10-16


## Outcomes & Retrospective


Both milestones are implemented. `cabal test all --test-show-details=direct` passes 451 core tests and four companion effectful consumer tests. Real loopback HTTP tests prove byte and file-backed multipart replay, custom middleware/request-builder preservation, failed-response cleanup before renewal and no replay of opened consumers. Deterministic MVar barriers prove two old-token rejections share one refresh and cannot send new credentials before save. Failure/cancellation tests cover pending persistence, uncertain outcomes, terminal invalid grants, null refresh tokens and installation identity. Plan 14 and MasterPlan 2 carry the runtime interface cascade. ADR 9 records the durable boundaries. Live refresh remains the separate integration gate in plan 19.


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

The prerequisite `docs/plans/16-decode-oauth-token-endpoint-errors-into-a-typed-exception.md` (Milestone 1 must be merged before this plan's Milestone 2) adds `OAuthError {oauthErrorCode :: OAuthErrorCode, errorDescription, errorUri, requestId, response}` and `OAuthErrorCode` (including `OAuthInvalidGrant`) to `Notion.V1.OAuth`. With it, `createOAuthToken` throws `OAuthError` when Notion rejects a refresh token. Confirm with `rg -n OAuthInvalidGrant src/Notion/V1/OAuth.hs`.

**The effectful package.** `notion-client-effectful/src/Notion/V1/Effectful/Interpreter.hs` exports `runNotion :: (IOE :> es, Error NotionError :> es) => Methods -> Eff (Notion : es) a -> Eff es a`. It takes a ready `Methods` value, so a `Methods` built from a token source works there without changes. [ADR 7](../adr/7-effectful-package-mirrors-methods-in-lockstep.md) requires lockstep edits only when `Methods` *fields* change, and this plan adds a constructor function, not a field.

**Tests.** `tasty/FakeNotion.hs` exports `fakeClientEnv :: [FakeReply] -> IO (ClientEnv, IORef [Recorded])`. Its `ClientEnv` middleware ignores the network, records `Recorded {method, path, headers}` for each request, and answers from a fixed script. Non-2xx replies are raised as Servant `FailureResponse`, so they pass through the real `notionMiddleware` and become `NotionError` exactly as live responses would. Because a fixed script cannot react to which token a request carries, this plan adds `fakeClientEnvWith :: (Recorded -> IO FakeReply) -> IO (ClientEnv, IORef [Recorded])`, which chooses each reply by calling a function. `fakeClientEnv` keeps its signature and can be reimplemented on top of it. Replace the recorder’s current `modifyIORef'` with `atomicModifyIORef'` so concurrent evidence cannot lose requests. Register new test modules in `tasty/Main.hs` and in the test suite's `other-modules` in `notion-client.cabal`. Fixtures use made-up Japanese names. A Notion `unauthorized` body is `{"object":"error","status":401,"code":"unauthorized","message":"API token is invalid."}`.

Relevant ADRs: [ADR 2](../adr/2-client-runtime-retry-policy-and-typed-errors.md) (the runtime this plan extends; its retry policy must not change) and [ADR 7](../adr/7-effectful-package-mirrors-methods-in-lockstep.md) (not triggered, as explained above). [ADR 1](../adr/1-tolerant-response-decoders.md) does not apply, because no decoded enum is added. [ADR 9](../adr/9-oauth-callback-and-token-lifecycle-boundaries.md) is the accepted design for the proposed lifecycle state machine; its implementation is still pending.


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
-- Scope the action to a replayable request/acquisition, never stream consumption or a user callback.
withStandardHeaders :: RequestContext -> ([Header] -> IO a) -> IO a
```

Export the new names from `Notion.V1.Client`, and re-export `requestContextWithTokenSource`, `withStandardHeaders`, `TokenSource (..)` and `staticTokenSource` from `Notion.V1`.

In `src/Notion/V1.hs`, add `makeMethodsWithTokenSource :: ClientConfig -> ClientEnv -> TokenSource -> Methods`, and redefine `makeMethodsWithEnv config env token = makeMethodsWithTokenSource config env (staticTokenSource token)`. Inside the new function, still pass a fixed placeholder header value to `Client.client @API Proxy`. Replace it per call by changing `run` to

```haskell
run clientM = withAuthorization source $ \auth ->
  runClientWith (configureClientEnv config (withAuthorizationHeader auth clientEnv)) clientM
```

where `withAuthorizationHeader auth env` returns `env` with a middleware that removes any `Authorization` header from the request and adds `("Authorization", encodeUtf8 auth)` before calling the inner function. Keep a small helper in `Notion.V1.Client` for this, and wrap the caller's existing middleware rather than replacing it. Renewal reruns the generated `ClientM` request. Verify replay of this library's byte and file-backed multipart bodies; an arbitrary one-shot stream is not made replayable merely by rerunning `ClientM`. Put authorization injection outside the caller middleware but inside the runtime so every attempt reaches it with exactly one bearer header. Preserve its custom request builder and base URL. Keep this bearer middleware out of `OAuthMethods`, which uses Basic authentication. Establish and test this middleware ordering with the caller middleware before extending the constructor to every method. Update the Haddock comments of `makeMethods*` and the module header example.

Update `tasty/RuntimeTests.hs` line 70 for `standardHeaders` now returning `IO`. Add tests in a new module `tasty/TokenSourceTests.hs` (group "TokenSource"):

1. A `TokenSource` backed by an `IORef` makes two consecutive `retrieveMyUser` calls carry `Bearer t1` and then `Bearer t2` after the `IORef` changes. Exactly one `Authorization` header is recorded per request.
2. With replies `[401 unauthorized, 200 user]` and a source whose `renewToken "old"` returns `Just "new"`, one call succeeds. It records two requests, carrying `Bearer old` and then `Bearer new`, and `renewToken` is called exactly once.
3. With `staticTokenSource`, a 401 `unauthorized` surfaces as `NotionError` with code `Unauthorized` after exactly one request.
4. With replies `[401, 401]` and a renewing source, the second `NotionError` propagates. There are exactly two requests, which proves there is no loop.
5. A 429 `rate_limited` reply is still retried by the runtime, independent of renewal. Use `RetryOptions` with a tiny delay, as `tasty/RuntimeTests.hs` does.
6. The producer/consumer check that stands in for plan 14's streaming must use a loopback HTTP server and the real `http-client` response/error conversion, not only a hand-thrown exception. The first stream-open attempt returns 401, the second accepts the new bearer header. Both carry `Notion-Version` and `User-Agent`; the failed response is closed before renewal. After a successful open, a consumer that throws `NotionError Unauthorized` must propagate without refresh or replay. Put `withStandardHeaders` around the response acquisition only, inside `bracket`'s acquire action, never around reading the body or the user callback. Add test-only `wai` and `warp` if needed.
7. A multipart upload fixture is byte-for-byte replayable after rejection; no arbitrary failed POST, decode failure, timeout, bare HTTP 401 without the typed `Unauthorized` code, or user callback exception triggers renewal. Test Basic OAuth headers stay intact and a caller middleware/custom request builder still runs.
8. Verify rate-limit retries before and after renewal use the existing retry budget independently; there is at most one renewal for the logical request. Compile a small effectful consumer using the new constructor; defer tests of the new lifecycle exceptions until Milestone 2, when those types exist.

Cascade to the dependent plan in the same commit. In `docs/plans/14-stream-session-updates-over-server-sent-events.md`, change the descriptions of `RequestContext` and `standardHeaders` (around lines 121–122) and the `StreamEnv` construction (around line 507) so that authorization comes from `withStandardHeaders` around response acquisition only, with `withRetries` inside it, instead of a fixed `authorization` field. Change the `StreamEnv` record, transport algorithm, construction sites and tests consistently; never wrap the body or user callback in either retry layer. Add a revision note at the bottom of that plan. Add an entry to the Surprises & Discoveries of `docs/masterplans/2-add-the-custom-agents-and-sessions-api-with-sse-streaming.md` that names this plan's path.

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
  deriving stock (Eq, Generic)
-- Redacted Show instance; never expose the token pair in logs.
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

-- | A save failed; pending credentials remain available only through currentTokens.
data TokenPersistenceError -- abstract, Exception and redacted Show
-- | A refresh may have succeeded remotely but its result is unavailable.
data RefreshOutcomeUnknown -- abstract, Exception and redacted Show

data OAuthTokenManager -- abstract: an MVar lifecycle state, OAuthMethods and TokenStore

newOAuthTokenManager :: OAuthMethods -> TokenStore -> IO OAuthTokenManager -- calls loadTokens once
tokenManagerSource :: OAuthTokenManager -> TokenSource
currentTokens :: OAuthTokenManager -> IO OAuthTokens
-- | Refresh now regardless of the current token (for example before a long batch job).
refreshTokensNow :: OAuthTokenManager -> IO OAuthTokens
-- | Retry persistence of a retained pair; never send another OAuth request.
retryTokenPersistence :: OAuthTokenManager -> IO OAuthTokens
```

The manager owns one installation and loads the store exactly once. Keep its lifecycle in an `MVar` with internal states `Ready tokens`, `PendingPersistence tokens`, `NeedsReauthorization cause`, and `UncertainOutcome`. Keep the last known pair alongside every state, including terminal states. `currentTokens` returns it for explicit recovery/inspection only; it is not the source used to authorize requests. `currentToken` waits for an in-progress transition (`readMVar` blocks while the MVar is empty), then returns only a `Ready` token. Pending persistence throws `TokenPersistenceError`; terminal states throw their corresponding exception. Never print token values through `Show` or default exception messages.

For automatic renewal, acquire the same lock and first check the lifecycle. In `Ready`, if the access token differs from the rejected token, return the newer token without refreshing. Otherwise a missing refresh token transitions to `NeedsReauthorization Nothing`. Send one `createOAuthToken (RefreshToken rt)` through plan 16's non-retrying methods. `OAuthInvalidGrant` transitions to `NeedsReauthorization (Just e)` so concurrent waiters do not each retry a dead grant. Other explicit OAuth rejections propagate without marking a known pair invalid; do not automatically retry them. An ambiguous outcome, including a network error, timeout, success-body decode failure, unclassified server failure, or cancellation during the exchange, transitions to `UncertainOutcome` before propagating the failure. Later calls fail with `RefreshOutcomeUnknown` without sending the old refresh token again. Recover by completing a new authorization and constructing a new manager; do not reload a potentially stale store and claim recovery.

On success, validate a nonempty bearer access token and the same bot/workspace identity, convert the response with `oauthTokensFromResponse`, and retain the pair before invoking the caller's store. Preserve the returned `refreshToken` exactly: a null/missing value becomes `Nothing`, never the previous refresh token. Such an access token can be used after persistence but will require reauthorization on a later renewal. Unexpected token type or changed installation identity is a protocol failure with an uncertain refresh outcome, not permission to use a token for another installation.

Call `saveTokens` under the same serialization boundary. On success install `Ready new`; on failure install `PendingPersistence new`, then throw `TokenPersistenceError`. No request may use that pair or initiate another refresh while pending. `retryTokenPersistence` saves the identical retained pair, transitions to `Ready` only on success, and never calls Notion. In `Ready` it is a no-op returning the current pair; in terminal states it throws the terminal error. `saveTokens` must be idempotent for the same pair and must not re-enter the manager. A successful return means persistence has met the application's durability contract.

Implement transitions with asynchronous-exception masking and explicit `Either SomeException result` outcomes: catch around the restored interruptible network/save actions, publish the resulting lifecycle state under masking, then rethrow outside the MVar update. Ordinary `modifyMVar` restores its old value when its action throws, so throwing inside its update after a successful rotation would incorrectly resurrect the old pair. Do not use `uninterruptibleMask` around network or storage. If interruption prevents obtaining a response, record uncertainty; if the response is known, retain it pending persistence. This prevents avoidable in-process loss, but cannot eliminate a process crash between remote rotation and local commit. State this limitation in the API docs.

`refreshTokensNow` acquires the same lock and refreshes only a `Ready` manager. It bypasses the rejected-token comparison, so concurrent explicit calls serialize but may each rotate; automatic rejections for one old token share a single completed refresh. Neither a store implementing compare-and-swap on save nor two separate managers share this lock. Require one manager per installation in one process; applications needing multiple processes must coordinate the entire load/check/remote-refresh/save sequence externally.

Add `tasty/TokenRefreshTests.hs` (group "TokenRefresh"). Use a fake API keyed on the Authorization header and a separate fake OAuth client. Record requests atomically. Use MVar barriers to prove both requests were sent with the old token before releasing either rejection, rather than relying on sleeps; put bounded timeouts around concurrency tests.

1. A rejection refreshes once, persists the pair, retries with the new bearer token, preserves installation identity, and sets `obtainedAt` to the time of the replacement response.
2. Two concurrent old-token rejections share one refresh. A late rejection arriving after completion also uses the new pair without another refresh. A store barrier proves no new-token request is sent before save succeeds.
3. `invalid_grant` and a missing refresh token each put the manager into a terminal reauthorization state. Repeated and concurrent callers make no additional refresh attempts.
4. A failed save retains the new pair; `currentToken` and `refreshTokensNow` fail without network traffic. After storage recovers, `retryTokenPersistence` saves that exact pair, then requests succeed with no second refresh. Repeat with cancellation during save.
5. Simulate a server consuming a refresh and losing its response. The triggering failure propagates, subsequent callers get `RefreshOutcomeUnknown`, and the consumed token is never retried. Also inject cancellation during exchange and immediately after response receipt; assert the lock is released and either uncertainty or the known pending pair is preserved appropriately.
6. A null/missing refresh token is stored as `Nothing`, never replaced with the old token. A later unauthorized response requires reauthorization. Invalid token type or mismatched bot/workspace identity cannot authorize a request.
7. Exercise an effectful consumer with a refreshing `Methods`: final `NotionError` uses `Error NotionError`, while `ReauthorizationRequired`, `TokenPersistenceError` and `RefreshOutcomeUnknown` propagate in IO.
8. `OAuthTokens` round-trips through JSON; token-bearing `Show` and exception messages redact sentinels. Non-`invalid_grant` explicit rejection remains distinguishable, and both explicit-refresh and automatic-refresh paths use the same transitions.

Documentation: in `README.md`'s "### OAuth" section, show `newOAuthTokenManager` and `makeMethodsWithTokenSource`, and explain `ReauthorizationRequired` and the single-process scope of the lock (see Interfaces). In `CHANGELOG.md`, under `## Unreleased` (create it at the top if absent), add a `### Breaking Changes` entry for `RequestContext.contextAuthorization` being replaced by `contextTokenSource` and `standardHeaders` now returning `IO [Header]`, and `### New Features` entries for token sources and the token manager. Update [ADR 9](../adr/9-oauth-callback-and-token-lifecycle-boundaries.md) with the implemented boundaries and any material discoveries, following `agents/skills/exec-plan/ADR.md`. It already records the proposed state machine and its limits; do not create a second ADR covering the same decision. Then add a one-line cross-reference in ADR 2's Consequences.


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

Use deterministic barriers and bounded timeouts for the concurrency cases. Additional repeated runs are useful only when resolving a concurrency failure; passing repetitions do not replace the ordering assertions. Commit at each milestone with Conventional Commits and trailers, for example:

```text
feat(client)!: attach bearer tokens per request through a TokenSource

MasterPlan: docs/masterplans/3-support-notion-public-integrations-with-an-oauth-login-flow.md
ExecPlan: docs/plans/18-refresh-oauth-access-tokens-automatically-for-methods.md
Intention: intention_01m52739hkexps2gwzdp5hnn4a
```


## Validation and Acceptance


Milestone 1 is accepted when all `TokenSource` tests pass, every pre-existing test passes unchanged except the one `standardHeaders` adaptation, `cabal build all` builds `notion-client-effectful` without source changes, and plan 14 and its MasterPlan carry the cascade notes. Milestone 2 is accepted when all `TokenRefresh` tests pass, including the deterministic failure/cancellation and persistence-order cases, and the README example type-checks.

A live refresh against Notion is not required here. It needs real OAuth tokens and is the acceptance of `docs/plans/19-demonstrate-and-document-the-public-integration-oauth-login-end-to-end.md`. If that plan's live run contradicts an assumption here (for example, a response shape differs from the published contract), it records the finding in the MasterPlan, and this plan's semantics must be revisited.


## Idempotence and Recovery


The changes are code and tests and can be re-run. The breaking change to `RequestContext` is confined to one record field and one function signature. Do not retain a stale `contextAuthorization` field as a compatibility workaround; a caller could unknowingly keep using the old token. Keep the legacy constructor functions through `staticTokenSource`. Do not bump the package version; the parent MasterPlan assigns the `0.10.0.0` bump to `docs/plans/19-demonstrate-and-document-the-public-integration-oauth-login-end-to-end.md`.


## Interfaces and Dependencies


No new library package dependencies. Put the effectful consumer check in the companion package or a scratch executable with both library dependencies; do not add a dependency from the core library to its adapter. The real HTTP consumer test adds test-only `wai` and `warp` if absent; verify current releases before choosing bounds. `Control.Concurrent.MVar` and `Control.Exception` come from `base`, and `time` and `aeson` are already library dependencies.

Produced for other plans:

- `Notion.V1.TokenSource`: `TokenSource (..)`, `staticTokenSource`, `withAuthorization`.
- `Notion.V1` / `Notion.V1.Client`: `makeMethodsWithTokenSource :: ClientConfig -> ClientEnv -> TokenSource -> Methods`, `requestContextWithTokenSource`, `withStandardHeaders :: RequestContext -> ([Header] -> IO a) -> IO a`, and `RequestContext {contextConfig, contextManager, contextBaseUrl, contextTokenSource}`. `docs/plans/14-stream-session-updates-over-server-sent-events.md` consumes these.
- `Notion.V1.OAuth.Refresh`: `OAuthTokens (..)`, `oauthTokensFromResponse`, `TokenStore (..)`, `inMemoryTokenStore`, `ReauthorizationRequired (..)`, `OAuthTokenManager`, `newOAuthTokenManager`, `tokenManagerSource`, `currentTokens`, `refreshTokensNow`, `retryTokenPersistence`, `TokenPersistenceError`, `RefreshOutcomeUnknown`. `docs/plans/19-demonstrate-and-document-the-public-integration-oauth-login-end-to-end.md` implements a file-backed `TokenStore` against these and uses them in its example.
- `tasty/FakeNotion.hs`: `fakeClientEnvWith`.

Scope limit to document: the manager serializes refreshes within one manager instance. Several managers or processes sharing one installation must coordinate the whole refresh transaction externally; a compare-and-swap on `saveTokens` alone is too late to prevent two requests consuming the same remote credential. The parent MasterPlan excludes multi-tenant and cross-process stores.

Prerequisites: none for Milestone 1. Milestone 2 requires Milestone 1 of `docs/plans/16-decode-oauth-token-endpoint-errors-into-a-typed-exception.md` (`OAuthError` and `OAuthInvalidGrant`). This plan does not depend on `docs/plans/17-build-authorization-urls-and-exchange-codes-from-verified-oauth-callbacks.md`.


Revision (2026-10-16): Replace optimistic save-failure handling with explicit pending/terminal states, specify cancellation and uncertain remote outcomes, preserve nullable refresh-token responses, and require a real HTTP consumer test plus deterministic concurrency checks.
