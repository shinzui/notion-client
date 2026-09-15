---
id: 1
slug: reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api
title: "Reach Parity with the Official Notion JS SDK on the Published REST API"
kind: master-plan
created_at: 2026-09-14T18:46:33Z
intention: intention_01m2jjvjgpef9tyyp50524jfwq
provenance:
  created_by:
    model: "claude-opus-5"
    harness: "claude-code"
    at: 2026-09-14T18:46:33Z
  revisions:
    - model: "claude-opus-5[1m]"
      harness: "claude-code"
      at: 2026-09-15T13:07:33Z
      mode: "implement"
      note: "Linked intention; started EP-1"
    - model: "claude-opus-5[1m]"
      harness: "claude-code"
      at: 2026-09-15T14:19:29Z
      mode: "implement"
      note: "EP-3 completed, registry updated, ADRs 3-4 added"
    - model: "claude-opus-5[1m]"
      harness: "claude-code"
      at: 2026-09-15T14:22:19Z
      mode: "implement"
      note: "Started EP-4; registry updated"
---

# Reach Parity with the Official Notion JS SDK on the Published REST API

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Vision & Scope

`notion-client` is a Haskell library (repository root `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`, package version 0.7.0.2) that exposes the Notion HTTP API as a Servant API type plus a record of `IO` functions called `Methods` (see `src/Notion/V1.hs`). A companion package, `notion-client-effectful`, re-exposes every `Methods` field as an `effectful` effect. The official reference client is Notion's TypeScript SDK `@notionhq/client` v5.26.0, checked out locally at `/Users/shinzui/Keikaku/hub/notion-sdk-js`. Its request and response types in `src/api-endpoints/*.ts` are generated from Notion's own API schema, so they are the most precise available description of the wire format. In this plan, "the JS SDK" means that checkout.

A comparison carried out on 2026-09-14 found four kinds of gap between the two clients:

1. **Correctness bugs.** Some responses the Haskell client cannot decode, and some requests it encodes in a shape Notion rejects. Examples: the `default_background` color, `custom_emoji` icons, code-block languages and mention types the client does not know, `agent_id` parents, users without an email, and `filter_properties` sent in the request body instead of the query string.
2. **Client runtime.** The JS SDK has behavior around each request that the Haskell client lacks: automatic retries on HTTP 429/529/5xx that honor `retry-after`, request timeouts, typed error codes that carry `request_id`, a configurable API version and base URL, per-request auth, OAuth token endpoints that use HTTP Basic auth, and helpers such as `extractNotionId`.
3. **Missing published endpoints.** Retrieve, update and delete for comments; retrieving async tasks; creating and querying meeting notes; the three-step view-query flow (`views/{id}/queries`); and the OAuth endpoints.
4. **Types that are missing or too loose.** Examples: `database_type`, `request_status` on list responses, typed search results, typed view configuration, filter variants, property-schema `description`, `link_mention` and `custom_emoji` mentions, typed webhook event data, and partial update payloads for blocks.

When this initiative is complete, a Haskell user can do everything below that the JS SDK allows on the published REST API:

- Decode every response shape the JS SDK types describe without a parse failure.
- Send every request body shape the JS SDK accepts.
- Call every published endpoint, including OAuth, comment mutation, async tasks, meeting notes and view queries.
- Rely on the client to retry rate-limited requests.
- Pattern-match on typed error codes.

Each child plan proves its part with unit tests in the `tasty` test suite: JSON fixtures copied from the JS SDK types, decoded and re-encoded. Where a live token is available, the example executable `notion-client-example` also exercises it.

Explicitly excluded from this MasterPlan:

- **The custom agents, sessions, threads and external-agent-stub routes.** The JS SDK added these in August 2026 from unpublished routes, and they are still changing weekly. They are coordinated separately by `docs/masterplans/2-add-the-custom-agents-and-sessions-api-with-sse-streaming.md`, which depends on this plan's client runtime and async-task work.
- **JS-only mechanics** that have no Haskell meaning: the `warnUnknownParams` runtime warning (Haskell records make unknown parameters a compile error), the `fetch` injection option, and the `isFull*` type guards (Haskell expresses "partial vs. full object" as sum types instead).
- **Changing the default `Notion-Version`.** The Haskell client pins `2026-03-11`; the JS SDK defaults to `2025-09-03` but supports `2026-03-11`. Haskell keeps `2026-03-11` and only makes it configurable.
- **Code generation** of the Haskell types from Notion's schema.


