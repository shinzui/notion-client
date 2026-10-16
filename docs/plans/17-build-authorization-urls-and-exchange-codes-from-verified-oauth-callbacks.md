---
id: 17
slug: build-authorization-urls-and-exchange-codes-from-verified-oauth-callbacks
title: "Build Authorization URLs and Exchange Codes from Verified OAuth Callbacks"
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
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-16T11:53:13Z
      verdict: "approved"
      note: "Revised design reviewed against code, relevant ADRs and current upstream contracts; implementation and live OAuth acceptance remain pending."
---

# Build Authorization URLs and Exchange Codes from Verified OAuth Callbacks


This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture


A Notion *public integration* can be installed by any Notion user. A user installs it by logging in through OAuth 2.0, an authorization protocol with three steps. First, the program sends the user's browser to Notion's consent page, an *authorization URL* that names the integration and the address to return to. Second, after the user clicks "Allow", Notion redirects the browser to that address, the *redirect URI*, adding a one-time *authorization code* to the query string. Third, the program exchanges the code for tokens at Notion's token endpoint. To stop another website from injecting its own code into the user's session (a cross-site request forgery, or CSRF, attack), the program also puts a random *state* value in the authorization URL, remembers it (in server-side session storage, bound to the initiating browser), and accepts the redirect only if the same state comes back.

The Haskell library in this repository can already perform the third step (`createOAuthToken` in `Notion.V1.OAuth`), but it cannot help with the first two. After this change a program can:

- generate a state value from a cryptographically secure random source with `newOAuthState`;
- build the exact authorization URL with `authorizationUrl`;
- hand the redirect's query string to `verifyAuthorizationCallback`, which either returns the code or explains what went wrong: the user cancelled (`error=access_denied`), the state does not match, or the callback is malformed;
- exchange the code with `exchangeAuthorizationCode`, which always sends the same `redirect_uri` that the URL used, as Notion requires.

To see it working, run `cabal test --test-options='-p Authorization'` and paste a URL printed by `authorizationUrl` into a browser. With a real integration's client ID, Notion shows its consent page. The full browser round trip against a real integration is demonstrated by the sibling plan `docs/plans/19-demonstrate-and-document-the-public-integration-oauth-login-end-to-end.md`.

This plan is EP-2 of `docs/masterplans/3-support-notion-public-integrations-with-an-oauth-login-flow.md`.


## Progress


- [ ] Milestone 1: `Notion.V1.OAuth.Authorization` exports `OAuthState`, `newOAuthState`, `AuthorizationRequest` and `authorizationUrl`. Tests show the exact URL for a fixed request, and show that state values are 43 URL-safe characters that differ between calls. A live `curl` of a generated URL answers HTTP 302 to `app.notion.com/install-integration`.
- [ ] Milestone 2 (requires EP-1 M1): `verifyAuthorizationCallback`, `AuthorizationCallbackError`, `OAuthCode`, `authorizationCodeGrant` and `exchangeAuthorizationCode` exist. Tests cover success, cancellation, state mismatch, missing state, missing code and percent-encoded values. README and CHANGELOG describe the login steps.


## Surprises & Discoveries


- During MasterPlan drafting (2026-10-16), `GET https://api.notion.com/v1/oauth/authorize?client_id=fake&response_type=code&owner=user&redirect_uri=http%3A%2F%2Flocalhost%3A8765%2Fcallback` answered HTTP 302 with `Location: https://app.notion.com/install-integration?response_type=code&client_id=fake&redirect_uri=http%3A%2F%2Flocalhost%3A8765%2Fcallback&owner=user`, even though the client ID is made up. The redirect proves that the parameters are well-formed, not that the client ID or redirect URI is valid.


## Decision Log


