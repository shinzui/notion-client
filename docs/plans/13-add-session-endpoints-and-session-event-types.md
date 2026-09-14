---
id: 13
slug: add-session-endpoints-and-session-event-types
title: "Add Session Endpoints and Session Event Types"
kind: exec-plan
created_at: 2026-09-14T18:46:51Z
master_plan: "docs/masterplans/2-add-the-custom-agents-and-sessions-api-with-sse-streaming.md"
provenance:
  created_by:
    model: "claude-opus-5"
    harness: "claude-code"
    at: 2026-09-14T18:46:51Z
---

# Add Session Endpoints and Session Event Types

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Notion workspaces can define "custom agents": AI agents configured inside Notion. Each conversation an agent runs is a "session". A session is a numbered sequence of "session events": a user message, an agent reply, a tool call and its result, the agent's reasoning ("thinking"), and status changes such as "requires action" or "completed". Notion's official TypeScript SDK exposes REST endpoints to drive sessions. The Haskell library `notion-client` has none of them.

After this plan, a Haskell program holding a Notion token can:

- start a session with an agent by sending a message, or continue an existing one;
- approve or reject an action the agent is waiting on, or resume a stopped session;
- cancel a running turn;
- read one session, page through all sessions, and page through one session's events, all as typed Haskell values.

Unknown statuses, event kinds and content kinds decode into fallback constructors instead of failing, because Notion is still changing this API.

To see it working, run `cabal test` and watch the new `Sessions` test group pass. With `NOTION_TOKEN` and `NOTION_AGENT_ID` set, run `cabal run notion-client-example`: its new "Sessions API" section sends a message to the agent, polls until the session settles, and prints each event's kind.

This plan also creates the typed building blocks that `docs/plans/14-stream-session-updates-over-server-sent-events.md` needs for streaming.


## Progress

