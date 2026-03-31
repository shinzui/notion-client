# Close All Notion API Coverage Gaps

Intention: intention_01kn288bpaeasb8rfvyjkf9k56

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After completing this plan, the `notion-client` library will handle every block type, mention type, object field, endpoint parameter, and enum variant documented in the Notion API reference (version 2026-03-11). Today, 15 specific gaps exist — some cause hard parse failures when encountering newer API responses (e.g., `template_mention` in rich text), others silently lose data (e.g., `is_locked` on pages), and the rest are missing enum values or write-side fields.

A developer using this library after these changes will be able to round-trip every Notion API response without data loss and use every write-side parameter the API supports.

The gaps were cataloged in `docs/plans/1-notion-api-gap-analysis.md`. This plan implements all of them.


## Progress

- [x] Milestone 1: Block type gaps (heading_4, tab, meeting_notes, template) — 2026-03-31
- [x] Milestone 2: Rich text template_mention — 2026-03-31
- [x] Milestone 3: Object field gaps (PageObject, DataSourceParent, Column, BotUser) — 2026-03-31
- [x] Milestone 4: Write-side gaps (CreateComment, UpdatePage, retrieve page filter_properties) — 2026-03-31
- [x] Milestone 5: Enum completeness (rollup functions, date filter conditions) — 2026-03-31
- [x] Milestone 6: Tests for all new types — 2026-03-31


## Surprises & Discoveries

- `QueryParams` (plural) is not exported from `Notion.Prelude`, only `QueryParam` (singular). Required explicit import from `Servant.API`.
- The `isArchived` field name caused ambiguity in tests because both `PageObject` and `UpdatePage` have it with `DuplicateRecordFields`. Resolved with pattern matching.
- The `ColumnBlock` constructor change required updating existing test data that constructed `ColumnBlock` values directly.


## Decision Log

- Decision: Group changes into 6 milestones by module area rather than by priority level.
  Rationale: Changes within the same file should be batched together. A file-oriented approach minimizes merge conflicts and makes each commit cohesive. Each milestone independently compiles and passes tests.
  Date: 2026-03-31

- Decision: Use `Value` for `meeting_notes` sub-fields (`calendarEvent`, `recording`) and for `template` block children.
  Rationale: These are read-only block types with complex nested structures that are rarely consumed programmatically. Using `Value` avoids defining a large number of types that would need to track every change Notion makes to these internal structures, while still preserving all data.
  Date: 2026-03-31

- Decision: Make `DataSourceParent.databaseId` a `Maybe UUID` rather than a required field.
  Rationale: The `database_id` in a data source parent is not always present in older API responses or when constructing parents for writes. Using `Maybe` avoids breaking the `ToJSON` instance for user-constructed parents.
  Date: 2026-03-31

- Decision: Add `filter_properties` to the retrieve page Servant endpoint rather than adding a wrapper type.
  Rationale: Servant's `QueryParams` (plural) natively handles repeated query parameters. This is the idiomatic approach and requires no new types.
  Date: 2026-03-31


## Outcomes & Retrospective

All 15 API coverage gaps have been closed. The library now handles every block type, mention type, object field, endpoint parameter, and enum variant documented in the Notion API reference (version 2026-03-11).

- All 6 milestones completed in a single session on 2026-03-31
- `cabal build all` compiles cleanly
- `cabal test tasty` passes all 124 tests (14 new tests added, up from 110)
- All changes are additive — no existing constructors or fields removed
- Backward compatibility preserved: `retrievePage` still works with just a PageID; `retrievePageFiltered` added for the filtered variant
- 6 commits, each leaving the codebase in a working state


## Context and Orientation

This library is a Haskell client for the Notion API, built on Servant (a type-level web framework that generates HTTP clients from API type definitions). The key pattern is: each module defines Haskell data types with hand-written `FromJSON`/`ToJSON` instances, a Servant `API` type alias, and the top-level `Notion.V1` module wires everything together into a `Methods` record of `IO` actions.

