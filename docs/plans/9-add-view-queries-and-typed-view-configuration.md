---
id: 9
slug: add-view-queries-and-typed-view-configuration
title: "Add View Queries and Typed View Configuration"
kind: exec-plan
created_at: 2026-09-14T18:46:51Z
master_plan: "docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md"
intention: intention_01m2jjvjgpef9tyyp50524jfwq
provenance:
  created_by:
    model: "claude-opus-5"
    harness: "claude-code"
    at: 2026-09-14T18:46:51Z
  revisions:
    - model: "claude-opus-5[1m]"
      harness: "claude-code"
      at: 2026-09-15T14:22:19Z
      mode: "implement"
      note: "Implemented EP-4 milestones"
---

# Add View Queries and Typed View Configuration

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.

This plan is EP-4 of the MasterPlan `docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md`.


## Purpose / Big Picture

A Notion "view" is a saved way of looking at a database: a table, board, calendar, timeline, gallery, list, map, form, chart or dashboard, with its own filter, sort order and layout settings. The Haskell library `notion-client` can already create, retrieve, update, list and delete views, but it has two problems.

First, it cannot read the rows a view shows. Its `queryView` method posts to `views/{view_id}/query`, a URL Notion does not serve. An earlier plan in this repository recorded that Notion answers it with HTTP 400 `invalid_request_url` (`docs/plans/complete-api-coverage.md`, Surprises & Discoveries). The official Notion TypeScript SDK uses a three-step flow instead. You create a *view query*, which is a short-lived server-side snapshot of the rows the view matches. You page through its results. Then you delete it.

Second, everything interesting about a view comes back as untyped JSON (`Data.Aeson.Value`): its parent, filter, sorts, quick filters and layout configuration. The same applies when creating or updating a view. A user who wants to "group this board by Status" or "freeze the first column of this table" has to hand-assemble JSON and hope the shape is right. There is also no way to *clear* a view's filter, because the request encoder drops every absent field and never sends `null`.

After this plan is implemented, a Haskell user can:

- Call `createViewQuery`, `getViewQueryResults` and `deleteViewQuery`, or the one-shot helper `queryAllViewPages`, to get the IDs of every page a view shows, in the view's own order and with the view's own filter.
- Decode a retrieved view into typed Haskell values. The filter is a `Filter`, the sorts are `Sort`s, and the configuration is a `ViewConfig` such as `BoardConfig BoardViewConfig {groupBy = StatusGroupBy ...}`. Anything the library does not recognise is kept as raw JSON instead of failing.
- Build create and update requests from the same typed values, including placing a new view tab (`position`), placing a dashboard widget (`placement`) and creating a linked database (`create_database`).
- Clear a view's filter, sorts or quick filters, or any individual configuration field, by sending `null`.

You can see it working in three ways. Run `cabal test`: a new `Views (EP-4)` test group decodes and re-encodes JSON fixtures copied from the SDK's type definitions. Run `cabal run notion-client-example` with `NOTION_TOKEN` and `NOTION_TEST_DATABASE_ID` set: the views section creates a view, queries its rows, prints how many there are and deletes the query.


## Progress

- [x] Milestone 1: Added `PartialPageObject` to `src/Notion/V1/Pages.hs` (EP-4 started first). (2026-09-15)
- [x] Milestone 1: Added `CreateViewQuery`, `ViewQuery` (with `requestStatus`, since EP-2 landed), `DeletedViewQuery` and `ViewQueryID` to `src/Notion/V1/Views.hs`. (2026-09-15)
- [x] Milestone 1: Replaced the `views/{id}/query` route with the three `views/{id}/queries` routes; updated `Methods`, `makeMethodsWithEnv` and the effectful package (`Effect.hs`, `Interpreter.hs`, `Effectful.hs`). (2026-09-15)
- [x] Milestone 1: Added `src/Notion/V1/ViewQueries.hs` with `queryAllViewPages`; registered it in `notion-client.cabal`. (2026-09-15)
- [x] Milestone 1: Created `tasty/ViewTests.hs` with the "View queries" group (plus a `FakeNotion` test of `queryAllViewPages`), wired it into `notion-client.cabal` and `tasty/Main.hs`; fixed `tasty/Main.hs` imports and the E2E lifecycle test. (2026-09-15)
- [x] Milestone 1: Updated `notion-client-example/ViewDemo.hs` with the query flow; `cabal build all` and `cabal test` pass, and the live "View E2E" test passes. (2026-09-15)
- [x] Milestone 2: Added `src/Notion/V1/Clearable.hs` and registered it. (2026-09-15)
- [x] Milestone 2: Added `FromJSON` for `Filter`, `PropertyCondition`, all condition types, `SortDirection` and `Sort`, plus `ToJSON PropertyCondition`, in `src/Notion/V1/Filter.hs` (EP-4 was first). (2026-09-15)
- [x] Milestone 2: Added `ViewFilter`, `ViewSort`, `QuickFilter`, `ViewPropertySort`, `ViewPosition`, `WidgetPlacement`, `CreateDatabaseForView` and `UnknownViewType`; retyped `ViewObject`, `CreateView` and `UpdateView` (configuration still `Value`). (2026-09-15)
- [x] Milestone 2: Added the "Filters and sorts", "View object" and "View requests" test groups; updated the literals in `tasty/Main.hs` and `ViewDemo.hs`. All 15 EP-4 tests and the live "View E2E" pass. (2026-09-15)
- [ ] Milestone 3: Create `src/Notion/V1/ViewConfig.hs` with the enum helpers, shared pieces (property config, group-by union, subtasks, cover) and table, board, calendar, timeline, gallery and list configs, plus `ViewConfig` with an `UnknownViewConfig` fallback.
- [ ] Milestone 3: Switch `ViewObject.configuration`, `CreateView.configuration` and `UpdateView.configuration` to `ViewConfig`; add the "View configuration" test group.
- [ ] Milestone 4: Add the chart, map, form and dashboard configs and their enums; extend the tests.
- [ ] Milestone 4: Write the CHANGELOG `## Unreleased` entries, finish `ViewDemo.hs`, run the full validation, and fill in Outcomes & Retrospective.


## Surprises & Discoveries

- EP-2 had already landed, so `RequestStatus` exists in `src/Notion/V1/ListOf.hs` and `ViewQuery` carries `requestStatus :: Maybe RequestStatus`. `makeMethods` is now a wrapper over `makeMethodsWithEnv`; the views pattern binding lives there.
- The live API (2026-09-15, `Notion-Version: 2026-03-11`) confirms the query flow. `POST views/{id}/queries` with `{"page_size":1}` returned HTTP 200 with `total_count: 47`, one result, and a `next_cursor` equal to the ID of the next page. `GET views/{id}/queries/{query_id}?start_cursor=<that cursor>&page_size=1` returned exactly that page, and `DELETE` returned HTTP 200 with `deleted: true`. All three return 200, not 202, so plain servant verbs are correct. Responses also carry a top-level `request_id`, which the decoders ignore.

  ```text
  {"object":"view_query",...,"total_count":47,"results":[{"object":"page","id":"…"}],"next_cursor":"33399d8a-…-d13ad7e99abe","has_more":true}
  {"object":"list","results":[{"object":"page","id":"33399d8a-…-d13ad7e99abe"}],"next_cursor":"33399d8a-…-cf54c43d0175","has_more":true,"type":"page","page":{}}
  ```

- A freshly retrieved table view on that database had `"filter":null,"sorts":null,"quick_filters":null,"configuration":{"type":"table"}`, so `null` really does appear in responses for these fields.
- `cabal test --test-options='-p "Views (EP-4)"'` does not work: cabal splits `--test-options` on spaces and tasty rejects the fragment. Use `cabal test --test-option=--pattern=EP-4` instead.


## Decision Log

- Decision: Remove `queryView`, the `QueryView` type and the `POST views/{view_id}/query` route outright, instead of deprecating them. This is a breaking change.
  Rationale: The route has never existed in the official SDK. `git -C /Users/shinzui/Keikaku/hub/notion-sdk-js log -S '/query`' -- src/api-endpoints/views.ts` returns nothing. The commit that introduced views, `2e27ab5` ("Add Views API endpoints (#684)", 2026-03-19), added only `views/${p.view_id}/queries` and `views/${p.view_id}/queries/${p.query_id}`. This repository's own `docs/plans/complete-api-coverage.md` recorded that the route returns HTTP 400 `invalid_request_url`, and the E2E test in `tasty/Main.hs` (`testViewLifecycle`, "Step 5") deliberately skips it. A method that can only fail is worse than no method. The MasterPlan already releases this batch of work as the breaking version 0.8.0.0.
  Date: 2026-09-14

- Decision: Model "absent vs. null vs. value" with a new type `Clearable a = Unset | Clear | Set a` in a new module `Notion.V1.Clearable`. Its `ToJSON` instance overrides aeson's `omitField`, and its `FromJSON` instance overrides `omittedField`. `Maybe (Maybe a)` was rejected.
  Rationale: Notion's update-view body accepts `null` to clear `filter`, `sorts`, `quick_filters` and most configuration fields ("Pass null to clear" in `src/api-endpoints/common.ts`). `aesonOptions` sets `omitNothingFields = True` (`src/Notion/Prelude.hs` line 117), so a `Maybe` field can only be omitted, never sent as `null`. aeson 2.2, which the `aeson >=2.2 && <2.3` bound guarantees, generalised `omitNothingFields` to omit any field whose `omitField` returns `True`. It also added `omittedField` for decoding missing fields. A dedicated type therefore works with the existing `genericToJSON aesonOptions` and `genericParseJSON aesonOptions` without hand-written encoders. Its constructors also say what they mean at call sites, whereas `Just Nothing` does not.
  Date: 2026-09-14

- Decision: Use one set of configuration types for both responses and requests, rather than parallel `*Request` and `*Response` records. Fields the SDK marks `| null` on either side are `Clearable`. Response-only convenience fields (`property_name`, `date_property_name`, `end_date_property_name`, `map_by_property_name`) are decoded but stripped by the encoders.
  Rationale: The request and response shapes in `common.ts` and `views.ts` differ only in those few names, in nullability, in `cover.type: "page_content_first"` and in the dashboard configuration. Twenty-odd duplicated records would double the code and force users to convert. Stripping the response-only names lets a user retrieve a view, change one field and send the configuration back.
  Date: 2026-09-14

- Decision: `ViewObject.filter`, `sorts` and `quick_filters` use wrapper types with a raw fallback (`ViewFilter = ViewFilter Filter | RawViewFilter Value`, and likewise `ViewSort` and `QuickFilter`). Every sum type in `Notion.V1.ViewConfig` falls back to an `Unknown… Value` constructor both when the `type` is unrecognised and when the typed parse fails.
  Rationale: The MasterPlan's tolerant-decoding rule says a response must never fail to decode because of a shape the library does not know. The `Filter` DSL in `src/Notion/V1/Filter.hs` cannot represent everything a view may hold. For example, `select` operators accept arrays in views (common.ts `ViewFilterRequest` comment), and EP-5 owns adding those constructors. Wrapping keeps `Filter` itself unchanged except for the new `FromJSON` instance. The raw constructors also serve as escape hatches in requests, so users are never blocked by a missing type.
  Date: 2026-09-14

- Decision: Phase the work into four milestones: the query flow; typed filter, sorts and request fields; the configurations for table, board, calendar, timeline, gallery and list; then chart, map, form and dashboard.
  Rationale: The query flow is independent and immediately useful. `UnknownViewConfig Value` lets Milestone 3 ship before Milestone 4's types exist.
  Date: 2026-09-14

- Decision: The configuration records and group-by records use `genericParseJSON aesonOptions` and `genericToJSON aesonOptions`. Sum types and enums use hand-written instances.
  Rationale: The records' field names map one-to-one to the wire names under `camelToSnake`, and there are about 30 of them. Hand-writing each decoder would add hundreds of lines with no behavioral benefit. `src/Notion/V1/Common.hs`, `Pages.hs` and `DataSources.hs` already use `genericParseJSON aesonOptions`. The round-trip tests guard the mapping.
  Date: 2026-09-14

- Decision: Put `queryAllViewPages` in a new module `Notion.V1.ViewQueries` that imports `Notion.V1 (Methods (..))`. It is not a `Methods` field, so there is no effectful counterpart.
  Rationale: `Notion.V1` imports `Notion.V1.Views`, so the helper cannot live in `Views.hs` without an import cycle. A separate module also avoids more edits to the contested `src/Notion/V1.hs`. The effectful lockstep rule applies only to `Methods` fields.
  Date: 2026-09-14

- Decision: Name the `create_database` field of `CreateView` as `createDatabase_`.
  Rationale: `Methods` already has a field `createDatabase`. Under `DuplicateRecordFields`, a module importing both `Notion.V1 (Methods (..))` and `Notion.V1.Views` unqualified would get an ambiguous-selector error on every `createDatabase methods …` call. `labelModifier` in `src/Notion/Prelude.hs` drops the trailing underscore, so the wire name stays `create_database`. The same trick is already used for `type_`.
  Date: 2026-09-14

- Decision: View-query result elements use the shared `PartialPageObject` type from `src/Notion/V1/Pages.hs`, not a view-specific reference type. If the type is absent, this plan adds it with EP-5's exact definition (`newtype PartialPageObject = PartialPageObject {id :: PageID}`, deriving `Generic` and `Show`, decoding only `id`). The `Filter`/`Sort` decoders use EP-5's helper names (`parsePropertyCondition` and friends).
  Rationale: The coordinator decided that the partial-page type is shared between EP-4 and EP-5 (`docs/plans/10-type-data-source-database-and-search-results-and-close-query-and-filter-gaps.md`, Milestone 1) and that whichever plan starts first defines it. The same applies to the `Filter`/`Sort` `FromJSON` instances. Matching names and shapes exactly means the second plan to land compiles without edits.
  Date: 2026-09-14

