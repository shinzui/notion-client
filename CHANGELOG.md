# Changelog for notion-client

## 0.3.1.0 (2026-03-29)

### New Features
* **Markdown Content API**: Add `updatePageMarkdown` method for editing page content via markdown with search-and-replace (`UpdateContent`), full replacement (`ReplaceContent`), and legacy insert/replace commands
* **Create pages with markdown**: Add `markdown` field to `CreatePage` as alternative to `children`
* **Move Page API**: Add `movePage` method (`POST /v1/pages/{page_id}/move`) to relocate pages between parents
* **Template support**: Add `Template` type and `template`/`eraseContent` fields to `CreatePage` and `UpdatePage`
* **List data source templates**: Add `listDataSourceTemplates` method (`GET /v1/data_sources/{id}/templates`)
* **Views API**: New `Notion.V1.Views` module with full CRUD + list + query endpoints for database views (table, board, list, calendar, timeline, gallery, form, chart, map, dashboard)
* **Custom Emojis API**: New `Notion.V1.CustomEmojis` module with `listCustomEmojis` method
* **Native icons**: Add `NativeIcon` variant to `Icon` type (name + color)
* **Custom emoji icons**: Add `CustomEmojiIcon` variant to `Icon` type
* **View webhook events**: Add `ViewCreated`, `ViewUpdated`, `ViewDeleted` event types and `ViewEntity` entity type
* **View object type**: Add `View` constructor to `ObjectType` enum
* Add `position` field to `CreatePage` for controlling page placement within parent

### Non-Breaking Changes
* Add `markdown` field to `CreatePage` (defaults to `Nothing` via `mkCreatePage`)
* Add `template`, `position` fields to `CreatePage` (defaults to `Nothing` via `mkCreatePage`)
* Add `template`, `eraseContent` fields to `UpdatePage` (defaults to `Nothing` via `mkUpdatePage`)

## 0.3.0.0 (2026-03-29)

### Breaking Changes
* Remove `archived` field from `BlockObject` — use `inTrash` instead (renamed to match API 2026-03-11)
* Remove `archived` field from `PageObject` — use existing `inTrash` field
* Remove `archived` field from `DatabaseObject` — use existing `inTrash` field
* Remove `archived` field from `DataSourceObject` — use existing `inTrash` field
* Rename `archived` to `inTrash` in `UpdatePage` request type
* Remove `archived` from `UpdateDatabase` request type — use existing `inTrash` field
* Remove `archived` from `UpdateDataSource` request type — use existing `inTrash` field
* Remove `archived` from `QueryDataSource` request type — use existing `inTrash` field
* Change `AppendBlockChildren` from `newtype` to `data` with new optional `position` field

### New Features
* Add `Position` type (`AfterBlock`, `Start`, `End`) for specifying block insertion position
* The `transcription` block type is renamed to `meeting_notes` by the API (no library code change needed since block types are `Text`)

### Bug Fixes
* Fix backward-compatible `FromJSON` fallback: `.:?` with `<|>` was silently broken (always returned `Nothing`), now correctly falls back through `in_trash` → `is_archived` → `archived`

## 0.2.0.0 (2026-03-29)

### Breaking Changes
* Bump Notion API version from `2025-09-03` to `2026-03-11`
* Change `DataSourceObject.archived` from `Bool` to `Maybe Bool` (field no longer guaranteed in API responses)

### New Features
* Add `PageMarkdown` type and `retrievePageMarkdown` method for `GET /v1/pages/{page_id}/markdown`
* Support optional `include_transcript` query parameter for markdown retrieval

### Bug Fixes
* Handle API rename of `archived` to `is_archived` in responses for `PageObject`, `BlockObject`, `DatabaseObject`, and `DataSourceObject`

## 0.1.0.1 (2026-03-29)

### Bug Fixes
* Export `UUID` constructor from `Notion.V1.Common` for pattern matching
* Fix `PropertyItem` parsing for rollup, formula, and relation property types
* Fix license field in README from BSD-3-Clause to MIT

### Other Changes
* Add `ToJSON` instances for `UserObject`, `BlockObject`, `PageObject`, and related types

## 0.1.0.0 (2026-02-28)

* Initial release
* Support for core Notion API endpoints:
  * Databases
  * Data Sources
  * Pages
  * Blocks
  * Users
  * Search
  * Comments
  * Webhooks (event types and signature verification)
* Type-safe client with Servant-based implementation
* Targets Notion API version 2025-09-03
