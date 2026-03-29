# Complete Notion API 2026-03-11 Upgrade

Intention: intention_01kmx8eeheepnvmesh2nv7m8qm

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, the notion-client library will be fully compliant with Notion API version `2026-03-11`. A user of the library will be able to use the new `position` parameter when appending block children (inserting at start, end, or after a specific block). All types will correctly use `in_trash` instead of `archived`, matching the API's response format. The `meeting_notes` block type will be documented as the replacement for `transcription`. Existing tests will be expanded with unit-level JSON parsing tests that validate the new response shapes, and the example app will be verified against the live API.


## Progress

### Milestone 1: Rename `archived` to `in_trash` across all types

- [x] Remove `archived` field from `BlockObject`, rename to `inTrash`, update `FromJSON`/`ToJSON` (2026-03-29)
- [x] Remove `archived` field from `PageObject` (keep `inTrash`), update `FromJSON`/`ToJSON` (2026-03-29)
- [x] Remove `archived` field from `DatabaseObject` (keep `inTrash`) (2026-03-29)
- [x] Remove `archived` field from `DataSourceObject` (keep `inTrash`) (2026-03-29)
- [x] Rename `archived` to `inTrash` in `UpdatePage`, update `mkUpdatePage` (2026-03-29)
- [x] Remove `archived` from `UpdateDatabase` (already has `inTrash`) (2026-03-29)
- [x] Remove `archived` from `UpdateDataSource` (already has `inTrash`) (2026-03-29)
- [x] Remove `archived` from `QueryDataSource` (already has `inTrash`) (2026-03-29)
- [x] Update example app references to `archived` field (2026-03-29)
- [x] Verify `cabal build all` compiles cleanly (2026-03-29)

### Milestone 2: Add `position` parameter to `AppendBlockChildren`

- [x] Define `Position` type with `AfterBlock`, `Start`, `End` constructors in `Blocks.hs` (2026-03-29)
- [x] Add optional `position` field to `AppendBlockChildren` (2026-03-29)
- [x] Export `Position(..)` from `Blocks` module (2026-03-29)
- [x] Update example app `appendBlockChildren` calls to use new type (2026-03-29)
- [x] Verify `cabal build all` compiles cleanly (2026-03-29)

### Milestone 3: Add JSON parsing unit tests

- [x] Add `bytestring` and `vector` to test dependencies in cabal file (2026-03-29)
- [x] Add `BlockObject` JSON parsing test with `in_trash` field (2026-03-29)
- [x] Add `BlockObject` JSON parsing test with legacy `archived` field — backward compat (2026-03-29)
- [x] Add `PageObject` JSON parsing test with `in_trash` field (2026-03-29)
- [x] Add `DatabaseObject` JSON parsing test with `in_trash` field (2026-03-29)
- [x] Add `DataSourceObject` JSON parsing test with `in_trash` field (2026-03-29)
- [x] Add `AppendBlockChildren` serialization test with `position` field (2026-03-29)
- [x] Add `Position` serialization tests for all three variants (2026-03-29)
- [x] Fix `<|>` with `.:?` bug — `.:?` always succeeds, so fallback never triggers (2026-03-29)
- [x] Verify `cabal test` passes — all 13 tests pass (2026-03-29)

### Milestone 4: Update CHANGELOG and manual testing

- [x] Update CHANGELOG.md with all breaking changes and new features (2026-03-29)
- [x] Integration tests pass against live API — user retrieval, list users, search, markdown (2026-03-29)
- [x] `cabal run notion-client-example` passes — all operations successful (user, database, data source, page, blocks, comments, search) (2026-03-29)
- [ ] Bump version if appropriate


## Surprises & Discoveries

- The existing `<|>` fallback pattern `(o .:? "in_trash" <|> o .:? "archived")` was silently broken: `.:?` always succeeds with `Nothing` for missing keys, so `<|>` never tried the alternatives. The legacy `archived` test caught this. Fixed by switching to `(o .: "in_trash") <|> (o .: "archived") <|> pure False` which correctly fails on missing keys and triggers the fallback chain. This means the pre-existing `FromJSON` parsers for `PageObject`, `DatabaseObject`, and `DataSourceObject` also had this latent bug with their old `is_archived`/`archived` fallback — now fixed.


## Decision Log

- Decision: Treat `archived` removal as a breaking change to the library's public API, since record fields like `PageObject.archived` are removed.
  Rationale: Users who pattern-match on `archived` will get compile errors. This is the correct behavior — the Notion API no longer returns this field in 2026-03-11, so keeping it would be misleading.
  Date: 2026-03-29