- Decision: EP-4 defined `PartialPageObject` in `src/Notion/V1/Pages.hs` with exactly the shared definition, because EP-5 had not started. `ViewQuery` includes `requestStatus`, because EP-2's `RequestStatus` exists.
  Rationale: The MasterPlan's Integration Points assign the type to whichever of EP-4 and EP-5 starts first, and this plan's Milestone 1 makes `requestStatus` conditional on EP-2.
  Date: 2026-09-15

- Decision: Bind the results route as `getViewQueryResults_` in `makeMethodsWithEnv` and assign `getViewQueryResults = getViewQueryResults_`, and use a qualified `Notion.V1.Views` import for the query types in `tasty/Main.hs`.
  Rationale: The first follows the existing convention for routes whose `Methods` field has per-argument Haddock comments (`listViews_`, `listUsers_`). The second is needed because importing `ViewQuery (..)` unqualified would make the `results` and `hasMore` selector functions used elsewhere in `tasty/Main.hs` ambiguous under `DuplicateRecordFields`.
  Date: 2026-09-15

- Decision: EP-4 added the `Filter`/`Sort`/`PropertyCondition` decoders, using the helper names `parsePropertyCondition`, `parseTextCondition`, `parseDateCondition` and so on, plus two small private helpers `flagKey` (for `{"is_empty": true}`) and `emptyKey` (for relative dates such as `{"next_week": {}}`). The round-trip test also covers `CreatedTime`/`CreatedBy`/`LastEditedTime`/`LastEditedBy`/`Url`/`Email`/`PhoneNumber` conditions and `RollupNumber`, beyond the minimum the plan listed.
  Rationale: EP-5 had not started, so under the MasterPlan's Integration Points this plan owns the instances. EP-5 can extend the parsers in place.
  Date: 2026-09-15

- Decision: Add `UnknownViewType Text` to `ViewType` in this plan.
  Rationale: The tolerant-decoding rule applies. `ViewType` currently calls `fail` on unknown strings (`src/Notion/V1/Views.hs` line 57), and the MasterPlan assigns no other plan to it.
  Date: 2026-09-14


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation


### The repository

The repository root is `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`. It is a cabal project (`cabal.project` lists `.` and `notion-client-effectful`), built with GHC 9.12.2 and `default-language: GHC2024`. It contains three things:

- **The library `notion-client`**, with sources under `src/`.
- **The companion library `notion-client-effectful`**, under `notion-client-effectful/`. It re-exposes every API method as an `effectful` effect.
- **A test suite and an example program.** The test suite `tasty` lives under `tasty/` and currently has only `tasty/Main.hs`. The example executable `notion-client-example` lives under `notion-client-example/`.

Build everything with `cabal build all` and run the tests with `cabal test`. A git pre-commit hook runs `treefmt`, which may reformat files. If a commit is rejected because files changed, re-stage them and commit again.

Every component enables these default extensions (see `notion-client.cabal`):

- `DuplicateRecordFields`: several record types may share a field name such as `id` or `name`.
- `OverloadedStrings`: string literals can be `Text` or JSON keys.
- `RecordWildCards`: `Foo {..}` binds or fills every field.
- `OverloadedLabels`.

GHC2024 also turns on `LambdaCase` and `NamedFieldPuns`. Modules with a record field called `id` write `import Prelude hiding (id)`.

### JSON conventions

The shared prelude `src/Notion/Prelude.hs` re-exports a selection of `Data.Aeson`: `FromJSON (..)`, `ToJSON (..)`, `Value (..)`, `genericToJSON` and `genericParseJSON`. It also re-exports `Text`, `Vector`, `Map`, `Natural`, `Generic` and the Servant combinators. It defines `aesonOptions`, whose `fieldLabelModifier` first drops a trailing underscore and then converts camelCase to snake_case, so `type_` becomes `type` and `dataSourceId` becomes `data_source_id`. It also sets `omitNothingFields = True`, so `Nothing` fields are left out of encoded JSON. `parseISO8601 :: Text -> Parser POSIXTime` parses Notion timestamps.

Response decoders are usually hand-written. They pattern-match `Object o` with `LambdaCase` and read fields with `o .: "key"` (required) and `o .:? "key"` (optional; a missing key or `null` gives `Nothing`). Request encoders usually use `genericToJSON aesonOptions`.

In this plan, **tolerant decoding** means that every closed enumeration or sum type decoded from a response has a fallback constructor that keeps the raw value. An unknown string becomes `UnknownX Text` and an unknown object becomes `UnknownX Value`, so a new Notion feature never makes a whole response fail to parse.

### How an endpoint is wired

Each resource module, such as `src/Notion/V1/Views.hs`, defines its request and response types and a Servant `API` type. Servant describes an HTTP API as a Haskell type, and `:<|>` separates alternative routes.

`src/Notion/V1.hs` combines every resource `API` into one `API` type. It also defines:

- `data Methods`, a record of plain `IO` functions, one per endpoint.
- `makeMethods :: ClientEnv -> Text -> Methods`, which runs `Client.client @API Proxy` and destructures the result with one large pattern binding. Each name in that pattern must sit in exactly the same position as its route in the `API` type.

Today the views part of that pattern (around lines 122–128) reads `createView :<|> retrieveView :<|> updateView :<|> deleteView :<|> listViews_ :<|> queryView`. The `Methods` fields are declared around lines 256–271.

### The effectful companion

The effectful companion must change in lockstep: whenever a `Methods` field is added, removed or retyped, three files change in the same commit.

- `notion-client-effectful/src/Notion/V1/Effectful/Effect.hs` has the `Notion` GADT (one constructor per field, for example `QueryView :: Views.ViewID -> Views.QueryView -> Notion m (ListOf PageObject)` at line 164), an export list, and a smart constructor per field (for example `queryView` at lines 384–386). The module header promises each smart constructor has "the same name, same argument order, and same argument types as the corresponding `Methods` field".
- `notion-client-effectful/src/Notion/V1/Effectful/Interpreter.hs` imports each constructor by name (lines 23–64) and has one case per constructor (views at lines 121–128).
- `notion-client-effectful/src/Notion/V1/Effectful.hs` re-exports the smart constructors (`queryView` appears at lines 76 and 112).

### Current view code

`src/Notion/V1/Views.hs`, 182 lines, defines the following:

- `ViewType`: ten constructors (`TableView`, `BoardView`, `ListViewType`, `CalendarView`, `TimelineView`, `GalleryView`, `FormView`, `ChartView`, `MapView`, `DashboardView`). Its `FromJSON` instance fails on unknown values.
- `ViewObject`: a hand-written decoder, with `parent :: Maybe Value`, `filter :: Maybe Value`, `sorts :: Maybe (Vector Value)`, `quickFilters :: Maybe Value` and `configuration :: Maybe Value`. Most fields are `Maybe` because list and delete responses return partial objects.
- `CreateView`: `dataSourceId`, `name`, `type_`, `databaseId`, `viewId`, `filter`, `sorts`, `quickFilters`, `configuration`, `position`; the last five are `Value`.
- `UpdateView`: `name`, `filter`, `sorts`, `quickFilters`, `configuration`, all `Maybe`.
- `QueryView`: `{startCursor, pageSize}`.
- The `API`: create `POST views`, get `GET views/{id}`, update `PATCH views/{id}`, delete `DELETE views/{id}`, list `GET views?database_id&data_source_id&start_cursor&page_size`, and the bogus `POST views/{id}/query` returning `ListOf PageObject`.

The other relevant modules:

- `src/Notion/V1/ListOf.hs` defines the paginated envelope `data ListOf a = List {results, nextCursor, hasMore, type_, object}`.
- `src/Notion/V1/Common.hs` defines `newtype UUID = UUID {text :: Text}` (with `Eq`, `IsString`) and `data Parent`, whose decoder already handles `{"type":"database_id","database_id":…}` as `DatabaseParent`.
- `src/Notion/V1/Users.hs` defines `UserReference {id, object}`.
- `src/Notion/V1/Filter.hs`, 416 lines, is a typed query DSL:
  - `data Filter = And [Filter] | Or [Filter] | PropertyFilter Text PropertyCondition | TimestampFilter TimestampType DateCondition`.
  - `PropertyCondition` has 22 constructors, each wrapping a condition type: `TextCondition`, `NumberCondition` (numbers are `Scientific`), `CheckboxCondition`, `SelectCondition`, `MultiSelectCondition`, `DateCondition`, `PeopleCondition`, `FilesCondition`, `RelationCondition`, `StatusCondition`, `UniqueIdCondition` (`Natural`), `VerificationCondition`, `FormulaCondition` and `RollupCondition`.
  - The sort types are `data SortDirection = Ascending | Descending` and `data Sort = PropertySort Text SortDirection | TimestampSort TimestampType SortDirection`.
  - Every type there has `ToJSON` only. The encoders are the private functions `textConditionToValue`, `propertyConditionToObject` and so on. There is **no `FromJSON`**; confirm with `grep -n "FromJSON" src/Notion/V1/Filter.hs`, which prints nothing today.

The code that uses views:

- `notion-client-example/ViewDemo.hs` creates a table view, retrieves, updates (with a raw JSON sort), lists and deletes it. `notion-client-example/Main.hs` calls `runViewDemo methods databaseIdStr` when `NOTION_TEST_DATABASE_ID` is set.
- `tasty/Main.hs` imports `Notion.V1.Views (CreateView (..), QueryView (..), UpdateView (..), ViewObject (..), ViewType (..))` at line 50. It has unit tests `testSerializeCreateView` and `testSerializeUpdateView` (lines 882–930) that build full record literals. Its E2E test `testViewLifecycle` (lines 1301–1356) binds `queryView` in its pattern but never calls it. The top-level group list is assembled in `tests` at lines 159–171.

### Architecture Decision Records

This repository has no `docs/adr/` directory; no relevant ADR exists.

### Integration with other plans

These come from the parent MasterPlan:

- **`ListOf` and `RequestStatus`.** They belong to EP-2 (`docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md`), which adds `requestStatus :: Maybe RequestStatus` to `ListOf` in `src/Notion/V1/ListOf.hs`. This plan consumes it as a soft dependency. `getViewQueryResults` returns `ListOf`, so it gains the field automatically once EP-2 lands. The `ViewQuery` record gets its own `requestStatus` field only if `RequestStatus` already exists when Milestone 1 is implemented. Check with `grep -n "data RequestStatus" src/Notion/V1/ListOf.hs`. If it does not exist, leave the field out and record that in the Decision Log.
- **`FromJSON` for `Filter` and `Sort`.** Whichever of EP-4 and EP-5 (`docs/plans/10-type-data-source-database-and-search-results-and-close-query-and-filter-gaps.md`) starts first adds these instances; the other consumes them. EP-5 owns every *new* filter condition constructor. This plan must not add constructors to `PropertyCondition` or the condition types.
- **`PartialPageObject`** (`{"object":"page","id":…}`, in `src/Notion/V1/Pages.hs`). It is shared with EP-5, and whichever plan starts first defines it with the exact shape given in Milestone 1. The other plan reuses it.
- **`makeMethods`.** EP-2 may restructure `makeMethods` into a wrapper over a configurable constructor. If it has, the pattern binding described above lives wherever `Client.hoistClient @API` is now called. Find it with `grep -n "listViews_" src/Notion/V1.hs`.
- **Tests.** New tests go in a new module `tasty/ViewTests.hs` exporting `tests :: TestTree`. It is listed under `other-modules` of `test-suite tasty` in `notion-client.cabal` and added with one line in the top-level `testGroup` in `tasty/Main.hs`. Fixtures never use the maintainer's real name; use invented names such as "Tanaka Hanako" or "Sato Kenji".
- **CHANGELOG.** Entries go under a single `## Unreleased` heading at the top of `CHANGELOG.md`, which must be created if absent, in `### Breaking Changes` / `### New Features` / `### Bug Fixes` subsections. Do not change the package version.

### Wire shapes from the official SDK

These are transcribed from `/Users/shinzui/Keikaku/hub/notion-sdk-js` at v5.26.0, from `src/api-endpoints/views.ts` and `src/api-endpoints/common.ts`, so you do not need to open that repository. `IdRequest` and `IdResponse` are strings.

The three view-query endpoints (views.ts lines 940–1030):

```typescript
// POST views/{view_id}/queries      body: CreateViewQueryRequest
export type CreateViewQueryRequest = { page_size?: number } // max 100

export type ViewQueryResponse = {
  object: "view_query"
  id: IdResponse            // the query ID
  view_id: IdResponse
  expires_at: string        // ISO 8601; when the cached results expire
  total_count: number
  results: Array<{ object: string; id: IdResponse }>   // first page, references only
  next_cursor: IdResponse | null
  has_more: boolean
  request_status?: { type: "complete" | "incomplete"; incomplete_reason?: "query_result_limit_reached" }
}

// GET views/{view_id}/queries/{query_id}?start_cursor=&page_size=
export type GetViewQueryResultsResponse = {
  object: "list"
  next_cursor: IdResponse | null
  has_more: boolean
  results: Array<{ object: "page"; id: IdResponse }>
  type: "page"
  page: EmptyObject
  request_status?: RequestStatusResponse
}

// DELETE views/{view_id}/queries/{query_id}
export type DeletedViewQueryResponse = { object: "view_query"; id: IdResponse; deleted: boolean }
```

The view object (views.ts lines 231–277; list and delete return the partial form `{object:"view", id, parent, type}`):

```typescript
export type DataSourceViewObjectResponse = {
  object: "view"
  id: IdResponse
  parent: { type: "database_id"; database_id: IdResponse }
  name: string
  type: "table" | "board" | "list" | "calendar" | "timeline" | "gallery" | "form" | "chart" | "map" | "dashboard"
  created_time: string
  last_edited_time: string
  url: string
  data_source_id?: string | null
  created_by?: PartialUserObjectResponse | null
  last_edited_by?: PartialUserObjectResponse | null
  filter?: ViewFilterResponse | null        // same shape as a data source query filter
  sorts?: Array<{ property: string; direction: "ascending" | "descending" }
               | { timestamp: "created_time" | "last_edited_time"; direction: "ascending" | "descending" }> | null
  quick_filters?: Record<string, QuickFilterCondition> | null  // key: property ID; value: e.g. { "select": { "equals": "High" } }
  configuration?: ViewConfigResponse | null
  dashboard_view_id?: string
}
```