## Decomposition Strategy

The work is split by functional concern, so that each child plan produces behavior that can be tested on its own. The groups follow the four kinds of gap above, with the large "types" group split by API resource family.

EP-1 (bug fixes) is separate from the resource-family plans. It holds only defects that make the client fail today, by crashing on decode or being rejected by Notion, so they can ship in their own release before any of the larger additive work lands. The rule for assigning an item to EP-1 is strict: it must produce a runtime failure against a real Notion response or request. Missing-but-harmless fields go to the resource plans.

EP-2 (client runtime) stands alone because it changes how every request is executed (`makeMethods` and its `run` function in `src/Notion/V1.hs`, plus `src/Notion/V1/Error.hs`), not any single resource. Keeping it separate lets resource plans add endpoints without touching retry logic. OAuth lives in EP-2 rather than the endpoint plan because its endpoints need a different `Authorization` header (HTTP Basic instead of the global `Bearer` header in `Notion.V1.API`), which is a runtime and auth concern.

EP-3 collects three small, unrelated new endpoint families (comment mutation, async tasks, meeting notes). None of them justifies its own plan. Async tasks must exist before anything returns one: `pages.create` with markdown and `allow_async`, `pages.updateMarkdown` with `allow_async`, and, in MasterPlan 2, `agents.batch`. EP-3 therefore also owns the `allow_async` request flags and the async-task response union for those two page endpoints.

The resource-family plans follow:

- **EP-4: views.** View queries and view configuration.
- **EP-5: data sources, databases and search.** Their result unions, `request_status`, filters and property schemas, plus the `iterateAllDataSourceRows` helper that depends on `request_status`.
- **EP-6: the remaining object types.** Pages, blocks, property values, rich text mentions, users, file uploads and webhooks.

These were grouped by the source modules they touch. The goal is that two plans rarely need to change the same function.

Alternatives considered:

- **One ExecPlan per JS SDK endpoint file (16 plans).** Rejected: too granular, and many files (`search.ts`, `custom-emojis.ts`) have no gap.
- **A single "close all gaps" ExecPlan.** Rejected: the repository already tried that shape (`docs/plans/2-close-api-gaps.md`, `docs/plans/complete-api-coverage.md`). The present gap touches more than twenty modules across unrelated concerns, well beyond the size an ExecPlan should hold.
- **Folding the bug fixes into the resource plans.** Rejected: the fixes would then wait behind large additive work, and users are hitting the decode failures now.

ADR context: this repository has no `docs/adr/` directory. A search of the Mori concept registry (`mori registry concepts --search notion`) returned only `mori://shinzui/jangso-db/okf/adrs/concepts/ADR-6`. That record is about how a different project consumes Notion data and does not constrain this client. No relevant ADR exists. The Integration Points section lists decisions from this initiative that should become the first ADRs.

Prior plans in this repository that give useful background (all checked in, all complete):

- `docs/plans/1-notion-api-gap-analysis.md` and `docs/plans/2-close-api-gaps.md`: the previous gap analysis against Notion's documentation.
- `docs/plans/complete-2026-03-11-upgrade.md`: the `archived` to `in_trash` rename and the `Notion-Version` pin.
- `docs/plans/typed-database-datasource-support.md`: the `Filter`, `Sort` and `PropertySchema` DSL.
- `docs/plans/typed-block-content.md`: the `BlockContent` sum type.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 1 | Fix Wire-Format Decoding and Encoding Bugs Found Against the Official SDK | docs/plans/6-fix-wire-format-decoding-and-encoding-bugs-found-against-the-official-sdk.md | None | None | Complete |
| 2 | Add a Configurable Client Runtime with Retries, Typed Error Codes, and OAuth | docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md | None | None | Complete |
| 3 | Add Comment Mutation, Async Task, and Meeting Notes Endpoints | docs/plans/8-add-comment-mutation-async-task-and-meeting-notes-endpoints.md | EP-1 | EP-2 | Complete |
| 4 | Add View Queries and Typed View Configuration | docs/plans/9-add-view-queries-and-typed-view-configuration.md | None | EP-2, EP-5 | Complete |
| 5 | Type Data Source, Database, and Search Results and Close Query and Filter Gaps | docs/plans/10-type-data-source-database-and-search-results-and-close-query-and-filter-gaps.md | EP-1, EP-2 | None | Not Started |
| 6 | Close Page, Block, Property Value, User, File Upload, and Webhook Field Gaps | docs/plans/11-close-page-block-property-value-user-file-upload-and-webhook-field-gaps.md | EP-1 | EP-3 | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-1, EP-3).


