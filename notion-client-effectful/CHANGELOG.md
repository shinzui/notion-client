# Changelog for `notion-client-effectful`

## 0.4.0.0 - 2026-10-19

### Breaking Changes

* Requires `notion-client >=0.10 && <0.11`. Upgrade this companion to 0.4.0.0 alongside core 0.10.0.0. `runNotion` accepts refreshing `Methods` unchanged; no effect constructors changed.
* `OAuthError`, `ReauthorizationRequired`, `TokenPersistenceError` and `RefreshOutcomeUnknown` propagate in IO; `Error NotionError` catches only final Notion API errors. Retry persistence on the same manager; reauthorization and uncertain refresh outcomes require a new login and manager.

### Validation

* Four OAuth runtime consumer tests verify reactive refresh and the IO exception boundary. The core client's live public-integration gate also passed login, rotation, persisted restart, cancellation and logout on 2026-10-19.

## 0.3.0.0 - 2026-10-12

### Breaking Changes

* Requires `notion-client >=0.9 && <0.10`. Core `RelationValue` gains a trailing `Maybe Bool` for response completeness: migrate patterns to `RelationValue pid refs hasMore` and manual write values to `RelationValue pid refs Nothing`. The `relationValue` smart constructor keeps its signature.
* Response exports can use core `propertyValueResponseJSON` and `pageResponseJSON`. These pure helpers require no new effect operations; `Methods` and the interpreter remain aligned.

## 0.2.0.0 - 2026-09-15

### Breaking Changes

* Requires `notion-client >=0.8 && <0.9`.
* `queryDataSource` and `search` now return `ListOf PageOrDataSource` (was `ListOf PageObject` and `ListOf Value`), following `notion-client`.
* `updateBlock` takes `Blocks.BlockUpdatePayload` (was `Blocks.BlockUpdate`).
* `createComment` returns `CommentResponse` (was `CommentObject`).
* Remove `queryView` / `QueryView`; use `createViewQuery`, `getViewQueryResults` and `deleteViewQuery`.

### New Features

* New operations `createPageFiltered`, `updatePageFiltered`, `createPageAsync`, `updatePageMarkdownAsync`, `retrieveAsyncTask`, `retrieveComment`, `updateComment`, `deleteComment`, `createViewQuery`, `getViewQueryResults`, `deleteViewQuery`, `createMeetingNote` and `queryMeetingNotes`.

## 0.1.0.0 - 2026-04-17

* Initial release: `Notion` effect and `runNotion` interpreter covering
  every `Notion.V1.Methods` field at the time of release
  (notion-client 0.7.x).