The project builds with `cabal build all` and tests run with `cabal test tasty`. Tests live in `tasty/Main.hs` and use the Tasty framework with HUnit assertions. JSON round-trip tests encode a value to JSON and decode it back, checking equality.

The files we will modify, listed by milestone:

**Milestone 1** (block types):
- `src/Notion/V1/BlockContent.hs` — the `BlockContent` sum type, `blockContentFields`, `parseBlockContent`, smart constructors, `withChildren`

**Milestone 2** (template_mention):
- `src/Notion/V1/RichText.hs` — the `MentionContent` sum type and its JSON instances

**Milestone 3** (object fields):
- `src/Notion/V1/Pages.hs` — `PageObject` (add `isLocked`, `isArchived`)
- `src/Notion/V1/Common.hs` — `DataSourceParent` (add `databaseId`)
- `src/Notion/V1/BlockContent.hs` — `ColumnBlock` (add `widthRatio`)
- `src/Notion/V1/Users.hs` — `BotUser` (add `workspaceId`, `workspaceLimits`)

**Milestone 4** (write-side):
- `src/Notion/V1/Comments.hs` — `CreateComment` (add `attachments`, `displayName`), add `ToJSON` for `CommentAttachment`/`CommentDisplayName`
- `src/Notion/V1/Pages.hs` — `UpdatePage` (add `isLocked`, `isArchived`), Servant API type (add `filter_properties`)
- `src/Notion/V1/V1.hs` — `Methods.retrievePage` type (add filter_properties param)

**Milestone 5** (enums):
- `src/Notion/V1/Properties.hs` — `RollupFunction` (add 3 constructors)
- `src/Notion/V1/Filter.hs` — `DateCondition` (add 2 constructors)

**Milestone 6** (tests):
- `tasty/Main.hs` — new test cases for every addition


## Plan of Work


### Milestone 1 — New Block Types

At the end of this milestone, the library will parse and serialize `heading_4`, `tab`, `meeting_notes`, and `template` blocks instead of falling through to `UnknownBlock`. The build will succeed and existing tests will pass.

In `src/Notion/V1/BlockContent.hs`, add four new constructors to the `BlockContent` data type.

`Heading4Block` follows the exact same pattern as the existing `Heading1Block`–`Heading3Block`: it carries `richText`, `color`, `isToggleable`, and `children` fields. Add it after `Heading3Block` in the data type definition.

`TabBlock` is a simple container block. It has only `children :: Vector BlockContent`. Add it after `SyncedBlockContent`.

`MeetingNotesBlock` is read-only with complex nested data. Define it as:

    MeetingNotesBlock
      { meetingTitle :: Text,
        meetingStatus :: Maybe Text,
        calendarEvent :: Maybe Value,
        recording :: Maybe Value,
        children :: Vector BlockContent
      }

The `calendarEvent` and `recording` fields use `Value` (from Aeson) because these are opaque, read-only nested structures that change frequently in the API.

`TemplateBlock` is deprecated but still returned by the API. Define it as:

    TemplateBlock
      { richText :: Vector RichText,
        children :: Vector BlockContent
      }

For each new constructor, add three things:

1. A case in `blockContentFields` that returns the JSON type name and serialized object. For `heading_4`, this is identical to the heading_3 pattern. For `tab`, emit `("tab", object $ childrenPairs children)`. For `meeting_notes`, emit the fields. For `template`, emit `rich_text` and children.

2. A case in `parseBlockContent` that parses from the type name string. For `"heading_4"`, copy the `"heading_3"` parser and change the constructor. For `"tab"`, parse only children. For `"meeting_notes"`, parse `title` (as `meetingTitle`), optional `status`, optional `calendar_event`, optional `recording`, and children. For `"template"`, parse `rich_text` and children.

3. Update `withChildren` to handle all four new constructors (they all have children).

Update the `headingBlock` smart constructor to accept level 4:

    headingBlock 4 rt = Heading4Block rt Default False Vector.empty