## Dependency Graph

The plans run in two waves.

**Wave 1: EP-1 and EP-2, in parallel.** They touch almost disjoint code:

- EP-1 edits the decoders and encoders in `Common.hs`, `RichText.hs`, `BlockContent.hs`, `Users.hs`, `Properties.hs`, `Webhooks.hs`, `Pages.hs`, `DataSources.hs` and `Databases.hs`.
- EP-2 edits `V1.hs` (`makeMethods`), `Error.hs`, `ListOf.hs` and `Pagination.hs`, and adds new modules.

The one overlap is in `src/Notion/V1.hs`. EP-1 moves `filter_properties` from the JSON body of `queryDataSource`/`queryDatabase` into a query parameter. It adds a `QueryParams` segment to those two Servant routes and a small wrapper inside `makeMethods`, but keeps both `Methods` field signatures unchanged, so `notion-client-effectful` needs no edit for it. EP-2 rewrites `makeMethods` into a wrapper over a configurable constructor. Whichever plan lands second must carry EP-1's wrapper into EP-2's new constructor.

**Wave 2: EP-3, EP-4, EP-5 and EP-6**, which can proceed in parallel once their hard dependencies are met.

- **EP-5 has two hard dependencies.** It needs EP-2's `RequestStatus` field on `ListOf` for its `iterateAllDataSourceRows` helper, whose termination logic reads `request_status.type == "incomplete"`. It also needs EP-1's corrected `filter_properties` routing, because it changes the same `QueryDataSource` record and route again, adding `result_type` and a page-or-data-source result union.
- **EP-6 hard-depends on EP-1.** It extends the very parsers EP-1 makes lenient: the mention parser in `RichText.hs` gains `link_mention` and `custom_emoji`, and the `custom_emoji` icon that EP-1 re-nests gains its `name`/`url` fields. Doing it before EP-1 would force EP-1 to be redone. EP-1, not EP-6, fully types the meeting-notes block payload.
- **EP-6 soft-depends on EP-3** only for reusing the `AsyncTask` type if it chooses to type the `file_import_result` webhook data. It can use `Value` until EP-3 lands.
- **EP-3 hard-depends on EP-1, but only for its meeting-notes milestones (3 and 4).** Those milestones reuse EP-1's `MeetingNotesStatus`, `MeetingNotesChildren`, `MeetingCalendarEvent` and `MeetingRecording` from `src/Notion/V1/BlockContent.hs`. EP-3's comment and async-task milestones can start before EP-1 lands.
- **EP-3 soft-depends on EP-2** for the typed error code in `AsyncTaskError`.
- **EP-4 soft-depends on EP-2**, for `request_status` on view query result lists, and on EP-5, to reuse `FromJSON` instances for `Filter` and `Sort` if EP-5 adds them first. If EP-4 lands first, EP-4 adds those instances and EP-5 reuses them (see Integration Points).

The resulting order is EP-1 ∥ EP-2 (with EP-3 milestones 1–2 able to run alongside them), then EP-3 ∥ EP-4 ∥ EP-5 ∥ EP-6. A single contributor working alone should follow EP-1, EP-2, EP-3, EP-5, EP-4, EP-6.

MasterPlan 2 (`docs/masterplans/2-add-the-custom-agents-and-sessions-api-with-sse-streaming.md`) hard-depends on EP-2 and EP-3 of this plan.


## Integration Points

**The `Methods` record, the `API` type and `makeMethods` (`src/Notion/V1.hs`).**
- EP-1, EP-2, EP-3, EP-4 and EP-5 all change them. EP-2 owns the shape of `makeMethods` and the configuration it accepts. It must keep `makeMethods :: ClientEnv -> Text -> Methods` working unchanged, as a wrapper over a new configurable constructor, so that later plans and existing users are unaffected.
- Every plan that adds or changes a `Methods` field adds its Servant route to the resource module's `API` type, adds the pattern binding in `makeMethods` in the same position as the route, and adds the record field.

