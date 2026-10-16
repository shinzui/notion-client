---
id: 19
slug: demonstrate-and-document-the-public-integration-oauth-login-end-to-end
title: "Demonstrate and Document the Public Integration OAuth Login End to End"
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

# Demonstrate and Document the Public Integration OAuth Login End to End

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

A Notion *public integration* is an integration that any Notion user can install into their own workspace by logging in through OAuth 2.0. OAuth 2.0 is the protocol in which a program sends the user to Notion's consent page, receives a one-time code when Notion redirects the browser back to the program, and trades that code for an access token and a refresh token. Three sibling plans add the library pieces:

- typed OAuth errors, in `docs/plans/16-decode-oauth-token-endpoint-errors-into-a-typed-exception.md`;
- the consent URL, the CSRF-protecting state, callback verification and code exchange, in `docs/plans/17-build-authorization-urls-and-exchange-codes-from-verified-oauth-callbacks.md`;
- automatic, rotation-safe token refresh for `Methods`, in `docs/plans/18-refresh-oauth-access-tokens-automatically-for-methods.md`.

Their tests run against a fake Notion. This plan proves that the pieces work against the real Notion, and gives users a complete program to copy.

After this change, `cabal run notion-client-oauth-example -- login` prints a consent URL and waits on `http://localhost:8765/callback`. A person opens the URL, chooses a workspace and pages, and clicks "Allow". The program then verifies the redirect, exchanges the code, stores the tokens in a local file and prints the connected workspace. `… -- whoami` calls the API with the stored tokens. `… -- refresh` forces a refresh and shows that the token pair rotated. `… -- revoke` revokes the token, after which the program reports that the user must log in again. The README gains a complete OAuth walkthrough, and the package is prepared for release as `0.10.0.0`.

This plan is EP-4 of `docs/masterplans/3-support-notion-public-integrations-with-an-oauth-login-flow.md`. It is the initiative's integration gate.


## Progress

- [ ] Milestone 1: The `notion-client-oauth-example` executable builds and implements `login`, `whoami`, `refresh` and `revoke` with a file-backed `TokenStore`. `cabal build all` is green, and running it without credentials prints a clear usage message.
- [ ] Milestone 2: A live run against a real public integration completes login, `whoami`, `refresh` (rotation observed), `revoke`, and a cancelled consent. Findings are recorded here and in the MasterPlan.
- [ ] Milestone 3: README OAuth walkthrough, CHANGELOG `0.10.0.0` section, version bumps (`notion-client` 0.10.0.0; `notion-client-effectful` bound and version), and the scope-exclusions ADR are done. `cabal build all` and `cabal test` are green.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Make the demo a separate executable, `notion-client-oauth-example`, rather than a section of `notion-client-example`.
  Rationale: The existing example needs an internal integration token (`NOTION_TOKEN`) and test page IDs. The OAuth flow needs different credentials, an HTTP listener and a browser. Mixing them would make both harder to run. Only this executable depends on `warp` and `wai`, so the library stays free of web-framework dependencies, as the MasterPlan requires.
  Date: 2026-10-16

- Decision: Keep the file-backed `TokenStore` in the example, not in the library.
  Rationale: The MasterPlan excludes persistence beyond memory from the library. Real programs store tokens in a database or a secret manager, and a file store in the library would invite insecure use.
  Date: 2026-10-16


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Work in the repository root `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`. It is a Cabal project (`cabal.project` lists `.` and `notion-client-effectful`) built with GHC 9.12 and `default-language: GHC2024`. `notion-client.cabal` defines the library, the `tasty` test suite and the executable `notion-client-example` (sources in `notion-client-example/`, unbounded `build-depends` such as `aeson`, `base`, `notion-client`, `text`). `treefmt` formats code in a pre-commit hook; re-stage files it changes.

This plan requires its three sibling plans to be **Complete**. Check the Exec-Plan Registry in `docs/masterplans/3-support-notion-public-integrations-with-an-oauth-login-flow.md` and confirm that the APIs exist:

