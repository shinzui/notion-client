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
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-16T11:53:13Z
      mode: "update"
      note: "Correct callback verification, OAuth replay policy, token lifecycle recovery and integration acceptance after source review."
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-19T20:35:27Z
      mode: "implement"
      note: "Implement loopback OAuth example, durable POSIX token store, offline acceptance and release documentation."
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-16T11:53:13Z
      verdict: "approved"
      note: "Revised design reviewed against code, relevant ADRs and current upstream contracts; implementation and live OAuth acceptance remain pending."
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

After this change, `cabal run notion-client-oauth-example -- login` prints a consent URL and waits on `http://localhost:8765/callback`. A person opens the URL, chooses a workspace and pages, and clicks "Allow". The program then verifies the redirect, exchanges the code, stores the tokens in a local file and prints the connected workspace. `… -- whoami` calls the API with the stored tokens. `… -- refresh` forces a refresh and shows that the token pair rotated. `… -- revoke` revokes the token and removes local credentials on confirmed success, after which the program requires a new login. The README gains a complete OAuth walkthrough, and the package is prepared for release as `0.10.0.0`.

This plan is EP-4 of `docs/masterplans/3-support-notion-public-integrations-with-an-oauth-login-flow.md`. It is the initiative's integration gate.


## Progress


- [x] (2026-10-19) Milestone 1: The `notion-client-oauth-example` executable builds and implements `login`, `whoami`, `refresh` and `revoke` with a file-backed `TokenStore`. network-free listener and file-store tests pass, `cabal build all` is green, and running it without credentials prints a clear usage message.
- [ ] Milestone 2 (live run pending credentials and browser consent): A live run against a real public integration completes login, `whoami`, `refresh` (rotation observed), `revoke`, and a cancelled consent. Findings are recorded here and in the MasterPlan.
- [x] (2026-10-19) Milestone 3: README OAuth walkthrough, CHANGELOG `0.10.0.0` section, version bumps (`notion-client` 0.10.0.0; `notion-client-effectful` bound and version), and the scope-exclusions ADR are done. `cabal build all` and `cabal test` are green.


## Surprises & Discoveries


- On 2026-10-19, neither `NOTION_OAUTH_CLIENT_ID` nor `NOTION_OAUTH_CLIENT_SECRET` is available in the implementation environment. The live run is pending credentials and browser consent. No live refresh or installation is claimed.
- Enabling CPP for the entire core test suite broke existing multiline JSON string gaps. A small `OAuthExamplePlatform` module alone owns the platform guard; other test modules retain their existing parsing. The POSIX helper/module dependencies remain conditional.
- Source archive checks exposed a companion test fixture dependency outside its package. Fixtures now live inside the adapter's own test directory so its sdist is self-contained.


## Decision Log


- Decision: Make the demo a separate executable, `notion-client-oauth-example`, rather than a section of `notion-client-example`.
  Rationale: The existing example needs an internal integration token (`NOTION_TOKEN`) and test page IDs. The OAuth flow needs different credentials, an HTTP listener and a browser. Mixing them would make both harder to run. Only this executable depends on `warp` and `wai`, so the library stays free of web-framework dependencies, as the MasterPlan requires.
  Date: 2026-10-16

- Decision: Keep the file-backed `TokenStore` in the example, not in the library.
  Rationale: The MasterPlan excludes persistence beyond memory from the library. Real programs store tokens in a database or a secret manager, and a file store in the library would invite insecure use.
  Date: 2026-10-16


## Outcomes & Retrospective


The offline example and release preparation are implemented. `cabal test all --test-show-details=direct` passes 462 core tests (including 11 OAuth example cases) and four companion runtime tests. Callback tests prove invalid-state recovery, authenticated cancellation, concurrent single use and persistence-before-success. File tests prove private complete replacement, failure cleanup, restart reads, symlink/unsafe-directory rejection and command-lock exclusion. Listener startup failure and timeout cleanup are exercised over real loopback HTTP.