**The `notion-client-effectful` companion package** (`notion-client-effectful/src/Notion/V1/Effectful/Effect.hs` and `Interpreter.hs`).
- Every plan that adds or changes a `Methods` field must add or change the matching constructor of the `Notion` GADT, its smart constructor, and its interpreter case in the same commit. That package's module header states that each smart constructor has "the same name, same argument order, and same argument types as the corresponding `Methods` field".
- Build both packages with `cabal build all` to verify.

**`ListOf` and `RequestStatus` (`src/Notion/V1/ListOf.hs`).**
- Owned by EP-2. It adds `requestStatus :: Maybe RequestStatus`, where `RequestStatus` covers `{type: "complete" | "incomplete", incomplete_reason?: "query_result_limit_reached" | unknown text}`.
- EP-4 and EP-5 consume it. No other plan redefines list envelopes.
- The meeting-notes query response (`{results, has_more}`, no cursor) does not fit `ListOf`. EP-3 defines its own response record for it.

**Error types (`src/Notion/V1/Error.hs`).**
- Owned by EP-2, which introduces an `APIErrorCode` sum type covering the JS SDK's 14 codes plus an `UnknownErrorCode Text` fallback. It also adds `request_id`, `additional_data`, the response status and the `cf-ray`/`x-notion-request-id` headers.
- EP-3's `AsyncTask` failed-state `error` object has the same `{code, message, status, additional_data}` shape. EP-3 must reuse EP-2's code type if EP-2 has landed. If not, EP-3 decodes `code` as `Text`, and a follow-up in whichever plan lands second switches it to the shared type.

**`AsyncTask` (new module `src/Notion/V1/AsyncTasks.hs`).**
- Owned by EP-3. It is consumed by EP-3's own `allow_async` page responses, optionally by EP-6, and by MasterPlan 2's `agents.batch`.
- The module also owns `AsyncVerb`, `AsyncStatuses` and `fromAsyncUnion`. Notion answers queued work with HTTP 202, and servant's plain `Post`/`Patch` verbs accept only 200, so every route that can return a task must accept 202 through a `UVerb` (see [docs/adr/3-background-operations-accept-200-or-202-and-return-asyncor.md](../adr/3-background-operations-accept-200-or-202-and-return-asyncor.md)). This includes MasterPlan 2's `agents.batch`.