```bash
grep -n "OAuthError\b" src/Notion/V1/OAuth.hs
grep -n "verifyAuthorizationCallback\|authorizationUrl" src/Notion/V1/OAuth/Authorization.hs
grep -n "newOAuthTokenManager\|ReauthorizationRequired" src/Notion/V1/OAuth/Refresh.hs
grep -n "makeMethodsWithTokenSource" src/Notion/V1.hs
```

The library API this plan uses, as specified by the sibling plans (read their Interfaces and Dependencies sections if a name differs in the working tree):

```haskell
-- Notion.V1.OAuth (existing, plus plan 16)
data OAuthCredentials = OAuthCredentials {clientId :: Text, clientSecret :: Text}
makeOAuthMethodsWith :: ClientConfig -> ClientEnv -> OAuthCredentials -> OAuthMethods
-- OAuthMethods {createOAuthToken, revokeOAuthToken :: Text -> IO OAuthRevokeResponse, introspectOAuthToken}
data OAuthError = OAuthError {oauthErrorCode :: OAuthErrorCode, errorDescription :: Maybe Text, requestId :: Maybe Text, ...}

-- Notion.V1.OAuth.Authorization (plan 17)
newOAuthState :: IO OAuthState
data AuthorizationRequest = AuthorizationRequest {clientId :: Text, redirectUri :: Text, state :: OAuthState}
authorizationUrl :: AuthorizationRequest -> Text
verifyAuthorizationCallback :: OAuthState -> Network.HTTP.Types.Query -> Either AuthorizationCallbackError OAuthCode
-- AuthorizationCallbackError = AuthorizationDenied OAuthErrorCode (Maybe Text) | StateMismatch | MissingCode
exchangeAuthorizationCode :: OAuthMethods -> AuthorizationRequest -> OAuthCode -> IO OAuthTokenResponse

-- Notion.V1.OAuth.Refresh (plan 18)
data OAuthTokens = OAuthTokens {accessToken, refreshToken :: Maybe Text, botId, workspaceId, workspaceName :: Maybe Text, obtainedAt :: UTCTime}  -- JSON instances
oauthTokensFromResponse :: UTCTime -> OAuthTokenResponse -> OAuthTokens
data TokenStore = TokenStore {loadTokens :: IO OAuthTokens, saveTokens :: OAuthTokens -> IO ()}
newOAuthTokenManager :: OAuthMethods -> TokenStore -> IO OAuthTokenManager
tokenManagerSource :: OAuthTokenManager -> TokenSource
currentTokens :: OAuthTokenManager -> IO OAuthTokens
refreshTokensNow :: OAuthTokenManager -> IO OAuthTokens
newtype ReauthorizationRequired = ReauthorizationRequired {reauthorizationCause :: Maybe OAuthError}

-- Notion.V1 (plan 18)
makeMethodsWithTokenSource :: ClientConfig -> ClientEnv -> TokenSource -> Methods
```

`Methods` has `retrieveMyUser :: IO UserObject` and `search :: SearchRequest -> IO (ListOf PageOrDataSource)`. See `notion-client-example/Main.hs` for how the existing example calls `search`. `defaultClientConfig` and `defaultBaseUrl` come from `Notion.V1`. `Servant.Client.mkClientEnv manager defaultBaseUrl` builds a `ClientEnv`, and `Network.HTTP.Client.TLS.newTlsManager` builds the manager.

**Notion-side setup (done by a person, not by the agent).** In Notion's developer portal (https://www.notion.so/profile/integrations), create a public integration ("public connection"). Under its OAuth configuration, add the redirect URI `http://localhost:8765/callback` and copy the OAuth client ID and client secret. If the portal refuses a plain-`http` localhost redirect URI, use an HTTPS tunnel instead (for example `cloudflared tunnel --url http://localhost:8765`). Register the tunnel's `https://…/callback` URL, set `NOTION_OAUTH_REDIRECT_URI` to it, and keep `NOTION_OAUTH_LISTEN_PORT=8765`. Record which one worked in Surprises & Discoveries. The agent must never print the client secret or full tokens; print at most the last four characters.

