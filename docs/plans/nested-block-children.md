# Add recursive children to BlockContent

Intention: intention_01kmzr1mw7e2aaravasaa15jks

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

The Notion API allows blocks to contain child blocks. A toggle block reveals its children on click; a column list contains column blocks which themselves contain content blocks; a bulleted list item can nest sub-items. Today the library's `BlockContent` type has no `children` field — users who want to create a toggle with nested content must make two API calls (create the toggle, then append children to it by ID).

After this change, users will be able to build nested block trees in a single expression and send them in one API call:

    let toggle = ToggleBlock
          { richText = mkRichText "Click to expand"
          , color = Default
          , children = Vector.fromList
              [ textBlock "Hidden paragraph one"
              , textBlock "Hidden paragraph two"
              ]
          }

    appendBlockChildren pageId (AppendBlockChildren (Vector.singleton toggle) Nothing)

This is observable by running the example app and the e2e tests, which will create blocks with inline children and verify they appear correctly in Notion.


## Progress

- [x] Add `children :: Vector BlockContent` field to all constructors that support children (14 constructors) — 2026-03-30
- [x] Update `blockContentFields` to serialize children when non-empty — 2026-03-30
- [x] Update `parseBlockContent` to parse optional children — 2026-03-30
- [x] Update smart constructors to default children to `Vector.empty` — 2026-03-30
- [x] Add `withChildren` combinator for ergonomic child attachment — 2026-03-30
- [x] Update `FromJSON BlockContent` (standalone) to handle recursive children — 2026-03-30 (recursive parsing works via existing `FromJSON BlockContent` instance; `parseBlockContent` now parses `children` field)
- [x] Update round-trip tests — 2026-03-30
- [x] Add new unit tests for nested block serialization — 2026-03-30 (4 new tests: nested toggle, nested column list, withChildren combinator, no-children-key assertion)
- [x] Add e2e test: create toggle with nested children, verify via listBlockChildren — 2026-03-30
- [x] Update BlockDemo example with nested block examples — 2026-03-30 (toggle with children, nested bulleted list, column layout)
- [x] Verify full build: `cabal build all && cabal test` — 2026-03-30 (all 87 tests pass)


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Use `Vector BlockContent` (not `Maybe (Vector BlockContent)`) for the children field.
  Rationale: An empty vector naturally means "no children" and serialization omits the field when empty. This avoids wrapping every children value in `Just`/`Nothing` and is consistent with how `richText` and `caption` fields already work (they use `Vector RichText` and default to empty). During parsing, absent `children` fields default to `Vector.empty`.
  Date: 2026-03-30

- Decision: Add children only to constructors where the Notion API supports them, not to all constructors.
  Rationale: Block types like `CodeBlock`, `EquationBlock`, `ImageBlock`, `DividerBlock`, `BookmarkBlock`, and `EmbedBlock` do not support children in the API. Adding a children field to these would be misleading — the API would reject the request. Keeping the type honest about which blocks can have children prevents runtime errors.
  Date: 2026-03-30

- Decision: Do not enforce child-type constraints or nesting depth at the Haskell type level.
  Rationale: The Notion API enforces structural rules (e.g., `column_list` children must be `column` blocks; `table` children must be `table_row` blocks; `column_list` must have at least 2 children). Additionally, a single API request allows at most two levels of nesting (the official SDK models this with a three-tier type hierarchy: `BlockObjectRequest` → children → grandchildren with no children). Encoding these constraints in Haskell's type system would require GADTs or type families, adding significant complexity for marginal benefit. The API provides clear error messages when constraints are violated. Document the constraints in Haddock comments instead. Deeper nesting is achievable via multiple API calls.
  Date: 2026-03-30

- Decision: Include toggleable headings in the set of constructors that receive children.
  Rationale: The Notion API supports children on `heading_1/2/3` blocks when `is_toggleable` is true. The API rejects children on non-toggleable headings at request time. Since our type system does not distinguish toggleable from non-toggleable headings at the type level (both use the same constructor with an `isToggleable :: Bool` field), adding `children` to heading constructors is consistent and lets users create toggleable headings with inline content. The API will reject the request if `is_toggleable` is false and children are provided.
  Date: 2026-03-30

- Decision: Provide a `withChildren` combinator rather than modifying all smart constructors.
  Rationale: The existing smart constructors (`paragraphBlock`, `toggleBlock`, etc.) return childless blocks, which is the common case. Adding a children parameter would change every smart constructor's signature — a large breaking change for little benefit. Instead, provide `withChildren :: BlockContent -> Vector BlockContent -> BlockContent` that attaches children to an existing block. This composes well: `toggleBlock (mkRichText "Click") \`withChildren\` Vector.fromList [textBlock "inner"]`.
  Date: 2026-03-30


