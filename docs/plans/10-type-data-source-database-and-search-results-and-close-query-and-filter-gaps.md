---
id: 10
slug: type-data-source-database-and-search-results-and-close-query-and-filter-gaps
title: "Type Data Source, Database, and Search Results and Close Query and Filter Gaps"
kind: exec-plan
created_at: 2026-09-14T18:46:51Z
intention: intention_01m2jjvjgpef9tyyp50524jfwq
master_plan: "docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md"
provenance:
  created_by:
    model: "claude-opus-5"
    harness: "claude-code"
    at: 2026-09-14T18:46:51Z
  revisions:
    - model: "claude-opus-5[1m]"
      harness: "claude-code"
      at: 2026-09-15T14:46:36Z
      mode: "implement"
      note: "Implementing EP-5 milestones"
---

# Type Data Source, Database, and Search Results and Close Query and Filter Gaps

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.

This plan is EP-5 of the MasterPlan `docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md`.


## Purpose / Big Picture

`notion-client` is a Haskell library for the Notion HTTP API. Today, three of its most used calls return data that is either untyped or wrong for some workspaces:

- Querying a data source (`queryDataSource`) is typed as returning only full page objects. Notion can also return partial pages, full data sources and partial data sources (a "wiki" database lists child data sources next to pages). When it does, decoding the whole response fails and the caller gets an exception instead of rows.
- Search (`search`) returns raw JSON values (`ListOf Value`). The helper `parseSearchResults` silently drops every result it cannot decode, so partial objects disappear without notice.
- A single query can return at most a fixed number of rows (10,000 by default). Past that limit, Notion stops paginating and marks the response "incomplete". The Haskell client has no way to fetch the rest.

Several smaller request and response fields that the official Notion TypeScript SDK supports are also missing. Examples: the `database_type` of a database ("tasks", "projects", ...), `description` on property schemas and select options, renaming a property without resending its schema, the `{property: "relevance"}` search sort, verification `does_not_equal` filters, and array values for select and status filters.

After this plan is implemented, a Haskell user can:

1. Query any data source, including wikis, and pattern-match each result as `PageResult`, `PartialPageResult`, `DataSourceResult`, `PartialDataSourceResult` or `UnknownResult`.
2. Call `search` and receive the same typed results directly.
3. Stream or collect every row of a data source past the 10,000-row limit with `iterateAllDataSourceRows` / `collectAllDataSourceRows`.
4. Read and write every data-source, database, search, property-schema and filter field the JS SDK types describe.

The proof is a new `tasty` test module, `tasty/DataSourceSearchTests.hs`. It decodes JSON fixtures transcribed from the JS SDK types and simulates the row helper against a fake query function. When a `NOTION_TOKEN` is available, the example executable also prints the typed search and query results.


## Progress

- [x] (2026-09-15) Preconditions verified: EP-1 (`filter_properties` query parameter, tolerant `NumberFormat`) and EP-2 (`ListOf.requestStatus`) are merged.
- [x] (2026-09-15) Test module `tasty/DataSourceSearchTests.hs` created and wired into `notion-client.cabal` and `tasty/Main.hs`.
- [x] (2026-09-15) Milestone 1: `DatabaseType`, `CreateDatabaseType`, optional `CreateDatabase.title` and `InitialDataSource.properties`.
- [x] (2026-09-15) Milestone 1: `PartialPageObject` (reused from EP-4), `PartialDataSourceObject`, `PartialDatabaseObject`, `PageOrDataSource`, `QueryResultType`, `_QueryDataSource`.
- [x] (2026-09-15) Milestone 1: `queryDataSource` returns `ListOf PageOrDataSource`; `Methods`, effectful package, example and tests updated; M1 tests pass.
- [x] (2026-09-15) Milestone 2: `SearchSort` and `SearchFilter` sum types; `search` returns `ListOf PageOrDataSource`; `SearchResult`/`parseSearchResults` removed; call sites and effectful package updated; M2 tests pass.
- [x] (2026-09-15) Milestone 3: property schema `schemaDescription`, `SelectOption.description`, relation `relationDatabaseId`, optional dual-property fields, `LocationSchema`, `LastVisitedTimeSchema`, `UnknownSchema`, status without groups, empty id omitted.
- [x] (2026-09-15) Milestone 3: `PropertyUpdate`/`OptionUpdate`/`OptionTarget` for `UpdateDataSource`; call sites updated; M3 tests pass.
- [x] (2026-09-15) Milestone 4: new filter constructors (verification `does_not_equal`, array values, `unique_id` empty checks with `Scientific`, `RelativeDate`), unknown fallbacks.
- [x] (2026-09-15) Milestone 4: `FromJSON` for `Filter` and `Sort` added (or extended, if EP-4 added them first); M4 tests pass.
- [x] (2026-09-15) Milestone 5: `src/Notion/V1/DataSourceRows.hs` with `createdTimeLowerBound`, `foldAllDataSourceRows`, `iterateAllDataSourceRows`, `collectAllDataSourceRows`; M5 tests pass.
- [ ] CHANGELOG `## Unreleased` entries written; `cabal build all` and `cabal test` green; MasterPlan Progress items for EP-5 checked.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Model the query and search result union as one sum type, `PageOrDataSource`, defined in `src/Notion/V1/DataSources.hs` and re-exported from `src/Notion/V1/Search.hs` (with `type SearchResult = PageOrDataSource`). Its constructors are `PageResult`, `PartialPageResult`, `DataSourceResult`, `PartialDataSourceResult` and `UnknownResult Value`.
  Rationale: The JS SDK's `QueryDataSourceResponse.results` and `SearchResponse.results` have the identical four-member union. Reusing the names `PageResult` and `DataSourceResult` from the old `SearchResult` type keeps existing pattern matches compiling. `Search.hs` already imports `DataSources.hs`, so defining the type there creates no import cycle.
  Date: 2026-09-14

- Decision: A result is "full" if the JSON object has a `url` key (for `object: "page"`) or a `title` key (for `object: "data_source"`). Otherwise it is partial. A full object that fails to decode is a decode error, not a silent fallback to partial. An unknown `object` value decodes to `UnknownResult`.
  Rationale: These are exactly the discriminators of the JS SDK guards `isFullPage` and `isFullDataSource` in `src/helpers.ts`. Failing loudly on a malformed full object avoids reintroducing the silent data loss of `parseSearchResults`.
  Date: 2026-09-14

- Decision: Keep the page-only ergonomics as pure helpers, `pageResults :: Vector PageOrDataSource -> Vector PageObject` and `dataSourceResults :: Vector PageOrDataSource -> Vector DataSourceObject`, rather than a second `Methods` field.
  Rationale: This avoids a new Servant route and a new effectful constructor for the same endpoint. Callers who know their data source is not a wiki write `pageResults (results list)`.
  Date: 2026-09-14

- Decision: Do not change the return types of `retrieveDatabase`, `createDatabase`, `updateDatabase`, `retrieveDataSource`, `createDataSource` or `updateDataSource` to partial-or-full unions, even though the JS SDK types them that way. `PartialDatabaseObject` and `PartialDataSourceObject` are still added and exported, and the partial data source is used inside `PageOrDataSource`.
  Rationale: For those endpoints the integration always has access to the object it just addressed, and a sum return type would force every existing caller to unwrap it. The partial types remain available for manual decoding.
  Date: 2026-09-14

- Decision: Leave `queryDatabase` (the deprecated `POST databases/{id}/query`) returning `ListOf PageObject`.
  Rationale: The JS SDK has no such endpoint, and the repository's own notes say it returns HTTP 400 on current API versions. Changing it is churn without benefit.
  Date: 2026-09-14

- Decision: Keep `CreateDataSource.description` and `CreateDataSource.cover`, and document on the record that they are not in the published schema.
  Rationale: The JS SDK body parameters for `POST data_sources` are only `parent`, `properties`, `title` and `icon` (verified in `src/api-endpoints/data-sources.ts`, `createDataSource.bodyParams`). Both Haskell fields are `Maybe` and omitted when `Nothing`, so they never change the wire format unless a caller sets them. Removing them would break callers without fixing a failure.
  Date: 2026-09-14

- Decision: Replace `UpdateDataSource.properties :: Maybe (Map Text (Maybe PropertySchema))` with `Maybe (Map Text PropertyUpdate)`. `PropertyUpdate` has the constructors `RemoveProperty`, `RenameProperty Text`, `SetPropertySchema PropertySchema`, and three option-update constructors that target options by name or id.
  Rationale: The JS request allows, per property, `null`, a rename-only `{name}`, a full config, or option lists whose entries are `{name, id?}` or `{id, name?}`. A nested `Maybe` cannot express rename-only or id-targeted options.
  Date: 2026-09-14

- Decision: Stop sending `"groups"` for a status schema when `statusGroups` is empty, and stop sending `"id"` for any property schema whose `schemaId` is the empty string. Decoding accepts a missing `groups`, `id` or `name`.
  Rationale: JS `StatusPropertyConfigRequest` and `StatusPropertyConfigUpdateRequest` only have `options`, and `PropertyConfigurationRequest` has no `id`. Omitting only the empty values keeps existing round-trip tests, which use non-empty ids and groups, valid.
  Date: 2026-09-14

- Decision: Add tolerant fallback constructors where responses are decoded: `UnknownDatabaseType Text`, `UnknownResult Value`, `UnknownSchema`, `UnknownFilter Value`, `UnknownCondition Text Value`, `UnknownSort Value` and `UnknownVerificationState Text`. Request-only enums (`CreateDatabaseType`, `QueryResultType`, `RelativeDate`) get no fallback.
  Rationale: This follows the MasterPlan rule that every closed enum or sum decoded from a response carries an "unknown" constructor. `Filter` and `Sort` are decoded from view responses by EP-4.
  Date: 2026-09-14

- Decision: Model string-or-array filter values as additional constructors taking `NonEmpty Text` (for example `SelectEqualsAny`). Relative dates are a `RelativeDate` enum plus a `relativeDate :: RelativeDate -> Text` renderer that is passed to the existing `Text`-taking date constructors.
  Rationale: Both are additive, so existing filters keep compiling. `NonEmpty` rules out an empty array. The date conditions already take `Text`, so a renderer gives type safety without five new constructors.
  Date: 2026-09-14

- Decision: The full-row helper takes the query as a function argument, `QueryDataSource -> IO (ListOf PageOrDataSource)`, rather than a `Methods` value and a data source id.
  Rationale: The function form is independent of how EP-1 routes `filter_properties` (callers partially apply `queryDataSource methods dsId`, plus a property list if EP-1 made that an argument). It can also be driven by a fake in unit tests, and works from the effectful package. No `Methods` field or effectful constructor is added for it.
  Date: 2026-09-14

- Decision: `FromJSON` for `Filter` and `Sort` is written conditionally. If EP-4 (`docs/plans/9-add-view-queries-and-typed-view-configuration.md`) has already added the instances, this plan only extends them for the new constructors and records that here. Otherwise this plan adds them.
  Rationale: The MasterPlan Integration Points say that whichever of EP-4 and EP-5 starts first adds them.
  Date: 2026-09-14


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

### Repository and toolchain

The repository root is the directory containing `notion-client.cabal`; all paths below are relative to it. It is a Haskell project built with GHC 9.12.2 and cabal. `cabal.project` builds two packages:

- `notion-client`: sources in `src/`, tests in `tasty/`, example executable in `notion-client-example/`.
- `notion-client-effectful`: sources in `notion-client-effectful/src/`.

Build everything with `cabal build all` and run the tests with `cabal test`. A git pre-commit hook runs `treefmt`, which reformats Haskell files. If a commit is rejected because files changed, re-stage them (`git add -u`) and commit again.

The library uses these default extensions (see `notion-client.cabal`): `DuplicateRecordFields`, `OverloadedLabels`, `OverloadedStrings` and `RecordWildCards`. `GHC2024` adds `LambdaCase` and friends. Modules whose records have an `id` field start with `import Prelude hiding (id)`. The internal module `src/Notion/Prelude.hs` re-exports common types (`Text`, `Vector`, `Map`, `Value`, `POSIXTime`, `Natural`, `NonEmpty`, Servant combinators) and provides:

- `aesonOptions`: generic Aeson options that convert camelCase field names to snake_case (`startCursor` becomes `start_cursor`), strip a trailing underscore (`type_` becomes `type`), and omit `Nothing` fields.
- `parseISO8601 :: Text -> Parser POSIXTime` and `posixToISO8601 :: POSIXTime -> Text`.

Response decoders in this codebase are mostly hand-written `FromJSON` instances using `\case Object o -> ...` and the operators `.:` (required key) and `.:?` (optional key). Request encoders use either `genericToJSON aesonOptions` or hand-written `Aeson.object [...]`.

### Terms used in this plan

- **Data source.** Since Notion API version 2025-09-03, a *database* is a container, and each *data source* inside it holds a property schema and rows (pages). The Haskell client pins `Notion-Version: 2026-03-11` in `src/Notion/V1.hs`.
- **Wiki.** A database whose data source can contain child data sources as well as pages. Querying it returns both kinds of result.
- **Partial object.** A minimal JSON object Notion returns instead of a full one, for example `{"object":"page","id":"..."}`.
- **Property schema.** The definition of one column of a data source (its type and configuration, such as select options).
- **Filter / sort.** The typed query DSL (domain-specific language) in `src/Notion/V1/Filter.hs`. It is serialized into the `filter` and `sorts` fields of a query body.
- **`request_status`.** An optional field on list responses. When `type` is `"incomplete"`, Notion stopped returning rows because the per-query result limit was reached, even though more rows match.
- **JS SDK.** Notion's official TypeScript client, v5.26.0. Its generated types are the reference for the wire format. All shapes this plan needs are transcribed below, so you do not need that repository.

### `Methods`, the API type, and the effectful lockstep

`src/Notion/V1.hs` defines three things:

- The Servant `API` type, which combines each resource module's `API`.
- `makeMethods :: ClientEnv -> Text -> Methods`, which pattern-binds the generated client functions in exactly the same order as the routes (for example `queryDataSource` is the fourth route in `DataSources.API`, and is bound in that position).
- The `Methods` record of `IO` functions.

Today the relevant fields are:

```haskell
queryDataSource :: DataSourceID -> DataSources.QueryDataSource -> IO (ListOf PageObject),
search :: SearchRequest -> IO (ListOf Value),
```

