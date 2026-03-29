# Changelog for notion-client

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