## Outcomes & Retrospective

Implementation completed in a single pass. All 14 constructors received children fields, serialization omits the field when empty (verified by unit test), and the recursive JSON parsing works through the existing `FromJSON BlockContent` instance. The e2e test confirmed that creating a toggle with inline children via a single `appendBlockChildren` call works correctly — the API returns `has_children = True` and `listBlockChildren` on the toggle returns the 2 child paragraphs. All 87 tests pass (4 new unit tests + 1 new e2e step).


## Context and Orientation

This plan builds on the typed block content work completed in `docs/plans/typed-block-content.md`. That plan introduced the `BlockContent` sum type in `src/Notion/V1/BlockContent.hs` with ~30 constructors, replacing the untyped `Value` that was previously used for block content. The plan explicitly deferred recursive children as a follow-up enhancement.

The `BlockContent` type currently lives in `src/Notion/V1/BlockContent.hs` (~600 lines). Each constructor represents a Notion block type and carries the type-specific fields. For example:

    ToggleBlock
      { richText :: Vector RichText,
        color :: Color
      }

The Notion API supports inline children during block creation. When you create or append blocks via `POST /v1/blocks/{id}/children`, the request body can include a `children` array nested inside the block type content. For example, creating a toggle with children:

    {
      "type": "toggle",
      "toggle": {
        "rich_text": [{"text": {"content": "Click to expand"}}],
        "children": [
          {
            "type": "paragraph",
            "paragraph": {"rich_text": [{"text": {"content": "Inner content"}}]}
          }
        ]
      }
    }

The `children` array contains full block objects (with `type` and the type-keyed content), using the same format as top-level blocks in the append request. This makes the structure naturally recursive.

When reading blocks back from the API via `GET /v1/blocks/{id}` or `GET /v1/blocks/{id}/children`, the response does NOT include inline children. Instead, the `has_children` boolean field on `BlockObject` indicates whether children exist, and they must be fetched separately via `GET /v1/blocks/{child_block_id}/children`. This means `parseBlockContent` will typically see an absent or empty `children` field in API responses.

The following block types support children in creation payloads (based on the Notion API documentation and SDK type definitions):

**Text blocks with children:** `paragraph`, `bulleted_list_item`, `numbered_list_item`, `to_do`, `toggle`, `quote`, `callout`. These accept any block type as children. Toggle blocks are the most common use case for inline children.

**Heading blocks (conditionally):** `heading_1`, `heading_2`, `heading_3` support children when `is_toggleable` is `true`. The API rejects children on non-toggleable headings.

**Structural blocks with constrained children:** `column_list` (children must be `column` blocks, minimum 2), `column` (children can be any block type), `table` (children must be `table_row` blocks, count must match `table_width`).

**Synced blocks:** `synced_block` with `synced_from: null` (original) supports children. References (`synced_from: { block_id: "..." }`) do not.

**Block types that do NOT support children:** `code`, `equation`, `image`, `video`, `audio`, `file`, `pdf`, `bookmark`, `embed`, `link_to_page`, `link_preview`, `divider`, `breadcrumb`, `table_of_contents`, `table_row`, `child_page`, `child_database`.

The nesting depth limit is 2 levels in a single API request. The official Notion SDK models this with a three-tier type hierarchy: top-level blocks can have children, those children can have grandchildren, but grandchildren cannot have further children. This means you can create a toggle with paragraph children, but a toggle containing a toggle containing a paragraph must be done in multiple API calls. The maximum number of block children per request is 100. There is no overall depth limit in the Notion data model — deeper nesting is achieved via sequential API calls.

Existing infrastructure that remains unchanged: `BlockObject` in `src/Notion/V1/Blocks.hs` (the API response type with `has_children :: Bool`), `AppendBlockChildren` (already uses `Vector BlockContent`), `CreatePage.children` in `src/Notion/V1/Pages.hs` (already uses `Maybe (Vector BlockContent)`), the `BlockUpdate` newtype, and all Servant API wiring.

Key files that will be modified:

- `src/Notion/V1/BlockContent.hs` — add `children` field to applicable constructors, update `blockContentFields`, `parseBlockContent`, smart constructors, add `withChildren`.
- `tasty/Main.hs` — update existing tests for new fields, add nested block tests.
- `notion-client-example/BlockDemo.hs` — add nested block examples.


## Plan of Work

