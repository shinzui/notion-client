# Changelog for notion-client

## Unreleased

### Breaking Changes
* `Color` gains `DefaultBackground` and an `UnknownColor Text` fallback; its JSON instances are now hand-written
* `Parent` gains `AgentParent` and an `UnknownParent Value` fallback
* `Icon` gains an `UnknownIcon Value` fallback, and `CustomEmojiIcon` now encodes as `{"type":"custom_emoji","custom_emoji":{"id":...}}`
* `MentionContent` gains an `UnknownMention Value` fallback
* `PersonUser.email` changes from `Text` to `Maybe Text`
* `UniqueIdResult.number` changes from `Natural` to `Maybe Natural`
* `MeetingNotesBlock` fields are now typed: `meetingTitle :: Maybe (Vector RichText)`, `meetingStatus :: Maybe MeetingNotesStatus`, `calendarEvent :: Maybe MeetingCalendarEvent`, `recording :: Maybe MeetingRecording`, and the `children` field is replaced by `meetingChildren :: Maybe MeetingNotesChildren`; `withChildren` leaves meeting-notes blocks unchanged
* `CodeLanguage` gains 18 languages (`Abc`, `Agda`, `AsciiArt`, `Assembly`, `Bnf`, `Coq`, `Dhall`, `Ebnf`, `Hcl`, `Idris`, `LlvmIr`, `Mathematica`, `NotionFormula`, `PureScript`, `Racket`, `Smalltalk`, `Solidity`, `Toml`) and an `OtherLanguage Text` fallback
* `UserOwner` gains an `UnknownOwner` fallback
* `NumberFormat` gains an `OtherNumberFormat Text` fallback
* `FormulaResult` gains `FormulaUnsupportedResult` and an `UnknownFormulaResult Value` fallback
* `NotionError.code` is now `APIErrorCode` (was `Text`); `NotionError` gains `requestId`, `additionalData` and `response` fields. String literals still work via `IsString`; use `apiErrorCodeText` to get `Text`
* Failure responses whose body is not a Notion error (for example Cloudflare HTML pages) now throw `UnknownHTTPResponseError` instead of servant's `ClientError` (`FailureResponse`)
* Connection and response timeouts now throw `RequestTimeoutError` instead of `ClientError` (`ConnectionError`)
* `makeMethods` now retries `rate_limited` (429) and `service_overload` (529) responses for all requests and `internal_server_error`/`service_unavailable` for GET/DELETE, up to 2 times with back-off honoring `retry-after`. Use `makeMethodsWithEnv defaultClientConfig {retryOptions = noRetries}` for the old behavior
* Requests now send a `User-Agent: notion-client-haskell/<version>` header
* Request paths containing `..` throw `InvalidPathParameterError` before any request is sent
* `ListOf` gains a `requestStatus` field; record construction must supply it
* Minimum `servant-client` is now 0.20.2; new dependencies `base64-bytestring`, `http-client`, `http-types`, `mtl`, `random` and `servant-client-core`
* `CreatePage.position` changes from `Maybe Blocks.Position` to `Maybe PagePosition`
* The exported Servant `API` types of `Notion.V1`, `Notion.V1.DataSources` and `Notion.V1.Databases` gain a `QueryParams "filter_properties" Text` segment on the query routes (only affects code deriving its own client from them; the `Methods` record is unchanged)
* `CreateComment` is restructured: `target :: CommentTarget` (parent or discussion) and `content :: CommentContent` (rich text or Markdown) replace `parent`, `discussionId` and `richText`; `attachments` now holds `CommentAttachmentRequest` and `displayName` holds `CommentDisplayNameRequest`. Use `mkCreateComment` / `mkReplyComment`
* `createComment` returns `CommentResponse` (full or partial comment) instead of `CommentObject`
* `Methods` and the effectful `Notion` GADT gain `retrieveComment`, `updateComment`, `deleteComment`, `createPageAsync`, `updatePageMarkdownAsync`, `retrieveAsyncTask` and `createMeetingNote`
* The exported Servant `API` types of `Notion.V1` and `Notion.V1.Pages` gain the async page routes, `AsyncTasks.API` and `MeetingNotes.API`

