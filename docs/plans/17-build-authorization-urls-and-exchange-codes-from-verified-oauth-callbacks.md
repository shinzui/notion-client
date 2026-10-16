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
---

# Build Authorization URLs and Exchange Codes from Verified OAuth Callbacks

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

A Notion *public integration* can be installed by any Notion user. A user installs it by logging in through OAuth 2.0, an authorization protocol with three steps. First, the program sends the user's browser to Notion's consent page, an *authorization URL* that names the integration and the address to return to. Second, after the user clicks "Allow", Notion redirects the browser to that address, the *redirect URI*, adding a one-time *authorization code* to the query string. Third, the program exchanges the code for tokens at Notion's token endpoint. To stop another website from injecting its own code into the user's session (a cross-site request forgery, or CSRF, attack), the program also puts a random *state* value in the authorization URL, remembers it (for example in a session cookie), and accepts the redirect only if the same state comes back.

The Haskell library in this repository can already perform the third step (`createOAuthToken` in `Notion.V1.OAuth`), but it cannot help with the first two. After this change a program can:

- generate a state value from a cryptographically secure random source with `newOAuthState`;
- build the exact authorization URL with `authorizationUrl`;
- hand the redirect's query string to `verifyAuthorizationCallback`, which either returns the code or explains what went wrong: the user cancelled (`error=access_denied`), the state does not match, or the code is missing;
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

- Decision: Use the `entropy` package (`System.Entropy.getEntropy`) for state randomness, and compare state values with a hand-written constant-time comparison instead of adding a cryptography library.
  Rationale: `random`, which the library already uses for retry jitter, is not a cryptographically secure generator. `entropy` is a small binding to the operating system's secure generator (`/dev/urandom`, `getrandom` or `BCryptGenRandom`). `crypton` would also work, but it is a much larger dependency for one function. Hackage's preferred `entropy` version on 2026-10-16 was 0.4.1.11.
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

and the token endpoint throws `OAuthError` on OAuth-format failures. Check that these exist (`grep -n OAuthErrorCode src/Notion/V1/OAuth.hs`) before starting Milestone 2. This plan reuses `OAuthErrorCode` for the redirect's `error` parameter and must not define another error-code type.

`Notion.V1.Client.defaultBaseUrl` is `BaseUrl Https "api.notion.com" 443 "/v1"`. Servant's `Servant.Client.showBaseUrl` renders it as `https://api.notion.com/v1`. `Network.HTTP.Types.URI` (package `http-types`, already a dependency) provides `renderQuery :: Bool -> Query -> ByteString`, which percent-encodes and adds a leading `?` when its first argument is `True`, and `parseQuery :: ByteString -> Query`, which accepts an optional leading `?` and decodes percent-encoding and `+`. The library's base64 dependency is `base64-bytestring`, whose `Data.ByteString.Base64.URL.encodeUnpadded` yields URL-safe base64 (alphabet `A–Z a–z 0–9 - _`) without padding.

Tests are tasty test groups. `tasty/OAuthTests.hs` is the existing "OAuth" group, and `tasty/Main.hs` registers each module's `tests` value in its top-level list (`OAuthTests.tests` appears there). Add a new module `tasty/AuthorizationTests.hs` with its own group named "Authorization", register it in `tasty/Main.hs` next to `OAuthTests.tests`, and list it in the test suite's `other-modules`. Fixtures that need a person's name use made-up Japanese names.

ADR context. [ADR 1](../adr/1-tolerant-response-decoders.md) requires unknown fallbacks for decoded enums; `parseOAuthErrorCode` already maps unknown codes to `UnknownOAuthErrorCode`, so a redirect with an unfamiliar `error` still yields `AuthorizationDenied`. [ADR 6](../adr/6-js-sdk-types-are-the-wire-format-reference.md) makes the JS SDK (`/Users/shinzui/Keikaku/hub/notion-sdk-js`) the wire reference. The SDK has no authorization-URL helper, so Notion's guide and the live check above are the sources here. No other ADR applies.


## Plan of Work