- Decision: Keep backward-compatible FromJSON parsing for `in_trash` in response types, falling back to `archived` and `is_archived`.
  Rationale: Users might cache or replay old API responses. Parsing should be tolerant of older response shapes while the Haskell record fields reflect the current API shape.
  Date: 2026-03-29

- Decision: Block types (`type_ :: Text`) are dynamically typed, so the `transcription` → `meeting_notes` rename requires no code changes, only documentation.
  Rationale: The codebase uses `Text` for block type names and stores block content under a dynamic key. There are no enum constructors for specific block types.
  Date: 2026-03-29

- Decision: Add unit tests that parse JSON fixtures rather than only integration tests against the live API.
  Rationale: Unit tests can run without a NOTION_TOKEN and validate JSON parsing logic deterministically. Integration tests remain for end-to-end verification.
  Date: 2026-03-29


## Outcomes & Retrospective

All milestones complete. 13 tests pass (5 JSON parsing, 4 serialization, 4 integration). Full example app runs against live API with all operations succeeding (user, database, data source CRUD, page creation, block appending, comments, search).

Key outcomes:
- `archived` field fully removed from all types, replaced by `inTrash`
- `Position` type added for block insertion control (`AfterBlock`, `Start`, `End`)
- Latent `<|>` + `.:?` bug discovered and fixed — backward-compatible parsing now actually works
- `transcription` → `meeting_notes` rename requires no code change (block types are `Text`)


## Context and Orientation

The notion-client library is a Haskell package at the repository root. It uses Servant for type-safe API bindings to the Notion REST API. The current version is 0.2.0.0 and the API version string is already set to `"2026-03-11"` in `src/Notion/V1.hs`, but the types and serialization have not been fully updated to match the 2026-03-11 API specification.

The Notion API 2026-03-11 upgrade guide describes three breaking changes:

1. **Block positioning**: The `after` string parameter on the Append Block Children endpoint is replaced by a `position` object with three placement types: `after_block` (insert after a specific block), `start` (insert at beginning), and `end` (insert at end, the default).

2. **Trash status**: The `archived` field is renamed to `in_trash` across all API responses and request parameters. This applies to pages, databases, blocks, and data sources.

3. **Block type rename**: The `transcription` block type is renamed to `meeting_notes`. Since this library represents block types as `Text` values (not a closed enum), no code change is needed — just documentation awareness.

The key source files involved are:

- `src/Notion/V1/Blocks.hs` — `BlockObject` (has `archived` field), `AppendBlockChildren` (missing `position` field)
- `src/Notion/V1/Pages.hs` — `PageObject` (has both `archived` and `inTrash`), `UpdatePage` (has `archived`, missing `inTrash`)
- `src/Notion/V1/Databases.hs` — `DatabaseObject` (has both `archived` and `inTrash`), `UpdateDatabase` (has both)
- `src/Notion/V1/DataSources.hs` — `DataSourceObject` (has both), `UpdateDataSource` (has both), `QueryDataSource` (has both)
- `src/Notion/V1.hs` — API version string, `Methods` record
- `tasty/Main.hs` — Test suite (currently integration-only)
- `notion-client-example/DatabaseDemo.hs` — Example code that may reference `archived`
- `CHANGELOG.md` — Release notes

The library uses custom `FromJSON` instances (not generics) for response types. Request types use `genericToJSON aesonOptions` which converts camelCase field names to snake_case (e.g., `inTrash` → `in_trash`). The `aesonOptions` also sets `omitNothingFields = True`.

The test suite in `tasty/Main.hs` uses tasty + tasty-hunit and only contains integration tests that require a `NOTION_TOKEN` environment variable. There are no unit-level JSON parsing tests yet.


## Plan of Work

### Milestone 1: Rename `archived` to `in_trash` across all types

This milestone removes every `archived` field from response and request types, ensuring the library's public API reflects the 2026-03-11 JSON shape. After this milestone, `cabal build all` must compile cleanly, meaning the example app must also be updated.

**`src/Notion/V1/Blocks.hs`**: The `BlockObject` record has `archived :: Bool`. Rename this field to `inTrash :: Bool`. In the `FromJSON` instance (line 53), change the parser from:

    archived <- fmap (fromMaybe False) (o .:? "is_archived" <|> o .:? "archived")

to:

    inTrash <- fmap (fromMaybe False) (o .:? "in_trash" <|> o .:? "is_archived" <|> o .:? "archived")

In the `ToJSON` instance (line 71), change `"archived" .= archived` to `"in_trash" .= inTrash`.

**`src/Notion/V1/Pages.hs`**: The `PageObject` record has both `archived :: Bool` and `inTrash :: Bool`. Remove the `archived` field entirely. In the `FromJSON` instance (line 68), remove the `archived` parser line. Update the `inTrash` parser to also fall back to `is_archived` and `archived`:

    inTrash <- fmap (fromMaybe False) (o .:? "in_trash" <|> o .:? "is_archived" <|> o .:? "archived")

