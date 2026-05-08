---
id: 1
slug: notion-api-gap-analysis
title: "Notion API Gap Analysis: Missing Support in notion-client"
kind: exec-plan
created_at: 2026-03-31T15:28:28Z
---


# Notion API Gap Analysis: Missing Support in notion-client

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Identify every gap between the official Notion API reference (https://developers.notion.com/reference/intro,
API version 2026-03-11) and this Haskell client library. The result is a prioritized catalog of
missing block types, object fields, endpoint parameters, mention types, and enum variants.
After this analysis, a developer can pick any gap and implement it with full confidence that
nothing else is missing in that area.

The library is already mature (31+ endpoints, 29 block types, 24 property types, typed filters
and sorts). This plan documents the **remaining gaps**, not a rewrite.


## Progress

- [x] Research Notion API reference documentation (2026-03-31)
- [x] Audit all library modules against API docs (2026-03-31)
- [x] Catalog missing block types (2026-03-31)
- [x] Catalog missing rich text / mention types (2026-03-31)
- [x] Catalog missing object fields (2026-03-31)
- [x] Catalog missing endpoint parameters (2026-03-31)
- [x] Catalog missing enum variants (2026-03-31)
- [x] Prioritize and organize findings (2026-03-31)


## Surprises & Discoveries

- The library is significantly more comprehensive than the basic API reference docs. It already
  supports endpoints (views CRUD, custom emojis, file upload listing, page markdown, page move,
  data source create/templates) that aren't even listed in the standard reference pages.
- The library already handles `heading_4` in the `UnknownBlock` fallback path — it won't crash,
  but the data is untyped.
- Comment attachments and display_name fields exist in the read path (`CommentObject`) but not
  the write path (`CreateComment`).
- The `PageObject` is missing `is_locked` and `is_archived` as distinct fields — they're collapsed
  into the single `inTrash` field via fallback parsing.


## Decision Log

- Decision: Structure the gap analysis as a single reference document, not as implementation milestones.
  Rationale: The user asked to "highlight all missing support" — this is a research/audit task, not an implementation plan.
  Date: 2026-03-31

- Decision: Prioritize gaps by severity (parse failures > data loss > missing write capability > enum completeness).
  Rationale: A gap that causes a JSON parse failure in production is more urgent than a missing enum value that falls through to a catch-all.
  Date: 2026-03-31


## Outcomes & Retrospective

Analysis complete. The library has excellent coverage — 21 modules, 31+ endpoints, all 24 property
types. The gaps below are mostly about newer block types, a few missing object fields, and some
enum variants. No endpoint is completely missing from the core API reference.


---

## Context and Orientation

**Library**: `notion-client` — a Haskell Notion API client using Servant for type-safe API bindings.
**API version targeted**: 2026-03-11 (set in `src/Notion/V1.hs` via the `Notion-Version` header).

Key modules under review:

| Module | Path | Responsibility |
|--------|------|----------------|
| BlockContent | `src/Notion/V1/BlockContent.hs` | Block type sum type, parse/serialize, smart constructors |
| RichText | `src/Notion/V1/RichText.hs` | Rich text, mentions, annotations |
| Comments | `src/Notion/V1/Comments.hs` | Comment object, create request |
| Users | `src/Notion/V1/Users.hs` | User/bot objects |
| Pages | `src/Notion/V1/Pages.hs` | Page object, create/update requests |
| Common | `src/Notion/V1/Common.hs` | Parent, Icon, Cover, Color, File |
| Filter | `src/Notion/V1/Filter.hs` | Typed query filters and sorts |
| Properties | `src/Notion/V1/Properties.hs` | Property schema (database columns) |
| PropertyValue | `src/Notion/V1/PropertyValue.hs` | Property values (page cells) |
| Databases | `src/Notion/V1/Databases.hs` | Database object, CRUD |
| Blocks | `src/Notion/V1/Blocks.hs` | Block object, append children, position |


---

## Gap Catalog

### Priority 1 — Parse Failures / Untyped Fallback

These gaps cause either a hard parse failure or silently drop data into `UnknownBlock` / lose fields.

#### 1.1 Missing Block Type: `heading_4`

**API**: The 2026-03-11 API added `heading_4` as a block type, with the same structure as `heading_1`–`heading_3` (rich_text, color, is_toggleable, children when toggleable).

**Library**: `BlockContent` in `src/Notion/V1/BlockContent.hs` has `Heading1Block`, `Heading2Block`, `Heading3Block` but no `Heading4Block`. The parser falls through to `UnknownBlock` at line 855.

**Fix**: Add `Heading4Block` constructor, parse case, serialize case, update `headingBlock` smart constructor to accept level 4, update `withChildren`.

#### 1.2 Missing Block Type: `tab`

**API**: `tab` blocks are containers (children are paragraphs). Returned by the API when pages use tabbed layouts.