Notion's documented behavior (https://developers.notion.com/docs/authorization) that this live run checks: the redirect carries `code` and `state`, or `error=access_denied` on cancel. The token response carries `access_token`, `refresh_token`, `bot_id`, `workspace_id`, `workspace_name` and `owner`. "Refreshing an access token will generate a new access token and a new refresh token." The guide does not say whether the old refresh token or the old access token stops working. Milestone 2 observes both, because `docs/plans/18-refresh-oauth-access-tokens-automatically-for-methods.md` assumes the old refresh token dies.

ADR context. [ADR 7](../adr/7-effectful-package-mirrors-methods-in-lockstep.md) says that `notion-client-effectful` constrains `notion-client` to the current major version and that the bound moves when the major version does. Today that is `notion-client >=0.9 && <0.10` in `notion-client-effectful/notion-client-effectful.cabal`, and that package's version is `0.3.0.0`. [ADR 8](../adr/8-core-parity-scope-exclusions.md) is the model for recording deliberate scope exclusions. [ADR 2](../adr/2-client-runtime-retry-policy-and-typed-errors.md) and the ADR created by plan 18 describe the runtime behavior the example relies on. No other ADR applies.


## Plan of Work

### Milestone 1: the example executable

Add to `notion-client.cabal` an `executable notion-client-oauth-example` stanza, mirroring `notion-client-example`'s language, extensions and `ghc-options`, with `hs-source-dirs: notion-client-oauth-example`, `main-is: Main.hs` and `other-modules: FileTokenStore`. Its `build-depends` are `aeson`, `base`, `bytestring`, `directory`, `filepath`, `http-client-tls`, `http-types`, `notion-client`, `servant-client`, `text`, `time`, `wai`, `warp`, plus `unix` if you use `setFileMode`. Confirm with `cabal build` that the Nix shell provides `wai` and `warp` (Hackage preferred versions on 2026-10-16: `warp` 3.4.16 and `wai` 3.2.5). Add `.notion-oauth-tokens.json` to `.gitignore`.

`notion-client-oauth-example/FileTokenStore.hs` exports `fileTokenStore :: FilePath -> TokenStore` and `tokenFileExists :: FilePath -> IO Bool`. `loadTokens` decodes the JSON file and fails with a clear message if it is missing or invalid. `saveTokens` writes to `<path>.tmp`, restricts it to the owner (mode `0600` via `System.Posix.Files.setFileMode`), and renames it over `<path>`, so that a crash never leaves a half-written file.

`notion-client-oauth-example/Main.hs` reads its configuration from the environment: `NOTION_OAUTH_CLIENT_ID` and `NOTION_OAUTH_CLIENT_SECRET` are required, `NOTION_OAUTH_REDIRECT_URI` defaults to `http://localhost:8765/callback`, `NOTION_OAUTH_LISTEN_PORT` defaults to 8765, and `NOTION_OAUTH_TOKEN_FILE` defaults to `.notion-oauth-tokens.json`. It dispatches on the first argument:

- `login`: generate a state, build the `AuthorizationRequest`, and print the URL. Start Warp on the listen port in a forked thread, with a WAI application that, for the redirect URI's path, runs `verifyAuthorizationCallback` on `Network.Wai.queryString`, answers a small HTML page ("Connected — you can close this tab", or the error), and puts the result into an `MVar`. Other paths answer 404. Wait on the `MVar`, then kill the server thread. On `Right code`, call `exchangeAuthorizationCode`, convert with `oauthTokensFromResponse`, save, and print the workspace name, workspace ID, bot ID and owner kind. On `Left err`, print it. `AuthorizationDenied OAuthAccessDenied _` prints "Consent was cancelled". Exit non-zero on failure.
- `whoami`: build an `OAuthTokenManager` from the file store, build `Methods` with `makeMethodsWithTokenSource defaultClientConfig env (tokenManagerSource manager)`, and print `retrieveMyUser`'s bot name plus the titles or IDs of the first five `search` results.
- `refresh`: call `refreshTokensNow` and print the last four characters of the old and new access and refresh tokens.
- `revoke`: call `revokeOAuthToken` with the stored access token, print the response's request ID, and leave the file in place so that a following `whoami` demonstrates the failure.

