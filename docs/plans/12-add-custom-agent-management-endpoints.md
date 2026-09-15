---
id: 12
slug: add-custom-agent-management-endpoints
title: "Add Custom Agent Management Endpoints"
kind: exec-plan
created_at: 2026-09-14T18:46:51Z
master_plan: "docs/masterplans/2-add-the-custom-agents-and-sessions-api-with-sse-streaming.md"
provenance:
  created_by:
    model: "claude-opus-5"
    harness: "claude-code"
    at: 2026-09-14T18:46:51Z
  revisions:
    - model: "claude-opus-5[1m]"
      harness: "claude-code"
      at: 2026-09-15T14:19:29Z
      mode: "update"
      note: "Batch route must accept HTTP 202 (from MP1 EP-3)"
---

# Add Custom Agent Management Endpoints

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Notion workspaces can define "custom agents". A custom agent is an AI assistant configured inside Notion, with instructions, connections to tools such as Slack or an MCP server, triggers such as a weekly schedule, a status (active or disabled) and a credit limit. Credits are Notion's unit of paid AI usage. Notion's official TypeScript SDK exposes seven REST routes for managing these agents. The Haskell library in this repository has none of them.

After this plan is implemented, a Haskell program using `notion-client` can do all of the following through the `Methods` record in `src/Notion/V1.hs`:

- List and search a workspace's agents with a typed filter, and page through the results.
- Retrieve one agent, optionally with its inline instructions.
- Soft-delete an agent.
- Read an agent's usage insights for a time window: credits used, runs completed and credit limit.
- Enable or disable an agent.
- Set or clear an agent's credit limit.
- Submit up to 100 of those operations in one batch request, which returns an async task the caller can poll.

The same seven operations are available through the `notion-client-effectful` package.

You can see this working in three ways:

- `cabal test` runs a new `Agents` test group. It decodes JSON fixtures that mirror the official SDK's types, including unknown enum values that Notion may add later, and checks the exact JSON bodies the client sends.
- Running `NOTION_AGENT_DEMO=1 cabal run notion-client-example` with a token for a workspace that has custom agents prints each agent's name, type, status and credit usage.
- The GHCi snippet in Validation and Acceptance exercises the mutating calls against a real agent you choose.


## Progress

- [ ] Milestone 1: Pre-flight re-diff of the JS SDK `src/api-endpoints/agents.ts` against the shapes in this plan; drift recorded in Surprises & Discoveries.
- [ ] Milestone 1: Check whether `src/Notion/V1/Agents/Common.hs` already exists (created by `docs/plans/13-add-session-endpoints-and-session-event-types.md`); if absent, create it with exactly the shared definitions (`AgentId`, `notionAiAgentId`, `ModelSelection`, `CreatedByRef`, `CreatedByType`, `AgentVersionRef`, `Hideable`) that plan also specifies.
- [ ] Milestone 1: Create `src/Notion/V1/Agents.hs` with the `Agent` object, its enums, connections, icon and triggers, all with tolerant `FromJSON`.
- [ ] Milestone 1: Register both modules in `notion-client.cabal`.
- [ ] Milestone 1: Create `tasty/AgentsTests.hs` with the agent-object decoding tests; register it in the cabal file and `tasty/Main.hs`; `cabal test` passes.
- [ ] Milestone 2: Add `QueryAgents`, `AgentFilter`, `AgentSort` and `DeletedAgent` types with their instances.
- [ ] Milestone 2: Add the query, retrieve and delete Servant routes, plus the `queryAgents`, `retrieveAgent` and `deleteAgent` `Methods` fields.
- [ ] Milestone 2: Add matching effect constructors, smart constructors and interpreter cases in `notion-client-effectful`.
- [ ] Milestone 2: Add request-encoding and list-decoding tests; `cabal build all` and `cabal test` pass.
- [ ] Milestone 3: Add `AgentInsights`, `InsightsWindow`, `UpdateAgentStatus`, `TargetAgentStatus`, `AgentStatusUpdated`, `UpdateAgentCreditLimit` and `AgentCreditLimitUpdated`.
- [ ] Milestone 3: Add the insights, status and credit-limit routes, `Methods` fields and effectful lockstep.
- [ ] Milestone 3: Add tests (including the explicit `"credit_limit": null` encoding).
- [ ] Milestone 3: Add `notion-client-example/AgentDemo.hs`, gated on `NOTION_AGENT_DEMO=1`.
- [ ] Milestone 3: Add CHANGELOG entries for Milestones 2–3.
- [ ] Milestone 4: Precondition check that `src/Notion/V1/AsyncTasks.hs` exports `AsyncTask` (from `docs/plans/8-add-comment-mutation-async-task-and-meeting-notes-endpoints.md`).
- [ ] Milestone 4: Add `AgentBatch`, `AgentOperation` and `mkAgentBatch`, the batch route, the `batchAgents` field and effectful lockstep.
- [ ] Milestone 4: Add batch tests; update the CHANGELOG; `cabal build all` and `cabal test` pass.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Decode the retrieve response and both variants of the query results (custom or autofill agents, and the fixed `notion_ai` personal agent) into one `Agent` record. Fields that some variants omit become `Maybe`.
  Rationale: The three JS shapes differ only in which fields are present or nullable (see Context and Orientation). One record lets callers pass an agent from `queryAgents` to `retrieveAgent` without converting, and a field Notion drops later decodes as `Nothing` instead of failing.
  Date: 2026-09-14

- Decision: Every closed enum and tagged union in a response gets a fallback constructor. Enums use `UnknownX Text`. Tagged objects use `UnknownX Value`, reached through `asum` when the typed parse fails. This covers agent type, status, pause reason, creator type, model selection, icon, connection, permission targets and schedule end. Connector machine names (about 35 literals such as `github` and `jira`) are kept as plain `Text`.
  Rationale: The parent MasterPlan requires tolerant decoding. The JS SDK describes this surface as "unpublished", and its enums widened weekly during August 2026. A new connector literal must never break decoding of a whole agent list.
  Date: 2026-09-14

- Decision: Represent the query `filter` as a typed `AgentFilter` sum with one constructor per documented property, `AgentFilterAnd`/`AgentFilterOr` compounds, and an `AgentFilterRaw Value` escape hatch. Do not reuse `Notion.V1.Filter.Filter`.
  Rationale: The agents filter grammar is small: 10 fixed properties, each with exactly one condition, nested at most two levels. A typed DSL catches typos at compile time for little code. `Notion.V1.Filter.Filter` models user-defined data-source properties with a different condition vocabulary (`id`, `string`, `people`, `mcp_server` keys do not exist there), so reusing it would allow invalid filters. The raw escape hatch absorbs any property Notion adds before this library catches up. The two-level nesting limit is documented rather than type-enforced, because enforcing it in types would triple the type count while the server already validates it.
  Date: 2026-09-14

- Decision: Model `"hidden"`-able fields as `Maybe (Hideable a)`, where `Hideable a = Hidden | Visible a`. `Nothing` means the field was absent or `null`.
  Rationale: Notion sends the string `"hidden"` in place of a value when the caller lacks edit or full access. Absent and `null` carry the same meaning to a caller ("no value"). Keeping `Hideable` free of a third "null" case lets EP-2 reuse it for non-nullable fields.
  Date: 2026-09-14

- Decision: Use the shared `Notion.V1.Agents.Common` definitions exactly as specified in `docs/plans/13-add-session-endpoints-and-session-event-types.md` (same type, constructor and field names). This includes one `ModelSelection` whose decoder accepts both wire spellings: agents use `{"mode": "auto"}` / `{"mode": "pinned", "id": ...}`, while sessions use `{"type": "auto"}` / `{"type": "pinned", "ids": [...]}`. Both normalize to `ModelAuto | ModelPinned (Vector (Maybe Text)) | UnknownModelSelection Value`. Agent-only helpers (`legacyNotionAiAgentId`, `parseHideable`, `parseTimestampValue`) live in `Notion.V1.Agents`, not in the shared module.
  Rationale: The MasterPlan forbids two definitions of the shared primitives. The two JS types spell the model discriminator and id field differently (`GetAgentResponse.model` at `agents.ts` line 740 versus `RetrieveSessionResponse.models` at line 4804), and one tolerant decoder serves both plans. Keeping helpers out of the shared file means neither plan's copy of the module drifts from the other's.
  Date: 2026-09-14

- Decision: Credit amounts in responses are `Scientific`, and the request-side credit limit is `Natural`. `UpdateAgentCreditLimit` and the batch operation serialize `Nothing` as an explicit JSON `null`.
  Rationale: The JS type is `number`, and the docs say "non-negative integer" only for the request. Decoding responses as `Natural` would fail on a fractional value. `aesonOptions` sets `omitNothingFields = True`, which would turn "clear the limit" into an empty body, so these two encoders are hand-written.
  Date: 2026-09-14

- Decision: `retrieveAgentInsights` takes `Maybe InsightsWindow` (a start/end pair in epoch seconds) rather than two independent `Maybe` parameters.
  Rationale: The JS doc comment says `start_time` and `end_time` "Must be supplied together". A pair makes the invalid half-window unrepresentable.
  Date: 2026-09-14

- Decision: Implement batch last, consume `AsyncTask` from `src/Notion/V1/AsyncTasks.hs` as defined by `docs/plans/8-add-comment-mutation-async-task-and-meeting-notes-endpoints.md`, and never define a local copy.
  Rationale: The MasterPlan assigns ownership of `AsyncTask` to that plan. The other six endpoints do not need it.
  Date: 2026-09-14

- Decision: Keep the example demo read-only (query, retrieve, insights) and gate it on `NOTION_AGENT_DEMO=1`.
  Rationale: Disabling or deleting a real agent, or changing its credit limit, affects a live workspace and consumes nothing reversible by the demo. Mutations are exercised by unit tests and an explicit GHCi snippet instead.
  Date: 2026-09-14

- Decision: Parse agent timestamps (`created_time`, `last_edited_time`, `last_run_time`, `last_run_at`, `published_at`, `deleted_at`) to `POSIXTime` with `Notion.Prelude.parseISO8601`. Keep trigger schedule `start_date` and `end.end_at` as `Text`.
  Rationale: `POSIXTime` matches existing modules such as `src/Notion/V1/Comments.hs`. Schedule dates are configuration echoed back from the Notion UI and are not guaranteed to carry a time component, so parsing them strictly would add a failure mode for no caller benefit.
  Date: 2026-09-14


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

### The repository

`notion-client` is a Haskell client for the Notion REST API. It uses GHC 9.12.2, language `GHC2024`, and is built with cabal. The repository root holds two packages, listed in `cabal.project`:

- `notion-client` (the `.` directory) is the library, a test suite named `tasty`, and an executable named `notion-client-example`.
- `notion-client-effectful` wraps the library in an `effectful` effect.

There is no `docs/adr/` directory in this repository, and no relevant ADR exists.

The library binds endpoints with Servant. Servant is a Haskell library that describes an HTTP API as a type, for example `"views" :> Capture "view_id" ViewID :> Get '[JSON] ViewObject`; `servant-client` then derives client functions from that type. Each endpoint area lives in its own module under `src/Notion/V1/` and exports a `type API`. For example, `src/Notion/V1/Views.hs` (lines 162–182) and `src/Notion/V1/CustomEmojis.hs` (a short, complete example worth reading first).

`src/Notion/V1.hs` ties everything together:

- `type API` (around line 297) prefixes every route with the `Authorization` and `Notion-Version` headers and joins the area APIs with `:<|>`.
- `data Methods` (around line 166) is a record with one `IO` function per endpoint.
- `makeMethods` (around line 79) calls `Client.hoistClient @API Proxy run (Client.client @API Proxy) authorization notionVersion`. It pattern-matches the resulting tree of `:<|>`-separated functions into local names, which `Methods {..}` (RecordWildCards) then picks up by name. The destructuring pattern must list the client functions in exactly the order the routes appear in `type API`. Adding a route therefore means editing the area module's `API`, the `:<|>` pattern in `makeMethods`, and the `Methods` record.
- `run` converts a Servant failure into a thrown `Notion.V1.Error.NotionError` (fields `object`, `status`, `code`, `message`, `details`) when the body parses as a Notion error.

`docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md` may have changed `makeMethods` and `NotionError` by the time you implement this plan, for example with a configuration record, retries, or a typed `code`. If so, add the agents routes to whatever client destructuring exists at that point. The principle is unchanged: one new route, one new destructured name, one new `Methods` field.

### JSON conventions

JSON conventions live in `src/Notion/Prelude.hs`, which every module imports and which re-exports `Data.Aeson`'s core classes, `Text`, `Vector`, `Map`, `POSIXTime`, `Natural`, `NonEmpty` and the Servant combinators:

- `aesonOptions` converts camelCase field names to snake_case (`createdTime` becomes `created_time`) and strips a trailing underscore (`type_` becomes `type`, which avoids the Haskell keyword). It also sets `omitNothingFields = True`, so a `Nothing` field is left out of the encoded object entirely.
- `parseISO8601 :: Text -> Parser POSIXTime` accepts both `Z` and `+00:00` offsets.

Request bodies usually derive `ToJSON` with `genericToJSON aesonOptions` (see `QueryDataSource` in `src/Notion/V1/DataSources.hs` line 132). Response types usually have hand-written `FromJSON` instances using `withObject` or `LambdaCase`, `.:` for required keys and `.:?` for optional ones (see `CommentObject` in `src/Notion/V1/Comments.hs` around line 111). `Data.Foldable.asum` is used to try several parsers in order (see `src/Notion/V1/Common.hs`).

All packages enable `DuplicateRecordFields`, `OverloadedLabels`, `OverloadedStrings` and `RecordWildCards` by default (see `notion-client.cabal`). Modules with a record field named `id` write `import Prelude hiding (id)`.

Useful existing types:

- `Notion.V1.Common.UUID` is a newtype over `Text` with `FromJSON`, `ToJSON`, `IsString` and `ToHttpApiData`.
- `Notion.V1.Common.Icon` decodes page icons: emoji, file, external, native `icon`, `custom_emoji`, `file_upload`.
- `Notion.V1.ListOf.ListOf a` decodes Notion's paginated envelope `{object, type, results, has_more, next_cursor}`.
- `Notion.V1.Pagination.paginateCollect` loops over cursors.
- `Notion.V1.Filter.SortDirection` (`Ascending`/`Descending`, encoded as `"ascending"`/`"descending"`) can be reused for agent sorts.

One mismatch is worth knowing about. The JS SDK's custom-emoji icon is `{"type": "custom_emoji", "custom_emoji": {"id", "name", "url"}}` (JS `src/api-endpoints/common.ts` line 386), but `Icon`'s parser reads a top-level `"id"`. An agent with a custom-emoji icon will therefore decode through this plan's fallback as `UnknownAgentIcon` until `Icon` itself is fixed. This plan does not change `Icon`.

### The effectful companion package (lockstep rule)

`notion-client-effectful/src/Notion/V1/Effectful/Effect.hs` defines a GADT `data Notion m a` with exactly one constructor per `Methods` field (for example `QueryView :: Views.ViewID -> Views.QueryView -> Notion m (ListOf PageObject)`). It also defines one smart constructor per field, with the same name and argument order as the field (for example `queryView vid q = send (QueryView vid q)`), and exports them all.

`notion-client-effectful/src/Notion/V1/Effectful/Interpreter.hs` imports every constructor by name and maps each to the `Methods` field in `runNotion`, for example `QueryView vid req -> runIO (Notion.queryView methods vid req)`. Request types that share a name with a constructor are imported qualified (`Views.QueryView`).

The lockstep rule: every `Methods` field added here must get a constructor, a smart constructor with an export, an import in the interpreter, and an interpreter case in the same commit. Otherwise `cabal build all` fails, or `-Wall` reports an incomplete pattern.

### Tests and the example program

The test suite is `tasty/Main.hs` (about 2300 lines), stanza `test-suite tasty` in `notion-client.cabal`, which today has no `other-modules` field. `tests :: IO TestTree` ends with:

```haskell
  pure $
    testGroup
      "Notion Client Tests"
      [ jsonParsingTests,
        jsonSerializationTests,
        propertyValueTests,
        fileUploadTests,
        basicIntegration,
        markdownE2E,
        pageE2E,
        databaseE2E,
        viewE2E
      ]
```

This plan adds a new module `tasty/AgentsTests.hs` exporting `tests :: TestTree`, imports it qualified as `AgentsTests` in `tasty/Main.hs`, and adds `AgentsTests.tests` to that list. If an earlier plan has already added an `other-modules` field to the stanza, append `AgentsTests` to it; otherwise create the field. The test-suite dependencies already include `aeson`, `bytestring`, `scientific`, `tasty`, `tasty-hunit`, `text` and `vector`.

The example executable is `notion-client-example/Main.hs`, with demo modules such as `notion-client-example/CustomEmojiDemo.hs` listed under `executable notion-client-example` `other-modules` in `notion-client.cabal`. Helpers in `notion-client-example/Console.hs` are `printHeader :: Text -> IO ()`, `runTest :: Text -> IO a -> IO a` (prints a label and "Done"; it does not catch exceptions) and `logError`.

`CHANGELOG.md` (currently topped by `## 0.7.0.2`) has no `## Unreleased` heading. Create it directly under `# Changelog for notion-client` if it still does not exist, with `### Breaking Changes` / `### New Features` / `### Bug Fixes` subsections as needed. Do the same in `notion-client-effectful/CHANGELOG.md`. Do not bump versions; the parent MasterPlan does that.

### Plans this one interacts with

The parent MasterPlan is `docs/masterplans/2-add-the-custom-agents-and-sessions-api-with-sse-streaming.md`; this plan is its EP-1.

- **Shared primitives.** The sibling `docs/plans/13-add-session-endpoints-and-session-event-types.md` (EP-2) shares the module `src/Notion/V1/Agents/Common.hs`. Whichever plan starts first creates it; the other imports from it and must not redefine its types.
- **`AsyncTask`.** `docs/plans/8-add-comment-mutation-async-task-and-meeting-notes-endpoints.md` owns `AsyncTask` in `src/Notion/V1/AsyncTasks.hs`, together with a `retrieveAsyncTask` method for `GET async_tasks/{task_id}`. At the time of writing that module does not exist, so batch is the last milestone and starts with a precondition check.
- **Typed errors and runtime.** `docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md` owns typed error codes and the configurable runtime. This plan only soft-depends on it, for nicer error printing in the demo.

### The upstream contract

The reference is Notion's official JS SDK `@notionhq/client` v5.26.0, checked out at `/Users/shinzui/Keikaku/hub/notion-sdk-js`. At drafting time its `HEAD` was commit `978d690e60009b493751b28a9d87a026a32e7286` (2026-09-04), and the last commit touching `src/api-endpoints/agents.ts` was `8eea864` (#787).

The routes are defined in `src/api-endpoints/agents.ts` and exposed as `client.agents.{query, retrieve, delete, retrieveInsights, updateStatus, updateCreditLimit, batch}` in `src/api-endpoint-methods.ts` (lines 331–378). `test/Client.test.ts` (lines 506–605) pins the facade to exactly these seven methods and checks their URLs, HTTP methods and bodies.

The SDK's commit history calls these routes "unpublished". Threads, chat, `listAgents` and `external_agent_stub/*` routes exist in the same file but are not on the facade, and are out of scope here.

Everything the implementer needs from that file is transcribed below. In these snippets, `IdRequest` and `IdResponse` are both `string`, and `PageIconResponse` is the ordinary page icon union (emoji, file, external, custom_emoji, icon).

An agent ID path parameter is typed everywhere as:

```typescript
agent_id: IdRequest | "notion_ai" | "33333333-3333-3333-3333-333333333333"
// "notion_ai" is the caller's personal agent; the fixed UUID is its legacy reserved ID.
```

#### Retrieve an agent

`GET agents/{agent_id}` takes the optional query parameter `verbose?: boolean` ("include the agent's inline instructions", default false). It returns `GetAgentResponse` (`agents.ts` lines 710–1087), abridged here only by collapsing repeated comments:

```typescript
type GetAgentResponse = {
  object: "agent"
  id: IdResponse
  agent_type: "notion_ai" | "custom_agent" | "autofill_custom_agent" | "external"
  name: string
  description: string | null
  instructions_page_id: IdResponse | null
  icon:
    | PageIconResponse
    | { type: "custom_agent_avatar"; custom_agent_avatar: { static_url: string; animated_url: string } }
    | null
  model: { mode: "auto" } | { mode: "pinned"; id: string | null }  // null id = pre-release model
  connections: Array<
    | { type: "notion"; name: string; account: null
        permissions: Array<{
          target:
            | { type: "page"; id: string }
            | { type: "database_property"; data_source_id: string; property_id: string }
            | { type: "agent"; id: string }
            | { type: "workspace" }
            | { type: "owner_private_pages" }
            | { type: "web_search"; allowed_domains: Array<string> | null }
            | { type: "notion_help_docs_search" }
          scopes: Array<string>  // "reader" | "comment_only" | "read_and_write" | "editor" | "allow" | "disallow"
        }> }
    | { type: "slack"; name: string
        account: { type: "slack_workspace"; team_id: string } | "hidden" | null
        permissions: Array<{
          target: { type: "slack_channel"; id: string } | { type: "slack_all_public_channels" } | { type: "slack_all_channels" }
          scopes: Array<string>  // "read" | "write" | "reply_in_thread" | "react"
        }> }
    | { type: "discord"; name: string
        account: { type: "discord_server"; id: string } | "hidden" | null
        permissions: Array<{
          target: { type: "discord_channel"; id: string } | { type: "discord_all_channels" }
          scopes: Array<string>
        }> }
    | { type: "mcp_server" | "custom_mcp_server"   // two separate variants with identical fields
        name: string
        account: { type: "mcp_server"; server_host: string } | "hidden" | null
        enabled_tools: Array<{ name: string; title: string | null }> | "hidden" | null  // null = all tools
        run_tools_automatically: { read: boolean; write: boolean } }
    | { type: "asana" | "box" | "browser" | "calendar" | "computer" | "confluence" | "cursor"
            | "files" | "fs" | "github" | "gmail" | "google_calendar" | "google_drive"
            | "google_drive_oauth" | "gtm" | "helpdocs" | "images" | "jira" | "linear" | "mail"
            | "marketplace" | "memory" | "microsoft_teams" | "outlook" | "salesforce" | "search"
            | "security" | "sharepoint" | "skills" | "system" | "test" | "web" | "webhooks"
            | "worker" | "workers"
        name: string
        account: string | null   // comment says it may also be "hidden"
        permissions: Array<{ target: { type: string; id: string }; scopes: Array<string> }> }
  >
  status: "active" | "disabled" | "deleted"
  pause_reason:
    | "run_limit" | "credit_limit" | "runaway_credit_usage" | "workspace_credit_limit"
    | "failure_limit" | "mark_session_failed_autopause" | "disabled_from_workspace_settings"
    | "disabled_from_api" | "disabled_from_agent_settings"
    | "disabled_due_to_no_members_with_access" | "disabled_due_to_lack_of_editors"
    | "disabled_by_notion" | "internal_error" | "needs_user_review" | "tool_unavailable"
    | null
  created_by: { object: "user"; type: "user"; id: IdResponse } | null
  version: { id: IdResponse; number: number; published_at: string } | null
  agent_version: { id: IdResponse; number: number; published_at: string } | null
  has_unpublished_changes: boolean | "hidden"
  last_run_time: string | "hidden" | null
  last_run_at: string | "hidden" | null
  credit_limit: number | "hidden" | null
  triggers: Array<{
    type: string          // e.g. "notion.agent.mentioned", "recurrence", "slack.reaction.added"
    enabled: boolean
    schedule?: {
      frequency: string   // "hour" | "day" | "week" | "month" | "year"
      interval: number
      weekdays?: Array<string>
      monthdays?: Array<number>
      week_numbers?: Array<number>   // -1 = last week
      hour?: number
      minute?: number
      timezone?: string
      start_date?: string
      end?: { type: "date"; end_at: string } | { type: "count"; occurrences: number }
    }
    config?: Record<string, Record<string, never>>
  }>
  created_time?: string
  last_edited_time?: string
  instructions?: string | null
}
```