The create and update request bodies (common.ts lines 314–332, 339–381, 1579–1596, 1660–1675, 1702–1709 and 1739–1753):

```typescript
export type CreateViewRequest = {
  data_source_id: IdRequest
  name: string
  type: ViewTypeRequest
  database_id?: IdRequest          // mutually exclusive with view_id and create_database
  view_id?: IdRequest              // dashboard view to add this view to as a widget
  filter?: ViewFilterRequest
  sorts?: Array<PropertySort | TimestampSort>
  quick_filters?: Record<string, QuickFilterConditionRequest>
  create_database?: {
    parent: { type: "page_id"; page_id: IdRequest }
    position?: { type: "after_block"; block_id: IdRequest }
  }
  configuration?: ViewConfigRequest
  position?: { type: "start" } | { type: "end" } | { type: "after_view"; view_id: IdRequest }
  placement?: { type: "new_row"; row_index?: number } | { type: "existing_row"; row_index: number }
}

export type UpdateViewRequest = {
  name?: string
  filter?: ViewFilterRequest | null                                        // null clears
  sorts?: Array<{ property: string; direction: "ascending" | "descending" }> | null  // property sorts only; null clears
  quick_filters?: Record<string, QuickFilterConditionRequest | null> | null // key null removes one; whole null clears all
  configuration?: ViewConfigRequest                                         // nullable fields inside may be null to clear them
}
```

Configurations are discriminated by `type`. The request union (common.ts line 1637) has nine members, with no dashboard. The response union (views.ts line 653) has ten. The comments mark `(req)` for request-only facts and `(resp)` for response-only fields. `?:` means the key may be absent, and `| null` means `null` is accepted (in requests, to clear).

```typescript
type TableViewConfig = {
  type: "table"
  properties?: Array<ViewPropertyConfig> | null
  group_by?: GroupByConfig | null
  subtasks?: SubtaskConfig | null
  wrap_cells?: boolean
  frozen_column_index?: number
  show_vertical_lines?: boolean
}
type BoardViewConfig = {
  type: "board"
  group_by: GroupByConfig                        // required
  sub_group_by?: GroupByConfig | null
  properties?: Array<ViewPropertyConfig> | null
  cover?: CoverConfig | null
  cover_size?: "small" | "medium" | "large" | null
  cover_aspect?: "contain" | "cover" | null
  card_layout?: "list" | "compact" | null
}
type CalendarViewConfig = {
  type: "calendar"
  date_property_id: string                       // required
  date_property_name?: string                    // (resp)
  properties?: Array<ViewPropertyConfig> | null
  view_range?: "week" | "month" | null
  show_weekends?: boolean | null
}
type TimelineViewConfig = {
  type: "timeline"
  date_property_id: string                       // required
  date_property_name?: string                    // (resp)
  end_date_property_id?: string | null
  end_date_property_name?: string                // (resp)
  properties?: Array<ViewPropertyConfig> | null
  show_table?: boolean | null
  table_properties?: Array<ViewPropertyConfig> | null
  preference?: { zoom_level: "hours" | "day" | "week" | "bi_week" | "month" | "quarter" | "year" | "5_years";
                 center_timestamp?: number } | null     // ms since epoch
  arrows_by?: { property_id?: string | null } | null
  color_by?: boolean | null
}
type GalleryViewConfig = {
  type: "gallery"
  properties?: Array<ViewPropertyConfig> | null
  cover?: CoverConfig | null
  cover_size?: "small" | "medium" | "large" | null
  cover_aspect?: "contain" | "cover" | null
  card_layout?: "list" | "compact" | null
}
type ListViewConfig = { type: "list"; properties?: Array<ViewPropertyConfig> | null }
type MapViewConfig = {
  type: "map"
  height?: "small" | "medium" | "large" | "extra_large" | null
  map_by?: string | null
  map_by_property_name?: string                  // (resp)
  properties?: Array<ViewPropertyConfig> | null
}
type FormViewConfig = {
  type: "form"
  is_form_closed?: boolean | null
  anonymous_submissions?: boolean | null
  submission_permissions?: "none" | "comment_only" | "reader" | "read_and_write" | "editor" | null
}
type ChartViewConfig = {
  type: "chart"
  chart_type: "column" | "bar" | "line" | "donut" | "number"   // required
  x_axis?: GroupByConfig | null
  y_axis?: ChartAggregation | null
  x_axis_property_id?: string | null
  y_axis_property_id?: string | null
  value?: ChartAggregation | null
  sort?: "manual" | "x_ascending" | "x_descending" | "y_ascending" | "y_descending" | null
  color_theme?: "gray" | "blue" | "yellow" | "green" | "purple" | "teal" | "orange" | "pink" | "red" | "auto" | "colorful" | null
  height?: "small" | "medium" | "large" | "extra_large" | null
  hide_empty_groups?: boolean | null
  legend_position?: "off" | "bottom" | "side" | null
  show_data_labels?: boolean | null
  axis_labels?: "none" | "x_axis" | "y_axis" | "both" | null
  grid_lines?: "none" | "horizontal" | "vertical" | "both" | null
  cumulative?: boolean | null
  smooth_line?: boolean | null
  hide_line_fill_area?: boolean | null
  group_style?: "normal" | "percent" | "side_by_side" | null
  y_axis_min?: number | null
  y_axis_max?: number | null
  donut_labels?: "none" | "value" | "name" | "name_and_value" | null
  hide_title?: boolean | null
  stack_by?: GroupByConfig | null
  reference_lines?: Array<ChartReferenceLine> | null
  caption?: string | null
  color_by_value?: boolean | null
}
type DashboardViewConfig = {                     // (resp) only
  type: "dashboard"
  rows: Array<{ id: string; widgets: Array<{ id: string; view_id: string; width?: number; row_index?: number }>; height?: number }>
}

type ChartAggregation = {
  aggregator: "count" | "count_values" | "sum" | "average" | "median" | "min" | "max" | "range" | "unique"
            | "empty" | "not_empty" | "percent_empty" | "percent_not_empty" | "checked" | "unchecked"
            | "percent_checked" | "percent_unchecked" | "earliest_date" | "latest_date" | "date_range"
  property_id?: string                           // required for everything except "count"
}
type ChartReferenceLine = {
  id: string                                     // required in responses, optional in requests
  value: number
  label: string
  color: "gray" | "lightgray" | "brown" | "yellow" | "orange" | "green" | "blue" | "purple" | "pink" | "red"
  dash_style: "solid" | "dash"
}
type ViewPropertyConfig = {
  property_id: string
  property_name?: string                         // (resp)
  visible?: boolean
  width?: number
  wrap?: boolean
  status_show_as?: "select" | "checkbox"
  card_property_width_mode?: "full_line" | "inline"
  date_format?: "full" | "short" | "month_day_year" | "day_month_year" | "year_month_day" | "relative"
  time_format?: "12_hour" | "24_hour" | "hidden"
}
type SubtaskConfig = {
  property_id?: string
  display_mode?: "show" | "hidden" | "flattened" | "disabled"
  filter_scope?: "parents" | "parents_and_subitems" | "subitems"
  toggle_column_id?: string
}
type CoverConfig = { type: "page_cover" | "page_content" | "page_content_first" /* (resp) */ | "property"; property_id?: string }
type GroupSort = { type: "manual" | "ascending" | "descending" }

type GroupByConfig =   // every member also has property_name?: string (resp) and hide_empty_groups?: boolean
  | { type: "select" | "multi_select"; property_id: string; sort: GroupSort }
  | { type: "status"; property_id: string; group_by: "group" | "option"; sort: GroupSort }
  | { type: "person" | "created_by" | "last_edited_by"; property_id: string; sort: GroupSort }
  | { type: "relation"; property_id: string; sort: GroupSort }
  | { type: "date" | "created_time" | "last_edited_time"; property_id: string;
      group_by: "relative" | "day" | "week" | "month" | "year"; sort: GroupSort; start_day_of_week?: 0 | 1 }
  | { type: "text" | "title" | "url" | "email" | "phone_number"; property_id: string;
      group_by: "exact" | "alphabet_prefix"; sort: GroupSort }
  | { type: "number"; property_id: string; sort: GroupSort; range_start?: number; range_end?: number; range_size?: number }
  | { type: "checkbox"; property_id: string; sort: GroupSort }
  | { type: "formula"; property_id: string; group_by: FormulaSubGroupBy }

type FormulaSubGroupBy =
  | { type: "date"; group_by: "relative" | "day" | "week" | "month" | "year"; sort: GroupSort; start_day_of_week?: 0 | 1 }
  | { type: "text"; group_by: "exact" | "alphabet_prefix"; sort: GroupSort }
  | { type: "number"; sort: GroupSort; range_start?: number; range_end?: number; range_size?: number }
  | { type: "checkbox"; sort: GroupSort }
```


## Plan of Work

The work proceeds in four milestones. Each one leaves the repository building, with all tests passing.


### Milestone 1: the view-query flow

At the end of this milestone, a user can ask Notion for the rows of a view. The bogus `queryView` is gone, and three new `Methods` fields and one helper exist.

The query results are partial pages, which the SDK types as `{object: "page", id}`. EP-5 (`docs/plans/10-type-data-source-database-and-search-results-and-close-query-and-filter-gaps.md`) needs the same type for data source query and search results. The two plans share one definition, `PartialPageObject` in `src/Notion/V1/Pages.hs`, and whichever plan starts first adds it. Check first:

```bash
cd /Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client
grep -n "PartialPageObject" src/Notion/V1/Pages.hs
```

If the type exists, reuse it unchanged and note in the Decision Log that it was consumed from EP-5. Otherwise, add it to `src/Notion/V1/Pages.hs` exactly as EP-5 defines it, and add `PartialPageObject (..)` to that module's export list. `PageID` is the existing alias at `Pages.hs` line 49, and `(.:)` is already imported at line 36.

```haskell
-- | @{"object":"page","id":...}@
newtype PartialPageObject = PartialPageObject {id :: PageID}
  deriving stock (Generic, Show)

instance FromJSON PartialPageObject where
  parseJSON = \case
    Object o -> PartialPageObject <$> o .: "id"
    _ -> fail "Expected object for PartialPageObject"
```

Do not add fields or instances to it, such as an `object` field or `Eq`. A different shape would break EP-5's code when the second plan lands. The view-query `results` elements carry `object: string` in the SDK, but only the `id` is needed.

In `src/Notion/V1/Views.hs`, remove `QueryView` (the type, its instance and its export). Change `import Notion.V1.Pages (PageObject)` to `import Notion.V1.Pages (PartialPageObject)`. Re-export `PartialPageObject (..)` from `Notion.V1.Views` for convenience. Add the following types and export them:

```haskell
-- | View query ID
type ViewQueryID = UUID

-- | Body of @POST views/{view_id}/queries@.
newtype CreateViewQuery = CreateViewQuery
  { pageSize :: Maybe Natural
  }
  deriving stock (Generic, Show)

instance ToJSON CreateViewQuery where
  toJSON = genericToJSON aesonOptions

-- | Response of @POST views/{view_id}/queries@: a cached query plus its first page.
data ViewQuery = ViewQuery
  { id :: ViewQueryID,
    viewId :: ViewID,
    expiresAt :: POSIXTime,
    totalCount :: Natural,
    results :: Vector PartialPageObject, -- the SDK's {object, id} references; only id is kept
    nextCursor :: Maybe Text,
    hasMore :: Bool
    -- If EP-2's RequestStatus exists in Notion.V1.ListOf, also add:
    -- requestStatus :: Maybe RequestStatus
  }
  deriving stock (Generic, Show)

instance FromJSON ViewQuery where
  parseJSON = \case
    Object o -> do
      id <- o .: "id"
      viewId <- o .: "view_id"
      expiresAt <- o .: "expires_at" >>= parseISO8601
      totalCount <- o .: "total_count"
      results <- o .: "results"
      nextCursor <- o .:? "next_cursor"
      hasMore <- o .: "has_more"
      pure ViewQuery {..}
    _ -> fail "Expected object for ViewQuery"

-- | Response of @DELETE views/{view_id}/queries/{query_id}@.
data DeletedViewQuery = DeletedViewQuery
  { id :: ViewQueryID,
    deleted :: Bool
  }
  deriving stock (Generic, Show)

instance FromJSON DeletedViewQuery where
  parseJSON = \case
    Object o -> DeletedViewQuery <$> o .: "id" <*> o .: "deleted"
    _ -> fail "Expected object for DeletedViewQuery"
```

In the same file, replace the last alternative of `API` (the `"query"` route) with three routes, in this order:

```haskell
           :<|> Capture "view_id" ViewID
           :> "queries"
           :> ReqBody '[JSON] CreateViewQuery
           :> Post '[JSON] ViewQuery
           :<|> Capture "view_id" ViewID
           :> "queries"
           :> Capture "query_id" ViewQueryID
           :> QueryParam "start_cursor" Text
           :> QueryParam "page_size" Natural
           :> Get '[JSON] (ListOf PartialPageObject)
           :<|> Capture "view_id" ViewID
           :> "queries"
           :> Capture "query_id" ViewQueryID
           :> Delete '[JSON] DeletedViewQuery
```

In `src/Notion/V1.hs`, replace `:<|> queryView` in the `makeMethods` pattern with `:<|> createViewQuery :<|> getViewQueryResults :<|> deleteViewQuery`, one per line and in that order. Also replace the `queryView` field of `Methods` with:

```haskell
    createViewQuery :: Views.ViewID -> Views.CreateViewQuery -> IO Views.ViewQuery,
    getViewQueryResults ::
      Views.ViewID ->
      Views.ViewQueryID ->
      Maybe Text ->
      -- \^ start_cursor
      Maybe Natural ->
      -- \^ page_size
      IO (ListOf PartialPageObject),
    deleteViewQuery :: Views.ViewID -> Views.ViewQueryID -> IO Views.DeletedViewQuery,
```