Core 0.10.0.0 and companion 0.4.0.0 are prepared together, and the README protocol/runtime snippets type-check. A separate explicit live harness, `scripts/OAuthLiveCheck.hs`, compiles and is ready to prove reactive renewal using the current saved refresh token; it never writes its invalid access-token fixture or probes superseded refresh tokens. ADR 9 records the implemented durable boundaries.

Milestone 2 remains open. Neither OAuth credential is present, and no person has completed browser consent in this run. Localhost registration, live owner decoding, explicit and automatic rotation, restart, cancellation and confirmed live logout are all unverified. Do not mark this child or the MasterPlan Complete until the documented live sequence and six observations pass. Nothing has been published.


## Context and Orientation


Work in the repository root `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`. It is a Cabal project (`cabal.project` lists `.` and `notion-client-effectful`) built with GHC 9.12 and `default-language: GHC2024`. `notion-client.cabal` defines the library, the `tasty` test suite and the executable `notion-client-example` (sources in `notion-client-example/`, unbounded `build-depends` such as `aeson`, `base`, `notion-client`, `text`). `treefmt` formats code in a pre-commit hook; re-stage files it changes.

This plan requires its three sibling plans to be **Complete**. Check the Exec-Plan Registry in `docs/masterplans/3-support-notion-public-integrations-with-an-oauth-login-flow.md` and confirm that the APIs exist:

```bash
rg -n "OAuthError\b" src/Notion/V1/OAuth.hs
rg -n "verifyAuthorizationCallback|authorizationUrl" src/Notion/V1/OAuth/Authorization.hs
rg -n "newOAuthTokenManager|ReauthorizationRequired" src/Notion/V1/OAuth/Refresh.hs
rg -n "makeMethodsWithTokenSource" src/Notion/V1.hs
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
-- AuthorizationCallbackError = AuthorizationDenied OAuthErrorCode (Maybe Text) | StateMismatch | MissingCode | MalformedCallback
exchangeAuthorizationCode :: OAuthMethods -> AuthorizationRequest -> OAuthCode -> IO OAuthTokenResponse

-- Notion.V1.OAuth.Refresh (plan 18)
data OAuthTokens = OAuthTokens {accessToken :: Text, refreshToken :: Maybe Text, botId :: Text, workspaceId :: Text, workspaceName :: Maybe Text, obtainedAt :: UTCTime}  -- JSON instances
oauthTokensFromResponse :: UTCTime -> OAuthTokenResponse -> OAuthTokens
data TokenStore = TokenStore {loadTokens :: IO OAuthTokens, saveTokens :: OAuthTokens -> IO ()}
newOAuthTokenManager :: OAuthMethods -> TokenStore -> IO OAuthTokenManager
tokenManagerSource :: OAuthTokenManager -> TokenSource
currentTokens :: OAuthTokenManager -> IO OAuthTokens
refreshTokensNow :: OAuthTokenManager -> IO OAuthTokens
retryTokenPersistence :: OAuthTokenManager -> IO OAuthTokens
-- TokenPersistenceError and RefreshOutcomeUnknown are redacted IO exceptions.
newtype ReauthorizationRequired = ReauthorizationRequired {reauthorizationCause :: Maybe OAuthError}

-- Notion.V1 (plan 18)
makeMethodsWithTokenSource :: ClientConfig -> ClientEnv -> TokenSource -> Methods
```

`Methods` has `retrieveMyUser :: IO UserObject` and `search :: SearchRequest -> IO (ListOf PageOrDataSource)`. See `notion-client-example/Main.hs` for how the existing example calls `search`. `defaultClientConfig` and `defaultBaseUrl` come from `Notion.V1`. `Servant.Client.mkClientEnv manager defaultBaseUrl` builds a `ClientEnv`, and `Network.HTTP.Client.TLS.newTlsManager` builds the manager.

