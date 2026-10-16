---
id: 16
slug: decode-oauth-token-endpoint-errors-into-a-typed-exception
title: "Decode OAuth Token Endpoint Errors into a Typed Exception"
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

# Decode OAuth Token Endpoint Errors into a Typed Exception

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

A Notion *public integration* is an integration that any Notion user can install. It obtains its API tokens through OAuth 2.0, an authorization protocol in which a program trades a one-time code or a refresh token for an access token at Notion's token endpoint, `POST https://api.notion.com/v1/oauth/token`. The Haskell library in this repository already has functions for that endpoint and for the related revoke and introspect endpoints. When Notion rejects a request, though, the program receives an opaque `UnknownHTTPResponseError` whose message is only "Request to Notion API failed with status: 401". The reason is that these endpoints answer failures in the OAuth error format, `{"error":"invalid_client", ...}`, rather than Notion's usual error format.

After this change a failed OAuth request throws a typed `OAuthError`, whose `oauthErrorCode` field is a Haskell value such as `OAuthInvalidClient` or `OAuthInvalidGrant`, along with Notion's request ID and the HTTP response details. A program can then tell a misconfigured client secret (`invalid_client`) from an authorization code that was already used, or a refresh token that was revoked (`invalid_grant`). It can react accordingly, for example by sending the user back through the login. To see it working, run the network-free tests (`cabal test --test-options='-p OAuth'`) and, optionally, call `createOAuthToken` with made-up credentials and observe `OAuthError {oauthErrorCode = OAuthInvalidClient, ...}` instead of `UnknownHTTPResponseError`.

This plan is EP-1 of `docs/masterplans/3-support-notion-public-integrations-with-an-oauth-login-flow.md`. Its first milestone (M1) is a prerequisite for two sibling plans. `docs/plans/17-build-authorization-urls-and-exchange-codes-from-verified-oauth-callbacks.md` reuses `OAuthErrorCode` for the browser redirect's `error` parameter. `docs/plans/18-refresh-oauth-access-tokens-automatically-for-methods.md` matches on `OAuthInvalidGrant` to detect a dead refresh token.


## Progress

- [ ] Milestone 1: `OAuthErrorCode`, `OAuthError` and `oauthErrorFromResponse` exported from `Notion.V1.OAuth`. `createOAuthToken`, `revokeOAuthToken` and `introspectOAuthToken` throw `OAuthError` for OAuth-format error bodies, while Notion-envelope errors still throw `NotionError`. The new network-free tests in the `OAuth` group pass, and `cabal build all` is green.
- [ ] Milestone 2: A live probe with made-up credentials throws `OAuthError` with `OAuthInvalidClient` and a request ID. README, CHANGELOG (`## Unreleased`) and ADR 2 describe the new error type.


## Surprises & Discoveries

- On 2026-10-16, while drafting the parent MasterPlan, a live probe showed the token endpoint's error format. Command and response (cookies removed):

  ```bash
  curl -s -i -u fake-client:fake-secret -H 'Content-Type: application/json' -H 'Notion-Version: 2026-03-11' \
    -X POST https://api.notion.com/v1/oauth/token \
    -d '{"grant_type":"authorization_code","code":"not-a-code","redirect_uri":"https://example.com/cb"}'
  ```

  ```text
  HTTP/2 401
  content-type: application/json; charset=utf-8
  www-authenticate: Basic realm="OAuth"
  x-notion-request-id: b68d69fd-0001-4efb-8ada-026ec3100def
  cf-ray: a4b6b399dce70c45-LAX

  {"error":"invalid_client","request_id":"b68d69fd-0001-4efb-8ada-026ec3100def"}
  ```

  The body has no `object`, `code` or `message` keys, so the existing `NotionError` decoder rejects it.


## Decision Log

- Decision: Reinterpret the error inside `makeOAuthMethodsWith` (by catching `UnknownHTTPResponseError` and re-decoding its body) rather than change `Notion.V1.Error.buildRequestError` for every route.
  Rationale: Only the OAuth routes use the OAuth error format. Changing the shared classifier would let an unrelated route's odd body become an `OAuthError`, and it would move ADR 2's boundary for every caller of `Methods`. The OAuth routes already have their own methods record, so the change stays local.
  Date: 2026-10-16