The work is a single milestone since all changes are in the `BlockContent` module, its tests, and the example code. The changes are additive within the module (new fields on existing constructors) and mechanically propagated to tests and examples.


### Milestone 1: Add children to BlockContent

This milestone adds a `children :: Vector BlockContent` field to the constructors that support children, updates serialization and parsing, adds a `withChildren` combinator, and updates all tests and examples.

**Step 1: Add children fields to constructors.** In `src/Notion/V1/BlockContent.hs`, add `children :: Vector BlockContent` as the last field of each constructor that supports children. The affected constructors are:

`ParagraphBlock` — add `children` after `paragraphIcon`. `Heading1Block` — add `children` after `isToggleable`; note in Haddock that children are only accepted by the API when `isToggleable` is `True`. `Heading2Block` — same as `Heading1Block`. `Heading3Block` — same as `Heading1Block`. `BulletedListItemBlock` — add `children` after `color`. `NumberedListItemBlock` — add `children` after `listStartIndex`. `ToDoBlock` — add `children` after `checked`. `ToggleBlock` — add `children` after `color`. `QuoteBlock` — add `children` after `color`. `CalloutBlock` — add `children` after `calloutIcon`. `ColumnListBlock` — currently has no fields; becomes a record with `children`. Add a Haddock note that children must be `ColumnBlock` values with at least 2 entries. `ColumnBlock` — currently has no fields; becomes a record with `children`. `TableBlock` — add `children` after `hasRowHeader`. Add a Haddock note that children must be `TableRowBlock` values. `SyncedBlockContent` — add `children` after `syncedFrom`. Note that children are only valid when `syncedFrom` is `SyncedOriginal`.

That is 14 constructors total.

Constructors that do NOT get children: `CodeBlock`, `EquationBlock`, `ImageBlock`, `VideoBlock`, `AudioBlock`, `FileBlock`, `PdfBlock`, `BookmarkBlock`, `EmbedBlock`, `LinkToPageBlock`, `LinkPreviewBlock`, `DividerBlock`, `BreadcrumbBlock`, `TableOfContentsBlock`, `TableRowBlock`, `ChildPageBlock`, `ChildDatabaseBlock`, `UnsupportedBlock`, `UnknownBlock`.

**Step 2: Update `blockContentFields`.** For each constructor that gained a `children` field, update the serialization to include `"children" .= children` only when the vector is non-empty. This is done with the pattern already used elsewhere in the module:

    <> if Vector.null children then [] else ["children" .= children]

This ensures that blocks without children serialize identically to the current format (no `children` key), while blocks with children include the nested array. The children themselves are serialized via `BlockContent`'s `ToJSON` instance, which produces the full discriminated union format (`{"type": "paragraph", "paragraph": {...}}`). This is correct because children in the API use the same format as top-level blocks.

For `ColumnListBlock` and `ColumnBlock`, the inner content was previously `object []` (empty object). With children, it becomes `object $ if Vector.null children then [] else ["children" .= children]`.

**Step 3: Update `parseBlockContent`.** For each constructor that supports children, parse the `children` field as optional, defaulting to `Vector.empty`:

    children <- fromMaybe Vector.empty <$> o .:? "children"

The `FromJSON BlockContent` instance handles the recursion: when `o .:? "children"` parses the array, each element is parsed via `FromJSON BlockContent`, which reads the `type` field and dispatches to `parseBlockContent`. This is standard recursive JSON parsing in aeson.

**Step 4: Update smart constructors.** Each smart constructor that returns a constructor with children must pass `Vector.empty` for the new field. For example:

    paragraphBlock :: Vector RichText -> BlockContent
    paragraphBlock rt = ParagraphBlock rt Default Nothing Vector.empty

    toggleBlock :: Vector RichText -> BlockContent
    toggleBlock rt = ToggleBlock rt Default Vector.empty

    bulletedListItemBlock :: Vector RichText -> BlockContent
    bulletedListItemBlock rt = BulletedListItemBlock rt Default Vector.empty

The `textBlock` smart constructor delegates to `paragraphBlock` and needs no change.

**Step 5: Add the `withChildren` combinator.** Define a function that attaches children to a block:

    withChildren :: BlockContent -> Vector BlockContent -> BlockContent

This function pattern-matches on the constructor and sets the `children` field. For constructors that do not support children, it returns the block unchanged (or could fail — but silently returning is more ergonomic for composition). Usage:

    toggleBlock (mkRichText "Click me") `withChildren` Vector.fromList
      [ textBlock "First child"
      , textBlock "Second child"
      ]

The implementation is a case expression over all constructors. For constructors with children, it sets the field. For constructors without children, it returns the input unchanged. Export `withChildren` from the module.