Wrap the top level so that `OAuthError`, `ReauthorizationRequired` and `NotionError` print readable one-line messages: `ReauthorizationRequired` prints "Run `login` again". With no or an unknown argument, or missing credentials, print usage and exit with status 2.

Add a header comment in `Main.hs`, like the one in `notion-client-example/Main.hs`, with the setup steps from Context and Orientation.

### Milestone 2: live verification

This milestone needs a person: create the integration, export the credentials in the shell, and click through the consent page. If credentials are not available, stop here, record "live run pending credentials" in Progress, and tell the user exactly what is needed. Do not mark this plan or the MasterPlan complete without this run.

Run the sequence in Concrete Steps and record short evidence (no secrets) in Surprises & Discoveries. Answer each of these questions:

1. Did Notion accept `http://localhost` as a redirect URI?
2. Does the token response's `owner` decode (user or workspace)?
3. After `refresh`, does the old access token still work? Test it with `curl` against `GET /v1/users/me` using the saved-before-refresh value.
4. After `refresh`, does the old refresh token fail with `invalid_grant`? Test it with one `createOAuthToken (RefreshToken old)` in `cabal repl`, expecting `OAuthError` with `OAuthInvalidGrant`.
5. After `revoke`, does `whoami` end in `ReauthorizationRequired`, or in a different error?
6. Does a cancelled consent produce `AuthorizationDenied OAuthAccessDenied`?

Copy each finding that affects a sibling plan's assumptions into the Surprises & Discoveries of `docs/masterplans/3-support-notion-public-integrations-with-an-oauth-login-flow.md`. If a finding contradicts plan 18's renewal semantics (for example, the old refresh token keeps working, or `revoke` leaves the refresh token valid so that `whoami` silently re-authenticates), stop and update the MasterPlan's Decision Log before changing library code.

### Milestone 3: documentation and release preparation

Rewrite `README.md`'s "### OAuth" section as a complete walkthrough: integration setup, the login steps with `Notion.V1.OAuth.Authorization`, building `Methods` from `newOAuthTokenManager`, handling `ReauthorizationRequired` and `OAuthError`, and a pointer to `cabal run notion-client-oauth-example`. Update the features line ("OAuth token exchange and URL-to-ID helpers") and the API-coverage bullet ("**OAuth**: …") to mention the login flow and automatic refresh. Add an "OAuth example" subsection under "## Running the Example".

In `CHANGELOG.md`, turn `## Unreleased` into `## 0.10.0.0 (<date>)`, merging duplicate subsections left by the sibling plans. Set `version: 0.10.0.0` in `notion-client.cabal`. In `notion-client-effectful/notion-client-effectful.cabal`, change the bound to `notion-client >=0.10 && <0.11` and bump that package to `0.4.0.0`, with a `notion-client-effectful/CHANGELOG.md` entry noting that it requires the new core release and needs no source change, because `runNotion` takes `Methods`. Do not publish to Hackage; publishing is the maintainer's decision.

Create the next-numbered ADR in `docs/adr/`, in the existing format (title, `Status:`, `Date:`, then Context/Decision/Consequences), following `agents/skills/exec-plan/ADR.md`. Title it along the lines of "OAuth login support stops at the protocol: no web framework, persistence or multi-tenant store". It records the MasterPlan's exclusions: no web-framework dependency in the library, persistence only in memory, one token manager per installation per process, no PKCE, no timer-based refresh, and Notion's MCP OAuth out of scope. Cite the live findings from Milestone 2 that support them.