- Decision: Prefix every `OAuthErrorCode` constructor with `OAuth` (`OAuthInvalidRequest`, …), and cover both lists in RFC 6749, the OAuth 2.0 specification: the token-endpoint codes from section 5.2 and the authorization-redirect codes from section 4.1.2.1.
  Rationale: `Notion.V1.Error.APIErrorCode` already has an `InvalidRequest` constructor, and programs commonly import both modules. The redirect codes are needed by `docs/plans/17-build-authorization-urls-and-exchange-codes-from-verified-oauth-callbacks.md`, which must not define a second code type.
  Date: 2026-10-16


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Work in the repository root `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`. It is a Cabal project (`cabal.project` lists `.` and `notion-client-effectful`) built with GHC 9.12 and `default-language: GHC2024`. The library's default extensions, set in `notion-client.cabal`, are `DuplicateRecordFields`, `OverloadedLabels`, `OverloadedStrings` and `RecordWildCards`. Code is formatted by `treefmt`, which a pre-commit hook runs. If the hook reformats files, stage them again.

The OAuth endpoints live in `src/Notion/V1/OAuth.hs`. That module defines `OAuthCredentials {clientId, clientSecret}`, the request types `OAuthTokenRequest` (`AuthorizationCode AuthorizationCodeGrant | RefreshToken Text`) and `TokenBody`, the response types (`OAuthTokenResponse`, `OAuthRevokeResponse`, `OAuthIntrospectResponse`), a Servant API type `API` for the three `POST` routes under `oauth/`, and the record

```haskell
data OAuthMethods = OAuthMethods
  { createOAuthToken :: OAuthTokenRequest -> IO OAuthTokenResponse,
    revokeOAuthToken :: Text -> IO OAuthRevokeResponse,
    introspectOAuthToken :: Text -> IO OAuthIntrospectResponse
  }
```

`makeOAuthMethodsWith :: ClientConfig -> ClientEnv -> OAuthCredentials -> OAuthMethods` builds it. It uses Servant's `hoistClient` with `runClientWith (configureClientEnv config env)` and sends `Authorization: Basic base64(client_id:client_secret)`.

"The runtime" means the request pipeline shared by every call in this library. It is described in [ADR 2](../adr/2-client-runtime-retry-policy-and-typed-errors.md) and implemented in `src/Notion/V1/Client.hs` (`configureClientEnv`, `notionMiddleware`, `withRetries`, `runClientWith`) and `src/Notion/V1/Error.hs`. When a response is not 2xx, `Notion.V1.Error.buildRequestError` tries to decode the body as a `NotionError`, Notion's usual error envelope `{"object":"error","status":…,"code":…,"message":…}`, which requires `code` and `message`. If that fails, the result is `UnknownHTTPResponseError`, a newtype over

```haskell
data HttpErrorResponse = HttpErrorResponse
  { httpStatus :: Int,
    errorHeaders :: ResponseHeaders,
    notionRequestId :: Maybe Text,   -- the x-notion-request-id header
    rayId :: Maybe Text,             -- the cf-ray header
    errorBody :: ByteString          -- lazy ByteString, raw body
  }
```

`notionMiddleware` throws that exception with `throwIO` from inside the request. It reaches the caller of, for example, `createOAuthToken` as an ordinary IO exception. `withRetries` retries only `NotionError` values with retryable codes (`rate_limited`, `service_overload`, and some 5xx codes for `GET`/`DELETE`), so an `UnknownHTTPResponseError` is never retried. The new `OAuthError` must keep that property.

