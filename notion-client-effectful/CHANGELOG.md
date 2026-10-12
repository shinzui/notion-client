# Changelog for `notion-client-effectful`

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