**Notion-side setup (done by a person, not by the agent).** In Notion's developer portal (https://www.notion.so/profile/integrations), create a public integration ("public connection"). Under its OAuth configuration, add the redirect URI `http://localhost:8765/callback` and copy the OAuth client ID and client secret. If the portal refuses a plain-`http` localhost redirect URI, use an HTTPS tunnel instead (for example `cloudflared tunnel --url http://localhost:8765`). Register the tunnel's `https://…/callback` URL, set `NOTION_OAUTH_REDIRECT_URI` to it, and keep `NOTION_OAUTH_LISTEN_PORT=8765`. Record which one worked in Surprises & Discoveries. Never print the client secret, authorization code or tokens. Show rotation as booleans obtained by comparing full values in memory, not token suffixes. This is a confidential-client example: real distributed desktop or browser applications must keep the client secret and code exchange on a trusted backend rather than embedding the secret in their distributed program.

Notion's documented behavior (https://developers.notion.com/docs/authorization) that this live run checks: the redirect carries `code` and `state`, or `error=access_denied` on cancel. The token response carries `access_token`, `refresh_token`, `bot_id`, `workspace_id`, `workspace_name` and `owner`. "Refreshing an access token will generate a new access token and a new refresh token." The guide does not specify invalidation timing, grace periods, or reuse detection. The manager conservatively avoids replaying a used refresh token and does not rely on the old access token expiring immediately. Do not probe an old refresh token on the installation used for acceptance: reuse could revoke its whole token family.

ADR context. [ADR 7](../adr/7-effectful-package-mirrors-methods-in-lockstep.md) says that `notion-client-effectful` constrains `notion-client` to the current major version and that the bound moves when the major version does. Today that is `notion-client >=0.9 && <0.10` in `notion-client-effectful/notion-client-effectful.cabal`, and that package's version is `0.3.0.0`. [ADR 8](../adr/8-core-parity-scope-exclusions.md) is the model for recording deliberate scope exclusions. [ADR 2](../adr/2-client-runtime-retry-policy-and-typed-errors.md) and [ADR 9](../adr/9-oauth-callback-and-token-lifecycle-boundaries.md) describe the runtime behavior the example relies on. No other ADR applies.


## Plan of Work


### Milestone 1: the example executable


Add to `notion-client.cabal` an `executable notion-client-oauth-example` stanza, mirroring `notion-client-example`'s language, extensions and `ghc-options`, with `hs-source-dirs: notion-client-oauth-example`, `main-is: Main.hs` and `other-modules: FileTokenStore, Login`. Its `build-depends` are `aeson`, `base`, `bytestring`, `directory`, `filepath`, `http-client-tls`, `http-types`, `notion-client`, `servant-client`, `text`, `time`, `wai`, `warp` and `unix` for the POSIX file-store implementation. Mark this executable `buildable: False` on Windows rather than making the library or companion package POSIX-only. Document this example limitation. Use Mori to locate `wai` and `warp` sources and verify their current Hackage releases and upstream tags before choosing bounds. Confirm resolution with `cabal build`. Add `.notion-oauth-tokens.json`, its temporary-file pattern and its lock directory to `.gitignore`. Include example sources needed by tests in `extra-source-files` or the relevant Cabal source dirs so an sdist contains them.

`notion-client-oauth-example/FileTokenStore.hs` exports `fileTokenStore :: FilePath -> TokenStore` and `tokenFileExists :: FilePath -> IO Bool`. `loadTokens` decodes the JSON file and fails with a clear message if it is missing or invalid. `saveTokens` creates a unique temporary file in the destination directory exclusively with owner-only permissions before writing any secret bytes, writes and flushes the complete JSON, synchronizes the file, closes it, renames it over the destination, and synchronizes the parent directory on the supported POSIX platform. Clean up only that owned temporary file on failure. Never write through a predictable `<path>.tmp` or chmod after writing. Refuse symbolic-link token paths and unsafe destination directories. A successful save means the durable replacement completed; failures propagate while the manager retains the pending pair. Atomic replacement prevents a partial JSON destination, but cannot make remote rotation and local persistence one transaction.

