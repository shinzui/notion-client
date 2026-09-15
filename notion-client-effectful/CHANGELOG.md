# Changelog for `notion-client-effectful`

## Unreleased

* `queryDataSource` and `search` now return `ListOf PageOrDataSource` (was `ListOf PageObject` and `ListOf Value`), following `notion-client`.

## 0.1.0.0 - 2026-04-17

* Initial release: `Notion` effect and `runNotion` interpreter covering
  every `Notion.V1.Methods` field at the time of release
  (notion-client 0.7.x).
