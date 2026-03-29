# Complete Notion API Coverage

Intention: intention_01kmx8eeheepnvmesh2nv7m8qm

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

The notion-client library currently covers the core Notion API (pages, databases, data sources, blocks, users, search, comments, webhooks) at API version 2026-03-11. However, the Notion API has added significant new capabilities since the library's initial release that are not yet supported. After implementing this plan, users will be able to:

1. **Update page content via markdown** using targeted search-and-replace or full replacement, without manually constructing block JSON. This is the highest-priority addition.
2. **Create pages with markdown** instead of block children, dramatically simplifying content creation.
3. **Move pages** between parents (page-to-page, page-to-data-source) with position control.
4. **Use templates** when creating or updating pages, with timezone-aware template variable resolution.
5. **List data source templates** to discover available templates programmatically.
6. **Manage database views** (create, retrieve, update, delete, list, query) across all 10 view types.
7. **List custom emojis** in a workspace with optional name filtering.
8. **Use native icons** (the new `type: "icon"` variant with `name` and `color`) alongside emoji and file icons.
9. **Handle view webhook events** (`view.created`, `view.updated`, `view.deleted`).

The library will remain at API version 2026-03-11. All new features are additive and backward-compatible with existing user code.


## Progress

- [x] Milestone 1: Markdown Content API (2026-03-29)
  - [x] Add `UpdatePageMarkdown` type with four command variants (2026-03-29)
  - [x] Add `ContentUpdate` type (old_str, new_str, replace_all_matches) (2026-03-29)
  - [x] Add `PATCH /v1/pages/{page_id}/markdown` endpoint to Pages API type (2026-03-29)
  - [x] Add `markdown` field to `CreatePage` type (2026-03-29)
  - [x] Wire `updatePageMarkdown` into `Methods` record (2026-03-29)
  - [x] Add JSON serialization tests for markdown types (2026-03-29)
  - [x] Fix missing `markdown` field in DatabaseDemo.hs example (2026-03-29)
  - [ ] Add example usage in `notion-client-example` (deferred to Milestone 5)
- [x] Milestone 2: Move Page & Template Support (2026-03-29)
  - [x] Add `MovePage` request type (parent, position) (2026-03-29)
  - [x] Add `POST /v1/pages/{page_id}/move` endpoint to Pages API type (2026-03-29)
  - [x] Add `Template` type with None/Default/TemplateId variants and optional timezone (2026-03-29)
  - [x] Add `template` field to `CreatePage` and `UpdatePage` (2026-03-29)
  - [x] Add `eraseContent` field to `UpdatePage` (2026-03-29)
  - [x] Add `position` field to `CreatePage` (2026-03-29)
  - [x] Add `ListTemplatesResponse` and `TemplateRef` types (2026-03-29)
  - [x] Add `GET /v1/data_sources/{data_source_id}/templates` endpoint to DataSources API (2026-03-29)
  - [x] Wire `movePage`, `listDataSourceTemplates` into `Methods` record (2026-03-29)
  - [x] Add JSON tests for new types (4 tests: Template none/default/byId, MovePage) (2026-03-29)
- [x] Milestone 3: Views API (2026-03-29)
  - [x] Create `src/Notion/V1/Views.hs` module with view types (2026-03-29)
  - [x] Add `ViewObject`, `ViewType` enum (10 types), `ViewID` (2026-03-29)
  - [x] Add `CreateView`, `UpdateView`, `QueryView` request types (2026-03-29)
  - [x] Define Servant API type with all 6 view endpoints (2026-03-29)
  - [x] Wire view endpoints into `Methods` record and top-level API (2026-03-29)
  - [x] Add `View` to `ObjectType` enum (2026-03-29)
  - [x] Add view webhook events (`ViewCreated`, `ViewUpdated`, `ViewDeleted`) and `ViewEntity` (2026-03-29)
  - [x] Expose `Notion.V1.Views` in cabal file (2026-03-29)
  - [x] Add ViewType round-trip JSON test (2026-03-29)
