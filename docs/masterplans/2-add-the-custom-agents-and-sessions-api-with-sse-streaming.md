---
id: 2
slug: add-the-custom-agents-and-sessions-api-with-sse-streaming
title: "Add the Custom Agents and Sessions API with SSE Streaming"
kind: master-plan
created_at: 2026-09-14T18:46:33Z
provenance:
  created_by:
    model: "claude-opus-5"
    harness: "claude-code"
    at: 2026-09-14T18:46:33Z
---

# Add the Custom Agents and Sessions API with SSE Streaming

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Vision & Scope

Notion now lets a workspace define "custom agents": AI agents configured inside Notion, with instructions, connections to tools and triggers. Each conversation an agent runs is a "session", a sequence of numbered events such as user messages, agent messages, tool calls and status changes. Notion's official TypeScript SDK (`@notionhq/client` v5.26.0, checked out at `/Users/shinzui/Keikaku/hub/notion-sdk-js`) added a REST surface for these in August 2026.

That surface has three parts:

- **Agent management.** Query, retrieve and delete agents; read usage insights; enable or disable an agent; set a credit limit; batch those operations.
- **Session control.** Start or continue a session by sending a message, approve a pending action, resume, cancel, and query sessions and their events.
- **A streaming variant of "send a message".** It answers with Server-Sent Events (SSE): a long-lived HTTP response in which the server writes a series of `event: <name>` / `data: <json>` text frames as the agent works.

The Haskell library `notion-client` (repository root `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`) has none of this. After this initiative, a Haskell program can:

- List and inspect a workspace's agents, change their status and credit limits, and batch-update them, polling the resulting async task.
- Start a session with an agent, send follow-up messages, approve required actions, cancel it, and page through its sessions and events.
- Consume a session turn as a live stream of typed Haskell events. The stream ends with `stream.end`, or surfaces `stream.error`/`stream.timeout` as values.

Each capability is proven by unit tests that decode JSON fixtures transcribed from the JS SDK types. It is also shown with a small demo in `notion-client-example`, when a token for a workspace with custom agents is available.

**In scope.** The 13 routes the JS SDK exposes on its public `Client` facade:

- `agents.query`, `agents.retrieve`, `agents.delete`, `agents.retrieveInsights`, `agents.updateStatus`, `agents.updateCreditLimit`, `agents.batch`
- `sessions.retrieve`, `sessions.update`, `sessions.stream`, `sessions.cancel`, `sessions.query`, `sessions.queryEvents`

**Explicitly excluded.** Routes defined in `src/api-endpoints/agents.ts` but deliberately not exposed on the JS `Client`:

