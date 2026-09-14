---
id: 14
slug: stream-session-updates-over-server-sent-events
title: "Stream Session Updates over Server-Sent Events"
kind: exec-plan
created_at: 2026-09-14T18:46:51Z
master_plan: "docs/masterplans/2-add-the-custom-agents-and-sessions-api-with-sse-streaming.md"
provenance:
  created_by:
    model: "claude-opus-5"
    harness: "claude-code"
    at: 2026-09-14T18:46:51Z
---

# Stream Session Updates over Server-Sent Events

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Notion "custom agents" are AI agents configured inside a Notion workspace. Each conversation with an agent is a "session". Sending a message to a session with `POST /v1/sessions` normally returns one JSON object after the agent has accepted the turn. The same route, when called with the request header `Accept: text/event-stream`, instead keeps the HTTP response open and writes a live feed of what the agent is doing: a snapshot of the session, provisional (still-being-written) agent messages and tool calls, committed events with sequence numbers, and a final `stream.end` frame. That feed uses Server-Sent Events (SSE), a plain-text format in which the server writes blocks such as `event: stream.end` followed by `data: {...json...}` and a blank line.

After this plan, a Haskell program using `notion-client` can call

```haskell
streamSession methods request $ \event -> print event
```

and see each typed `SessionStreamEvent` printed the moment Notion sends it, not after the turn finishes. It can also use `withSessionStream` to pull events one at a time and stop early, with the HTTP connection closed automatically. Opening the stream obeys the same retry policy, timeout, API version and error types as every other request in the library, and it never replays a stream once events have started flowing.

You can see it working three ways: the `tasty` test suite runs a local fake SSE server and shows events arriving incrementally, retries happening only before the stream opens, and the connection being closed on early exit; the same suite checks the frame parser at every possible chunk boundary; and, with a real token and an agent id, `cabal run notion-client-example` prints a live stream from a Notion agent.


## Progress