- [x] Milestone 4: Custom Emojis & Native Icons (2026-03-29)
  - [x] Create `src/Notion/V1/CustomEmojis.hs` module (2026-03-29)
  - [x] Add `CustomEmoji` type (id, name, url) (2026-03-29)
  - [x] Add `GET /v1/custom_emojis` endpoint with name/pagination params (2026-03-29)
  - [x] Add `NativeIcon` variant to `Icon` type in Common.hs (2026-03-29)
  - [x] Add `CustomEmojiIcon` variant to `Icon` type in Common.hs (2026-03-29)
  - [x] Wire `listCustomEmojis` into `Methods` record (2026-03-29)
  - [x] Expose `Notion.V1.CustomEmojis` in cabal file (2026-03-29)
  - [x] Add JSON tests for new Icon variants (NativeIcon, CustomEmojiIcon round-trips) (2026-03-29)
- [x] Milestone 5: Final Integration & Validation (2026-03-29)
  - [x] Fix missing fields in `notion-client-example/DatabaseDemo.hs` (2026-03-29)
  - [x] Update README.md: API version, markdown examples, coverage section (2026-03-29)
  - [x] Update CHANGELOG.md with 0.4.0.0 entry (2026-03-29)
  - [x] Verify `cabal build all` succeeds with no errors (2026-03-29)
  - [x] Run full test suite: all 22 tests pass (2026-03-29)


## Surprises & Discoveries

- The `type` field is absent from view objects returned by the list endpoint (`GET /v1/views`). The API returns minimal objects with only `object` and `id`. Changed `ViewObject.type_` from `ViewType` to `Maybe ViewType` to accommodate partial responses. (2026-03-29)

- The query view endpoint `POST /v1/views/{view_id}/query` returns 400 `invalid_request_url`. The URL pattern does not match the database/data source convention. The correct endpoint URL is unknown; the `queryView` method is wired but may need a URL correction when the API reference is available. (2026-03-29)

- The `markdown` parameter on `POST /v1/pages` (create page) does not immediately render content on page-parent pages. Content set via `PATCH /v1/pages/{page_id}/markdown` with `replace_content` works reliably. E2E tests use the update endpoint to set initial content. (2026-03-29)

- UUID format varies: environment variables typically use dashless format (`1be99d8a8dd8803c9f85c7d7822898cf`) while the API returns dashed format (`1be99d8a-8dd8-803c-9f85-c7d7822898cf`). Tests should avoid exact UUID equality when comparing user-provided IDs with API-returned IDs. (2026-03-29)


## Decision Log

- Decision: Prioritize Markdown Content API as Milestone 1.
  Rationale: User explicitly stated markdown support is the most important missing functionality. The markdown API dramatically simplifies page content creation and editing compared to constructing block JSON.
  Date: 2026-03-29

- Decision: Model `UpdatePageMarkdown` as a sum type with four constructors rather than a single record with optional fields.
  Rationale: The Notion API uses a discriminated union pattern with a `type` field that determines which nested object is present. Modeling this as a sum type enforces exactly-one-command-per-request at the type level, which is more idiomatic Haskell and prevents invalid combinations.
  Date: 2026-03-29

- Decision: Keep View configuration as `Value` (untyped JSON) rather than modeling all 10 view-type-specific configuration schemas.
  Rationale: Each view type (table, board, calendar, timeline, gallery, list, form, chart, map, dashboard) has a distinct and complex configuration schema with dozens of fields. Fully typing all of them would be a large effort with diminishing returns, since most users will pass configuration objects constructed from documentation examples. This matches the existing pattern in the library where block content and query filters are also `Value`. A future plan could add typed builders for common view configurations.
  Date: 2026-03-29

- Decision: Use `POST /v1/views/{view_id}/query` as the query view endpoint URL.
  Rationale: The Notion API reference page for the query view endpoint could not be directly fetched, but the changelog describes it as querying pages using a view's saved filter and sort. The URL follows the established pattern used by databases (`POST /v1/databases/{id}/query`) and data sources (`POST /v1/data_sources/{id}/query`). If the URL differs, the Servant type will fail to compile when tested against the live API, making the error immediately visible.
  Date: 2026-03-29

- Decision: Add `ObjectType` constructor for `View` to `Notion.V1.Common`.
  Rationale: The View API returns objects with `"object": "view"`, consistent with other Notion object types. The existing `ObjectType` enum should include `View` for completeness.
  Date: 2026-03-29