Hold an exclusive lock for the entire command, from loading credentials through any refresh and save. A simple example-only lock is an atomically created `<path>.lock` directory released with `bracket`; if it already exists, fail clearly without touching the tokens. A crash may leave it behind: document manual removal only after verifying no example process is active. Locking only `saveTokens` is insufficient. This avoids adding a cross-process store protocol to the library.

`notion-client-oauth-example/Main.hs` reads its configuration from the environment: `NOTION_OAUTH_CLIENT_ID` and `NOTION_OAUTH_CLIENT_SECRET` are required, `NOTION_OAUTH_REDIRECT_URI` defaults to `http://localhost:8765/callback`, `NOTION_OAUTH_LISTEN_PORT` defaults to 8765, and `NOTION_OAUTH_TOKEN_FILE` defaults to `.notion-oauth-tokens.json`. It dispatches on the first argument:

- `login`: bind Warp explicitly to `127.0.0.1`, propagate bind/startup failures, and wait for listener readiness before printing the authorization URL. Validate that the configured callback URI has an absolute path and no query or fragment; use its exact path and accept only GET. Keep the listener bracketed and impose a ten-minute login timeout. A WAI application verifies the query against the pending state. Invalid or forged callbacks get a generic 400 and leave the pending login intact. Atomically claim a valid callback once; duplicates get 409 and cause no second exchange. A valid denial consumes the state and reports cancellation. For success, exchange the code once, save the initial pair, and only then answer “Connected” and signal completion. If exchange or storage fails, answer a generic failure and propagate a redacted diagnostic to the console; never report connection success before storage succeeds. Do not echo unescaped descriptions, callback query strings or credentials into HTML or logs. Respond with `Cache-Control: no-store` and `Referrer-Policy: no-referrer`. If an initial save fails, retain the received pair in the process and offer a retry of that save; never exchange the same code again. Termination before a successful save may require another login.
- `whoami`: build an `OAuthTokenManager` from the file store, then `Methods` with `makeMethodsWithTokenSource defaultClientConfig env (tokenManagerSource manager)`. Print the bot name from `retrieveMyUser` and up to five `search` results; an empty search is valid and should be reported without treating it as an auth failure.
- `refresh`: call `refreshTokensNow`; compare the complete old and new strings in memory and print `access token changed: True/False` and `refresh token changed: True/False` (or “not returned”). No suffix or token is printed. If persistence fails, keep the manager alive and offer `retryTokenPersistence` without another OAuth request; do not silently exit claiming rotation succeeded durably.
- `revoke`: call `revokeOAuthToken` with the stored access token. After confirmed success, remove the local credentials under the command lock and require a new login. On failure keep the file and report the failure. Local logout must not depend on an assumption that revoking one token invalidates its refresh token.

Wrap the top level so `OAuthError`, `ReauthorizationRequired`, `TokenPersistenceError`, `RefreshOutcomeUnknown` and `NotionError` produce redacted one-line messages. Distinguish a fixable store failure, an uncertain refresh requiring a new login, bad client credentials, and user cancellation. With no or an unknown argument, or missing required credentials, print usage and exit with status 2. Missing local tokens for `whoami` print “Run login again” and exit nonzero.

Factor the callback application and orchestration into `notion-client-oauth-example/Login.hs` so tests can inject OAuth methods and storage. Add `tasty/OAuthExampleTests.hs` to the suite with the required example source directory and test dependencies. Test invalid state followed by valid success, authenticated cancellation, duplicate concurrent callbacks with one exchange, no success response before save, startup failure, timeout cleanup, generic escaped-safe error pages, no secret logging, and restart loading of a saved pair. File tests use a temporary directory and verify restrictive permissions, complete replacement, rejection of unsafe symlinks, retained old destination on a pre-rename failure, and exclusion of a second process/command by the lock. These run without real credentials.

Add a header comment in `Main.hs`, like the one in `notion-client-example/Main.hs`, with the setup steps from Context and Orientation.