**Step 6: Update round-trip tests.** The existing round-trip tests in `tasty/Main.hs` construct `BlockContent` values and verify `fromJSON (toJSON x) == x`. The tests for constructors that gained children still work because the smart constructors default children to empty. Add new tests:

A test for a toggle block with nested children: construct a `ToggleBlock` with two paragraph children, serialize, parse back, verify equality.

A test for a column list with column children: construct a `ColumnListBlock` with two `ColumnBlock` children (each containing a paragraph), serialize, parse back, verify equality.

A test verifying that `withChildren` produces the expected structure.

A test verifying that `BlockUpdate` (for PATCH endpoint) also correctly serializes nested children.

**Step 7: Add e2e test.** In `tasty/Main.hs`, within the block lifecycle e2e test, add a step that creates a toggle block with inline children via `appendBlockChildren`, then fetches the toggle's children via `listBlockChildren` and verifies they exist.

**Step 8: Update BlockDemo example.** In `notion-client-example/BlockDemo.hs`, add a new section "Nested Blocks" that demonstrates:

Creating a toggle with two paragraph children using `withChildren`. Creating a column layout with two columns, each containing a paragraph. Creating a bulleted list with nested sub-items.

Then reading the blocks back and showing that `has_children` is true on the parent blocks.

**Verification.** Run:

    cabal build all

All targets must compile. Then:

    cabal test

All tests must pass, including the new round-trip tests and the e2e test with nested children.

    cabal run notion-client-example

The block demo section should show nested blocks being created and read back successfully.


## Concrete Steps

All commands are run from the repository root: `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`.

After modifying `src/Notion/V1/BlockContent.hs`:

    cabal build notion-client

Expected: clean compilation. If constructors gained new fields, pattern matches in `Blocks.hs` and test code will need updating.

After all changes:

    cabal build all && cabal test

Expected: clean compilation and all tests passing.

    cabal run notion-client-example

Expected: nested block demo creates blocks with children, reads them back, and shows `has_children` as `True`.


## Validation and Acceptance

The change is accepted when:

1. `cabal build all` compiles with no new errors or warnings.

2. `cabal test` passes all tests, including new round-trip tests for nested `BlockContent` values.

3. A toggle block with inline children can be created in a single API call:

        let toggle = toggleBlock (mkRichText "Expand") `withChildren`
              Vector.fromList [textBlock "Child 1", textBlock "Child 2"]
        appendBlockChildren pageId (AppendBlockChildren (Vector.singleton toggle) Nothing)

   The returned block list shows `has_children = True` on the toggle block, and `listBlockChildren` on the toggle returns the two child paragraphs.

4. Pattern matching on blocks with children works:

        case content block of
          ToggleBlock {richText, children} -> ...
          ParagraphBlock {richText, children} -> ...

5. Blocks without children serialize identically to before (no `children` key in JSON output).

6. The `withChildren` combinator is exported and usable.


## Idempotence and Recovery

All changes are to existing source files and are safe to repeat. Adding fields to constructors is a compile-time breaking change that is caught immediately. If the build fails after partial changes, continuing with the remaining steps resolves it. `git stash` or `git checkout` reverts to the previous compiling state.


## Interfaces and Dependencies

No new external dependencies. The change is entirely within `src/Notion/V1/BlockContent.hs` and its consumers.

The key interface change is the addition of a `children` field to 14 constructors of `BlockContent`, plus one new exported function:

In `src/Notion/V1/BlockContent.hs`:

    -- Updated constructors (showing only the added field):
    ParagraphBlock { ..., children :: Vector BlockContent }
    Heading1Block { ..., children :: Vector BlockContent }
    Heading2Block { ..., children :: Vector BlockContent }
    Heading3Block { ..., children :: Vector BlockContent }
    BulletedListItemBlock { ..., children :: Vector BlockContent }
    NumberedListItemBlock { ..., children :: Vector BlockContent }
    ToDoBlock { ..., children :: Vector BlockContent }
    ToggleBlock { ..., children :: Vector BlockContent }
    QuoteBlock { ..., children :: Vector BlockContent }
    CalloutBlock { ..., children :: Vector BlockContent }
    ColumnListBlock { children :: Vector BlockContent }
    ColumnBlock { children :: Vector BlockContent }
    TableBlock { ..., children :: Vector BlockContent }
    SyncedBlockContent { ..., children :: Vector BlockContent }

    -- New combinator
    withChildren :: BlockContent -> Vector BlockContent -> BlockContent

All existing smart constructors retain their signatures and default `children` to `Vector.empty`.