Add `PartialPageObject` to the existing `import Notion.V1.Pages (…)` list in `src/Notion/V1.hs`. `PageObject` stays in that list because `createPage` still uses it.

Apply the lockstep in `notion-client-effectful`:

- In `Effect.hs`, replace the `QueryView` constructor with `CreateViewQuery :: Views.ViewID -> Views.CreateViewQuery -> Notion m Views.ViewQuery`, `GetViewQueryResults :: Views.ViewID -> Views.ViewQueryID -> Maybe Text -> Maybe Natural -> Notion m (ListOf PartialPageObject)` (import `PartialPageObject` by adding it to the existing `Notion.V1.Pages (…)` import list) and `DeleteViewQuery :: Views.ViewID -> Views.ViewQueryID -> Notion m Views.DeletedViewQuery`.
- Still in `Effect.hs`, replace the `queryView` smart constructor and its export with `createViewQuery`, `getViewQueryResults` and `deleteViewQuery`, each documented as `-- | See 'Notion.V1.Methods'.'Notion.V1.createViewQuery'.` and so on. The implementations are `send (CreateViewQuery vid req)`, `send (GetViewQueryResults vid qid cursor size)` and `send (DeleteViewQuery vid qid)`.
- In `Interpreter.hs`, swap `QueryView` in the import list for the three new constructors. Replace its case with `CreateViewQuery vid req -> runIO (Notion.createViewQuery methods vid req)`, `GetViewQueryResults vid qid c s -> runIO (Notion.getViewQueryResults methods vid qid c s)` and `DeleteViewQuery vid qid -> runIO (Notion.deleteViewQuery methods vid qid)`.
- In `Effectful.hs`, replace `queryView` in both the export list and the import list with the three new names.

Create `src/Notion/V1/ViewQueries.hs` and add `Notion.V1.ViewQueries` to `exposed-modules` in `notion-client.cabal`, in alphabetical order after `Notion.V1.Users`. The helper creates a query, follows cursors until `hasMore` is false, and always deletes the query afterwards. A failure to delete is ignored, because the query expires on its own at `expires_at`.

```haskell
-- | Convenience helpers for the view-query flow.
module Notion.V1.ViewQueries
  ( queryAllViewPages,
  )
where

import Control.Exception qualified as Exception
import Data.Vector qualified as Vector
import Notion.Prelude
import Notion.V1 (Methods (..))
import Notion.V1.ListOf (ListOf (..))
import Notion.V1.Pages (PartialPageObject)
import Notion.V1.Views (CreateViewQuery (..), ViewID, ViewQuery (..))
import Prelude hiding (id)

-- | Create a view query, collect every result page, then delete the query.
--
-- The page size (max 100) applies to every request. Errors from the final
-- delete are swallowed: the cached query expires on its own.
queryAllViewPages :: Methods -> ViewID -> Maybe Natural -> IO (Vector PartialPageObject)
queryAllViewPages Methods {createViewQuery, getViewQueryResults, deleteViewQuery} viewId pageSize = do
  ViewQuery {id = queryId, results = firstPage, nextCursor, hasMore} <-
    createViewQuery viewId CreateViewQuery {pageSize}
  let cleanup = do
        _ <- Exception.try @Exception.SomeException (deleteViewQuery viewId queryId)
        pure ()
      go acc (Just cursor) True = do
        List {results, nextCursor = next, hasMore = more} <-
          getViewQueryResults viewId queryId (Just cursor) pageSize
        go (acc <> results) next more
      go acc _ _ = pure acc
  go firstPage nextCursor hasMore `Exception.finally` cleanup
```

The `ListOf` pattern uses field puns, so it keeps compiling when EP-2 adds `requestStatus` to `List`. `Data.Vector` may turn out to be unused; remove that import if `-Wall` warns.

Create the test module `tasty/ViewTests.hs`, exporting `tests :: TestTree` as `testGroup "Views (EP-4)" [viewQueryTests]`. The "View queries" group contains:

- A test decoding the `ViewQuery` fixture below. It asserts `totalCount == 3`, two results, `hasMore == True` and `nextCursor == Just "66666666-7777-4888-9999-aaaaaaaaaaaa"`.
- A test decoding the results-list fixture as `ListOf PartialPageObject`. It asserts one result whose `id` is `UUID "bbbbbbbb-cccc-4ddd-8eee-ffffffffffff"` and `hasMore == False`. `PartialPageObject` has no `Eq` instance, so compare the `id` fields, which are `UUID` and do have `Eq`.
- A test decoding the delete fixture. It asserts `deleted == True`.
- A test encoding `CreateViewQuery {pageSize = Just 50}`, which must equal `{"page_size":50}`, and `CreateViewQuery {pageSize = Nothing}`, which must equal `{}`.

```json
{
  "object": "view_query",
  "id": "7f1c2a9e-3b4d-4e5f-8a6b-1c2d3e4f5a6b",
  "view_id": "2b3c4d5e-6f70-4812-9a3b-4c5d6e7f8091",
  "expires_at": "2026-09-14T19:15:00.000Z",
  "total_count": 3,
  "results": [
    { "object": "page", "id": "11111111-2222-4333-8444-555555555555" },
    { "object": "page", "id": "66666666-7777-4888-9999-aaaaaaaaaaaa" }
  ],
  "next_cursor": "66666666-7777-4888-9999-aaaaaaaaaaaa",
  "has_more": true
}
```

```json
{
  "object": "list",
  "next_cursor": null,
  "has_more": false,
  "results": [{ "object": "page", "id": "bbbbbbbb-cccc-4ddd-8eee-ffffffffffff" }],
  "type": "page",
  "page": {}
}
```

```json
{ "object": "view_query", "id": "7f1c2a9e-3b4d-4e5f-8a6b-1c2d3e4f5a6b", "deleted": true }
```

Write the fixtures as Haskell string literals and decode them with `Aeson.eitherDecode`. A small helper keeps this short:

```haskell
decodeOrFail :: (Aeson.FromJSON a) => L8.ByteString -> IO a
decodeOrFail bytes = either (assertFailure . ("decode failed: " <>)) pure (Aeson.eitherDecode bytes)

jsonValue :: L8.ByteString -> Aeson.Value
jsonValue bytes = either error id (Aeson.eitherDecode bytes)
```

Wire the test module in as follows:

- In `notion-client.cabal`, add `other-modules: ViewTests` to `test-suite tasty` (the stanza has no `other-modules` today; if another plan already added it, append `ViewTests` to its list).
- In `tasty/Main.hs`, add `import ViewTests qualified`, and add `ViewTests.tests` to the list inside `testGroup "Notion Client Tests"` (currently `[jsonParsingTests, …, viewE2E]`).
- Still in `tasty/Main.hs`, remove `QueryView (..)` from the line-50 import, and change the `testViewLifecycle` pattern from `queryView` to `createViewQuery, getViewQueryResults, deleteViewQuery`.
- Replace the "Step 5" comment block with a real query step:

```haskell
  -- Step 5: Query the view's rows through the view-query flow
  query <- createViewQuery viewId CreateViewQuery {pageSize = Just 10}
  let ViewQuery {id = queryId, totalCount, results = firstPage} = query
  assertBool "first page is no larger than total_count" (fromIntegral (Vector.length firstPage) <= totalCount)
  page2 <- getViewQueryResults viewId queryId Nothing (Just 10)
  assertBool "results page decodes" (Vector.length (results page2) >= 0)
  DeletedViewQuery {deleted} <- deleteViewQuery viewId queryId
  assertBool "query deleted" deleted
```

Import `CreateViewQuery (..)`, `ViewQuery (..)` and `DeletedViewQuery (..)` from `Notion.V1.Views` in `tasty/Main.hs`.

In `notion-client-example/ViewDemo.hs`, add a new part between "List Views" and "Delete the view", titled `Views: Query View Rows`. It does four things:

1. Calls `createViewQuery methods viewId CreateViewQuery {pageSize = Just 5}` and prints `id`, `totalCount`, `expiresAt` and the number of results.
2. If `hasMore` is true, calls `getViewQueryResults methods viewId queryId nextCursor (Just 5)` and prints the count.
3. Calls `deleteViewQuery` and prints `deleted`.
4. Calls `queryAllViewPages methods viewId (Just 100)` and prints how many page references came back.

Update the module header comment to list "Query a view's rows". Import `Notion.V1.ViewQueries (queryAllViewPages)` and `Control.Monad (when)`.

Acceptance: `cabal build all` succeeds with no new warnings, and `cabal test` shows the "View queries" tests passing.


### Milestone 2: `Clearable`, filter and sort decoding, and typed request fields

At the end of this milestone, a retrieved view exposes its parent, filter, sorts and quick filters as typed values, with a raw fallback. Create requests accept typed `position`, `placement` and `create_database`. Update requests can clear fields. `configuration` stays `Value` until Milestone 3.

Create `src/Notion/V1/Clearable.hs` and add `Notion.V1.Clearable` to `exposed-modules`:

```haskell
-- | A request field that can be left out, explicitly cleared with JSON @null@,
-- or set to a value.
--
-- Inside a record encoded with 'genericToJSON' 'aesonOptions', 'Unset' omits
-- the key entirely, 'Clear' writes @null@, and 'Set' writes the value. When
-- decoded with 'genericParseJSON' 'aesonOptions', a missing key becomes 'Unset'
-- and @null@ becomes 'Clear'. (Outside a record, for example as a 'Map' value,
-- 'Unset' also encodes as @null@; use 'Maybe' there instead.)
module Notion.V1.Clearable
  ( Clearable (..),
    clearableToMaybe,
  )
where

import Notion.Prelude

data Clearable a
  = Unset
  | Clear
  | Set a
  deriving stock (Eq, Show, Generic, Functor, Foldable, Traversable)

instance (ToJSON a) => ToJSON (Clearable a) where
  toJSON = \case
    Unset -> Null
    Clear -> Null
    Set a -> toJSON a
  omitField = \case
    Unset -> True
    _ -> False

instance (FromJSON a) => FromJSON (Clearable a) where
  parseJSON = \case
    Null -> pure Clear
    v -> Set <$> parseJSON v
  omittedField = Just Unset

-- | 'Set' becomes 'Just'; 'Unset' and 'Clear' become 'Nothing'.
clearableToMaybe :: Clearable a -> Maybe a
clearableToMaybe = \case
  Set a -> Just a
  _ -> Nothing
```

`omitField` and `omittedField` are class methods added in aeson 2.2. `Notion.Prelude` exports `ToJSON (..)` and `FromJSON (..)`, which include them, and `Value (..)`, which provides `Null`.

Next, add decoding to `src/Notion/V1/Filter.hs`. First check whether EP-5 got there first:

```bash
cd /Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client
grep -n "instance FromJSON Filter\|instance FromJSON Sort\|instance FromJSON PropertyCondition\|instance ToJSON PropertyCondition" src/Notion/V1/Filter.hs
```

Branch on the result:

- **All four instances are present.** Skip to the `Views.hs` changes and add a Decision Log entry saying the instances were consumed from EP-5.
- **EP-5 added only `FromJSON Filter` and `FromJSON Sort`.** Its draft does not list the `PropertyCondition` instances. Add just the two `PropertyCondition` instances below, delegating to EP-5's `parsePropertyCondition :: Aeson.Object -> Parser PropertyCondition`.
- **None are present** (EP-4 is first). Add all of them as described below.

In every branch, do not add or rename any constructor, because EP-5 owns those.

When EP-4 is first, use the same helper names and the same `(<|>)`-chain shape that EP-5's draft uses (`parsePropertyCondition`, `parseTextCondition`, `parseDateCondition`, and so on). EP-5 can then extend these parsers in place instead of rewriting them. Each `FromJSON` inverts the matching existing encoder.

After EP-5 lands, `Filter`, `Sort` and `PropertyCondition` gain `UnknownFilter`, `UnknownSort` and `UnknownCondition` fallbacks, and their decoders stop failing. Until then they can fail, which is why `Views.hs` wraps them below.

Add these imports:

- `Control.Applicative ((<|>))` if needed
- `Data.Foldable (asum)`
- `Data.Aeson ((.:))`
- `Data.Aeson.Types (Parser)`

```haskell
instance FromJSON Filter where
  parseJSON = Aeson.withObject "Filter" $ \o ->
    asum
      [ And <$> o .: "and",
        Or <$> o .: "or",
        do
          ts <- o .: "timestamp"
          tsType <- parseTimestampType ts
          cond <- o .: Key.fromText ts >>= parseDateCondition
          pure (TimestampFilter tsType cond),
        PropertyFilter <$> o .: "property" <*> parsePropertyCondition o
      ]

-- | Encodes a condition as the object Notion uses for quick filters, e.g. {"select":{"equals":"High"}}.
instance ToJSON PropertyCondition where
  toJSON c = Aeson.object (propertyConditionToObject c)

instance FromJSON PropertyCondition where
  parseJSON = Aeson.withObject "PropertyCondition" parsePropertyCondition

parseTimestampType :: Text -> Parser TimestampType
parseTimestampType = \case
  "created_time" -> pure FilterCreatedTime
  "last_edited_time" -> pure FilterLastEditedTime
  other -> fail ("unknown timestamp: " <> unpack other)

-- | Finds the one property-type key (title, rich_text, number, …) and parses its condition.
parsePropertyCondition :: Aeson.Object -> Parser PropertyCondition
parsePropertyCondition o =
  asum
    [ TitleCondition <$> (o .: "title" >>= parseTextCondition),
      RichTextCondition <$> (o .: "rich_text" >>= parseTextCondition),
      NumberCondition <$> (o .: "number" >>= parseNumberCondition),
      -- … one line per constructor of PropertyCondition, using exactly the keys in
      -- propertyConditionToObject: checkbox, select, multi_select, date, people, files,
      -- relation, status, unique_id, verification, formula, rollup, created_time,
      -- created_by, last_edited_time, last_edited_by, phone_number, url, email
      EmailCondition <$> (o .: "email" >>= parseTextCondition)
    ]

-- | Requires the flag key to hold JSON true (Notion encodes is_empty as {"is_empty": true}).
flagKey :: Aeson.Object -> Aeson.Key -> Parser ()
flagKey c k = do
  b <- c .: k
  if b then pure () else fail ("expected true for " <> show k)

parseTextCondition :: Value -> Parser TextCondition
parseTextCondition = Aeson.withObject "TextCondition" $ \c ->
  asum
    [ TextEquals <$> c .: "equals",
      TextDoesNotEqual <$> c .: "does_not_equal",
      TextContains <$> c .: "contains",
      TextDoesNotContain <$> c .: "does_not_contain",
      TextStartsWith <$> c .: "starts_with",
      TextEndsWith <$> c .: "ends_with",
      TextIsEmpty <$ flagKey c "is_empty",
      TextIsNotEmpty <$ flagKey c "is_not_empty"
    ]
```