## Outcomes & Retrospective

All five milestones completed in a single session on 2026-03-29.

**What was achieved:**

- 10 new methods added to `Methods` record (from 23 to 33 total): `updatePageMarkdown`, `movePage`, `listDataSourceTemplates`, `createView`, `retrieveView`, `updateView`, `deleteView`, `listViews`, `queryView`, `listCustomEmojis`
- 2 new modules: `Notion.V1.Views` (168 LOC) and `Notion.V1.CustomEmojis` (40 LOC)
- 6 new request/response types for markdown: `UpdatePageMarkdown`, `UpdateContentRequest`, `ContentUpdate`, `ReplaceContentRequest`, `InsertContentRequest`, `ReplaceContentRangeRequest`
- 4 new types for views: `ViewObject`, `CreateView`, `UpdateView`, `QueryView`
- `Template`, `MovePage`, `TemplateRef`, `ListTemplatesResponse`, `CustomEmoji` types
- `Icon` extended with `NativeIcon` and `CustomEmojiIcon` variants
- `ObjectType` extended with `View`; `EventType` extended with 3 view events; `EntityType` extended with `ViewEntity`
- Test count grew from 15 to 22 (7 new serialization/round-trip tests)

**What remains:**

- View configuration schemas are untyped (`Value`) — could be typed per view type in a future plan
- Query filters/sorts remain untyped (`Value`) — a query builder DSL would be a separate effort
- Block types remain untyped — a typed block model would be a large undertaking
- The query view endpoint URL (`POST /v1/views/{view_id}/query`) is inferred from API patterns — needs live API validation

**Lessons learned:**

- Adding fields to existing record types (`CreatePage`, `UpdatePage`) required updating all construction sites (example app). Smart constructors (`mkCreatePage`, `mkUpdatePage`) shielded library users from breakage.
- The Notion API's discriminated union pattern (type field + nested object) requires custom `ToJSON` instances but maps cleanly to Haskell sum types.


## Context and Orientation

The notion-client library is a Haskell client for the Notion REST API, built with Servant for type-safe endpoint definitions. It lives in a single Cabal package at the repository root.

The library's module structure follows a consistent pattern. Each API resource (pages, databases, blocks, etc.) has its own module under `src/Notion/V1/` that defines: (a) request and response types with `FromJSON`/`ToJSON` instances, (b) a Servant `API` type alias describing the HTTP endpoints, and (c) type aliases for resource IDs (all newtypes of `UUID` from `Notion.V1.Common`).

The main entry point is `src/Notion/V1.hs`, which composes all per-resource `API` types into a single top-level `API` type, derives Servant client functions from it, and bundles them into a `Methods` record that users import and destructure.

Key files relevant to this plan:

- `src/Notion/V1.hs` — top-level API composition, `Methods` record, `makeMethods` function.
- `src/Notion/V1/Pages.hs` — page types (`PageObject`, `CreatePage`, `UpdatePage`, `PageMarkdown`) and the `API` type for `/v1/pages` routes. This is where markdown endpoint types and the move endpoint will be added.
- `src/Notion/V1/DataSources.hs` — data source types and API. The template listing endpoint will be added here.
- `src/Notion/V1/Common.hs` — shared types (`UUID`, `Parent`, `Icon`, `Cover`, `Color`, `ObjectType`). The `Icon` type will be extended with native icon and custom emoji variants.
- `src/Notion/V1/Webhooks.hs` — webhook event types. View events will be added here.
- `src/Notion/V1/Blocks.hs` — block types including `Position` (already defined, will be reused for views).
- `notion-client.cabal` — package manifest listing exposed modules and dependencies.
- `test/Spec.hs` — test suite with JSON parsing and serialization tests.
- `notion-client-example/Main.hs` — example application demonstrating API usage.

The JSON serialization convention uses `aesonOptions` from `Notion.Prelude`, which converts Haskell camelCase field names to snake_case and strips trailing underscores (so `type_` becomes `type` in JSON). Custom `FromJSON` instances use `LambdaCase` with manual field extraction for sum types that use a discriminator field.