#### Query agents

`POST agents/query` takes the body `QueryAgentsBodyParameters` (lines 2116–2346). Every field is optional:

```typescript
type QueryAgentsBodyParameters = {
  query?: string                 // case-insensitive substring over name and description
  filter?: AgentPropertyFilter
         | { and: Array<AgentPropertyFilter | { and: Array<AgentPropertyFilter> } | { or: Array<AgentPropertyFilter> }> }
         | { or:  Array<AgentPropertyFilter | { and: Array<AgentPropertyFilter> } | { or: Array<AgentPropertyFilter> }> }
  sorts?: Array<{ property: "created_time" | "last_run_at"; direction: "ascending" | "descending" }>
                                 // default: created_time descending
  start_cursor?: string | null
  page_size?: number             // max 100
  verbose?: boolean              // include inline instructions
  include_deleted?: boolean      // include soft-deleted agents
}
// AgentPropertyFilter is this plan's name for the leaf union that the SDK inlines in every position:
type AgentPropertyFilter =
  | { property: "id"; id: { equals: string } }
  | { property: "agent_type"; string: { equals: "notion_ai" | "custom_agent" | "autofill_custom_agent" } }
  | { property: "created_by"; people: { contains: string } }
  | { property: "created_time"; date: { after?: string; before?: string } }
  | { property: "favorited"; checkbox: { equals: boolean } }
  | { property: "connections"; mcp_server: { contains: string } }
  | { property: "status"; status: { in: Array<"active" | "disabled" | "deleted"> } }
  | { property: "model_mode"; select: { equals: "auto" | "pinned" } }
  | { property: "agent_version"; number: { equals: number } }
  | { property: "last_run_at"; date: { after?: string; before?: string } }
```

The response `QueryAgentsResponse` (lines 2350–3030) is `{object: "list", type: "agent", results: Array<...>, has_more: boolean, next_cursor: string | null}`. Each result is one of two variants.

The first variant is for custom and autofill agents. It is identical to `GetAgentResponse` except for these differences, verified by a line diff:

- `agent_type` is only `"custom_agent" | "autofill_custom_agent"`.
- `created_by` is `{type: "user" | "bot"; id} | null`, with no `object` key.
- There is no `version`, `has_unpublished_changes` or `last_run_time`.
- `created_time` and `last_edited_time` are required strings.
- `instructions?` is still present.

The second variant is the fixed personal agent:

```typescript
{
  object: "agent"
  id: "33333333-3333-3333-3333-333333333333"
  agent_type: "notion_ai"
  name: "Notion Agent"
  description: null
  instructions_page_id: null
  icon: PageIconResponse | { type: "custom_agent_avatar"; custom_agent_avatar: {...} }   // not nullable
  model: /* same as above */
  connections: /* same union as above */
  status: "active"
  pause_reason: null
  created_by: null
  agent_version: null
  created_time: null
  last_edited_time: null
  last_run_at: null
  credit_limit: null
  triggers: /* same as above */
}
```

#### Delete an agent

`DELETE agents/{agent_id}` (lines 668–694). The personal agent cannot be deleted. The deletion is a soft delete and is recoverable:

```typescript
type DeleteAgentResponse = { agent_id: IdResponse; status: "deleted"; deleted_at: string }
```

#### Insights

`GET agents/{agent_id}/insights` (lines 1182–1253). Its query parameters are `start_time?: number` and `end_time?: number`, both epoch seconds. They must be supplied together; if either is omitted, the window defaults to the current billing period.

```typescript
type GetInsightsResponse = {
  object: "agent_insights"
  id: IdResponse
  name: string
  agent_type: "custom_agent" | "autofill_custom_agent"
  status: "active" | "disabled" | "deleted"
  pause_reason: /* same 15 literals */ | null
  created_by: { id: string; type: "user" | "bot" } | null
  total_credits_used: number
  credit_limit: number | "hidden" | null
  runs_completed: number
}
```

#### Update status

`PATCH agents/{agent_id}/status` (lines 4993–5047):

```typescript
type UpdateAgentStatusBodyParameters = { status: "active" | "disabled" }
type UpdateAgentStatusResponse = {
  agent_id: IdResponse
  status: "active" | "disabled" | "deleted"
  pause_reason: /* same 15 literals */ | null
  last_edited_time: string
}
```

#### Update credit limit

`PATCH agents/{agent_id}/credit_limit` (lines 4958–4991). The personal agent is not supported:

```typescript
type UpdateAgentCreditLimitBodyParameters = { credit_limit: number | null }  // null clears the limit
type UpdateAgentCreditLimitResponse = {
  agent_id: IdResponse
  credit_limit: number | null        // note: never "hidden" here
  last_edited_time: string
}
```

#### Batch

`POST agents/batch` (lines 354–426). The batch is not atomic: operations apply in order, each succeeds or fails on its own, and outcomes are reported in the async task's result.

```typescript
type AgentBatchBodyParameters = {
  operations: Array<   // 1..100
    | { action: "update_status"; agent_id: AgentIdParam; fields: { status: "active" | "disabled" } }
    | { action: "update_credit_limit"; agent_id: AgentIdParam; fields: { credit_limit: number | null } }
    | { action: "delete"; agent_id: AgentIdParam }
  >
}
type AgentBatchResponse = {
  object: "async_task"
  id: string
  status_url: string
  created_time: string
  operation: { surface: "rest" | "mcp"; name: string }
  status: "queued" | "running" | "retrying"
  poll_after_seconds: number
}
```

The JS test at `test/Client.test.ts` line 506 expects this exact request body for one operation:

```json
{"operations":[{"action":"update_status","agent_id":"notion_ai","fields":{"status":"disabled"}}]}
```

It also expects `PATCH .../credit_limit` with body `{"credit_limit":1000}` and `PATCH .../status` with body `{"status":"disabled"}` (lines 581–596).

### Terms used in this plan

- A **tolerant decoder** is a `FromJSON` instance that never fails on a value Notion might add later. It maps the value to a fallback constructor that carries the raw `Text` or `Value`.
- A **hideable field** is one where Notion sends the literal string `"hidden"` instead of the real value because the caller lacks access.
- **Lockstep** means changing `Methods` and the effectful package together, in the same commit.
- An **async task** is a server-side job whose ID is returned immediately. The caller polls it with `GET async_tasks/{task_id}`.


## Plan of Work

The work has four milestones. Milestone 1 adds types and decoders only, with no network code, so that the fastest-changing part (the agent object) is pinned by tests before any endpoint depends on it. Milestones 2 and 3 add endpoints in two groups of three. Milestone 4 adds batch, which depends on a type owned by another plan.

### Milestone 1: pre-flight, shared primitives and the agent object

Scope: confirm the upstream contract has not drifted, create the shared primitive module (or reuse it), and define `Agent` with fully tolerant decoding. At the end, `cabal test` runs an `Agents` group that decodes a retrieved custom agent, a query-result custom agent, the personal `notion_ai` agent, and a fixture full of unknown enum values. No `Methods` field changes yet.

**Pre-flight re-diff.** Run the commands under Concrete Steps, Milestone 1. If `git log 978d690e..HEAD` lists any commit touching `src/api-endpoints/agents.ts`, `src/api-endpoint-methods.ts` or the agent tests, read the diff. Compare it with the TypeScript snippets in Context and Orientation, and record each difference in Surprises & Discoveries: added or removed fields, widened enums, renamed routes. Then update the snippets, the Haskell types below and the fixtures before writing code. A removed field becomes `Maybe` (or stays `Maybe`). An added enum literal becomes a new named constructor, and the `Unknown` fallback stays. If a route is removed from the facade, drop it from this plan and log the decision.

**Shared primitives.** The definitions of `src/Notion/V1/Agents/Common.hs` are fixed jointly with the sibling plan `docs/plans/13-add-session-endpoints-and-session-event-types.md`. This plan must use exactly the same names, constructors and field names, and must not add a second definition of any of them. First check whether the file exists:

- If it exists, EP-2 created it. Import from it, and only confirm that `ModelSelection` accepts both wire forms (the agent form is exercised by this plan's tests). If a decoder branch is missing, add it without renaming anything, and record that in the Decision Log.
- If it does not exist, create it with module name `Notion.V1.Agents.Common`, with exactly the content below (transcribed from that plan), and add it to `exposed-modules`.

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

Write the instances by hand in the same module:

- `ModelSelection` (`FromJSON` only). Read the discriminator with `o .:? "mode"`, falling back to `o .:? "type"`. `"auto"` gives `ModelAuto`. For `"pinned"`, read `ids` if present (`o .:? "ids"`); otherwise wrap the nullable `id` in a one-element vector. Any other discriminator, or a non-object, gives `UnknownModelSelection` carrying the whole value.
- `CreatedByType`: `"user"` gives `CreatedByUser`, `"bot"` gives `CreatedByBot`, and any other string gives `UnknownCreatedByType`. Its `ToJSON` inverts this mapping.
- `CreatedByRef`: read `id` and `type`. Any extra `object` key, which the retrieve-agent response sends, is ignored.
- `AgentVersionRef`: read `id` and `number`, and read `published_at` through `parseISO8601`.
- `Hideable a`: `String "hidden"` gives `Hidden`; anything else gives `Visible <$> parseJSON v`.

For example, the `ModelSelection` instance:

```haskell
instance FromJSON ModelSelection where
  parseJSON = \case
    v@(Object o) -> do
      mMode <- o .:? "mode"
      mType <- o .:? "type"
      case (maybe mType Just mMode :: Maybe Text) of
        Just "auto" -> pure ModelAuto
        Just "pinned" -> do
          mIds <- o .:? "ids"
          case mIds of
            Just ids -> pure (ModelPinned ids)
            Nothing -> ModelPinned . pure <$> (o .:? "id" :: Parser (Maybe Text))
        _ -> pure (UnknownModelSelection v)
    v -> pure (UnknownModelSelection v)
```

This plan needs a few helpers that the shared module does not provide. They go in this plan's own module `Notion.V1.Agents`, not in `Common.hs`, so the shared file stays identical to the sibling plan's definition:

```haskell
-- | The legacy reserved ID of the personal agent (query results return this as its id).
legacyNotionAiAgentId :: AgentId
legacyNotionAiAgentId = AgentId "33333333-3333-3333-3333-333333333333"

-- | Like the 'Hideable' FromJSON instance, but with a custom parser for the visible value
-- (needed for ISO 8601 timestamps, which have no suitable FromJSON instance).
parseHideable :: (Value -> Parser a) -> Value -> Parser (Hideable a)
parseHideable _ (String "hidden") = pure Hidden
parseHideable p v = Visible <$> p v

parseTimestampValue :: Value -> Parser POSIXTime
parseTimestampValue = withText "timestamp" parseISO8601
```

Export `legacyNotionAiAgentId`. Keep `parseHideable` and `parseTimestampValue` internal. To build an `AgentId` from a `UUID`, write `AgentId (text uuid)`; both newtypes have a field named `text`, which `DuplicateRecordFields` permits.

**The agent object.** Create `src/Notion/V1/Agents.hs` with module name `Notion.V1.Agents`, starting with `import Prelude hiding (id)`. It imports `Notion.V1.Agents.Common`, `Notion.V1.Common (Icon, UUID)`, `Notion.V1.ListOf (ListOf)`, `Data.Aeson (object, withObject, withText, (.:), (.:?), (.!=), (.=))`, `Data.Aeson.Types (Parser)`, `Data.Foldable (asum)` and `Data.Scientific (Scientific)`. Define these types, all deriving `stock (Eq, Show)`:

```haskell
data AgentType
  = NotionAiAgent            -- "notion_ai"
  | CustomAgent              -- "custom_agent"
  | AutofillCustomAgent      -- "autofill_custom_agent"
  | ExternalAgent            -- "external"
  | UnknownAgentType Text

data AgentStatus
  = AgentActive | AgentDisabled | AgentDeleted | UnknownAgentStatus Text

data PauseReason
  = PauseRunLimit                          -- "run_limit"
  | PauseCreditLimit                       -- "credit_limit"
  | PauseRunawayCreditUsage                -- "runaway_credit_usage"
  | PauseWorkspaceCreditLimit              -- "workspace_credit_limit"
  | PauseFailureLimit                      -- "failure_limit"
  | PauseMarkSessionFailedAutopause        -- "mark_session_failed_autopause"
  | PauseDisabledFromWorkspaceSettings     -- "disabled_from_workspace_settings"
  | PauseDisabledFromApi                   -- "disabled_from_api"
  | PauseDisabledFromAgentSettings         -- "disabled_from_agent_settings"
  | PauseDisabledDueToNoMembersWithAccess  -- "disabled_due_to_no_members_with_access"
  | PauseDisabledDueToLackOfEditors        -- "disabled_due_to_lack_of_editors"
  | PauseDisabledByNotion                  -- "disabled_by_notion"
  | PauseInternalError                     -- "internal_error"
  | PauseNeedsUserReview                   -- "needs_user_review"
  | PauseToolUnavailable                   -- "tool_unavailable"
  | UnknownPauseReason Text

data AgentIcon
  = AgentPageIcon Icon
  | CustomAgentAvatar {staticUrl :: Text, animatedUrl :: Text}
  | UnknownAgentIcon Value

-- | One target/scopes grant. The target type differs per connection kind.
data Permission target = Permission {target :: target, scopes :: Vector Text}

data NotionTarget
  = NotionPageTarget {id :: Text}
  | NotionDatabasePropertyTarget {dataSourceId :: Text, propertyId :: Text}
  | NotionAgentTarget {id :: Text}
  | NotionWorkspaceTarget
  | NotionOwnerPrivatePagesTarget
  | NotionWebSearchTarget {allowedDomains :: Maybe (Vector Text)}  -- Nothing = unrestricted
  | NotionHelpDocsSearchTarget
  | UnknownNotionTarget Value

data SlackTarget
  = SlackChannelTarget {id :: Text}
  | SlackAllPublicChannelsTarget
  | SlackAllChannelsTarget
  | UnknownSlackTarget Value

data DiscordTarget
  = DiscordChannelTarget {id :: Text}
  | DiscordAllChannelsTarget
  | UnknownDiscordTarget Value

-- | Target of a generic connector grant; @id@ is optional for tolerance.
data ConnectorTarget = ConnectorTarget {type_ :: Text, id :: Maybe Text}

newtype SlackWorkspace = SlackWorkspace {teamId :: Text}
newtype DiscordServer = DiscordServer {id :: Text}
newtype McpServerAccount = McpServerAccount {serverHost :: Text}
data McpTool = McpTool {name :: Text, title :: Maybe Text}
data RunToolsAutomatically = RunToolsAutomatically {read :: Bool, write :: Bool}

data NotionConnection = NotionConnection
  {name :: Text, permissions :: Vector (Permission NotionTarget)}

data SlackConnection = SlackConnection
  {name :: Text, account :: Maybe (Hideable SlackWorkspace), permissions :: Vector (Permission SlackTarget)}

data DiscordConnection = DiscordConnection
  {name :: Text, account :: Maybe (Hideable DiscordServer), permissions :: Vector (Permission DiscordTarget)}

data McpServerConnection = McpServerConnection
  { name :: Text,
    account :: Maybe (Hideable McpServerAccount),
    -- | 'Nothing' means every tool is enabled, including tools the server adds later.
    enabledTools :: Maybe (Hideable (Vector McpTool)),
    runToolsAutomatically :: RunToolsAutomatically
  }

-- | A generic connector such as @github@ or @jira@. @account@ may be the text "hidden".
data ConnectorConnection = ConnectorConnection
  {type_ :: Text, name :: Text, account :: Maybe Text, permissions :: Vector (Permission ConnectorTarget)}

data AgentConnection
  = ConnectionNotion NotionConnection
  | ConnectionSlack SlackConnection
  | ConnectionDiscord DiscordConnection
  | ConnectionMcpServer McpServerConnection         -- "mcp_server"
  | ConnectionCustomMcpServer McpServerConnection   -- "custom_mcp_server"
  | ConnectionConnector ConnectorConnection         -- any other type with the generic shape
  | UnknownConnection Value                         -- anything that fails all of the above

data ScheduleEnd
  = ScheduleEndsAt Text          -- {"type":"date","end_at":...}
  | ScheduleEndsAfter Natural    -- {"type":"count","occurrences":...}
  | UnknownScheduleEnd Value

data TriggerSchedule = TriggerSchedule
  { frequency :: Text,
    interval :: Natural,
    weekdays :: Maybe (Vector Text),
    monthdays :: Maybe (Vector Int),
    weekNumbers :: Maybe (Vector Int),
    hour :: Maybe Natural,
    minute :: Maybe Natural,
    timezone :: Maybe Text,
    startDate :: Maybe Text,
    end :: Maybe ScheduleEnd
  }

data AgentTrigger = AgentTrigger
  {type_ :: Text, enabled :: Bool, schedule :: Maybe TriggerSchedule, config :: Maybe Value}

data Agent = Agent
  { id :: AgentId,
    agentType :: AgentType,
    name :: Text,
    description :: Maybe Text,
    instructionsPageId :: Maybe UUID,
    icon :: Maybe AgentIcon,
    model :: ModelSelection,
    connections :: Vector AgentConnection,
    status :: AgentStatus,
    pauseReason :: Maybe PauseReason,
    createdBy :: Maybe CreatedByRef,
    -- | Retrieve only.
    version :: Maybe AgentVersionRef,
    agentVersion :: Maybe AgentVersionRef,
    -- | Retrieve only.
    hasUnpublishedChanges :: Maybe (Hideable Bool),
    -- | Retrieve only.
    lastRunTime :: Maybe (Hideable POSIXTime),
    lastRunAt :: Maybe (Hideable POSIXTime),
    creditLimit :: Maybe (Hideable Scientific),
    triggers :: Vector AgentTrigger,
    -- | Null for the personal agent; absent in older retrieve responses.
    createdTime :: Maybe POSIXTime,
    lastEditedTime :: Maybe POSIXTime,
    -- | Present only when requested with verbose = true.
    instructions :: Maybe Text
  }
```

The `read` field in `RunToolsAutomatically` shadows `Prelude.read`. If GHC reports an ambiguity where it is used, extend the hiding clause to `import Prelude hiding (id, read)`. Fields such as `name`, `id`, `type_`, `account` and `permissions` repeat across records; `DuplicateRecordFields` allows that because each record is a separate type. That is also why connections are separate record types wrapped by `AgentConnection`, rather than one sum type with conflicting field types.

Decoding rules for `Notion.V1.Agents`:

- Enums (`AgentType`, `AgentStatus`, `PauseReason`) use `withText` and a `\case` whose last branch is `other -> pure (UnknownX other)`. Give them `ToJSON` instances too (the unknown constructor writes its raw text back), because Milestone 2's filter encodes them.
- Tagged objects (`AgentIcon`, `NotionTarget`, `SlackTarget`, `DiscordTarget`, `ScheduleEnd`, `AgentConnection`) use `parseJSON v = asum [typed v, pure (UnknownX v)]`. `typed` reads `"type"` and dispatches.
- `AgentIcon`'s `typed` returns `CustomAgentAvatar` for `"custom_agent_avatar"` and otherwise `AgentPageIcon <$> parseJSON v`. A custom-emoji icon therefore currently falls through to `UnknownAgentIcon`, as explained in Context.
- `AgentConnection`'s `typed` maps `"notion"`, `"slack"`, `"discord"`, `"mcp_server"` and `"custom_mcp_server"` to their records, and any other type string to `ConnectionConnector <$> parseJSON v`. If that parse fails (for example a future connector with an object `account`), `asum` falls back to `UnknownConnection v`.
- Hideable nullable fields use `.:?` to get a `Maybe Value`, then `traverse (parseHideable parser)`. `.:?` already yields `Nothing` for both absent and `null`. For example:

```haskell
instance FromJSON Agent where
  parseJSON = withObject "Agent" $ \o -> do
    id <- o .: "id"
    agentType <- o .: "agent_type"
    name <- o .: "name"
    description <- o .:? "description"
    instructionsPageId <- o .:? "instructions_page_id"
    icon <- o .:? "icon"
    model <- o .: "model"
    connections <- o .:? "connections" .!= mempty
    status <- o .: "status"
    pauseReason <- o .:? "pause_reason"
    createdBy <- o .:? "created_by"
    version <- o .:? "version"
    agentVersion <- o .:? "agent_version"
    hasUnpublishedChanges <- o .:? "has_unpublished_changes"
    lastRunTime <- hideableTime o "last_run_time"
    lastRunAt <- hideableTime o "last_run_at"
    creditLimit <- o .:? "credit_limit"
    triggers <- o .:? "triggers" .!= mempty
    createdTime <- (o .:? "created_time") >>= traverse parseISO8601
    lastEditedTime <- (o .:? "last_edited_time") >>= traverse parseISO8601
    instructions <- o .:? "instructions"
    pure Agent {..}
    where
      hideableTime obj key =
        (obj .:? key :: Parser (Maybe Value)) >>= traverse (parseHideable parseTimestampValue)
```

`Permission`, `ConnectorTarget`, `McpTool`, `RunToolsAutomatically`, the account newtypes, `TriggerSchedule` and `AgentTrigger` are plain objects decoded with `withObject` and `.:`/`.:?`. Use `.:?` for every key the JS type marks optional, and also for `ConnectorTarget.id`.

Export all of these types with `(..)` from `Notion.V1.Agents`, and re-export the `Notion.V1.Agents.Common` names so users need only one import. Add both modules to `exposed-modules` in `notion-client.cabal`, keeping alphabetical order: `Notion.V1.Agents` and `Notion.V1.Agents.Common`, after `Notion.V1`. If Milestone 1 defines no `API` yet, do not export one; it is added in Milestone 2.

**Tests.** Create `tasty/AgentsTests.hs` (see Concrete Steps for the fixtures and assertions). Register it in the cabal file and in `tasty/Main.hs`.

Acceptance: `cabal build all` succeeds, and `cabal test` shows the `Agents / Agent object` tests passing.

### Milestone 2: query, retrieve and delete

Scope: the first three endpoints, end to end. At the end, `queryAgents`, `retrieveAgent` and `deleteAgent` exist on `Methods` and in the effectful package, and tests prove the request bodies and the list decoding.

In `src/Notion/V1/Agents.hs` add the request and response types:

```haskell
-- | Body of @POST /v1/agents/query@. Use 'emptyQueryAgents' and record update.
data QueryAgents = QueryAgents
  { query :: Maybe Text,
    filter :: Maybe AgentFilter,
    sorts :: Maybe [AgentSort],
    startCursor :: Maybe Text,
    pageSize :: Maybe Natural,      -- maximum 100
    verbose :: Maybe Bool,
    includeDeleted :: Maybe Bool
  }
  deriving stock (Eq, Generic, Show)

instance ToJSON QueryAgents where
  toJSON = genericToJSON aesonOptions   -- omits Nothing fields

emptyQueryAgents :: QueryAgents
emptyQueryAgents = QueryAgents Nothing Nothing Nothing Nothing Nothing Nothing Nothing

data ModelMode = ModelModeAuto | ModelModePinned
  deriving stock (Eq, Show)

-- | Agent query filter. Notion accepts at most two levels of and/or nesting;
-- deeper filters are rejected by the server with a validation error.
data AgentFilter
  = AgentIdEquals AgentId                          -- {"property":"id","id":{"equals":..}}
  | AgentTypeEquals AgentType                      -- {"property":"agent_type","string":{"equals":..}}
  | CreatedByContains UUID                         -- {"property":"created_by","people":{"contains":..}}
  | CreatedTimeRange (Maybe Text) (Maybe Text)     -- {"property":"created_time","date":{"after"?,"before"?}}
  | FavoritedEquals Bool                           -- {"property":"favorited","checkbox":{"equals":..}}
  | ConnectionsMcpServerContains Text              -- {"property":"connections","mcp_server":{"contains":..}}
  | StatusIn [AgentStatus]                         -- {"property":"status","status":{"in":[..]}}
  | ModelModeEquals ModelMode                      -- {"property":"model_mode","select":{"equals":"auto"|"pinned"}}
  | AgentVersionEquals Natural                     -- {"property":"agent_version","number":{"equals":..}}
  | LastRunAtRange (Maybe Text) (Maybe Text)       -- {"property":"last_run_at","date":{"after"?,"before"?}}
  | AgentFilterAnd [AgentFilter]                   -- {"and":[..]}
  | AgentFilterOr [AgentFilter]                    -- {"or":[..]}
  | AgentFilterRaw Value                           -- sent verbatim
  deriving stock (Eq, Show)

data AgentSortProperty = AgentSortCreatedTime | AgentSortLastRunAt | AgentSortOther Text
  deriving stock (Eq, Show)

data AgentSort = AgentSort {property :: AgentSortProperty, direction :: SortDirection}
  deriving stock (Eq, Show)

data DeletedAgent = DeletedAgent
  {agentId :: AgentId, status :: Text, deletedAt :: POSIXTime}
  deriving stock (Eq, Show)
```

Write `ToJSON AgentFilter` by hand with `object` and `.=`, following the comments above. In the two date-range constructors, omit a `Nothing` bound from the inner object (build the pair list with `maybe [] (\t -> ["after" .= t]) after`). `ToJSON AgentSort` writes `{"property": "created_time" | "last_run_at" | <other>, "direction": ...}`, where the direction comes from `Notion.V1.Filter.SortDirection`'s own `ToJSON`, imported with `import Notion.V1.Filter (SortDirection (..))`. The date bounds are ISO 8601 strings such as `"2026-09-01T00:00:00Z"`, matching `Notion.V1.Filter.DateCondition`, which also uses `Text`. `FromJSON DeletedAgent` reads `agent_id`, `status` and `deleted_at` (via `parseISO8601`).

Add the Servant API at the bottom of `src/Notion/V1/Agents.hs` and export `API`:

```haskell
type API =
  "agents"
    :> ( "query"
           :> ReqBody '[JSON] QueryAgents
           :> Post '[JSON] (ListOf Agent)
           :<|> Capture "agent_id" AgentId
             :> QueryParam "verbose" Bool
             :> Get '[JSON] Agent
           :<|> Capture "agent_id" AgentId
             :> Delete '[JSON] DeletedAgent
       )
```

`servant-client` only builds requests; it never matches incoming routes. A literal segment `"query"` next to a `Capture` is therefore not ambiguous for the client, and route order only has to match the destructuring in `makeMethods`.

In `src/Notion/V1.hs`, make four changes:

- Import `Notion.V1.Agents (Agent, AgentId, DeletedAgent)` and `Notion.V1.Agents qualified as Agents`.
- Append `:<|> Agents.API` as the last alternative of `type API`.
- Append a matching group to the destructuring pattern in `makeMethods`, after the file-uploads group:

```haskell
        :<|> ( queryAgents
                 :<|> retrieveAgent
                 :<|> deleteAgent
               )
```

- Add the fields to `data Methods`, after the file-uploads fields, under a `-- \* Agents` comment:

```haskell
    -- \* Agents
    -- | Query the workspace's custom agents (POST /v1/agents/query).
    queryAgents :: Agents.QueryAgents -> IO (ListOf Agent),
    retrieveAgent ::
      AgentId ->
      Maybe Bool ->
      -- \^ verbose: include inline instructions
      IO Agent,
    -- | Soft-delete an agent. The personal agent cannot be deleted.
    deleteAgent :: AgentId -> IO DeletedAgent
```

Remember that the previous last field, `listFileUploads`, now needs a trailing comma.

In `notion-client-effectful/src/Notion/V1/Effectful/Effect.hs`:

- Import `Notion.V1.Agents (Agent, AgentId, DeletedAgent)` and `Notion.V1.Agents qualified as Agents`.
- Add the GADT constructors `QueryAgents :: Agents.QueryAgents -> Notion m (ListOf Agent)`, `RetrieveAgent :: AgentId -> Maybe Bool -> Notion m Agent` and `DeleteAgent :: AgentId -> Notion m DeletedAgent` under a `-- Agents` comment.
- Add an `-- * Agents` export section listing `queryAgents`, `retrieveAgent` and `deleteAgent`.
- Add the smart constructors under a `-- ── Agents ──` banner, in the style of `listCustomEmojis`, for example `queryAgents :: (Notion :> es) => Agents.QueryAgents -> Eff es (ListOf Agent)`.

In `Interpreter.hs`, add `DeleteAgent`, `QueryAgents` and `RetrieveAgent` to the alphabetical constructor import list, and add these cases:

```haskell
  -- Agents
  QueryAgents req -> runIO (Notion.queryAgents methods req)
  RetrieveAgent aid verbose -> runIO (Notion.retrieveAgent methods aid verbose)
  DeleteAgent aid -> runIO (Notion.deleteAgent methods aid)
```

Add Milestone 2 tests to `tasty/AgentsTests.hs` (see Concrete Steps).

Acceptance: `cabal build all` succeeds with no new warnings, and `cabal test` shows the `Agents / Query, retrieve, delete` tests passing.

### Milestone 3: insights, status, credit limit and the demo

Scope: the three remaining non-batch endpoints and a read-only demo. At the end, six of the seven facade methods work.

In `src/Notion/V1/Agents.hs` add:

```haskell
-- | Insights window in epoch seconds. Both bounds are sent together.
data InsightsWindow = InsightsWindow {startTime :: Integer, endTime :: Integer}
  deriving stock (Eq, Show)

data AgentInsights = AgentInsights
  { id :: AgentId,
    name :: Text,
    agentType :: AgentType,
    status :: AgentStatus,
    pauseReason :: Maybe PauseReason,
    createdBy :: Maybe CreatedByRef,
    totalCreditsUsed :: Scientific,
    creditLimit :: Maybe (Hideable Scientific),
    runsCompleted :: Natural
  }
  deriving stock (Eq, Show)

data TargetAgentStatus = SetAgentActive | SetAgentDisabled
  deriving stock (Eq, Show)
-- ToJSON: "active" / "disabled"

newtype UpdateAgentStatus = UpdateAgentStatus {status :: TargetAgentStatus}
  deriving stock (Eq, Show)
-- ToJSON: {"status": ...}

data AgentStatusUpdated = AgentStatusUpdated
  {agentId :: AgentId, status :: AgentStatus, pauseReason :: Maybe PauseReason, lastEditedTime :: POSIXTime}
  deriving stock (Eq, Show)

-- | 'Nothing' clears the limit and is sent as an explicit JSON null.
newtype UpdateAgentCreditLimit = UpdateAgentCreditLimit {creditLimit :: Maybe Natural}
  deriving stock (Eq, Show)

instance ToJSON UpdateAgentCreditLimit where
  toJSON UpdateAgentCreditLimit {creditLimit} = object ["credit_limit" .= creditLimit]

data AgentCreditLimitUpdated = AgentCreditLimitUpdated
  {agentId :: AgentId, creditLimit :: Maybe Scientific, lastEditedTime :: POSIXTime}
  deriving stock (Eq, Show)
```

`Maybe Natural` with `.=` encodes `Nothing` as `null`; the explicit `object` avoids `omitNothingFields`. Write `FromJSON` for the three response types with `withObject`. `UpdateAgentStatus` and `TargetAgentStatus` get hand-written `ToJSON`.

Extend `type API` inside the `"agents"` group, after the delete route:

```haskell
           :<|> Capture "agent_id" AgentId
             :> "insights"
             :> QueryParam "start_time" Integer
             :> QueryParam "end_time" Integer
             :> Get '[JSON] AgentInsights
           :<|> Capture "agent_id" AgentId
             :> "status"
             :> ReqBody '[JSON] UpdateAgentStatus
             :> Patch '[JSON] AgentStatusUpdated
           :<|> Capture "agent_id" AgentId
             :> "credit_limit"
             :> ReqBody '[JSON] UpdateAgentCreditLimit
             :> Patch '[JSON] AgentCreditLimitUpdated
```

In `makeMethods`, extend the agents group with `:<|> retrieveAgentInsights_ :<|> updateAgentStatus :<|> updateAgentCreditLimit`, and in the `where` block add:

```haskell
    retrieveAgentInsights aid window =
      retrieveAgentInsights_ aid (startTime <$> window) (endTime <$> window)
      where
        startTime Agents.InsightsWindow {startTime = s} = s
        endTime Agents.InsightsWindow {endTime = e} = e
```

The local helpers avoid ambiguous-selector errors, since `startTime` may exist on other records. Add these `Methods` fields:

```haskell
    -- | Usage insights; 'Nothing' means the current billing period.
    retrieveAgentInsights :: AgentId -> Maybe Agents.InsightsWindow -> IO Agents.AgentInsights,
    updateAgentStatus :: AgentId -> Agents.UpdateAgentStatus -> IO Agents.AgentStatusUpdated,
    -- | Not supported for the personal agent.
    updateAgentCreditLimit :: AgentId -> Agents.UpdateAgentCreditLimit -> IO Agents.AgentCreditLimitUpdated
```

Apply the lockstep in the effectful package:

- Constructors: `RetrieveAgentInsights :: AgentId -> Maybe Agents.InsightsWindow -> Notion m Agents.AgentInsights`, `UpdateAgentStatus :: AgentId -> Agents.UpdateAgentStatus -> Notion m Agents.AgentStatusUpdated` and `UpdateAgentCreditLimit :: AgentId -> Agents.UpdateAgentCreditLimit -> Notion m Agents.AgentCreditLimitUpdated`.
- Smart constructors `retrieveAgentInsights`, `updateAgentStatus` and `updateAgentCreditLimit`, with exports.
- Interpreter imports and cases.

Create `notion-client-example/AgentDemo.hs` exporting `runAgentDemo :: Methods -> IO ()`:

- Print a header with `printHeader`.
- Call `queryAgents methods emptyQueryAgents {pageSize = Just 10}` inside `Control.Exception.try @NotionError`, so a workspace or token without agent access prints the error `code` and `message` and returns instead of aborting the whole example.
- For each result, print `name`, `agentType`, `status` and `pauseReason`.
- For the first custom agent (skip `NotionAiAgent`), call `retrieveAgent methods aid (Just True)` and print whether `instructions` is present. Then call `retrieveAgentInsights methods aid Nothing` and print `totalCreditsUsed`, `runsCompleted` and `creditLimit`.

In `notion-client-example/Main.hs`, after `runCustomEmojiDemo methods`, add:

```haskell
  agentDemoEnv <- Environment.lookupEnv "NOTION_AGENT_DEMO"
  when (agentDemoEnv == Just "1") $ runAgentDemo methods
```

Also add `AgentDemo` to the example's `other-modules` in `notion-client.cabal`, and mention `NOTION_AGENT_DEMO=1` in the header comment of `Main.hs`. If `docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md` has landed and `NotionError.code` is a typed value, print it with `show`.

Add CHANGELOG entries in both packages under `## Unreleased` / `### New Features` (and `### Breaking Changes`, see Interfaces and Dependencies).

Acceptance: `cabal build all` succeeds; `cabal test` shows the `Agents / Insights, status, credit limit` tests passing; with a suitable token, the demo prints agents (see Validation and Acceptance).

### Milestone 4: batch operations

Scope: `POST agents/batch`, returning the async task type owned by `docs/plans/8-add-comment-mutation-async-task-and-meeting-notes-endpoints.md`.

**Precondition.** Run the check under Concrete Steps, Milestone 4. If `src/Notion/V1/AsyncTasks.hs` does not exist or does not export `AsyncTask`, stop. Mark this milestone blocked in Progress, note it in Surprises & Discoveries, and do not define a local async-task type. Everything from Milestones 1–3 remains shippable. If the module exists, read `AsyncTask`'s fields and its `FromJSON` instance before writing the test. Adapt the test's assertions to the actual field names, and confirm it decodes the batch response shape transcribed in Context (`object`, `id`, `status_url`, `created_time`, `operation{surface,name}`, `status`, `poll_after_seconds`). If it cannot decode that shape, record the gap in Surprises & Discoveries and raise it with that plan's owner rather than patching around it here.

Add to `src/Notion/V1/Agents.hs`:

```haskell
data AgentOperation
  = BatchUpdateStatus AgentId TargetAgentStatus
  | BatchUpdateCreditLimit AgentId (Maybe Natural)   -- Nothing = clear, sent as null
  | BatchDelete AgentId
  deriving stock (Eq, Show)

instance ToJSON AgentOperation where
  toJSON = \case
    BatchUpdateStatus aid s ->
      object ["action" .= ("update_status" :: Text), "agent_id" .= aid, "fields" .= object ["status" .= s]]
    BatchUpdateCreditLimit aid l ->
      object ["action" .= ("update_credit_limit" :: Text), "agent_id" .= aid, "fields" .= object ["credit_limit" .= l]]
    BatchDelete aid ->
      object ["action" .= ("delete" :: Text), "agent_id" .= aid]

-- | 1 to 100 operations, applied in order, not atomically.
newtype AgentBatch = AgentBatch {operations :: NonEmpty AgentOperation}
  deriving stock (Eq, Show)

instance ToJSON AgentBatch where
  toJSON AgentBatch {operations} = object ["operations" .= operations]

-- | Validates the 1..100 bound documented by Notion.
mkAgentBatch :: [AgentOperation] -> Either Text AgentBatch
mkAgentBatch = \case
  [] -> Left "agent batch needs at least one operation"
  ops@(o : os)
    | length ops > 100 -> Left "agent batch accepts at most 100 operations"
    | otherwise -> Right (AgentBatch (o :| os))
```

`AgentBatch`'s constructor stays exported, so callers who build a `NonEmpty` themselves can skip the smart constructor; the 100 limit is then enforced by the server.

Append the batch route as the last alternative inside the `"agents"` group: `:<|> "batch" :> ReqBody '[JSON] AgentBatch :> Post '[JSON] AsyncTask`, importing `Notion.V1.AsyncTasks (AsyncTask)`. **Before writing this route, read [docs/adr/3-background-operations-accept-200-or-202-and-return-asyncor.md](../adr/3-background-operations-accept-200-or-202-and-return-asyncor.md).** Notion answers queued work with HTTP 202, and a `Post '[JSON]` route accepts only 200, so this route as written would throw `UnknownHTTPResponseError` on a successful batch. Use `UVerb 'POST '[JSON] '[WithStatus 200 AsyncTask, WithStatus 202 AsyncTask]` (from `Servant.API` and `Servant.API.UVerb`), and collapse the `Union` in `makeMethods` the same way `fromAsyncUnion` does in `src/Notion/V1/AsyncTasks.hs`, so `batchAgents` keeps the type `IO AsyncTask`. Confirm the status live once. A `FakeNotion` test cannot catch this, because its middleware bypasses servant's status check. Extend the `makeMethods` pattern with `:<|> batchAgents`. Add the `Methods` field:

```haskell
    -- | Apply up to 100 agent operations; poll the returned task with 'retrieveAsyncTask'.
    batchAgents :: Agents.AgentBatch -> IO AsyncTask
```

Then apply the effectful lockstep: constructor `BatchAgents :: Agents.AgentBatch -> Notion m AsyncTask`, smart constructor `batchAgents`, interpreter case `BatchAgents req -> runIO (Notion.batchAgents methods req)`.

Add the batch tests and the CHANGELOG entry.

Acceptance: `cabal build all` succeeds, and `cabal test` shows the `Agents / Batch` tests passing, including one whose encoded body equals the JS SDK test's body.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client` unless stated otherwise.

### Milestone 1

Pre-flight re-diff against the drafting baseline:

```bash
git -C /Users/shinzui/Keikaku/hub/notion-sdk-js pull
git -C /Users/shinzui/Keikaku/hub/notion-sdk-js log --oneline 978d690e60009b493751b28a9d87a026a32e7286..HEAD -- src/api-endpoints/agents.ts src/api-endpoint-methods.ts src/Client.ts test/Client.test.ts
git -C /Users/shinzui/Keikaku/hub/notion-sdk-js diff 978d690e60009b493751b28a9d87a026a32e7286..HEAD -- src/api-endpoints/agents.ts
grep -n "export type GetAgentResponse\|type QueryAgentsBodyParameters\|export type QueryAgentsResponse\|export type GetInsightsResponse\|export type DeleteAgentResponse\|type AgentBatchBodyParameters\|export type UpdateAgentCreditLimitResponse\|export type UpdateAgentStatusResponse" /Users/shinzui/Keikaku/hub/notion-sdk-js/src/api-endpoints/agents.ts
```

If the `log` command prints nothing, there is no drift. Expected `grep` output at the baseline (the line numbers move if the file changed):

```text
354:type AgentBatchBodyParameters = {
676:export type DeleteAgentResponse = {
710:export type GetAgentResponse = {
1202:export type GetInsightsResponse = {
2116:type QueryAgentsBodyParameters = {
2350:export type QueryAgentsResponse = {
4972:export type UpdateAgentCreditLimitResponse = {
5008:export type UpdateAgentStatusResponse = {
```

Check for the shared module:

```bash
test -f src/Notion/V1/Agents/Common.hs && echo "exists: import it" || echo "absent: create it"
```

Create `src/Notion/V1/Agents/Common.hs` and `src/Notion/V1/Agents.hs` as described in Plan of Work, then edit `notion-client.cabal`:

```diff
   exposed-modules:
     Notion.V1
+    Notion.V1.Agents
+    Notion.V1.Agents.Common
     Notion.V1.BlockContent
```

```diff
 test-suite tasty
   default-language:   GHC2024
   type:               exitcode-stdio-1.0
   hs-source-dirs:     tasty
   main-is:            Main.hs
+  other-modules:      AgentsTests
```

Create `tasty/AgentsTests.hs`:

```haskell
module AgentsTests (tests) where

import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy.Char8 qualified as L8
import Data.Vector qualified as Vector
import Notion.V1.Agents
import Test.Tasty
import Test.Tasty.HUnit
import Prelude hiding (id)

tests :: TestTree
tests =
  testGroup
    "Agents"
    [ testGroup
        "Agent object"
        [ testCase "decodes a retrieved custom agent" testRetrievedAgent,
          testCase "decodes the notion_ai personal agent from query results" testNotionAiAgent,
          testCase "decodes a query-result custom agent without retrieve-only fields" testQueryResultAgent,
          testCase "decodes unknown enum and union values into fallbacks" testUnknownValues,
          testCase "decodes session-style model selection" testSessionModelSelection
        ]
    ]

decodeOrFail :: (Aeson.FromJSON a) => L8.ByteString -> IO a
decodeOrFail bytes = either (assertFailure . ("decode failed: " <>)) pure (Aeson.eitherDecode bytes)
```

The retrieved-agent fixture is used by `testRetrievedAgent`. It is transcribed from `GetAgentResponse`, and all names are invented:

```json
{
  "object": "agent",
  "id": "5c1f2a0e-8d3b-4e61-9a7c-2b4d6e8f0a13",
  "agent_type": "custom_agent",
  "name": "Weekly Digest",
  "description": "Summarizes team notes for Tanaka Hanako",
  "instructions_page_id": "0b7e9d24-3f51-4c8a-b6d2-7e19a4c05f38",
  "icon": {"type": "custom_agent_avatar", "custom_agent_avatar": {"static_url": "https://example.com/a.png", "animated_url": "https://example.com/a.gif"}},
  "model": {"mode": "pinned", "id": "claude-sonnet-5"},
  "connections": [
    {"type": "notion", "name": "Notion", "account": null, "permissions": [
      {"target": {"type": "page", "id": "7a2c4e61-1b3d-4f5a-8c9e-0d1f2a3b4c5d"}, "scopes": ["read_and_write"]},
      {"target": {"type": "database_property", "data_source_id": "9e8d7c6b-5a49-4382-a716-f5e4d3c2b1a0", "property_id": "abc%3D"}, "scopes": ["editor"]},
      {"target": {"type": "web_search", "allowed_domains": null}, "scopes": ["allow"]},
      {"target": {"type": "notion_help_docs_search"}, "scopes": ["disallow"]}
    ]},
    {"type": "slack", "name": "Slack", "account": "hidden", "permissions": [
      {"target": {"type": "slack_channel", "id": "C0123456"}, "scopes": ["read", "reply_in_thread"]}
    ]},
    {"type": "mcp_server", "name": "Issue Tracker", "account": {"type": "mcp_server", "server_host": "mcp.example.com"},
     "enabled_tools": [{"name": "search_issues", "title": null}], "run_tools_automatically": {"read": true, "write": false}},
    {"type": "github", "name": "GitHub", "account": "sato-kenji", "permissions": [
      {"target": {"type": "repository", "id": "notion-client"}, "scopes": ["read"]}
    ]}
  ],
  "status": "disabled",
  "pause_reason": "credit_limit",
  "created_by": {"object": "user", "type": "user", "id": "d3b07384-d9a0-4c5e-9f1b-2a6c8e0f4b7d"},
  "version": {"id": "4f6a8c0e-2b4d-4e6f-8a0c-1e3b5d7f9a2c", "number": 3, "published_at": "2026-09-01T10:00:00.000Z"},
  "agent_version": {"id": "4f6a8c0e-2b4d-4e6f-8a0c-1e3b5d7f9a2c", "number": 3, "published_at": "2026-09-01T10:00:00.000Z"},
  "has_unpublished_changes": false,
  "last_run_time": "hidden",
  "last_run_at": "2026-09-12T07:30:00.000+00:00",
  "credit_limit": 5000,
  "triggers": [
    {"type": "recurrence", "enabled": true, "schedule": {"frequency": "week", "interval": 1, "weekdays": ["monday"], "hour": 9, "minute": 0,
      "timezone": "Asia/Tokyo", "start_date": "2026-09-07T00:00:00.000Z", "end": {"type": "count", "occurrences": 10}}},
    {"type": "notion.agent.mentioned", "enabled": false}
  ],
  "created_time": "2026-08-20T03:00:00.000Z",
  "last_edited_time": "2026-09-12T07:00:00.000Z",
  "instructions": null
}
```

Embed each fixture in the test module as a `L8.ByteString` literal. With `OverloadedStrings`, a multi-line string using `\` line continuations works, as does `L8.unlines` of short lines. `testRetrievedAgent` asserts:

- `agentType == CustomAgent`, `status == AgentDisabled` and `pauseReason == Just PauseCreditLimit`.
- `model == ModelPinned (Vector.singleton (Just "claude-sonnet-5"))`.
- `icon` is `Just (CustomAgentAvatar ...)`.
- `hasUnpublishedChanges == Just (Visible False)`, `lastRunTime == Just Hidden`, `creditLimit == Just (Visible 5000)` and `lastRunAt` is `Just (Visible _)`.
- `Vector.length connections == 4`. The constructors are, in order, `ConnectionNotion`, `ConnectionSlack` (whose `account == Just Hidden`), `ConnectionMcpServer` and `ConnectionConnector` (whose `type_ == "github"`), and none is `UnknownConnection`.
- The Notion connection's third target is `NotionWebSearchTarget Nothing`.
- The first trigger's schedule `end == Just (ScheduleEndsAfter 10)`, and the second trigger's `schedule == Nothing`.
- `instructions == Nothing` and `createdBy` has `type_ == CreatedByUser`.

`testNotionAiAgent` decodes this personal-agent fixture as an `Agent`. It asserts `agentType == NotionAiAgent`, `id == legacyNotionAiAgentId`, `model == ModelAuto`, `createdTime == Nothing`, `creditLimit == Nothing` and `version == Nothing`:

```json
{"object": "agent", "id": "33333333-3333-3333-3333-333333333333", "agent_type": "notion_ai", "name": "Notion Agent",
 "description": null, "instructions_page_id": null, "icon": {"type": "emoji", "emoji": "🤖"}, "model": {"mode": "auto"},
 "connections": [], "status": "active", "pause_reason": null, "created_by": null, "agent_version": null,
 "created_time": null, "last_edited_time": null, "last_run_at": null, "credit_limit": null, "triggers": []}
```

`testQueryResultAgent` decodes a custom agent in the query-result shape: `created_by` is `{"type": "bot", "id": ...}` with no `object`, and there is no `version`, `has_unpublished_changes` or `last_run_time`. It asserts `createdBy` has `type_ == CreatedByBot`, `version == Nothing`, `hasUnpublishedChanges == Nothing` and `lastRunTime == Nothing`.

`testUnknownValues` decodes a minimal agent whose values are all unfamiliar:

- `"agent_type": "swarm_agent"`, `"status": "hibernating"` and `"pause_reason": "moon_phase"`.
- `"model": {"mode": "ensemble"}` and `"icon": {"type": "hologram"}`.
- `"connections": [{"type": "telepathy", "name": "X", "account": {"nested": true}, "permissions": []}]`.
- A trigger schedule with `"end": {"type": "forever"}`.

It asserts the fallbacks: `UnknownAgentType "swarm_agent"`, `UnknownAgentStatus "hibernating"`, `Just (UnknownPauseReason "moon_phase")`, `UnknownModelSelection _`, `Just (UnknownAgentIcon _)`, a single `UnknownConnection _` (the generic connector parse fails because `account` is an object) and `Just (UnknownScheduleEnd _)`.

`testSessionModelSelection` decodes `{"type": "pinned", "ids": ["claude-sonnet-5", null]}` as `ModelSelection` and expects `ModelPinned (Vector.fromList [Just "claude-sonnet-5", Nothing])`.

Wire the module into `tasty/Main.hs`. Add `import AgentsTests qualified` with the other imports, then:

```diff
       [ jsonParsingTests,
         jsonSerializationTests,
         propertyValueTests,
         fileUploadTests,
+        AgentsTests.tests,
         basicIntegration,
```

Build and test:

```bash
cabal build all
cabal test
```

Expected excerpt:

```text
Notion Client Tests
  ...
  Agents
    Agent object
      decodes a retrieved custom agent:                                    OK
      decodes the notion_ai personal agent from query results:             OK
      decodes a query-result custom agent without retrieve-only fields:    OK
      decodes unknown enum and union values into fallbacks:                OK
      decodes session-style model selection:                               OK
  ...
All N tests passed
```

Commit (the pre-commit hook runs `treefmt`; if it reformats files, `git add` them again and re-run the commit):

```text
feat(agents): add agent object types with tolerant decoding

Add Notion.V1.Agents.Common (AgentId, Hideable, ModelSelection,
CreatedByRef, AgentVersionRef) and the Agent object in Notion.V1.Agents,
with fallback constructors for every enum and tagged union.

MasterPlan: docs/masterplans/2-add-the-custom-agents-and-sessions-api-with-sse-streaming.md
ExecPlan: docs/plans/12-add-custom-agent-management-endpoints.md
```

### Milestone 2

Apply the edits from Plan of Work, Milestone 2. Add a `testGroup "Query, retrieve, delete"` to `AgentsTests.tests`. Compare `Value`s, not encoded bytes, because key order in encoded JSON is not something to depend on. It contains these cases:

- "encodes an empty query as {}": `Aeson.toJSON emptyQueryAgents @?= Aeson.object []`.
- "encodes a nested filter, sorts and paging". It encodes the following value and compares it with the JSON literal below, decoded to `Value`:

```haskell
emptyQueryAgents
  { query = Just "digest",
    filter = Just (AgentFilterAnd [StatusIn [AgentActive, AgentDisabled], AgentFilterOr [AgentTypeEquals CustomAgent, CreatedTimeRange (Just "2026-09-01T00:00:00Z") Nothing]]),
    sorts = Just [AgentSort AgentSortLastRunAt Descending],
    pageSize = Just 50,
    includeDeleted = Just False
  }
```

```json
{"query": "digest",
 "filter": {"and": [
   {"property": "status", "status": {"in": ["active", "disabled"]}},
   {"or": [
     {"property": "agent_type", "string": {"equals": "custom_agent"}},
     {"property": "created_time", "date": {"after": "2026-09-01T00:00:00Z"}}
   ]}
 ]},
 "sorts": [{"property": "last_run_at", "direction": "descending"}],
 "page_size": 50,
 "include_deleted": false}
```

- "encodes every leaf filter": one assertion per remaining leaf constructor (`AgentIdEquals notionAiAgentId`, `CreatedByContains`, `FavoritedEquals True`, `ConnectionsMcpServerContains "mcp.example.com"`, `ModelModeEquals ModelModePinned`, `AgentVersionEquals 3`, `LastRunAtRange Nothing (Just "...")`), each checked against the JSON shape in the constructor's comment. Also check that `AgentFilterRaw v` encodes to `v` unchanged.
- "decodes a query response list": decode `{"object": "list", "type": "agent", "results": [<custom agent>, <notion_ai agent>], "has_more": true, "next_cursor": "cursor-2"}` as `ListOf Agent` (import `Notion.V1.ListOf (ListOf (..))`), and check two results, `hasMore == True` and `nextCursor == Just "cursor-2"`.
- "decodes a delete response": decode `{"agent_id": "5c1f2a0e-8d3b-4e61-9a7c-2b4d6e8f0a13", "status": "deleted", "deleted_at": "2026-09-13T12:00:00.000Z"}` as `DeletedAgent`.

Run and commit:

```bash
cabal build all
cabal test
```

```text
  Agents
    Agent object
      ...
    Query, retrieve, delete
      encodes an empty query as {}:                  OK
      encodes a nested filter, sorts and paging:     OK
      encodes every leaf filter:                     OK
      decodes a query response list:                 OK
      decodes a delete response:                     OK
```

Commit message subject: `feat(agents): add query, retrieve and delete agent endpoints`, with the same two trailers.

### Milestone 3

Apply the edits from Plan of Work, Milestone 3. Add a `testGroup "Insights, status, credit limit"` with these cases:

- "decodes insights with a hidden credit limit": fixture `{"object": "agent_insights", "id": "5c1f2a0e-8d3b-4e61-9a7c-2b4d6e8f0a13", "name": "Weekly Digest", "agent_type": "autofill_custom_agent", "status": "active", "pause_reason": null, "created_by": {"id": "d3b07384-d9a0-4c5e-9f1b-2a6c8e0f4b7d", "type": "user"}, "total_credits_used": 1234.5, "credit_limit": "hidden", "runs_completed": 42}`. Assert `creditLimit == Just Hidden`, `totalCreditsUsed == 1234.5` and `runsCompleted == 42`.
- "encodes a status update": `Aeson.toJSON (UpdateAgentStatus SetAgentDisabled)` equals `{"status": "disabled"}`.
- "encodes a credit limit": `UpdateAgentCreditLimit (Just 1000)` encodes to `{"credit_limit": 1000}`, matching the JS SDK test.
- "encodes clearing a credit limit as null": `UpdateAgentCreditLimit Nothing` encodes to `{"credit_limit": null}` (not `{}`).
- "decodes status and credit-limit responses": `{"agent_id": "...", "status": "disabled", "pause_reason": "disabled_from_api", "last_edited_time": "2026-09-13T12:00:00.000Z"}` gives `pauseReason == Just PauseDisabledFromApi`; `{"agent_id": "...", "credit_limit": null, "last_edited_time": "..."}` gives `creditLimit == Nothing`.

Create the demo and wire it in, then run:

```bash
cabal build all
cabal test
```

Commit subjects: `feat(agents): add agent insights, status and credit limit endpoints` and `docs(example): add read-only custom agent demo`, each with the two trailers.

### Milestone 4

Precondition check:

```bash
test -f src/Notion/V1/AsyncTasks.hs && grep -n "AsyncTask (..)\|^data AsyncTask\|retrieveAsyncTask" src/Notion/V1/AsyncTasks.hs src/Notion/V1.hs
```

Expected when the dependency has landed: at least one line from `src/Notion/V1/AsyncTasks.hs` defining or exporting `AsyncTask`, and one line from `src/Notion/V1.hs` with `retrieveAsyncTask`. If the command prints nothing or exits non-zero, stop and mark Milestone 4 blocked in Progress.

Apply the edits from Plan of Work, Milestone 4. Add a `testGroup "Batch"` with these cases:

- "encodes the JS SDK batch example": `Aeson.toJSON <$> mkAgentBatch [BatchUpdateStatus notionAiAgentId SetAgentDisabled]` equals `Right` of the decoded JS test body `{"operations":[{"action":"update_status","agent_id":"notion_ai","fields":{"status":"disabled"}}]}`.
- "encodes credit-limit and delete operations": `BatchUpdateCreditLimit (AgentId "5c1f2a0e-8d3b-4e61-9a7c-2b4d6e8f0a13") Nothing` encodes to `{"action": "update_credit_limit", "agent_id": "5c1f...", "fields": {"credit_limit": null}}`, and `BatchDelete ...` encodes to `{"action": "delete", "agent_id": "5c1f..."}` with no `fields` key.
- "rejects empty and oversized batches": `mkAgentBatch []` is a `Left`, `mkAgentBatch (replicate 101 (BatchDelete notionAiAgentId))` is a `Left`, and 100 operations give a `Right`.
- "decodes the batch async task response": decode `{"object": "async_task", "id": "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d", "status_url": "https://api.notion.com/v1/async_tasks/a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d", "created_time": "2026-09-14T09:00:00.000Z", "operation": {"surface": "rest", "name": "agents.batch"}, "status": "queued", "poll_after_seconds": 2}` as `AsyncTask`, and assert its id (the `operation.name` value is illustrative).

Run `cabal build all` and `cabal test`, then commit with subject `feat(agents): add agent batch operations returning an async task` and the two trailers.


## Validation and Acceptance

Unit-level acceptance, which needs no token:

```bash
cd /Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client
cabal build all
cabal test
```

`cabal build all` must finish without errors, and without new `-Wall` warnings in `src/Notion/V1/Agents.hs`, `src/Notion/V1/Agents/Common.hs`, `src/Notion/V1.hs` or the effectful modules. An "incomplete patterns" warning in `Interpreter.hs` means a lockstep step was missed. `cabal test` must end with `All N tests passed` and list, under `Agents`, the groups `Agent object`, `Query, retrieve, delete`, `Insights, status, credit limit` and `Batch`, with every case `OK`.

To prove the tests exercise the new behavior, temporarily change `UpdateAgentCreditLimit`'s `ToJSON` to `genericToJSON aesonOptions`. "encodes clearing a credit limit as null" must then fail with an `expected`/`but got` diff showing `{}`. Revert afterwards.

Live read-only check (requires `NOTION_TOKEN` for an integration with access to a workspace that has custom agents):

```bash
NOTION_TOKEN=secret_xxx NOTION_AGENT_DEMO=1 cabal run notion-client-example
```

Observe a `Custom Agents API` header followed by `Querying agents... ✓ Done` and one line per agent, for example `- Weekly Digest (CustomAgent, AgentActive)`, then instruction presence and insights for the first custom agent. If the workspace or token has no access, the demo prints the Notion error code and message and the rest of the example continues. This counts as acceptance for the error path, but not for decoding.

Live mutation check, optional and run by hand against an agent you own. Note its current credit limit first so you can restore it:

```bash
cabal repl notion-client
```

```haskell
import Notion.V1
import Notion.V1.Agents
import qualified Data.Text as T
import System.Environment (getEnv)
token <- T.pack <$> getEnv "NOTION_TOKEN"
env <- getClientEnv "https://api.notion.com/v1"
let m = makeMethods env token
let aid = AgentId "<your-agent-uuid>"
updateAgentStatus m aid (UpdateAgentStatus SetAgentDisabled)
-- AgentStatusUpdated {agentId = "...", status = AgentDisabled, pauseReason = Just PauseDisabledFromApi, lastEditedTime = ...}
updateAgentStatus m aid (UpdateAgentStatus SetAgentActive)
updateAgentCreditLimit m aid (UpdateAgentCreditLimit (Just 1000))
updateAgentCreditLimit m aid (UpdateAgentCreditLimit Nothing)
-- AgentCreditLimitUpdated {agentId = "...", creditLimit = Nothing, lastEditedTime = ...}
```

After Milestone 4, `batchAgents m <$> ...` with a single `BatchUpdateStatus` returns an `AsyncTask` whose status is queued or running. `retrieveAsyncTask` from `docs/plans/8-add-comment-mutation-async-task-and-meeting-notes-endpoints.md` then eventually reports completion.


## Idempotence and Recovery

All code steps are additive: new modules, new record fields, new constructors and new tests. Re-running a step against a file that already contains the edit should be detected by reading the file first, not by blindly re-applying a diff. `cabal build all` and `cabal test` can be run any number of times.

The pre-flight `git pull` in the JS SDK checkout only fast-forwards a read-only reference clone. If it fails because of local changes there, run `git -C /Users/shinzui/Keikaku/hub/notion-sdk-js stash` first; never commit in that repository.

If `src/Notion/V1/Agents/Common.hs` appears while you are mid-milestone (EP-2 landed concurrently), rebase onto it. Delete your local copies of any duplicated type, import the shared ones, and re-run the tests. The Milestone 1 tests act as the compatibility check for the shared decoders.

If the `makeMethods` pattern gets out of order with `type API`, GHC reports a type mismatch on the destructuring. Fix it by making the pattern's order match the route order exactly.

The mutation snippets in Validation and Acceptance change a live agent. Restore the original status and credit limit afterwards. `deleteAgent` is a soft delete, but this plan provides no undelete call, so do not run it against an agent you need.

If Milestone 4 is blocked on `AsyncTask`, Milestones 1–3 are complete and releasable on their own. Leave the batch items unchecked with a note, and resume when the precondition check passes.


## Interfaces and Dependencies

No new package dependencies. `aeson`, `scientific`, `servant`, `servant-client`, `text`, `time` and `vector` are already in the library's `build-depends`, and the test suite already depends on `aeson`, `bytestring`, `scientific`, `tasty`, `tasty-hunit`, `text` and `vector`. The effectful package already depends on `notion-client >=0.7 && <0.8`.

At the end of Milestone 1, module `Notion.V1.Agents.Common` exports exactly `AgentId (..)` (a newtype with field `text :: Text`), `notionAiAgentId :: AgentId`, `ModelSelection (..)`, `CreatedByRef (..)`, `CreatedByType (..)`, `AgentVersionRef (..)` and `Hideable (..)`, identical to the definitions in `docs/plans/13-add-session-endpoints-and-session-event-types.md`. Module `Notion.V1.Agents` exports `legacyNotionAiAgentId :: AgentId`, `Agent (..)`, `AgentType (..)`, `AgentStatus (..)`, `PauseReason (..)`, `AgentIcon (..)`, `AgentConnection (..)`, `NotionConnection (..)`, `SlackConnection (..)`, `DiscordConnection (..)`, `McpServerConnection (..)`, `ConnectorConnection (..)`, `Permission (..)`, `NotionTarget (..)`, `SlackTarget (..)`, `DiscordTarget (..)`, `ConnectorTarget (..)`, `SlackWorkspace (..)`, `DiscordServer (..)`, `McpServerAccount (..)`, `McpTool (..)`, `RunToolsAutomatically (..)`, `AgentTrigger (..)`, `TriggerSchedule (..)` and `ScheduleEnd (..)`, and re-exports `Notion.V1.Agents.Common`.

At the end of Milestone 2, `Notion.V1.Agents` additionally exports `QueryAgents (..)`, `emptyQueryAgents :: QueryAgents`, `AgentFilter (..)`, `ModelMode (..)`, `AgentSort (..)`, `AgentSortProperty (..)`, `DeletedAgent (..)` and `API`. `Notion.V1.Methods` has these fields:

```haskell
queryAgents :: Agents.QueryAgents -> IO (ListOf Agent)
retrieveAgent :: AgentId -> Maybe Bool -> IO Agent
deleteAgent :: AgentId -> IO DeletedAgent
```

`Notion.V1.Effectful.Effect` has the constructors `QueryAgents`, `RetrieveAgent` and `DeleteAgent`, and the smart constructors `queryAgents`, `retrieveAgent` and `deleteAgent`, with the same argument types in `Eff es`.

At the end of Milestone 3, `Notion.V1.Agents` additionally exports `InsightsWindow (..)`, `AgentInsights (..)`, `TargetAgentStatus (..)`, `UpdateAgentStatus (..)`, `AgentStatusUpdated (..)`, `UpdateAgentCreditLimit (..)` and `AgentCreditLimitUpdated (..)`. `Methods` gains:

```haskell
retrieveAgentInsights :: AgentId -> Maybe Agents.InsightsWindow -> IO Agents.AgentInsights
updateAgentStatus :: AgentId -> Agents.UpdateAgentStatus -> IO Agents.AgentStatusUpdated
updateAgentCreditLimit :: AgentId -> Agents.UpdateAgentCreditLimit -> IO Agents.AgentCreditLimitUpdated
```

The effectful package gains matching constructors and smart constructors. `notion-client-example/AgentDemo.hs` exports `runAgentDemo :: Methods -> IO ()`.

At the end of Milestone 4, `Notion.V1.Agents` additionally exports `AgentOperation (..)`, `AgentBatch (..)` and `mkAgentBatch :: [AgentOperation] -> Either Text AgentBatch`. `Methods` gains `batchAgents :: Agents.AgentBatch -> IO AsyncTask`, where `AsyncTask` comes from `Notion.V1.AsyncTasks` (owned by `docs/plans/8-add-comment-mutation-async-task-and-meeting-notes-endpoints.md`). The effectful package gains `BatchAgents` / `batchAgents`.

Breaking changes, to be listed under `### Breaking Changes` in both CHANGELOGs:

- `Notion.V1.Methods` gains seven fields. Code that builds a `Methods` value by hand (for example a test double using record construction) must supply them.
- The `Notion` effect GADT in `notion-client-effectful` gains seven constructors. Custom interpreters that pattern-match exhaustively must handle them.

No existing type, field or behavior changes. The `### New Features` entry in `CHANGELOG.md` should read roughly: "Custom agent management (`Notion.V1.Agents`): `queryAgents` with a typed `AgentFilter`, `retrieveAgent`, `deleteAgent`, `retrieveAgentInsights`, `updateAgentStatus`, `updateAgentCreditLimit` and `batchAgents`. These routes are unpublished upstream and may change; unknown values decode into `Unknown*` constructors."

Integration points honored:

- `Notion.V1.Agents.Common` is shared with `docs/plans/13-add-session-endpoints-and-session-event-types.md`; whichever plan runs first creates it.
- `AsyncTask` is consumed from, and never redefined apart from, `docs/plans/8-add-comment-mutation-async-task-and-meeting-notes-endpoints.md`.
- Error types and client runtime are consumed from `docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md` as they exist at implementation time.


Revision 2026-09-15 (cross-plan update from MasterPlan 1 EP-3): Milestone 4's batch route instructions now warn that Notion returns HTTP 202 for queued work and that a `Post '[JSON] AsyncTask` route would reject it, and they point to ADR 3 and `fromAsyncUnion`. `docs/plans/8-add-comment-mutation-async-task-and-meeting-notes-endpoints.md` discovered this during a live check. No other part of this plan changed.