The OAuth error format comes from RFC 6749 section 5.2. Its body is a JSON object with a required `error` string and optional `error_description` and `error_uri` strings. Notion adds `request_id`. The standard token-endpoint codes are `invalid_request`, `invalid_client`, `invalid_grant`, `unauthorized_client`, `unsupported_grant_type` and `invalid_scope`. RFC 6749 section 4.1.2.1 defines the codes Notion may put in the browser redirect after the consent page: `invalid_request`, `unauthorized_client`, `access_denied`, `unsupported_response_type`, `invalid_scope`, `server_error` and `temporarily_unavailable`. Notion's authorization guide (https://developers.notion.com/docs/authorization) documents `error=access_denied` for a cancelled consent. The official Notion JS SDK (`/Users/shinzui/Keikaku/hub/notion-sdk-js`, `src/api-endpoints/oauth.ts`) types the success bodies only, so the live probe in Surprises & Discoveries is the wire-format evidence, as [ADR 6](../adr/6-js-sdk-types-are-the-wire-format-reference.md) allows ("a live check against the API overrides the SDK types").

Tests live in `tasty/`. `tasty/OAuthTests.hs` exports `tests :: TestTree`, the "OAuth" group, which is registered in `tasty/Main.hs`. `tasty/FakeNotion.hs` provides `fakeClientEnv :: [FakeReply] -> IO (ClientEnv, IORef [Recorded])`, a `ClientEnv` that answers from a script without the network, and `jsonReply :: Int -> LBS.ByteString -> FakeReply`. A non-2xx scripted reply is raised as a Servant `FailureResponse` and then goes through the real runtime middleware, so a fake 401 produces exactly the exception a real one would. `FakeReply {status, replyHeaders, body}` can carry headers such as `x-notion-request-id`. Test fixtures that need a person's name use made-up Japanese names such as "Tanaka Hanako".

Relevant ADRs:

- [ADR 1](../adr/1-tolerant-response-decoders.md): decoded enums carry an unknown fallback. `OAuthErrorCode` needs `UnknownOAuthErrorCode Text`.
- [ADR 2](../adr/2-client-runtime-retry-policy-and-typed-errors.md): defines the `NotionError`/`UnknownHTTPResponseError` split that this plan refines for OAuth routes. Milestone 2 amends it.

No other ADR applies.


## Plan of Work

### Milestone 1: typed OAuth errors

In `src/Notion/V1/OAuth.hs`, add an "Errors" section to the export list with `OAuthErrorCode (..)`, `oauthErrorCodeText`, `parseOAuthErrorCode`, `OAuthError (..)` and `oauthErrorFromResponse`.

Define

```haskell
data OAuthErrorCode
  = OAuthInvalidRequest
  | OAuthInvalidClient
  | OAuthInvalidGrant
  | OAuthUnauthorizedClient
  | OAuthUnsupportedGrantType
  | OAuthInvalidScope
  | OAuthAccessDenied
  | OAuthUnsupportedResponseType
  | OAuthServerError
  | OAuthTemporarilyUnavailable
  | -- | A code this library does not know yet, carried verbatim.
    UnknownOAuthErrorCode Text
  deriving stock (Eq, Show)
```

with `oauthErrorCodeText :: OAuthErrorCode -> Text` (the snake_case wire string) and `parseOAuthErrorCode :: Text -> OAuthErrorCode`, inverse functions in the style of `apiErrorCodeText`/`parseAPIErrorCode` in `src/Notion/V1/Error.hs`. Add `FromJSON` and `ToJSON` instances through those functions.

Define the exception:

```haskell
-- | An OAuth-format error from @/v1/oauth/*@ (RFC 6749 section 5.2).
data OAuthError = OAuthError
  { oauthErrorCode :: OAuthErrorCode,
    errorDescription :: Maybe Text,
    errorUri :: Maybe Text,
    -- | The body's @request_id@, or else the @x-notion-request-id@ header.
    requestId :: Maybe Text,
    -- | 'Nothing' when decoded from bare JSON rather than an HTTP response.
    response :: Maybe HttpErrorResponse
  }
  deriving stock (Eq, Show)
```