In the `ToJSON` instance, remove the `"archived" .= archived` line.

The `UpdatePage` record has `archived :: Maybe Bool`. Rename this to `inTrash :: Maybe Bool`. Update the `mkUpdatePage` smart constructor accordingly, setting `inTrash = Nothing`. Since `genericToJSON aesonOptions` is used, this will automatically serialize to `"in_trash"` in the JSON output.

**`src/Notion/V1/Databases.hs`**: The `DatabaseObject` record has both `archived :: Maybe Bool` and `inTrash :: Maybe Bool`. Remove the `archived` field. In the `FromJSON` instance (line 85), remove the `archived` parser. Update the `inTrash` parser to fall back:

    inTrash <- o .:? "in_trash" <|> o .:? "is_archived" <|> o .:? "archived"

The `UpdateDatabase` record has both `archived :: Maybe Bool` and `inTrash :: Maybe Bool`. Remove the `archived` field.

**`src/Notion/V1/DataSources.hs`**: The `DataSourceObject` record has both `archived :: Maybe Bool` and `inTrash :: Maybe Bool`. Remove the `archived` field. In the `FromJSON` instance (line 70), remove the `archived` parser. Update the `inTrash` parser:

    inTrash <- o .:? "in_trash" <|> o .:? "is_archived" <|> o .:? "archived"

The `UpdateDataSource` record has both `archived :: Maybe Bool` and `inTrash :: Maybe Bool`. Remove the `archived` field.

The `QueryDataSource` record has both `archived :: Maybe Bool` and `inTrash :: Maybe Bool`. Remove the `archived` field.

**`notion-client-example/DatabaseDemo.hs`**: Update the `QueryDataSource` construction (line 63-70) to remove `archived = Nothing`. Update the `UpdateDataSource` construction (line 154-162) to remove `archived = Nothing`.

Acceptance: `cabal build all` compiles with no errors.


### Milestone 2: Add `position` parameter to `AppendBlockChildren`

This milestone adds support for the new `position` object on the Append Block Children endpoint. After this milestone, users can specify where new blocks are inserted relative to existing blocks.

**`src/Notion/V1/Blocks.hs`**: Define a new `Position` sum type with three constructors:

    data Position
      = AfterBlock UUID
      | Start
      | End
      deriving stock (Generic, Show)

The `ToJSON` instance must produce the exact JSON shape the API expects:

- `AfterBlock blockId` → `{"type": "after_block", "after_block": {"id": "<blockId>"}}`
- `Start` → `{"type": "start", "start": {}}`
- `End` → `{"type": "end", "end": {}}`

Change `AppendBlockChildren` from a `newtype` to a `data` type with two fields:

    data AppendBlockChildren = AppendBlockChildren
      { children :: Vector Value,
        position :: Maybe Position
      }

Update the `ToJSON` instance. Since `aesonOptions` has `omitNothingFields = True` and `Position` needs a custom `ToJSON`, write a manual `ToJSON`:

    instance ToJSON AppendBlockChildren where
      toJSON AppendBlockChildren {..} =
        Aeson.object $
          ["children" .= children]
            <> maybe [] (\p -> ["position" .= p]) position

Import `UUID` from `Notion.V1.Common` (it is already indirectly available via `BlockID`).

Update the module's export list to include `Position(..)`.

**`notion-client-example/DatabaseDemo.hs`** and **`notion-client-example/PageDemo.hs`**: Update `AppendBlockChildren` constructions to include `position = Nothing` (preserving existing behavior of appending at the end).

Acceptance: `cabal build all` compiles. The `Position` type serializes correctly (verified by tests in Milestone 3).


### Milestone 3: Add JSON parsing unit tests

This milestone adds unit tests that validate JSON parsing without needing a live API token. The tests parse JSON fixtures that match the 2026-03-11 response format and verify the Haskell types are populated correctly.

**`notion-client.cabal`**: Add `bytestring` to the test-suite build-depends (it is already transitively available but should be explicit for `Data.ByteString.Lazy`).

**`tasty/Main.hs`**: Add a new test group `"JSON Parsing"` that contains:

1. A test that parses a `BlockObject` JSON fixture with `in_trash` field (not `archived`) and verifies `inTrash` is parsed correctly.

2. A test that parses a `PageObject` JSON fixture with `in_trash` field and verifies `inTrash` is parsed correctly and there is no `archived` field on the record.

3. A test that parses a `DatabaseObject` JSON fixture with `in_trash` field.

4. A test that parses a `DataSourceObject` JSON fixture with `in_trash` field.

