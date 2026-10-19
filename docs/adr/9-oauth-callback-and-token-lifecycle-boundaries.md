# ADR 9: OAuth callbacks and rotating tokens have explicit lifecycle boundaries

Status: Accepted (library and offline example implemented; live installation gate pending)
Date: 2026-10-19


## Context

[MasterPlan 3](../masterplans/3-support-notion-public-integrations-with-an-oauth-login-flow.md)
adds browser authorization and token refresh to the existing Basic-authenticated OAuth methods.
The existing request runtime captures a fixed bearer token and retries selected Notion error
codes. A code exchange or token rotation can consume a credential, so replay and persistence
have different consequences from an ordinary API request.

The [Notion authorization guide](https://developers.notion.com/docs/authorization) documents
replacement access and refresh tokens, but does not define old-token invalidation timing or
reuse detection. The [refresh response schema](https://developers.notion.com/reference/refresh-a-token)
permits a null refresh token. Neither an in-process lock nor an atomic file replacement can
make a remote rotation and a local save one transaction.


## Decision

The library provides protocol helpers for a confidential client: its client secret and token
exchange run in a trusted process. A distributed native or browser application must use a
trusted backend; this example does not establish that embedding a client secret is safe.
Application session management, production storage, distributed locking, PKCE (undocumented
for this Notion flow), proactive timer refresh and Notion MCP OAuth remain outside scope.

Callbacks validate one nonempty state before accepting either success or denial. Duplicate
protocol fields, conflicting code/error results and malformed text are rejected. The caller
binds the request to the initiating session and atomically consumes it once before exchange;
invalid callbacks do not consume it. The pure parser does not provide expiry or replay storage.
State uses operating-system randomness and an established byte comparison primitive.

OAuth methods normalize OAuth failures locally, supporting both the OAuth `error` field and
known OAuth codes in the documented Notion envelope. Ordinary Notion codes retain `NotionError`.
OAuth calls disable automatic retries, including retries of Notion-envelope rate-limit errors.
This deliberately refines [ADR 2](2-client-runtime-retry-policy-and-typed-errors.md) for OAuth;
the ordinary API retry policy stays intact. A token request with an ambiguous result is not
automatically resubmitted.

A `TokenSource` supplies authorization for each API request. One typed `Unauthorized` failure
may trigger renewal and one replay, outside the normal retry loop. Non-Servant streams apply
this only to response acquisition: close a rejected response before renewal, and never replay
a body reader or user callback. Legacy constructors use a static source.

One `OAuthTokenManager` serializes one installation. Its internal states distinguish usable
persisted credentials, a new pair awaiting persistence, required reauthorization, and an
uncertain remote refresh outcome. A failed save retains the new pair but blocks its use and
further refresh; an explicit persistence retry saves that identical pair without calling Notion.
An ambiguous exchange blocks automatic reuse of the old refresh token. Terminal invalid-grant
failures are remembered so queued callers do not each retry them. A null replacement refresh
token remains absent; no unproven fallback resurrects the previous token.

Transitions preserve known tokens and uncertainty under asynchronous cancellation, publish
state before rethrowing, and keep network/storage operations interruptible. Recovery from an
uncertain remote outcome or a crash that loses an unsaved pair may require fresh authorization.
The store's save is idempotent and must not call back into its manager. Several managers or
processes need external coordination over the entire load/refresh/save sequence; compare-and-swap
at save time alone cannot prevent competing remote refreshes.

The example owns its loopback callback server and POSIX file store. Its default
file store accepts only an owner-only regular token file and an owned destination
directory without group/other write permission. Private temporary files are created
with mode 0600 before writing; both file and parent directory are synchronized.
The complete command holds an exclusive directory lock; crash-stale locks require
manual removal after checking no process is active. Initial-save recovery retains
the response pair and retries storage without exchanging the code again. It binds loopback explicitly,
serves no success page before exchange and save succeed, and keeps invalid callbacks from ending
a pending login. It locks the complete command, creates private temporary files before writing
secrets, synchronizes and atomically replaces the token file, and reports tokens only through
explicit metadata or comparison booleans. Confirmed revocation clears local credentials without
assuming remote revocation of the whole token family. New token/state/code types and default
exception rendering redact secrets.


## Consequences

The four child plans retain separate ownership of errors, authorization helpers, runtime token
management and the runnable example. They share this ADR instead of creating overlapping records.
The public `RequestContext` change requires a major release and a synchronized update of the
planned streaming consumer. Effectful method constructors do not change, but documentation must
explain that OAuth lifecycle exceptions remain IO exceptions outside `Error NotionError`.

Network-free tests cover duplicate/forged callbacks, request replay boundaries, concurrent
rejections, failed persistence, uncertain exchanges and cancellation. Live acceptance separately
proves consent, explicit and reactive refresh, restart with persisted credentials, cancellation
and local logout. The library and example implementations are covered by network-free tests, including
real loopback HTTP acquisition, multipart replay, callback single use, listener
cleanup, file permissions, atomic replacement and command-lock exclusion. Callback
exceptions redact descriptions and unknown code text by default; explicit fields
remain available to callers. The full public-installation live gate remains
pending until those checks pass. No claim of crash-proof or distributed exactly-once token rotation is made.