### Milestone 1: authorization URL and state

Create `src/Notion/V1/OAuth/Authorization.hs` (module `Notion.V1.OAuth.Authorization`) and add it to `exposed-modules`. Add `entropy` to the library's `build-depends`. Confirm the current release on Hackage first (`curl -s -H 'Accept: application/json' https://hackage.haskell.org/package/entropy/preferred`) and use a bound such as `entropy >=0.4.1 && <0.5`. If the Nix development shell cannot provide it, record the problem in Surprises & Discoveries, then fall back to `crypton`'s `Crypto.Random.getRandomBytes` with a bound matching its current Hackage release, and record the switch in the Decision Log.

Define:

```haskell
-- | An unguessable value tying a redirect to the browser session that started the login.
newtype OAuthState = OAuthState {oauthStateText :: Text}
  deriving stock (Show)

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

`OAuthState` deliberately has no `Eq` instance, so that callers compare with `sameOAuthState`. Implement `sameOAuthState` by comparing the UTF-8 bytes. Return `False` when the lengths differ. Otherwise fold `xor` over `ByteString.zipWith` results and test that the result is zero, so the time taken does not depend on the position of the first difference. A program stores a state between requests with `oauthStateText` and restores it with the `OAuthState` constructor.

Build the URL with `showBaseUrl base <> "/oauth/authorize"` followed by `renderQuery True`, with the parameters in the order `client_id`, `response_type=code`, `owner=user`, `redirect_uri`, `state`. Decode the result to `Text` as UTF-8.

Tests in `tasty/AuthorizationTests.hs`:

1. For `AuthorizationRequest {clientId = "1a2b3c4d-0000-4000-8000-000000000001", redirectUri = "http://localhost:8765/callback", state = OAuthState "fixed-state"}`, `authorizationUrl` equals exactly `https://api.notion.com/v1/oauth/authorize?client_id=1a2b3c4d-0000-4000-8000-000000000001&response_type=code&owner=user&redirect_uri=http%3A%2F%2Flocalhost%3A8765%2Fcallback&state=fixed-state`.
2. `newOAuthState` returns 43 characters drawn from `A–Z a–z 0–9 - _`, and two calls return different values.
3. `sameOAuthState` is true for equal values and false for a one-character difference and for a different length.

Live check (network, no credentials): `curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' "<url printed by authorizationUrl for test 1>"` prints `302 https://app.notion.com/install-integration?...` with the same parameters.

### Milestone 2: callback verification and code exchange

Before starting, confirm that the prerequisite types from `docs/plans/16-decode-oauth-token-endpoint-errors-into-a-typed-exception.md` Milestone 1 exist.

Add to `Notion.V1.OAuth.Authorization`:

```haskell
-- | The one-time code from a successful redirect.
newtype OAuthCode = OAuthCode {oauthCodeText :: Text}
  deriving stock (Eq, Show)

data AuthorizationCallbackError
  = -- | Notion redirected with @error@ (for example the user pressed Cancel); carries @error_description@.
    AuthorizationDenied OAuthErrorCode (Maybe Text)
  | -- | @state@ is absent or differs from the expected one: possibly forged; never exchange.
    StateMismatch
  | -- | Neither @code@ nor @error@ was present.
    MissingCode
  deriving stock (Eq, Show)

instance Exception AuthorizationCallbackError

-- | Check a redirect's query against the state stored when the login started.
verifyAuthorizationCallback :: OAuthState -> Query -> Either AuthorizationCallbackError OAuthCode

-- | The token request for a verified code: always sends the request's redirect URI.
authorizationCodeGrant :: AuthorizationRequest -> OAuthCode -> OAuthTokenRequest

-- | 'createOAuthToken' applied to 'authorizationCodeGrant'.
exchangeAuthorizationCode :: OAuthMethods -> AuthorizationRequest -> OAuthCode -> IO OAuthTokenResponse
```