- Decision: Put the new code in a new module, `Notion.V1.OAuth.Authorization`, which imports `Notion.V1.OAuth`, and do not re-export it from `Notion.V1.OAuth`.
  Rationale: Re-exporting would create an import cycle. The parent MasterPlan also assigns the export list of `Notion.V1.OAuth` to `docs/plans/16-decode-oauth-token-endpoint-errors-into-a-typed-exception.md`, so that parallel plans do not collide in it.
  Date: 2026-10-16

- Decision: Take the callback as an http-types `Query` (`[(ByteString, Maybe ByteString)]`) and do not depend on any web framework.
  Rationale: Every Haskell web stack (WAI/Warp, Servant server, Yesod, Scotty) can produce a `Query`, and `Network.HTTP.Types.parseQuery` turns a raw query string into one. `http-types` is already a library dependency. The parent MasterPlan excludes web-framework integration.
  Date: 2026-10-16

- Decision: Use `entropy` (`System.Entropy.getEntropy`) for state randomness and `memory` (`Data.ByteArray.constEq`) for comparison.
  Rationale: `random`, which the library already uses for retry jitter, is not a cryptographically secure generator. `entropy` supplies operating-system randomness. `memory` supplies an established comparison primitive; a hand-written Haskell fold is not evidence of constant-time machine code. On 2026-10-16 Hackage and upstream tags agree on entropy 0.4.1.11 and memory 0.18.0.
  Date: 2026-10-16

- Decision: When the redirect carries `error`, report `AuthorizationDenied` before checking the state. Report `StateMismatch` before looking at `code`.
  Rationale: A program never exchanges anything for an error redirect, so a forged error redirect can only show the user a "cancelled" message. Checking the state before the code guarantees that a code is never returned for an unverified state.
  Date: 2026-10-16


## Outcomes & Retrospective


(To be filled during and after implementation.)


## Context and Orientation


Work in the repository root `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`. It is a Cabal project (`cabal.project` lists `.` and `notion-client-effectful`) built with GHC 9.12 and `default-language: GHC2024`. The library's default extensions are `DuplicateRecordFields`, `OverloadedLabels`, `OverloadedStrings` and `RecordWildCards`. `treefmt` formats code in a pre-commit hook; re-stage files it changes. Library modules are listed under `exposed-modules` in `notion-client.cabal`, and test modules under the `test-suite tasty` stanza's `other-modules`.

Notion's authorization guide (https://developers.notion.com/docs/authorization) defines the flow this plan implements:

- **Authorization URL.** `https://api.notion.com/v1/oauth/authorize` with the query parameters `client_id` (required; the integration's OAuth client ID from Notion's developer portal), `redirect_uri` (required; one of the redirect URIs registered for the integration), `response_type` (required; must be `code`), `owner` (required; must be `user`) and `state` (optional; returned unchanged and used against CSRF). Notion documents no PKCE parameters (proof key for code exchange), and this plan adds none.
- **Redirect.** On success, Notion appends `code` and `state` to the redirect URI. On denial or cancellation, it appends `error`; the guide's example is `error=access_denied`, and the codes follow the OAuth specification, RFC 6749 section 4.1.2.1. An `error_description` may also be present.
- **Exchange.** `POST /v1/oauth/token` with HTTP Basic credentials and the body `{"grant_type":"authorization_code","code":…,"redirect_uri":…}`. `redirect_uri` is required if it was in the authorization URL, which it always is here.

Existing code you will build on, all in `src/Notion/V1/OAuth.hs`:

```haskell
data OAuthCredentials = OAuthCredentials {clientId :: Text, clientSecret :: Text}
data OAuthTokenRequest = AuthorizationCode AuthorizationCodeGrant | RefreshToken Text
data AuthorizationCodeGrant = AuthorizationCodeGrant
  {code :: Text, redirectUri :: Maybe Text, externalAccount :: Maybe ExternalAccount}
data OAuthMethods = OAuthMethods
  { createOAuthToken :: OAuthTokenRequest -> IO OAuthTokenResponse, ... }
makeOAuthMethodsWith :: ClientConfig -> ClientEnv -> OAuthCredentials -> OAuthMethods
```