Verification: `cabal build all` succeeds, `cabal test tasty` passes all existing tests.


### Milestone 2 — Template Mention in Rich Text

At the end of this milestone, rich text containing `template_mention` will parse instead of failing with "Unknown mention type". This is important because any Notion page using template mentions in its content would cause a hard parse failure today.

In `src/Notion/V1/RichText.hs`, add two new constructors to `MentionContent`:

    | TemplateMentionDate { templateMentionDate :: Text }
    | TemplateMentionUser { templateMentionUser :: Text }

In the `FromJSON` instance for `MentionContent`, add a case for `"template_mention"`:

    "template_mention" -> do
      tmObj <- o .: "template_mention"
      tmType <- tmObj .: "type"
      case tmType of
        "template_mention_date" -> TemplateMentionDate <$> tmObj .: "template_mention_date"
        "template_mention_user" -> TemplateMentionUser <$> tmObj .: "template_mention_user"
        other -> fail $ "Unknown template_mention type: " <> unpack other

In the `ToJSON` instance for `MentionContent`, add cases:

    TemplateMentionDate d ->
      object ["type" .= ("template_mention" :: Text),
              "template_mention" .= object ["type" .= ("template_mention_date" :: Text),
                                            "template_mention_date" .= d]]
    TemplateMentionUser u ->
      object ["type" .= ("template_mention" :: Text),
              "template_mention" .= object ["type" .= ("template_mention_user" :: Text),
                                            "template_mention_user" .= u]]

Verification: `cabal build all` succeeds, `cabal test tasty` passes.


### Milestone 3 — Missing Object Fields

At the end of this milestone, `PageObject` will carry `isLocked` and `isArchived` as separate fields, `DataSourceParent` will preserve the `databaseId`, `ColumnBlock` will have `widthRatio`, and `BotUser` will have `workspaceId` and `workspaceLimits`. No data from API responses will be silently dropped.

**3a. PageObject fields** — In `src/Notion/V1/Pages.hs`, add two fields to `PageObject`:

    isLocked :: Maybe Bool,
    isArchived :: Maybe Bool,

In the `FromJSON` instance, parse them:

    isLocked <- o .:? "is_locked"
    isArchived <- o .:? "is_archived"

Keep the existing `inTrash` fallback logic as-is for backward compatibility. In the `ToJSON` instance, add:

    <> maybe [] (\v -> ["is_locked" .= v]) isLocked
    <> maybe [] (\v -> ["is_archived" .= v]) isArchived

**3b. DataSourceParent.databaseId** — In `src/Notion/V1/Common.hs`, change:

    DataSourceParent {dataSourceId :: UUID}

to:

    DataSourceParent {dataSourceId :: UUID, parentDatabaseId :: Maybe UUID}

Use `parentDatabaseId` to avoid conflict with `DatabaseParent`'s field. Update `FromJSON` to parse the extra field:

    "data_source" -> \o -> DataSourceParent <$> o .: "data_source_id" <*> o .:? "database_id"
    "data_source_id" -> \o -> DataSourceParent <$> o .: "data_source_id" <*> o .:? "database_id"

Update `ToJSON` to conditionally emit it:

    toJSON (DataSourceParent dsId mDbId) =
      object $ ["type" .= ("data_source_id" :: Text), "data_source_id" .= dsId]
        <> maybe [] (\dbId -> ["database_id" .= dbId]) mDbId

Update the `parseByKey` fallback to also parse the optional `database_id`:

    DataSourceParent <$> o .: "data_source_id" <*> o .:? "database_id",

Every call site that constructs a `DataSourceParent` must now supply the second field. Search for `DataSourceParent` across the codebase and add `Nothing` as the `parentDatabaseId` where values are constructed for writes (the `database_id` is only meaningful in read responses).

**3c. Column.widthRatio** — In `src/Notion/V1/BlockContent.hs`, change `ColumnBlock`:

    ColumnBlock
      { widthRatio :: Maybe Double,
        children :: Vector BlockContent
      }

