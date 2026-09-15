# ADR 8: The core REST client excludes unpublished routes and JS-only mechanics

Status: Accepted
Date: 2026-09-15


## Context

In August 2026 the official JS SDK added custom agents, sessions, threads and external-agent stub
routes. Its commits (#768, #769, #770, #786, #787) describe these routes as unpublished, one
sub-surface is literally named "stub", and the contract changed weekly. The surface is roughly 27
endpoints and 60 to 80 object shapes.

The SDK also has mechanics that exist only because of JavaScript: a `warnUnknownParams` runtime
warning, an injectable `fetch`, and `isFull*` type guards.


## Decision

- **Unpublished routes.** Parity work on the published REST API
  (`docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md`)
  excludes them. They are coordinated separately by
  `docs/masterplans/2-add-the-custom-agents-and-sessions-api-with-sse-streaming.md`, which builds
  on the published API's runtime (ADR 2) and async tasks (ADR 3) but must not change them.
- **JS-only mechanics.** They have no Haskell counterpart:
  - Records make unknown request parameters a compile error, so there is no unknown-parameter
    warning.
  - `ClientEnv` and `Manager` already let callers supply the transport.
  - Sum types express full-or-partial objects (ADR 4), so there are no type guards.
- **Code generation.** Generating Haskell types from Notion's schema is out of scope. Types are
  written by hand against the SDK's generated types (ADR 6).


## Consequences

- Churn in unpublished routes cannot block or break releases of the published client.
- A route that Notion publishes later moves into core scope through its own plan.
- Hand-written types need a periodic diff against new SDK releases to stay current.