`OAuthTokenResponse` holds `accessToken`, `refreshToken :: Maybe Text`, `botId`, `workspaceId`, `workspaceName`, `owner` and more. Note that `AuthorizationCode` is already a *constructor* name in that module, so the new type for a callback's code is named `OAuthCode`.

From the prerequisite plan `docs/plans/16-decode-oauth-token-endpoint-errors-into-a-typed-exception.md` (its Milestone 1 must be merged before this plan's Milestone 2), `Notion.V1.OAuth` exports

```haskell
data OAuthErrorCode = OAuthInvalidRequest | OAuthInvalidClient | OAuthInvalidGrant
  | OAuthUnauthorizedClient | OAuthUnsupportedGrantType | OAuthInvalidScope
  | OAuthAccessDenied | OAuthUnsupportedResponseType | OAuthServerError
  | OAuthTemporarilyUnavailable | UnknownOAuthErrorCode Text
parseOAuthErrorCode :: Text -> OAuthErrorCode
data OAuthError = OAuthError {oauthErrorCode :: OAuthErrorCode, errorDescription :: Maybe Text, ...}
```

and the token endpoint throws `OAuthError` on OAuth-format failures. Check that these exist (`rg -n OAuthErrorCode src/Notion/V1/OAuth.hs`) before starting Milestone 2. This plan reuses `OAuthErrorCode` for the redirect's `error` parameter and must not define another error-code type.

`Notion.V1.Client.defaultBaseUrl` is `BaseUrl Https "api.notion.com" 443 "/v1"`. Servant's `Servant.Client.showBaseUrl` renders it as `https://api.notion.com/v1`. `Network.HTTP.Types.URI` (package `http-types`, already a dependency) provides `renderQuery :: Bool -> Query -> ByteString`, which percent-encodes and adds a leading `?` when its first argument is `True`, and `parseQuery :: ByteString -> Query`, which accepts an optional leading `?` and decodes percent-encoding and `+`. The library's base64 dependency is `base64-bytestring`, whose `Data.ByteString.Base64.URL.encodeUnpadded` yields URL-safe base64 (alphabet `A–Z a–z 0–9 - _`) without padding.

Tests are tasty test groups. `tasty/OAuthTests.hs` is the existing "OAuth" group, and `tasty/Main.hs` registers each module's `tests` value in its top-level list (`OAuthTests.tests` appears there). Add a new module `tasty/AuthorizationTests.hs` with its own group named "Authorization", register it in `tasty/Main.hs` next to `OAuthTests.tests`, and list it in the test suite's `other-modules`. Fixtures that need a person's name use made-up Japanese names.

ADR context. [ADR 1](../adr/1-tolerant-response-decoders.md) requires unknown fallbacks for decoded enums; `parseOAuthErrorCode` already maps unknown codes to `UnknownOAuthErrorCode`, so a redirect with an unfamiliar `error` still yields `AuthorizationDenied`. [ADR 6](../adr/6-js-sdk-types-are-the-wire-format-reference.md) makes the JS SDK (`mori://makenotion/notion-sdk-js`, project-relative `src/api-endpoints/oauth.ts`; artifact-level URI pending) the wire reference. The SDK has no authorization-URL helper, so Notion's guide and the live check above are the sources here. [ADR 9](../adr/9-oauth-callback-and-token-lifecycle-boundaries.md) defines the planned callback, persistence and retry boundaries; implement its state-first, single-use contract here.


## Plan of Work


### Milestone 1: authorization URL and state


Create `src/Notion/V1/OAuth/Authorization.hs` (module `Notion.V1.OAuth.Authorization`) and add it to `exposed-modules`. Add `entropy >=0.4.1.11 && <0.5` and `memory >=0.18 && <0.19` to the library's `build-depends`. Mori searches for these packages returned no source entries during this review. Hackage's preferred-version JSON and the upstream tags `v0.4.1.11` and `memory-v0.18.0` were checked on 2026-10-16. Source references are `mori://tommd/entropy`, project-relative `System/Entropy.hs`, and `mori://vincenthz/hs-memory`, project-relative `Data/ByteArray/Methods.hs` (artifact-level URIs pending). `getEntropy 32` supplies the bytes; `constEq` supports strict `ByteString` and rejects different lengths early. Recheck registry and release metadata before implementation if these versions change. Resolve any build failure against those sources; do not silently substitute a new cryptographic dependency.

Define:

```haskell
-- | An unguessable value tying a redirect to the browser session that started the login.
newtype OAuthState = OAuthState {oauthStateText :: Text}
  -- Redacted Show instance; serialize explicitly with oauthStateText.

-- | 32 bytes from the operating system's secure generator, URL-safe base64 without padding (43 characters).
newOAuthState :: IO OAuthState

-- | Equality in time independent of where the values first differ.
sameOAuthState :: OAuthState -> OAuthState -> Bool

data AuthorizationRequest = AuthorizationRequest
  { clientId :: Text,
    redirectUri :: Text,
    state :: OAuthState
  }

-- | @https://api.notion.com/v1/oauth/authorize?client_id=…&response_type=code&owner=user&redirect_uri=…&state=…@
authorizationUrl :: AuthorizationRequest -> Text
authorizationUrl = authorizationUrlWith defaultBaseUrl

-- | The same against another base URL (tests, proxies).
authorizationUrlWith :: BaseUrl -> AuthorizationRequest -> Text
```

`OAuthState` deliberately has no `Eq` instance, so that callers compare with `sameOAuthState`. Implement `sameOAuthState` with `Data.ByteArray.constEq` over the UTF-8 bytes; do not implement a home-grown timing primitive. A program stores a state between requests with `oauthStateText` and restores it with the `OAuthState` constructor.

Build the URL from `Text.pack (showBaseUrl base) <> "/oauth/authorize"` and the UTF-8-decoded output of `renderQuery True`, with the parameters in the order `client_id`, `response_type=code`, `owner=user`, `redirect_uri`, `state`. Decode the result to `Text` as UTF-8.

Tests in `tasty/AuthorizationTests.hs` (randomness-shape checks supplement review of the secure source; they do not prove unpredictability):

1. For `AuthorizationRequest {clientId = "1a2b3c4d-0000-4000-8000-000000000001", redirectUri = "http://localhost:8765/callback", state = OAuthState "fixed-state"}`, `authorizationUrl` equals exactly `https://api.notion.com/v1/oauth/authorize?client_id=1a2b3c4d-0000-4000-8000-000000000001&response_type=code&owner=user&redirect_uri=http%3A%2F%2Flocalhost%3A8765%2Fcallback&state=fixed-state`.
2. `newOAuthState` returns 43 characters drawn from `A–Z a–z 0–9 - _`, and two calls return different values.
3. `sameOAuthState` is true for equal values and false for a one-character difference, for a different length, and for two differences with the same XOR delta (for example `aa` versus `bb`). The last case catches the original draft’s incorrect XOR reduction, which can cancel differences and falsely accept unequal states.

Live check (network, no credentials): `curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' "<url printed by authorizationUrl for test 1>"` prints `302 https://app.notion.com/install-integration?...` with the same parameters.

### Milestone 2: callback verification and code exchange


Before starting, confirm that the prerequisite types from `docs/plans/16-decode-oauth-token-endpoint-errors-into-a-typed-exception.md` Milestone 1 exist.

Add to `Notion.V1.OAuth.Authorization`:

```haskell
-- | The one-time code from a successful redirect.
newtype OAuthCode = OAuthCode {oauthCodeText :: Text}
  deriving stock (Eq)
  -- Redacted Show instance.

data AuthorizationCallbackError
  = -- | Notion redirected with @error@ (for example the user pressed Cancel); carries @error_description@.
    AuthorizationDenied OAuthErrorCode (Maybe Text)
  | -- | @state@ is absent or differs from the expected one: possibly forged; never exchange.
    StateMismatch
  | -- | Neither a nonempty @code@ nor @error@ was present.
    MissingCode
  | -- | Duplicate protocol keys, invalid UTF-8, or conflicting result fields.
    MalformedCallback
  deriving stock (Eq, Show)

instance Exception AuthorizationCallbackError

-- | Check a redirect's query against the state stored when the login started.
verifyAuthorizationCallback :: OAuthState -> Query -> Either AuthorizationCallbackError OAuthCode

-- | The token request for a verified code: always sends the request's redirect URI.
authorizationCodeGrant :: AuthorizationRequest -> OAuthCode -> OAuthTokenRequest

-- | 'createOAuthToken' applied to 'authorizationCodeGrant'.
exchangeAuthorizationCode :: OAuthMethods -> AuthorizationRequest -> OAuthCode -> IO OAuthTokenResponse
```

`verifyAuthorizationCallback` operates on the query already percent-decoded by `parseQuery` or WAI; never decode it a second time. First reject duplicate `state`, `code`, `error`, `error_description` or `error_uri` parameters, invalid UTF-8 in protocol values, valueless protocol parameters, and simultaneous `code` and `error`, with `MalformedCallback`. Ignore unrelated keys for forward compatibility. Next require one nonempty expected state and one nonempty returned state and compare them; otherwise return `StateMismatch`. This check precedes both success and denial, so a forged `error=access_denied` cannot terminate a legitimate login. Only after state validation may a nonempty `error` become `AuthorizationDenied`, or a nonempty `code` become `Right (OAuthCode c)`. An empty `error` is malformed; an absent or empty code without an error is `MissingCode`. Treat descriptions as untrusted display data.

The pure verifier does not prevent replay or enforce expiry. The caller must bind the request (state, client ID and exact redirect URI) to the initiating session, expire it after a short interval (the example uses ten minutes), and atomically consume it on the first valid success or state-validated denial. Invalid callbacks must neither consume state nor call the token endpoint. Documentation must make that caller responsibility explicit. `OAuthCode` is a convenience wrapper, not a proof that arbitrary callers used the verifier.

`authorizationCodeGrant` builds `AuthorizationCode AuthorizationCodeGrant {code, redirectUri = Just redirectUri, externalAccount = Nothing}`. `exchangeAuthorizationCode` calls the non-retrying OAuth methods from plan 16 exactly once. A caller who needs `external_account` can call `createOAuthToken` directly.

Tests (add to `tasty/AuthorizationTests.hs`), each using `parseQuery` on a literal query string and the expected state `OAuthState "s-123"`:

1. `?code=c-1&state=s-123` gives `Right (OAuthCode "c-1")`.
2. `?error=access_denied&state=s-123` gives `Left (AuthorizationDenied OAuthAccessDenied Nothing)`. `?error=access_denied&state=s-123&error_description=User%20cancelled` carries `Just "User cancelled"`.
3. `?error=slow_down&state=s-123` gives `AuthorizationDenied (UnknownOAuthErrorCode "slow_down") Nothing`.
4. `?code=c-1&state=other` and `?code=c-1` give `StateMismatch`.
5. `?state=s-123` and `?code=&state=s-123` give `MissingCode`.
6. `?code=a%2Bb&state=s-123` gives `OAuthCode "a+b"`.
7. `Aeson.toJSON (authorizationCodeGrant req (OAuthCode "c-1"))` equals `{"grant_type":"authorization_code","code":"c-1","redirect_uri":"http://localhost:8765/callback"}`.
8. Reject denial with missing or incorrect state, repeated state/code/error fields (including identical duplicates), simultaneous code and error, valueless fields and invalid UTF-8. Reject an empty expected state. Verify unknown unrelated parameters are ignored.
9. Using `FakeNotion.fakeClientEnv [jsonReply 200 <token JSON>]`, `exchangeAuthorizationCode` sends one `POST /oauth/token` with a `Basic` authorization header and returns the decoded response. Copy the token JSON fixture from `tasty/OAuthTests.hs` (`tokenJson`), or export it from there.

Documentation: in `README.md`'s "### OAuth" section, describe the three steps with a short example: generate a state, build the URL, store the state, verify the callback, and exchange. Mention that the redirect URI must exactly match one registered for the integration. In `CHANGELOG.md`, under `## Unreleased` (create it at the top if absent) → `### New Features`, add one entry for `Notion.V1.OAuth.Authorization`.


## Concrete Steps


From `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`:

```bash
cabal build all
cabal test --test-show-details=direct --test-options='-p Authorization'
```

Expected after Milestone 2:

```text
    Authorization
      authorization URL is exact for a fixed request:   OK
      newOAuthState is 43 URL-safe characters:          OK
      ...
      code exchange sends the redirect URI:             OK
  All N tests passed
```

Run the full suite before each commit (`cabal test --test-show-details=direct`). Commit messages follow Conventional Commits and carry trailers, for example:

```text
feat(oauth): build authorization URLs and verify OAuth callbacks

MasterPlan: docs/masterplans/3-support-notion-public-integrations-with-an-oauth-login-flow.md
ExecPlan: docs/plans/17-build-authorization-urls-and-exchange-codes-from-verified-oauth-callbacks.md
Intention: intention_01m52739hkexps2gwzdp5hnn4a
```


## Validation and Acceptance


Milestone 1 is accepted when tests 1 to 3 pass and the live `curl` shows the 302 to `install-integration` with the generated parameters. If no network is available, note that in Progress; the tests alone still accept the milestone. Milestone 2 is accepted when tests 1 to 9 pass, `cabal build all` succeeds, and the README example type-checks. Copy it into a scratch module, or check it with `cabal repl`. The live consent-and-redirect round trip is the acceptance of `docs/plans/19-demonstrate-and-document-the-public-integration-oauth-login-end-to-end.md`, not of this plan.


## Idempotence and Recovery


Every step is additive (a new module, a new test module, and two new dependencies) and safe to repeat. If a dependency fails to resolve, inspect its current release and compiler support before changing the dependency choice, and record any change.


## Interfaces and Dependencies


New dependencies: `entropy` (`System.Entropy.getEntropy :: Int -> IO ByteString`) and `memory` (`Data.ByteArray.constEq`). Existing dependencies used: `http-types` (`Network.HTTP.Types.URI.Query`, `renderQuery`, `parseQuery`), `base64-bytestring` (`Data.ByteString.Base64.URL.encodeUnpadded`), and `servant-client` (`BaseUrl`, `showBaseUrl`).

At completion, `Notion.V1.OAuth.Authorization` exports `OAuthState (..)`, `newOAuthState`, `sameOAuthState`, `AuthorizationRequest (..)`, `authorizationUrl`, `authorizationUrlWith`, `OAuthCode (..)`, `AuthorizationCallbackError (..)`, `verifyAuthorizationCallback`, `authorizationCodeGrant` and `exchangeAuthorizationCode`, with the signatures above. `docs/plans/19-demonstrate-and-document-the-public-integration-oauth-login-end-to-end.md` uses all of these from its example executable.

Prerequisites: none for Milestone 1. For Milestone 2, Milestone 1 of `docs/plans/16-decode-oauth-token-endpoint-errors-into-a-typed-exception.md` (`OAuthErrorCode`, `parseOAuthErrorCode` and `OAuthError` exported from `Notion.V1.OAuth`). This plan does not edit `src/Notion/V1/OAuth.hs`.


Revision (2026-10-16): Validate state on errors as well as successes, reject ambiguous callbacks, specify caller-owned expiry and single use, and replace the incorrect XOR-reduction comparison with a verified dependency.