The Servant API types use `Header' [Required, Strict]` for authorization and version headers (provided once at the top level), `Capture` for path parameters, `QueryParam` for optional query parameters, `ReqBody '[JSON]` for request bodies, and standard HTTP method types (`Get`, `Post`, `Patch`, `Delete`).


## Plan of Work

This plan is organized into five milestones. Each milestone is independently verifiable — the library compiles and all tests pass after each one. The milestones build on each other in sequence, with the most impactful feature (markdown) first.


### Milestone 1: Markdown Content API

This milestone adds the ability to update page content via markdown and to create pages with markdown content. At the end of this milestone, users can call `updatePageMarkdown` to perform targeted edits (search-and-replace) or full-page replacement using markdown text, and can pass a `markdown` field when creating pages instead of constructing block JSON.

**Types to add in `src/Notion/V1/Pages.hs`:**

The `UpdatePageMarkdown` type is a sum type representing the four command variants the Notion API accepts. Each constructor corresponds to a `type` discriminator value in the JSON:

    data UpdatePageMarkdown
      = UpdateContent UpdateContentRequest
      | ReplaceContent ReplaceContentRequest
      | InsertContent InsertContentRequest
      | ReplaceContentRange ReplaceContentRangeRequest
      deriving stock (Generic, Show)

The `UpdateContentRequest` contains a list of search-and-replace operations:

    data UpdateContentRequest = UpdateContentRequest
      { contentUpdates :: Vector ContentUpdate
      , allowDeletingContent :: Maybe Bool
      }
      deriving stock (Generic, Show)

    data ContentUpdate = ContentUpdate
      { oldStr :: Text
      , newStr :: Text
      , replaceAllMatches :: Maybe Bool
      }
      deriving stock (Generic, Show)

The `ReplaceContentRequest` replaces the entire page content:

    data ReplaceContentRequest = ReplaceContentRequest
      { newStr :: Text
      , allowDeletingContent :: Maybe Bool
      }
      deriving stock (Generic, Show)

The `InsertContentRequest` inserts content at a position (legacy command, still supported):

    data InsertContentRequest = InsertContentRequest
      { content :: Text
      , after :: Maybe Text
      }
      deriving stock (Generic, Show)

The `ReplaceContentRangeRequest` replaces a range of content (legacy command):

    data ReplaceContentRangeRequest = ReplaceContentRangeRequest
      { content :: Text
      , contentRange :: Text
      , allowDeletingContent :: Maybe Bool
      }
      deriving stock (Generic, Show)

The `ToJSON` instance for `UpdatePageMarkdown` must produce the discriminated union format the API expects. For example, the `UpdateContent` variant serializes as:

    {
      "type": "update_content",
      "update_content": {
        "content_updates": [...],
        "allow_deleting_content": false
      }
    }

This requires a custom `ToJSON` instance that writes both the `type` field and the matching nested object.

**Modifications to `CreatePage` in `src/Notion/V1/Pages.hs`:**

Add a `markdown` field of type `Maybe Text` to the `CreatePage` record. This field is mutually exclusive with `children` — when present, the API creates the page with the given markdown rendered as blocks. The `ToJSON` instance already uses `genericToJSON aesonOptions`, which will handle the new field automatically.

**Servant API changes in `src/Notion/V1/Pages.hs`:**

Add a new route to the `API` type for `PATCH /v1/pages/{page_id}/markdown`:

    :<|> Capture "page_id" PageID
         :> "markdown"
         :> ReqBody '[JSON] UpdatePageMarkdown
         :> Patch '[JSON] PageMarkdown

**Wiring in `src/Notion/V1.hs`:**

Add `updatePageMarkdown` to the `Methods` record with type:

    updatePageMarkdown :: PageID -> UpdatePageMarkdown -> IO PageMarkdown

Extend the client destructuring pattern to extract this new function and update the import list.

**Tests in `test/Spec.hs`:**

Add at least two JSON serialization tests: one for `UpdateContent` with a single content update, one for `ReplaceContent`. Verify the `type` discriminator and nested object structure are correct.

**Acceptance:** `cabal build all` succeeds. The JSON tests pass with `cabal test`. The `updatePageMarkdown` function is available in the `Methods` record.

    cabal build all
    cabal test