Its `FromJSON` instance requires `error` and reads `error_description`, `error_uri` and `request_id` optionally, with `response = Nothing`. Its `Exception` instance gives a `displayException` such as `Notion OAuth request failed: invalid_client (HTTP 401): <description>`, omitting the parts that are absent. `oauthErrorFromResponse :: HttpErrorResponse -> Maybe OAuthError` decodes `errorBody` with `Aeson.decode` and fills `response` and the `requestId` fallback. It returns `Nothing` when the body is not an OAuth error object.

Then change `makeOAuthMethodsWith` so that each of the three fields is wrapped by a local function `reinterpret :: IO a -> IO a`. This function catches `UnknownHTTPResponseError (meta)` and throws `oauthErrorFromResponse meta` when that is `Just`; otherwise it rethrows the original exception unchanged. Use `Control.Exception.handle` or `catch`, and catch only `UnknownHTTPResponseError`, so that `NotionError`, `RequestTimeoutError` and connection failures pass through. `UnknownHTTPResponseError` comes from `Notion.V1.Error`, which `src/Notion/V1/OAuth.hs` does not import yet.

Update the module header comment of `src/Notion/V1/OAuth.hs` to mention that failures throw `OAuthError`.

Add the following cases to `tasty/OAuthTests.hs`. Each fake test builds `makeOAuthMethodsWith defaultClientConfig env credentials` with the existing `credentials` value and uses `Control.Exception.try`.

1. The probe body `{"error":"invalid_client","request_id":"b68d69fd-0001-4efb-8ada-026ec3100def"}`, scripted as `jsonReply 401`, makes `createOAuthToken` throw `OAuthError` with `oauthErrorCode = OAuthInvalidClient`, that `requestId`, and `httpStatus` 401 in `response`.
2. A `400` with `{"error":"invalid_grant","error_description":"Invalid code."}` and an `x-notion-request-id: r-oauth-2` header, but no body `request_id`, gives `OAuthInvalidGrant`, `errorDescription = Just "Invalid code."`, and `requestId = Just "r-oauth-2"` taken from the header.
3. A Notion envelope `{"object":"error","status":400,"code":"validation_error","message":"bad"}` from `revokeOAuthToken` still throws `NotionError` (catching `OAuthError` must not match).
4. A `502` with a non-JSON body from `introspectOAuthToken` still throws `UnknownHTTPResponseError`.
5. `{"error":"slow_down"}` decodes to `UnknownOAuthErrorCode "slow_down"`, and `oauthErrorCodeText` round-trips every named constructor through `parseOAuthErrorCode`.
6. The fake records exactly one request for case 1, which proves that the error is not retried.

### Milestone 2: live confirmation and documentation

With network access, run the live probe below from `cabal repl`. It needs no real integration, because made-up credentials are enough to provoke `invalid_client`. Record the result in Surprises & Discoveries. If Notion now answers with a different shape, change the decoder to match and record the change in the Decision Log.

Document the behavior. In `README.md`, in the "### OAuth" section, say that the OAuth methods throw `OAuthError` and give a short example of matching on `OAuthInvalidGrant`. In `CHANGELOG.md`, add a `## Unreleased` heading at the top if none exists and, under `### New Features`, an entry for `OAuthError`/`OAuthErrorCode`. Under `### Breaking Changes`, add an entry saying that OAuth endpoint failures that used to throw `UnknownHTTPResponseError` now throw `OAuthError`, because code catching `UnknownHTTPResponseError` around `createOAuthToken` changes behavior. In [ADR 2](../adr/2-client-runtime-retry-policy-and-typed-errors.md), add a dated amendment under "Decision → Errors": OAuth routes reinterpret an OAuth-format body as `OAuthError`, which is never retried, and other routes are unchanged. Follow `agents/skills/exec-plan/ADR.md`. The ADR directory is a plain numbered directory with `Status:`/`Date:` lines, not an OKF-profiled bundle, so keep that format.


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`.

Build and run the OAuth tests:

```bash
cabal build all
cabal test --test-show-details=direct --test-options='-p OAuth'
```

Expected tail after Milestone 1 (counts grow by the new cases):

```text
    OAuth
      basicAuthorization encodes client_id:client_secret:  OK
      ...
      invalid_client error body throws OAuthError:          OK
      Notion envelope from OAuth route stays NotionError:   OK
  All N tests passed
