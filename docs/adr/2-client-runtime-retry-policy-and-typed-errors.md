# ADR 2: One client runtime with the JS SDK's retry policy and typed errors

Status: Accepted
Date: 2026-09-15


## Context

Before 2026-09-15, every `Methods` call ran `servant-client` directly. A single HTTP 429 became an
exception. Error codes were untyped strings, and the `Notion-Version` header was hard-coded.
Notion's official TypeScript SDK (`@notionhq/client` 5.26.0) retries some failures automatically
and distinguishes Notion's error envelope from other failed responses. Several later plans also
need to send requests that do not go through Servant, for example server-sent event streams in
`docs/plans/14-stream-session-updates-over-server-sent-events.md`, and those requests must
behave the same way.


## Decision

All requests share one runtime, defined in `src/Notion/V1/Client.hs`, `src/Notion/V1/Retry.hs`
and `src/Notion/V1/Error.hs`.

- **Where it runs.** The runtime is a servant-client `ClientEnv` middleware, so Servant needs
  servant-client 0.20.2 or newer. It retries only the HTTP exchange; decoding the response
  happens afterwards. The timeout is set on the http-client request (`responseTimeout`, which
  covers connecting and waiting for response headers), not with `System.Timeout`, so long-lived
  streams are not killed.
- **Retry policy (ported from the JS SDK).** The decision is keyed on the error code in the JSON
  body, not on the HTTP status:
  - `rate_limited` and `service_overload` are retried for every method;
  - `internal_server_error` and `service_unavailable` are retried only for `GET` and `DELETE`;
  - nothing else is retried, including `gateway_timeout`, unknown codes, non-JSON responses and
    timeouts.

  The defaults are two retries and a one-second initial delay, with delays capped at 60 seconds.
  A `retry-after` header (delta-seconds or an HTTP date) sets the delay; otherwise the delay is
  `base * jitter + base / 2` with `base = initial * 2^attempt`.
- **Errors.** A Notion error envelope becomes `NotionError`, with a typed `APIErrorCode` (which
  has an `UnknownErrorCode` fallback, per [ADR 1](1-tolerant-response-decoders.md)), the
  request ID and the response metadata. Any other non-2xx response becomes
  `UnknownHTTPResponseError`, and timeouts become `RequestTimeoutError`. These are separate
  exception types rather than one sum type, so existing `catch @NotionError` handlers keep
  working.
- **Existing callers.** `makeMethods` keeps its type and gains the default retries. It keeps the
  caller's `Manager` timeout.
- **Requests outside Servant.** They reuse the runtime through exported names:
  `RequestContext`, `requestContextFor`, `standardHeaders`, `responseTimeoutFor`, `withRetries`,
  `buildRequestError` and `notionErrorFromResponse`. Renaming any of them requires updating
  plan 14.


## Consequences

- Rate-limited requests succeed without caller code. The costs are added latency on failure and
  a new dependency on `random`.
- Retrying re-sends the request. That is safe for multipart uploads, because servant-client
  rebuilds `RequestBodySource` bodies for each attempt.
- OAuth uses the same runtime, with its own API type, because it authenticates with HTTP Basic
  auth instead of a bearer token.
- A request path containing `..` is rejected before sending, because `http-api-data` leaves `.`
  unencoded in URL pieces.