`verifyAuthorizationCallback` reads the first occurrence of each key, decoding the values as UTF-8 leniently. It checks in this order: if `error` is present, it returns `AuthorizationDenied (parseOAuthErrorCode e) description`. If `state` is absent or `not (sameOAuthState expected (OAuthState s))`, it returns `StateMismatch`. If `code` is absent or empty, it returns `MissingCode`. Otherwise it returns `Right (OAuthCode c)`. `authorizationCodeGrant` builds `AuthorizationCode AuthorizationCodeGrant {code, redirectUri = Just redirectUri, externalAccount = Nothing}`. A caller who needs `external_account` can call `createOAuthToken` directly.

Tests (add to `tasty/AuthorizationTests.hs`), each using `parseQuery` on a literal query string and the expected state `OAuthState "s-123"`:

1. `?code=c-1&state=s-123` gives `Right (OAuthCode "c-1")`.
2. `?error=access_denied&state=s-123` gives `Left (AuthorizationDenied OAuthAccessDenied Nothing)`. `?error=access_denied&error_description=User%20cancelled` carries `Just "User cancelled"`.
3. `?error=slow_down` gives `AuthorizationDenied (UnknownOAuthErrorCode "slow_down") Nothing`.
4. `?code=c-1&state=other` and `?code=c-1` give `StateMismatch`.
5. `?state=s-123` and `?code=&state=s-123` give `MissingCode`.
6. `?code=a%2Bb&state=s-123` gives `OAuthCode "a+b"`.
7. `Aeson.toJSON (authorizationCodeGrant req (OAuthCode "c-1"))` equals `{"grant_type":"authorization_code","code":"c-1","redirect_uri":"http://localhost:8765/callback"}`.
8. Using `FakeNotion.fakeClientEnv [jsonReply 200 <token JSON>]`, `exchangeAuthorizationCode` sends one `POST /oauth/token` with a `Basic` authorization header and returns the decoded response. Copy the token JSON fixture from `tasty/OAuthTests.hs` (`tokenJson`), or export it from there.

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

Milestone 1 is accepted when tests 1 to 3 pass and the live `curl` shows the 302 to `install-integration` with the generated parameters. If no network is available, note that in Progress; the tests alone still accept the milestone. Milestone 2 is accepted when tests 1 to 8 pass, `cabal build all` succeeds, and the README example type-checks. Copy it into a scratch module, or check it with `cabal repl`. The live consent-and-redirect round trip is the acceptance of `docs/plans/19-demonstrate-and-document-the-public-integration-oauth-login-end-to-end.md`, not of this plan.


## Idempotence and Recovery

Every step is additive (a new module, a new test module, and one new dependency) and safe to repeat. If the `entropy` dependency fails to resolve, revert only the `build-depends` line and follow the `crypton` fallback described in Milestone 1.


## Interfaces and Dependencies

New dependency: `entropy` (`System.Entropy.getEntropy :: Int -> IO ByteString`), or `crypton` as the recorded fallback. Existing dependencies used: `http-types` (`Network.HTTP.Types.URI.Query`, `renderQuery`, `parseQuery`), `base64-bytestring` (`Data.ByteString.Base64.URL.encodeUnpadded`), and `servant-client` (`BaseUrl`, `showBaseUrl`).

At completion, `Notion.V1.OAuth.Authorization` exports `OAuthState (..)`, `newOAuthState`, `sameOAuthState`, `AuthorizationRequest (..)`, `authorizationUrl`, `authorizationUrlWith`, `OAuthCode (..)`, `AuthorizationCallbackError (..)`, `verifyAuthorizationCallback`, `authorizationCodeGrant` and `exchangeAuthorizationCode`, with the signatures above. `docs/plans/19-demonstrate-and-document-the-public-integration-oauth-login-end-to-end.md` uses all of these from its example executable.

Prerequisites: none for Milestone 1. For Milestone 2, Milestone 1 of `docs/plans/16-decode-oauth-token-endpoint-errors-into-a-typed-exception.md` (`OAuthErrorCode`, `parseOAuthErrorCode` and `OAuthError` exported from `Notion.V1.OAuth`). This plan does not edit `src/Notion/V1/OAuth.hs`.