5. A test that serializes `AppendBlockChildren` with various `Position` values and verifies the JSON output matches the expected shape.

6. A test that serializes `AppendBlockChildren` with `position = Nothing` and verifies no `position` key appears in the output.

Each test constructs a JSON `ByteString` literal, decodes it with `Data.Aeson.eitherDecode`, and asserts on the parsed record fields. For serialization tests, encode the value and compare against expected JSON structure.

Acceptance: `cabal test` passes with all new tests green.


### Milestone 4: Update CHANGELOG and manual testing

Update `CHANGELOG.md` to document all breaking changes from this work:

- Removed `archived` field from `BlockObject`, `PageObject`, `DatabaseObject`, `DataSourceObject` — use `inTrash` instead
- Removed `archived` field from `UpdatePage`, `UpdateDatabase`, `UpdateDataSource`, `QueryDataSource` — use `inTrash` instead
- Changed `AppendBlockChildren` from `newtype` to `data` with new optional `position` field
- Added `Position` type (`AfterBlock`, `Start`, `End`) for block placement
- Noted `transcription` block type renamed to `meeting_notes` by the API (no library code change needed)

Run `cabal run notion-client-example` with `NOTION_TOKEN` set and verify the example app works against the live API. If `NOTION_TEST_DATABASE_ID` and `NOTION_TEST_PAGE_ID` are available, run the full demo. Record the output as evidence.

Run `cabal test` with `NOTION_TOKEN` set to verify both unit and integration tests pass.

Acceptance: CHANGELOG is accurate. Example app runs without errors. All tests pass.


## Concrete Steps

All commands are run from the repository root: `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`.

After each milestone, verify the build:

    cabal build all

Expected output should end with a line like:

    Building library for notion-client-0.2.0.0..
    [X of Y] Compiling ...

with no errors.

After Milestone 3, run tests:

    cabal test

Expected output:

    Test suite tasty: RUNNING...
    Notion API Tests
      JSON Parsing
        Parse BlockObject with in_trash:     OK
        Parse PageObject with in_trash:      OK
        ...
    All X tests passed.

After Milestone 4, run the example:

    NOTION_TOKEN=<token> cabal run notion-client-example

(Output will be recorded during implementation.)


## Validation and Acceptance

The upgrade is complete when:

1. `cabal build all` compiles with no errors or warnings related to the changes.
2. `cabal test` passes all JSON parsing unit tests (no NOTION_TOKEN required for unit tests).
3. `cabal test` passes all integration tests (NOTION_TOKEN required).
4. `cabal run notion-client-example` runs without errors against the live Notion API.
5. The CHANGELOG accurately describes all breaking changes.
6. No `archived` field remains in any response or request type (only `inTrash`).
7. `AppendBlockChildren` supports the optional `position` field.
8. All `Position` variants serialize to the correct JSON shape.


## Idempotence and Recovery

All changes are to source files and can be reverted with `git checkout -- .`. The changes are purely additive/subtractive to types and serialization; no migrations, no external state changes. Each milestone can be re-applied independently. The build can be verified at any point with `cabal build all`.


## Interfaces and Dependencies

No new library dependencies are needed. The existing dependencies (`aeson`, `servant`, `vector`, `containers`, `text`) are sufficient.

After Milestone 1, these types will have their `archived` field removed:

    -- In src/Notion/V1/Blocks.hs:
    data BlockObject = BlockObject { ..., inTrash :: Bool, ... }

    -- In src/Notion/V1/Pages.hs:
    data PageObject = PageObject { ..., inTrash :: Bool, ... }  -- archived removed
    data UpdatePage = UpdatePage { ..., inTrash :: Maybe Bool, ... }  -- archived → inTrash

    -- In src/Notion/V1/Databases.hs:
    data DatabaseObject = DatabaseObject { ..., inTrash :: Maybe Bool, ... }  -- archived removed
    data UpdateDatabase = UpdateDatabase { ..., inTrash :: Maybe Bool, ... }  -- archived removed

    -- In src/Notion/V1/DataSources.hs:
    data DataSourceObject = DataSourceObject { ..., inTrash :: Maybe Bool, ... }  -- archived removed
    data UpdateDataSource = UpdateDataSource { ..., inTrash :: Maybe Bool, ... }  -- archived removed
    data QueryDataSource = QueryDataSource { ..., inTrash :: Maybe Bool, ... }  -- archived removed

After Milestone 2, these new types will exist:

    -- In src/Notion/V1/Blocks.hs:
    data Position = AfterBlock UUID | Start | End

    data AppendBlockChildren = AppendBlockChildren
      { children :: Vector Value,
        position :: Maybe Position
      }