```

Live probe for Milestone 2:

```bash
cabal repl notion-client
```

```haskell
:set -XOverloadedStrings -XNamedFieldPuns
import Network.HTTP.Client.TLS (newTlsManager)
import Servant.Client (mkClientEnv)
import Control.Exception (try)
import Notion.V1 (defaultClientConfig, defaultBaseUrl)
import Notion.V1.OAuth
m <- newTlsManager
let oauth = makeOAuthMethodsWith defaultClientConfig (mkClientEnv m defaultBaseUrl) (OAuthCredentials "fake-client" "fake-secret")
r <- try (createOAuthToken oauth (AuthorizationCode (AuthorizationCodeGrant "not-a-code" (Just "https://example.com/cb") Nothing)))
either (\OAuthError {oauthErrorCode, requestId} -> print (oauthErrorCode, requestId)) (const (putStrLn "unexpected success")) r
```

Expected output, with a different request ID:

```text
(OAuthInvalidClient,Just "…")
```

Run the whole suite before committing. The live E2E groups in `tasty/Main.hs` skip themselves without `NOTION_TOKEN`:

```bash
cabal test --test-show-details=direct
```

Commit with Conventional Commits and the trailers:

```text
feat(oauth)!: throw typed OAuthError for OAuth-format error bodies

MasterPlan: docs/masterplans/3-support-notion-public-integrations-with-an-oauth-login-flow.md
ExecPlan: docs/plans/16-decode-oauth-token-endpoint-errors-into-a-typed-exception.md
Intention: intention_01m52739hkexps2gwzdp5hnn4a
```


## Validation and Acceptance

Acceptance for Milestone 1: the six new cases pass, the existing `OAuth` cases still pass, and `cabal build all` builds both packages without warnings in the changed module. Case 3 and case 4 are the guard that Notion's own envelope and non-JSON failures keep their existing types. Case 6 is the guard that OAuth errors are not retried.

Acceptance for Milestone 2: the live probe prints `OAuthInvalidClient` and a request ID. If the machine has no network access, record that in Progress and leave Milestone 2 open; Milestone 1 alone satisfies the dependency that sibling plans have on this plan ("EP-1 M1" in the MasterPlan).


## Idempotence and Recovery

All changes are additive code and tests, and they can be re-run freely. The live probe uses made-up credentials, cannot affect any Notion workspace, and can be repeated. If `treefmt` rewrites files during commit, re-stage and commit again.


## Interfaces and Dependencies

No new package dependencies. `aeson`, `http-types` and `text` are already in the library's `build-depends`.

At the end of Milestone 1, `Notion.V1.OAuth` exports:

```haskell
data OAuthErrorCode = OAuthInvalidRequest | OAuthInvalidClient | OAuthInvalidGrant
  | OAuthUnauthorizedClient | OAuthUnsupportedGrantType | OAuthInvalidScope
  | OAuthAccessDenied | OAuthUnsupportedResponseType | OAuthServerError
  | OAuthTemporarilyUnavailable | UnknownOAuthErrorCode Text
oauthErrorCodeText :: OAuthErrorCode -> Text
parseOAuthErrorCode :: Text -> OAuthErrorCode
data OAuthError = OAuthError
  { oauthErrorCode :: OAuthErrorCode, errorDescription :: Maybe Text, errorUri :: Maybe Text,
    requestId :: Maybe Text, response :: Maybe HttpErrorResponse }
instance Exception OAuthError
oauthErrorFromResponse :: HttpErrorResponse -> Maybe OAuthError
```

`docs/plans/17-build-authorization-urls-and-exchange-codes-from-verified-oauth-callbacks.md` uses `OAuthErrorCode` and `parseOAuthErrorCode` for the redirect's `error` parameter. `docs/plans/18-refresh-oauth-access-tokens-automatically-for-methods.md` catches `OAuthError` and matches on `OAuthInvalidGrant`. Do not rename these after Milestone 1 lands without updating both plans and the MasterPlan's Integration Points.

This plan has no prerequisites.