Update `blockContentFields` to conditionally emit it:

    ColumnBlock {..} ->
      ("column", object $ maybe [] (\r -> ["width_ratio" .= r]) widthRatio
                        <> childrenPairs children)

Update `parseBlockContent` for `"column"`:

    "column" -> parseObj $ \o -> do
      widthRatio <- o .:? "width_ratio"
      children <- fromMaybe Vector.empty <$> o .:? "children"
      pure ColumnBlock {..}

Update `withChildren` — no change needed since it already uses record update syntax on `ColumnBlock`.

**3d. BotUser fields** — In `src/Notion/V1/Users.hs`, add a new type and extend `BotUser`:

    data WorkspaceLimits = WorkspaceLimits
      { maxFileUploadSizeInBytes :: Maybe Natural
      }
      deriving stock (Generic, Show)

    instance FromJSON WorkspaceLimits where
      parseJSON = genericParseJSON aesonOptions

Then change `BotUser` to:

    data BotUser = BotUser
      { owner :: Maybe UserOwner,
        workspaceName :: Maybe Text,
        workspaceId :: Maybe Text,
        workspaceLimits :: Maybe WorkspaceLimits
      }
      deriving stock (Generic, Show)

Since `BotUser` uses `genericParseJSON aesonOptions`, the new optional fields will automatically parse correctly with no further changes (the `aesonOptions` converts `workspaceId` to `workspace_id` and `workspaceLimits` to `workspace_limits`).

Export `WorkspaceLimits` from the module.

Verification: `cabal build all` succeeds. Fix any compilation errors from `DataSourceParent` construction sites.


### Milestone 4 — Write-Side Gaps

At the end of this milestone, users will be able to attach files to comments, lock/archive pages via update, and filter properties when retrieving a page.

**4a. CreateComment enhancements** — In `src/Notion/V1/Comments.hs`, add `ToJSON` instances for `CommentAttachment` and `CommentDisplayName` (currently they only have `FromJSON`):

    instance ToJSON CommentAttachment where
      toJSON = genericToJSON aesonOptions {fieldLabelModifier = \s -> if s == "type_" then "type" else labelModifier s}

    instance ToJSON CommentDisplayName where
      toJSON = genericToJSON aesonOptions {fieldLabelModifier = \s -> if s == "type_" then "type" else labelModifier s}

Then add two fields to `CreateComment`:

    data CreateComment = CreateComment
      { parent :: Parent,
        richText :: Vector RichText,
        discussionId :: Maybe UUID,
        attachments :: Maybe (Vector CommentAttachment),
        displayName :: Maybe CommentDisplayName
      }

The existing `ToJSON` uses `genericToJSON aesonOptions` which will automatically include the new optional fields when present and omit them when `Nothing`.

**4b. UpdatePage enhancements** — In `src/Notion/V1/Pages.hs`, add two fields to `UpdatePage`:

    data UpdatePage = UpdatePage
      { properties :: PageProperties,
        inTrash :: Maybe Bool,
        isLocked :: Maybe Bool,
        isArchived :: Maybe Bool,
        icon :: Maybe Icon,
        cover :: Maybe Cover,
        template :: Maybe Template,
        eraseContent :: Maybe Bool
      }

Update `mkUpdatePage` to set the new fields to `Nothing`.

**4c. Retrieve page filter_properties** — In `src/Notion/V1/Pages.hs`, change the retrieve page Servant endpoint from:

    Capture "page_id" PageID
      :> Get '[JSON] PageObject

to:

    Capture "page_id" PageID
      :> QueryParams "filter_properties" Text
      :> Get '[JSON] PageObject

In `src/Notion/V1.hs`, update the `Methods` record type for `retrievePage`:

    retrievePage :: PageID -> [Text] -> IO PageObject,

And in `makeMethods`, the destructuring already binds `retrievePage` from the Servant client, so the type will automatically update. However, every existing call site that uses `retrievePage pageId` will now need `retrievePage pageId []`. The example in the module doc should also be updated.