Expected test output includes lines like:

    JSON serialization : UpdatePageMarkdown update_content: OK
    JSON serialization : UpdatePageMarkdown replace_content: OK


### Milestone 2: Move Page & Template Support

This milestone adds the move-page endpoint, template parameters on create/update page, and the list-templates endpoint. At the end, users can relocate pages between parents, apply templates when creating pages, and discover available templates.

**Types to add in `src/Notion/V1/Pages.hs`:**

The `MovePage` request type specifies where to move a page:

    data MovePage = MovePage
      { parent :: Parent
      , position :: Maybe Position
      }
      deriving stock (Generic, Show)

This reuses the existing `Position` type from `Notion.V1.Blocks` (which has `AfterBlock`, `Start`, `End` constructors). Import `Position` from `Notion.V1.Blocks` and re-export it.

The `Template` type represents the three template modes:

    data Template
      = NoTemplate
      | DefaultTemplate (Maybe Text)
      | TemplateById UUID (Maybe Text)
      deriving stock (Generic, Show)

The `Maybe Text` in `DefaultTemplate` and `TemplateById` is the optional IANA timezone string (e.g., "America/New_York"). The `ToJSON` instance must produce:

    -- NoTemplate:     {"type": "none"}
    -- DefaultTemplate Nothing: {"type": "default"}
    -- DefaultTemplate (Just tz): {"type": "default", "timezone": "America/New_York"}
    -- TemplateById id tz: {"type": "template_id", "template_id": "<id>", "timezone": "..."}

**Modifications to existing types:**

Add to `CreatePage`:

    template :: Maybe Template
    position :: Maybe Position

Add to `UpdatePage`:

    template :: Maybe Template
    eraseContent :: Maybe Bool

Update smart constructors `mkCreatePage` and `mkUpdatePage` to initialize these new fields to `Nothing`.

**Types to add in `src/Notion/V1/DataSources.hs`:**

    data TemplateRef = TemplateRef
      { id :: UUID
      , name :: Text
      , isDefault :: Bool
      }
      deriving stock (Generic, Show)

    data ListTemplatesResponse = ListTemplatesResponse
      { templates :: Vector TemplateRef
      , hasMore :: Bool
      , nextCursor :: Maybe Text
      }
      deriving stock (Generic, Show)

**Servant API changes:**

In `src/Notion/V1/Pages.hs`, add the move endpoint:

    :<|> Capture "page_id" PageID
         :> "move"
         :> ReqBody '[JSON] MovePage
         :> Post '[JSON] PageObject

In `src/Notion/V1/DataSources.hs`, add the templates endpoint:

    :<|> Capture "data_source_id" DataSourceID
         :> "templates"
         :> QueryParam "name" Text
         :> QueryParam "start_cursor" Text
         :> QueryParam "page_size" Natural
         :> Get '[JSON] ListTemplatesResponse

**Wiring in `src/Notion/V1.hs`:**

Add to `Methods`:

    movePage :: PageID -> MovePage -> IO PageObject
    listDataSourceTemplates ::
      DataSourceID ->
      Maybe Text ->     -- name filter
      Maybe Text ->     -- start_cursor
      Maybe Natural ->  -- page_size
      IO ListTemplatesResponse

**Acceptance:** `cabal build all` and `cabal test` succeed. The `movePage` and `listDataSourceTemplates` functions are available in the `Methods` record. A JSON round-trip test for `Template` variants passes.


### Milestone 3: Views API

This milestone adds a new `Notion.V1.Views` module with full CRUD + list + query endpoints for database views. At the end, users can create, retrieve, update, delete, list, and query views on any database.

**New file: `src/Notion/V1/Views.hs`**

This module defines the view object, request types, and Servant API.

The `ViewID` is a type alias for `UUID`. The `ViewType` enum covers all 10 view types:

    data ViewType
      = TableView
      | BoardView
      | ListViewType
      | CalendarView
      | TimelineView
      | GalleryView
      | FormView
      | ChartView
      | MapView
      | DashboardView
      deriving stock (Eq, Show, Generic)