- [ ] Milestone 1: Pre-flight re-diff of the JS SDK `src/api-endpoints/agents.ts` against the shapes in this plan; drift recorded in Surprises & Discoveries.
- [ ] Milestone 1: `src/Notion/V1/Agents/Common.hs` exists (created here, or already created by `docs/plans/12-add-custom-agent-management-endpoints.md`) and is registered in `notion-client.cabal`.
- [ ] Milestone 1: Response types in `src/Notion/V1/Sessions.hs` (`Session`, `SessionStatus`, `RequiredAction`, `SessionError`, `SessionEvent`, `SessionEventPayload` and friends), each with `FromJSON`.
- [ ] Milestone 1: `SessionUpdateRequest` and `CancelSessionRequest` with `ToJSON`.
- [ ] Milestone 1: `tasty/SessionsTests.hs` with decoding and encoding tests, registered in `notion-client.cabal` and `tasty/Main.hs`; `cabal test` passes.
- [ ] Milestone 2: Servant routes, `Methods` fields and `makeMethods` wiring for `retrieveSession`, `updateSession`, `cancelSession`.
- [ ] Milestone 2: Matching constructors, smart constructors and interpreter cases in `notion-client-effectful`.
- [ ] Milestone 2: Request-capture tests proving method, path and body for the three endpoints; `cabal build all` and `cabal test` pass.
- [ ] Milestone 3: Filter and sort types, `QuerySessionsRequest`, `QuerySessionEventsRequest`, routes, `Methods` fields and effectful lockstep for `querySessions` and `querySessionEvents`.
- [ ] Milestone 3: Filter-encoding, list-decoding and request-capture tests; `cabal build all` and `cabal test` pass.
- [ ] Milestone 3: `notion-client-example/SessionDemo.hs` gated on `NOTION_AGENT_ID`; CHANGELOG entries under `## Unreleased`.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Use one `Session` record for every endpoint's session. The fields that only `sessions.retrieve` and `sessions.query` return are `Maybe`.
  Rationale: The JS SDK types the update and cancel responses (and the stream's `session.snapshot`) as a base shape, and retrieve and query as that base plus about eleven extra fields. Two nearly identical Haskell records would force callers to convert between them. `Maybe` fields also cope with Notion adding or dropping these optional fields.
  Date: 2026-09-14

- Decision: Split a session event into a `SessionEvent` envelope and a `SessionEventPayload` sum type. The envelope holds `id`, `session_id`, `sequence` and `created_at`; the payload is the variant chosen by `type`. The payload parser is exported on its own.
  Rationale: Committed events (stream) and queried events carry the same envelope but slightly different payloads. Provisional stream events, which `docs/plans/14-stream-session-updates-over-server-sent-events.md` handles, have no `sequence`. A separately exported payload parser lets that plan reuse the variants without duplicating them.
  Date: 2026-09-14

- Decision: A single payload type covers both the stream ("committed") and query shapes, using `Maybe` for fields only one of them has. Specifically:
  - `created_by` exists only on queried user and agent messages.
  - `usage` and `artifacts` exist only on committed `session.status` events.
  - Event content can be text, a file reference `{file_id}` (stream) or a resolved file `{name, content_type, url, expiry_time}` (query).
  Rationale: The differences are small and additive. One type keeps pattern matches identical for streamed and queried events.
  Date: 2026-09-14

- Decision: Model the session and session-event `filter` bodies as typed recursive sum types, each with a raw `Value` escape-hatch constructor. Do not use a bare `Value` for the whole filter.
  Rationale: The filter vocabulary is small and closed. Sessions filter on `id`, `agent_id`, `status`, `created_at`/`updated_at`; events on `id`, `type`, `sequence`, `created_at`. The shapes are regular Notion-style property filters that typed constructors make easy to get right. The API is unstable, so the `...FilterRaw Value` constructor lets a caller send a shape Notion adds before this library catches up. The nesting-depth limits (two levels for sessions, three for events) are enforced by the server and only documented in Haddock; encoding them in types would add complexity for no safety gain, since the server rejects deeper filters with a 400 error anyway.
  Date: 2026-09-14

- Decision: Name the request records `CancelSessionRequest`, `QuerySessionsRequest` and `QuerySessionEventsRequest`, not `CancelSession`, `QuerySessions`, `QuerySessionEvents`.
  Rationale: `notion-client-effectful` names its effect constructors after `Methods` fields in PascalCase (`CancelSession`, `QuerySessions`, `QuerySessionEvents`). Different type names avoid confusing readers of `Effect.hs`, where both would appear in one signature.
  Date: 2026-09-14

- Decision: `ModelSelection` in `src/Notion/V1/Agents/Common.hs` decodes both wire forms: the agent form `{"mode": "auto"}` / `{"mode": "pinned", "id": string|null}` and the session form `{"type": "auto"}` / `{"type": "pinned", "ids": [string|null]}`. It uses the constructors `ModelAuto`, `ModelPinned (Vector (Maybe Text))` and `UnknownModelSelection Value`.
  Rationale: The MasterPlan assigns one shared `ModelSelection` type to that module. The JS SDK uses a different discriminator key (`mode` vs `type`) and a different payload (`id` vs `ids`) for agents (`agents.ts` line 740) and sessions (`agents.ts` line 4804). One tolerant decoder honours the single-owner rule. The type is only decoded from responses, never sent, so the lossy normalisation of `id` to a one-element vector does no harm.
  Date: 2026-09-14

- Decision: The example demo is gated on `NOTION_AGENT_ID` and sends exactly one short message.
  Rationale: Running an agent consumes workspace credits. A demo that fires without an explicit agent ID would surprise users.
  Date: 2026-09-14


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

**Repository and tooling.** The repository root is `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`, and every command below runs from there unless stated otherwise.

- Language and compiler: Haskell, GHC 9.12.2, `default-language: GHC2024`.
- Build tool: cabal. `cabal.project` lists two packages: the root package `notion-client` and `notion-client-effectful/`.
- Build and test: `cabal build all` builds everything; `cabal test` runs the `tasty` test suite.
- Formatting: a pre-commit hook runs `treefmt`. It may reformat files, in which case re-stage them and commit again.
- ADRs: this repository has no `docs/adr/` directory; no relevant ADR exists.

**How the library is organised.** Each Notion REST area has one module under `src/Notion/V1/`, for example `src/Notion/V1/Views.hs` or `src/Notion/V1/CustomEmojis.hs`. Each module defines:

- its request and response types;
- hand-written or generic `FromJSON`/`ToJSON` instances;
- a Servant `API` type describing the routes.

Servant is a Haskell library in which an HTTP API is written as a type. `servant-client` turns that type into client functions. For example, `src/Notion/V1/Views.hs` lines 162–182 declare `"views" :> (ReqBody '[JSON] CreateView :> Post '[JSON] ViewObject :<|> Capture "view_id" ViewID :> Get '[JSON] ViewObject :<|> ...)`. Here `:<|>` separates alternative routes, `Capture` is a path segment variable, and `ReqBody` is a JSON body.

**Wiring in `src/Notion/V1.hs`.** Three pieces work together:

- The top-level `type API` (bottom of the file) prefixes every module's `API` with the `Authorization` and `Notion-Version` headers and joins the modules with `:<|>`.
- `makeMethods` builds all client functions with `Client.hoistClient @API Proxy run (Client.client @API Proxy) authorization notionVersion`. It pattern-matches the resulting `:<|>` tree into local names in the same order as `API`, and returns `Methods {..}`.
- `data Methods` is a record with one `IO` function per endpoint. Users call, for example, `retrieveView methods viewId`.

`run` turns a Servant `ClientError` whose body is a Notion error into the `NotionError` exception from `src/Notion/V1/Error.hs`. Adding an endpoint therefore touches three places, all kept in the same order: the module's `API`, the `API` list in `src/Notion/V1.hs`, and the `makeMethods` pattern plus the `Methods` record. `docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md` may restructure `makeMethods`. If it has landed when you start, follow whatever per-module wiring pattern the file then uses.

**JSON conventions.** `src/Notion/Prelude.hs` re-exports `FromJSON`, `ToJSON`, `Value`, `Text`, `Vector`, `Map`, `Natural`, `POSIXTime`, `Generic` and the Servant combinators. It also defines:

- `aesonOptions`: generic JSON options that convert camelCase field names to snake_case (`createdAt` becomes `created_at`), strip one trailing underscore (`type_` becomes `type`, `in_` becomes `in`), and omit `Nothing` fields when encoding;
- `parseISO8601 :: Text -> Parser POSIXTime`, which parses Notion timestamps with a `Z` suffix or a `+00:00` offset, including fractional seconds.

Response types mostly use hand-written `FromJSON` instances: `parseJSON = \case Object o -> do ...; _ -> fail "..."`, with `(.:)` for required keys and `(.:?)` for optional keys. See `ViewObject` in `src/Notion/V1/Views.hs` lines 96–118. Modules enable `DuplicateRecordFields`, `OverloadedStrings`, `OverloadedLabels` and `RecordWildCards` globally (see `default-extensions` in `notion-client.cabal`). Modules with record fields named like Prelude functions import `Prelude hiding (id)`.

`DuplicateRecordFields` lets several record types share a field name. This plan relies on that heavily: `sessionId`, `agentId`, `status`, `title` and `pageSize` each appear in more than one type. Under GHC 9.12, though, a bare selector call such as `status s`, or a record update such as `r {sessionId = ...}`, is rejected as ambiguous when the name belongs to several types in scope. A record update is accepted only if its set of field names belongs to exactly one type. In tests and the demo, therefore:

- build values with full constructor syntax (`QuerySessionsRequest {query = ..., filter = ..., ...}`) or the helper functions this plan defines;
- read fields by pattern matching (`Session {status, title}`, using `NamedFieldPuns`, which GHC2024 enables) or with `RecordWildCards`.

`Notion.V1.Common` defines `newtype UUID = UUID {text :: Text}`, the ID type used everywhere. `src/Notion/V1/Filter.hs` lines 391–398 define `SortDirection = Ascending | Descending`, encoding to `"ascending"`/`"descending"`; this plan reuses it.

**Paginated lists.** `src/Notion/V1/ListOf.hs` defines `ListOf a` with fields `results`, `nextCursor`, `hasMore`, `type_`, `object`. Its `FromJSON` reads only those keys and ignores every other key. The session list responses carry an extra placeholder key, `"session": {}` or `"session_event": {}`, which `ListOf` therefore ignores. Milestone 3 has a test that proves it.

**The effectful companion package.** `notion-client-effectful/` wraps `Methods` as an `effectful` effect. `effectful` is a Haskell effect-system library: an "effect" is a GADT of operations, and an "interpreter" gives them meaning.

- `notion-client-effectful/src/Notion/V1/Effectful/Effect.hs` has one GADT constructor per `Methods` field, named in PascalCase with the same argument order (for example `ListCustomEmojis :: Maybe Text -> Maybe Text -> Maybe Natural -> Notion m (ListOf CustomEmoji)`). It also has one lower-case smart constructor per field (`listCustomEmojis ... = send (ListCustomEmojis ...)`) and an export list grouped by area.
- `notion-client-effectful/src/Notion/V1/Effectful/Interpreter.hs` imports the constructor names explicitly and has one `\case` branch per constructor, for example `ListCustomEmojis a b c -> runIO (Notion.listCustomEmojis methods a b c)`.

**Lockstep rule:** every `Methods` field added in this plan must get its constructor, smart constructor, export and interpreter branch in the same commit. Otherwise `cabal build all` fails with a non-exhaustive or missing-name error.

**Tests.** The test suite `tasty` is declared in `notion-client.cabal` (`test-suite tasty`, `hs-source-dirs: tasty`, `main-is: Main.hs`). It currently has no `other-modules` field. `tasty/Main.hs` assembles its top-level group near line 158:

```haskell
  pure $
    testGroup
      "Notion Client Tests"
      [ jsonParsingTests,
        jsonSerializationTests,
        propertyValueTests,
        fileUploadTests,
        basicIntegration,
        ...
      ]
```

This plan adds a new module `tasty/SessionsTests.hs` exporting `tests :: TestTree`. `Main.hs` defines its own `tests :: IO TestTree`, so import the new module qualified (`import SessionsTests qualified`) and add `SessionsTests.tests` to that list. The test suite already depends on `aeson`, `bytestring`, `http-client`, `servant-client`, `tasty`, `tasty-hunit`, `text`, `vector` and `containers`. Fixtures must never use real people's names; use made-up Japanese names such as "Tanaka Hanako" or "Sato Kenji".

**Example app.** `notion-client-example/Main.hs` reads `NOTION_TOKEN`, builds `methods` and calls demo modules such as `CustomEmojiDemo.runCustomEmojiDemo methods`. Those modules use `Console.printHeader` and `Console.runTest` from `notion-client-example/Console.hs`. Demo modules are listed in `other-modules` of `executable notion-client-example` in `notion-client.cabal`.

**The reference SDK.** Notion's official TypeScript SDK `@notionhq/client` v5.26.0 is checked out at `/Users/shinzui/Keikaku/hub/notion-sdk-js`. When this plan was written its HEAD was `978d690` (2026-09-04), and `src/api-endpoints/agents.ts` was last changed by `8eea864` (#787). The session shapes below were transcribed from these locations in `src/api-endpoints/agents.ts`:

- `UpdateSessionStreamResponse` (committed stream events): lines 51–333.
- `cancelSession`: lines 428–484.
- `querySessionEvents`: lines 3049–3881.
- `querySessions`: lines 3883–4399.
- `retrieveSession`: lines 4773–4845.
- `updateSession`: lines 5049–5122.

The facade test `test/Client.test.ts` lines 611–862 checks each endpoint's URL, method and body. The SDK's own commit messages call this surface "unpublished", and it changed weekly in August 2026. That is why Milestone 1 begins with a re-diff.

**Who owns what.** The parent MasterPlan is `docs/masterplans/2-add-the-custom-agents-and-sessions-api-with-sse-streaming.md`; this plan is its EP-2.

This plan owns `src/Notion/V1/Sessions.hs` and in it:

- `SessionEvent` (committed events, including `agent.thinking` from queried events);
- `SessionStatus`;
- `RequiredAction`;
- `SessionError` (the in-payload `{code, message, retryable}` object, which is not the HTTP error envelope `NotionError`);
- `SessionUpdateRequest`.

It shares `src/Notion/V1/Agents/Common.hs` with `docs/plans/12-add-custom-agent-management-endpoints.md`. Whichever plan starts first creates it with `AgentId`, `ModelSelection`, `CreatedByRef`, `AgentVersionRef` and `Hideable`; the other imports it and never redefines those types. `docs/plans/14-stream-session-updates-over-server-sent-events.md` consumes this plan's types and defines only the stream envelope. This plan has no hard dependencies. It does not use `AsyncTask` or the typed error codes from the other MasterPlan.

**Wire shapes this plan must match.** These are transcribed verbatim, with comments condensed, so you do not need to open the JS repository.

The session object. The update, cancel and stream-snapshot responses contain only the base fields. Retrieve and query results add the fields marked "retrieve/query only".

```typescript
type Session = {
  object: "session"
  id: string
  agent_id: string
  title: string
  status: "queued" | "in_progress" | "requires_action" | "completed" | "failed" | "canceled" | "terminated"
  created_at: string
  updated_at: string
  required_actions?: Array<{
    action_id: string
    title: string
    options: Array<{ id: "approve" | "reject"; label: string }>
  }>
  error?: { code: string; message: string; retryable: boolean }
  // retrieve/query only:
  created_by: { id: string; type: "user" | "bot" }
  agent_version: { id: string; number: number; published_at: string } | null
  models: { type: "auto" } | { type: "pinned"; ids: Array<string | null> }
  trigger_type?: string
  type_labels?: Array<string> | null
  chat_user_emails?: Array<string> | null
  tool_types?: Array<string> | null
  tool_call_count?: number | null
  credits_used?: number | null
  runs_completed?: number | null
  message_count?: number | null
}
```

The update request body (`POST sessions`). It is a three-way union with no discriminator field; the keys present decide which branch it is.

```typescript
type UpdateSessionBodyParameters =
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

The cancel request body (`POST sessions/{session_id}/cancel`). The SDK's comment on `event_id` says: "A session event identifying the turn to cancel. If omitted, cancels the current nonterminal turn."

```typescript
type CancelSessionBodyParameters = { event_id?: string }
```

Committed events, as found inside a stream's `event.committed`. Every variant also has `object: "session_event"`, `id: string`, `session_id: string`, `sequence: number` and `created_at: string`.

```typescript
  | { type: "user.message"; content: Array<{ type: "text"; text: string } | { type: "file"; file_id: string }>; metadata?: Record<string, string> }
  | { type: "agent.message"; content: Array<{ type: "text"; text: string }> }
  | { type: "agent.tool_use"; tool_name: string }
  | { type: "agent.tool_result"; tool_use_id: string; tool_name: string; is_error: boolean }
  | { type: "session.status"; status: /* the 7 statuses */; required_actions?: /* as above */; error?: /* as above */
      usage?: { total_tokens: number; input_tokens?: number; output_tokens?: number }
      artifacts?: Array<{ type: "page"; url: string; title: string } | { type: "html_artifact"; url: string; page_url: string }> }
```

Queried events, in the `results` of `POST sessions/{session_id}/events/query`. They have the same common fields. Their differences from committed events are:

- `agent.thinking` exists;
- messages carry `created_by` and a nullable `metadata`;
- file content is resolved to a download URL;
- `session.status` lists five statuses and has no `usage`/`artifacts`.

```typescript
  | { type: "user.message"
      content: Array<{ type: "text"; text: string } | { type: "file"; name: string; content_type: string; url: string; expiry_time?: string }>
      created_by: { id: string; type: "user" | "bot" } | null
      metadata: Record<string, string> | null }
  | { type: "agent.message"; content: /* same text | file union */; created_by: /* same */ | null; metadata: { model: string } | null }
  | { type: "agent.thinking"; content: Array<{ type: "text"; text: string }> }
  | { type: "agent.tool_use"; tool_name: string }
  | { type: "agent.tool_result"; tool_use_id: string; tool_name: string; is_error: boolean }
  | { type: "session.status"; status: "requires_action" | "completed" | "failed" | "canceled" | "terminated"
      required_actions?: /* as above */; error?: /* as above */ }
```

The query request bodies and list envelopes.

```typescript
type QuerySessionsBodyParameters = {
  query?: string            // case-insensitive substring search over titles
  filter?: SessionFilter    // nested up to two levels
  sorts?: Array<{ property: "created_at" | "updated_at"; direction: "ascending" | "descending" }> // default updated_at descending
  start_cursor?: string | null
  page_size?: number        // max 100
}
// SessionFilter leaf shapes, or { and: [...] } / { or: [...] } of them:
//   { property: "id"; string: { equals: string } }
//   { property: "agent_id"; string: { equals: string } }
//   { property: "status"; status: { equals?: Status; in?: Array<Status> } }
//   { property: "created_at" | "updated_at"; timestamp: { before?: string; after?: string; on_or_before?: string; on_or_after?: string } }

type QuerySessionEventsBodyParameters = {
  filter?: EventFilter      // nested up to three levels
  sorts?: Array<{ property: "sequence" | "created_at"; direction: "ascending" | "descending" }> // default sequence ascending
  start_cursor?: string | null
  page_size?: number        // max 100
}
// EventFilter leaf shapes, or { and: [...] } / { or: [...] } of them:
//   { property: "id"; string: { equals: string } }
//   { property: "type"; event_type: { equals?: EventType; in?: Array<EventType> } }
//     EventType = "user.message" | "agent.message" | "agent.thinking" | "agent.tool_use" | "agent.tool_result" | "session.status"
//   { property: "sequence"; number: { greater_than?: number; greater_than_or_equal_to?: number; less_than?: number; less_than_or_equal_to?: number } }
//   { property: "created_at"; timestamp: { equals?: string; before?: string; after?: string; on_or_before?: string; on_or_after?: string } }

type QuerySessionsResponse = { object: "list"; type: "session"; session: {}; results: Array<Session>; has_more: boolean; next_cursor: string | null }
type QuerySessionEventsResponse = { object: "list"; type: "session_event"; session_event: {}; results: Array<QueriedEvent>; has_more: boolean; next_cursor: string | null }
```

The routes: `GET sessions/{session_id}` returns a session; `POST sessions` takes the update body and returns a session; `POST sessions/{session_id}/cancel` takes the cancel body and returns a session; `POST sessions/query` and `POST sessions/{session_id}/events/query` take the query bodies and return the lists.


## Plan of Work

The work proceeds in three milestones. Each ends with a green `cabal build all` and `cabal test`.


### Milestone 1: pre-flight, shared primitives, and session types with decoding tests

At the end of this milestone the library exports `Notion.V1.Agents.Common` and `Notion.V1.Sessions`, containing every session response type and the two write-request types, and the test suite proves they decode fixtures copied from the SDK types. No endpoint is callable yet.

**Pre-flight.** Update the SDK checkout and list the commits since this plan was written (see Concrete Steps). If `src/api-endpoints/agents.ts` changed after `978d690`, diff the session types listed in Context and Orientation. For every field added, removed or re-typed, record an entry in Surprises & Discoveries and adjust the Haskell types in this plan before writing them.

**Shared primitives.** If `src/Notion/V1/Agents/Common.hs` does not exist, create it. If `docs/plans/12-add-custom-agent-management-endpoints.md` already created it, check that `ModelSelection` accepts both wire forms (see Decision Log) and extend its decoder if not. Add `Notion.V1.Agents.Common` to `exposed-modules` in `notion-client.cabal`. Its contents:

```haskell
-- | Small types shared by the custom-agent (@agents/*@) and session (@sessions/*@) endpoints.
module Notion.V1.Agents.Common
  ( AgentId (..),
    notionAiAgentId,
    ModelSelection (..),
    CreatedByRef (..),
    CreatedByType (..),
    AgentVersionRef (..),
    Hideable (..),
  )
where

import Data.Aeson ((.:), (.:?))
import Data.Aeson.Types (Parser)
import Notion.Prelude
import Notion.V1.Common (UUID)
import Prelude hiding (id)

-- | An agent identifier: a UUID, the literal @notion_ai@ (the personal Notion Agent),
-- or the legacy reserved UUID @33333333-3333-3333-3333-333333333333@.
newtype AgentId = AgentId {text :: Text}
  deriving newtype (Eq, Show, IsString, FromJSON, ToJSON, ToHttpApiData)

notionAiAgentId :: AgentId
notionAiAgentId = AgentId "notion_ai"

-- | Model selection. Agents send {"mode":"auto"} or {"mode":"pinned","id":...};
-- sessions send {"type":"auto"} or {"type":"pinned","ids":[...]}. Both decode here.
data ModelSelection
  = ModelAuto
  | ModelPinned (Vector (Maybe Text))
  | UnknownModelSelection Value
  deriving stock (Eq, Show, Generic)

data CreatedByType = CreatedByUser | CreatedByBot | UnknownCreatedByType Text
  deriving stock (Eq, Show, Generic)

data CreatedByRef = CreatedByRef {id :: UUID, type_ :: CreatedByType}
  deriving stock (Eq, Show, Generic)

data AgentVersionRef = AgentVersionRef {id :: UUID, number :: Natural, publishedAt :: POSIXTime}
  deriving stock (Eq, Show, Generic)

-- | A field Notion may replace with the string "hidden" when the caller lacks access.
data Hideable a = Hidden | Visible a
  deriving stock (Eq, Show, Generic)
```

Write the instances by hand:

- `ModelSelection`: in `parseJSON`, read the discriminator with `o .:? "mode"`, falling back to `o .:? "type"`. `"auto"` gives `ModelAuto`. For `"pinned"`, read `ids` if present (`o .:? "ids"`), otherwise wrap the nullable `id` in a one-element vector. Any other discriminator, or a non-object, gives `UnknownModelSelection` carrying the whole value.
- `CreatedByType`: map `"user"` and `"bot"`, and put any other string in `UnknownCreatedByType`. Give it a `ToJSON` that inverts this mapping.
- `CreatedByRef`: read `id` and `type`.
- `AgentVersionRef`: read `published_at` through `parseISO8601`.
- `Hideable a`: `String "hidden"` gives `Hidden`; anything else gives `Visible <$> parseJSON v`.
- `ModelSelection` needs only `FromJSON`, because it is never sent. Sessions use `AgentId`, `ModelSelection`, `CreatedByRef` and `AgentVersionRef`; `Hideable` is used only by agent responses and exists so the shared module is complete for the sibling plan.

**Session response types.** Create `src/Notion/V1/Sessions.hs` and add `Notion.V1.Sessions` to `exposed-modules`. Start the module with `import Prelude hiding (error, id, sequence)`, because records use those field names. Define:

```haskell
type SessionID = UUID

data SessionStatus
  = SessionQueued
  | SessionInProgress
  | SessionRequiresAction
  | SessionCompleted
  | SessionFailed
  | SessionCanceled
  | SessionTerminated
  | UnknownSessionStatus Text
  deriving stock (Eq, Show, Generic)

-- | The approve/reject choice offered by a required action and sent back in an approval.
data ActionOptionId = ApproveOption | RejectOption | UnknownActionOption Text
  deriving stock (Eq, Show, Generic)

data RequiredActionOption = RequiredActionOption {id :: ActionOptionId, label :: Text}
  deriving stock (Eq, Show, Generic)

data RequiredAction = RequiredAction
  { actionId :: Text,
    title :: Text,
    options :: Vector RequiredActionOption
  }
  deriving stock (Eq, Show, Generic)

-- | The error object embedded in session payloads (not the HTTP error envelope).
data SessionError = SessionError {code :: Text, message :: Text, retryable :: Bool}
  deriving stock (Eq, Show, Generic)

data Session = Session
  { id :: SessionID,
    agentId :: AgentId,
    title :: Text,
    status :: SessionStatus,
    createdAt :: POSIXTime,
    updatedAt :: POSIXTime,
    requiredActions :: Maybe (Vector RequiredAction),
    error :: Maybe SessionError,
    -- Returned only by retrieveSession and querySessions:
    createdBy :: Maybe CreatedByRef,
    agentVersion :: Maybe AgentVersionRef,
    models :: Maybe ModelSelection,
    triggerType :: Maybe Text,
    typeLabels :: Maybe (Vector Text),
    chatUserEmails :: Maybe (Vector Text),
    toolTypes :: Maybe (Vector Text),
    toolCallCount :: Maybe Natural,
    creditsUsed :: Maybe Scientific,
    runsCompleted :: Maybe Natural,
    messageCount :: Maybe Natural
  }
  deriving stock (Eq, Show, Generic)
```

`Scientific` comes from `Data.Scientific`; the library already depends on `scientific`. `credits_used` is a JSON number that may be fractional, so it is not a `Natural`.

`SessionStatus` and `ActionOptionId` need both `FromJSON` and `ToJSON`, because status appears in filters and option IDs appear in approvals. Use `"queued"`, `"in_progress"`, `"requires_action"`, `"completed"`, `"failed"`, `"canceled"`, `"terminated"` and `"approve"`, `"reject"`; the `Unknown...` constructors round-trip their text.

`Session`'s `FromJSON` is hand-written. It uses `(.:)` for the seven base fields, `(.:?)` for everything else, and `parseISO8601` for the two timestamps. `(.:?)` maps both a missing key and JSON `null` to `Nothing`, which covers every `?: ... | null` field in the SDK.

**Session event types.**

```haskell
data SessionEvent = SessionEvent
  { id :: Text,
    sessionId :: SessionID,
    sequence :: Natural,
    createdAt :: POSIXTime,
    payload :: SessionEventPayload
  }
  deriving stock (Eq, Show, Generic)

data SessionEventPayload
  = UserMessage MessageEvent
  | AgentMessage MessageEvent
  | AgentThinking (Vector EventContent)
  | AgentToolUse ToolUseEvent
  | AgentToolResult ToolResultEvent
  | SessionStatusChanged StatusEvent
  | UnknownSessionEvent Text Value
  -- ^ the unrecognised @type@ string and the whole event object
  deriving stock (Eq, Show, Generic)

data MessageEvent = MessageEvent
  { content :: Vector EventContent,
    createdBy :: Maybe CreatedByRef,     -- queried events only
    metadata :: Maybe (Map Text Text)    -- user: arbitrary strings; agent (queried): {"model": ...}
  }
  deriving stock (Eq, Show, Generic)

data EventContent
  = TextContent Text
  | FileIdContent Text
  -- ^ stream form: {"type":"file","file_id":...}
  | FileContent ResolvedFile
  -- ^ query form: {"type":"file","name":...,"content_type":...,"url":...,"expiry_time"?:...}
  | UnknownEventContent Value
  deriving stock (Eq, Show, Generic)

data ResolvedFile = ResolvedFile
  { name :: Text,
    contentType :: Text,
    url :: Text,
    expiryTime :: Maybe POSIXTime
  }
  deriving stock (Eq, Show, Generic)

newtype ToolUseEvent = ToolUseEvent {toolName :: Text}
  deriving stock (Eq, Show, Generic)

data ToolResultEvent = ToolResultEvent {toolUseId :: Text, toolName :: Text, isError :: Bool}
  deriving stock (Eq, Show, Generic)

data StatusEvent = StatusEvent
  { status :: SessionStatus,
    requiredActions :: Maybe (Vector RequiredAction),
    error :: Maybe SessionError,
    usage :: Maybe SessionUsage,              -- committed (stream) events only
    artifacts :: Maybe (Vector SessionArtifact) -- committed (stream) events only
  }
  deriving stock (Eq, Show, Generic)

data SessionUsage = SessionUsage {totalTokens :: Natural, inputTokens :: Maybe Natural, outputTokens :: Maybe Natural}
  deriving stock (Eq, Show, Generic)

data SessionArtifact
  = PageArtifact {url :: Text, title :: Text}
  | HtmlArtifact {url :: Text, pageUrl :: Text}
  | UnknownArtifact Value
  deriving stock (Eq, Show, Generic)
```

Event `id`s are plain `Text`, not `UUID`: the SDK's stream test uses IDs such as `"tool-1:use"`.

Write the payload parser as a standalone exported function, `parseSessionEventPayload :: Object -> Parser SessionEventPayload`, so the streaming plan can reuse it on provisional events that lack `sequence`. It reads `type` and dispatches:

- `"user.message"` becomes `UserMessage`, and `"agent.message"` becomes `AgentMessage`. Both parse `MessageEvent` from `content`, optional `created_by` and optional `metadata`.
- `"agent.thinking"` becomes `AgentThinking` from `content`.
- `"agent.tool_use"` and `"agent.tool_result"` read their named fields.
- `"session.status"` reads `StatusEvent`.
- Any other string produces `UnknownSessionEvent t (Object o)`.

For `EventContent`, `type == "text"` gives `TextContent`. `type == "file"` gives `FileIdContent` if `file_id` is present, otherwise `FileContent`. Anything else gives `UnknownEventContent`. `SessionEvent`'s `FromJSON` reads `id`, `session_id`, `sequence` and `created_at`, then calls `parseSessionEventPayload o`.

Tolerance matters here. If a known `type` has a malformed body (for example, Notion removes a field this plan treats as required), the event must fail loudly rather than silently becoming `UnknownSessionEvent`. Loud failure surfaces contract drift; the unknown constructor is only for new `type` values.

**Write-request types.**

```haskell
data SessionUpdateRequest
  = NewTurn NewTurnRequest
  | ApproveActions ApprovalRequest
  | Resume ResumeRequest
  deriving stock (Eq, Show, Generic)

data NewTurnRequest = NewTurnRequest
  { message :: Text,
    agentId :: Maybe AgentId,
    sessionId :: Maybe SessionID,   -- set to continue an existing session
    attachments :: Maybe (Vector SessionAttachment),
    metadata :: Maybe (Map Text Text),
    promptContext :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)

-- | Encodes as {"type":"file_upload","file_upload":{"id":...},"name"?:...}
data SessionAttachment = SessionAttachment {fileUploadId :: UUID, name :: Maybe Text}
  deriving stock (Eq, Show, Generic)

data ApprovalRequest = ApprovalRequest
  { sessionId :: SessionID,
    actions :: Vector ActionApproval,
    metadata :: Maybe (Map Text Text)
  }
  deriving stock (Eq, Show, Generic)

data ActionApproval = ActionApproval {actionId :: Text, optionId :: ActionOptionId}
  deriving stock (Eq, Show, Generic)

-- | Resume a session from a point. The SDK does not document @continue_from@
-- beyond its type (a string); treat it as an opaque event reference.
data ResumeRequest = ResumeRequest {sessionId :: SessionID, continueFrom :: Text}
  deriving stock (Eq, Show, Generic)

newtype CancelSessionRequest = CancelSessionRequest {eventId :: Maybe Text}
  deriving stock (Eq, Show, Generic)

-- | A new-turn request with only a message, optional agent and optional session;
-- attachments, metadata and prompt context are Nothing.
newTurn :: Maybe AgentId -> Maybe SessionID -> Text -> SessionUpdateRequest
```

Encoding rules:

- `NewTurnRequest`, `ApprovalRequest`, `ResumeRequest`, `ActionApproval` and `CancelSessionRequest` use `genericToJSON aesonOptions`. `omitNothingFields` drops absent optional keys, so `CancelSessionRequest Nothing` encodes as `{}`.
- `SessionUpdateRequest`'s `ToJSON` is untagged: it encodes the inner record directly (`NewTurn r -> toJSON r`, and so on), because the wire union has no discriminator.
- `SessionAttachment` gets a hand-written `ToJSON` producing the nested `file_upload` object.

The module export list groups types under Haddock headings `-- * Sessions`, `-- * Events`, `-- * Requests` and `-- * Servant`. In this milestone `API` is not defined yet, so leave `API` out of the exports until Milestone 2.

**Tests.** Create `tasty/SessionsTests.hs` (`module SessionsTests (tests) where`, `tests :: TestTree`) with a `testGroup "Sessions"` containing the cases listed under Validation and Acceptance for Milestone 1. Decode fixtures with `Aeson.eitherDecode`, so a failure prints the aeson error. Add `other-modules: SessionsTests` to `test-suite tasty` in `notion-client.cabal`; if another plan already added the field, append to it. In `tasty/Main.hs`, add `import SessionsTests qualified` and put `SessionsTests.tests` in the top-level list.

**CHANGELOG.** At the top of `CHANGELOG.md`, directly under `# Changelog for notion-client`, make sure a `## Unreleased` heading exists; another plan may already have created it. Under its `### New Features` sub-heading, add: "Add `Notion.V1.Sessions` types for custom-agent sessions and session events, and `Notion.V1.Agents.Common` shared agent primitives (unknown statuses and event kinds decode into fallback constructors)". Do not bump the package version.


### Milestone 2: retrieve, update and cancel

At the end of this milestone `retrieveSession`, `updateSession` and `cancelSession` are callable from `Methods` and from the effectful package, and tests prove each sends the right HTTP method, path and body.

**Routes in `src/Notion/V1/Sessions.hs`.** Add the Servant API and export it. Milestone 3 extends it with two more alternatives.

```haskell
type API =
  "sessions"
    :> ( Capture "session_id" SessionID
           :> Get '[JSON] Session
           :<|> ReqBody '[JSON] SessionUpdateRequest
           :> Post '[JSON] Session
           :<|> Capture "session_id" SessionID
           :> "cancel"
           :> ReqBody '[JSON] CancelSessionRequest
           :> Post '[JSON] Session
       )
```

**`src/Notion/V1.hs`.** Make these changes:

- Import `Notion.V1.Sessions (Session, SessionID, SessionUpdateRequest)` and `Notion.V1.Sessions qualified as Sessions`.
- Append `:<|> Sessions.API` as the last alternative in `type API`.
- Append a matching last element `:<|> (retrieveSession :<|> updateSession :<|> cancelSession)` to the `makeMethods` pattern.
- Add to `data Methods`, after the File Uploads fields, a `-- \* Sessions` comment and:

```haskell
    -- | Retrieve one session, including usage fields (created_by, models, credits_used, ...).
    retrieveSession :: SessionID -> IO Session,
    -- | Start a session, send a follow-up message, approve required actions, or resume.
    updateSession :: SessionUpdateRequest -> IO Session,
    -- | Cancel the current (or the given) turn of a session.
    cancelSession :: SessionID -> Sessions.CancelSessionRequest -> IO Session,
```

**Effectful lockstep.** In `notion-client-effectful/src/Notion/V1/Effectful/Effect.hs`:

- Import `Notion.V1.Sessions (Session, SessionID, SessionUpdateRequest)` and `Notion.V1.Sessions qualified as Sessions`.
- Add a `-- * Sessions` export group with `retrieveSession`, `updateSession`, `cancelSession`.
- Add GADT constructors `RetrieveSession :: SessionID -> Notion m Session`, `UpdateSession :: SessionUpdateRequest -> Notion m Session` and `CancelSession :: SessionID -> Sessions.CancelSessionRequest -> Notion m Session`.
- Add smart constructors in the existing style, each with a `-- | See 'Notion.V1.Methods'.'Notion.V1.retrieveSession'.` Haddock line.

In `notion-client-effectful/src/Notion/V1/Effectful/Interpreter.hs`, add the three names to the explicit `Notion (...)` import list and add these branches:

```haskell
  RetrieveSession sid -> runIO (Notion.retrieveSession methods sid)
  UpdateSession req -> runIO (Notion.updateSession methods req)
  CancelSession sid req -> runIO (Notion.cancelSession methods sid req)
```

**Request-capture tests.** These tests prove the routes without a network. Build a `Methods` whose HTTP manager records the outgoing request and then aborts. `http-client`'s `managerModifyRequest` hook runs before any connection is opened. `servant-client` catches only `HttpException` (`servant-client/src/Servant/Client/Internal/HttpClient.hs`, `catchConnectionError`), so a custom exception thrown from the hook propagates out of the method call. In `tasty/SessionsTests.hs`:

```haskell
data Captured = Captured deriving stock (Show)
instance Exception Captured

-- | Run a Methods call against a manager that records the request and aborts.
captureRequest :: (Methods -> IO a) -> IO HTTP.Request
captureRequest call = do
  ref <- newIORef Nothing
  manager <-
    HTTP.newManager
      HTTP.defaultManagerSettings
        { HTTP.managerModifyRequest = \req -> writeIORef ref (Just req) >> throwIO Captured
        }
  baseUrl <- Client.parseBaseUrl "http://localhost/v1"
  let methods = makeMethods (Client.mkClientEnv manager baseUrl) "test-token"
  _ <- try @SomeException (call methods)
  readIORef ref >>= maybe (assertFailure "no request captured") pure

requestBodyValue :: HTTP.Request -> Maybe Aeson.Value
requestBodyValue req = case HTTP.requestBody req of
  HTTP.RequestBodyLBS b -> Aeson.decode b
  HTTP.RequestBodyBS b -> Aeson.decodeStrict b
  _ -> Nothing
```

The imports needed are `Network.HTTP.Client qualified as HTTP`, `Servant.Client qualified as Client`, `Control.Exception (Exception, SomeException, throwIO, try)` and `Data.IORef`; these packages are already test dependencies. If `docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md` has changed how `Methods` is built, construct it with the new API but keep the manager hook. If its retry logic re-runs the hook, the recorded request is still the last one sent, which is fine.

**CHANGELOG.** Under `## Unreleased` / `### New Features`, add: "Add `retrieveSession`, `updateSession` and `cancelSession` methods (and effectful operations) for `GET /v1/sessions/{id}`, `POST /v1/sessions` and `POST /v1/sessions/{id}/cancel`".


### Milestone 3: session and session-event queries, demo

At the end of this milestone callers can page through sessions and events with typed filters and sorts. The example app demonstrates a full turn.

**Filter and sort types in `src/Notion/V1/Sessions.hs`.**

```haskell
-- | Timestamp comparison (ISO 8601 strings). Sessions do not accept 'equals'; events do.
data TimestampCondition = TimestampCondition
  { equals :: Maybe Text,
    before :: Maybe Text,
    after :: Maybe Text,
    onOrBefore :: Maybe Text,
    onOrAfter :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)

emptyTimestampCondition :: TimestampCondition   -- all fields Nothing

data SessionTimestampProperty = SessionCreatedAt | SessionUpdatedAt
  deriving stock (Eq, Show, Generic)

-- | Filter for querySessions. The server allows and/or nesting up to two levels deep.
data SessionFilter
  = SessionIdEquals Text
  | SessionAgentIdEquals AgentId
  | SessionStatusFilter {equals :: Maybe SessionStatus, in_ :: Maybe (Vector SessionStatus)}
  | SessionTimestampFilter SessionTimestampProperty TimestampCondition
  | SessionFilterAnd (Vector SessionFilter)
  | SessionFilterOr (Vector SessionFilter)
  | SessionFilterRaw Value
  deriving stock (Eq, Show, Generic)

data SessionEventType
  = UserMessageType | AgentMessageType | AgentThinkingType
  | AgentToolUseType | AgentToolResultType | SessionStatusType
  | OtherSessionEventType Text
  deriving stock (Eq, Show, Generic)

data NumberCondition = NumberCondition
  { greaterThan :: Maybe Natural,
    greaterThanOrEqualTo :: Maybe Natural,
    lessThan :: Maybe Natural,
    lessThanOrEqualTo :: Maybe Natural
  }
  deriving stock (Eq, Show, Generic)

emptyNumberCondition :: NumberCondition          -- all fields Nothing

-- | Filter for querySessionEvents. The server allows and/or nesting up to three levels deep.
data SessionEventFilter
  = EventIdEquals Text
  | EventTypeFilter {equals :: Maybe SessionEventType, in_ :: Maybe (Vector SessionEventType)}
  | EventSequenceFilter NumberCondition
  | EventCreatedAtFilter TimestampCondition
  | EventFilterAnd (Vector SessionEventFilter)
  | EventFilterOr (Vector SessionEventFilter)
  | EventFilterRaw Value
  deriving stock (Eq, Show, Generic)

data SessionSortProperty = SortByCreatedAt | SortByUpdatedAt
data SessionSort = SessionSort {property :: SessionSortProperty, direction :: SortDirection}

data SessionEventSortProperty = SortBySequence | SortByEventCreatedAt
data SessionEventSort = SessionEventSort {property :: SessionEventSortProperty, direction :: SortDirection}

data QuerySessionsRequest = QuerySessionsRequest
  { query :: Maybe Text,
    filter :: Maybe SessionFilter,
    sorts :: Maybe (Vector SessionSort),
    startCursor :: Maybe Text,
    pageSize :: Maybe Natural
  }

data QuerySessionEventsRequest = QuerySessionEventsRequest
  { filter :: Maybe SessionEventFilter,
    sorts :: Maybe (Vector SessionEventSort),
    startCursor :: Maybe Text,
    pageSize :: Maybe Natural
  }

emptyQuerySessions :: QuerySessionsRequest        -- all fields Nothing
emptyQuerySessionEvents :: QuerySessionEventsRequest
```

`SortDirection` is imported from `Notion.V1.Filter`. The two query records and two sort records derive `(Eq, Show, Generic)` like the others. `TimestampCondition`, `NumberCondition`, `QuerySessionsRequest` and `QuerySessionEventsRequest` use `genericToJSON aesonOptions`, which omits `Nothing` keys and turns `greaterThanOrEqualTo` into `greater_than_or_equal_to`.

Hand-write `ToJSON` for the filter sum types. Each leaf becomes a property filter:

- `SessionIdEquals t` becomes `{"property":"id","string":{"equals":t}}`.
- `SessionAgentIdEquals a` becomes `{"property":"agent_id","string":{"equals":a}}`.
- `SessionStatusFilter` becomes `{"property":"status","status":{...}}`, omitting `Nothing` keys.
- `SessionTimestampFilter p c` becomes `{"property":"created_at"|"updated_at","timestamp":c}`.
- `SessionFilterAnd xs` becomes `{"and":xs}`, and `SessionFilterOr xs` becomes `{"or":xs}`.
- `SessionFilterRaw v` is sent as `v` unchanged.

The event filter follows the same pattern with property names `id` (`string`), `type` (`event_type`), `sequence` (`number`) and `created_at` (`timestamp`). `SessionEventType` encodes to the six dotted strings; `OtherSessionEventType t` encodes to `t`. The sort properties encode to `"created_at"`, `"updated_at"`, `"sequence"` and `"created_at"`.

**Routes.** Extend `Sessions.API` with two more alternatives at the end:

```haskell
           :<|> "query"
           :> ReqBody '[JSON] QuerySessionsRequest
           :> Post '[JSON] (ListOf Session)
           :<|> Capture "session_id" SessionID
           :> "events"
           :> "query"
           :> ReqBody '[JSON] QuerySessionEventsRequest
           :> Post '[JSON] (ListOf SessionEvent)
```

`servant-client` only builds requests and never matches routes, so the literal `"query"` segment cannot collide with `Capture "session_id"`.

**Wiring.** Extend the `makeMethods` pattern element to `(retrieveSession :<|> updateSession :<|> cancelSession :<|> querySessions :<|> querySessionEvents)`, and add to `Methods`:

```haskell
    -- | Query sessions (title search, filter, sorts, cursor pagination; page_size max 100).
    querySessions :: Sessions.QuerySessionsRequest -> IO (ListOf Session),
    -- | Query one session's events (filter, sorts, cursor pagination; page_size max 100).
    querySessionEvents :: SessionID -> Sessions.QuerySessionEventsRequest -> IO (ListOf Sessions.SessionEvent),
```

In the effectful package, add `QuerySessions` and `QuerySessionEvents` constructors, the `querySessions` and `querySessionEvents` smart constructors and exports, and the interpreter branches `QuerySessions req -> runIO (Notion.querySessions methods req)` and `QuerySessionEvents sid req -> runIO (Notion.querySessionEvents methods sid req)`.

**Demo.** Create `notion-client-example/SessionDemo.hs` exporting `runSessionDemo :: Methods -> Text -> IO ()`; the second argument is the agent ID. Add `SessionDemo` to `other-modules` of the example executable in `notion-client.cabal`. The demo:

1. prints a `printHeader "Sessions API"` banner;
2. calls `querySessions` with `pageSize = Just 5` and prints each title and status;
3. calls `updateSession (newTurn (Just (AgentId agentId)) Nothing "Reply with one short greeting for Tanaka Hanako.")` and prints the returned session ID and status;
4. polls `retrieveSession` every 2 seconds (`threadDelay 2000000`, at most 30 times) until the status is anything other than `SessionQueued` or `SessionInProgress`;
5. prints `required_actions` titles if the status is `SessionRequiresAction`; it does not approve anything automatically;
6. calls `querySessionEvents` with `emptyQuerySessionEvents` and prints one line per event, `sequence`, type and (for messages) the first text content;
7. if polling timed out, calls `cancelSession sid (CancelSessionRequest Nothing)` and prints the result.

In `notion-client-example/Main.hs`, read `NOTION_AGENT_ID` with `Environment.lookupEnv`. Call `runSessionDemo methods (Text.pack aid)` when it is set; otherwise print `Skipping Sessions API demo (set NOTION_AGENT_ID to run it; it consumes agent credits)`. Mention the variable in the module header comment's setup steps.

**CHANGELOG.** Under `### New Features`, add: "Add `querySessions` and `querySessionEvents` with typed `SessionFilter`/`SessionEventFilter` (plus raw-JSON escape hatches) and sorts".


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client` unless another directory is shown.

Pre-flight for Milestone 1:

```bash
git -C /Users/shinzui/Keikaku/hub/notion-sdk-js pull
git -C /Users/shinzui/Keikaku/hub/notion-sdk-js log --oneline 978d690..HEAD -- src/api-endpoints/agents.ts src/Client.ts src/api-endpoint-methods.ts
git -C /Users/shinzui/Keikaku/hub/notion-sdk-js diff 978d690 HEAD -- src/api-endpoints/agents.ts | grep -n -i -E 'session|continue_from|event_id' | head -80
```

If the log prints nothing, there is no drift; note "pre-flight: no drift since 978d690" in Surprises & Discoveries. Otherwise read the diff hunks for the types named in Context and Orientation and update this plan first.

Check whether the shared module exists:

```bash
ls src/Notion/V1/Agents/Common.hs 2>/dev/null && echo "exists: import it" || echo "absent: create it"
```

After each milestone's edits:

```bash
cabal build all
cabal test
```

To run only this plan's tests:

```bash
cabal test --test-options='-p Sessions'
```

Expected tail of a successful Milestone 1 run (exact names follow the test cases listed below):

```text
  Sessions
    Decode base session (update/cancel response):                OK
    Decode full session (retrieve response):                     OK
    Unknown session status decodes to UnknownSessionStatus:      OK
    ...
All N tests passed (0.xx s)
```

Commit at the end of each milestone. Stage all changed files (including `CHANGELOG.md`, `notion-client.cabal` and the effectful package), and if `treefmt` rewrites files during the pre-commit hook, re-stage them and commit again. Example message:

```text
feat(sessions): add session and session event types

Add Notion.V1.Sessions with Session, SessionStatus, RequiredAction,
SessionError, SessionEvent and SessionUpdateRequest, plus the shared
Notion.V1.Agents.Common primitives. Unknown enum values decode into
fallback constructors.

MasterPlan: docs/masterplans/2-add-the-custom-agents-and-sessions-api-with-sse-streaming.md
ExecPlan: docs/plans/13-add-session-endpoints-and-session-event-types.md
```

Milestone 2 uses a subject such as `feat(sessions): add retrieveSession, updateSession and cancelSession`, and Milestone 3 `feat(sessions): add session and session event queries`, with the same trailers.


## Validation and Acceptance

**Milestone 1.** `cabal build all` succeeds with no new warnings in `src/Notion/V1/Sessions.hs` or `src/Notion/V1/Agents/Common.hs`. `cabal test` shows a `Sessions` group in which all of the following pass. Each fixture is a JSON literal inside `tasty/SessionsTests.hs`.

- **Decode base session.** Input `{"object":"session","id":"11111111-1111-1111-1111-111111111111","agent_id":"notion_ai","title":"Weekly standup summary","status":"requires_action","created_at":"2026-08-15T03:36:28.649Z","updated_at":"2026-08-15T03:36:30+00:00","required_actions":[{"action_id":"act-1","title":"Send email to Sato Kenji","options":[{"id":"approve","label":"Approve"},{"id":"reject","label":"Reject"}]}]}`. It decodes to `status == SessionRequiresAction`, one required action with two options `ApproveOption`/`RejectOption`, `agentId == AgentId "notion_ai"`, and `createdBy == Nothing`.
- **Decode full session.** The same object plus `"created_by":{"id":"22222222-2222-2222-2222-222222222222","type":"user"}`, `"agent_version":{"id":"33333333-aaaa-4bbb-8ccc-444444444444","number":3,"published_at":"2026-08-01T00:00:00Z"}`, `"models":{"type":"pinned","ids":["claude-sonnet-5",null]}`, `"trigger_type":"manual"`, `"type_labels":null`, `"chat_user_emails":["tanaka.hanako@example.com"]`, `"tool_call_count":4`, `"credits_used":1.5`, `"runs_completed":1`, `"message_count":6` and `"error":{"code":"tool_failed","message":"Search timed out","retryable":true}`. It decodes with `models == Just (ModelPinned [Just "claude-sonnet-5", Nothing])`, `creditsUsed == Just 1.5`, `typeLabels == Nothing`, and `error` equal to that `SessionError`.
- **Unknown status.** `"status":"paused"` decodes to `UnknownSessionStatus "paused"`.
- **Agent-form model selection.** `{"mode":"pinned","id":null}` decodes to `ModelPinned [Nothing]`, `{"mode":"auto"}` to `ModelAuto`, and `{"mode":"custom"}` to `UnknownModelSelection`.
- **Committed user message.** `{"object":"session_event","id":"event-1","session_id":"11111111-1111-1111-1111-111111111111","sequence":1,"created_at":"2026-08-15T03:36:28.649Z","type":"user.message","content":[{"type":"text","text":"hello"},{"type":"file","file_id":"22222222-2222-2222-2222-222222222222"}],"metadata":{"source":"test"}}`. It decodes to `UserMessage` with `[TextContent "hello", FileIdContent "2222..."]` and metadata `fromList [("source","test")]`. This fixture is copied from the SDK's own test, `test/Client.test.ts` line 726.
- **Committed status event with usage and artifacts.** `{"object":"session_event","id":"event-2","session_id":"1111...","sequence":2,"created_at":"2026-08-15T03:36:29.649Z","type":"session.status","status":"completed","usage":{"input_tokens":10,"output_tokens":20,"total_tokens":30},"artifacts":[{"type":"page","url":"https://notion.so/page","title":"Plan"},{"type":"html_artifact","url":"https://notion.so/a.html","page_url":"https://notion.so/page"}]}`. It decodes to `SessionStatusChanged` with `usage == Just (SessionUsage 30 (Just 10) (Just 20))` and a `PageArtifact` followed by an `HtmlArtifact`.
- **Queried agent message with resolved file.** It has `"created_by":{"id":"2222...","type":"bot"}`, `"metadata":{"model":"claude-sonnet-5"}`, and content `[{"type":"file","name":"report.pdf","content_type":"application/pdf","url":"https://files.example.com/report.pdf","expiry_time":"2026-08-15T04:36:28Z"}]`. It decodes to `AgentMessage` with `FileContent` and `createdBy` with `CreatedByBot`.
- **Queried thinking, tool use and tool result.** `agent.thinking` with one text part, `agent.tool_use` with `"tool_name":"search"`, and `agent.tool_result` with `"tool_use_id":"tool-1","tool_name":"search","is_error":false` each decode to their constructors.
- **Unknown event type.** `"type":"agent.plan"` decodes to `UnknownSessionEvent "agent.plan" _`, with `sequence` still read.
- **Malformed known event fails.** `"type":"agent.tool_use"` with no `tool_name` makes `eitherDecode` return `Left`.
- **Encode new turn.** `toJSON (newTurn Nothing (Just "1111...") "hello")` equals the decoded value of `{"message":"hello","session_id":"1111..."}`. This is the body the SDK test at `test/Client.test.ts` line 647 expects.
- **Encode new turn with attachment.** An attachment with `fileUploadId = "4444..."` and `name = Just "notes.txt"` encodes to `{"message":"...","attachments":[{"type":"file_upload","file_upload":{"id":"4444..."},"name":"notes.txt"}]}`.
- **Encode approval.** It encodes to `{"session_id":"1111...","actions":[{"action_id":"act-1","option_id":"approve"}]}`.
- **Encode resume.** It encodes to `{"session_id":"1111...","continue_from":"event-7"}`.
- **Encode cancel.** `CancelSessionRequest Nothing` encodes to `{}`, and `CancelSessionRequest (Just "event-3")` encodes to `{"event_id":"event-3"}`.

Compare JSON as `Aeson.Value`s (decode the expected literal with `Aeson.decode`), never as strings, because key order is not stable.

**Milestone 2.** `cabal build all` succeeds for both packages. The build output for `notion-client-effectful` must contain no `Pattern match(es) are non-exhaustive` warning for `Interpreter.hs`. Both packages build with `-Wall` but not `-Werror`, so a missing interpreter branch shows up only as that warning, and you must check for it. `cabal test` additionally passes these cases:

- **retrieveSession request.** `captureRequest (\m -> retrieveSession m "1111...")` has method `"GET"` and path `"/v1/sessions/1111..."`.
- **updateSession request.** It has method `"POST"`, path `"/v1/sessions"`, and body `{"message":"hello","session_id":"1111..."}`.
- **cancelSession request.** It has method `"POST"`, path `"/v1/sessions/1111.../cancel"`, and body `{"event_id":"event-3"}`.
- **Headers.** The `retrieveSession` request carries `Authorization: Bearer test-token` and a `Notion-Version` header.

**Milestone 3.** `cabal test` additionally passes:

- **Session filter encoding.** `SessionFilterAnd [SessionStatusFilter {equals = Nothing, in_ = Just [SessionCompleted, SessionFailed]}, SessionTimestampFilter SessionUpdatedAt emptyTimestampCondition {onOrAfter = Just "2026-08-01T00:00:00Z"}]` (an unambiguous update, because `onOrAfter` belongs only to `TimestampCondition`) encodes to `{"and":[{"property":"status","status":{"in":["completed","failed"]}},{"property":"updated_at","timestamp":{"on_or_after":"2026-08-01T00:00:00Z"}}]}`.
- **Event filter encoding.** `EventFilterOr [EventTypeFilter {equals = Just AgentThinkingType, in_ = Nothing}, EventSequenceFilter NumberCondition {greaterThan = Nothing, greaterThanOrEqualTo = Just 5, lessThan = Nothing, lessThanOrEqualTo = Nothing}]` encodes to `{"or":[{"property":"type","event_type":{"equals":"agent.thinking"}},{"property":"sequence","number":{"greater_than_or_equal_to":5}}]}`.
- **Raw filter passthrough.** `SessionFilterRaw v` encodes to `v` unchanged.
- **Query body.** `QuerySessionsRequest {query = Just "standup", filter = Nothing, sorts = Nothing, startCursor = Nothing, pageSize = Just 10}` encodes to `{"query":"standup","page_size":10}`, matching the SDK test at `test/Client.test.ts` line 840.
- **Sessions list with placeholder.** `{"object":"list","type":"session","session":{},"results":[<base session fixture>],"has_more":true,"next_cursor":"cursor-2"}` decodes as `ListOf Session` with one result, `hasMore == True` and `nextCursor == Just "cursor-2"`.
- **Events list with placeholder.** `{"object":"list","type":"session_event","session_event":{},"results":[<thinking event>,<unknown event>],"has_more":false,"next_cursor":null}` decodes as `ListOf SessionEvent` with two results.
- **querySessions and querySessionEvents requests.** Their paths are `"/v1/sessions/query"` and `"/v1/sessions/1111.../events/query"`, both with method `"POST"`.

**Optional live check.** This needs a workspace with a custom agent the integration can reach.

```bash
NOTION_TOKEN=secret_... NOTION_AGENT_ID=<agent uuid or notion_ai> cabal run notion-client-example
```

In the output, look for a `=== Sessions API ===` section. It should show:

- the created session ID with status `SessionQueued` or `SessionInProgress`;
- a final status such as `SessionCompleted`;
- event lines like `1 user.message: Reply with one short greeting for Tanaka Hanako.` followed by `agent.message` (and possibly `agent.thinking`) lines.

If Notion returns a 4xx `NotionError` saying the route is unavailable, the surface is not enabled for that workspace. Record it in Surprises & Discoveries; unit tests remain the acceptance gate. Without `NOTION_AGENT_ID` the section prints the skip message.


## Idempotence and Recovery

Every step is additive: new modules, new record fields, new test cases and new CHANGELOG lines. Re-running the build and tests is always safe. Re-running the pre-flight commands is safe; `git pull` only fast-forwards the reference checkout, which this plan never edits.

Before creating `src/Notion/V1/Agents/Common.hs`, always check whether it exists, because the sibling agents plan may have created it in the meantime. If both plans created it concurrently on different branches, keep one copy, merge in any missing constructor or decoder branch, and delete the duplicate. Never keep two definitions of `AgentId` or `ModelSelection`.

If a milestone's build breaks halfway, the usual cause is an ordering mismatch between `Sessions.API`, the `API` list in `src/Notion/V1.hs` and the `makeMethods` pattern. GHC reports a type error mentioning `:<|>`. Compare the three orders and fix them. A missing effectful branch shows up as a compile error in `notion-client-effectful`. Nothing touches remote state except the optional demo, which creates one session. If the demo times out it cancels its own session; otherwise stop it with the `cancelSession` method from GHCi.

Adding `Methods` fields and `Notion` effect constructors breaks anyone who constructs `Methods` by hand or pattern-matches `Notion` exhaustively. That is the library's normal additive growth; no existing field or constructor changes. There are no breaking changes to existing types, so no `### Breaking Changes` entry is needed, unless the shared `ModelSelection` in an already-released `Notion.V1.Agents.Common` has to change shape, in which case add one.


## Interfaces and Dependencies

No new package dependencies. The library already uses `aeson` (JSON), `servant`/`servant-client` (routes and clients), `scientific` (for `creditsUsed`), `text`, `vector`, `containers` (`Map`) and `time` (via `parseISO8601`). The test suite already uses `http-client` (for `managerModifyRequest`), `servant-client`, `tasty` and `tasty-hunit`.

At the end of Milestone 1, `Notion.V1.Agents.Common` exports `AgentId (..)`, `notionAiAgentId`, `ModelSelection (..)`, `CreatedByRef (..)`, `CreatedByType (..)`, `AgentVersionRef (..)` and `Hideable (..)`, with the definitions shown in Plan of Work. `Notion.V1.Sessions` exports:

```haskell
SessionID, Session (..), SessionStatus (..), RequiredAction (..), RequiredActionOption (..),
ActionOptionId (..), SessionError (..),
SessionEvent (..), SessionEventPayload (..), MessageEvent (..), EventContent (..), ResolvedFile (..),
ToolUseEvent (..), ToolResultEvent (..), StatusEvent (..), SessionUsage (..), SessionArtifact (..),
parseSessionEventPayload,   -- :: Aeson.Object -> Aeson.Types.Parser SessionEventPayload
SessionUpdateRequest (..), NewTurnRequest (..), newTurn, SessionAttachment (..),
ApprovalRequest (..), ActionApproval (..), ResumeRequest (..), CancelSessionRequest (..)
```

At the end of Milestone 2, `Notion.V1.Sessions` also exports `API`, and `Notion.V1.Methods` has these fields:

```haskell
retrieveSession :: SessionID -> IO Session
updateSession   :: SessionUpdateRequest -> IO Session
cancelSession   :: SessionID -> CancelSessionRequest -> IO Session
```

`Notion.V1.Effectful.Effect` has the constructors `RetrieveSession`, `UpdateSession` and `CancelSession` and the smart constructors of the same lower-case names and argument order, returning `Eff es Session` under `(Notion :> es)`.

At the end of Milestone 3, `Notion.V1.Sessions` also exports `SessionFilter (..)`, `SessionEventFilter (..)`, `SessionEventType (..)`, `TimestampCondition (..)`, `emptyTimestampCondition`, `NumberCondition (..)`, `emptyNumberCondition`, `SessionTimestampProperty (..)`, `SessionSort (..)`, `SessionSortProperty (..)`, `SessionEventSort (..)`, `SessionEventSortProperty (..)`, `QuerySessionsRequest (..)`, `emptyQuerySessions`, `QuerySessionEventsRequest (..)` and `emptyQuerySessionEvents`. `Methods` gains:

```haskell
querySessions      :: QuerySessionsRequest -> IO (ListOf Session)
querySessionEvents :: SessionID -> QuerySessionEventsRequest -> IO (ListOf SessionEvent)
```

The effectful package gains `QuerySessions`/`querySessions` and `QuerySessionEvents`/`querySessionEvents`.

What `docs/plans/14-stream-session-updates-over-server-sent-events.md` consumes from this plan:

- `SessionUpdateRequest`, as its request body;
- `Session`, for `session.snapshot`;
- `SessionEvent`, for `event.committed`;
- `parseSessionEventPayload`, for provisional events without `sequence`;
- `SessionStatus`, for `stream.end`;
- `SessionError`, for `stream.error`.

It does not consume `Methods` fields from this plan.