**`Parent` and `Color` (`src/Notion/V1/Common.hs`).**
- EP-1 adds `AgentParent` and `default_background`. EP-6 must not re-add them.
- `Icon` is shared the same way: EP-1 fixes the `custom_emoji` icon's nested shape and adds `UnknownIcon`. EP-6 adds the icon's `name`/`url` fields (changing the `CustomEmojiIcon` constructor and EP-1's icon tests) and types native icon colors.

**Meeting-notes payload types (`src/Notion/V1/BlockContent.hs`).**
- Owned by EP-1: `MeetingNotesStatus`, `MeetingNotesChildren`, `MeetingCalendarEvent`, `MeetingRecording`, and the `MeetingNotesBlock` constructor, including the `transcription` alias.
- EP-3's `src/Notion/V1/MeetingNotes.hs` imports them into its `MeetingNotesContent` record for the create and query responses.
- EP-6 does not touch them.

**Page position (`PagePosition`).**
- EP-1 introduces `PagePosition` (`after_block | page_start | page_end`) for `CreatePage`.
- EP-6 reuses it.

**Partial objects (`PartialPageObject`, `PartialDataSourceObject`, `PartialDatabaseObject`).**
- EP-3 set the pattern with `CommentResponse` and `CreateMeetingNoteResponse`: a full-or-partial sum type decided by a key only the full shape has. It is recorded in [docs/adr/4-full-or-partial-responses-and-request-only-types.md](../adr/4-full-or-partial-responses-and-request-only-types.md), which EP-4, EP-5 and EP-6 should follow.
- `PartialPageObject` is a newtype `{id :: PageID}` in `src/Notion/V1/Pages.hs`, used by EP-4 (view query results) and EP-5 (query and search result unions). **EP-4 defined it** (2026-09-15) with exactly that definition; EP-5 reuses it.
- EP-5 owns the data-source and database partials and `PageOrDataSource`.
- EP-6 defers partial page and block responses for other endpoints to a follow-up, which must reuse these types.

**The mention parser (`src/Notion/V1/RichText.hs`).**
- EP-1 adds an `UnknownMention Value` fallback so unknown mention types no longer fail. Its tests use made-up mention types, not `link_mention`, so they keep exercising the fallback after EP-6.
- EP-6 adds `LinkMention` and `CustomEmojiMention`, and enriches `UserMention`, on top of that fallback.

**`CodeLanguage` (`src/Notion/V1/BlockContent.hs`).**
- EP-1 adds the 18 missing languages and an `OtherLanguage Text` fallback.

**`Filter`/`Sort` FromJSON instances (`src/Notion/V1/Filter.hs`).**
- Needed by both EP-4 (typed `ViewObject.filter`/`sorts`) and EP-5 (search sorts, filter variants). **EP-4 added them** (2026-09-15): `FromJSON` for `Filter`, `PropertyCondition`, every condition type, `Sort` and `SortDirection`, plus `ToJSON PropertyCondition`, built from `parsePropertyCondition`, `parseTextCondition`, `parseDateCondition` and similar helpers. EP-5 consumes them, extends those parsers in place when it adds constructors, and records that in its Decision Log.
- EP-5 owns all new filter condition constructors: verification `does_not_equal`, string-or-array values, `unique_id` empty checks.

**`PropertySchema`, `SelectOption` and `NumberFormat` (`src/Notion/V1/Properties.hs`).**
- EP-1 makes `NumberFormat` tolerant of unknown values (`OtherNumberFormat Text`).
- EP-5 owns everything else here: `description` fields, rename-only updates (`PropertyUpdate`), status configuration without `groups`, `LocationSchema`/`LastVisitedTimeSchema`, and the `UnknownSchema` fallback.

**Runtime interfaces for non-Servant callers.**
- EP-2 exports `ClientConfig`, `RequestContext`, `standardHeaders`, `responseTimeoutFor`, `withRetries`, `notionErrorFromResponse` and `buildRequestError`.
- MasterPlan 2's SSE plan (`docs/plans/14-stream-session-updates-over-server-sent-events.md`) builds raw `http-client` requests with them. Renaming any of them requires updating that plan.

**Tests (`tasty/Main.hs`, 2298 lines).**
- To avoid merge conflicts between parallel plans, each child plan puts its new tests in a new module `tasty/<Area>Tests.hs` exporting `tests :: TestTree`. It lists that module under `other-modules` of `test-suite tasty` in `notion-client.cabal` and adds one line to the top-level `testGroup` in `tasty/Main.hs`.
- Fixtures are JSON literals transcribed from the JS SDK type definitions. Never use the maintainer's real name in fixtures; use made-up Japanese names such as "Tanaka Hanako".

**`CHANGELOG.md` and the package version.**
- Each plan appends its entries under a single `## Unreleased` heading at the top of `CHANGELOG.md`, using the existing `### Breaking Changes` / `### New Features` / `### Bug Fixes` subsections.
- EP-1 changes exported field types (`PersonUser.email`, `UniqueIdResult.number`, `MeetingNotesBlock`) and adds constructors, so under the Haskell Package Versioning Policy it is breaking and cannot ship as `0.7.x`. If an early fix release is wanted, EP-1 ships alone as `0.8.0.0`, and the remaining plans follow as `0.9.0.0`.
- Otherwise all plans are released together as `0.8.0.0`. The version bump in `notion-client.cabal` and the effectful package's `notion-client` bound happen once, after the last plan completes. They are tracked in Progress below.

**Cross-plan decisions that should become ADRs** once implemented (there is no `docs/adr/` yet; create it with a plain Markdown convention, since `mori.dhall` declares no profiled ADR bundle):

1. The JS SDK's generated types are the reference for the wire format, and `2026-03-11` is the pinned API version.
2. Decoders must be tolerant: every closed enum and sum type decoded from a response has an "unknown" fallback constructor carrying the raw value. **Recorded** as [docs/adr/1-tolerant-response-decoders.md](../adr/1-tolerant-response-decoders.md) (2026-09-15). The directory uses plain Markdown files named `<N>-<slug>.md`.
3. The retry policy: which errors, which methods, how `retry-after` is honored. **Recorded** as [docs/adr/2-client-runtime-retry-policy-and-typed-errors.md](../adr/2-client-runtime-retry-policy-and-typed-errors.md) (2026-09-15), together with the typed error model and the runtime interfaces for non-Servant requests.
4. The `notion-client-effectful` lockstep rule.
5. The deliberate exclusion of unpublished agent routes from the core REST parity effort.
6. Operations that may run in the background (HTTP 202, `AsyncOr`, `AsyncVerb`). **Recorded** as [docs/adr/3-background-operations-accept-200-or-202-and-return-asyncor.md](../adr/3-background-operations-accept-200-or-202-and-return-asyncor.md) (2026-09-15), from EP-3.
7. Full-or-partial response sum types and request-only types. **Recorded** as [docs/adr/4-full-or-partial-responses-and-request-only-types.md](../adr/4-full-or-partial-responses-and-request-only-types.md) (2026-09-15), from EP-3.
8. Three-state (`Clearable`) request fields and one type for a configuration that is read and sent back. **Recorded** as [docs/adr/5-clearable-request-fields-and-shared-configuration-types.md](../adr/5-clearable-request-fields-and-shared-configuration-types.md) (2026-09-15), from EP-4. EP-4 also amended ADR 1 with the parse-failure fallback rule for nested, partially modelled values.


## Progress

- [x] EP-1: Decoder crash fixes (colors, icons, code languages, mentions, parents, users, meeting-notes block, webhooks)
- [x] EP-1: Encoder fixes (`filter_properties` query parameter, page `position`, custom-emoji icon request, webhook signature case)
- [x] EP-2: Configurable client (API version, base URL, timeout) with `makeMethods` preserved (it gains default retries)
- [x] EP-2: Retries with back-off and `retry-after`
- [x] EP-2: Typed error codes and `request_status` on `ListOf`
- [x] EP-2: OAuth token, revoke and introspect with Basic auth; `extractNotionId` helpers
- [x] EP-3: Comment retrieve, update and delete, plus create-comment write shapes
- [x] EP-3: Async task retrieval and `allow_async` page responses
- [x] EP-3: Meeting notes create and query with typed filter grammar
- [x] EP-4: View query create, results and delete flow (removes the non-existent `queryView` route)
- [x] EP-4: Typed view configuration, filters and sorts
- [ ] EP-5: `database_type`, page-or-data-source query results, `result_type`
- [ ] EP-5: Typed search results, sorts and filters
- [ ] EP-5: Property schema and filter condition gaps
- [ ] EP-5: `iterateAllDataSourceRows` helper
- [ ] EP-6: Page and block request gaps (partial block updates, page create options)
- [ ] EP-6: Property value, mention, user and file upload response gaps
- [ ] EP-6: Webhook event types, fields and typed data
- [ ] Release: bump to 0.8.0.0, update effectful bounds, finalize CHANGELOG, create ADRs


## Surprises & Discoveries

- Cross-plan review during drafting (2026-09-14) found and resolved several collisions between the child plans. EP-1 and EP-3 both defined meeting-notes payload types, including an identically named `MeetingNotesChildren`; EP-1 now owns them. EP-4 and EP-5 both needed a partial-page type; one shared definition is now recorded above. EP-1's mention tests used `link_mention`, which EP-6 later types; the fixtures were switched to made-up types.
- `queryView` (`POST views/{id}/query`) has no JS SDK equivalent in any commit. The JS views API was added in commit 2e27ab5 with only `views/{id}/queries`, and an earlier plan here recorded a 400 from that route. EP-4 removes it (a breaking change).
- The path-traversal guard is relevant in Haskell after all. `http-api-data` leaves `.` unencoded in URL pieces, and `UUID` has an `IsString` instance, so `retrievePage methods ".."` would request `/v1/pages/..`. EP-2 adds the guard.
- EP-1 cannot be a patch release, because its fixes change exported field types.
- EP-1 (completed 2026-09-15) kept the `Methods` signatures of `queryDataSource`/`queryDatabase` unchanged. Only the Servant `API` types gained `QueryParams "filter_properties" Text`, and `makeMethods` now binds `queryDataSource_`/`queryDatabase_` with two wrapper equations in its `where` block. EP-2 must carry those wrappers into its configurable constructor. EP-5 builds on the new route shape.
- EP-1 fully typed the meeting-notes payload, as recorded in the Decision Log. The Dependency Graph's older wording ("EP-6 ... meeting notes") is superseded: EP-3 can now reuse `MeetingNotesStatus`, `MeetingNotesChildren`, `MeetingCalendarEvent` and `MeetingRecording` from `Notion.V1.BlockContent`.
- EP-1 added `tasty/WireFormatTests.hs` with a `captureRequest` helper. The helper overrides servant-client's `makeClientRequest` to inspect a built HTTP request without network access, which EP-2, EP-3 and EP-5 can copy for their own encoding tests. The first `other-modules` entry of `test-suite tasty` now exists; later plans append their modules to it.
- EP-2 (completed 2026-09-15) carried EP-1's `queryDataSource_`/`queryDatabase_` wrappers into `makeMethodsWithEnv` unchanged, as the Dependency Graph required; EP-1's `captureRequest` tests kept passing under the new middleware. EP-2 also added `tasty/FakeNotion.hs`, a scripted `ClientEnv` middleware that records requests and replays canned responses, which EP-3, EP-4 and EP-5 can use for network-free endpoint tests. `ListOf.requestStatus` and `RequestStatus`/`RequestStatusType`/`IncompleteReason` now exist for EP-4 and EP-5, and `APIErrorCode` exists for EP-3's `AsyncTask` error, so EP-3 does not need its `Text` fallback. Every hand-built `ListOf.List` literal must now supply `requestStatus`.
- EP-2's runtime interfaces for plan 14 landed with the names listed under Integration Points. `Notion.V1` also re-exports `withRetries`, and `Notion.V1.Client` additionally exports `defaultUserAgent`.
- EP-3 (completed 2026-09-15) found that **Notion answers accepted background work with HTTP 202**, which servant-client's `Post '[JSON]`/`Patch '[JSON]` routes reject, because `Verb` accepts only its exact status. `FakeNotion` tests cannot catch this, because the fake middleware bypasses servant's status check. EP-3 added `AsyncVerb` (a `UVerb` accepting 200 and 202) in `src/Notion/V1/AsyncTasks.hs`. MasterPlan 2's `docs/plans/12-add-custom-agent-management-endpoints.md` planned `agents/batch` as `Post '[JSON] AsyncTask` and has been annotated. Any plan adding an endpoint that may return a non-200 success status should check it live.
- EP-3 found that meeting-notes date filters accept only specific relative strings (documented in `Notion.V1.MeetingNotes` Haddocks). It also found that Notion validates a request body before checking whether the workspace plan includes the feature, so encoders can be validated live against a workspace without AI meeting notes. EP-3 used `APIErrorCode` directly for `AsyncTaskError.code`, so no follow-up switch is needed. `FakeNotion` records request paths without the `/v1` base-URL prefix.
- EP-4 (completed 2026-09-15) started before EP-5, so it defined `PartialPageObject` and the `Filter`/`Sort` decoders (see Integration Points). EP-5 must reuse both. When EP-5 adds filter-condition constructors, it should extend the existing `parse…Condition` helpers rather than write new decoders. EP-4's round-trip test deliberately leaves out `UniqueIdCondition` and `VerificationCondition`, whose payloads EP-5 changes.
- EP-4 verified the view-query flow live. All three routes return HTTP 200, so plain servant verbs are correct and no `AsyncVerb` is needed. The `next_cursor` from the create response continues to the second page. Live responses also carry a top-level `request_id`. Its live E2E test showed that `null` clears a view filter and that typed configurations are accepted.
- EP-4 introduced `Notion.V1.Clearable` (`Unset | Clear | Set a`) for request fields that accept `null`. EP-5's property-schema updates and EP-6's partial block updates should use it rather than `Maybe (Maybe a)`. See ADR 5.
- `cabal test --test-options='-p "…"'` does not filter tests, because cabal splits the options on spaces. Child plans should use `cabal test --test-option=--pattern=<pattern>`.
- The first ADR, [docs/adr/1-tolerant-response-decoders.md](../adr/1-tolerant-response-decoders.md), records cross-plan decision 2 below (tolerant decoders). Later plans that add fallback constructors should follow it.


## Decision Log

- Decision: Split the JS SDK gap into two MasterPlans. This one covers the published REST API; `docs/masterplans/2-add-the-custom-agents-and-sessions-api-with-sse-streaming.md` covers custom agents, sessions and SSE streaming.
  Rationale: The agents surface is roughly 27 endpoints and 60–80 object shapes. The JS SDK commits (#768, #769, #770, #786, #787, August 2026) describe these routes as "unpublished". In one sub-surface the routes are literally named "stub". Its contract has changed weekly, with fields removed and event types added. Blending it with stable REST parity would hold the stable work hostage to churn.
  Date: 2026-09-14

- Decision: Isolate crash-level correctness bugs into EP-1 with no dependencies.
  Rationale: Users hit these failures today, for example any page carrying a `default_background` block or a code block in `toml`. They should ship as a patch release independently of the breaking additive work.
  Date: 2026-09-14

- Decision: Put OAuth in the client-runtime plan (EP-2) rather than the endpoints plan (EP-3).
  Rationale: The OAuth endpoints need HTTP Basic auth instead of the `Bearer` header that `Notion.V1.API` applies globally. That is a change to request construction and authentication, which EP-2 already owns.
  Date: 2026-09-14

- Decision: EP-3 owns `allow_async` on page creation and markdown update.
  Rationale: Those responses can be an `async_task` object, whose type EP-3 defines. Keeping both in one plan avoids a hard dependency from EP-6 onto EP-3.
  Date: 2026-09-14

- Decision: New tests go in per-plan `tasty/<Area>Tests.hs` modules rather than growing `tasty/Main.hs`.
  Rationale: Four Wave-2 plans may run in parallel, and a single 2300-line test file would conflict constantly.
  Date: 2026-09-14

- Decision: Keep `Notion-Version: 2026-03-11` as the default and make it configurable, rather than following the JS SDK default of `2025-09-03`.
  Rationale: The library already migrated to `2026-03-11` (`docs/plans/complete-2026-03-11-upgrade.md`), and the JS SDK types document `2026-03-11` behavior. Downgrading would reintroduce `archived`.
  Date: 2026-09-14


- Decision: EP-1 owns the fully typed meeting-notes payload. EP-3 reuses it and hard-depends on EP-1 for its meeting-notes milestones.
  Rationale: The first drafts defined the same types twice, with colliding exported names. EP-1 must touch the decoder anyway to fix the crash.
  Date: 2026-09-14

- Decision: `makeMethods` keeps its type but gains the default retry policy. It leaves the caller's `Manager` timeout untouched.
  Rationale: This reflects EP-2's Decision Log. Users should benefit from retries without code changes, retries can only turn failures into successes or delay failures, and a caller-tuned `Manager` must not be silently changed.
  Date: 2026-09-14

- Decision: Record EP-3's 202 finding as a shared interface (`AsyncVerb` in `Notion.V1.AsyncTasks`, ADR 3) and annotate MasterPlan 2's agents plan, rather than leave each plan to rediscover it.
  Rationale: The failure appears only against the live API, so a plan that follows its written route type would ship a broken endpoint.
  Date: 2026-09-15

- Decision: EP-4 removes `queryView` rather than deprecating it.
  Rationale: The route never existed in Notion's published API. It returns HTTP 400, so any existing caller is already broken.
  Date: 2026-09-14


## Outcomes & Retrospective

(To be filled during and after implementation.)


Revision 2026-09-15 (implementation of EP-3): EP-3 is marked Complete, and its three Progress items are checked. Surprises & Discoveries records the HTTP 202 finding, the meeting-notes filter grammar and `FakeNotion`'s path recording. The Integration Points section now names `AsyncVerb` as part of the `AsyncTask` interface, and the partial-objects entry points to the full-or-partial pattern. ADRs 3 and 4 were added to the ADR list. The Decision Log records why the 202 finding was propagated to MasterPlan 2's agents plan.

Revision 2026-09-15 (implementation of EP-4): EP-4 is marked Complete, and its two Progress items are checked. Integration Points now record that EP-4 defined `PartialPageObject` and the `Filter`/`Sort` `FromJSON` instances, which EP-5 consumes. Surprises & Discoveries record the live view-query findings, the new `Clearable` type for EP-5 and EP-6, and the tasty filter-command gotcha. ADR 5 was added to the ADR list, and ADR 1 was amended.