### Milestone 2: live verification


This milestone needs a person: create the integration, export the credentials in the shell, and click through the consent page. If credentials are not available, record "live run pending credentials" in Progress and finish all offline tests and Milestone 3 documentation/build work. Report the missing live gate after that work; lack of credentials does not block independent authorized work. Do not mark this plan or the MasterPlan complete without this run.

Run the sequence in Concrete Steps and record short evidence (no secrets) in Surprises & Discoveries. Answer each of these questions:

1. Did Notion accept `http://localhost` as a redirect URI?
2. Does the token response's `owner` decode (user or workspace)?
3. Does explicit refresh return a new pair, persist it, and let a fresh process run `whoami` successfully? Compare full values in memory and record booleans only. A matching last-four suffix is not evidence that two tokens are identical.
4. The checked-in test-only `scripts/OAuthLiveCheck.hs` provides the isolated reactive-refresh harness. Run it explicitly with the command below; it is never part of offline `cabal test`. Does a public `Methods` request rejected with `unauthorized` take the automatic path? In a test-only harness, replace only the locally held access-token value with a deliberately invalid sentinel while retaining the freshly saved valid refresh token. Make one `retrieveMyUser` call through the manager, observe one refresh and a successful retry, then persist the replacement pair. Do not expose a corruption flag in the user-facing executable or reuse an older refresh token. This proves the real rejection/classification/renewal path without waiting for expiry.
5. After `revoke`, is local logout complete and does `whoami` require login without attempting refresh? The remote response and optional introspection may document remote validity, but acceptance does not assume revocation of an entire token family.
6. Does a cancelled consent with matching state produce `AuthorizationDenied OAuthAccessDenied` and no exchange?

Copy findings that affect sibling plans into the MasterPlan. A null refresh token is supported by the published response schema but cannot pass the full refreshing-installation gate; record it and keep that part pending until a refresh-capable installation is available. If a live response contradicts the agreed contract, revise the plans and tests before claiming completion. Old-refresh-token reuse is unnecessary for acceptance; any separate investigation requires a disposable installation and must never overwrite the primary token store.

### Milestone 3: documentation and release preparation


Rewrite `README.md`'s "### OAuth" section as a complete walkthrough: integration setup, the login steps with `Notion.V1.OAuth.Authorization`, building `Methods` from `newOAuthTokenManager`, handling `ReauthorizationRequired`, `OAuthError`, `TokenPersistenceError` and `RefreshOutcomeUnknown`, and a pointer to `cabal run notion-client-oauth-example`. Update the features line ("OAuth token exchange and URL-to-ID helpers") and the API-coverage bullet ("**OAuth**: …") to mention the login flow and automatic refresh. Add an "OAuth example" subsection under "## Running the Example".

In `CHANGELOG.md`, turn `## Unreleased` into `## 0.10.0.0 (<date>)`, merging duplicate subsections left by the sibling plans. Set `version: 0.10.0.0` in `notion-client.cabal`. These numbers assume the current 0.9.0.0/0.3.0.0 versions; if another initiative releases first, recalculate the next breaking version and adapter bound together instead of downgrading either package. In `notion-client-effectful/notion-client-effectful.cabal`, change the bound to `notion-client >=0.10 && <0.11` and bump that package to `0.4.0.0`, with a `notion-client-effectful/CHANGELOG.md` entry noting that it requires the new core release and requires no effect constructor changes, because `runNotion` takes `Methods`. Update its README and interpreter Haddock to state that refresh and persistence exceptions propagate in IO; `Error NotionError` catches only Notion API errors. Do not publish to Hackage; publishing is the maintainer's decision.

Review and finalize [ADR 9](../adr/9-oauth-callback-and-token-lifecycle-boundaries.md) against live evidence, following `agents/skills/exec-plan/ADR.md`. It already records protocol-only library scope, the confidential-client boundary, per-manager serialization, no PKCE/timer, and Notion MCP OAuth exclusion. Update ADR 8 with a link if useful; do not create a duplicate exclusions ADR.


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

