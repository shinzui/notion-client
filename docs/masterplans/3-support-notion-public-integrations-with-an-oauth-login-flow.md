---
id: 3
slug: support-notion-public-integrations-with-an-oauth-login-flow
title: "Support Notion Public Integrations with an OAuth Login Flow"
kind: master-plan
created_at: 2026-10-16T11:24:45Z
intention: "intention_01m52739hkexps2gwzdp5hnn4a"
provenance:
  created_by:
    model: "claude-opus-5-5"
    harness: "claude-code"
    at: 2026-10-16T11:24:45Z
---

# Support Notion Public Integrations with an OAuth Login Flow

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Vision & Scope

Notion has two kinds of integrations. An *internal* integration belongs to one workspace and authenticates with a fixed secret pasted into the program. A *public* integration (Notion's developer portal now calls it a "public connection") can be installed by any Notion user into any workspace. It authenticates through OAuth 2.0: the program sends the user to Notion's consent page, Notion redirects the browser back to the program with a one-time *authorization code*, and the program exchanges that code for an *access token* (used as the bearer token on every API call) and a *refresh token* (used later to obtain a new access token). Notion's authorization guide (https://developers.notion.com/docs/authorization) states that refreshing "will generate a new access token and a new refresh token", so the refresh token *rotates*: after a refresh the old refresh token is dead and the new pair must be stored.

The Haskell library `notion-client` (repository root `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`) already has the raw token endpoints in `src/Notion/V1/OAuth.hs`: `createOAuthToken` (authorization-code and refresh-token grants), `revokeOAuthToken` and `introspectOAuthToken`, authenticated with HTTP Basic credentials. They were added by `docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md`, whose live OAuth check was skipped for lack of credentials. Everything around those endpoints that a real login flow needs is missing:

- There is no way to build the consent URL (`https://api.notion.com/v1/oauth/authorize?client_id=…&response_type=code&owner=user&redirect_uri=…&state=…`), to generate the unguessable `state` value that protects the redirect against cross-site request forgery, or to parse and verify the redirect's query string (`code` and `state` on success, `error=access_denied` when the user cancels).
- A failed token request is unreadable. A probe on 2026-10-16 with made-up credentials returned HTTP 401 with body `{"error":"invalid_client","request_id":"b68d69fd-…"}`. That is the OAuth error format, not Notion's usual `{"object":"error","code":…,"message":…}` envelope, so the runtime in `src/Notion/V1/Error.hs` reports it as an opaque `UnknownHTTPResponseError`. A program cannot tell a reused code or a revoked refresh token (`invalid_grant`) from a misconfigured client (`invalid_client`).
- `Methods` (the record of API calls built by `makeMethodsWith` in `src/Notion/V1.hs`) captures one bearer token when it is constructed. When that access token stops working there is no way to swap in a refreshed one, so every caller must rebuild `Methods` by hand and coordinate rotation of the refresh token themselves.
- Nothing shows the pieces working together against a real public integration.

After this initiative a Haskell program can run Notion's whole public-integration login. It builds the authorization URL with a fresh state value, verifies the callback, and exchanges the code; failures raise a typed `OAuthError` carrying codes such as `OAuthInvalidGrant`. It then obtains a `Methods` whose access token refreshes itself when Notion answers `unauthorized`. The refreshed token pair is persisted through a caller-supplied store, at most one refresh runs at a time, and a dead refresh token raises `ReauthorizationRequired` so the program can send the user through the login again. A new example executable runs the full flow against a real public integration on `localhost` and stores the tokens in a local file.

In scope: the authorization URL and state; callback parsing and verification; typed OAuth errors for the token, revoke and introspect endpoints; a pluggable token source used by `Methods` and by non-Servant requests built from `RequestContext`; refresh with rotation-safe persistence hooks; an example application; and README and CHANGELOG documentation.

Explicitly excluded: a web-framework integration (the library parses a query string and does not depend on Warp, Servant server or Yesod); persistence beyond an in-memory store (the example's file store stays in the example); a multi-tenant store keyed by workspace or bot ID (one token source serves one installation, and callers keep one per installation); PKCE (proof key for code exchange), which Notion's public-integration flow does not document; Notion's MCP server OAuth, which is a different authorization server; and proactive refresh on a timer, because Notion's token response carries no `expires_in`.


## Decomposition Strategy

The work splits into three library behaviors and one end-to-end demonstration, each verifiable on its own:

- **EP-1, typed OAuth errors.** It changes how the existing OAuth endpoints report failure and defines the error-code type that the other plans reuse. It is small, but the type is shared by two later plans, and the work touches the error-classification rules recorded in ADR 2, so it gets its own plan and owner.
- **EP-2, authorization request and callback.** Mostly pure code: building a URL and validating a query string, plus the code exchange that sends the same `redirect_uri` the URL used. A web application can adopt it without the refresh machinery.
- **EP-3, token source and refresh.** This changes the client runtime itself: how the `Authorization` header is attached to each request, how a rejected token triggers one refresh and one retry, and how non-Servant requests built from `RequestContext` take part. It is the riskiest plan, because it changes the shared runtime (ADR 2), the public `RequestContext` type, and concurrency behavior.
- **EP-4, end-to-end example and documentation.** It is the integration gate. It needs a real public integration, a browser and a person to click "Allow", so it is the only plan whose acceptance is a live run rather than network-free tests.

Alternatives considered:

- **One plan for all library work.** Rejected. The URL and callback work is low-risk and useful by itself. The refresh work changes the runtime and carries concurrency risk, and combining them would hold the simple part hostage to the hard one.
- **Folding typed errors into EP-2.** Rejected because EP-3 needs `OAuthInvalidGrant` to recognise a dead refresh token. With the type inside EP-2, EP-3 would depend on the whole login plan just for an error type.
- **Rebuilding `Methods` on every refresh instead of a per-request token source.** Rejected. Callers hold `Methods` values in long-lived application state and in `notion-client-effectful`'s `runNotion`, so a replaced value would not reach them. A token read once per request keeps `Methods` stable. It also leaves the `Methods` fields unchanged, so the lockstep rule in ADR 7 is not triggered.

ADR context, all local (`docs/adr/` is a plain numbered directory, not an OKF-profiled bundle):

- [ADR 2](../adr/2-client-runtime-retry-policy-and-typed-errors.md) defines the single client runtime (`src/Notion/V1/Client.hs`, `src/Notion/V1/Retry.hs`, `src/Notion/V1/Error.hs`), the retry policy keyed on the body's error code, and the split between `NotionError` and `UnknownHTTPResponseError`. EP-1 extends the classification for OAuth routes. EP-3 adds authorization and refresh to the same runtime, and the refresh retry must not change ADR 2's retry policy.
- [ADR 1](../adr/1-tolerant-response-decoders.md) requires a fallback constructor for unknown values in decoded enums. That applies to the new OAuth error-code type.
- [ADR 6](../adr/6-js-sdk-types-are-the-wire-format-reference.md) makes the JS SDK (`/Users/shinzui/Keikaku/hub/notion-sdk-js`, `src/api-endpoints/oauth.ts`) the wire-format reference, with live checks taking precedence. The SDK types no OAuth error bodies and has no authorize-URL helper, so this initiative relies on the live probe and Notion's authorization guide.
- [ADR 7](../adr/7-effectful-package-mirrors-methods-in-lockstep.md) requires lockstep changes to `notion-client-effectful` when `Methods` fields change. This initiative adds constructors, not fields. `runNotion` in `notion-client-effectful/src/Notion/V1/Effectful/Interpreter.hs` takes a `Methods` value, so a refreshing `Methods` works there unchanged.
- [ADR 8](../adr/8-core-parity-scope-exclusions.md) records the core client's scope exclusions. The exclusions above follow its pattern.

A Mori concept search for OAuth (`mori registry concepts --search oauth`) found only ADRs of `shinzui/shomei`, an authorization server whose decisions concern minting codes. None applies to a client of Notion's OAuth.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 1 | Decode OAuth Token Endpoint Errors into a Typed Exception | docs/plans/16-decode-oauth-token-endpoint-errors-into-a-typed-exception.md | None | None | Not Started |
| 2 | Build Authorization URLs and Exchange Codes from Verified OAuth Callbacks | docs/plans/17-build-authorization-urls-and-exchange-codes-from-verified-oauth-callbacks.md | EP-1 M1 (for EP-2 M2 only) | None | Not Started |
| 3 | Refresh OAuth Access Tokens Automatically for Methods | docs/plans/18-refresh-oauth-access-tokens-automatically-for-methods.md | EP-1 M1 (for EP-3 M2 only) | None | Not Started |
| 4 | Demonstrate and Document the Public Integration OAuth Login End to End | docs/plans/19-demonstrate-and-document-the-public-integration-oauth-login-end-to-end.md | EP-1, EP-2, EP-3 | None | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-1, EP-3).
A whole-child hard dependency requires that child to be Complete. If only a milestone's
accepted output is needed, name it explicitly (e.g., EP-1 M1) and explain it below.

"EP-1 M1" is EP-1's first milestone: `OAuthErrorCode` and `OAuthError` exported from `Notion.V1.OAuth`, and the OAuth methods throwing `OAuthError` for OAuth-format error bodies, with network-free tests passing.


## Dependency Graph

EP-1 has no prerequisites and should start first. It is small.

EP-2's first milestone (authorization URL and state generation) depends on nothing and can start alongside EP-1. EP-2's second milestone parses the callback's `error` parameter into `OAuthErrorCode`. It therefore needs EP-1 M1 merged, so the callback and the token endpoint share one error-code type.

EP-3's first milestone (per-request authorization through a token source, and the `RequestContext` change) depends on nothing and can also start immediately. Its second milestone, the OAuth token manager, depends on EP-1 M1. A refresh that fails with `OAuthError {oauthErrorCode = OAuthInvalidGrant}` is how EP-3 recognises a dead refresh token and raises `ReauthorizationRequired`. Without the typed error, EP-3 would have to parse `UnknownHTTPResponseError` bodies itself and duplicate EP-1. EP-3 does not depend on EP-2. EP-1, EP-2 M1 and EP-3 M1 can all run in parallel, and EP-2 M2 and EP-3 M2 can run in parallel once EP-1 M1 lands.

EP-4 depends on all three. Its example runs the full flow: EP-2 for login, EP-3 for the refreshing `Methods`, and EP-1 so that failures print readable errors.

```text
EP-1 ──M1──┬──> EP-2 M2 ──┐
           └──> EP-3 M2 ──┼──> EP-4 (needs EP-1, EP-2, EP-3 Complete)
EP-2 M1 (independent) ────┤
EP-3 M1 (independent) ────┘
```


## Integration Points

**`OAuthErrorCode` and `OAuthError` (owned by EP-1, module `Notion.V1.OAuth`).** EP-1 defines `OAuthErrorCode`, with constructors named with an `OAuth` prefix because `Notion.V1.Error.APIErrorCode` already has `InvalidRequest`. It covers both RFC 6749 lists: the token-endpoint codes (`invalid_request`, `invalid_client`, `invalid_grant`, `unauthorized_client`, `unsupported_grant_type`, `invalid_scope`) and the authorization-redirect codes (`access_denied`, `unsupported_response_type`, `server_error`, `temporarily_unavailable`), plus `UnknownOAuthErrorCode Text`. EP-1 also defines the `OAuthError` exception record. EP-2 reuses `OAuthErrorCode` for the callback's `error` parameter and must not define a second code type. EP-3 matches on `OAuthInvalidGrant` and re-exports nothing from it.

**`src/Notion/V1/OAuth.hs` export list.** EP-1 adds error types there. EP-2 and EP-3 put their code in new modules, `Notion.V1.OAuth.Authorization` (EP-2) and `Notion.V1.OAuth.Refresh` (EP-3), which import `Notion.V1.OAuth`. `Notion.V1.OAuth` must not re-export them, because that would create an import cycle. Only EP-1 edits `Notion.V1.OAuth`'s export list. If EP-2 or EP-3 needs a change to `OAuthMethods`, it records the change in its own Decision Log and makes it additively.

**Token source and `RequestContext` (owned by EP-3, modules `Notion.V1.TokenSource`, `Notion.V1.Client` and `Notion.V1`).** EP-3 introduces `TokenSource`, which supplies the current access token and refreshes it on request. EP-3 changes `RequestContext` so that non-Servant requests read the token per request, and adds `makeMethodsWithTokenSource`. `RequestContext` is a public type, and the not-yet-started `docs/plans/14-stream-session-updates-over-server-sent-events.md` (child EP-3 of `docs/masterplans/2-add-the-custom-agents-and-sessions-api-with-sse-streaming.md`) plans to read `contextAuthorization` as a fixed `Text`. When EP-3 changes that field, it must, in the same change, update plan 14's Context and Interfaces sections and its MasterPlan's Surprises & Discoveries to describe the new way to obtain the header. Because plan 14 has not started, no code needs migrating. The representative producer/consumer check is EP-3's test that sends a hand-built `http-client` request through the new building block and observes a refresh. That check stands in for plan 14's streaming consumer.

**`OAuthTokens` and `TokenStore` (owned by EP-3, module `Notion.V1.OAuth.Refresh`).** EP-3 defines the persisted token pair (`OAuthTokens`, with JSON instances so that callers can store it) and the `TokenStore` record (`loadTokens`, `saveTokens`), with an in-memory implementation only. EP-2's `exchangeAuthorizationCode` returns the existing `OAuthTokenResponse`. EP-3 provides `oauthTokensFromResponse` to convert it, so EP-2 does not need to know about `OAuthTokens`. EP-4 implements a file-backed `TokenStore` inside the example executable.

**`CHANGELOG.md` and the package version.** Each library plan adds its entries under a `## Unreleased` heading at the top of `CHANGELOG.md` (the first plan to land creates the heading). EP-3's `RequestContext` change is breaking, so the next release is `0.10.0.0`. EP-4 owns the version bump in `notion-client.cabal`, the matching move of the `notion-client >=0.9 && <0.10` bound in `notion-client-effectful/notion-client-effectful.cabal` (ADR 7), and the README rewrite. No intermediate plan bumps the version.

**`tasty/OAuthTests.hs` and `tasty/FakeNotion.hs`.** EP-1 and EP-2 both add cases to the existing `OAuth` test group, or EP-2 adds a sibling group in a new module, and each plan owns only its own cases. `FakeNotion.fakeClientEnv` already replays non-2xx replies as `FailureResponse`, which passes through the real runtime middleware, so all plans can test error and refresh paths without the network. EP-3 may extend `FakeNotion` with a reply that depends on the request's `Authorization` header. It must keep the existing `fakeClientEnv` signature.

Cross-plan decisions likely to deserve ADRs:

- **OAuth error format (EP-1).** OAuth routes report OAuth-format failures as `OAuthError`, distinct from `NotionError` and never retried. This is an amendment to ADR 2 or a new ADR.
- **Per-request authorization (EP-3).** The bearer token is obtained from a `TokenSource` for each request. Refresh is reactive: it is triggered by a `unauthorized` error code, never by a timer. At most one refresh runs at a time, rotated tokens are persisted before they are used, a rejected request gets exactly one retry after a refresh, and that retry is separate from ADR 2's retry policy. This is a new ADR.
- **Scope exclusions (EP-4, at completion).** No web-framework dependency, no persistence beyond memory, no multi-tenant store, no PKCE. This is a new ADR or an amendment to ADR 8.


## Progress

No child plans have started. EP-1, EP-2 M1 and EP-3 M1 can begin immediately and in parallel.

The initiative's integration gate is EP-4's live run, which requires a real Notion public integration. Its client ID and client secret must be supplied as `NOTION_OAUTH_CLIENT_ID` and `NOTION_OAUTH_CLIENT_SECRET`, and its redirect URI must be registered in the Notion developer portal. A person must also complete the consent page in a browser. Until that run passes, the initiative is not complete, even if every network-free test passes.


## Surprises & Discoveries

- Notion's token endpoint uses the OAuth error format, not Notion's error envelope. With credentials `fake-client:fake-secret`, `POST https://api.notion.com/v1/oauth/token` returned HTTP 401, `www-authenticate: Basic realm="OAuth"`, and body `{"error":"invalid_client","request_id":"b68d69fd-0001-4efb-8ada-026ec3100def"}`. Today this surfaces as `UnknownHTTPResponseError`. This finding motivates EP-1. (2026-10-16)
- `GET https://api.notion.com/v1/oauth/authorize?client_id=fake&response_type=code&owner=user&redirect_uri=http%3A%2F%2Flocalhost%3A8765%2Fcallback` answers HTTP 302 to `https://app.notion.com/install-integration?…`, carrying the same parameters, even for an unknown client ID. So a URL that builds correctly proves nothing about whether the client ID or redirect URI is valid. Only EP-4's live run can show that. (2026-10-16)


## Decision Log

- Decision: Four child plans: typed OAuth errors, authorization URL and callback, token source and refresh, and an end-to-end example. Milestone-level hard dependencies on EP-1 M1 let EP-2 and EP-3 proceed in parallel.
  Rationale: Each plan proves an independent behavior. The shared error-code type has one owner. The runtime-changing refresh work is isolated from the low-risk URL work. See Decomposition Strategy.
  Date: 2026-10-16

- Decision: Refresh is triggered by a `unauthorized` response, plus an explicit refresh call, never by a timer.
  Rationale: Notion's token response has no `expires_in`, so the library cannot know when a token expires.
  Date: 2026-10-16


## Outcomes & Retrospective

(To be filled during and after implementation.)