- `listAgents` (JS #769 calls the agent-list endpoint "still-unimplemented")
- `chatWithAgent`, `listThreads`, `queryThreads`, `continueThread`, `listThreadMessages`, `sendThreadMessage`, `queryThreadMessages`
- every `external_agent_stub/*` route, which are test stubs by name and comment

These can be added by a later update to this MasterPlan if Notion publishes them.

**Stability warning.** The JS SDK commits that introduced this surface (#768, #769, #770, #786, #787, dated 2026-08-14 to 2026-08-31) describe it as "unpublished" routes. Its compatibility checker has already rejected one field removal (#773, removing `stream.end.last_sequence`), and another removal is pending (#772, removing tool-call fields). Before starting any child plan, the implementer must re-diff `src/api-endpoints/agents.ts` in the JS SDK checkout against the shapes recorded in the child plan:

```bash
git -C /Users/shinzui/Keikaku/hub/notion-sdk-js pull
git -C /Users/shinzui/Keikaku/hub/notion-sdk-js log --oneline -- src/api-endpoints/agents.ts src/Client.ts
```

Record any drift in that plan's Surprises & Discoveries. Every closed enum in this surface must decode unknown values into a fallback constructor rather than failing.


## Decomposition Strategy

The surface splits cleanly along the JS SDK facade:

- **EP-1: agent management** (`agents.*`).
- **EP-2: session request/response endpoints and the session-event type family** (`sessions.*` except `stream`).
- **EP-3: the SSE transport and `sessions.stream`.**

Streaming is separate from the other session endpoints because it is the only part of the whole Haskell library that is not a request followed by a single JSON response. It needs a different Servant combinator or a hand-written `http-client` loop, a frame parser, and a different retry rule: retry only before the stream opens. It carries real technical risk and deserves a prototype milestone of its own. It also cannot exist without the event types, which EP-2 defines, so it follows EP-2.

Agent management and sessions share only small types: the `agent_id` format (a UUID, `"notion_ai"`, or a reserved legacy UUID), `created_by` references, and the `models` selection (`auto`/`pinned`). Otherwise they are independent. Keeping them separate lets them be built in parallel.

Alternatives considered:

- **One ExecPlan for everything.** Rejected: 13 endpoints, 60–80 object shapes and a new transport exceed a single plan's reasonable size.
- **Folding this into `docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md`.** Rejected because of the instability described above. The Decision Log of that MasterPlan records the same decision.
- **A fourth plan for threads.** Rejected for now, because the JS SDK does not expose threads.

ADR context: this repository has no `docs/adr/` directory, and a Mori concept search found no ADR relevant to Notion agents or SSE clients. No relevant ADR exists.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 1 | Add Custom Agent Management Endpoints | docs/plans/12-add-custom-agent-management-endpoints.md | MP1 EP-3 | MP1 EP-2 | Not Started |
| 2 | Add Session Endpoints and Session Event Types | docs/plans/13-add-session-endpoints-and-session-event-types.md | None | MP1 EP-2, EP-1 | Not Started |
| 3 | Stream Session Updates over Server-Sent Events | docs/plans/14-stream-session-updates-over-server-sent-events.md | EP-2, MP1 EP-2 | None | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-1, EP-3). "MP1 EP-n" means child EP-n of `docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md`:

- MP1 EP-2 is `docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md`.
- MP1 EP-3 is `docs/plans/8-add-comment-mutation-async-task-and-meeting-notes-endpoints.md`.


## Dependency Graph

**EP-1 (agents) hard-depends on MP1 EP-3.** `POST agents/batch` returns an `async_task` object, and the caller polls it with `GET async_tasks/{task_id}`. MP1 EP-3 defines the `AsyncTask` type in `src/Notion/V1/AsyncTasks.hs` and the `retrieveAsyncTask` method. EP-1 reuses both rather than defining a second copy. EP-1's other six endpoints do not need MP1 EP-3. If MP1 EP-3 is late, EP-1 may implement those six first and leave batch as its final milestone.

**EP-1 soft-depends on MP1 EP-2** for the typed `APIErrorCode`, which is used in examples and error handling.

**EP-2 (sessions) has no hard dependencies.** It soft-depends on MP1 EP-2 for typed errors and on EP-1 for shared small types. If EP-2 starts first, it defines the shared types (see Integration Points), and EP-1 reuses them.

**EP-3 (streaming) hard-depends on EP-2 and on MP1 EP-2.**
- It needs EP-2's `SessionUpdateRequest` (the request body is identical to `sessions.update`) and EP-2's committed-event types, which are nested inside stream events.
- It needs MP1 EP-2's configurable runtime. The stream request must reuse MP1 EP-2's retry policy for the pre-open phase (429 and 529 only, since the request is a POST), its timeout setting, its `Notion-Version` configuration and its typed error construction. Duplicating that logic would be a correctness risk.

Order: MP1 EP-2 and MP1 EP-3 (from the other MasterPlan), with EP-2 able to start at any time; then EP-1 ∥ EP-2; then EP-3.


## Integration Points

**Shared agent and session primitives.** The new module `src/Notion/V1/Agents/Common.hs` holds:

- `AgentId`: a UUID, the literal `notion_ai`, or the legacy reserved UUID `33333333-3333-3333-3333-333333333333`, rendered as text.
- `ModelSelection` (`ModelAuto | ModelPinned (Vector (Maybe Text)) | UnknownModelSelection Value`). There are two wire shapes: agents send `{mode: "auto" | "pinned", id}`, while sessions send `{type: "auto" | "pinned", ids: [...]}`. The single shared decoder accepts both.
- `CreatedByRef`: `{id, type: "user" | "bot"}` with `CreatedByType` and an unknown fallback. Agent responses use three slightly different `created_by` shapes (see `docs/plans/12-add-custom-agent-management-endpoints.md`); agent-specific variants live in `Notion.V1.Agents`, not in the shared module.
- `AgentVersionRef`: `{id, number, published_at}`.
- The `"hidden"`-or-value wrapper `Hideable a`, used by agent fields such as `last_run_time` and `credit_limit`.

Both child plans transcribe the identical definition. Whichever of EP-1 and EP-2 starts first creates this module, and the other imports it. Neither redefines these types. Helpers specific to one plan stay in that plan's own module.

**`AsyncTask`.** Owned by MP1 EP-3 (`src/Notion/V1/AsyncTasks.hs`). EP-1 consumes it for `agents.batch`.

**Error types and runtime.** Owned by MP1 EP-2 (`src/Notion/V1/Error.hs`, the configurable client in `src/Notion/V1.hs`). EP-3 uses its exported non-Servant interfaces: `ClientConfig`, `RequestContext`, `standardHeaders`, `responseTimeoutFor`, `withRetries :: ClientConfig -> Method -> Text -> IO a -> IO a` and `notionErrorFromResponse`.
- EP-3's stream function must go through the same configuration record, so that base URL, version, auth, timeout and retries behave identically.
- The session error object `{code, message, retryable}` inside session payloads is not the HTTP error envelope. EP-2 defines it separately as `SessionError`.

**Session event types.** Owned by EP-2 in `src/Notion/V1/Sessions.hs`:

- `SessionEvent`, the committed events: `user.message`, `agent.message`, `agent.tool_use`, `agent.tool_result`, `session.status`, and, for queried events, `agent.thinking`.
- `SessionStatus`.
- `RequiredAction`.
- `SessionUpdateRequest`, a three-way union: new turn, approval, resume.

EP-3 consumes these. It defines only the stream envelope `SessionStreamEvent`: `session.snapshot`, `event.provisional`, `event.committed`, `stream.timeout`, `stream.end` and `stream.error`, plus the provisional event subset.

**`Methods`, `API` and `notion-client-effectful`.**
- EP-1 and EP-2 add JSON endpoints to `Methods`, and must add matching constructors, smart constructors and interpreter cases in `notion-client-effectful/src/Notion/V1/Effectful/Effect.hs` and `Interpreter.hs`.
- EP-3 adds two non-Servant `Methods` fields: `streamSession`, which pushes each event to a callback, and `withSessionStream`, which hands the continuation a bracketed pull reader. It mirrors both in the effectful package as higher-order effect operations.

**Tests and CHANGELOG.** Follow the convention set by MP1:
- Each plan adds `tasty/<Area>Tests.hs` exporting `tests :: TestTree`, registered in `notion-client.cabal` and `tasty/Main.hs`, with fixtures using made-up Japanese names.
- Each plan adds entries under `## Unreleased` in `CHANGELOG.md`.

**ADR candidates.**
- The exclusion of unexposed thread and external-stub routes.
- The SSE transport choice and its "no retry after open" rule.
- The tolerant decoding rule for fast-moving enums.


## Progress

- [ ] Pre-flight: re-diff the JS SDK `agents.ts` against the shapes recorded in each child plan
- [ ] EP-1: Agent types and query, retrieve, delete
- [ ] EP-1: Insights, status and credit-limit updates
- [ ] EP-1: Batch operations returning an async task
- [ ] EP-2: Session, status and event types
- [ ] EP-2: Session retrieve, update, cancel
- [ ] EP-2: Session and session-event queries
- [ ] EP-3: SSE transport prototype and frame parser
- [ ] EP-3: `streamSession` with typed stream events and pre-open retries
- [ ] Release: CHANGELOG, demo, ADRs


## Surprises & Discoveries

- Drafting on 2026-09-14 found that "model selection" has two different wire shapes, `{mode, id}` on agents and `{type, ids}` on sessions. It is reconciled into one tolerant shared type.
- Queried session events differ from streamed committed events. Queried `agent.message` can carry file content, queried `session.status` allows only five statuses and has no `usage`/`artifacts`, and file parts carry resolved file metadata instead of `file_id`. EP-2 models both.


## Decision Log

- Decision: Scope this MasterPlan to the 13 routes exposed on the JS SDK `Client` facade, and exclude threads, chat, the agent list and external agent stubs.
  Rationale: The JS SDK itself withholds those routes from its public facade. One is described as unimplemented (#769), and the stubs are named and commented as stubs. Binding them in Haskell would promise an API Notion has not published.
  Date: 2026-09-14

- Decision: Separate SSE streaming into its own plan with a prototype milestone.
  Rationale: It is the only non-request/response interaction in the library and needs a new transport and a frame parser. Its retry semantics are also different: retry before open, never after.
  Date: 2026-09-14

- Decision: Require a re-diff against the JS SDK before each child plan starts, and tolerant decoding for all enums.
  Rationale: The surface changed weekly during August 2026, with fields added, removed and widened.
  Date: 2026-09-14


- Decision: The SSE transport uses `http-client` directly (`responseOpen`/`brRead` inside `bracket`), not Servant's streaming client.
  Rationale: This reflects EP-3's Decision Log. Servant streaming runs in a different `ClientM` with its own framing, which does not match the JS SDK's frame rules. Raw `http-client` gives exact control over pre-open retries and closing the connection on early exit.
  Date: 2026-09-14


## Outcomes & Retrospective

(To be filled during and after implementation.)