Write `parseNumberCondition`, `parseCheckboxCondition`, `parseSelectCondition`, `parseMultiSelectCondition`, `parsePeopleCondition`, `parseFilesCondition`, `parseRelationCondition`, `parseStatusCondition`, `parseUniqueIdCondition`, `parseVerificationCondition` and `parseDateCondition` the same way, as mirror images of their `…ToValue` functions. For the relative date constructors (`DateNextWeek` and friends, encoded as `{"next_week": {}}`), use `DateNextWeek <$ (c .: "next_week" :: Parser Value)`.

`parseFormulaCondition` reads one of `string`, `number`, `date` or `checkbox`. `parseRollupCondition` reads `any`, `every` or `none` (each via `withObject … parsePropertyCondition`) or `number` or `date`.

Also add:

```haskell
instance FromJSON SortDirection where
  parseJSON = Aeson.withText "SortDirection" $ \case
    "ascending" -> pure Ascending
    "descending" -> pure Descending
    other -> fail ("unknown sort direction: " <> unpack other)

instance FromJSON Sort where
  parseJSON = Aeson.withObject "Sort" $ \o ->
    asum
      [ PropertySort <$> o .: "property" <*> o .: "direction",
        TimestampSort <$> (o .: "timestamp" >>= parseTimestampType) <*> o .: "direction"
      ]
```

These decoders may fail on shapes the DSL cannot express, such as an array value. That is intended, because the view wrappers below catch the failure.

Now edit `src/Notion/V1/Views.hs`:

- Add `UnknownViewType Text` to `ViewType`. Its decoder's final case becomes `other -> pure (UnknownViewType other)`, and its encoder gets `UnknownViewType t -> String t`. The decoder's `\case` then needs to bind a `Text`; use `Aeson.withText "ViewType" $ \case …`.
- Add the following types and export them:

```haskell
-- | A view's filter: typed when the Filter DSL can express it, raw JSON otherwise.
data ViewFilter
  = ViewFilter Filter
  | RawViewFilter Value
  deriving stock (Eq, Show)

instance FromJSON ViewFilter where
  parseJSON v = (ViewFilter <$> parseJSON v) <|> pure (RawViewFilter v)

instance ToJSON ViewFilter where
  toJSON = \case
    ViewFilter f -> toJSON f
    RawViewFilter v -> v

-- | A view sort: typed property/timestamp sort, or raw JSON.
data ViewSort
  = ViewSort Sort
  | RawViewSort Value
  deriving stock (Eq, Show)
-- FromJSON / ToJSON exactly like ViewFilter.

-- | A quick filter condition (a property condition without the "property" key), or raw JSON.
data QuickFilter
  = QuickFilter PropertyCondition
  | RawQuickFilter Value
  deriving stock (Eq, Show)
-- FromJSON / ToJSON exactly like ViewFilter (ToJSON uses the new ToJSON PropertyCondition).

-- | Update-view sorts accept property sorts only.
data ViewPropertySort = ViewPropertySort
  { property :: Text,
    direction :: SortDirection
  }
  deriving stock (Eq, Generic, Show)

instance ToJSON ViewPropertySort where
  toJSON = genericToJSON aesonOptions

-- | Where a new view tab goes in the database's tab bar.
data ViewPosition
  = ViewPositionStart
  | ViewPositionEnd
  | ViewPositionAfterView ViewID
  deriving stock (Eq, Show)

instance ToJSON ViewPosition where
  toJSON = \case
    ViewPositionStart -> Aeson.object ["type" .= ("start" :: Text)]
    ViewPositionEnd -> Aeson.object ["type" .= ("end" :: Text)]
    ViewPositionAfterView v -> Aeson.object ["type" .= ("after_view" :: Text), "view_id" .= v]

-- | Where a new widget goes inside a dashboard view (0-based row index).
data WidgetPlacement
  = NewRow (Maybe Natural)
  | ExistingRow Natural
  deriving stock (Eq, Show)

instance ToJSON WidgetPlacement where
  toJSON = \case
    NewRow Nothing -> Aeson.object ["type" .= ("new_row" :: Text)]
    NewRow (Just i) -> Aeson.object ["type" .= ("new_row" :: Text), "row_index" .= i]
    ExistingRow i -> Aeson.object ["type" .= ("existing_row" :: Text), "row_index" .= i]

-- | Create a new linked database block on a page and put the view in it.
data CreateDatabaseForView = CreateDatabaseForView
  { parentPageId :: UUID,
    afterBlockId :: Maybe UUID
  }
  deriving stock (Eq, Show)

instance ToJSON CreateDatabaseForView where
  toJSON CreateDatabaseForView {..} =
    Aeson.object $
      ["parent" .= Aeson.object ["type" .= ("page_id" :: Text), "page_id" .= parentPageId]]
        <> maybe [] (\b -> ["position" .= Aeson.object ["type" .= ("after_block" :: Text), "block_id" .= b]]) afterBlockId
```

- Retype the records. `ViewObject`'s hand-written decoder keeps using `o .:?` for these fields, so only the field types change:

```haskell
data ViewObject = ViewObject
  { id :: ViewID,
    parent :: Maybe Parent,
    name :: Maybe Text,
    type_ :: Maybe ViewType,
    createdTime :: Maybe POSIXTime,
    lastEditedTime :: Maybe POSIXTime,
    url :: Maybe Text,
    dataSourceId :: Maybe UUID,
    createdBy :: Maybe UserReference,
    lastEditedBy :: Maybe UserReference,
    filter :: Maybe ViewFilter,
    sorts :: Maybe (Vector ViewSort),
    quickFilters :: Maybe (Map Text QuickFilter),
    configuration :: Maybe Value, -- becomes Maybe ViewConfig in Milestone 3
    dashboardViewId :: Maybe ViewID,
    object :: Maybe ObjectType
  }

data CreateView = CreateView
  { dataSourceId :: UUID,
    name :: Text,
    type_ :: ViewType,
    databaseId :: Maybe UUID,
    viewId :: Maybe ViewID,
    filter :: Maybe ViewFilter,
    sorts :: Maybe (Vector ViewSort),
    quickFilters :: Maybe (Map Text QuickFilter),
    createDatabase_ :: Maybe CreateDatabaseForView, -- wire name "create_database"
    configuration :: Maybe Value, -- becomes Maybe ViewConfig in Milestone 3
    position :: Maybe ViewPosition,
    placement :: Maybe WidgetPlacement
  }

data UpdateView = UpdateView
  { name :: Maybe Text,
    filter :: Clearable ViewFilter,
    sorts :: Clearable (Vector ViewPropertySort),
    quickFilters :: Clearable (Map Text (Maybe QuickFilter)), -- Nothing value = remove that quick filter
    configuration :: Maybe Value -- becomes Maybe ViewConfig in Milestone 3
  }
```

Both request types keep `toJSON = genericToJSON aesonOptions`. Views.hs needs these imports:

- `Notion.V1.Common (ObjectType, Parent, UUID)`
- `Notion.V1.Filter (Filter, PropertyCondition, Sort, SortDirection)`
- `Notion.V1.Clearable (Clearable (..))`
- `Control.Applicative ((<|>))`
- `Data.Aeson ((.:), (.:?), (.=))`
- `Data.Aeson qualified as Aeson`

Re-export `Clearable (..)` from `Notion.V1.Views` so users need one import.

Callers must be updated:

- In `tasty/Main.hs`, `testSerializeCreateView` gets `createDatabase_ = Nothing` and `placement = Nothing`. `testSerializeUpdateView` changes `filter`, `sorts` and `quickFilters` to `Unset`. `testViewLifecycle`'s literals change the same way.
- In `notion-client-example/ViewDemo.hs`, the create literal gets the two new fields. The update literal becomes `sorts = Set (Vector.singleton ViewPropertySort {property = "title", direction = Ascending})`, with `filter = Unset` and `quickFilters = Unset`. Import `Notion.V1.Filter (SortDirection (..))` and drop `Data.Aeson` if it becomes unused.

Write each record literal in full. Record-update syntax such as `req {filter = …}` on these types is ambiguous under `DuplicateRecordFields`, because `name` and `filter` are shared by several records in the module.

Add three groups to `tasty/ViewTests.hs`.

The "Filters and sorts" group:

- A round-trip test: for every value in a list, `Aeson.fromJSON (Aeson.toJSON f) == Aeson.Success f`. Include at least one `And`/`Or` nesting, a `TimestampFilter FilterLastEditedTime DateNextWeek`, a `PropertyFilter` for each condition type except `UniqueIdCondition` and `VerificationCondition`, `RollupCondition (RollupAny (RichTextCondition (TextContains "Sato")))`, `FormulaCondition (FormulaNumber (NumGreaterThan 3))`, and both `Sort` constructors. EP-5 changes the payloads of the two excluded constructors, so leaving them out keeps this test stable whichever plan lands first.
- A test that the JSON `{"property":"Status","select":{"does_not_equal":["Done","Archive"]}}` decodes as a `ViewFilter` without failing, and that re-encoding gives back the identical `Value`. Before EP-5 it is a `RawViewFilter`; after EP-5 it is `ViewFilter (PropertyFilter "Status" (SelectCondition (SelectDoesNotEqualAny …)))`. Assert only the decode success and the round trip, not the constructor.

The "View object" group decodes the fixture below. It asserts:

- `parent` is `Just (DatabaseParent …)`.
- `type_ == Just BoardView`.
- `filter` is `Just (ViewFilter (And [...]))`.
- `sorts` has one `ViewSort (TimestampSort FilterCreatedTime Descending)` and one `ViewSort (PropertySort "Due" Ascending)`.
- `quickFilters` maps `"Priority"` to `QuickFilter (SelectCondition (SelectEquals "High"))`.

A second fixture with `"type": "wiki_board"` must decode with `type_ == Just (UnknownViewType "wiki_board")`.

```json
{
  "object": "view",
  "id": "2b3c4d5e-6f70-4812-9a3b-4c5d6e7f8091",
  "parent": { "type": "database_id", "database_id": "d1d1d1d1-0000-4000-8000-000000000002" },
  "name": "Tanaka Hanako's tasks",
  "type": "board",
  "created_time": "2026-09-01T09:00:00.000Z",
  "last_edited_time": "2026-09-02T10:30:00.000+00:00",
  "url": "https://www.notion.so/d1d1d1d1000040008000000000000002?v=2b3c4d5e6f7048129a3b4c5d6e7f8091",
  "data_source_id": "e5e5e5e5-0000-4000-8000-000000000003",
  "created_by": { "object": "user", "id": "u1u1u1u1-0000-4000-8000-000000000004" },
  "last_edited_by": { "object": "user", "id": "u1u1u1u1-0000-4000-8000-000000000004" },
  "filter": {
    "and": [
      { "property": "Assignee", "people": { "contains": "u1u1u1u1-0000-4000-8000-000000000004" } },
      { "timestamp": "created_time", "created_time": { "past_month": {} } }
    ]
  },
  "sorts": [
    { "timestamp": "created_time", "direction": "descending" },
    { "property": "Due", "direction": "ascending" }
  ],
  "quick_filters": { "Priority": { "select": { "equals": "High" } } },
  "configuration": {
    "type": "board",
    "group_by": { "type": "status", "property_id": "a%3Bc", "group_by": "group", "sort": { "type": "manual" }, "property_name": "Status" }
  }
}
```

The "View requests" group compares `Aeson.toJSON req` with an expected `Value`, using `@?=`:

- An `UpdateView` with `name = Nothing`, `filter = Clear`, `sorts = Set [ViewPropertySort "Due" Descending]`, `quickFilters = Set (Map.fromList [("Priority", Nothing), ("Status", Just (QuickFilter (StatusCondition (StatusEquals "In progress"))))])` and `configuration = Nothing` must encode to `{"filter":null,"sorts":[{"property":"Due","direction":"descending"}],"quick_filters":{"Priority":null,"Status":{"status":{"equals":"In progress"}}}}`.
- An all-`Unset`/`Nothing` `UpdateView` must encode to `{}`.
- A `CreateView` with `position = Just (ViewPositionAfterView "view-9")` must include `"position":{"type":"after_view","view_id":"view-9"}`.
- A `CreateView` with `viewId = Just "dash-1"` and `placement = Just (ExistingRow 0)` must include `"view_id":"dash-1","placement":{"type":"existing_row","row_index":0}`.
- A `CreateView` with `createDatabase_ = Just (CreateDatabaseForView "page-1" (Just "block-1"))` must include `"create_database":{"parent":{"type":"page_id","page_id":"page-1"},"position":{"type":"after_block","block_id":"block-1"}}` and no `create_database_` key.

Acceptance: `cabal build all` and `cabal test` pass, including the three new groups.


### Milestone 3: typed configuration for table, board, calendar, timeline, gallery and list

At the end of this milestone, `ViewObject.configuration`, `CreateView.configuration` and `UpdateView.configuration` are `Maybe ViewConfig`. Table, board, calendar, timeline, gallery and list configurations are fully typed. Chart, map, form and dashboard still arrive as `UnknownViewConfig Value`, which also works for sending them.