**Library**: Falls through to `UnknownBlock`.

**Fix**: Add `TabBlock { children :: Vector BlockContent }` constructor with parse/serialize support.

#### 1.3 Missing Block Type: `meeting_notes`

**API**: `meeting_notes` is a read-only block type with fields: `title`, `status`, `children`, `calendar_event`, `recording`.

**Library**: Falls through to `UnknownBlock`.

**Fix**: Add `MeetingNotesBlock` as a read-only constructor. Could use `Value` for the complex sub-fields (`calendar_event`, `recording`) since they're read-only and rarely consumed programmatically.

#### 1.4 Missing Mention Type: `template_mention`

**API**: Rich text mentions include a `template_mention` type with two sub-types:
- `template_mention_date` — dynamic date placeholder in templates
- `template_mention_user` — dynamic user placeholder in templates

**Library**: `MentionContent` in `src/Notion/V1/RichText.hs` (lines 80–106) handles `user`, `page`, `database`, `date`, `link_preview` but fails on `template_mention` with "Unknown mention type".

**Fix**: Add `TemplateMentionDate Text` and `TemplateMentionUser Text` constructors to `MentionContent`.

#### 1.5 Missing Field: `PageObject.isLocked`

**API**: Page objects have an `is_locked` boolean field.

**Library**: `PageObject` in `src/Notion/V1/Pages.hs` does not include `isLocked`. The field is silently dropped during parsing.

**Fix**: Add `isLocked :: Maybe Bool` to `PageObject`, parse with `o .:? "is_locked"`.

#### 1.6 Missing Field: `PageObject.isArchived`

**API**: Page objects have a distinct `is_archived` boolean field (separate from `in_trash`).

**Library**: `PageObject` collapses `in_trash`, `is_archived`, and `archived` into a single `inTrash :: Bool` field (line 81). This means `is_archived` status is not preserved separately.

**Fix**: Add `isArchived :: Maybe Bool` to `PageObject` as a separate field.

#### 1.7 Missing Field: `DataSourceParent.databaseId`

**API**: The `data_source_id` parent type includes both `data_source_id` and `database_id` fields:
```json
{ "type": "data_source_id", "data_source_id": "...", "database_id": "..." }
```

**Library**: `DataSourceParent` in `src/Notion/V1/Common.hs` (line 49) only stores `dataSourceId`, dropping the `databaseId`.

**Fix**: Change to `DataSourceParent { dataSourceId :: UUID, databaseId :: Maybe UUID }`.

#### 1.8 Missing Field: `Column.width_ratio`

**API**: Column blocks have a `width_ratio` field (number) that controls column width proportions.

**Library**: `ColumnBlock` in `src/Notion/V1/BlockContent.hs` (lines 535–537) only has `children`, no `width_ratio`.

**Fix**: Add `widthRatio :: Maybe Double` to `ColumnBlock`.


### Priority 2 — Missing Write Capabilities

These gaps prevent users from setting fields that the API supports on create/update.

#### 2.1 Missing Write Fields: `CreateComment.attachments` and `display_name`

**API**: The create comment endpoint accepts:
- `attachments` — array of file attachment objects
- `display_name` — custom display name object

**Library**: `CreateComment` in `src/Notion/V1/Comments.hs` (lines 83–88) only has `parent`, `richText`, `discussionId`. The read side (`CommentObject`) already parses these fields.

**Fix**: Add `attachments :: Maybe (Vector CommentAttachment)` and `displayName :: Maybe CommentDisplayName` to `CreateComment`, add `ToJSON` instances for `CommentAttachment` and `CommentDisplayName`.

#### 2.2 Missing Write Fields: `UpdatePage.isLocked` and `isArchived`

**API**: The update page endpoint accepts `is_locked` and `is_archived` fields.

**Library**: `UpdatePage` in `src/Notion/V1/Pages.hs` (lines 167–175) has `inTrash`, `icon`, `cover`, `template`, `eraseContent` but not `isLocked` or `isArchived`.

**Fix**: Add `isLocked :: Maybe Bool` and `isArchived :: Maybe Bool` to `UpdatePage`.

#### 2.3 Missing Query Parameter: Retrieve Page `filter_properties`

**API**: `GET /v1/pages/{page_id}` supports a `filter_properties` query parameter (repeated) to limit which properties are returned.

**Library**: The Servant API type in `src/Notion/V1/Pages.hs` (line 342–343) is:
```haskell
Capture "page_id" PageID :> Get '[JSON] PageObject
```
No query parameter support.

**Fix**: Add `QueryParams "filter_properties" Text` to the retrieve page endpoint.


### Priority 3 — Missing Enum Variants

These gaps cause parse failures only when the specific new value is encountered.

#### 3.1 Missing Rollup Functions: `count_per_group`, `percent_per_group`, `unique`