Run the isolated automatic-refresh acceptance check after explicit refresh and restart, before revoke. It uses the current saved refresh token and changes only the in-memory access token:

```bash
cabal exec -- runghc -package=notion-client -XGHC2024 -XOverloadedStrings -XDuplicateRecordFields -XRecordWildCards -inotion-client-oauth-example scripts/OAuthLiveCheck.hs
```

Expected: a successful unauthorized/refresh/retry path, exactly one refresh, persisted replacement `True`, and full-value token rotation booleans. This is an explicit live operation on the installation, not an offline fixture.

Final checks for Milestone 3:

```bash
cabal build all
env -u NOTION_TOKEN cabal test --test-show-details=direct --test-options='-p OAuthExample'
env -u NOTION_TOKEN cabal test --test-show-details=direct
```

Commit at each milestone with Conventional Commits and trailers, for example:

```text
feat(example): add an OAuth login example for public integrations

MasterPlan: docs/masterplans/3-support-notion-public-integrations-with-an-oauth-login-flow.md
ExecPlan: docs/plans/19-demonstrate-and-document-the-public-integration-oauth-login-end-to-end.md
Intention: intention_01m52739hkexps2gwzdp5hnn4a
```


## Validation and Acceptance


Milestone 1 is accepted when the `OAuthExample` tests pass, `cabal build all` succeeds, and the no-argument run prints usage and exits with status 2.

Milestone 2 is accepted when a person has completed the live sequence and every one of the six questions has a recorded answer. Include the isolated automatic-refresh harness result, not just the explicit refresh command. In particular, `whoami` must succeed both before and after `refresh`, `refresh` must compare full values and show rotation booleans for both tokens, a new process must load the saved pair, and the injected-invalid-access-token check must demonstrate automatic refresh, and the cancelled consent must print the cancellation message.

Milestone 3 is accepted when the README walkthrough's code type-checks (copy it into a scratch module, or check it in `cabal repl`), both packages build at their new versions, and the full test suite passes. The plan as a whole, and therefore the MasterPlan's integration gate, is complete only after all three milestones.


## Idempotence and Recovery


`login` overwrites the token file atomically and can be repeated; each login may issue a new token pair. `revoke` removes local credentials only after a successful remote response. Failed saves can be retried from the retained pair in the same process; after an uncertain exchange or a crash that loses an unsaved pair, authorize again. If the listener port is busy, set `NOTION_OAUTH_LISTEN_PORT` together with a matching registered redirect URI. The integration created in Notion can be deleted from the developer portal after testing. Version bumps are plain text edits and can be reverted with git if the release is postponed.


## Interfaces and Dependencies


New executable-only dependencies: `wai`, `warp`, `directory`, `filepath` and `unix` (POSIX permissions and synchronization). The callback/file-store test group also needs the executable helpers and these dependencies. Use a conditional test module list and CPP import/registration guard so Windows skips only these POSIX example tests; existing core tests must continue to build. The library gains no dependencies from this plan.

Consumes, and requires Complete: `docs/plans/16-decode-oauth-token-endpoint-errors-into-a-typed-exception.md` (`OAuthError`), `docs/plans/17-build-authorization-urls-and-exchange-codes-from-verified-oauth-callbacks.md` (`Notion.V1.OAuth.Authorization`), and `docs/plans/18-refresh-oauth-access-tokens-automatically-for-methods.md` (`Notion.V1.OAuth.Refresh`, `makeMethodsWithTokenSource`).

Owns, per the MasterPlan's Integration Points: the `0.10.0.0` version bump, the `notion-client-effectful` bound and version, the final `CHANGELOG.md` section, and the README OAuth walkthrough.


Revision (2026-10-16): Make the listener and persistence observable in offline tests, protect callback single use and token files, require both forced and automatic live refresh, and remove unproven invalidation and suffix-comparison assumptions. Complete offline work while live credentials are pending.