Create `src/Notion/V1/ViewConfig.hs`, add `Notion.V1.ViewConfig` to `exposed-modules`, and re-export it from `Notion.V1.Views` (`module Notion.V1.ViewConfig` in the export list). It imports:

- `Notion.Prelude`
- `Notion.V1.Clearable (Clearable (..))`
- `Notion.V1.Common (UUID)`, used for the dashboard in Milestone 4
- `Data.Aeson qualified as Aeson`
- `Data.Aeson.KeyMap qualified as KeyMap`
- `Data.Aeson.Types (Parser)`
- `Data.Scientific (Scientific)`
- `Data.Tuple (swap)`
- `Control.Applicative ((<|>))`
- `Prelude hiding (id)`

Start with three internal helpers:

```haskell
-- | Decode a string enum from a lookup table; unknown strings go to the fallback constructor.
parseEnum :: String -> [(Text, a)] -> (Text -> a) -> Value -> Parser a
parseEnum name table unknown =
  Aeson.withText name $ \t -> pure (maybe (unknown t) id (lookup t table))

-- | Encode a known enum constructor via the same table (Unknown constructors are handled by the caller).
enumToJSON :: (Eq a) => [(Text, a)] -> a -> Value
enumToJSON table a = maybe Null String (lookup a (map swap table))

-- | Add the "type" discriminator to an encoded object.
withType :: Text -> Value -> Value
withType t = \case
  Object o -> Object (KeyMap.insert "type" (String t) o)
  other -> other

-- | Remove response-only convenience keys before sending a configuration back to Notion.
dropKeys :: [Aeson.Key] -> Value -> Value
dropKeys ks = \case
  Object o -> Object (foldr KeyMap.delete o ks)
  other -> other
```

`id` here is `Prelude.id` hidden by `Prelude hiding (id)`. Use `fromMaybe (unknown t) (lookup t table)` from `Data.Maybe` instead.

Every enum follows one pattern, shown here once:

```haskell
data CoverSize = CoverSmall | CoverMedium | CoverLarge | UnknownCoverSize Text
  deriving stock (Eq, Show, Generic)

coverSizeTable :: [(Text, CoverSize)]
coverSizeTable = [("small", CoverSmall), ("medium", CoverMedium), ("large", CoverLarge)]

instance FromJSON CoverSize where
  parseJSON = parseEnum "CoverSize" coverSizeTable UnknownCoverSize

instance ToJSON CoverSize where
  toJSON = \case
    UnknownCoverSize t -> String t
    known -> enumToJSON coverSizeTable known
```

This milestone needs the enums below. Each also gets an `Unknown<TypeName> Text` constructor, and the wire strings are shown in comments.

```haskell
data GroupSort = GroupSortManual | GroupSortAscending | GroupSortDescending | UnknownGroupSort Text
  -- wire: {"type":"manual"|"ascending"|"descending"} (an object, not a bare string:
  -- parse with withObject then the table on the "type" field; encode as object ["type" .= …])
data SelectGroupKind = SelectKind | MultiSelectKind | UnknownSelectGroupKind Text              -- select, multi_select
data PersonGroupKind = PersonKind | CreatedByKind | LastEditedByKind | UnknownPersonGroupKind Text -- person, created_by, last_edited_by
data DateGroupKind = DateKind | CreatedTimeKind | LastEditedTimeKind | UnknownDateGroupKind Text  -- date, created_time, last_edited_time
data TextGroupKind = TextKind | TitleKind | UrlKind | EmailKind | PhoneNumberKind | UnknownTextGroupKind Text -- text, title, url, email, phone_number
data DateGranularity = GranularityRelative | GranularityDay | GranularityWeek | GranularityMonth | GranularityYear | UnknownDateGranularity Text -- relative, day, week, month, year
data TextGroupMode = GroupExact | GroupAlphabetPrefix | UnknownTextGroupMode Text              -- exact, alphabet_prefix
data StatusGroupMode = GroupByStatusGroup | GroupByStatusOption | UnknownStatusGroupMode Text  -- group, option
data StatusShowAs = ShowAsSelect | ShowAsCheckbox | UnknownStatusShowAs Text                    -- select, checkbox
data CardPropertyWidthMode = WidthFullLine | WidthInline | UnknownCardPropertyWidthMode Text   -- full_line, inline
data DateFormat = DateFormatFull | DateFormatShort | DateFormatMonthDayYear | DateFormatDayMonthYear
  | DateFormatYearMonthDay | DateFormatRelative | UnknownDateFormat Text  -- full, short, month_day_year, day_month_year, year_month_day, relative
data TimeFormat = TimeFormat12Hour | TimeFormat24Hour | TimeFormatHidden | UnknownTimeFormat Text -- 12_hour, 24_hour, hidden
data SubtaskDisplayMode = SubtasksShow | SubtasksHidden | SubtasksFlattened | SubtasksDisabled | UnknownSubtaskDisplayMode Text -- show, hidden, flattened, disabled
data SubtaskFilterScope = ScopeParents | ScopeParentsAndSubitems | ScopeSubitems | UnknownSubtaskFilterScope Text -- parents, parents_and_subitems, subitems
data CoverType = CoverPageCover | CoverPageContent | CoverPageContentFirst | CoverProperty | UnknownCoverType Text -- page_cover, page_content, page_content_first, property
data CoverSize -- as above: small, medium, large
data CoverAspect = AspectContain | AspectCover | UnknownCoverAspect Text                       -- contain, cover
data CardLayout = CardLayoutList | CardLayoutCompact | UnknownCardLayout Text                   -- list, compact
data CalendarRange = RangeWeek | RangeMonth | UnknownCalendarRange Text                         -- week, month
data TimelineZoomLevel = ZoomHours | ZoomDay | ZoomWeek | ZoomBiWeek | ZoomMonth | ZoomQuarter
  | ZoomYear | ZoomFiveYears | UnknownTimelineZoomLevel Text  -- hours, day, week, bi_week, month, quarter, year, 5_years
```

Next come the records. Every record derives `(Eq, Show, Generic)` and uses `parseJSON = genericParseJSON aesonOptions`. Its `toJSON` is `genericToJSON aesonOptions`, wrapped in `dropKeys [...]` when it has response-only fields (shown in comments).

```haskell
data ViewPropertyConfig = ViewPropertyConfig
  { propertyId :: Text,
    propertyName :: Maybe Text, -- response-only; toJSON = dropKeys ["property_name"] . genericToJSON aesonOptions
    visible :: Maybe Bool,
    width :: Maybe Int,
    wrap :: Maybe Bool,
    statusShowAs :: Maybe StatusShowAs,
    cardPropertyWidthMode :: Maybe CardPropertyWidthMode,
    dateFormat :: Maybe DateFormat,
    timeFormat :: Maybe TimeFormat
  }

data SubtaskConfig = SubtaskConfig
  { propertyId :: Maybe Text,
    displayMode :: Maybe SubtaskDisplayMode,
    filterScope :: Maybe SubtaskFilterScope,
    toggleColumnId :: Maybe Text
  }

data CoverConfig = CoverConfig
  { type_ :: CoverType,
    propertyId :: Maybe Text
  }

-- Group-by records. Records whose wire "type" has several values carry a type_ field;
-- the others get "type" added by GroupByConfig's encoder. All drop "property_name" on encode.
data SelectGroupByConfig = SelectGroupByConfig
  { type_ :: SelectGroupKind, propertyId :: Text, sort :: GroupSort,
    propertyName :: Maybe Text, hideEmptyGroups :: Maybe Bool }
data StatusGroupByConfig = StatusGroupByConfig
  { propertyId :: Text, groupBy :: StatusGroupMode, sort :: GroupSort,
    propertyName :: Maybe Text, hideEmptyGroups :: Maybe Bool }
data PersonGroupByConfig = PersonGroupByConfig
  { type_ :: PersonGroupKind, propertyId :: Text, sort :: GroupSort,
    propertyName :: Maybe Text, hideEmptyGroups :: Maybe Bool }
data RelationGroupByConfig = RelationGroupByConfig
  { propertyId :: Text, sort :: GroupSort, propertyName :: Maybe Text, hideEmptyGroups :: Maybe Bool }
data DateGroupByConfig = DateGroupByConfig
  { type_ :: DateGroupKind, propertyId :: Text, groupBy :: DateGranularity, sort :: GroupSort,
    propertyName :: Maybe Text, hideEmptyGroups :: Maybe Bool, startDayOfWeek :: Maybe Int }
data TextGroupByConfig = TextGroupByConfig
  { type_ :: TextGroupKind, propertyId :: Text, groupBy :: TextGroupMode, sort :: GroupSort,
    propertyName :: Maybe Text, hideEmptyGroups :: Maybe Bool }
data NumberGroupByConfig = NumberGroupByConfig
  { propertyId :: Text, sort :: GroupSort, propertyName :: Maybe Text, hideEmptyGroups :: Maybe Bool,
    rangeStart :: Maybe Scientific, rangeEnd :: Maybe Scientific, rangeSize :: Maybe Scientific }
data CheckboxGroupByConfig = CheckboxGroupByConfig
  { propertyId :: Text, sort :: GroupSort, propertyName :: Maybe Text, hideEmptyGroups :: Maybe Bool }
data FormulaGroupByConfig = FormulaGroupByConfig
  { propertyId :: Text, groupBy :: FormulaSubGroupBy, propertyName :: Maybe Text, hideEmptyGroups :: Maybe Bool }

data FormulaDateSubGroupBy = FormulaDateSubGroupBy
  { groupBy :: DateGranularity, sort :: GroupSort, startDayOfWeek :: Maybe Int }
data FormulaTextSubGroupBy = FormulaTextSubGroupBy { groupBy :: TextGroupMode, sort :: GroupSort }
data FormulaNumberSubGroupBy = FormulaNumberSubGroupBy
  { sort :: GroupSort, rangeStart :: Maybe Scientific, rangeEnd :: Maybe Scientific, rangeSize :: Maybe Scientific }
newtype FormulaCheckboxSubGroupBy = FormulaCheckboxSubGroupBy { sort :: GroupSort }

data FormulaSubGroupBy
  = FormulaDateGroup FormulaDateSubGroupBy        -- "date"
  | FormulaTextGroup FormulaTextSubGroupBy        -- "text"
  | FormulaNumberGroup FormulaNumberSubGroupBy    -- "number"
  | FormulaCheckboxGroup FormulaCheckboxSubGroupBy -- "checkbox"
  | UnknownFormulaGroup Value

data GroupByConfig
  = SelectGroupBy SelectGroupByConfig     -- "select", "multi_select"
  | StatusGroupBy StatusGroupByConfig     -- "status"
  | PersonGroupBy PersonGroupByConfig     -- "person", "created_by", "last_edited_by"
  | RelationGroupBy RelationGroupByConfig -- "relation"
  | DateGroupBy DateGroupByConfig         -- "date", "created_time", "last_edited_time"
  | TextGroupBy TextGroupByConfig         -- "text", "title", "url", "email", "phone_number"
  | NumberGroupBy NumberGroupByConfig     -- "number"
  | CheckboxGroupBy CheckboxGroupByConfig -- "checkbox"
  | FormulaGroupBy FormulaGroupByConfig   -- "formula"
  | UnknownGroupBy Value

data TableViewConfig = TableViewConfig
  { properties :: Clearable (Vector ViewPropertyConfig),
    groupBy :: Clearable GroupByConfig,
    subtasks :: Clearable SubtaskConfig,
    wrapCells :: Maybe Bool,
    frozenColumnIndex :: Maybe Int,
    showVerticalLines :: Maybe Bool
  }

data BoardViewConfig = BoardViewConfig
  { groupBy :: GroupByConfig,
    subGroupBy :: Clearable GroupByConfig,
    properties :: Clearable (Vector ViewPropertyConfig),
    cover :: Clearable CoverConfig,
    coverSize :: Clearable CoverSize,
    coverAspect :: Clearable CoverAspect,
    cardLayout :: Clearable CardLayout
  }

data CalendarViewConfig = CalendarViewConfig
  { datePropertyId :: Text,
    datePropertyName :: Maybe Text, -- response-only, dropped on encode
    properties :: Clearable (Vector ViewPropertyConfig),
    viewRange :: Clearable CalendarRange,
    showWeekends :: Clearable Bool
  }

data TimelinePreference = TimelinePreference
  { zoomLevel :: TimelineZoomLevel,
    centerTimestamp :: Maybe Integer -- milliseconds since the Unix epoch
  }

newtype TimelineArrowsBy = TimelineArrowsBy
  { propertyId :: Clearable Text -- Clear (null) disables arrows
  }

data TimelineViewConfig = TimelineViewConfig
  { datePropertyId :: Text,
    datePropertyName :: Maybe Text, -- response-only, dropped on encode
    endDatePropertyId :: Clearable Text,
    endDatePropertyName :: Maybe Text, -- response-only, dropped on encode
    properties :: Clearable (Vector ViewPropertyConfig),
    showTable :: Clearable Bool,
    tableProperties :: Clearable (Vector ViewPropertyConfig),
    preference :: Clearable TimelinePreference,
    arrowsBy :: Clearable TimelineArrowsBy,
    colorBy :: Clearable Bool
  }

data GalleryViewConfig = GalleryViewConfig
  { properties :: Clearable (Vector ViewPropertyConfig),
    cover :: Clearable CoverConfig,
    coverSize :: Clearable CoverSize,
    coverAspect :: Clearable CoverAspect,
    cardLayout :: Clearable CardLayout
  }

newtype ListViewConfig = ListViewConfig
  { properties :: Clearable (Vector ViewPropertyConfig)
  }

data ViewConfig
  = TableConfig TableViewConfig       -- "table"
  | BoardConfig BoardViewConfig       -- "board"
  | CalendarConfig CalendarViewConfig -- "calendar"
  | TimelineConfig TimelineViewConfig -- "timeline"
  | GalleryConfig GalleryViewConfig   -- "gallery"
  | ListConfig ListViewConfig         -- "list"
  | UnknownViewConfig Value           -- any other type, or a typed parse failure; sent back verbatim
```