**API**: The rollup function enum includes these three values not present in the library.

**Library**: `RollupFunction` in `src/Notion/V1/Properties.hs` (lines 230–256) has 24 constructors but is missing these three.

**Fix**: Add `CountPerGroup`, `PercentPerGroup`, and `Unique` constructors with corresponding parse/serialize cases.

#### 3.2 Missing Date Filter Conditions: `this_month`, `this_year`

**API**: Date filters support `this_month` and `this_year` relative conditions.

**Library**: `DateCondition` in `src/Notion/V1/Filter.hs` (lines 228–243) has `DateThisWeek` but not `DateThisMonth` or `DateThisYear`.

**Fix**: Add `DateThisMonth` and `DateThisYear` constructors.

#### 3.3 Missing Block Type: `template` (Deprecated)

**API**: `template` blocks still exist in the API (deprecated for creation after 2023-03-27). They can appear in read responses.

**Library**: Falls through to `UnknownBlock`.

**Fix**: Add a read-only `TemplateBlock { richText :: Vector RichText, children :: Vector BlockContent }` constructor.


### Priority 4 — Missing Object Fields (Non-Critical)

These are fields that are typically not needed for common operations.

#### 4.1 Missing Fields: `BotUser.workspaceId` and `workspaceLimits`

**API**: Bot user objects include:
- `workspace_id` — string
- `workspace_limits.max_file_upload_size_in_bytes` — integer

**Library**: `BotUser` in `src/Notion/V1/Users.hs` (lines 60–62) only has `owner` and `workspaceName`.

**Fix**: Add `workspaceId :: Maybe Text` and `workspaceLimits :: Maybe WorkspaceLimits` to `BotUser`, where `WorkspaceLimits` is a new type.


---

## Summary Table

| # | Gap | Module | Severity | Effort |
|---|-----|--------|----------|--------|
| 1.1 | `heading_4` block type | BlockContent.hs | High | Small |
| 1.2 | `tab` block type | BlockContent.hs | High | Small |
| 1.3 | `meeting_notes` block type | BlockContent.hs | High | Small |
| 1.4 | `template_mention` mention type | RichText.hs | High | Small |
| 1.5 | `PageObject.isLocked` field | Pages.hs | High | Trivial |
| 1.6 | `PageObject.isArchived` field | Pages.hs | High | Trivial |
| 1.7 | `DataSourceParent.databaseId` field | Common.hs | High | Small |
| 1.8 | `Column.width_ratio` field | BlockContent.hs | High | Trivial |
| 2.1 | `CreateComment` attachments/display_name | Comments.hs | Medium | Small |
| 2.2 | `UpdatePage` isLocked/isArchived | Pages.hs | Medium | Trivial |
| 2.3 | Retrieve page `filter_properties` param | Pages.hs | Medium | Small |
| 3.1 | Rollup functions: count_per_group, etc. | Properties.hs | Low | Trivial |
| 3.2 | Date filter: this_month, this_year | Filter.hs | Low | Trivial |
| 3.3 | `template` block type (deprecated) | BlockContent.hs | Low | Small |
| 4.1 | `BotUser` workspace fields | Users.hs | Low | Small |


## What the Library Already Covers Well

For completeness, here is what the library already handles that is notable:

- **All 24 database property types** including place, button, verification
- **All 22+ page property value types** with smart constructors
- **29 block types** with full parse/serialize round-tripping
- **Comprehensive filter DSL** covering all 21 property condition types
- **Sorts** (property + timestamp)
- **Views** — full CRUD + query (6 endpoints, 10 view types)
- **File uploads** — create, retrieve, send, complete, list (5 endpoints)
- **Page markdown** — read and write with 4 update modes
- **Page move** — position-aware page relocation
- **Templates** — default, by-ID, with timezone
- **Custom emojis** — list endpoint
- **Data sources** — full CRUD + query + templates (5 endpoints)
- **Webhooks** — typed event parsing with 16+ event types
- **6 icon types** — emoji, file, external, native, custom_emoji, file_upload
- **3 cover types** — file, external, file_upload
- **Auto-pagination** via `Notion.V1.Pagination`
- **Position-aware block insertion** (start, end, after_block)


## Validation and Acceptance

This is a research/audit plan. Validation criteria:

1. Every endpoint listed at https://developers.notion.com/reference/intro has been checked.
2. Every object type's fields have been compared field-by-field.
3. Every enum (block types, property types, rollup functions, filter conditions, colors, etc.) has been compared value-by-value.
4. Gaps are categorized by severity and effort.
5. Each gap includes the specific file path and line numbers where the fix would go.


## Idempotence and Recovery

This plan is read-only research — no code changes. It can be re-run at any time by re-auditing the API docs against the library source.


## Interfaces and Dependencies

No code changes — this plan produces a reference document only.