## Concrete Steps

From `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`:

```bash
cabal build all
cabal run notion-client-oauth-example
```

Expected without arguments:

```text
usage: notion-client-oauth-example (login | whoami | refresh | revoke)
  requires NOTION_OAUTH_CLIENT_ID and NOTION_OAUTH_CLIENT_SECRET
```

Live sequence (Milestone 2). The person exports the credentials first:

```bash
export NOTION_OAUTH_CLIENT_ID=...        # from the developer portal
export NOTION_OAUTH_CLIENT_SECRET=...
cabal run notion-client-oauth-example -- login
```

```text
Open this URL in your browser:
https://api.notion.com/v1/oauth/authorize?client_id=…&response_type=code&owner=user&redirect_uri=http%3A%2F%2Flocalhost%3A8765%2Fcallback&state=…
Waiting for the redirect on http://localhost:8765/callback …
Connected to workspace "…" (workspace …, bot …, owner: user)
Tokens saved to .notion-oauth-tokens.json
```

```bash
cabal run notion-client-oauth-example -- whoami
cabal run notion-client-oauth-example -- refresh
cabal run notion-client-oauth-example -- whoami
cabal run notion-client-oauth-example -- revoke
cabal run notion-client-oauth-example -- whoami   # expect: "Run `login` again" (or record what happens)
cabal run notion-client-oauth-example -- login    # click Cancel; expect "Consent was cancelled"
```

Final checks for Milestone 3:

```bash
cabal build all
cabal test --test-show-details=direct
```

Commit at each milestone with Conventional Commits and trailers, for example:

```text
feat(example): add an OAuth login example for public integrations

MasterPlan: docs/masterplans/3-support-notion-public-integrations-with-an-oauth-login-flow.md
ExecPlan: docs/plans/19-demonstrate-and-document-the-public-integration-oauth-login-end-to-end.md
Intention: intention_01m52739hkexps2gwzdp5hnn4a
```


## Validation and Acceptance

Milestone 1 is accepted when `cabal build all` succeeds and the no-argument run prints the usage text and exits with status 2.

Milestone 2 is accepted when a person has completed the live sequence and every one of the six questions has a recorded answer. In particular, `whoami` must succeed both before and after `refresh`, `refresh` must show different last-four characters for both tokens, and the cancelled consent must print the cancellation message.

Milestone 3 is accepted when the README walkthrough's code type-checks (copy it into a scratch module, or check it in `cabal repl`), both packages build at their new versions, and the full test suite passes. The plan as a whole, and therefore the MasterPlan's integration gate, is complete only after all three milestones.


## Idempotence and Recovery

`login` overwrites the token file atomically and can be repeated; each login may issue a new token pair. `revoke` leaves the file, so delete `.notion-oauth-tokens.json` to start clean. If the listener port is busy, set `NOTION_OAUTH_LISTEN_PORT` together with a matching registered redirect URI. The integration created in Notion can be deleted from the developer portal after testing. Version bumps are plain text edits and can be reverted with git if the release is postponed.


## Interfaces and Dependencies

New executable-only dependencies: `wai`, `warp`, `directory`, `filepath` and `unix` (for `setFileMode`). The library gains no dependencies from this plan.

Consumes, and requires Complete: `docs/plans/16-decode-oauth-token-endpoint-errors-into-a-typed-exception.md` (`OAuthError`), `docs/plans/17-build-authorization-urls-and-exchange-codes-from-verified-oauth-callbacks.md` (`Notion.V1.OAuth.Authorization`), and `docs/plans/18-refresh-oauth-access-tokens-automatically-for-methods.md` (`Notion.V1.OAuth.Refresh`, `makeMethodsWithTokenSource`).

Owns, per the MasterPlan's Integration Points: the `0.10.0.0` version bump, the `notion-client-effectful` bound and version, the final `CHANGELOG.md` section, and the README OAuth walkthrough.