`newtype` records with one field still use `genericParseJSON aesonOptions`. `unwrapUnaryRecords` is `False` in `aesonOptions`, so they are still encoded as objects.

The three sum types (`ViewConfig`, `GroupByConfig` and `FormulaSubGroupBy`) share one decoder and encoder pattern:

```haskell
instance FromJSON ViewConfig where
  parseJSON v = typed <|> pure (UnknownViewConfig v)
    where
      typed = flip (Aeson.withObject "ViewConfig") v $ \o -> do
        t <- o .: "type"
        case (t :: Text) of
          "table" -> TableConfig <$> parseJSON v
          "board" -> BoardConfig <$> parseJSON v
          "calendar" -> CalendarConfig <$> parseJSON v
          "timeline" -> TimelineConfig <$> parseJSON v
          "gallery" -> GalleryConfig <$> parseJSON v
          "list" -> ListConfig <$> parseJSON v
          other -> fail ("unknown view configuration type: " <> unpack other)

instance ToJSON ViewConfig where
  toJSON = \case
    TableConfig c -> withType "table" (toJSON c)
    BoardConfig c -> withType "board" (toJSON c)
    CalendarConfig c -> withType "calendar" (toJSON c)
    TimelineConfig c -> withType "timeline" (toJSON c)
    GalleryConfig c -> withType "gallery" (toJSON c)
    ListConfig c -> withType "list" (toJSON c)
    UnknownViewConfig raw -> raw
```

`GroupByConfig` dispatches every wire type listed in its comments. For multi-kind records (select, person, date, text), `toJSON` is just `toJSON c`, because their `type_` field already writes `"type"`. The other constructors use `withType`. `FormulaSubGroupBy` does the same with `date`, `text`, `number` and `checkbox`. The records' own generic decoders ignore the extra `"type"` key, because `rejectUnknownFields` is `False`.

Switch the three `configuration` fields in `src/Notion/V1/Views.hs` to `Maybe ViewConfig`. `ViewObject`'s `o .:? "configuration"` then decodes typed. Update the test literals and `ViewDemo.hs` if they set `configuration`; with `Nothing` they need no change.

Add a "View configuration" group to `tasty/ViewTests.hs` with these tests:

- **Round trips of request-shaped fixtures.** Each fixture below must decode to the expected constructor, and `Aeson.toJSON decoded` must equal the fixture `Value` exactly. Numbers compare by value, because `Scientific` equality ignores `1` versus `1.0`.
- **Response-only stripping.** The board configuration inside the Milestone 2 `ViewObject` fixture decodes to `BoardConfig` whose `groupBy` is `StatusGroupBy StatusGroupByConfig {propertyName = Just "Status", groupBy = GroupByStatusGroup, …}`. Re-encoding it yields a `group_by` object with no `property_name` key.
- **Unknown configuration.** `{"type":"kanban_3d","depth":3}` decodes as `UnknownViewConfig` and re-encodes identically.
- **Unknown enum.** `{"type":"list","properties":[{"property_id":"title","date_format":"iso_week"}]}` decodes with `dateFormat = Just (UnknownDateFormat "iso_week")` and re-encodes identically.
- **Formula group-by.** `{"type":"board","group_by":{"type":"formula","property_id":"fx","group_by":{"type":"number","sort":{"type":"descending"},"range_start":0,"range_end":100,"range_size":10}}}` round-trips, and its group-by is `FormulaGroupBy` with `FormulaNumberGroup`.
- **Clearing inside a configuration.** `UpdateView {…, configuration = Just (TableConfig TableViewConfig {properties = Unset, groupBy = Clear, subtasks = Unset, wrapCells = Nothing, frozenColumnIndex = Nothing, showVerticalLines = Nothing})}` encodes `configuration` as `{"type":"table","group_by":null}`.

The round-trip fixtures:

```json
{
  "type": "table",
  "properties": [
    { "property_id": "title", "visible": true, "width": 280, "wrap": false },
    { "property_id": "d%3Aue", "date_format": "year_month_day", "time_format": "24_hour" }
  ],
  "group_by": { "type": "date", "property_id": "d%3Aue", "group_by": "week", "sort": { "type": "ascending" }, "start_day_of_week": 1 },
  "subtasks": { "property_id": "r%3Bx", "display_mode": "flattened", "filter_scope": "parents_and_subitems" },
  "wrap_cells": true,
  "frozen_column_index": 1,
  "show_vertical_lines": false
}
```

```json
{
  "type": "board",
  "group_by": { "type": "multi_select", "property_id": "t%3Ag", "sort": { "type": "manual" }, "hide_empty_groups": true },
  "sub_group_by": null,
  "properties": [{ "property_id": "title", "card_property_width_mode": "full_line" }],
  "cover": { "type": "property", "property_id": "f%3Ail" },
  "cover_size": "medium",
  "cover_aspect": "cover",
  "card_layout": "compact"
}
```

```json
{ "type": "calendar", "date_property_id": "d%3Aue", "view_range": "week", "show_weekends": false }
```

```json
{
  "type": "timeline",
  "date_property_id": "d%3Aue",
  "end_date_property_id": null,
  "show_table": true,
  "table_properties": [{ "property_id": "title" }],
  "preference": { "zoom_level": "5_years", "center_timestamp": 1789000000000 },
  "arrows_by": { "property_id": null },
  "color_by": false
}
```

```json
{ "type": "gallery", "cover": { "type": "page_cover" }, "cover_size": "large", "card_layout": "list" }
```

```json
{ "type": "list", "properties": [{ "property_id": "title", "visible": true, "status_show_as": "checkbox" }] }
```

Acceptance: `cabal build all` and `cabal test` pass, including "View configuration".


### Milestone 4: chart, map, form and dashboard configurations; changelog and demo

At the end of this milestone, all ten configuration types are typed and the CHANGELOG describes the whole plan.

In `src/Notion/V1/ViewConfig.hs`, add the enums below, following the Milestone 3 pattern, each with an `Unknown… Text` constructor:

```haskell
data ViewHeight = HeightSmall | HeightMedium | HeightLarge | HeightExtraLarge | UnknownViewHeight Text -- small, medium, large, extra_large
data SubmissionPermission = SubmissionNone | SubmissionCommentOnly | SubmissionReader
  | SubmissionReadAndWrite | SubmissionEditor | UnknownSubmissionPermission Text -- none, comment_only, reader, read_and_write, editor
data ChartType = ChartColumn | ChartBar | ChartLine | ChartDonut | ChartNumber | UnknownChartType Text -- column, bar, line, donut, number
data ChartSort = ChartSortManual | ChartSortXAscending | ChartSortXDescending | ChartSortYAscending
  | ChartSortYDescending | UnknownChartSort Text -- manual, x_ascending, x_descending, y_ascending, y_descending
data ChartColorTheme = ThemeGray | ThemeBlue | ThemeYellow | ThemeGreen | ThemePurple | ThemeTeal | ThemeOrange
  | ThemePink | ThemeRed | ThemeAuto | ThemeColorful | UnknownChartColorTheme Text -- gray … colorful
data LegendPosition = LegendOff | LegendBottom | LegendSide | UnknownLegendPosition Text -- off, bottom, side
data AxisLabels = AxisLabelsNone | AxisLabelsX | AxisLabelsY | AxisLabelsBoth | UnknownAxisLabels Text -- none, x_axis, y_axis, both
data GridLines = GridLinesNone | GridLinesHorizontal | GridLinesVertical | GridLinesBoth | UnknownGridLines Text -- none, horizontal, vertical, both
data GroupStyle = GroupStyleNormal | GroupStylePercent | GroupStyleSideBySide | UnknownGroupStyle Text -- normal, percent, side_by_side
data DonutLabels = DonutLabelsNone | DonutLabelsValue | DonutLabelsName | DonutLabelsNameAndValue | UnknownDonutLabels Text -- none, value, name, name_and_value
data ChartAggregator = AggCount | AggCountValues | AggSum | AggAverage | AggMedian | AggMin | AggMax | AggRange
  | AggUnique | AggEmpty | AggNotEmpty | AggPercentEmpty | AggPercentNotEmpty | AggChecked | AggUnchecked
  | AggPercentChecked | AggPercentUnchecked | AggEarliestDate | AggLatestDate | AggDateRange | UnknownChartAggregator Text
  -- count, count_values, sum, average, median, min, max, range, unique, empty, not_empty, percent_empty,
  -- percent_not_empty, checked, unchecked, percent_checked, percent_unchecked, earliest_date, latest_date, date_range
data ReferenceLineColor = LineGray | LineLightGray | LineBrown | LineYellow | LineOrange | LineGreen | LineBlue
  | LinePurple | LinePink | LineRed | UnknownReferenceLineColor Text -- gray, lightgray, brown, yellow, orange, green, blue, purple, pink, red
data DashStyle = DashSolid | DashDashed | UnknownDashStyle Text -- solid, dash
```

Add these records, following the same generic-instance rule:

```haskell
data MapViewConfig = MapViewConfig
  { height :: Clearable ViewHeight,
    mapBy :: Clearable Text,
    mapByPropertyName :: Maybe Text, -- response-only, dropped on encode
    properties :: Clearable (Vector ViewPropertyConfig)
  }

data FormViewConfig = FormViewConfig
  { isFormClosed :: Clearable Bool,
    anonymousSubmissions :: Clearable Bool,
    submissionPermissions :: Clearable SubmissionPermission
  }

data ChartAggregation = ChartAggregation
  { aggregator :: ChartAggregator,
    propertyId :: Maybe Text -- required unless aggregator is AggCount
  }

data ChartReferenceLine = ChartReferenceLine
  { id :: Maybe Text, -- always present in responses; optional in requests (Notion generates one)
    value :: Scientific,
    label :: Text,
    color :: ReferenceLineColor,
    dashStyle :: DashStyle
  }

data ChartViewConfig = ChartViewConfig
  { chartType :: ChartType,
    xAxis :: Clearable GroupByConfig,
    yAxis :: Clearable ChartAggregation,
    xAxisPropertyId :: Clearable Text,
    yAxisPropertyId :: Clearable Text,
    value :: Clearable ChartAggregation,
    sort :: Clearable ChartSort,
    colorTheme :: Clearable ChartColorTheme,
    height :: Clearable ViewHeight,
    hideEmptyGroups :: Clearable Bool,
    legendPosition :: Clearable LegendPosition,
    showDataLabels :: Clearable Bool,
    axisLabels :: Clearable AxisLabels,
    gridLines :: Clearable GridLines,
    cumulative :: Clearable Bool,
    smoothLine :: Clearable Bool,
    hideLineFillArea :: Clearable Bool,
    groupStyle :: Clearable GroupStyle,
    yAxisMin :: Clearable Scientific,
    yAxisMax :: Clearable Scientific,
    donutLabels :: Clearable DonutLabels,
    hideTitle :: Clearable Bool,
    stackBy :: Clearable GroupByConfig,
    referenceLines :: Clearable (Vector ChartReferenceLine),
    caption :: Clearable Text,
    colorByValue :: Clearable Bool
  }

data DashboardWidget = DashboardWidget
  { id :: Text,
    viewId :: UUID,
    width :: Maybe Int, -- 1..12 grid columns
    rowIndex :: Maybe Int
  }

data DashboardRow = DashboardRow
  { id :: Text,
    widgets :: Vector DashboardWidget,
    height :: Maybe Int -- pixels
  }

newtype DashboardViewConfig = DashboardViewConfig
  { rows :: Vector DashboardRow
  }
```

Check the generic field names. `xAxisPropertyId` becomes `x_axis_property_id` and `yAxisMin` becomes `y_axis_min`, because `camelToSnake` puts an underscore before every uppercase letter. The round-trip tests confirm this.

Extend `ViewConfig` with `MapConfig MapViewConfig` ("map"), `FormConfig FormViewConfig` ("form"), `ChartConfig ChartViewConfig` ("chart") and `DashboardConfig DashboardViewConfig` ("dashboard"), in both its decoder and its encoder. The dashboard configuration is only ever returned by Notion; the request union has no dashboard member. The encoder still writes it, and its Haddock comment should say Notion may reject it in a request.

Extend "View configuration" in `tasty/ViewTests.hs` with round trips of these fixtures, plus one test that a map response with `"map_by_property_name":"Office"` decodes it and drops it on re-encode:

```json
{
  "type": "chart",
  "chart_type": "column",
  "x_axis": { "type": "select", "property_id": "s%3Bq", "sort": { "type": "manual" } },
  "y_axis": { "aggregator": "sum", "property_id": "n%3Aum" },
  "sort": "y_descending",
  "color_theme": "colorful",
  "height": "extra_large",
  "legend_position": "bottom",
  "show_data_labels": true,
  "axis_labels": "both",
  "grid_lines": "horizontal",
  "group_style": "side_by_side",
  "y_axis_min": 0,
  "y_axis_max": null,
  "stack_by": null,
  "reference_lines": [{ "id": "line-1", "value": 75.5, "label": "Target", "color": "lightgray", "dash_style": "dash" }],
  "caption": null,
  "color_by_value": false
}
```

```json
{ "type": "chart", "chart_type": "number", "value": { "aggregator": "count" }, "hide_title": true }
```

```json
{ "type": "map", "height": "large", "map_by": "l%3Boc", "properties": [{ "property_id": "title" }] }
```

```json
{ "type": "form", "is_form_closed": false, "anonymous_submissions": true, "submission_permissions": "read_and_write" }
```

```json
{
  "type": "dashboard",
  "rows": [
    {
      "id": "row-1",
      "widgets": [
        { "id": "w-1", "view_id": "2b3c4d5e-6f70-4812-9a3b-4c5d6e7f8091", "width": 6, "row_index": 0 },
        { "id": "w-2", "view_id": "9a8b7c6d-5e4f-4321-8fed-cba987654321", "width": 6, "row_index": 0 }
      ],
      "height": 320
    }
  ]
}
```