Alternatively, to avoid breaking the simple call pattern, add a convenience wrapper in `makeMethods`:

    retrievePage pid = retrievePage_ pid []

and expose `retrievePageFiltered` for the full version. This preserves backward compatibility.

Verification: `cabal build all` succeeds. The example app and any call sites compile.


### Milestone 5 — Enum Completeness

At the end of this milestone, the library will recognize three additional rollup functions and two additional date filter conditions from the API.

**5a. Rollup functions** — In `src/Notion/V1/Properties.hs`, add three constructors to `RollupFunction`:

    | CountPerGroup
    | PercentPerGroup
    | Unique

Add parse cases in the `FromJSON` instance:

    "count_per_group" -> pure CountPerGroup
    "percent_per_group" -> pure PercentPerGroup
    "unique" -> pure Unique

Add serialize cases in the `ToJSON` instance:

    toJSON CountPerGroup = Aeson.String "count_per_group"
    toJSON PercentPerGroup = Aeson.String "percent_per_group"
    toJSON Unique = Aeson.String "unique"

**5b. Date filter conditions** — In `src/Notion/V1/Filter.hs`, add two constructors to `DateCondition`:

    | DateThisMonth
    | DateThisYear

Add serialize cases in `dateConditionToValue`:

    DateThisMonth -> Aeson.object ["this_month" .= Aeson.object []]
    DateThisYear -> Aeson.object ["this_year" .= Aeson.object []]

Verification: `cabal build all` succeeds, `cabal test tasty` passes.


### Milestone 6 — Tests

At the end of this milestone, every new type and field has at least one unit test confirming correct JSON round-tripping.

In `tasty/Main.hs`, add new test cases to the appropriate test groups.

**Block type tests** — Add to the JSON parsing tests group. For each new block type, define a JSON string literal and verify it parses to the expected `BlockContent` constructor. Then add round-trip tests.

`heading_4` parse and round-trip test: construct a `Heading4Block` with sample rich text, default color, non-toggleable, empty children. Encode to JSON, decode back, check equality.

`tab` parse and round-trip test: construct a `TabBlock` with a child paragraph. Round-trip it.

`meeting_notes` parse test: define a JSON object with type `"meeting_notes"` containing a title, status, and empty calendar_event/recording. Parse it and check the `meetingTitle` field.

`template` parse and round-trip test: construct a `TemplateBlock` with rich text and a child paragraph.

**Template mention test** — Add to a rich text or general parsing test group. Define a JSON string for a rich text object with `"type": "mention"` and `"mention": {"type": "template_mention", "template_mention": {"type": "template_mention_date", "template_mention_date": "today"}}`. Parse it and verify the `TemplateMentionDate "today"` constructor. Test the round-trip.

**PageObject field tests** — Extend the existing page parsing test to include `"is_locked": true` and `"is_archived": false` in the JSON. Verify the parsed `PageObject` has `isLocked = Just True` and `isArchived = Just False`.

**DataSourceParent test** — Add a parse test for a parent JSON with `"type": "data_source_id", "data_source_id": "...", "database_id": "..."`. Verify both fields are present in the parsed `DataSourceParent`.

**Column widthRatio test** — Add a round-trip test for `ColumnBlock` with `widthRatio = Just 0.5` and some children.

**BotUser test** — Add a parse test with `"workspace_id"` and `"workspace_limits"` fields.

**CreateComment test** — Add a serialization test verifying that `CreateComment` with attachments and display_name emits the expected JSON.

**UpdatePage test** — Add a serialization test verifying `isLocked` and `isArchived` appear in the JSON output.

**Rollup function test** — Add round-trip tests for `CountPerGroup`, `PercentPerGroup`, and `Unique`.

**Date condition test** — Add serialization tests for `DateThisMonth` and `DateThisYear`.

Verification: `cabal test tasty` passes with all new tests green.


## Concrete Steps

All commands are run from the project root: `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`.