### New Features
* Export `UserOwner (..)` from `Notion.V1.Users`
* New meeting-notes payload types `MeetingNotesStatus`, `MeetingNotesChildren`, `MeetingCalendarEvent` and `MeetingRecording` in `Notion.V1.BlockContent`
* New `PagePosition` type (`PageAfterBlock`, `PageStart`, `PageEnd`) in `Notion.V1.Pages`
* `ClientConfig`, `defaultClientConfig`, `makeMethodsWith` and `makeMethodsWithEnv`: configurable Notion-Version, base URL, timeout (default 60s), retries, User-Agent and logging (`stderrLogger` for opt-in logging)
* `APIErrorCode` with all 14 Notion error codes plus `UnknownErrorCode`
* `RequestStatus` on list responses
* OAuth: `Notion.V1.OAuth` with `createOAuthToken`, `revokeOAuthToken` and `introspectOAuthToken` using HTTP Basic auth
* `Notion.V1.Helpers`: `extractNotionId`, `extractPageId`, `extractDatabaseId`, `extractBlockId`
* `paginateFoldM` and `paginateForM_` in `Notion.V1.Pagination`
* Runtime building blocks for non-Servant requests: `RequestContext`, `standardHeaders`, `responseTimeoutFor`, `withRetries`, `buildRequestError` and `notionErrorFromResponse`
* Retrieve, update (rich text or Markdown) and delete comments; create comments with Markdown, discussion replies, file-upload attachments and display names
* New `Notion.V1.AsyncTasks` module: `AsyncTask`, `retrieveAsyncTask`, `waitForAsyncTask`, and `allow_async` page creation / markdown update via `createPageAsync` and `updatePageMarkdownAsync` (which accept Notion's `202 Accepted` responses)
* New `Notion.V1.MeetingNotes` module: `createMeetingNote` from an uploaded recording or an existing media block, with a typed `MeetingNoteBlock` response

### Bug Fixes
* Decode the `default_background` color — previously any rich text or block using it failed the whole response
* Decode `agent_id` parents on pages and blocks
* Read and write custom-emoji icons in the nested `custom_emoji` object shape Notion uses; the old top-level `id` shape is still accepted when reading
* Unknown colors, parent kinds, icon kinds and mention kinds (for example `link_mention` and `custom_emoji` mentions) decode into fallback constructors instead of failing
* Decode code blocks in every language Notion supports (for example `toml`), with unknown languages kept as `OtherLanguage`
* Decode real meeting-notes blocks (rich-text `title`, object `children`) and the deprecated `transcription` block type
* Decode person users without a visible email, and bots owned by a user (Notion sends the user object, not a bare ID)
* Decode data sources with number formats newer than this library
* Decode unique-ID properties whose `number` is null, and formula properties with an `unsupported` result
* `queryDataSource` and `queryDatabase` send `filterProperties` as repeated `filter_properties` query parameters instead of a JSON body field, which Notion rejected
* `CreatePage` positions encode as `page_start`, `page_end` and `after_block`, the shapes Notion accepts for page creation
* `WebhookEvent` decodes without `accessible_by` (it is only sent to public integrations); `accessibleBy` is empty in that case
* `verifySignature` accepts upper- or lowercase hex and rejects headers without the `sha256=` prefix, of the wrong length, or with non-hex characters

## 0.7.0.2 (2026-06-27)

### Bug Fixes
* Relation property schemas with `single_property` now serialize the required empty `single_property` object, so creating one-directional and self-referential relation columns no longer fails Notion validation with "is not a valid property schema"

## 0.7.0.1 (2026-04-16)

### Bug Fixes
* Fix `FromJSON`/`ToJSON` for native icons to use the nested `{"type":"icon","icon":{"name":..., "color":...}}` shape returned by GET endpoints — previously crashed with `key "name" not found` on pages/databases carrying built-in pictogram icons

## 0.7.0.0 (2026-04-16)

### Breaking Changes
* `BlockContent` gains new constructors: `Heading4`, `Tab`, `MeetingNotes`, `Template` — pattern matches on `BlockContent` must handle these variants
* `MentionContent` gains new constructors: `TemplateMentionDate`, `TemplateMentionUser` — pattern matches must be updated
* `RollupFunction` gains new constructors: `CountPerGroup`, `PercentPerGroup`, `Unique`
* `DateCondition` gains new constructors: `DateThisMonth`, `DateThisYear`
* `PageObject` gains new fields: `isLocked`, `isArchived`
* `DataSourceParent` gains `parentDatabaseId` field
* `ColumnBlock` gains `widthRatio` field
* `BotUser` gains `workspaceId`, `workspaceLimits` fields (new `WorkspaceLimits` type)
* `CreateComment` gains `attachments` and `displayName` fields
* `UpdatePage` gains `isLocked` and `isArchived` fields
* `CommentAttachment` restructured: all fields now `Maybe`, new `category` field, hand-rolled FromJSON/ToJSON to support both read and write shapes
* `CommentDisplayName` gains `resolvedName` field

### New Features
* Add `retrievePageFiltered` method with `filter_properties` query parameter for `GET /v1/pages/{page_id}` (`retrievePage` remains backward-compatible)
* Smart constructor `headingBlock` now supports level 4
* `CommentAttachment` and `CommentDisplayName` now have `ToJSON` instances

### Bug Fixes
* Strip read-only `list_start_index` and `list_format` fields from `BlockUpdate` serialization — the Notion API rejects PATCH requests containing these fields on `numbered_list_item` blocks
* Fix parsing of `List Comments` responses: `CommentAttachment` now correctly decodes the `{"category":..., "file":...}` read shape, and `CommentDisplayName` preserves the `resolved_name` field

## 0.6.1.0 (2026-03-31)

### New Features
* **File Upload API**: New `Notion.V1.FileUploads` module with complete file upload support — create, send (multipart form-data), complete, retrieve, and list endpoints
* Smart constructors for single-part, multi-part, and external URL upload modes
* Add `file_upload` variant to `FileValue`, `Icon`, and `Cover` types

### Other Changes
* Update seihou scaffolding (exec-plan 0.1.2 → 0.1.3)

## 0.6.0.0 (2026-03-30)

### Breaking Changes
* Replace untyped `Value` block content with typed `BlockContent` sum type in `Notion.V1.BlockContent` module
* `AppendBlockChildren` and `CreatePage` now use `[BlockContent]` instead of `[Value]` for children
* Block types are now statically typed variants (e.g., `Paragraph`, `Heading1`, `BulletedListItem`, `Code`, `Toggle`, `Callout`, etc.) instead of free-form JSON

### New Features
* **Typed Block Content**: New `Notion.V1.BlockContent` module with `BlockContent` sum type for creating blocks with compile-time safety and smart constructors
* **Nested Block Children**: `BlockContent` supports recursive `children` for creating nested block hierarchies in a single API call (e.g., toggles containing paragraphs, bulleted lists with sub-items)

## 0.5.0.0 (2026-03-29)

### Breaking Changes
* Replace untyped `PropertyValue`/`PropertyItem`/`PropertyValueType` with a proper `PropertyValue` sum type (23 variants) in new `Notion.V1.PropertyValue` module
* Remove `SelectOption` from `Notion.V1.Pages` — use `SelectOptionValue` from `Notion.V1.PropertyValue` instead
* `PageObject.properties` is now `Map Text PropertyValue` instead of `Map Text PropertyItem`
* `CreatePage.properties` and `UpdatePage.properties` are now `Map Text PropertyValue`
* `UpdateDataSource.properties` changes from `Maybe (Map Text PropertySchema)` to `Maybe (Map Text (Maybe PropertySchema))` to support property deletion via `null`
* `QueryDatabase` and `QueryDataSource` gain a `filterProperties` field
* `UpdateDatabase` gains an `isLocked` field
* `CreateDataSource` gains `description` and `cover` fields

### New Features
* **Typed Property Values**: New `Notion.V1.PropertyValue` module with `PropertyValue` sum type for reading page properties via pattern matching, and smart constructors (`titleValue`, `selectValue`, `numberValue`, `checkboxValue`, `dateValue`, `statusValue`, `relationValue`, `peopleValue`, `filesValue`, etc.) for writes
* **Page Property Item Endpoint**: Add `retrievePageProperty` method (`GET /v1/pages/{page_id}/properties/{property_id}`) with `PropertyItemResponse` type handling both single and paginated results
* **Typed Error Handling**: `NotionError` now has an `Exception` instance. The client automatically parses Notion API errors into typed `NotionError` exceptions. Add `parseNotionError` helper and `ToJSON` instance
* **Property Schema Deletion**: Set properties to `Nothing` in `UpdateDataSource` to delete them from the schema (emits `null` in JSON)
* **Auto-Pagination**: New `paginateAll` and `paginateCollect` functions in `Notion.V1.Pagination` that follow cursors automatically
* Add `publicUrl :: Maybe Text` to `PageObject`
* Mark `queryDatabase` as deprecated in favor of `queryDataSource`

## 0.4.0.0 (2026-03-29)

### Breaking Changes
* Replace `properties :: Maybe Value` in `DatabaseObject` with `Maybe (Map Text PropertySchema)`
* Replace `properties :: Value` in `DataSourceObject` with `Map Text PropertySchema`
* Replace `properties :: Value` / `Maybe Value` in `CreateDataSource`, `UpdateDataSource`, `InitialDataSource` with typed `PropertySchema`
* Replace `filter :: Maybe Value` in `QueryDatabase` and `QueryDataSource` with `Maybe Filter`
* Replace `sorts :: Maybe [Value]` in `QueryDatabase` and `QueryDataSource` with `Maybe [Sort]`

### New Features
* **Typed Property Schemas**: New `Notion.V1.Properties` module with `PropertySchema` sum type (23 property types), `SelectColor` enum (10 colors), `NumberFormat` enum (39 formats), `RollupFunction` enum (25 functions), `RelationType`, `SelectOption`, `StatusGroup`
* **Typed Query Filters**: New `Notion.V1.Filter` module with `Filter` DSL — compound `And`/`Or` filters, `PropertyFilter` with 22 condition variants (text, number, checkbox, select, multi-select, date, people, files, relation, status, unique ID, verification, formula, rollup), and `TimestampFilter`
* **Typed Query Sorts**: `Sort` type with `PropertySort` and `TimestampSort`, `SortDirection` enum

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