Finish `notion-client-example/ViewDemo.hs`:

- The create request uses `position = Just ViewPositionEnd` and `configuration = Just (TableConfig TableViewConfig {properties = Unset, groupBy = Unset, subtasks = Unset, wrapCells = Just True, frozenColumnIndex = Nothing, showVerticalLines = Nothing})`.
- The retrieve part prints the typed `configuration`.

Add to `CHANGELOG.md` under `## Unreleased`. Create the heading directly below `# Changelog for notion-client` if it does not exist, and merge into existing subsections if other plans already created them:

```markdown
### Breaking Changes
* Remove `queryView`, `QueryView`, and the `POST /v1/views/{view_id}/query` route (Notion never served it; it returned 400 `invalid_request_url`). Use `createViewQuery` / `getViewQueryResults` / `deleteViewQuery` or `Notion.V1.ViewQueries.queryAllViewPages`. The effectful `queryView` / `QueryView` are removed too.
* `ViewType` gains `UnknownViewType Text`.
* `ViewObject`: `parent` is now `Maybe Parent`, `filter` is `Maybe ViewFilter`, `sorts` is `Maybe (Vector ViewSort)`, `quickFilters` is `Maybe (Map Text QuickFilter)`, `configuration` is `Maybe ViewConfig`.
* `CreateView`: `filter`, `sorts`, `quickFilters`, `configuration`, `position` are typed; new fields `createDatabase_` (wire `create_database`) and `placement`.
* `UpdateView`: `filter`, `sorts` (now property sorts only), and `quickFilters` are `Clearable`, so they can be cleared with `null`; `configuration` is `Maybe ViewConfig`.

### New Features
* View query endpoints: `createViewQuery` (`POST /v1/views/{view_id}/queries`), `getViewQueryResults` (`GET /v1/views/{view_id}/queries/{query_id}`), `deleteViewQuery` (`DELETE …`), plus the `queryAllViewPages` helper.
* Typed view configuration (`Notion.V1.ViewConfig`) for table, board, calendar, timeline, gallery, list, map, form, chart, and dashboard views, including group-by, property, subtask, cover, timeline, and chart settings; unknown shapes are preserved as raw JSON.
* `Notion.V1.Clearable` for request fields that distinguish "leave unchanged" from "clear with null".
* `FromJSON` instances for `Filter`, `PropertyCondition` and its condition types, `Sort`, and `SortDirection`; `ToJSON PropertyCondition`.
* `CreateView` supports `position` (`ViewPositionStart`/`End`/`AfterView`), dashboard widget `placement`, and `create_database`.
```

If EP-5 supplied the `Filter`/`Sort` `FromJSON` instances, leave that bullet out.

Acceptance: `cabal build all` and `cabal test` pass, with every test in `Views (EP-4)` OK. The optional live check below shows the query flow working.


## Concrete Steps

Run every command from the repository root, `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`.

Before starting, confirm the tree builds and check the two soft dependencies:

```bash
cd /Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client
cabal build all
grep -n "data RequestStatus" src/Notion/V1/ListOf.hs          # EP-2 landed? (adds ViewQuery.requestStatus)
grep -n "instance FromJSON Filter" src/Notion/V1/Filter.hs     # EP-5 landed the Filter instances?
```

After each milestone's edits:

```bash
cabal build all 2>&1 | tail -n 20
cabal test 2>&1 | tail -n 60
```

To iterate on the new tests only:

```bash
cabal test --test-option=--pattern=EP-4
```

Expected tail after Milestone 1. The exact test names are the ones you give in `tasty/ViewTests.hs`; integration groups print as skipped when no token is set.

```text
  Views (EP-4)
    View queries
      decode ViewQuery (create response):          OK
      decode view query results list:              OK
      decode DeletedViewQuery:                     OK
      encode CreateViewQuery:                      OK
  ...
All NN tests passed (0.xxs)
Test suite tasty: PASS
```

After Milestone 4, the group also lists "Filters and sorts", "View object", "View requests" and "View configuration", all `OK`.

If `cabal build all` reports `Ambiguous occurrence 'createDatabase'` or similar in an example or test module, a record literal or selector is clashing under `DuplicateRecordFields`. Qualify the import (`import Notion.V1.Views qualified as Views`) or use a pattern binding, as the existing code does.

Commit after each milestone. Use Conventional Commits with the plan trailers, for example:

```text
feat(views): add view query create, results and delete endpoints

Replace the never-served POST views/{id}/query route with the
three-step views/{id}/queries flow from the official SDK, add the
queryAllViewPages helper, and mirror the Methods change in
notion-client-effectful.

MasterPlan: docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md
ExecPlan: docs/plans/9-add-view-queries-and-typed-view-configuration.md
```

Suggested subjects for the later milestones:

- `feat(views): type view filters, sorts and create/update request fields`
- `feat(views): type table, board, calendar, timeline, gallery and list configuration`
- `feat(views): type chart, map, form and dashboard configuration`


## Validation and Acceptance

**Unit tests (no network).** `cabal test` must end with `Test suite tasty: PASS`, and every test under `Views (EP-4)` must print `OK`. The tests demonstrate behavior, not just compilation:

- The query fixtures decode into `ViewQuery`, `ListOf PartialPageObject` and `DeletedViewQuery` with the asserted counts, cursors and flags.
- Every `Filter` and `Sort` value survives `toJSON` then `fromJSON` unchanged. An array-valued select filter is preserved as `RawViewFilter` rather than failing.
- The `ViewObject` fixture yields a `DatabaseParent`, a typed `And` filter, typed sorts and a typed quick filter. An unknown view type yields `UnknownViewType`.
- `UpdateView` with `Clear` emits `"filter":null`. `Unset` emits no key. A `Nothing` quick-filter entry emits `"Priority":null`.
- Every configuration fixture decodes to its typed constructor and re-encodes byte-for-byte to the same JSON value. Response-only names are stripped, and unknown types and enum values round-trip unchanged.

Run the unit tests before Milestone 1's edits as a baseline. The new `ViewTests` module does not exist yet, so its tests are absent. They must all pass afterwards.

**Both packages build.** `cabal build all` compiles `notion-client`, `notion-client-effectful`, the example and the tests. This proves the effectful lockstep: a missing `CreateViewQuery` case in `Interpreter.hs` would fail with an incomplete-pattern warning, and a stale `queryView` export would fail with a "not in scope" error.

**Optional live check.** This needs a Notion integration token with access to a database that has at least one row:

```bash
export NOTION_TOKEN=secret_...
export NOTION_TEST_DATABASE_ID=<database id>
cabal run notion-client-example 2>&1 | sed -n '/=== Views: Create Table View ===/,/View lifecycle complete/p'
```

Observe that "Creating table view... ✓ Done" is followed by a `Views: Query View Rows` section that prints:

- a query id
- `totalCount` equal to the number of rows in the database's first data source, or fewer if the new view hides some
- an `expiresAt` timestamp a few minutes in the future
- `deleted: True`
- a `queryAllViewPages` count equal to `totalCount`

With the same variables set, `cabal test` also runs the "View E2E" group, whose lifecycle test now exercises create query, get results and delete query. Record the observed output in Surprises & Discoveries. The live semantics of `next_cursor` from the create response have not been verified against a real workspace, so note whether continuing from it returned the second page as expected.


## Idempotence and Recovery

All changes are source edits plus new files, so every step can be repeated. The build and tests do not touch any Notion data. The example and E2E test create a view and a view query and delete both at the end.

If a live run is interrupted, delete the leftover view "API Demo - Table View" or "E2E Test View" in the Notion UI. Leftover view queries expire on their own at `expires_at`.

If a milestone is half-done and the build is broken, `git stash` (or `git checkout -- <file>`) returns to the last green commit. Each milestone is committed separately, so rolling back one milestone is `git revert <commit>`.

If `treefmt` rewrites files during `git commit`, run `git add -u` and commit again.

If another Wave-2 plan has edited `notion-client.cabal`'s `test-suite tasty` stanza or the top-level list in `tasty/Main.hs` in the meantime, resolve the conflict by keeping both plans' lines. If EP-2 changed `makeMethods` or `ListOf` concurrently, rebase and re-apply the three-route pattern change where `listViews_` now lives. The `ListOf` pattern in `queryAllViewPages` uses field puns, so it survives an added `requestStatus` field.


## Interfaces and Dependencies

This plan adds no new package dependencies. It uses:

- `aeson`'s `omitField` / `omittedField` class methods, which the existing `aeson >=2.2 && <2.3` bound guarantees. They are what make `Clearable` work with `genericToJSON` and `genericParseJSON`.
- `servant` `Capture`, `QueryParam`, `ReqBody`, `Get`, `Post` and `Delete` for the routes.
- `scientific` (already a library dependency) for chart and number-group values.
- `containers` `Map` for quick filters.
- `Control.Exception` from `base` for `finally` and `try` in the helper.
- The test suite's existing dependencies: `aeson`, `bytestring`, `containers`, `scientific`, `tasty`, `tasty-hunit`, `text` and `vector`.

At the end of Milestone 1, these exist:

```haskell
-- Notion.V1.Pages (shared with EP-5; defined by whichever plan lands first)
newtype PartialPageObject = PartialPageObject {id :: PageID}

-- Notion.V1.Views
type ViewQueryID = UUID
newtype CreateViewQuery = CreateViewQuery {pageSize :: Maybe Natural}
data ViewQuery = ViewQuery {id :: ViewQueryID, viewId :: ViewID, expiresAt :: POSIXTime, totalCount :: Natural,
                            results :: Vector PartialPageObject, nextCursor :: Maybe Text, hasMore :: Bool}
                            -- plus requestStatus :: Maybe RequestStatus iff EP-2 had landed
data DeletedViewQuery = DeletedViewQuery {id :: ViewQueryID, deleted :: Bool}

-- Notion.V1.Methods (fields)
createViewQuery :: Views.ViewID -> Views.CreateViewQuery -> IO Views.ViewQuery
getViewQueryResults :: Views.ViewID -> Views.ViewQueryID -> Maybe Text -> Maybe Natural -> IO (ListOf PartialPageObject)
deleteViewQuery :: Views.ViewID -> Views.ViewQueryID -> IO Views.DeletedViewQuery

-- Notion.V1.ViewQueries
queryAllViewPages :: Methods -> ViewID -> Maybe Natural -> IO (Vector PartialPageObject)

-- Notion.V1.Effectful.Effect (and re-exported by Notion.V1.Effectful)
createViewQuery :: (Notion :> es) => Views.ViewID -> Views.CreateViewQuery -> Eff es Views.ViewQuery
getViewQueryResults :: (Notion :> es) => Views.ViewID -> Views.ViewQueryID -> Maybe Text -> Maybe Natural -> Eff es (ListOf PartialPageObject)
deleteViewQuery :: (Notion :> es) => Views.ViewID -> Views.ViewQueryID -> Eff es Views.DeletedViewQuery
```

At the end of Milestone 2, these exist:

```haskell
-- Notion.V1.Clearable
data Clearable a = Unset | Clear | Set a   -- ToJSON (omitField Unset = True), FromJSON (omittedField = Just Unset)
clearableToMaybe :: Clearable a -> Maybe a

-- Notion.V1.Filter (new instances only)
instance FromJSON Filter; instance FromJSON PropertyCondition; instance ToJSON PropertyCondition
instance FromJSON Sort; instance FromJSON SortDirection

-- Notion.V1.Views
data ViewType = … | UnknownViewType Text
data ViewFilter = ViewFilter Filter | RawViewFilter Value
data ViewSort = ViewSort Sort | RawViewSort Value
data QuickFilter = QuickFilter PropertyCondition | RawQuickFilter Value
data ViewPropertySort = ViewPropertySort {property :: Text, direction :: SortDirection}
data ViewPosition = ViewPositionStart | ViewPositionEnd | ViewPositionAfterView ViewID
data WidgetPlacement = NewRow (Maybe Natural) | ExistingRow Natural
data CreateDatabaseForView = CreateDatabaseForView {parentPageId :: UUID, afterBlockId :: Maybe UUID}
-- ViewObject, CreateView, UpdateView retyped as shown in Milestone 2
```

At the end of Milestone 3, `Notion.V1.ViewConfig` (re-exported by `Notion.V1.Views`) exports:

- `ViewConfig (..)` with the table, board, calendar, timeline, gallery, list and unknown constructors.
- `TableViewConfig (..)`, `BoardViewConfig (..)`, `CalendarViewConfig (..)`, `TimelineViewConfig (..)`, `GalleryViewConfig (..)`, `ListViewConfig (..)`, `TimelinePreference (..)`, `TimelineArrowsBy (..)`.
- `GroupByConfig (..)` and its nine record types, `FormulaSubGroupBy (..)` and its four record types, `GroupSort (..)`.
- `ViewPropertyConfig (..)`, `SubtaskConfig (..)`, `CoverConfig (..)`.
- Every Milestone 3 enum with `(..)`.

All three `configuration` fields are `Maybe ViewConfig`.

At the end of Milestone 4, `ViewConfig` also has `MapConfig`, `FormConfig`, `ChartConfig` and `DashboardConfig`. The module additionally exports:

- `MapViewConfig (..)`, `FormViewConfig (..)`, `ChartViewConfig (..)`, `ChartAggregation (..)`, `ChartReferenceLine (..)`.
- `DashboardViewConfig (..)`, `DashboardRow (..)`, `DashboardWidget (..)`.
- Every Milestone 4 enum with `(..)`.

Across plans, this plan consumes `RequestStatus` from EP-2 (`docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md`) when present. It shares ownership of the `Filter`/`Sort` `FromJSON` instances with EP-5 (`docs/plans/10-type-data-source-database-and-search-results-and-close-query-and-filter-gaps.md`), and EP-5 may reuse `ToJSON`/`FromJSON PropertyCondition` for its own work. It must not add filter condition constructors.