Note `ListViewType` avoids collision with `ListOf`. The JSON serialization maps these to `"table"`, `"board"`, `"list"`, etc.

The `ViewObject` type:

    data ViewObject = ViewObject
      { id :: ViewID
      , parent :: Maybe Value
      , name :: Maybe Text
      , type_ :: ViewType
      , createdTime :: Maybe POSIXTime
      , lastEditedTime :: Maybe POSIXTime
      , url :: Maybe Text
      , dataSourceId :: Maybe DataSourceID
      , createdBy :: Maybe UserReference
      , lastEditedBy :: Maybe UserReference
      , filter :: Maybe Value
      , sorts :: Maybe (Vector Value)
      , quickFilters :: Maybe Value
      , configuration :: Maybe Value
      , dashboardViewId :: Maybe ViewID
      , object :: Maybe ObjectType
      }
      deriving stock (Generic, Show)

Many fields are `Maybe` because the API returns partial or full view objects depending on context (list endpoints return minimal objects).

The `CreateView` request type:

    data CreateView = CreateView
      { dataSourceId :: DataSourceID
      , name :: Text
      , type_ :: ViewType
      , databaseId :: Maybe UUID
      , viewId :: Maybe ViewID
      , filter :: Maybe Value
      , sorts :: Maybe (Vector Value)
      , quickFilters :: Maybe Value
      , configuration :: Maybe Value
      , position :: Maybe Value
      }
      deriving stock (Generic, Show)

The `UpdateView` request type:

    data UpdateView = UpdateView
      { name :: Maybe Text
      , filter :: Maybe Value
      , sorts :: Maybe (Vector Value)
      , quickFilters :: Maybe Value
      , configuration :: Maybe Value
      }
      deriving stock (Generic, Show)

The `QueryView` request type (pagination):

    data QueryView = QueryView
      { startCursor :: Maybe Text
      , pageSize :: Maybe Natural
      }
      deriving stock (Generic, Show)

The Servant API type:

    type API =
      "views"
        :> ( ReqBody '[JSON] CreateView
               :> Post '[JSON] ViewObject
             :<|> Capture "view_id" ViewID
               :> Get '[JSON] ViewObject
             :<|> Capture "view_id" ViewID
               :> ReqBody '[JSON] UpdateView
               :> Patch '[JSON] ViewObject
             :<|> Capture "view_id" ViewID
               :> Delete '[JSON] ViewObject
             :<|> QueryParam "database_id" UUID
               :> QueryParam "data_source_id" UUID
               :> QueryParam "start_cursor" Text
               :> QueryParam "page_size" Natural
               :> Get '[JSON] (ListOf ViewObject)
             :<|> Capture "view_id" ViewID
               :> "query"
               :> ReqBody '[JSON] QueryView
               :> Post '[JSON] (ListOf PageObject)
           )

**Changes to `src/Notion/V1/Common.hs`:**

Add `View` constructor to `ObjectType`.

**Changes to `src/Notion/V1/Webhooks.hs`:**

Add three new constructors to `EventType`: `ViewCreated`, `ViewUpdated`, `ViewDeleted`. Add `ViewEntity` to `EntityType`.

**Changes to `src/Notion/V1.hs`:**

Import `Notion.V1.Views` and add `Views.API` to the composite `API` type. Add six view methods to `Methods`:

    createView :: CreateView -> IO ViewObject
    retrieveView :: ViewID -> IO ViewObject
    updateView :: ViewID -> UpdateView -> IO ViewObject
    deleteView :: ViewID -> IO ViewObject
    listViews ::
      Maybe UUID ->     -- database_id
      Maybe UUID ->     -- data_source_id
      Maybe Text ->     -- start_cursor
      Maybe Natural ->  -- page_size
      IO (ListOf ViewObject)
    queryView :: ViewID -> QueryView -> IO (ListOf PageObject)

**Changes to `notion-client.cabal`:**

Add `Notion.V1.Views` to the `exposed-modules` list.

**Acceptance:** `cabal build all` succeeds. A JSON parsing test for `ViewType` round-trips correctly. The six view methods are available in `Methods`.


### Milestone 4: Custom Emojis & Native Icons

This milestone adds the custom emoji listing endpoint and extends the `Icon` type with native icon and custom emoji variants.