- [ ] Pre-flight: re-diff the JS SDK `src/api-endpoints/agents.ts` and `src/Client.ts` against the shapes transcribed in this plan; record drift in Surprises & Discoveries.
- [ ] Pre-flight: run the precondition greps for `docs/plans/13-add-session-endpoints-and-session-event-types.md` and `docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md` artifacts; record the actual names found in the Decision Log.
- [ ] Milestone 1: add `warp`, `wai`, `http-types`, `http-client` to the test suite and create `tasty/SessionStreamTests.hs` registered in `notion-client.cabal` and `tasty/Main.hs`.
- [ ] Milestone 1: implement `src/Notion/V1/Sessions/Sse.hs` (pure SSE frame parser) and its unit tests, including every-chunk-boundary tests.
- [ ] Milestone 1: prototype tests proving raw `http-client` incremental delivery, open-only timeout and early close against a warp server; decide promote or fall back.
- [ ] Milestone 2: implement stream event types, `ProvisionalEvent`, `SessionStreamException` and `decodeSessionStreamEvent` in `src/Notion/V1/Sessions/Stream.hs`.
- [ ] Milestone 2: fixture tests for all six event kinds, the unknown-event fallback and each validation error.
- [ ] Milestone 3: implement `StreamEnv`, `withSessionStreamIO` and `streamSessionIO` with pre-open retries and bracketed response closing.
- [ ] Milestone 3: fake-server tests for request shape, incremental delivery, 429 retry, 500 no-retry, no retry after open, open timeout, idle body, early exit.
- [ ] Milestone 4: add `streamSession` and `withSessionStream` to `Methods` in `src/Notion/V1.hs`, wired from the client configuration.
- [ ] Milestone 4: mirror both in `notion-client-effectful` (Effect, Interpreter, re-export module).
- [ ] Milestone 4: add `notion-client-example/SessionStreamDemo.hs` gated on `NOTION_AGENT_ID`; update CHANGELOG files.
- [ ] Final: `cabal build all` and `cabal test` green; Outcomes & Retrospective written; ADR distillation pass (create `docs/adr/` entry for the SSE transport and no-retry-after-open rule).


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Implement the stream transport directly on `http-client` (`responseOpen`/`brRead`/`responseClose` inside `Control.Exception.bracket`) instead of a Servant streaming combinator (`StreamPost NoFraming ...` via `Servant.Client.Streaming.withClientM`, or servant 0.20.3's `ServerSentEvents'`).
  Rationale: (1) `Servant.Client.Streaming` defines its own `ClientM` (a `Codensity IO` stack, see `servant-client/src/Servant/Client/Internal/HttpClient/Streaming.hs` in servant-client 0.20.3.0), distinct from the `Servant.Client.ClientM` that `makeMethods` hoists, so it could not share the existing `hoistClient` call or `run` function anyway. (2) On non-2xx it `throwIO`s a `FailureResponse` from inside `Client.withResponse` rather than through `ExceptT`, so the retry/error path would still be custom. (3) servant's SSE parser (`servant-client-core/src/Servant/Client/Core/ServerSentEvents.hs`) dispatches frames that have no data, treats a lone CR as a line end and yields `Maybe` event names — all different from the JS SDK, which we mirror. (4) `http-client` is already a transitive dependency, `ClientEnv` exposes its `manager` and `baseUrl`, and in http-client 0.7.19 `responseTimeout` is applied only to connecting and reading the status line and headers (`getConnectionWrapper` in `Network/HTTP/Client/Core.hs`, `parseStatusHeaders` in `Network/HTTP/Client/Response.hs`), which is exactly the JS "timeout covers opening only" rule. (5) `responseClose` on an unread body releases the connection with `DontReuse` without draining (`cleanup False` in `Response.hs`), so early exit is cheap. Milestone 1 verifies (4) and (5) empirically before anything depends on them.
  Date: 2026-09-14

- Decision: Prove the transport against a real local HTTP server using `warp` (plus `wai`, `http-types`) as test-suite-only dependencies, and prove the parser with pure chunk-list tests.
  Rationale: Only a real socket shows that events reach the callback before the server finishes the response, and that closing the response really disconnects. The dependencies are test-only, so library users pay nothing. Pure tests cover framing edge cases exhaustively and fast.
  Date: 2026-09-14

- Decision: Check chunk boundaries exhaustively (every single split point and every pair of split points, plus one-byte chunks) instead of adding QuickCheck.
  Rationale: Fixture inputs are a few hundred bytes, so exhaustive enumeration runs in milliseconds, is deterministic, and strictly covers what random splitting would sample. Avoids a new test dependency.
  Date: 2026-09-14

- Decision: An SSE frame whose event name is not one of the six known names, but whose JSON `type` equals that name, decodes to `UnknownStreamEvent name payload` instead of throwing. A mismatch between the JSON `type` and the SSE event name, data without an event name, invalid JSON, a payload that is not an object with a string `type`, and a known event whose body fails to decode all throw `SessionStreamException`.
  Rationale: The JS SDK throws on unknown names (`parseSessionStreamEvent`, `src/Client.ts` 1203–1214), but the parent MasterPlan requires tolerant decoding because this surface changes weekly; a new event kind must not kill a running stream. A name/type mismatch or missing name is a protocol violation, not an extension, so it stays an error as in JS.
  Date: 2026-09-14

- Decision: Expose two `Methods` fields: `streamSession :: SessionUpdateRequest -> (SessionStreamEvent -> IO ()) -> IO ()` (push, runs to completion) and `withSessionStream :: SessionUpdateRequest -> (IO (Maybe SessionStreamEvent) -> IO a) -> IO a` (bracketed pull reader, allows early exit by simply returning). `streamSession` is implemented on top of `withSessionStream`.
  Rationale: The callback form is the simplest for the common "print everything" case. The JS consumer can `break` out of its async iterator; the Haskell equivalent without exceptions is a pull reader scoped by a bracket, which guarantees the response is closed on normal return, exception or early exit.
  Date: 2026-09-14

- Decision: Put the transport in a module that does not import `Notion.V1`, parameterised by a `StreamEnv` record that carries the manager, base URL, auth header, version, open timeout, a retry wrapper and an error builder. `src/Notion/V1.hs` builds the `StreamEnv` from the client configuration.
  Rationale: `Notion.V1` will import the stream module, so the stream module cannot import `Notion.V1` (import cycle). Passing EP-2's retry wrapper and error builder in keeps one retry policy (the MasterPlan forbids duplicating it) and lets tests inject a fake server's base URL.
  Date: 2026-09-14

- Decision: Mirror both fields in `notion-client-effectful` as higher-order effect operations whose callbacks run in `Eff es` (`StreamSession :: SessionUpdateRequest -> (SessionStreamEvent -> m ()) -> Notion m ()`, `WithSessionStream :: SessionUpdateRequest -> (m (Maybe SessionStreamEvent) -> m a) -> Notion m a`), interpreted with `localSeqUnliftIO` / `localLiftUnliftIO`.
  Rationale: The package's lockstep rule requires every `Methods` field to have a constructor. Keeping the callback in `IO` would force effectful users to unlift manually; running it in `Eff` lets a callback call other Notion operations. This deliberately deviates from "same argument types as `Methods`" only in replacing `IO` with `Eff es`, documented in Haddock.
  Date: 2026-09-14

- Decision: EP-3 owns the provisional event subset (`ProvisionalEvent`) with its own small text-content type, rather than reusing EP-2's committed-event content type.
  Rationale: Provisional events lack `sequence` and are transient previews; the MasterPlan assigns "the provisional event subset" to this plan. A local type avoids coupling to EP-2's internal naming.
  Date: 2026-09-14

- Decision: Do not strip a UTF-8 byte-order mark at stream start, and decode event names with lenient UTF-8 (invalid bytes become U+FFFD).
  Rationale: The JS `TextDecoder` does both, but Notion emits ASCII JSON; BOM handling across chunk boundaries adds complexity for a case not observed. Lenient decoding of names matches JS; `data` is handed to aeson as bytes.
  Date: 2026-09-14


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

**Repository.** `notion-client` (root `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`) is a Haskell library, GHC 9.12.2, language `GHC2024`, built with cabal. `cabal.project` lists two packages: `.` (`notion-client.cabal`) and `notion-client-effectful`. Build with `cabal build all`, test with `cabal test`. A pre-commit hook runs `treefmt`, which may reformat files; re-stage and commit again if it does. Default extensions in every component are `DuplicateRecordFields`, `OverloadedLabels`, `OverloadedStrings`, `RecordWildCards`.

**How requests work today.** `src/Notion/V1.hs` defines `getClientEnv :: Text -> IO ClientEnv` (a Servant `ClientEnv` holding an `http-client` `Manager` from `Network.HTTP.Client.TLS.newTlsManager` and a parsed `BaseUrl`), the `Methods` record (one `IO` function per endpoint), the Servant `API` type (every route is prefixed by `Header' '[Required, Strict] "Authorization" Text` and `"Notion-Version"`), and `makeMethods :: ClientEnv -> Text -> Methods`. `makeMethods` pattern-binds every client function from `Client.hoistClient @API Proxy run (Client.client @API Proxy) authorization notionVersion` where `authorization = "Bearer " <> token`, `notionVersion = "2026-03-11"`, and `run` executes a `ClientM` and rethrows a decoded `NotionError` (from `src/Notion/V1/Error.hs`) or the raw `ClientError`. Every endpoint is a single request followed by a single JSON response. Nothing in the library streams today.

**JSON style.** Resource modules (for example `src/Notion/V1/FileUploads.hs`) use `aesonOptions` from `src/Notion/Prelude.hs` (camelCase field names become snake_case, a trailing underscore is dropped so `type_` becomes `type`, `Nothing` fields are omitted) for simple records, and hand-written `FromJSON` instances using `LambdaCase` (`parseJSON = \case Object o -> ...`) or `withObject` for tagged unions. Timestamps are parsed with `parseISO8601 :: Text -> Parser POSIXTime` from `Notion.Prelude`. Identifiers use `newtype UUID = UUID {text :: Text}` from `src/Notion/V1/Common.hs`. Modules with an `id` record field import `Prelude hiding (id)`.

**Dependencies on other plans (hard).** This plan is EP-3 of `docs/masterplans/2-add-the-custom-agents-and-sessions-api-with-sse-streaming.md`. It consumes, and must not redefine:

From `docs/plans/13-add-session-endpoints-and-session-event-types.md` (module `src/Notion/V1/Sessions.hs`): `SessionUpdateRequest` (the three-way request union: new turn, approval, resume, with a `ToJSON` instance producing the bodies shown below), `Session` (the session object), `SessionEvent` (committed events `user.message`, `agent.message`, `agent.tool_use`, `agent.tool_result`, `session.status`, and `agent.thinking`), `SessionStatus` (seven values plus an unknown fallback) and `SessionError` (`{code, message, retryable}`).

From `docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md` (in `src/Notion/V1.hs` and `src/Notion/V1/Error.hs`): a client configuration record carrying base URL, `Notion-Version`, timeout and retry settings, a configurable constructor behind the preserved `makeMethods :: ClientEnv -> Text -> Methods`, the retry policy (429 `rate_limited` and 529 `service_overload` retried for any method; 500 and 503 only for GET/DELETE; delay from `retry-after` capped, otherwise exponential back-off with jitter; defaults 2 retries, 1 s initial delay, 60 s cap), and typed error construction (`APIErrorCode` with `UnknownErrorCode Text`, `request_id`, status, headers).

**Names in the sibling plans.** A cross-plan review on 2026-09-14 reconciled this plan against the finished drafts of both dependencies, so the names below are the intended ones. Still verify them in the pre-flight step, because implementation may rename things. If a name differs, adapt to the real name and record the mapping in the Decision Log.

From `docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md`:
- `ClientConfig`, with fields `apiBaseUrl`, `notionVersion`, `timeout`, `retryOptions`, `userAgent`, `logger`, `logLevel`.
- `RequestContext {contextConfig, contextManager, contextBaseUrl, contextAuthorization}`, built by `requestContextFor`.
- `standardHeaders :: RequestContext -> [Header]`: Authorization, Notion-Version and User-Agent.
- `responseTimeoutFor :: ClientConfig -> ResponseTimeout`.
- `withRetries :: ClientConfig -> Method -> Text -> IO a -> IO a`. `Method` is the http-types `Method`, so pass `methodPost`. The `Text` is a label for logging. It retries only when the action throws `NotionError`.
- `notionErrorFromResponse :: Status -> ResponseHeaders -> ByteString -> SomeException`.

Therefore `openOnce` must `throwIO` the exception returned by `notionErrorFromResponse` for non-2xx responses, so that a 429 or 529 carrying Notion's JSON error body is retried.

From `docs/plans/13-add-session-endpoints-and-session-event-types.md`, all in `Notion.V1.Sessions`:
- `SessionUpdateRequest`, whose branches are `NewTurnRequest`, `ApprovalRequest` and `ResumeRequest`.
- `Session`. Its retrieve-only and query-only fields are `Maybe`, so the smaller `session.snapshot` object decodes.
- `SessionEvent`, an envelope around `SessionEventPayload`.
- `parseSessionEventPayload :: Object -> Parser SessionEventPayload`. Exported specifically so provisional events, which have no `sequence`, can reuse it.
- `SessionStatus`.
- `SessionError`.
- `EventContent`, which decodes both the `file_id` file part and the queried-events resolved-file part.

Only if `withRetries` or `notionErrorFromResponse` turns out not to exist at implementation time, add the missing function to EP-2's modules as an additive refactor and record it in both plans' Decision Logs. Do not copy the logic into this module.

**Terms.**

Server-Sent Events (SSE): an HTTP response with content type `text/event-stream` whose body is a sequence of *frames*. A frame is a group of lines ended by a blank line. Each line is `field: value`. Lines beginning with `:` are comments (servers send them as keep-alives). This plan only cares about the `event` field (the frame's name) and `data` field (its payload; several `data` lines are joined with a newline).

Chunk: one piece of bytes returned by a single read from the socket. A frame can be split across chunks at any byte, and one chunk can contain several frames, so the parser must carry an unfinished remainder from one chunk to the next.

Opening the stream: sending the request and receiving a 2xx status line and headers. Retries and the timeout apply only up to this point. After it, a failure is reported to the caller and never retried, because the agent has already started work and replaying would duplicate the turn.

Bracket: `Control.Exception.bracket acquire release use`, which runs `release` whether `use` returns normally, throws, or is interrupted.

**The JS SDK reference.** The official Notion TypeScript SDK v5.26.0 is checked out at `/Users/shinzui/Keikaku/hub/notion-sdk-js`. You should not need to open it; everything required is transcribed here. Its behaviour, verified against the source:

`src/api-endpoints/agents.ts` lines 336–352 define the endpoint: method `post`, path `sessions`, body params `message, agent_id, session_id, attachments, metadata, prompt_context, actions, continue_from`, headers `{ Accept: "text/event-stream" }`. It is the same path and body as the non-streaming `updateSession` (line 5112); only the `Accept` header differs. The request parameters (lines 14–46):

```typescript
export type UpdateSessionStreamParameters =
  | {
      message: string
      agent_id?: string | "notion_ai" | "33333333-3333-3333-3333-333333333333"
      session_id?: string
      attachments?: Array<{ file_upload: { id: string }; type?: "file_upload"; name?: string }>
      metadata?: Record<string, string>
      prompt_context?: string
    }
  | {
      session_id: string
      actions: Array<{ action_id: string; option_id: "approve" | "reject" }>
      metadata?: Record<string, string>
    }
  | { session_id: string; continue_from: string }
```

The stream events (lines 51–333), with doc comments removed:

```typescript
export type UpdateSessionStreamResponse =
  | {
      type: "session.snapshot"
      session: {
        object: "session"; id: string; agent_id: string; title: string
        status: "queued" | "in_progress" | "requires_action" | "completed" | "failed" | "canceled" | "terminated"
        created_at: string; updated_at: string
        required_actions?: Array<{ action_id: string; title: string
          options: Array<{ id: "approve" | "reject"; label: string }> }>
        error?: { code: string; message: string; retryable: boolean }
      }
    }
  | {
      type: "event.provisional"
      event:
        | { object: "session_event"; id: string; session_id: string; created_at: string
            type: "agent.message"; content: Array<{ type: "text"; text: string }> }
        | { object: "session_event"; id: string; session_id: string; created_at: string
            type: "agent.tool_use"; tool_name: string }
    }
  | {
      type: "event.committed"
      event:  // every variant also has object: "session_event", id, session_id, sequence: number, created_at
        | { type: "user.message"
            content: Array<{ type: "text"; text: string } | { type: "file"; file_id: string }>
            metadata?: Record<string, string> }
        | { type: "agent.message"; content: Array<{ type: "text"; text: string }> }
        | { type: "agent.tool_use"; tool_name: string }
        | { type: "agent.tool_result"; tool_use_id: string; tool_name: string; is_error: boolean }
        | { type: "session.status"
            status: "queued" | "in_progress" | "requires_action" | "completed" | "failed" | "canceled" | "terminated"
            required_actions?: Array<{ action_id: string; title: string
              options: Array<{ id: "approve" | "reject"; label: string }> }>
            error?: { code: string; message: string; retryable: boolean }
            usage?: { total_tokens: number; input_tokens?: number; output_tokens?: number }
            artifacts?: Array<{ type: "page"; url: string; title: string }
                            | { type: "html_artifact"; url: string; page_url: string }> }
    }
  | { type: "stream.timeout"; session_id: string; message: string }
  | { type: "stream.end"; session_id: string
      status: "requires_action" | "completed" | "failed" | "canceled" | "terminated"
      last_sequence: number }
  | { type: "stream.error"; error: { code: string; message: string; retryable: true | false }
      session_id?: string }
```

Note that the `session.snapshot` session has fewer fields than the object returned by `sessions.retrieve`, provisional events have no `sequence`, and a committed `user.message` file part carries `file_id` (the queried-events variant instead carries `name, content_type, url, expiry_time`).

`src/Client.ts` runtime, verified:

- `streamRequest` (lines 235–315) builds the same headers as JSON requests (`authorization: Bearer ...`, `Notion-Version`, `content-type: application/json` when there is a body) plus the endpoint's `Accept: text/event-stream`, then calls `executeWithRetry` (line 435) around `executeSingleStreamRequest` (lines 512–532). The latter awaits `fetch` under the client timeout (default `DEFAULT_TIMEOUT_MS = 60_000`, `src/constants.ts`) and, if the status is not ok, reads the body text and throws `buildRequestError`. Its doc comment: "only the initial, retryable HTTP failures are retried; once a stream has opened, its events are never replayed." `canRetry` (line 573) retries `rate_limited` and `service_overload` for every method and `internal_server_error`/`service_unavailable` only for GET/DELETE, so for this POST only 429 and 529 are retried.
- After opening, it reads the body with a reader, decodes bytes to text, and calls `takeSseFrames({content: remaining + newText, complete: false})` for each chunk, yielding each parsed event. When the body ends it calls `takeSseFrames({content: remaining, complete: true})`. In `finally`, if the body was not fully read (the consumer broke out early), it calls `reader.cancel()`, then `releaseLock()`. The timeout does not apply to body reading.
- `takeSseFrames` (lines 1140–1166): replace every `\r\n` with `\n`; repeatedly find `\n\n`, parse the text before it as a frame, keep the text after it; when `complete` is true and the remainder is non-empty, parse the remainder as a final frame.
- `parseSseFrame` (lines 1168–1201): split on `\n`; skip lines starting with `:`; skip lines with no `:`; field is text before the first colon; value is text after it with exactly one leading space removed if present; `event` sets the name (last one wins), `data` appends a data line; every other field (`id`, `retry`, anything) is ignored. No data lines: the frame is dropped. Data lines but no event name: throw "Session stream event is missing its SSE event name." Otherwise the frame is `{eventName, data: dataLines.join("\n")}`.
- `parseSessionStreamEvent` (lines 1203–1214): `JSON.parse(data)`; throw "Session stream event does not match its SSE event name." unless the payload is an object whose `type` is one of the six names and equals `eventName`. Nested event variants are not validated. `stream.error` is yielded as an ordinary event, not thrown.

JS tests in `test/Client.test.ts` that this plan mirrors: "streams session events as SSE frames arrive" (line 652: two chunks `stream.error` then `stream.end`, asserts `Accept: text/event-stream`, `content-type: application/json`, body `{"message":"hello"}`), "types streamed tool lifecycle events without tool payloads" (690), "types streamed user messages and session status metadata" (723), "cancels an open session stream when the consumer stops early" (790), and "retries opening a session stream on rate limit" (1215).

**Files this plan creates or edits.**

- `src/Notion/V1/Sessions/Sse.hs` (new, exposed): pure SSE framing.
- `src/Notion/V1/Sessions/Stream.hs` (new, exposed): stream event types, validation, `StreamEnv`, transport.
- `src/Notion/V1.hs`: two new `Methods` fields and their wiring.
- `notion-client.cabal`: new exposed modules; library deps `http-client`, `http-types`; test-suite deps and `other-modules`; example `other-modules`.
- `tasty/SessionStreamTests.hs` (new) and one line in `tasty/Main.hs`.
- `notion-client-effectful/src/Notion/V1/Effectful/Effect.hs`, `Interpreter.hs`, `notion-client-effectful/src/Notion/V1/Effectful.hs`, `notion-client-effectful/notion-client-effectful.cabal` (if a dependency is needed).
- `notion-client-example/SessionStreamDemo.hs` (new) and `notion-client-example/Main.hs`.
- `CHANGELOG.md` and `notion-client-effectful/CHANGELOG.md`.

**Tests layout.** `tasty/Main.hs` (about 2300 lines) assembles a top-level `testGroup "Notion Client Tests" [jsonParsingTests, jsonSerializationTests, propertyValueTests, fileUploadTests, basicIntegration, markdownE2E, pageE2E, databaseE2E, viewE2E]` near line 158. Per the MasterPlans' convention, this plan adds a new module `tasty/SessionStreamTests.hs` exporting `tests :: TestTree`, lists it under `other-modules` of `test-suite tasty` in `notion-client.cabal` (the stanza currently has no `other-modules` field; add one), imports it qualified in `tasty/Main.hs` (`import SessionStreamTests qualified`) and adds `SessionStreamTests.tests` to that list. Fixtures never use the maintainer's real name; use made-up Japanese names such as "Tanaka Hanako" or "Sato Kenji".

**ADRs.** This repository has no `docs/adr/` directory; no relevant ADR exists.


## Plan of Work

The work has four milestones. The first is a labelled prototype that removes the transport risk and delivers the pure parser; it does not depend on the other plans. The second adds typed events and needs `docs/plans/13-add-session-endpoints-and-session-event-types.md`. The third builds the real transport and needs `docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md`. The fourth exposes it publicly, mirrors it in the effectful package and adds the demo.


### Pre-flight

Re-diff the JS SDK against this plan, as the MasterPlan requires, and check the prerequisite artifacts. Run the commands in Concrete Steps. If the six event names or any field transcribed above changed, update the transcription, fixtures and types, and write the drift into Surprises & Discoveries. Record the real names of EP-2 and MP1 EP-2 artifacts in the Decision Log.


### Milestone 1: transport prototype and pure SSE frame parser

Scope: prove that raw `http-client` delivers an SSE body incrementally, that its `responseTimeout` does not cut off a long-idle body, and that `responseClose` disconnects promptly; and implement the frame parser. At the end, `src/Notion/V1/Sessions/Sse.hs` exists with tests, and the prototype tests pass. Nothing is added to `Methods`.

First add test infrastructure. In `notion-client.cabal`, `test-suite tasty` stanza, add to `build-depends`: `http-types`, `wai`, `warp` (`http-client` and `bytestring` are already there), and add `other-modules: SessionStreamTests`. In the `library` stanza add `http-client >=0.7 && <0.8` and `http-types >=0.12 && <0.13` to `build-depends` and `Notion.V1.Sessions.Sse` to `exposed-modules`. Create `tasty/SessionStreamTests.hs` with `module SessionStreamTests (tests) where` and `tests = testGroup "Session streaming" [sseParserTests, transportPrototypeTests]`, and register it in `tasty/Main.hs` as described in Context and Orientation.

Then write `src/Notion/V1/Sessions/Sse.hs`. It works on strict `Data.ByteString.ByteString` rather than `Text` so that a multi-byte UTF-8 character split across chunks is never decoded half-way; the bytes `\n` (10) and `:` (58) never occur inside a multi-byte UTF-8 sequence, so splitting on them is safe.

```haskell
module Notion.V1.Sessions.Sse
  ( SseFrame (..),
    SseParseError (..),
    SseBuffer,
    emptySseBuffer,
    feedSse,
    finishSse,
    parseSseFrame,
  )
where

import Data.ByteString (StrictByteString)
import Data.Text (Text)

-- | One complete SSE frame that carried data.
data SseFrame = SseFrame
  { eventName :: Text,              -- ^ value of the last @event:@ line (lenient UTF-8)
    eventData :: StrictByteString   -- ^ all @data:@ values joined with a single '\n'
  }
  deriving stock (Eq, Show)

-- | A frame had @data:@ lines but no @event:@ line. Carries the joined data.
newtype SseParseError = SseMissingEventName StrictByteString
  deriving stock (Eq, Show)

-- | Unfinished bytes carried from one chunk to the next (already CRLF-normalised).
newtype SseBuffer = SseBuffer StrictByteString
  deriving stock (Eq, Show)

emptySseBuffer :: SseBuffer

-- | Append a chunk, normalise every "\r\n" to "\n" in (buffer <> chunk), and
-- return every frame completed by a "\n\n" boundary, in order, plus the remainder.
feedSse :: SseBuffer -> StrictByteString -> Either SseParseError ([SseFrame], SseBuffer)

-- | End of body: parse a non-empty remainder as a final frame.
finishSse :: SseBuffer -> Either SseParseError [SseFrame]

-- | Parse the text of one frame (no "\n\n" inside). 'Right Nothing' when it has no data lines.
parseSseFrame :: StrictByteString -> Either SseParseError (Maybe SseFrame)
```

Implement exactly the JS rules. `feedSse (SseBuffer rest) chunk`: let `buf = normaliseCrlf (rest <> chunk)` where `normaliseCrlf` replaces each `"\r\n"` with `"\n"` (a trailing lone `\r` stays, so a CRLF split across chunks is joined on the next feed); loop with `Data.ByteString.breakSubstring "\n\n" buf`; if the separator part is empty, stop and return the frames so far and `SseBuffer buf`; otherwise parse the prefix with `parseSseFrame`, keep a `Just` frame, and continue on `Data.ByteString.drop 2` of the separator part. If any frame returns `Left`, return that `Left` (earlier frames from the same feed are discarded, as JS does). `finishSse (SseBuffer rest)` returns `Right []` when `rest` is empty, otherwise `maybeToList <$> parseSseFrame rest`. `parseSseFrame` splits on byte 10, folds over lines keeping `(Maybe name, reversed data lines)`: a line starting with `:` is skipped; a line with no `:` is skipped; otherwise `field = take i line`, `rest = drop (i + 1) line`, `value = fromMaybe rest (stripPrefix " " rest)`; `"event"` replaces the name, `"data"` adds a data line, anything else is ignored. With no data lines return `Right Nothing`; with data but no name return `Left (SseMissingEventName joined)`; otherwise return the frame with the name decoded by `Data.Text.Encoding.decodeUtf8With Data.Text.Encoding.Error.lenientDecode` and data lines joined by `Data.ByteString.intercalate "\n"`. Note an empty `event:` value is a present, empty name (JS behaviour), which later fails the type check.

Parser tests (`sseParserTests`), each a `testCase` with literal expected values:

1. Two frames in one chunk (`event: stream.error\ndata: {...}\n\nevent: stream.end\ndata: {...}\n\n`) give two frames and an empty buffer.
2. CRLF input gives the same frames as LF input.
3. Comment lines (`: keep-alive`), `id:` and `retry:` lines, and a line with no colon are ignored.
4. `data:x` (no space) and `data:  x` (two spaces, value keeps one space) are handled.
5. Two `data:` lines join as `"line1\nline2"`.
6. A frame with only `event: ping` is dropped; a frame with only comments is dropped.
7. `data: {}` with no `event:` yields `Left (SseMissingEventName "{}")`.
8. A trailing frame without the final blank line is not returned by `feedSse` but is returned by `finishSse`.
9. Every single split: for a fixture string `s` containing CRLF line endings, comments, a multi-data frame and a final unterminated frame, for every `i` in `[0 .. length s]` feed `take i s` then `drop i s` then `finishSse`, and assert the concatenated frames equal the one-chunk result (which is itself compared to a literal list). Repeat for every pair `i <= j` (three chunks) and for one-byte chunks. Write a helper `runChunks :: [StrictByteString] -> Either SseParseError [SseFrame]`. Include a chunk split between `\r` and `\n` and one between the two `\n` of a boundary; the exhaustive loops cover them, but also add one named case each so a failure message is readable.
10. A multi-byte UTF-8 event name (for example `event: 進捗`) split mid-character still yields `eventName == "進捗"`.

Then the prototype (`transportPrototypeTests`), clearly labelled "prototype" in test names. These tests use only `http-client`, `warp` and the new parser, not any session types. Use `Network.Wai.Handler.Warp.testWithApplication (pure app) $ \port -> ...` and `Network.Wai.responseStream status200 [("Content-Type", "text/event-stream")] $ \write flush -> ...` with `Data.ByteString.Builder.byteString` chunks. The client builds a request with `Network.HTTP.Client.parseRequest ("http://127.0.0.1:" <> show port <> "/v1/sessions")`, `method = "POST"`, and uses `responseOpen` / `brRead` / `responseClose` under `bracket` with a manager from `newManager defaultManagerSettings`.

- "prototype: frames arrive before the response ends": the server writes frame 1, flushes, then blocks on `takeMVar gate`; the client reads until the parser yields frame 1, then `putMVar gate ()`; the server writes frame 2 and returns. Wrap the whole test in `System.Timeout.timeout 5000000` and fail on `Nothing`. If `http-client` buffered the whole body, this deadlocks and the timeout fails the test.
- "prototype: responseTimeout covers opening only": request `responseTimeout = responseTimeoutMicro 500000`; the server sends headers and frame 1 immediately, sleeps 1.5 s, sends frame 2. The client must receive both frames without exception. A second case has the server sleep 1.5 s *before* responding; the client must get an `HttpExceptionRequest _ ResponseTimeout` (or `ConnectionTimeout`).
- "prototype: closing early disconnects": the server writes frame 1 then loops writing `": keep-alive\n\n"` every 50 ms, with `Control.Exception.finally` putting `()` into a `serverDone` MVar. The client reads frame 1 and exits the bracket. Assert the bracket returns within 1 s and that `serverDone` is filled within 2 s (Warp's write fails once the socket is closed).

Promotion criteria: if all three prototype tests pass, the raw `http-client` design is promoted and Milestone 3 builds on it; keep these tests as regression tests. If incremental delivery or the open-only timeout fails, stop, record evidence in Surprises & Discoveries, and re-evaluate the Servant streaming alternative in the Decision Log before continuing.

Acceptance: `cabal test` shows the "Session streaming" group with all SSE parser and prototype tests passing.


### Milestone 2: typed stream events and validation

Scope: the Haskell representation of every stream event and the function that turns an `SseFrame` into one, with the unknown-event fallback and validation errors. At the end, `src/Notion/V1/Sessions/Stream.hs` exists (types and decoding only) and fixture tests pass. Requires the session types from `docs/plans/13-add-session-endpoints-and-session-event-types.md`.

Add `Notion.V1.Sessions.Stream` to `exposed-modules`. Define:

```haskell
module Notion.V1.Sessions.Stream
  ( -- * Events
    SessionStreamEvent (..),
    ProvisionalEvent (..),
    ProvisionalContent (..),
    StreamTimeoutInfo (..),
    StreamEndInfo (..),
    StreamErrorInfo (..),
    decodeSessionStreamEvent,
    -- * Errors
    SessionStreamException (..),
    -- * Transport (Milestone 3)
    StreamEnv (..),
    withSessionStreamIO,
    streamSessionIO,
  )
where

-- | One event from a session stream (the JSON payload's "type" selects the constructor).
data SessionStreamEvent
  = SessionSnapshot Session               -- ^ "session.snapshot": payload field "session"
  | EventProvisional ProvisionalEvent     -- ^ "event.provisional": payload field "event"
  | EventCommitted SessionEvent           -- ^ "event.committed": payload field "event"
  | StreamTimeout StreamTimeoutInfo       -- ^ "stream.timeout"
  | StreamEnd StreamEndInfo               -- ^ "stream.end"
  | StreamError StreamErrorInfo           -- ^ "stream.error" (a value, not an exception)
  | UnknownStreamEvent Text Value         -- ^ unrecognised type name and the whole raw payload
  deriving stock (Show)

-- | A not-yet-committed preview. No sequence number.
data ProvisionalEvent
  = ProvisionalAgentMessage
      { id :: Text, sessionId :: UUID, createdAt :: POSIXTime, content :: Vector ProvisionalContent }
  | ProvisionalToolUse
      { id :: Text, sessionId :: UUID, createdAt :: POSIXTime, toolName :: Text }
  | UnknownProvisionalEvent Value
  deriving stock (Show)

data ProvisionalContent
  = ProvisionalText Text                  -- ^ {"type":"text","text":...}
  | UnknownProvisionalContent Value
  deriving stock (Show)

data StreamTimeoutInfo = StreamTimeoutInfo { sessionId :: UUID, message :: Text }
  deriving stock (Show)

data StreamEndInfo = StreamEndInfo
  { sessionId :: UUID, status :: SessionStatus, lastSequence :: Natural }
  deriving stock (Show)

data StreamErrorInfo = StreamErrorInfo
  { sessionError :: SessionError, sessionId :: Maybe UUID }  -- JSON keys "error", "session_id"
  deriving stock (Show)

data SessionStreamException
  = SseFramingError SseParseError
  | StreamEventInvalidJson { sseEventName :: Text, reason :: Text, rawData :: StrictByteString }
  | StreamEventMissingType { sseEventName :: Text, payload :: Value }
  | StreamEventNameMismatch { sseEventName :: Text, payloadType :: Text }
  | StreamEventDecodeFailure { sseEventName :: Text, reason :: Text, payload :: Value }
  deriving stock (Show)

instance Exception SessionStreamException

decodeSessionStreamEvent :: SseFrame -> Either SessionStreamException SessionStreamEvent
```

Positional constructors are used for `SessionStreamEvent` because `DuplicateRecordFields` does not allow one field name (`event`) with two types inside a single data type. `sessionError` is used instead of `error` to avoid shadowing `Prelude.error`. The module needs `import Prelude hiding (id)` because `ProvisionalEvent` has an `id` field. `ProvisionalEvent` has a partial-field shape (fields shared by two constructors, absent from the third); `notion-client`'s library uses `-Wall` without `-Wpartial-fields`, so this compiles cleanly, matching existing modules such as `FileImportResult` in `src/Notion/V1/FileUploads.hs`.

Write hand-written `FromJSON` instances in the repository style. `SessionStreamEvent`: `withObject`, read `type`, and dispatch: `"session.snapshot"` parses `o .: "session"`, `"event.provisional"` and `"event.committed"` parse `o .: "event"`, `"stream.timeout"` parses `session_id` and `message`, `"stream.end"` parses `session_id`, `status`, `last_sequence`, `"stream.error"` parses `error` and optional `session_id` (`.:?`), any other string gives `UnknownStreamEvent other (Object o)`. `ProvisionalEvent`: dispatch on `type` (`agent.message`, `agent.tool_use`, otherwise `UnknownProvisionalEvent`), parse `created_at` with `parseISO8601`. `ProvisionalContent`: `type == "text"` gives `ProvisionalText`, otherwise the unknown constructor. No `ToJSON` instances are needed, because these events are only ever received.

`decodeSessionStreamEvent SseFrame {eventName, eventData}` proceeds in order: `Data.Aeson.eitherDecodeStrict eventData` or `StreamEventInvalidJson`; the value must be an `Object` whose `"type"` is a `String` or `StreamEventMissingType`; that string must equal `eventName` or `StreamEventNameMismatch`; then `Data.Aeson.Types.parseEither parseJSON value` or `StreamEventDecodeFailure`.

Precondition inside this milestone: `SessionSnapshot` reuses EP-2's `Session`. The snapshot session lacks the retrieve/query-only fields (`created_by`, `agent_version`, `models`, `trigger_type`, counts). Write the snapshot fixture test first. If it fails because EP-2's `Session` requires those fields, make them `Maybe` in `src/Notion/V1/Sessions.hs` if EP-2 has not been released, or otherwise define a local `SessionSnapshotObject` record in `Stream.hs` with exactly the snapshot fields, and record which in the Decision Log. Likewise, if EP-2's `user.message` content type cannot decode `{"type":"file","file_id":...}`, add that variant to EP-2's content type (additive) rather than duplicating the event family, and record it.

Fixture tests (`streamEventTests`), all decoding `SseFrame` values built in the test (event name plus JSON bytes written as Haskell string literals). Use session id `11111111-1111-1111-1111-111111111111`.

- `session.snapshot`: `{"type":"session.snapshot","session":{"object":"session","id":"11111111-1111-1111-1111-111111111111","agent_id":"notion_ai","title":"Weekly plan for Tanaka Hanako","status":"in_progress","created_at":"2026-08-15T03:36:28.649Z","updated_at":"2026-08-15T03:36:29.000Z"}}` decodes to `SessionSnapshot` with that title and status.
- `event.provisional` tool use (from JS test line 690): `{"type":"event.provisional","event":{"object":"session_event","id":"tool-1:use","session_id":"11111111-1111-1111-1111-111111111111","created_at":"2026-08-15T03:36:28.649Z","type":"agent.tool_use","tool_name":"callFunction"}}` gives `ProvisionalToolUse` with `toolName == "callFunction"`.
- `event.provisional` agent message with `"content":[{"type":"text","text":"こんにちは、Sato Kenji さん"}]`.
- `event.committed` user message and session status (from JS test line 723): `{"type":"event.committed","event":{"object":"session_event","id":"event-1","session_id":"11111111-1111-1111-1111-111111111111","sequence":1,"created_at":"2026-08-15T03:36:28.649Z","type":"user.message","content":[{"type":"text","text":"hello"},{"type":"file","file_id":"22222222-2222-2222-2222-222222222222"}],"metadata":{"source":"test"}}}` and `{"type":"event.committed","event":{"object":"session_event","id":"event-2","session_id":"11111111-1111-1111-1111-111111111111","sequence":2,"created_at":"2026-08-15T03:36:29.649Z","type":"session.status","status":"completed","usage":{"input_tokens":10,"output_tokens":20,"total_tokens":30},"artifacts":[{"type":"page","url":"https://notion.so/page","title":"Plan"}]}}`; assert on the constructors EP-2 defines.
- `stream.timeout`: `{"type":"stream.timeout","session_id":"11111111-1111-1111-1111-111111111111","message":"Stream time limit reached"}`.
- `stream.end`: `{"type":"stream.end","session_id":"11111111-1111-1111-1111-111111111111","status":"completed","last_sequence":2}` gives `lastSequence == 2`.
- `stream.error` without and with `session_id`: `{"type":"stream.error","error":{"code":"agent_error","message":"Retry later","retryable":false}}`.
- Unknown: event name `session.heartbeat`, data `{"type":"session.heartbeat","at":1}` gives `UnknownStreamEvent "session.heartbeat" _`.
- Errors: data `not json` gives `StreamEventInvalidJson`; `[1,2]` gives `StreamEventMissingType`; event `stream.end` with `{"type":"stream.error",...}` gives `StreamEventNameMismatch "stream.end" "stream.error"`; event `stream.end` with `{"type":"stream.end"}` gives `StreamEventDecodeFailure`.

Acceptance: `cabal test` shows these tests passing in the "Session streaming" group.


### Milestone 3: the transport with pre-open retries and resource safety

Scope: open the stream through EP-2's retry policy and timeout, feed the body to the parser and decoder, and close the response in every case. At the end, `withSessionStreamIO` and `streamSessionIO` work against the fake server. Still no `Methods` change. Requires `docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md`.

Add to `src/Notion/V1/Sessions/Stream.hs`:

```haskell
-- | Everything the transport needs, supplied by 'Notion.V1' (or by tests).
data StreamEnv = StreamEnv
  { manager :: Network.HTTP.Client.Manager,
    baseUrl :: Servant.Client.BaseUrl,     -- ^ e.g. https://api.notion.com/v1
    authorization :: Text,                 -- ^ full header value, e.g. "Bearer secret_..."
    notionVersion :: Text,
    openTimeout :: Network.HTTP.Client.ResponseTimeout,
    extraHeaders :: [Network.HTTP.Types.Header],  -- ^ e.g. User-Agent if EP-2 sets one
    retryOpen :: forall a. IO a -> IO a,   -- ^ EP-2's retry policy specialised to POST
    responseError :: Network.HTTP.Client.Response Data.ByteString.Lazy.ByteString -> SomeException
      -- ^ EP-2's typed error for a non-2xx response (status, headers, body)
  }

-- | Open the stream, then run the continuation with a reader that returns the next
-- event, or 'Nothing' once the body has ended. The response is closed when the
-- continuation returns or throws. The reader must not be used after that, nor after
-- it has thrown.
withSessionStreamIO :: StreamEnv -> SessionUpdateRequest -> (IO (Maybe SessionStreamEvent) -> IO a) -> IO a

-- | Run the callback for every event until the body ends.
streamSessionIO :: StreamEnv -> SessionUpdateRequest -> (SessionStreamEvent -> IO ()) -> IO ()
```

`RankNTypes` is part of `GHC2024`, so the rank-2 `retryOpen` field needs no pragma; bind it with `StreamEnv {..}` pattern matching rather than using it as a selector function.

Implementation of `withSessionStreamIO env@StreamEnv {..} body use`:

1. Build the request once: `parseRequest (dropTrailingSlash (showBaseUrl baseUrl) <> "/sessions")`, then set `method = "POST"`, `requestHeaders = [("Authorization", encodeUtf8 authorization), ("Notion-Version", encodeUtf8 notionVersion), ("Accept", "text/event-stream"), ("Content-Type", "application/json")] <> extraHeaders`, `requestBody = RequestBodyLBS (Aeson.encode body)`, `responseTimeout = openTimeout`. `parseRequest` does not throw on non-2xx statuses, which we want.
2. `openOnce`: `res <- responseOpen request manager`; if `statusIsSuccessful (responseStatus res)` return it; else read the error body with `brConsume` (inside `finally (responseClose res)`) and `throwIO (responseError res {responseBody = LBS.fromChunks chunks})`.
3. `Control.Exception.bracket (retryOpen openOnce) responseClose $ \res -> do reader <- newEventReader (responseBody res); use reader`. Retries and the open timeout therefore apply to `openOnce` only; exceptions from the body, the decoder or `use` escape the bracket unretried.
4. `newEventReader :: BodyReader -> IO (IO (Maybe SessionStreamEvent))` keeps an `IORef` with the `SseBuffer`, a list of already-decoded pending events and a `done` flag. `next`: if pending is non-empty, pop one; if done, return `Nothing`; otherwise `chunk <- brRead body`; an empty chunk means end of body, so run `finishSse`, decode those frames, set done and loop; a non-empty chunk runs `feedSse`, decodes the frames with `decodeSessionStreamEvent`, stores them as pending and loops. Any `Left` is thrown with `throwIO` (`SseFramingError` wraps a parser error).

`streamSessionIO env req k = withSessionStreamIO env req $ \next -> let loop = next >>= maybe (pure ()) (\e -> k e >> loop) in loop`.

Known limitation to document in Haddock: because the transport uses the `Manager` directly, a custom `makeClientRequest`, `middleware` or cookie jar installed on the Servant `ClientEnv` does not apply to streams.

Tests (`transportTests`) run against warp and build a `StreamEnv` directly: `manager` from `newManager defaultManagerSettings`, `baseUrl` from `parseBaseUrl ("http://127.0.0.1:" <> show port <> "/v1")`, `authorization = "Bearer test-token"`, `notionVersion = "2026-03-11"`, `openTimeout = responseTimeoutMicro 2000000`, `retryOpen` from EP-2's retry function configured for method POST and the smallest delays its configuration permits, `responseError` from EP-2's builder. The server records each request (method, path, headers, body) in an `IORef`/`MVar` list.

- "sends the SSE request": server answers one `stream.end` frame. Assert method `POST`, path `/v1/sessions`, headers `Accept: text/event-stream`, `Content-Type: application/json`, `Authorization: Bearer test-token`, `Notion-Version: 2026-03-11`, and that the body decodes to the JSON of EP-2's new-turn request for message `hello` (`{"message":"hello"}`).
- "delivers events as frames arrive": server sends `stream.error` frame, waits on a gate filled by the callback after it sees the first event, then sends `stream.end`. Collected event kinds equal `[stream.error, stream.end]`; whole test under a 5 s `timeout`.
- "retries opening on 429": first request answers 429 with header `retry-after: 1` (or `0` if EP-2 accepts it) and body `{"object":"error","status":429,"code":"rate_limited","message":"Slow down"}`; the second answers a `stream.end` frame. Assert events `[stream.end]` and exactly 2 requests.
- "does not retry a 500 on POST": server always answers 500 with `{"object":"error","status":500,"code":"internal_server_error","message":"boom"}`. Assert EP-2's typed error is thrown with code internal server error and exactly 1 request.
- "never retries after the stream opened": server answers 200, sends one valid frame then `event: stream.end\ndata: not json\n\n`. Assert the callback saw one event, `StreamEventInvalidJson` is thrown, and exactly 1 request was made.
- "open timeout": server sleeps 3 s before responding with `openTimeout = responseTimeoutMicro 500000`; assert an `HttpException` timeout (possibly wrapped by EP-2's retry, which must not retry it unless EP-2's policy says so) within 3 s.
- "idle body is not timed out": server sends one frame, sleeps 1.5 s, sends `stream.end`, with `openTimeout = responseTimeoutMicro 500000`; both events arrive.
- "early exit closes the connection": with `withSessionStreamIO`, read one event and return; the server's keep-alive loop ends (its `finally` MVar is filled within 2 s). Repeat with a callback that throws a test exception from `streamSessionIO`; the exception propagates and the server also observes the disconnect.
- "final frame without trailing blank line": server body ends with `event: stream.end\ndata: {...}` (no `\n\n`); the event is still delivered.

Acceptance: `cabal test` passes all transport tests; the request count assertions prove the retry-before-open rule.


### Milestone 4: public API, effectful companion, demo and changelog

Scope: make streaming available from `Methods`, from `notion-client-effectful`, and in the example program. At the end, users can call `streamSession methods req handler`.

In `src/Notion/V1.hs`: import `Notion.V1.Sessions.Stream qualified as Stream` and EP-2's `SessionUpdateRequest`; add to `Methods`, in a `-- \* Session streaming` section after the session fields EP-2 adds:

```haskell
    -- | POST /v1/sessions with Accept: text/event-stream. Calls the handler for each
    -- event as it arrives and returns when the server ends the response. Retries
    -- (429/529) and the timeout apply only to opening the stream.
    streamSession :: SessionUpdateRequest -> (SessionStreamEvent -> IO ()) -> IO (),
    -- | Like 'streamSession', but hands the continuation a reader returning the next
    -- event or 'Nothing' at end of stream. Returning early closes the connection.
    withSessionStream :: forall a. SessionUpdateRequest -> (IO (Maybe SessionStreamEvent) -> IO a) -> IO a,
```

These are not Servant routes, so nothing is added to `API` or to the `hoistClient` pattern binding. In EP-2's configurable constructor (the function `makeMethods` now wraps), in its `where` block, build `streamEnv = Stream.StreamEnv {manager = Client.manager clientEnv, baseUrl = <EP-2 configured base URL, else Client.baseUrl clientEnv>, authorization, notionVersion, openTimeout = responseTimeoutFor config, extraHeaders = <the User-Agent entry from standardHeaders (requestContextFor ...), if any>, retryOpen = withRetries config methodPost "sessions.stream", responseError = \res -> notionErrorFromResponse (responseStatus res) (responseHeaders res) (responseBody res)}` and define `streamSession = Stream.streamSessionIO streamEnv` and `withSessionStream = Stream.withSessionStreamIO streamEnv`. Re-export `SessionStreamEvent (..)` and friends from `Notion.V1.Sessions.Stream` only; do not re-export from `Notion.V1`. Because `withSessionStream` has a rank-2 type, if `RecordWildCards` construction (`Methods {..}`) rejects the polymorphic binding, give the local binding an explicit signature `withSessionStream :: forall a. ...`.

Add a test in `tasty/SessionStreamTests.hs`, "Methods.streamSession uses the client configuration": build `Methods` with `getClientEnv (Text.pack ("http://127.0.0.1:" <> show port <> "/v1"))` and `makeMethods clientEnv "test-token"` against warp, and assert events arrive and the `Notion-Version` header equals the library default.

In `notion-client-effectful/src/Notion/V1/Effectful/Effect.hs`: add to the export list under `-- * Session streaming` `streamSession, withSessionStream`; add constructors

```haskell
  StreamSession :: SessionUpdateRequest -> (SessionStreamEvent -> m ()) -> Notion m ()
  WithSessionStream :: SessionUpdateRequest -> (m (Maybe SessionStreamEvent) -> m a) -> Notion m a
```

and smart constructors

```haskell
-- | See 'Notion.V1.Methods'.'Notion.V1.streamSession'. The handler runs in 'Eff',
-- so it may call other 'Notion' operations.
streamSession :: (Notion :> es) => SessionUpdateRequest -> (SessionStreamEvent -> Eff es ()) -> Eff es ()
streamSession req k = send (StreamSession req k)

-- | See 'Notion.V1.Methods'.'Notion.V1.withSessionStream'. Do not let the reader escape.
withSessionStream :: (Notion :> es) => SessionUpdateRequest -> (Eff es (Maybe SessionStreamEvent) -> Eff es a) -> Eff es a
withSessionStream req k = send (WithSessionStream req k)
```

Update the module header comment to note that these two differ from `Methods` only by `IO` becoming `Eff es` in callbacks. In `Interpreter.hs`, change `interpret $ \_ -> \case` to `interpret $ \env -> \case`, import `localSeqUnliftIO`, `localLiftUnliftIO` from `Effectful.Dispatch.Dynamic` and `UnliftStrategy (SeqUnlift)` from `Effectful`, and add:

```haskell
  -- Session streaming
  StreamSession req k -> do
    result <- localSeqUnliftIO env $ \unlift ->
      Exception.try (Notion.streamSession methods req (unlift . k))
    either (\(ne :: NotionError) -> throwError ne) pure result
  WithSessionStream req k -> do
    result <- localLiftUnliftIO env SeqUnlift $ \liftToLocal unlift ->
      Exception.try (Notion.withSessionStream methods req (\next -> unlift (k (liftToLocal next))))
    either (\(ne :: NotionError) -> throwError ne) pure result
```

(If EP-2 renamed the error type caught by `runIO`, use that type.) The exact type of `localSeqUnliftIO`/`localLiftUnliftIO` differs slightly between `effectful-core` 2.5 and 2.7 (older versions carry an extra `handlerEs` type parameter on `LocalEnv`); the call sites above are the same in both. Add `StreamSession, WithSessionStream` to the constructor import list and the two smart constructors to the export list of `notion-client-effectful/src/Notion/V1/Effectful.hs`.

In `notion-client-example/SessionStreamDemo.hs`, write `runSessionStreamDemo :: Methods -> Text -> IO ()` that prints a header with `printHeader`, builds EP-2's new-turn request with `agent_id` from the argument and message from `NOTION_AGENT_PROMPT` or `"Reply with one short sentence."`, calls `streamSession`, and prints one line per event with `hFlush stdout` after each: `[snapshot] <session id> <status>`, `[provisional] agent.message: <text>` or `[provisional] tool: <name>`, `[committed #<sequence>] <event type>`, `[timeout] <message>`, `[end] <status> last_sequence=<n>`, `[error] <code>: <message> (retryable=<bool>)`, `[unknown] <name>`. Catch EP-2's error type around the call and print it instead of exiting, since this surface is unpublished and may answer 403/404. In `notion-client-example/Main.hs` add `agentIdEnv <- Environment.lookupEnv "NOTION_AGENT_ID"` and, after the optional database block, `case agentIdEnv of Just a -> runSessionStreamDemo methods (Text.pack a); Nothing -> putStrLn "Skipping session stream demo (set NOTION_AGENT_ID to enable)"`; add `SessionStreamDemo` to the executable's `other-modules` and mention the variable in the header comment.

In `CHANGELOG.md`, under `## Unreleased` at the top (create it if absent), add under `### New Features`: "Stream session updates over Server-Sent Events with `streamSession` and `withSessionStream` (`POST /v1/sessions` with `Accept: text/event-stream`); typed `SessionStreamEvent` in `Notion.V1.Sessions.Stream`; pure SSE parser in `Notion.V1.Sessions.Sse`. Retries and the timeout apply only before the stream opens." Under `### Breaking Changes`: "`Methods` gains fields `streamSession` and `withSessionStream`; code constructing `Methods` with a record literal must supply them." In `notion-client-effectful/CHANGELOG.md` under its own `## Unreleased`: new `StreamSession`/`WithSessionStream` operations (breaking for exhaustive custom interpreters of `Notion`). Do not bump versions.

Acceptance: `cabal build all` succeeds, all tests pass, and the demo runs as described in Validation and Acceptance.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client` unless stated.

Pre-flight drift check:

```bash
git -C /Users/shinzui/Keikaku/hub/notion-sdk-js pull
git -C /Users/shinzui/Keikaku/hub/notion-sdk-js log --oneline -- src/api-endpoints/agents.ts src/Client.ts | head
sed -n 14,352p /Users/shinzui/Keikaku/hub/notion-sdk-js/src/api-endpoints/agents.ts
sed -n 1120,1215p /Users/shinzui/Keikaku/hub/notion-sdk-js/src/Client.ts
```

Compare with the transcriptions in Context and Orientation (the last reviewed JS commit was `978d690`).

Precondition greps (expect at least one hit per line; if a name differs, adapt and record it):

```bash
grep -n "data SessionUpdateRequest\|data SessionEvent\|data SessionStatus\|data SessionError\|data Session " src/Notion/V1/Sessions.hs
grep -n "instance ToJSON SessionUpdateRequest" src/Notion/V1/Sessions.hs
grep -rn "APIErrorCode\|RateLimited\|ServiceOverload" src/Notion/V1/Error.hs
grep -rn "retry\|Retry" src/Notion/V1.hs src/Notion/V1/*.hs | head -20
grep -rn "timeout\|Timeout\|notionVersion\|baseUrl" src/Notion/V1.hs | head -20
```

Milestone 1:

```bash
cabal build all
cabal test --test-show-details=direct --test-options='-p "Session streaming"'
```

Expected excerpt:

```text
Notion Client Tests
  Session streaming
    SSE parser
      two frames in one chunk:                    OK
      CRLF equals LF:                             OK
      every single chunk split:                   OK
      every pair of chunk splits:                 OK
      ...
    Transport prototype
      prototype: frames arrive before the response ends: OK
      prototype: responseTimeout covers opening only:    OK
      prototype: closing early disconnects:              OK
```

If cabal cannot resolve `warp`, run `cabal update` first; warp 3.4.x, wai 3.2.x and http-types 0.12.x are the expected versions.

Milestones 2 and 3: the same test command; expect the "Stream events" and "Transport" subgroups to report `OK` and a final `All N tests passed`.

Milestone 4:

```bash
cabal build all
cabal test
NOTION_TOKEN=secret_xxx NOTION_AGENT_ID=<agent uuid or notion_ai> cabal run notion-client-example
```

Commit after each milestone (the pre-commit `treefmt` hook may reformat; re-add and commit again). Example message:

```text
feat(sessions): add SSE frame parser and transport prototype

Pure incremental SSE parser mirroring the JS SDK takeSseFrames/parseSseFrame,
with exhaustive chunk-boundary tests and warp-backed prototype tests for
http-client incremental delivery, open-only timeout and early close.

MasterPlan: docs/masterplans/2-add-the-custom-agents-and-sessions-api-with-sse-streaming.md
ExecPlan: docs/plans/14-stream-session-updates-over-server-sent-events.md
```

Milestone 4 must change `Methods` and `notion-client-effectful` in the same commit (the effectful lockstep rule).


## Validation and Acceptance

Automated: `cabal build all` compiles both packages and the example with no new warnings. `cabal test` passes, including the "Session streaming" group. The behaviours that prove the feature, beyond compilation:

- Parser: feeding the fixture stream split at any byte position, or in one-byte chunks, yields exactly the same frames as one chunk; comments, `id`/`retry` lines and colon-less lines are ignored; data without `event` fails.
- Incremental delivery: the "delivers events as frames arrive" test would deadlock (and fail by timeout) if events were only delivered after the response ended.
- Retry rule: a 429 first response leads to exactly 2 requests and the events of the second; a 500 leads to exactly 1 request and a thrown typed error; a decode error after opening leads to exactly 1 request.
- Timeout rule: a server slow to send headers fails with a timeout; a server idle for longer than the timeout between frames does not.
- Resource safety: returning early from `withSessionStream`, or throwing from the `streamSession` handler, disconnects the server within 2 s.
- Tolerance: an unknown event name with a matching `type` decodes to `UnknownStreamEvent`.

Live (optional, needs a workspace with custom agents): with `NOTION_TOKEN` and `NOTION_AGENT_ID` set, `cabal run notion-client-example` prints, after the other demos, something like:

```text
=== Session Stream ===

[snapshot] 5c0e...-... in_progress
[committed #1] user.message
[provisional] agent.message: Hello
[provisional] agent.message: Hello! How can I help?
[committed #2] agent.message
[committed #3] session.status
[end] completed last_sequence=3
```

Lines should appear progressively, not all at once. If the workspace lacks access, a single `[error]`-style line with the Notion error code is printed and the program continues.

A GHCi check is also possible: `cabal repl notion-client`, then build `Methods` with `getClientEnv "https://api.notion.com/v1"` and `makeMethods`, and call `streamSession methods <new-turn request> print`.


## Idempotence and Recovery

All steps are additive: new modules, new record fields, new tests, new dependencies. Re-running `cabal build all` and `cabal test` is safe. The warp tests bind random free ports through `testWithApplication`, so they can run repeatedly and in parallel with other suites. If a prototype test hangs, every such test is wrapped in `System.Timeout.timeout`, so it fails instead of blocking; if one still hangs (for example a missing `timeout` wrapper), interrupt with Ctrl-C and add the wrapper. If Milestone 1's prototype fails, revert only the prototype code (keep the parser) and re-plan the transport in the Decision Log. If EP-2 or EP-2-of-MP1 names change after this plan's code lands, only `src/Notion/V1.hs` wiring and imports need updating, because the transport receives its policy through `StreamEnv`. The live demo sends a real message to a real agent and consumes agent credits; it creates a new session each run, which is harmless but not free, so run it sparingly.


## Interfaces and Dependencies

Libraries: `http-client` (0.7.x; `Network.HTTP.Client`: `Manager`, `Request`, `parseRequest`, `responseOpen`, `responseClose`, `brRead`, `brConsume`, `RequestBody (RequestBodyLBS)`, `ResponseTimeout`, `responseTimeoutMicro`, `responseTimeoutDefault`, `HttpException`), `http-types` (0.12.x; `Network.HTTP.Types`: `Header`, `statusIsSuccessful`), `aeson` (existing), `bytestring` (existing), `servant-client` (existing; `BaseUrl`, `showBaseUrl`, `ClientEnv (manager, baseUrl)`). Test-only: `warp` (`Network.Wai.Handler.Warp.testWithApplication`), `wai` (`responseStream`, `strictRequestBody`, `requestHeaders`, `rawPathInfo`, `requestMethod`), `http-types`. Effectful: `effectful-core` (`Effectful.Dispatch.Dynamic.localSeqUnliftIO`, `localLiftUnliftIO`, `Effectful.UnliftStrategy (SeqUnlift)`).

Consumed from `docs/plans/13-add-session-endpoints-and-session-event-types.md` (`Notion.V1.Sessions`): `SessionUpdateRequest` with `ToJSON`; `Session`, `SessionEvent`, `SessionStatus`, `SessionError` with `FromJSON`.

Consumed from `docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md`: client configuration (base URL, version, timeout, retry settings), a retry wrapper usable on an arbitrary `IO` action for method POST, and typed error construction from a raw response.

At the end of Milestone 1, `Notion.V1.Sessions.Sse` exports:

```haskell
data SseFrame = SseFrame {eventName :: Text, eventData :: StrictByteString}
newtype SseParseError = SseMissingEventName StrictByteString
data SseBuffer
emptySseBuffer :: SseBuffer
feedSse :: SseBuffer -> StrictByteString -> Either SseParseError ([SseFrame], SseBuffer)
finishSse :: SseBuffer -> Either SseParseError [SseFrame]
parseSseFrame :: StrictByteString -> Either SseParseError (Maybe SseFrame)
```

At the end of Milestone 2, `Notion.V1.Sessions.Stream` exports `SessionStreamEvent (..)`, `ProvisionalEvent (..)`, `ProvisionalContent (..)`, `StreamTimeoutInfo (..)`, `StreamEndInfo (..)`, `StreamErrorInfo (..)`, `SessionStreamException (..)` and:

```haskell
decodeSessionStreamEvent :: SseFrame -> Either SessionStreamException SessionStreamEvent
```

At the end of Milestone 3 it additionally exports:

```haskell
data StreamEnv = StreamEnv {..}  -- fields as defined in Milestone 3
withSessionStreamIO :: StreamEnv -> SessionUpdateRequest -> (IO (Maybe SessionStreamEvent) -> IO a) -> IO a
streamSessionIO :: StreamEnv -> SessionUpdateRequest -> (SessionStreamEvent -> IO ()) -> IO ()
```

At the end of Milestone 4, `Notion.V1.Methods` has:

```haskell
streamSession :: SessionUpdateRequest -> (SessionStreamEvent -> IO ()) -> IO ()
withSessionStream :: forall a. SessionUpdateRequest -> (IO (Maybe SessionStreamEvent) -> IO a) -> IO a
```

and `Notion.V1.Effectful` exports:

```haskell
streamSession :: (Notion :> es) => SessionUpdateRequest -> (SessionStreamEvent -> Eff es ()) -> Eff es ()
withSessionStream :: (Notion :> es) => SessionUpdateRequest -> (Eff es (Maybe SessionStreamEvent) -> Eff es a) -> Eff es a
```