(EP-1 keeps `queryDataSource`'s signature; `filterProperties` travels in the URL via a `makeMethods` wrapper. See Preconditions.)

The companion package mirrors every field. `notion-client-effectful/src/Notion/V1/Effectful/Effect.hs` has one GADT constructor per field, for example:

```haskell
QueryDataSource :: DataSourceID -> DataSources.QueryDataSource -> Notion m (ListOf PageObject)
Search :: SearchRequest -> Notion m (ListOf Value)
```

It also has one smart constructor per field with the same name and argument order (`queryDataSource`, `search`). `notion-client-effectful/src/Notion/V1/Effectful/Interpreter.hs` dispatches each constructor to the `Methods` field (for example `Search req -> runIO (Notion.search methods req)`). **Lockstep rule:** whenever a `Methods` field's type changes, the GADT constructor and the smart constructor must change in the same commit. The interpreter usually needs no edit, because it only forwards arguments. Build with `cabal build all` to check both packages.

### Files this plan edits

- `src/Notion/V1/Databases.hs`
  - `DatabaseObject`, with a hand-written `FromJSON`. It has no `databaseType`.
  - `CreateDatabase`: `title :: Vector RichText` is required.
  - `newtype InitialDataSource { properties :: Map Text PropertySchema }`.
  - `QueryDatabase`, and `API` (create, get, update, query).
- `src/Notion/V1/DataSources.hs`
  - `DataSourceObject`, with a hand-written `FromJSON` that requires `created_by`, `title` and friends.
  - `CreateDataSource`.
  - `UpdateDataSource`, with `properties :: Maybe (Map Text (Maybe PropertySchema))` and a hand-written `ToJSON` that emits `null` for `Nothing`.
  - `QueryDataSource`: fields `filter`, `sorts`, `startCursor`, `pageSize`, `inTrash`, and `filterProperties` until EP-1. Its `ToJSON` is generic.
  - `API`: the query route returns `ListOf PageObject`.
- `src/Notion/V1/Search.hs`
  - `SearchRequest` and `_SearchRequest`.
  - `SearchSort {direction, timestamp :: Text}`.
  - `SearchFilter {value :: SearchObjectType, property :: Text}`, plus `pageFilter` and `dataSourceFilter`.
  - `API` returning `ListOf Aeson.Value`.
  - `SearchResult = PageResult PageObject | DataSourceResult DataSourceObject`, and `parseSearchResults`, which drops failures.
- `src/Notion/V1/Pages.hs`: `PageObject` (requires `url`, `created_by` and more). A partial page type is added here.
- `src/Notion/V1/Properties.hs`
  - `SelectOption {id :: Maybe Text, name :: Text, color :: Maybe SelectColor}`, generic JSON.
  - `StatusGroup`.
  - `RelationType = SingleProperty | DualProperty {syncedPropertyId :: Text, syncedPropertyName :: Text}`.
  - `PropertySchema`, whose constructors all carry `schemaId` and `schemaName`. `FromJSON` fails on unknown `type`. `ToJSON` always emits `id`, `name`, `type`, and for status both `options` and `groups`.
- `src/Notion/V1/Filter.hs`
  - `Filter = And | Or | PropertyFilter Text PropertyCondition | TimestampFilter TimestampType DateCondition`.
  - The condition types. `UniqueIdCondition` uses `Natural` and has no empty checks. `VerificationCondition = VerificationStatus Text`.
  - `Sort = PropertySort | TimestampSort`, and `SortDirection`.
  - Only `ToJSON` instances exist.
- `src/Notion/V1/ListOf.hs`: the `ListOf a = List {results, nextCursor, hasMore, type_, object}` envelope. EP-2 adds `requestStatus`.
- `src/Notion/V1.hs`: the `Methods` field types for `queryDataSource` and `search`.
- `notion-client-effectful/src/Notion/V1/Effectful/Effect.hs`: the `QueryDataSource` and `Search` constructors and smart constructors. It imports `Data.Aeson (Value)` only for `search`, so remove that import once `search` changes, because the package builds with `-Wall`.
- New: `src/Notion/V1/DataSourceRows.hs` (the full-row helper). Add it to `exposed-modules` in `notion-client.cabal`.
- New: `tasty/DataSourceSearchTests.hs`. Add it to `test-suite tasty` in `notion-client.cabal` as `other-modules: DataSourceSearchTests`, and reference it from the top-level `testGroup "Notion Client Tests" [...]` near line 159 of `tasty/Main.hs`.
- Call sites that must be updated when types change:
  - `tasty/Main.hs`:
    - Imports of `Notion.V1.Search` (line 48).
    - `testSearchPages` and `testSearchDataSources` (about lines 997-1017).
    - `testSerializeNullablePropertyDeletion` (about line 1503).
    - The property-schema round-trip tests (about lines 1978-2070).
  - `notion-client-example/Main.hs`: search section, lines 42 and 104-155.
  - `notion-client-example/DatabaseDemo.hs`: `SelectOption` values and `UpdateDataSource` near lines 110-137, and `TitleSchema`/`RichTextSchema` near line 88.
- `CHANGELOG.md`: it has no `## Unreleased` heading today (the top entry is `## 0.7.0.2`).

ADR context: this repository has no `docs/adr/` directory, so no relevant ADR exists.

### Preconditions (hard dependencies)

The MasterPlan makes EP-1 and EP-2 hard dependencies of this plan. Check both before starting Milestone 1.

EP-1 is `docs/plans/6-fix-wire-format-decoding-and-encoding-bugs-found-against-the-official-sdk.md`. It moves `filter_properties` from the JSON body of `queryDataSource` into a URL query parameter, and adds `OtherNumberFormat Text` to `NumberFormat`. To check, run from the repository root:

```bash
grep -n "filter_properties" src/Notion/V1/DataSources.hs
grep -n "OtherNumberFormat" src/Notion/V1/Properties.hs
```

Expect a `QueryParams "filter_properties"` (or `QueryParam`) line inside `DataSources.API`, and an `OtherNumberFormat` constructor. EP-1 keeps the `Methods` signature of `queryDataSource` unchanged. `filterProperties` stays a field of `QueryDataSource`, the hand-written `ToJSON` strips it from the body, and a wrapper inside `makeMethods` passes it to the `QueryParams "filter_properties" Text` route segment. When you add `resultType` to `QueryDataSource` in this plan, keep that wrapper and the body-stripping `ToJSON` intact. Add `result_type` to the body, not to the stripped keys. If EP-1 was implemented differently, for example with an extra `[Text]` argument, adapt every `queryDataSource methods dsId` snippet below and record it in the Decision Log.

EP-2 is `docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md`. It adds `requestStatus :: Maybe RequestStatus` to `ListOf`. To check:

```bash
grep -n "requestStatus\|data RequestStatus\|RequestStatus" src/Notion/V1/ListOf.hs
```

Expect a `requestStatus` field on `ListOf` and a `RequestStatus` type covering `{type: "complete" | "incomplete", incomplete_reason?}`. Read its constructor names; Milestone 5 needs a function `isIncomplete :: ListOf a -> Bool` written against them.

If EP-1 has not landed, Milestones 3 and 4 may still be implemented, because they touch neither the query route nor `ListOf`. Stop before Milestone 1 and record the blocker in Progress. If EP-2 has not landed, Milestones 1–4 may proceed, but Milestone 5 must wait.

### JS SDK wire shapes (transcribed)

Database and data source responses (from `databases.ts` and `data-sources.ts`). Both full objects carry `database_type`, and the partial forms are minimal:

```typescript
database_type:
  | "tasks" | "projects" | "sprints" | "docs" | "wiki"
  | "meetings" | "meeting_notes" | "skills" | "github_prs" | null

export type PartialDatabaseObjectResponse = { object: "database"; id: string }
export type PartialDataSourceObjectResponse = {
  object: "data_source"; id: string
  properties: Record<string, DatabasePropertyConfigResponse>
}
export type PartialPageObjectResponse = { object: "page"; id: string }
```

Create database body (`databases.ts`):

```typescript
type CreateDatabaseBodyParameters = {
  parent: { type: "page_id"; page_id: string } | { type: "workspace"; workspace: true }
  title?: Array<RichTextItemRequest>
  description?: Array<RichTextItemRequest>
  is_inline?: boolean
  initial_data_source?: { properties?: Record<string, PropertyConfigurationRequest> }
  // Cannot be combined with initial_data_source. When title is omitted, the database is named after the type.
  database_type?: "tasks" | "projects" | "skills"
  icon?: PageIconRequest
  cover?: PageCoverRequest
}
```

Query data source (`data-sources.ts`). `filter_properties` is a query parameter; everything else is the body:

```typescript
type QueryDataSourceBodyParameters = {
  sorts?: Array<
    | { property: string; direction: "ascending" | "descending" }
    | { timestamp: "created_time" | "last_edited_time"; direction: "ascending" | "descending" }>
  filter?: { or: GroupFilterOperatorArray } | { and: GroupFilterOperatorArray } | PropertyFilter | TimestampFilter
  start_cursor?: string | null
  page_size?: number
  in_trash?: boolean
  // Regular, non-wiki databases only support page children. Default: no filtering.
  result_type?: "page" | "data_source"
}
export type QueryDataSourceResponse = {
  type: "page_or_data_source"; page_or_data_source: {}
  object: "list"; next_cursor: string | null; has_more: boolean
  results: Array<PageObjectResponse | PartialPageObjectResponse
               | PartialDataSourceObjectResponse | DataSourceObjectResponse>
  request_status?: { type: "complete" | "incomplete"; incomplete_reason?: "query_result_limit_reached" }
}
```

Search (`search.ts`). The response has the same `results` union and `request_status`:

```typescript
type SearchBodyParameters = {
  sort?: { timestamp: "last_edited_time"; direction: "ascending" | "descending" }
       | { property: "relevance" }
  query?: string
  start_cursor?: string | null
  page_size?: number
  filter?: { property: "object"; value: "page" | "data_source"; in_trash?: boolean }
         | { in_trash: boolean }
}
```

Property schema responses (`data-sources.ts`). Every property carries a nullable `description`; select and status options carry a nullable `description`; the relation config carries `database_id`:

```typescript
type DatabasePropertyConfigResponseCommon = { id: string; name: string; description: string | null }
type SelectPropertyResponse = { id: string; name: string; color: SelectColor; description: string | null }
type DatabasePropertyRelationConfigResponseCommon = { database_id: string; data_source_id: string }
type StatusDatabasePropertyConfigResponse = { type: "status"; status: {
  options: Array<{ id: string; name: string; color: SelectColor; description: string | null }>
  groups: Array<{ id: string; name: string; color: SelectColor; option_ids: Array<string> }> } }
```

Property schema requests (`common.ts`). There is no `id`; `description` is optional. `location` and `last_visited_time` are request-only config types:

```typescript
type PropertyConfigurationRequestCommon = { description?: string | null }
type LocationPropertyConfigurationRequest = { type?: "location"; location: {} }
type LastVisitedTimePropertyConfigurationRequest = { type?: "last_visited_time"; last_visited_time: {} }
type StatusPropertyConfigRequest = {   // create: options only, no groups
  options?: Array<{ name: string; color?: SelectColor; description?: string | null }> }
type RelationPropertyConfigurationRequest = { type?: "relation"; relation: { data_source_id: string } & (
  | { type?: "single_property"; single_property: {} }
  | { type?: "dual_property"; dual_property: { synced_property_id?: string; synced_property_name?: string } }) }
```

Update data source `properties` (`data-sources.ts`). Each value is a config (as above, with optional `name`, `description` and `type`), or a rename-only object, or `null`. Option lists may target an option by id:

```typescript
properties?: Record<string,
  | ({ name?: string; description?: string | null } & (
      | { type?: "select"; select: { options?: Array<
            { color?: SelectColor; description?: string | null } &
            ({ name: string; id?: string } | { id: string; name?: string })> } }
      | { type?: "multi_select"; multi_select: { options?: /* same as select */ } }
      | { type?: "status"; status: { options?: /* same as select */ } }
      | /* ...every other create config, including place... */ ))
  | { name: string }       // rename only
  | null>                  // remove
```

Create data source body (`data-sources.ts`): only `parent`, `properties`, `title?`, `icon?`.

Filters (`common.ts`):

```typescript
type StringOrStringArray = string | Array<string>
type SelectPropertyFilter = { equals: StringOrStringArray } | { does_not_equal: StringOrStringArray } | ExistencePropertyFilter
type StatusPropertyFilter = { equals: StringOrStringArray } | { does_not_equal: StringOrStringArray } | ExistencePropertyFilter
type MultiSelectPropertyFilter = { contains: StringOrStringArray } | { does_not_contain: StringOrStringArray } | ExistencePropertyFilter
type ExistencePropertyFilter = { is_empty: true } | { is_not_empty: true }
type NumberPropertyFilter = { equals: number } | { does_not_equal: number } | { greater_than: number }
  | { less_than: number } | { greater_than_or_equal_to: number } | { less_than_or_equal_to: number } | ExistencePropertyFilter
// PropertyFilter member: { unique_id: NumberPropertyFilter; property: string; type?: "unique_id" }
// PropertyFilter member: { verification: { status: V } | { does_not_equal: V }; property: string; type?: "verification" }
//   where V = "verified" | "expired" | "none"
type RelativeDateValue = "today" | "tomorrow" | "yesterday" | "one_week_ago"
  | "one_week_from_now" | "one_month_ago" | "one_month_from_now"
type DateOrRelativeDate = string | RelativeDateValue   // used by equals/before/after/on_or_before/on_or_after
```

The `type?` discriminator on each property filter is optional and never sent by the Haskell client. When decoding, prefer it if present.

### The full-row helper in the JS SDK (`src/helpers.ts`)

`iterateAllDataSourceRows(client, args)` works around the per-query row limit. Its behaviour, which the Haskell port must reproduce exactly:

1. Keep a set of seen row ids, and a `windowStart` that starts undefined.
2. Repeat for each window:
   1. Query with `sorts: [{timestamp: "created_time", direction: "ascending"}]` and `filter: createdTimeLowerBound(args.filter, windowStart)`, paginating by `start_cursor` while `next_cursor` is non-null.
   2. For each row that is a full page or full data source, set `lastCreatedTime = row.created_time`.
   3. Yield each row whose id is not yet seen, and add the id to the seen set.
   4. If any response in the window had `request_status.type === "incomplete"`, the limit was reached.
3. If the limit was not reached, stop.
4. If `lastCreatedTime` is undefined or equals `windowStart`, throw an error whose message contains "cannot make progress". Otherwise set `windowStart = lastCreatedTime` and start the next window.

`createdTimeLowerBound(filter, windowStart)` works as follows:

- If `windowStart` is undefined, it returns `filter`.
- Otherwise the bound is `{timestamp: "created_time", created_time: {on_or_after: windowStart}}`.
- With no filter, it returns the bound.
- With a filter `{and: xs}`, it returns `{and: [...xs, bound]}`.
- With any other filter, it returns `{and: [filter, bound]}`.

A top-level `or` filter is not accepted (type `FullDataSourceQueryFilter = PropertyFilter | TimestampFilter | {and: ...}`). Adding the bound would need a third nesting level, and Notion allows only two. The JS tests (`test/helpers.test.ts`) cover five scenarios, and Milestone 5 ports all five:

- a single complete window;
- advancing past the limit with de-duplication;
- combining a caller filter with `and`;
- advancing on a data-source boundary row;
- throwing when one timestamp holds more rows than the limit.


## Plan of Work

The work is five milestones. Each leaves `cabal build all` and `cabal test` green and adds tests to `tasty/DataSourceSearchTests.hs`. Do the test-module wiring first, as part of Milestone 1.

### Test module wiring

Create `tasty/DataSourceSearchTests.hs`:

```haskell
module DataSourceSearchTests (tests) where

import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy.Char8 qualified as L8
import Data.Map qualified as Map
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "EP-5 Data sources, databases, search, filters"
    [ milestone1Tests
    -- later milestones append their groups here
    ]
```

Each milestone adds its own `testGroup` value and appends it to that list. In `notion-client.cabal`, under `test-suite tasty`, add a line `other-modules: DataSourceSearchTests` below `main-is: Main.hs`. If another plan already added `other-modules:`, append the module name to that list instead. In `tasty/Main.hs`, add `import DataSourceSearchTests qualified` and add `DataSourceSearchTests.tests` to the list inside `testGroup "Notion Client Tests"`.

Fixtures use made-up names such as "Tanaka Hanako" and "Sato Kenji" in titles, never a real person's name. Decode fixtures with a helper:

```haskell
decodeOrFail :: (Aeson.FromJSON a) => L8.ByteString -> IO a
decodeOrFail bs = either (assertFailure . ("decode failed: " <>)) pure (Aeson.eitherDecode bs)
```

Two fixture builders are used across milestones. `pageJson` builds a full page and `dataSourceJson` a full data source, both as `Aeson.Value`, with every field the Haskell decoders require:

```haskell
pageJson :: Text.Text -> Text.Text -> Aeson.Value
pageJson pid created =
  Aeson.object
    [ "object" Aeson..= ("page" :: Text.Text), "id" Aeson..= pid,
      "created_time" Aeson..= created, "last_edited_time" Aeson..= created,
      "created_by" Aeson..= user, "last_edited_by" Aeson..= user,
      "cover" Aeson..= Aeson.Null, "icon" Aeson..= Aeson.Null,
      "parent" Aeson..= Aeson.object ["type" Aeson..= ("data_source_id" :: Text.Text), "data_source_id" Aeson..= ("ds-1" :: Text.Text), "database_id" Aeson..= ("db-1" :: Text.Text)],
      "in_trash" Aeson..= False, "is_locked" Aeson..= False,
      "properties" Aeson..= Aeson.object [],
      "url" Aeson..= ("https://www.notion.so/" <> pid), "public_url" Aeson..= Aeson.Null ]
  where user = Aeson.object ["object" Aeson..= ("user" :: Text.Text), "id" Aeson..= ("user-1" :: Text.Text)]

dataSourceJson :: Text.Text -> Text.Text -> Aeson.Value
dataSourceJson dsid created =
  Aeson.object
    [ "object" Aeson..= ("data_source" :: Text.Text), "id" Aeson..= dsid,
      "created_time" Aeson..= created, "last_edited_time" Aeson..= created,
      "created_by" Aeson..= user, "last_edited_by" Aeson..= user,
      "title" Aeson..= ([] :: [Aeson.Value]), "description" Aeson..= ([] :: [Aeson.Value]),
      "properties" Aeson..= Aeson.object [],
      "parent" Aeson..= Aeson.object ["type" Aeson..= ("database_id" :: Text.Text), "database_id" Aeson..= ("db-1" :: Text.Text)],
      "database_parent" Aeson..= Aeson.object ["type" Aeson..= ("page_id" :: Text.Text), "page_id" Aeson..= ("page-0" :: Text.Text)],
      "is_inline" Aeson..= False, "in_trash" Aeson..= False, "database_type" Aeson..= ("wiki" :: Text.Text),
      "icon" Aeson..= Aeson.Null, "cover" Aeson..= Aeson.Null,
      "url" Aeson..= ("https://www.notion.so/" <> dsid), "public_url" Aeson..= Aeson.Null ]
  where user = Aeson.object ["object" Aeson..= ("user" :: Text.Text), "id" Aeson..= ("user-1" :: Text.Text)]
```

(If EP-1 made `created_by` optional or changed `Icon` decoding, these fixtures still decode, because they only add fields.)

### Milestone 1: database type, partial objects, and typed data source query results

Scope: at the end of this milestone, `DatabaseObject` and `DataSourceObject` expose `databaseType`. `CreateDatabase` can create a typed database without a title, `QueryDataSource` can send `result_type`, and `queryDataSource` returns `ListOf PageOrDataSource`, so wiki queries decode.

In `src/Notion/V1/Databases.hs`, add and export:

```haskell
-- | The kind of typed database, or an unrecognised value.
data DatabaseType
  = TasksDatabase
  | ProjectsDatabase
  | SprintsDatabase
  | DocsDatabase
  | WikiDatabase
  | MeetingsDatabase
  | MeetingNotesDatabase
  | SkillsDatabase
  | GithubPrsDatabase
  | UnknownDatabaseType Text
  deriving stock (Eq, Show, Generic)

instance FromJSON DatabaseType where
  parseJSON = Aeson.withText "DatabaseType" $ \case
    "tasks" -> pure TasksDatabase
    "projects" -> pure ProjectsDatabase
    "sprints" -> pure SprintsDatabase
    "docs" -> pure DocsDatabase
    "wiki" -> pure WikiDatabase
    "meetings" -> pure MeetingsDatabase
    "meeting_notes" -> pure MeetingNotesDatabase
    "skills" -> pure SkillsDatabase
    "github_prs" -> pure GithubPrsDatabase
    other -> pure (UnknownDatabaseType other)

instance ToJSON DatabaseType where
  toJSON = Aeson.String . \case
    TasksDatabase -> "tasks"
    ProjectsDatabase -> "projects"
    SprintsDatabase -> "sprints"
    DocsDatabase -> "docs"
    WikiDatabase -> "wiki"
    MeetingsDatabase -> "meetings"
    MeetingNotesDatabase -> "meeting_notes"
    SkillsDatabase -> "skills"
    GithubPrsDatabase -> "github_prs"
    UnknownDatabaseType t -> t

-- | Typed database kinds accepted by @POST /v1/databases@.
data CreateDatabaseType = CreateTasksDatabase | CreateProjectsDatabase | CreateSkillsDatabase
  deriving stock (Eq, Show, Generic)

instance ToJSON CreateDatabaseType where
  toJSON = Aeson.String . \case
    CreateTasksDatabase -> "tasks"
    CreateProjectsDatabase -> "projects"
    CreateSkillsDatabase -> "skills"

-- | @{"object":"database","id":...}@
newtype PartialDatabaseObject = PartialDatabaseObject {id :: DatabaseID}
  deriving stock (Generic, Show)

instance FromJSON PartialDatabaseObject where
  parseJSON = Aeson.withObject "PartialDatabaseObject" $ \o -> PartialDatabaseObject <$> o .: "id"
```

Add `import Data.Aeson qualified as Aeson` to the module. Then make these changes:

- Add `databaseType :: Maybe DatabaseType` to `DatabaseObject`, placed after `isInline`, decoded with `databaseType <- o .:? "database_type"`. `.:?` maps both an absent key and JSON `null` to `Nothing`.
- In `CreateDatabase`, change `title` to `Maybe (Vector RichText)` and add `databaseType :: Maybe CreateDatabaseType`. Generic `ToJSON` with `aesonOptions` then emits `database_type` and omits `Nothing` fields.
- Change `InitialDataSource` to `newtype InitialDataSource = InitialDataSource {properties :: Maybe (Map Text PropertySchema)}`. It then encodes as `{}` when `Nothing`.

In `src/Notion/V1/Pages.hs`, first run `grep -n "PartialPageObject" src/Notion/V1/Pages.hs`. EP-4 or EP-6 may have added the type already; if so, reuse it. Otherwise add and export:

```haskell
-- | @{"object":"page","id":...}@
newtype PartialPageObject = PartialPageObject {id :: PageID}
  deriving stock (Generic, Show)

instance FromJSON PartialPageObject where
  parseJSON = \case
    Object o -> PartialPageObject <$> o .: "id"
    _ -> fail "Expected object for PartialPageObject"
```

In `src/Notion/V1/DataSources.hs`, add `databaseType :: Maybe DatabaseType` to `DataSourceObject`, placed after `isInline`, and decode it with `.:? "database_type"`. Import `Notion.V1.Databases (DatabaseType)`; `Databases.hs` does not import `DataSources.hs`, so there is no cycle. Add a doc comment on `CreateDataSource.description` and `cover` stating that they are not in the published request schema. Then add and export:

```haskell
-- | @{"object":"data_source","id":...,"properties":{...}}@
data PartialDataSourceObject = PartialDataSourceObject
  { id :: DataSourceID,
    properties :: Map Text PropertySchema
  }
  deriving stock (Generic, Show)

instance FromJSON PartialDataSourceObject where
  parseJSON = \case
    Object o -> PartialDataSourceObject <$> o .: "id" <*> (o .:? "properties" .!= mempty)
    _ -> fail "Expected object for PartialDataSourceObject"

-- | One result of a data source query or a search.
data PageOrDataSource
  = PageResult PageObject
  | PartialPageResult PartialPageObject
  | DataSourceResult DataSourceObject
  | PartialDataSourceResult PartialDataSourceObject
  | -- | An object type this client does not know; the raw JSON is kept.
    UnknownResult Value
  deriving stock (Generic, Show)

instance FromJSON PageOrDataSource where
  parseJSON v = case v of
    Object o -> do
      objectType <- o .:? "object" :: Parser (Maybe Text)
      case objectType of
        Just "page"
          | KeyMap.member "url" o -> PageResult <$> parseJSON v
          | otherwise -> PartialPageResult <$> parseJSON v
        Just "data_source"
          | KeyMap.member "title" o -> DataSourceResult <$> parseJSON v
          | otherwise -> PartialDataSourceResult <$> parseJSON v
        _ -> pure (UnknownResult v)
    _ -> pure (UnknownResult v)

-- | Full pages only.
pageResults :: Vector PageOrDataSource -> Vector PageObject
pageResults = Vector.mapMaybe $ \case PageResult p -> Just p; _ -> Nothing

-- | Full data sources only.
dataSourceResults :: Vector PageOrDataSource -> Vector DataSourceObject
dataSourceResults = Vector.mapMaybe $ \case DataSourceResult d -> Just d; _ -> Nothing

-- | The id of a result, if it has one (unknown results are inspected for a string @id@).
resultId :: PageOrDataSource -> Maybe Text

-- | @created_time@ of a full page or full data source; 'Nothing' for partial and unknown results.
resultCreatedTime :: PageOrDataSource -> Maybe POSIXTime

-- | Restrict a query to pages or to data sources.
data QueryResultType = ResultTypePage | ResultTypeDataSource
  deriving stock (Eq, Show, Generic)

instance ToJSON QueryResultType where
  toJSON ResultTypePage = Aeson.String "page"
  toJSON ResultTypeDataSource = Aeson.String "data_source"
```

Implement `resultId` and `resultCreatedTime` by pattern matching:

- `resultId (PageResult PageObject {id = UUID t}) = Just t`, and likewise for the other three constructors.
- For `UnknownResult (Object o)`, use `KeyMap.lookup "id" o` and accept only `String`.
- `resultCreatedTime` returns `Just createdTime` for `PageResult` and `DataSourceResult`, and `Nothing` otherwise.

Import `Data.Aeson.KeyMap qualified as KeyMap`, `Data.Aeson.Types (Parser)`, `Data.Vector qualified as Vector`, `(.!=)` from `Data.Aeson`, `Notion.V1.Common (UUID (..))` and `Notion.V1.Pages (PageObject (..), PartialPageObject)`. `PageObject (..)` brings the `id` field into scope; the module already hides `Prelude.id`.

Add `resultType :: Maybe QueryResultType` as the last field of `QueryDataSource`. If its `ToJSON` is still generic, `result_type` is emitted automatically. If EP-1 made it hand-written, add `<> maybe [] (\r -> ["result_type" .= r]) resultType`. Add and export a default value, unless EP-1 already added one (check with `grep -n "_QueryDataSource" src/Notion/V1/DataSources.hs`):

```haskell
-- | A query with every optional field unset. Use record update to set fields.
_QueryDataSource :: QueryDataSource
_QueryDataSource = QueryDataSource {filter = Nothing, sorts = Nothing, startCursor = Nothing, pageSize = Nothing, inTrash = Nothing, resultType = Nothing}
```

Include `filterProperties = Nothing` if that field still exists after EP-1.

In `DataSources.API`, change the query route's response type from `(ListOf PageObject)` to `(ListOf PageOrDataSource)`. Export `PartialDataSourceObject (..)`, `PageOrDataSource (..)`, `QueryResultType (..)`, `_QueryDataSource`, `pageResults`, `dataSourceResults`, `resultId` and `resultCreatedTime`. Also re-export `PartialPageObject (..)` for convenience.

In `src/Notion/V1.hs`, change the field to `queryDataSource :: DataSourceID -> ... -> DataSources.QueryDataSource -> IO (ListOf DataSources.PageOrDataSource)`, keeping any EP-1 argument. `makeMethods` needs no change, because the binding position is unchanged. In `notion-client-effectful/src/Notion/V1/Effectful/Effect.hs`, change the result type of the `QueryDataSource` GADT constructor and of the `queryDataSource` smart constructor to `ListOf DataSources.PageOrDataSource`.

Update the call sites:

- `notion-client-example/DatabaseDemo.hs`: the two `QueryDataSource` record literals need `resultType = Nothing`. The `paginateAll` result is now `Vector PageOrDataSource`; the printed count still works.
- `tasty/Main.hs`: `testQueryDataSource` needs `resultType = Nothing` in its literal.
- Search the whole tree for other `CreateDatabase {` literals and wrap `title` in `Just`, using `grep -rn "CreateDatabase" --include='*.hs' src tasty notion-client-example`.

Add a `milestone1Tests` group to `tasty/DataSourceSearchTests.hs` with these cases:

- `"DatabaseObject decodes database_type"`. Build a JSON object with the required `DatabaseObject` keys: `object`, `id`, `created_time`, `last_edited_time`, `title: []`, `url`, `parent: {"type":"page_id","page_id":"p1"}`, `data_sources: [{"id":"ds-1","name":"Tanaka Hanako Tasks"}]`, and `database_type: "tasks"`. Assert `databaseType == Just TasksDatabase`.
- `"DatabaseObject decodes null database_type"`. Same object with `"database_type": null`; expect `Nothing`.
- `"DatabaseType falls back on unknown values"`. `Aeson.eitherDecode "\"roadmaps\""` yields `Right (UnknownDatabaseType "roadmaps")`.
- `"DataSourceObject decodes database_type"`. Decode `dataSourceJson "ds-9" "2024-01-01T00:00:00.000Z"`; expect `Just WikiDatabase`.
- `"CreateDatabase encodes database_type without title"`. Encode `CreateDatabase {parent = PageParent {pageId = "p1"}, title = Nothing, initialDataSource = Nothing, icon = Nothing, cover = Nothing, description = Nothing, isInline = Nothing, databaseType = Just CreateTasksDatabase}`. Expect exactly `{"parent":{...},"database_type":"tasks"}`: check that `database_type` is `"tasks"` and that the `title` key is absent.
- `"InitialDataSource without properties encodes as {}"`. Expect `Aeson.object []`.
- `"QueryDataSource encodes result_type"`. `_QueryDataSource {resultType = Just ResultTypeDataSource}` encodes with `"result_type": "data_source"`.
- `"Query response decodes every result kind"`. Decode as `ListOf PageOrDataSource` a list whose `results` are `pageJson "r1" ...`, `{"object":"page","id":"r2"}`, `dataSourceJson "ds-child" ...`, `{"object":"data_source","id":"ds-3","properties":{}}` and `{"object":"view","id":"v1"}`, with `"type":"page_or_data_source"` and `"page_or_data_source":{}`. Assert that the constructors are, in order, `PageResult`, `PartialPageResult`, `DataSourceResult`, `PartialDataSourceResult` and `UnknownResult`, and that `resultId` gives `r1, r2, ds-child, ds-3, v1`.
- `"pageResults keeps only full pages"`. On the vector above, the length is 1.
- `"PartialDatabaseObject decodes"`. Decode `{"object":"database","id":"db-2"}`.

Acceptance: `cabal build all` succeeds with no new warnings, and `cabal test` shows the ten cases above as `OK`.

### Milestone 2: typed search

Scope: at the end of this milestone, `search` returns `ListOf PageOrDataSource`, sorts can be by relevance, and filters can include `in_trash` or be `in_trash` alone.

In `src/Notion/V1/Search.hs`, replace `SearchSort` and `SearchFilter`:

```haskell
-- | Search sort.
data SearchSort
  = -- | @{"timestamp":"last_edited_time","direction":...}@
    SearchByLastEditedTime SearchSortDirection
  | -- | @{"property":"relevance"}@
    SearchByRelevance
  deriving stock (Generic, Show)

instance ToJSON SearchSort where
  toJSON (SearchByLastEditedTime dir) = Aeson.object ["timestamp" .= ("last_edited_time" :: Text), "direction" .= dir]
  toJSON SearchByRelevance = Aeson.object ["property" .= ("relevance" :: Text)]

-- | Search filter.
data SearchFilter
  = -- | @{"property":"object","value":...,"in_trash"?:...}@
    SearchObjectFilter SearchObjectType (Maybe Bool)
  | -- | @{"in_trash":...}@
    SearchInTrashFilter Bool
  deriving stock (Generic, Show)

instance ToJSON SearchFilter where
  toJSON (SearchObjectFilter v mTrash) =
    Aeson.object $ ["property" .= ("object" :: Text), "value" .= v] <> maybe [] (\t -> ["in_trash" .= t]) mTrash
  toJSON (SearchInTrashFilter t) = Aeson.object ["in_trash" .= t]

pageFilter :: SearchFilter
pageFilter = SearchObjectFilter SearchPage Nothing

dataSourceFilter :: SearchFilter
dataSourceFilter = SearchObjectFilter SearchDataSource Nothing
```

Import `(.=)` from `Data.Aeson`. Then:

- Delete the old `SearchResult` data type, its `FromJSON` instance, and `parseSearchResults`.
- Add `type SearchResult = PageOrDataSource` and re-export `PageOrDataSource (..)`, `PartialPageObject (..)`, `PartialDataSourceObject (..)`, `pageResults` and `dataSourceResults` from `Notion.V1.DataSources`.
- Change `API` to `Post '[JSON] (ListOf PageOrDataSource)`.
- Remove the now-unused `Data.Vector` import and the `ListOf (..)` constructor import if `-Wall` flags them.

Update the export list accordingly, removing `parseSearchResults`.

In `src/Notion/V1.hs`, change the field to `search :: SearchRequest -> IO (ListOf Search.PageOrDataSource)`. In `Effect.hs`, change the `Search` constructor and the `search` smart constructor to `ListOf PageOrDataSource`, importing it from `Notion.V1.Search`, and delete `import Data.Aeson (Value)`. Update `notion-client-effectful/CHANGELOG.md` with a one-line note under an `## Unreleased` heading, created if absent.

Update the call sites:

- `notion-client-example/Main.hs`:
  - Replace `SearchSort {direction = Descending, timestamp = ...}` with `SearchByLastEditedTime Descending`.
  - Drop `parseSearchResults` and `SearchSort (..)` from the imports, and use `results rawResults` directly.
  - Print one line per result naming the constructor (`page`, `partial page`, `data_source`, `partial data_source`, `unknown`).
- `tasty/Main.hs`:
  - In `testSearchPages` and `testSearchDataSources`, iterate over `results result` instead of `parseSearchResults result`.
  - Accept `PartialPageResult` alongside `PageResult` (and the data-source equivalents), and fail on any other constructor.
  - Remove `parseSearchResults` from the import on line 48.

Add a `milestone2Tests` group:

- `"SearchSort relevance encodes"`. Expect `{"property":"relevance"}`.
- `"SearchSort last_edited_time encodes"`. Expect `{"timestamp":"last_edited_time","direction":"descending"}`.
- `"SearchFilter object filter with in_trash"`. `SearchObjectFilter SearchPage (Just True)` gives `{"property":"object","value":"page","in_trash":true}`.
- `"SearchFilter standalone in_trash"`. `SearchInTrashFilter False` gives `{"in_trash":false}`.
- `"Search response decodes typed results"`. Decode the same five-result list as in Milestone 1, plus `"request_status":{"type":"incomplete","incomplete_reason":"query_result_limit_reached"}`, as `ListOf PageOrDataSource`. Assert that there are 5 results and that none are dropped.

Acceptance: `cabal build all` succeeds, `cabal test` shows these five cases `OK`, and the existing tests still pass.

### Milestone 3: property schemas and data source updates

Scope: at the end of this milestone, property schemas round-trip `description`, and select and status options carry `description`. Relation schemas decode `database_id`, and dual-property synced fields are optional. The request-only `location` and `last_visited_time` types exist, and unknown property types decode instead of failing. `UpdateDataSource` can rename a property or target an option by id.

In `src/Notion/V1/Properties.hs`, make these changes:

1. Add `description :: Maybe Text` as the last field of `SelectOption`. Its generic JSON handles it: decoding tolerates `null` or an absent key, and encoding omits `Nothing`.

2. Change `DualProperty` to `DualProperty {syncedPropertyId :: Maybe Text, syncedPropertyName :: Maybe Text}`. In both `RelationType`'s `ToJSON` and `schemaFields`, emit only the `Just` keys inside `dual_property` (an empty object when both are `Nothing`). Decode both with `.:?`.

3. Add the field `schemaDescription :: Maybe Text` to **every** `PropertySchema` constructor, directly after `schemaName`. Add `relationDatabaseId :: Maybe UUID` to `RelationSchema` after `relationDataSourceId`. Add three constructors:

   ```haskell
     | LocationSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text}
     | LastVisitedTimeSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text}
     | -- | A property type this client does not model; @schemaConfig@ is the raw value under the type key.
       UnknownSchema {schemaId :: Text, schemaName :: Text, schemaDescription :: Maybe Text, schemaType :: Text, schemaConfig :: Value}
   ```

4. In `FromJSON PropertySchema`:
   - Read `sid <- o .:? "id" .!= ""`, `sname <- o .:? "name" .!= ""` and `sdesc <- o .:? "description"`, and pass `sdesc` into every constructor.
   - For `"relation"`, also read `cfg .:? "database_id"`.
   - For `"status"`, read `groups` with `.:? "groups" .!= mempty`.
   - Add `"location"` and `"last_visited_time"` cases.
   - Replace the `other -> fail` case with `other -> \o' -> UnknownSchema sid sname sdesc other <$> (o' .:? Key.fromText other .!= Aeson.object [])`. Import `Data.Aeson.Key qualified as Key` and `(.!=)`.

5. In `ToJSON PropertySchema`:
   - Build the envelope as `(if Text.null sid then [] else ["id" .= sid]) <> ["name" .= sname, "type" .= typeName] <> maybe [] (\d -> ["description" .= d]) (schemaDescription schema) <> [typeName .= typeConfig]`. Import `Data.Text qualified as Text`.
   - In `schemaFields`, change the status case to `object (["options" .= statusOptions] <> (if Vector.null statusGroups then [] else ["groups" .= statusGroups]))`, and emit `database_id` for relations only when `Just`.
   - Add `LocationSchema` (`"location"`, `object []`), `LastVisitedTimeSchema` (`"last_visited_time"`, `object []`) and `UnknownSchema` (`Key.fromText schemaType`, `schemaConfig`).

6. Add the update types and export them with `(..)`:

   ```haskell
   -- | Which existing option an option update addresses.
   data OptionTarget
     = -- | @{"name": ...}@: match (or create) by name.
       OptionNamed Text
     | -- | @{"id": ..., "name"?: ...}@: match by id, optionally renaming.
       OptionWithId Text (Maybe Text)
     deriving stock (Eq, Show, Generic)

   data OptionUpdate = OptionUpdate
     { target :: OptionTarget,
       color :: Maybe SelectColor,
       description :: Maybe Text
     }
     deriving stock (Eq, Show, Generic)

   instance ToJSON OptionUpdate where
     toJSON OptionUpdate {..} =
       object $
         ( case target of
             OptionNamed n -> ["name" .= n]
             OptionWithId i mn -> ["id" .= i] <> maybe [] (\n -> ["name" .= n]) mn
         )
           <> maybe [] (\c -> ["color" .= c]) color
           <> maybe [] (\d -> ["description" .= d]) description

   -- | One entry of @UpdateDataSource.properties@.
   data PropertyUpdate
     = -- | @null@: remove the property.
       RemoveProperty
     | -- | @{"name": ...}@: rename only.
       RenameProperty Text
     | -- | A full property configuration.
       SetPropertySchema PropertySchema
     | -- | @{"name"?:..., "select": {"options": [...]}}@
       UpdateSelectOptions {newName :: Maybe Text, optionUpdates :: Vector OptionUpdate}
     | UpdateMultiSelectOptions {newName :: Maybe Text, optionUpdates :: Vector OptionUpdate}
     | UpdateStatusOptions {newName :: Maybe Text, optionUpdates :: Vector OptionUpdate}
     deriving stock (Eq, Show, Generic)

   instance ToJSON PropertyUpdate where
     toJSON = \case
       RemoveProperty -> Null
       RenameProperty n -> object ["name" .= n]
       SetPropertySchema s -> toJSON s
       UpdateSelectOptions {..} -> opts "select" newName optionUpdates
       UpdateMultiSelectOptions {..} -> opts "multi_select" newName optionUpdates
       UpdateStatusOptions {..} -> opts "status" newName optionUpdates
       where
         opts key mName us = object $ maybe [] (\n -> ["name" .= n]) mName <> [key .= object ["options" .= us]]
   ```

In `src/Notion/V1/DataSources.hs`, change `UpdateDataSource.properties` to `Maybe (Map Text PropertyUpdate)`. In its `ToJSON`, replace `mapWithNulls` with a plain `"properties" .= p`: `Map Text PropertyUpdate` encodes as an object, and `RemoveProperty` becomes `null`. Import `PropertyUpdate`.

Update the construction sites. Omitting a record field is only a warning in Haskell, and the missing field crashes at runtime, so every literal must be fixed:

- Run `grep -rn "Schema {\|SelectOption {\|DualProperty {\|UpdateDataSource" --include='*.hs' src tasty notion-client-example` and add `schemaDescription = Nothing`, `description = Nothing` and `relationDatabaseId = Nothing` as needed.
- In `tasty/Main.hs`, change `testPropertySchemaRelationRoundTrip`'s `DualProperty` to `Just "sp1"`/`Just "Related"`.
- In `testSerializeNullablePropertyDeletion`, change the map to `[("OldColumn", RemoveProperty), ("NewColumn", SetPropertySchema (TitleSchema {...}))]`. Its assertions stay the same.
- In `notion-client-example/DatabaseDemo.hs`, wrap the update map values in `SetPropertySchema`.
- Finally, build with `cabal build all 2>&1 | grep -i "missing-fields\|Fields of"`. It must print nothing.

Add a `milestone3Tests` group:

- `"Property schema decodes description"`. Decode `{"id":"a1","name":"Owner","description":"Sato Kenji's column","type":"people","people":{}}` and assert `schemaDescription == Just "Sato Kenji's column"`.
- `"Select and status options decode description"`. Decode a select schema whose option is `{"id":"o1","name":"Done","color":"green","description":null}`, and a status schema with options carrying `"description":"finished"`, `groups` with one entry and `option_ids`.
- `"Relation schema decodes database_id"`. Decode `{"id":"r1","name":"Tasks","description":null,"type":"relation","relation":{"database_id":"db-1","data_source_id":"ds-1","type":"dual_property","dual_property":{"synced_property_id":"sp1","synced_property_name":"Related"}}}`. Expect `relationDatabaseId == Just "db-1"`.
- `"Dual property with no synced fields encodes empty dual_property"`. Expect `"dual_property": {}` under `relation`.
- `"Status schema without groups encodes options only"`. Expect the `status` value to be `{"options":[{"name":"Todo"}]}` (options built with `id = Nothing`, `color = Nothing`, `description = Nothing`).
- `"Empty schema id is omitted"`. `TitleSchema {schemaId = "", schemaName = "Name", schemaDescription = Nothing}` has no `id` key.
- `"Location and last_visited_time schemas encode"`. Expect `"type":"location","location":{}` and `"type":"last_visited_time","last_visited_time":{}`.
- `"Unknown property type decodes to UnknownSchema"`. Decode `{"id":"x","name":"Mood","type":"sentiment","sentiment":{"scale":5}}`. Expect `UnknownSchema` with `schemaType == "sentiment"`, and re-encoding gives the same `sentiment` object.
- `"UpdateDataSource rename-only property"`. `properties = Just (Map.fromList [("Old", RenameProperty "New")])` encodes to `{"properties":{"Old":{"name":"New"}}}`.
- `"UpdateDataSource select option targeted by id"`. `UpdateSelectOptions {newName = Nothing, optionUpdates = [OptionUpdate (OptionWithId "o1" Nothing) (Just Red) (Just "urgent")]}` encodes to `{"select":{"options":[{"id":"o1","color":"red","description":"urgent"}]}}`.

Acceptance: `cabal build all` prints no missing-field warnings, `cabal test` shows these ten cases `OK`, and every pre-existing property-schema round-trip test still passes.

### Milestone 4: filter conditions and filter/sort decoding

Scope: at the end of this milestone, `Filter` can express every JS SDK filter variant, and `Filter` and `Sort` decode from JSON with unknown fallbacks. EP-4 and users can then read filters and sorts from view responses.

First check whether EP-4 already added decoders: `grep -n "instance FromJSON Filter\|instance FromJSON Sort" src/Notion/V1/Filter.hs`. If both exist, keep EP-4's structure and names, extend each parser for the new constructors below, and record "consumed EP-4's FromJSON instances" in the Decision Log. If they do not exist, add them as described here.

In `src/Notion/V1/Filter.hs`, add and export:

```haskell
-- | Verification states used by verification filters.
data VerificationState
  = VerificationVerified
  | VerificationExpired
  | VerificationNone
  | UnknownVerificationState Text
  deriving stock (Eq, Show, Generic)

-- | Relative date keywords accepted wherever a date filter takes a date string.
data RelativeDate = Today | Tomorrow | Yesterday | OneWeekAgo | OneWeekFromNow | OneMonthAgo | OneMonthFromNow
  deriving stock (Eq, Show, Generic, Enum, Bounded)

-- | Render for use with 'DateAfter', 'DateBefore', 'DateEquals', 'DateOnOrAfter', 'DateOnOrBefore'.
relativeDate :: RelativeDate -> Text
relativeDate = \case
  Today -> "today"
  Tomorrow -> "tomorrow"
  Yesterday -> "yesterday"
  OneWeekAgo -> "one_week_ago"
  OneWeekFromNow -> "one_week_from_now"
  OneMonthAgo -> "one_month_ago"
  OneMonthFromNow -> "one_month_from_now"
```

Change and extend the condition types, and update their `*ToValue` functions:

- `SelectCondition`: add `SelectEqualsAny (NonEmpty Text)` and `SelectDoesNotEqualAny (NonEmpty Text)`. They encode as `{"equals": [..]}` and `{"does_not_equal": [..]}`; `NonEmpty` has a `ToJSON` instance that encodes as an array.
- `StatusCondition`: add `StatusEqualsAny (NonEmpty Text)` and `StatusDoesNotEqualAny (NonEmpty Text)`.
- `MultiSelectCondition`: add `MultiSelectContainsAny (NonEmpty Text)` and `MultiSelectDoesNotContainAny (NonEmpty Text)`.
- `UniqueIdCondition`: change every payload from `Natural` to `Scientific`, and add `UniqueIdIsEmpty` and `UniqueIdIsNotEmpty` (`{"is_empty": true}`, `{"is_not_empty": true}`).
- `VerificationCondition`: replace it with `VerificationStatus VerificationState | VerificationDoesNotEqual VerificationState`, which encode as `{"status": s}` and `{"does_not_equal": s}`. Give `VerificationState` `ToJSON` (`"verified"`, `"expired"`, `"none"`, raw text) and `FromJSON` (unknown strings become `UnknownVerificationState`).
- `PropertyCondition`: add `UnknownCondition Text Value` (the condition key and its raw value), encoded by `propertyConditionToObject` as `[(Key.fromText k, v)]`.
- `Filter`: add `UnknownFilter Value`, encoded as the raw value.
- `Sort`: add `UnknownSort Value`, encoded as the raw value.

Then write the decoders. The structure below is a guide, not code to paste unchanged:

```haskell
instance FromJSON Filter where
  parseJSON v = case v of
    Object o ->
      (And <$> o .: "and")
        <|> (Or <$> o .: "or")
        <|> timestampFilter o
        <|> propertyFilter o
        <|> pure (UnknownFilter v)
    _ -> pure (UnknownFilter v)
    where
      timestampFilter o = do
        ts <- o .: "timestamp"
        case ts :: Text of
          "created_time" -> TimestampFilter FilterCreatedTime <$> (o .: "created_time" >>= parseDateCondition)
          "last_edited_time" -> TimestampFilter FilterLastEditedTime <$> (o .: "last_edited_time" >>= parseDateCondition)
          _ -> fail "unknown timestamp"
      propertyFilter o = do
        prop <- o .: "property"
        PropertyFilter prop <$> parsePropertyCondition o
```

`parsePropertyCondition :: Aeson.Object -> Parser PropertyCondition` works as follows:

1. Pick the condition key. If `o .:? "type"` gives `Just k`, use `k`. Otherwise use the first key present from this list: `title`, `rich_text`, `number`, `checkbox`, `select`, `multi_select`, `status`, `date`, `people`, `files`, `url`, `email`, `phone_number`, `relation`, `created_by`, `created_time`, `last_edited_by`, `last_edited_time`, `formula`, `unique_id`, `rollup`, `verification`.
2. Parse the value under that key with the matching per-type parser, and wrap it in the matching constructor.
3. If the per-type parser fails, or the key is not in the list, return `UnknownCondition key rawValue`. Use `<|>` so a malformed known condition also falls back.
4. If there is no key at all, fail. `Filter`'s decoder then falls back to `UnknownFilter`.

Each per-type parser (`parseTextCondition`, `parseNumberCondition`, `parseDateCondition`, and the rest) is an `Aeson.withObject` that tries each operator key in turn:

- A string value under `equals` gives `SelectEquals`, and an array gives `SelectEqualsAny` via `NonEmpty`'s `FromJSON`, which fails on an empty array.
- `is_empty: true` gives the matching `IsEmpty` constructor.
- `next_week: {}` gives `DateNextWeek`, and so on.

`parseRollupCondition` decodes `any`, `every` and `none` by calling `parsePropertyCondition` on the inner object, which has no `property` key. Rule 1 above applies to it unchanged. `number` and `date` map to `RollupNumber` and `RollupDate`. `parseFormulaCondition` maps `string`, `number`, `date` and `checkbox`.

For sorts:

```haskell
instance FromJSON SortDirection where
  parseJSON = Aeson.withText "SortDirection" $ \case
    "ascending" -> pure Ascending
    "descending" -> pure Descending
    other -> fail ("Unknown sort direction: " <> unpack other)

instance FromJSON Sort where
  parseJSON v = case v of
    Object o ->
      (PropertySort <$> o .: "property" <*> o .: "direction")
        <|> (timestampSort o)
        <|> pure (UnknownSort v)
    _ -> pure (UnknownSort v)
```

`timestampSort` maps `"created_time"` and `"last_edited_time"` to `TimestampType`. An unknown direction makes the known branches fail, so the whole sort becomes `UnknownSort`. That is the tolerant fallback for `SortDirection`.

Import `Control.Applicative ((<|>))`, `Data.Aeson ((.:), (.:?))`, `Data.Aeson.Types (Parser)` and `Data.Aeson.KeyMap qualified as KeyMap`. Remove `Natural` usages from the module. `Scientific` is already imported.

Update the call sites: `grep -rn "VerificationStatus\|UniqueId" --include='*.hs' tasty notion-client-example` and adapt them. None are expected today.

Add a `milestone4Tests` group:

- `"Verification does_not_equal encodes"`. `PropertyFilter "Reviewed" (VerificationCondition (VerificationDoesNotEqual VerificationExpired))` gives `{"property":"Reviewed","verification":{"does_not_equal":"expired"}}`.
- `"Select equals array encodes"`. `SelectEqualsAny ("High" :| ["Medium"])` gives `{"equals":["High","Medium"]}` under `select`.
- `"Status and multi_select array variants encode"`. Covers `does_not_equal` and `contains` arrays.
- `"unique_id is_empty and fractional numbers encode"`. `UniqueIdIsEmpty` gives `{"is_empty":true}`, and `UniqueIdGreaterThan 2.5` gives `2.5`.
- `"relativeDate renders keywords"`. `DateOnOrAfter (relativeDate OneWeekAgo)` gives `{"on_or_after":"one_week_ago"}`, and `map relativeDate [minBound .. maxBound]` equals the seven JS strings in order.
- `"Filter FromJSON round-trips every constructor"`. Build a list of filters covering every condition constructor, including `And`/`Or` nesting, both timestamp filters, formula and rollup (`RollupAny (SelectCondition (SelectEquals "Done"))`), and the new constructors. Assert `Aeson.fromJSON (Aeson.toJSON f) == Aeson.Success f` for each.
- `"Filter FromJSON accepts optional type discriminator"`. `{"property":"Name","type":"title","title":{"contains":"Tanaka"}}` decodes to `PropertyFilter "Name" (TitleCondition (TextContains "Tanaka"))`.
- `"Unknown filter shapes fall back"`. `{"property":"Mood","sentiment":{"equals":"happy"}}` gives `PropertyFilter "Mood" (UnknownCondition "sentiment" ...)`, and `{"weird":1}` gives `UnknownFilter`.
- `"Sort FromJSON round-trips and falls back"`. Property and timestamp sorts round-trip; `{"property":"X","direction":"sideways"}` gives `UnknownSort`.

Acceptance: `cabal build all` succeeds, `cabal test` shows these nine cases `OK`, and the existing filter serialization tests in `tasty/Main.hs` ("Filter: property title contains" and others) still pass unchanged.

### Milestone 5: the full-row helper

Scope: at the end of this milestone, `Notion.V1.DataSourceRows` lets a caller visit every row of a data source past the per-query limit. It is proven against a fake query function replaying the five JS SDK test scenarios.

Create `src/Notion/V1/DataSourceRows.hs` and add `Notion.V1.DataSourceRows` to `exposed-modules` in `notion-client.cabal`. Import only `QueryDataSource (..)` and the result helpers from `Notion.V1.DataSources`. Do not import `Notion.V1.Databases` or `Notion.V1.Search` unqualified: `QueryDatabase` and `SearchRequest` also have `filter` and `startCursor` fields, and with `DuplicateRecordFields` the record update below would become ambiguous. Hide `Prelude.filter` for the same reason.

```haskell
-- | Iterate every row of a data source, including rows past Notion's per-query result limit.
module Notion.V1.DataSourceRows
  ( AllRowsFilter (..),
    DataSourceRowsError (..),
    createdTimeLowerBound,
    foldAllDataSourceRows,
    iterateAllDataSourceRows,
    collectAllDataSourceRows,
  )
where

import Control.Exception (Exception, throwIO)
import Control.Monad (foldM)
import Data.Set qualified as Set
import Data.Vector qualified as Vector
import Notion.Prelude
import Notion.V1.DataSources (PageOrDataSource, QueryDataSource (..), resultCreatedTime, resultId)
import Notion.V1.Filter (DateCondition (..), Filter (..), PropertyCondition, Sort (..), SortDirection (..), TimestampType (..))
import Notion.V1.ListOf (ListOf (..))
import Prelude hiding (filter)

-- | Filters the helper can combine with its created_time bound. A top-level 'Or' is
-- deliberately not representable: adding the bound would need a third nesting level.
data AllRowsFilter
  = AllRowsPropertyFilter Text PropertyCondition
  | AllRowsTimestampFilter TimestampType DateCondition
  | AllRowsAnd [Filter]
  deriving stock (Eq, Show)

data DataSourceRowsError
  = -- | The limit was reached but the window could not advance past this created_time.
    CannotMakeProgress (Maybe POSIXTime)
  deriving stock (Show)

instance Exception DataSourceRowsError

-- | Pure: combine the caller filter with @created_time on_or_after windowStart@.
createdTimeLowerBound :: Maybe AllRowsFilter -> Maybe POSIXTime -> Maybe Filter
createdTimeLowerBound mFilter Nothing = toFilter <$> mFilter
createdTimeLowerBound mFilter (Just start) =
  Just $ case mFilter of
    Nothing -> bound
    Just (AllRowsAnd xs) -> And (xs <> [bound])
    Just other -> And [toFilter other, bound]
  where
    bound = TimestampFilter FilterCreatedTime (DateOnOrAfter (posixToISO8601 start))

toFilter :: AllRowsFilter -> Filter
toFilter = \case
  AllRowsPropertyFilter p c -> PropertyFilter p c
  AllRowsTimestampFilter t c -> TimestampFilter t c
  AllRowsAnd xs -> And xs

foldAllDataSourceRows ::
  -- | The query, e.g. @queryDataSource methods dsId@.
  (QueryDataSource -> IO (ListOf PageOrDataSource)) ->
  -- | Base request; its @filter@, @sorts@ and @startCursor@ are overwritten.
  QueryDataSource ->
  Maybe AllRowsFilter ->
  acc ->
  (acc -> PageOrDataSource -> IO acc) ->
  IO acc

iterateAllDataSourceRows ::
  (QueryDataSource -> IO (ListOf PageOrDataSource)) -> QueryDataSource -> Maybe AllRowsFilter -> (PageOrDataSource -> IO ()) -> IO ()
iterateAllDataSourceRows q base f visit = foldAllDataSourceRows q base f () (const visit)

-- | Collect every row into memory. Check that the data source fits in memory first.
collectAllDataSourceRows ::
  (QueryDataSource -> IO (ListOf PageOrDataSource)) -> QueryDataSource -> Maybe AllRowsFilter -> IO (Vector PageOrDataSource)
collectAllDataSourceRows q base f =
  Vector.fromList . reverse <$> foldAllDataSourceRows q base f [] (\acc r -> pure (r : acc))
```

Implement `foldAllDataSourceRows` as two nested loops that mirror the JS algorithm in Context and Orientation.

The outer loop, `go seen windowStart acc`, runs one window and receives `(seen', acc', limitReached, lastCreated)`:

- If `not limitReached`, return `acc'`.
- If `lastCreated == Nothing || lastCreated == windowStart`, run `throwIO (CannotMakeProgress lastCreated)`.
- Otherwise, loop with `go seen' lastCreated acc'`.

The inner loop pages one window with `cursor`, starting at `Nothing`:

1. Send `base {filter = createdTimeLowerBound mFilter windowStart, sorts = Just [TimestampSort FilterCreatedTime Ascending], startCursor = cursor}`.
2. `foldM` over `results`, and for each row:
   - If `resultCreatedTime row` is `Just t`, set `lastCreated` to `Just t`.
   - If `resultId row` is `Just rid` and `rid` is in `seen`, skip the row.
   - Otherwise run `step acc row`, and insert `rid` into `seen` when the id is present. Rows without an id are always passed to `step`.
3. OR `limitReached` with `isIncomplete response`.
4. If `nextCursor response` is `Just c`, repeat with `Just c`. Otherwise, the window is done.

Define `isIncomplete :: ListOf a -> Bool` in this module against EP-2's actual type: `True` exactly when `requestStatus` is `Just` a status whose type is "incomplete". For example, if EP-2 defined `RequestStatus {type_ :: RequestStatusType, ...}` with a constructor `RequestIncomplete`, write `isIncomplete List {requestStatus = Just RequestStatus {type_ = RequestIncomplete}} = True; isIncomplete _ = False`. Adapt to the names you found in the Preconditions check.

Add a `milestone5Tests` group. The fake query function is built from a list of JSON response bodies, and records each request's JSON:

```haskell
fakeQuery :: [Aeson.Value] -> IO (QueryDataSource -> IO (ListOf PageOrDataSource), IO [Aeson.Value])
fakeQuery bodies = do
  queue <- newIORef bodies
  sent <- newIORef []
  let run req = do
        modifyIORef' sent (Aeson.toJSON req :)
        next <- atomicModifyIORef' queue (\case (b : bs) -> (bs, b); [] -> ([], Aeson.Null))
        case Aeson.fromJSON next of
          Aeson.Success l -> pure l
          Aeson.Error e -> assertFailure ("fake response did not decode: " <> e)
  pure (run, reverse <$> readIORef sent)

queryResponse :: [Aeson.Value] -> Maybe Text.Text -> Bool -> Aeson.Value
queryResponse rows cursor incomplete =
  Aeson.object $
    [ "object" Aeson..= ("list" :: Text.Text), "type" Aeson..= ("page_or_data_source" :: Text.Text),
      "page_or_data_source" Aeson..= Aeson.object [], "results" Aeson..= rows,
      "has_more" Aeson..= maybe False (const True) cursor, "next_cursor" Aeson..= cursor ]
      <> [ "request_status" Aeson..= Aeson.object ["type" Aeson..= ("incomplete" :: Text.Text), "incomplete_reason" Aeson..= ("query_result_limit_reached" :: Text.Text)] | incomplete ]
```

The cases:

- `"createdTimeLowerBound: first window returns caller filter"`. `createdTimeLowerBound (Just (AllRowsPropertyFilter "Status" (StatusCondition (StatusEquals "Done")))) Nothing` equals `Just (PropertyFilter "Status" ...)`.
- `"createdTimeLowerBound: no caller filter returns bound"`. With `Just t` for 2024-01-04T00:00:00Z, the encoded result is `{"timestamp":"created_time","created_time":{"on_or_after":"2024-01-04T00:00:00Z"}}`. `posixToISO8601` prints no milliseconds; build `t` by decoding the string with `Aeson.fromJSON` via a page fixture, or with `Data.Time.Clock.POSIX.utcTimeToPOSIXSeconds`.
- `"createdTimeLowerBound: and filter gets bound appended"`. `AllRowsAnd [a]` gives `And [a, bound]`.
- `"createdTimeLowerBound: property filter is wrapped in and"`. The result is `And [PropertyFilter ..., bound]`.
- `"iterateAllDataSourceRows: single complete window"`:
  - One response with `pageJson "r1" "2024-01-01T00:00:00.000Z"` and `pageJson "r2" "2024-01-02T00:00:00.000Z"`.
  - Visited ids are `["r1","r2"]`, and exactly one request was sent.
  - That request's `sorts` is `[{"timestamp":"created_time","direction":"ascending"}]`, and it has no `filter` and no `start_cursor` key.
- `"iterateAllDataSourceRows: advances past the limit and de-duplicates"`:
  - Responses: `[r1, r2]` with cursor `"c1"`; `[r3, r4]` incomplete; then `[r4, r5]` complete, with created times on 2024-01-01 through 2024-01-05.
  - Ids are `r1..r5` and three requests were sent.
  - The second request has `start_cursor` `"c1"`.
  - The third has no `start_cursor`, and its filter is the created_time bound `"2024-01-04T00:00:00Z"`.
- `"iterateAllDataSourceRows: combines caller filter with and"`:
  - Caller filter `AllRowsPropertyFilter "Status" (StatusCondition (StatusEquals "Done"))`.
  - Responses: `[r1]` incomplete, then `[r1, r2]`.
  - Ids are `["r1","r2"]`.
  - The first request's filter is `{"property":"Status","status":{"equals":"Done"}}`, and the second is `{"and":[that, bound 2024-01-01T00:00:00Z]}`.
- `"iterateAllDataSourceRows: advances on a data-source boundary row"`:
  - Responses: `[pageJson "r1" day1, dataSourceJson "ds-child" day2]` incomplete, then `[dataSourceJson "ds-child" day2, pageJson "r2" day3]`.
  - Ids are `["r1","ds-child","r2"]`, two requests were sent, and the second filter's bound is day 2.
- `"collectAllDataSourceRows: cannot make progress throws"`:
  - Two responses, each `[r1, r2]` with the same created time and incomplete.
  - `try @DataSourceRowsError (collectAllDataSourceRows ...)` returns `Left (CannotMakeProgress (Just t))`.
  - `show` of the exception is non-empty.
- `"collectAllDataSourceRows: collects across windows"`. Responses: `[r1]` incomplete, then `[r1, r2]`; the result ids are `["r1","r2"]`.

In every case call the helper with `_QueryDataSource` as the base request. Add `TypeApplications` usage only where needed (`GHC2024` enables it), and import `Data.IORef` and `Control.Exception (try)` in the test module.

Finally, add a short demonstration to `notion-client-example/DatabaseDemo.hs`, after the existing auto-pagination section. Call `collectAllDataSourceRows (queryDataSource methods dsId) _QueryDataSource Nothing` (with EP-1's extra argument if any) and print the number of rows, so the live check exercises the helper.

Acceptance: `cabal build all` succeeds, and `cabal test` shows the ten Milestone 5 cases `OK`.

### CHANGELOG

In `CHANGELOG.md`, make sure a `## Unreleased` heading exists directly under `# Changelog for notion-client`. Create it if absent; if another plan created it, reuse it. Add these entries under its subsections, creating any subsection that is missing.

Under `### Breaking Changes`:

- `queryDataSource` returns `ListOf PageOrDataSource`, and `search` returns `ListOf PageOrDataSource` (was `ListOf Value`). `SearchResult` is now a type alias, and `parseSearchResults` was removed.
- `SearchSort` and `SearchFilter` are now sum types (`SearchByLastEditedTime`/`SearchByRelevance`, `SearchObjectFilter`/`SearchInTrashFilter`).
- `CreateDatabase.title` is `Maybe`, `CreateDatabase` gains `databaseType`, and `InitialDataSource.properties` is `Maybe`.
- `QueryDataSource` gains `resultType`.
- Every `PropertySchema` constructor gains `schemaDescription`, `RelationSchema` gains `relationDatabaseId`, and `SelectOption` gains `description`. `DualProperty` fields are `Maybe`.
- `UpdateDataSource.properties` is `Maybe (Map Text PropertyUpdate)`.
- `PropertySchema` encoding omits an empty `id`, and omits `groups` for a status schema with no groups.
- `VerificationCondition` takes `VerificationState`, and `UniqueIdCondition` takes `Scientific`.
- `Filter`, `PropertyCondition` and `Sort` gain `UnknownFilter`, `UnknownCondition` and `UnknownSort`.
- `DatabaseObject` and `DataSourceObject` gain `databaseType`.
- The effectful `queryDataSource` and `search` result types changed accordingly.

Under `### New Features`:

- `DatabaseType`, `CreateDatabaseType`, `QueryResultType` and `_QueryDataSource`.
- `PartialPageObject`, `PartialDataSourceObject` and `PartialDatabaseObject`.
- `pageResults`, `dataSourceResults`, `resultId` and `resultCreatedTime`.
- The search relevance sort and `in_trash` filters.
- `LocationSchema`, `LastVisitedTimeSchema` and `UnknownSchema`.
- `PropertyUpdate`, `OptionUpdate` and `OptionTarget`.
- The filter constructors `SelectEqualsAny` and friends, `UniqueIdIsEmpty`/`UniqueIdIsNotEmpty`, `VerificationDoesNotEqual`, and `RelativeDate`/`relativeDate`.
- `FromJSON` for `Filter` and `Sort` (omit this entry if EP-4 already listed it).
- The new module `Notion.V1.DataSourceRows`, with `iterateAllDataSourceRows`, `collectAllDataSourceRows` and `foldAllDataSourceRows`.

Under `### Bug Fixes`:

- Data source queries on wiki databases no longer fail to decode.
- Search no longer silently drops partial results.
- Unknown property types no longer fail data source decoding.

Do not change the package version.


## Concrete Steps

All commands run from the repository root.

1. Verify the preconditions:

   ```bash
   grep -n "filter_properties" src/Notion/V1/DataSources.hs
   grep -n "OtherNumberFormat" src/Notion/V1/Properties.hs
   grep -n "requestStatus\|RequestStatus" src/Notion/V1/ListOf.hs
   ls docs/adr 2>/dev/null || echo "no docs/adr"
   ```

   Expected: the first three commands each print at least one line, and the last prints `no docs/adr`.

2. Establish a green baseline before editing:

   ```bash
   cabal build all
   cabal test
   ```

   Expected tail of the test output (the test count varies):

   ```text
   All 1xx tests passed (x.xxs)
   ```

3. Wire up `tasty/DataSourceSearchTests.hs` and implement Milestone 1. Then run:

   ```bash
   cabal build all 2>&1 | grep -E "^src|^tasty|^notion-client|rror" || true
   cabal test --test-options='-p "EP-5"'
   ```

   Expected, among the output:

   ```text
   EP-5 Data sources, databases, search, filters
     Milestone 1
       DatabaseObject decodes database_type:                     OK
       ...
       Query response decodes every result kind:                 OK
   ```

4. Commit Milestone 1:

   ```bash
   git add -A
   git commit -F - <<'EOF'
   feat(data-sources)!: type data source query results and database_type

   queryDataSource now returns ListOf PageOrDataSource so wiki data
   sources and partial objects decode. Adds DatabaseType, typed-database
   creation, optional CreateDatabase title, and result_type.

   MasterPlan: docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md
   ExecPlan: docs/plans/10-type-data-source-database-and-search-results-and-close-query-and-filter-gaps.md
   EOF
   ```

   If the pre-commit hook reformats files and aborts, run `git add -u` and repeat the commit.

5. Repeat the implement, test and commit cycle for Milestones 2–5, using the same `cabal test --test-options='-p "EP-5"'` filter and then a full `cabal test`. Suggested commit subjects:

   ```text
   feat(search)!: return typed search results and add relevance sort and in_trash filters
   feat(properties)!: add property descriptions, rename-only updates and option targeting by id
   feat(filter)!: add missing filter variants and FromJSON for Filter and Sort
   feat(data-sources): add iterateAllDataSourceRows for queries past the result limit
   ```

   Each commit ends with the same two trailers shown above.

6. After Milestone 5, update `CHANGELOG.md` and tick the EP-5 items in the MasterPlan's Progress section. Run the full validation below and commit with `docs(changelog): record EP-5 changes` plus the trailers.


## Validation and Acceptance

Automated checks, from the repository root:

```bash
cabal build all
cabal test
```

Acceptance:

- `cabal build all` compiles both `notion-client` and `notion-client-effectful` with no errors, and prints no `-Wmissing-fields` warnings.
- `cabal test` ends with `All N tests passed`.
- The `EP-5 Data sources, databases, search, filters` group lists the test names given in each milestone, all `OK`: ten in M1, five in M2, ten in M3, nine in M4 and ten in M5.

The tests are effective beyond compilation in these ways:

- The "every result kind" test fails on the current code, where decoding a partial data source into `PageObject` errors.
- The row-helper tests check the exact JSON bodies sent across windows.

Optional live check, when `NOTION_TOKEN` (and, for the database part, `NOTION_TEST_DATABASE_ID`) is set:

```bash
NOTION_TOKEN=secret_... NOTION_TEST_DATABASE_ID=... cabal run notion-client-example
```

Observe that:

- The "Search API" section prints one line per result naming its kind (for example `- page`, `- data_source`) and never an exception.
- The database section prints the data source query count, and a line such as `collectAllDataSourceRows returned 12 rows` whose number equals the `paginateAll` count for small data sources.
- A wiki data source, if you have one, lists `data_source` rows instead of failing.

A GHCi alternative:

```bash
cabal repl notion-client
```

```haskell
import Notion.V1
import Notion.V1.Search
import Notion.V1.ListOf
import qualified Data.Text as T
env <- getClientEnv "https://api.notion.com/v1"
m <- makeMethods env . T.pack <$> System.Environment.getEnv "NOTION_TOKEN"
r <- search m _SearchRequest { sort = Just SearchByRelevance, pageSize = Just 5 }
mapM_ (putStrLn . takeWhile (/= ' ') . show) (results r)
```

Expected: up to five lines such as `PageResult` or `DataSourceResult`.


## Idempotence and Recovery

Every step is an ordinary source edit and can be repeated safely. Builds and tests change no external state. The live example creates and trashes pages in the test database exactly as it does today; this plan adds only a read-only `collectAllDataSourceRows` call.

If a milestone leaves the build broken halfway, run `git stash` (or `git checkout -- <file>`) to return to the last green commit, then redo the milestone in smaller edits. Change the type first, then follow the compiler errors outward from `src/` to `notion-client-effectful/`, `tasty/` and `notion-client-example/`.

Missing record fields are the main silent hazard. Before each commit, run `cabal build all 2>&1 | grep -i "missing-fields\|Fields of .* not initialised"`. It must print nothing.

If EP-4 lands `FromJSON Filter` while Milestone 4 is in progress, rebase onto it and keep EP-4's instance shape. Re-add only the new constructors, and note this in Surprises & Discoveries. If EP-1 or EP-2 change `QueryDataSource` or `ListOf` again after this plan starts, rebase. Only `_QueryDataSource`, the `QueryDataSource` literals and `isIncomplete` should need edits.


## Interfaces and Dependencies

No new package dependencies are added. The code uses `aeson` for decoding and encoding (`Data.Aeson`, `Data.Aeson.KeyMap`, `Data.Aeson.Key`, `Data.Aeson.Types`), `containers` (`Data.Set` for de-duplication, `Data.Map`), `vector`, `scientific`, `text` and `time` through `Notion.Prelude`. All are already in the `library` stanza of `notion-client.cabal`. The tests use `tasty`, `tasty-hunit`, `aeson`, `containers`, `text` and `vector`, which are already in the `test-suite tasty` stanza.

The following must exist at the end of each milestone.

After Milestone 1:

- In `Notion.V1.Databases`:

  ```haskell
  data DatabaseType = TasksDatabase | ProjectsDatabase | SprintsDatabase | DocsDatabase | WikiDatabase | MeetingsDatabase | MeetingNotesDatabase | SkillsDatabase | GithubPrsDatabase | UnknownDatabaseType Text
  data CreateDatabaseType = CreateTasksDatabase | CreateProjectsDatabase | CreateSkillsDatabase
  newtype PartialDatabaseObject = PartialDatabaseObject {id :: DatabaseID}
  ```

  `DatabaseObject` has the field `databaseType :: Maybe DatabaseType`. `CreateDatabase` has `title :: Maybe (Vector RichText)` and `databaseType :: Maybe CreateDatabaseType`. `InitialDataSource` has `properties :: Maybe (Map Text PropertySchema)`.
- In `Notion.V1.Pages`: `newtype PartialPageObject = PartialPageObject {id :: PageID}`, unless it already exists.
- In `Notion.V1.DataSources`:

  ```haskell
  data PartialDataSourceObject = PartialDataSourceObject {id :: DataSourceID, properties :: Map Text PropertySchema}
  data PageOrDataSource = PageResult PageObject | PartialPageResult PartialPageObject | DataSourceResult DataSourceObject | PartialDataSourceResult PartialDataSourceObject | UnknownResult Value
  data QueryResultType = ResultTypePage | ResultTypeDataSource
  _QueryDataSource :: QueryDataSource
  pageResults :: Vector PageOrDataSource -> Vector PageObject
  dataSourceResults :: Vector PageOrDataSource -> Vector DataSourceObject
  resultId :: PageOrDataSource -> Maybe Text
  resultCreatedTime :: PageOrDataSource -> Maybe POSIXTime
  ```

  `DataSourceObject` has `databaseType :: Maybe DatabaseType`, and `QueryDataSource` has `resultType :: Maybe QueryResultType`.
- `Notion.V1.Methods.queryDataSource` and the effectful `queryDataSource` return `IO (ListOf PageOrDataSource)` and `Eff es (ListOf PageOrDataSource)`.

After Milestone 2:

- In `Notion.V1.Search`:

  ```haskell
  data SearchSort = SearchByLastEditedTime SearchSortDirection | SearchByRelevance
  data SearchFilter = SearchObjectFilter SearchObjectType (Maybe Bool) | SearchInTrashFilter Bool
  type SearchResult = PageOrDataSource
  pageFilter, dataSourceFilter :: SearchFilter
  ```

- `Notion.V1.Methods.search :: SearchRequest -> IO (ListOf PageOrDataSource)`, and the effectful `search` matches.

After Milestone 3:

- In `Notion.V1.Properties`:
  - Every `PropertySchema` constructor has `schemaDescription :: Maybe Text`.
  - `RelationSchema` has `relationDatabaseId :: Maybe UUID`.
  - New constructors: `LocationSchema`, `LastVisitedTimeSchema` and `UnknownSchema {..., schemaType :: Text, schemaConfig :: Value}`.
  - `SelectOption` has `description :: Maybe Text`.
  - `DualProperty {syncedPropertyId :: Maybe Text, syncedPropertyName :: Maybe Text}`.
  - The update types:

    ```haskell
    data OptionTarget = OptionNamed Text | OptionWithId Text (Maybe Text)
    data OptionUpdate = OptionUpdate {target :: OptionTarget, color :: Maybe SelectColor, description :: Maybe Text}
    data PropertyUpdate = RemoveProperty | RenameProperty Text | SetPropertySchema PropertySchema
      | UpdateSelectOptions {newName :: Maybe Text, optionUpdates :: Vector OptionUpdate}
      | UpdateMultiSelectOptions {newName :: Maybe Text, optionUpdates :: Vector OptionUpdate}
      | UpdateStatusOptions {newName :: Maybe Text, optionUpdates :: Vector OptionUpdate}
    ```

- `Notion.V1.DataSources.UpdateDataSource` has `properties :: Maybe (Map Text PropertyUpdate)`.

After Milestone 4, in `Notion.V1.Filter`:

- The new types and renderer:

  ```haskell
  data VerificationState = VerificationVerified | VerificationExpired | VerificationNone | UnknownVerificationState Text
  data VerificationCondition = VerificationStatus VerificationState | VerificationDoesNotEqual VerificationState
  data RelativeDate = Today | Tomorrow | Yesterday | OneWeekAgo | OneWeekFromNow | OneMonthAgo | OneMonthFromNow
  relativeDate :: RelativeDate -> Text
  ```

- New constructors on existing types:
  - `SelectEqualsAny`, `SelectDoesNotEqualAny`, `StatusEqualsAny`, `StatusDoesNotEqualAny`, `MultiSelectContainsAny` and `MultiSelectDoesNotContainAny`, each taking `NonEmpty Text`.
  - `UniqueIdCondition` payloads are `Scientific`, plus `UniqueIdIsEmpty` and `UniqueIdIsNotEmpty`.
  - `UnknownCondition Text Value` on `PropertyCondition`, `UnknownFilter Value` on `Filter` and `UnknownSort Value` on `Sort`.
- Instances: `FromJSON Filter`, `FromJSON Sort`, `FromJSON SortDirection`, and `ToJSON`/`FromJSON VerificationState`.

After Milestone 5, in `Notion.V1.DataSourceRows` (exposed module):

```haskell
data AllRowsFilter = AllRowsPropertyFilter Text PropertyCondition | AllRowsTimestampFilter TimestampType DateCondition | AllRowsAnd [Filter]
data DataSourceRowsError = CannotMakeProgress (Maybe POSIXTime)   -- instance Exception
createdTimeLowerBound :: Maybe AllRowsFilter -> Maybe POSIXTime -> Maybe Filter
foldAllDataSourceRows :: (QueryDataSource -> IO (ListOf PageOrDataSource)) -> QueryDataSource -> Maybe AllRowsFilter -> acc -> (acc -> PageOrDataSource -> IO acc) -> IO acc
iterateAllDataSourceRows :: (QueryDataSource -> IO (ListOf PageOrDataSource)) -> QueryDataSource -> Maybe AllRowsFilter -> (PageOrDataSource -> IO ()) -> IO ()
collectAllDataSourceRows :: (QueryDataSource -> IO (ListOf PageOrDataSource)) -> QueryDataSource -> Maybe AllRowsFilter -> IO (Vector PageOrDataSource)
```

What this plan consumes from other plans:

- EP-1 (`docs/plans/6-fix-wire-format-decoding-and-encoding-bugs-found-against-the-official-sdk.md`): the `filter_properties` query-parameter routing of `queryDataSource`, and `OtherNumberFormat`.
- EP-2 (`docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md`): `ListOf.requestStatus :: Maybe RequestStatus`.
- EP-4 (`docs/plans/9-add-view-queries-and-typed-view-configuration.md`), optionally: `FromJSON Filter`/`Sort`, and possibly `PartialPageObject`.

What other plans consume from this one: EP-4 may reuse `FromJSON Filter`/`Sort`, `PartialPageObject` and `PageOrDataSource`.