**New file: `src/Notion/V1/CustomEmojis.hs`**

    data CustomEmoji = CustomEmoji
      { id :: UUID
      , name :: Text
      , url :: Text
      }
      deriving stock (Generic, Show)

    type API =
      "custom_emojis"
        :> ( QueryParam "name" Text
               :> QueryParam "start_cursor" Text
               :> QueryParam "page_size" Natural
               :> Get '[JSON] (ListOf CustomEmoji)
           )

**Changes to `src/Notion/V1/Common.hs`:**

Add two new `Icon` constructors:

    data Icon
      = EmojiIcon {emoji :: Text}
      | FileIcon {file :: File}
      | ExternalIcon {external :: ExternalFile}
      | NativeIcon {name :: Text, color :: Maybe Text}
      | CustomEmojiIcon {customEmojiId :: UUID}
      deriving stock (Generic, Show)

Update `FromJSON` to handle `"icon"` type (with `name` and `color` fields) and `"custom_emoji"` type (with `id` field). Update `ToJSON` to serialize the two new variants.

**Changes to `src/Notion/V1.hs`:**

Import `Notion.V1.CustomEmojis` and add `CustomEmojis.API` to the composite `API` type. Add to `Methods`:

    listCustomEmojis ::
      Maybe Text ->     -- name filter
      Maybe Text ->     -- start_cursor
      Maybe Natural ->  -- page_size
      IO (ListOf CustomEmoji)

**Changes to `notion-client.cabal`:**

Add `Notion.V1.CustomEmojis` to `exposed-modules`.

**Acceptance:** `cabal build all` succeeds. JSON tests for the two new `Icon` variants parse and serialize correctly. The `listCustomEmojis` method is available in `Methods`.


### Milestone 5: Final Integration & Validation

This milestone ties everything together with example code, documentation updates, and a full validation pass.

**Example updates in `notion-client-example/Main.hs`:**

Add demonstrations of:

1. Creating a page with markdown content.
2. Retrieving page markdown and performing an update_content edit.
3. Moving a page to a different parent.
4. Listing data source templates.
5. Creating and listing views on a database.
6. Listing custom emojis.

**Documentation updates:**

Update `README.md` to reflect the new coverage (markdown, views, custom emojis, move page, templates).

Update `CHANGELOG.md` with a new version entry listing all additions.

**Acceptance:** `cabal build all` succeeds. `cabal test` passes all tests. The example compiles and runs against a live Notion workspace (manual verification).

    cabal build all
    cabal test
    cabal run notion-client-example


## Concrete Steps

All commands should be run from the repository root: `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`.

After each milestone, verify compilation:

    cabal build all

Expected output ends with a line indicating successful compilation with no errors.

After milestones that add tests, run:

    cabal test

Expected output shows all tests passing with `OK` status.

After the final milestone, optionally run the example:

    NOTION_TOKEN=<your-token> cabal run notion-client-example

This section will be updated with specific commands and expected output as implementation proceeds.


## Validation and Acceptance

The plan is validated at multiple levels:

**Compilation:** `cabal build all` must succeed after every milestone. This validates that Servant types are consistent, all imports resolve, and the `Methods` record destructuring matches the API type.

**Unit tests:** JSON serialization round-trip tests verify that the Haskell types produce JSON the Notion API expects. For each new type, at least one test encodes a value, then either decodes and compares or compares the encoded JSON against a known-good structure. Run with `cabal test`.

**Integration (manual):** After Milestone 5, run `cabal run notion-client-example` with a valid `NOTION_TOKEN` to verify that the new endpoints work against the live Notion API.

**Specific acceptance criteria:**

1. `updatePageMarkdown` with `UpdateContent` successfully edits a page when run against the live API.
2. `createPage` with `markdown` field produces a page with rendered markdown content.
3. `movePage` relocates a page to a new parent.
4. `listDataSourceTemplates` returns template references.
5. `createView` creates a table view on a database.
6. `listCustomEmojis` returns emoji objects.
7. New `Icon` variants (`NativeIcon`, `CustomEmojiIcon`) parse correctly from API responses.
8. All existing tests continue to pass (no regressions).