After each milestone, run:

    cabal build all

Expected: compilation succeeds with no errors. Warnings are acceptable.

After each milestone, run:

    cabal test tasty

Expected: all tests pass. Integration tests may be skipped if environment variables are not set; that is fine.

After Milestone 6, run the full test suite one final time to confirm everything works together:

    cabal test tasty

Expected output (approximate):

    Test suite tasty: RUNNING...
    All N tests passed.
    Test suite tasty: PASS


## Validation and Acceptance

The change is considered complete when:

1. `cabal build all` compiles cleanly.
2. `cabal test tasty` passes all unit tests, including new tests for every gap addressed.
3. Every new block type (`heading_4`, `tab`, `meeting_notes`, `template`) round-trips through JSON without data loss.
4. A `template_mention` rich text object parses and serializes correctly.
5. `PageObject` preserves `isLocked` and `isArchived` as distinct fields.
6. `DataSourceParent` preserves the `databaseId` field.
7. `ColumnBlock` preserves the `widthRatio` field.
8. `BotUser` preserves `workspaceId` and `workspaceLimits`.
9. `CreateComment` can serialize with attachments and display_name.
10. `UpdatePage` can serialize with `isLocked` and `isArchived`.
11. The retrieve page endpoint accepts `filter_properties`.
12. Three new rollup functions parse without error.
13. Two new date filter conditions serialize correctly.


## Idempotence and Recovery

All changes are additive — new constructors, new fields (all `Maybe`), new enum variants. No existing constructors or fields are removed or renamed. If any milestone fails partway through, the previous milestone's commit is a clean state to restart from.

The `cabal build all` command is fully idempotent and can be run at any point to check compilation status.


## Interfaces and Dependencies

No new external dependencies are needed. All changes use existing imports (`Data.Aeson`, `Notion.Prelude`, etc.).

After all milestones, the following new types and functions will exist:

In `src/Notion/V1/BlockContent.hs`:
- `Heading4Block` constructor (same shape as `Heading1Block`)
- `TabBlock` constructor (`children :: Vector BlockContent`)
- `MeetingNotesBlock` constructor (`meetingTitle`, `meetingStatus`, `calendarEvent`, `recording`, `children`)
- `TemplateBlock` constructor (`richText`, `children`)
- `ColumnBlock` gains `widthRatio :: Maybe Double`

In `src/Notion/V1/RichText.hs`:
- `TemplateMentionDate` constructor (`templateMentionDate :: Text`)
- `TemplateMentionUser` constructor (`templateMentionUser :: Text`)

In `src/Notion/V1/Pages.hs`:
- `PageObject` gains `isLocked :: Maybe Bool`, `isArchived :: Maybe Bool`
- `UpdatePage` gains `isLocked :: Maybe Bool`, `isArchived :: Maybe Bool`
- Retrieve page Servant endpoint gains `QueryParams "filter_properties" Text`

In `src/Notion/V1/Common.hs`:
- `DataSourceParent` gains `parentDatabaseId :: Maybe UUID`

In `src/Notion/V1/Users.hs`:
- `WorkspaceLimits` new type (`maxFileUploadSizeInBytes :: Maybe Natural`)
- `BotUser` gains `workspaceId :: Maybe Text`, `workspaceLimits :: Maybe WorkspaceLimits`

In `src/Notion/V1/Comments.hs`:
- `CreateComment` gains `attachments :: Maybe (Vector CommentAttachment)`, `displayName :: Maybe CommentDisplayName`
- `ToJSON CommentAttachment` instance
- `ToJSON CommentDisplayName` instance

In `src/Notion/V1/Properties.hs`:
- `CountPerGroup`, `PercentPerGroup`, `Unique` constructors on `RollupFunction`

In `src/Notion/V1/Filter.hs`:
- `DateThisMonth`, `DateThisYear` constructors on `DateCondition`

In `src/Notion/V1.hs`:
- `Methods.retrievePage` signature updated to accept filter properties
