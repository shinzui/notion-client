# Changelog for notion-client

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