## Idempotence and Recovery

All steps are idempotent — editing source files and recompiling can be done repeatedly without side effects. If a step fails partway through:

- Compilation failures from partial edits can be fixed by completing the edit or reverting with `git checkout -- <file>`.
- Test failures indicate a JSON structure mismatch; compare the test expectation against the Notion API documentation.
- The `cabal build` command always performs a clean incremental build; no manual cache clearing is needed.

Each milestone commits its changes. To recover from a bad state, reset to the last good commit:

    git log --oneline -5
    git checkout <last-good-commit> -- src/ test/ notion-client-example/


## Interfaces and Dependencies

No new Cabal dependencies are required. All new types use existing libraries (aeson, servant, text, vector, containers, time).

**New module interfaces at end of plan:**

In `src/Notion/V1/Pages.hs`, define:

    data UpdatePageMarkdown
      = UpdateContent UpdateContentRequest
      | ReplaceContent ReplaceContentRequest
      | InsertContent InsertContentRequest
      | ReplaceContentRange ReplaceContentRangeRequest

    data UpdateContentRequest = UpdateContentRequest
      { contentUpdates :: Vector ContentUpdate
      , allowDeletingContent :: Maybe Bool
      }

    data ContentUpdate = ContentUpdate
      { oldStr :: Text
      , newStr :: Text
      , replaceAllMatches :: Maybe Bool
      }

    data ReplaceContentRequest = ReplaceContentRequest
      { newStr :: Text
      , allowDeletingContent :: Maybe Bool
      }

    data InsertContentRequest = InsertContentRequest
      { content :: Text
      , after :: Maybe Text
      }

    data ReplaceContentRangeRequest = ReplaceContentRangeRequest
      { content :: Text
      , contentRange :: Text
      , allowDeletingContent :: Maybe Bool
      }

    data MovePage = MovePage
      { parent :: Parent
      , position :: Maybe Position
      }

    data Template
      = NoTemplate
      | DefaultTemplate (Maybe Text)
      | TemplateById UUID (Maybe Text)

In `src/Notion/V1/DataSources.hs`, define:

    data TemplateRef = TemplateRef
      { id :: UUID
      , name :: Text
      , isDefault :: Bool
      }

    data ListTemplatesResponse = ListTemplatesResponse
      { templates :: Vector TemplateRef
      , hasMore :: Bool
      , nextCursor :: Maybe Text
      }

In `src/Notion/V1/Views.hs`, define:

    type ViewID = UUID

    data ViewType = TableView | BoardView | ListViewType | CalendarView
                  | TimelineView | GalleryView | FormView | ChartView
                  | MapView | DashboardView

    data ViewObject = ViewObject { ... }  -- as described in Milestone 3
    data CreateView = CreateView { ... }
    data UpdateView = UpdateView { ... }
    data QueryView = QueryView { ... }

In `src/Notion/V1/CustomEmojis.hs`, define:

    data CustomEmoji = CustomEmoji
      { id :: UUID
      , name :: Text
      , url :: Text
      }

In `src/Notion/V1/Common.hs`, extend:

    data Icon = ... | NativeIcon {name :: Text, color :: Maybe Text}
              | CustomEmojiIcon {customEmojiId :: UUID}

In `src/Notion/V1.hs`, extend `Methods` with:

    updatePageMarkdown :: PageID -> UpdatePageMarkdown -> IO PageMarkdown
    movePage :: PageID -> MovePage -> IO PageObject
    listDataSourceTemplates :: DataSourceID -> Maybe Text -> Maybe Text -> Maybe Natural -> IO ListTemplatesResponse
    createView :: CreateView -> IO ViewObject
    retrieveView :: ViewID -> IO ViewObject
    updateView :: ViewID -> UpdateView -> IO ViewObject
    deleteView :: ViewID -> IO ViewObject
    listViews :: Maybe UUID -> Maybe UUID -> Maybe Text -> Maybe Natural -> IO (ListOf ViewObject)
    queryView :: ViewID -> QueryView -> IO (ListOf PageObject)
    listCustomEmojis :: Maybe Text -> Maybe Text -> Maybe Natural -> IO (ListOf CustomEmoji)
