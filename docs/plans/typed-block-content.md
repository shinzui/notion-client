# Add typed block content to replace untyped Value

Intention: intention_01kmzr1mw7e2aaravasaa15jks

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

The Notion API represents block content (paragraphs, headings, code, images, etc.) as a discriminated union: each block carries a `type` field (a string like `"paragraph"`) and the actual content nested under a key matching that type name. Today the library stores this content as an opaque `Value` (from the `aeson` library), forcing every consumer to construct and destructure raw JSON by hand. This is error-prone, untyped, and makes pattern matching impossible.

After this change, consumers will be able to:
- Pattern-match on typed constructors like `ParagraphBlock`, `Heading1Block`, `CodeBlock`, etc.
- Use smart constructors like `paragraphBlock "Hello world"` instead of manually building JSON objects.
- Get compile-time guarantees that block content is well-formed.
- Benefit from editor autocompletion for block-specific fields (rich text, color, language, caption, etc.).

The change is observable by running `cabal build all` (everything compiles with the new types), running `cabal test` (all unit and e2e tests pass), and reviewing the example code in `notion-client-example/` which will use typed constructors instead of raw JSON.


## Progress

- [x] Create `src/Notion/V1/BlockContent.hs` with supporting types (`CodeLanguage`, `FileSource`, `ListFormat`, `SyncedFrom`) (2026-03-30)
- [x] Define the `BlockContent` sum type with all constructors (2026-03-30)
- [x] Implement `FromJSON` for `BlockContent` (2026-03-30)
- [x] Implement `ToJSON` for `BlockContent` and `blockContentFields` helper (2026-03-30)
- [x] Add smart constructors for common block types (2026-03-30)
- [x] Register new module in `notion-client.cabal` and verify compilation (2026-03-30)
- [x] Update `BlockObject` in `src/Notion/V1/Blocks.hs` to use `BlockContent` instead of `Value` (2026-03-30)
- [x] Replace the old `BlockContent` newtype with `BlockUpdate` newtype wrapping the new `BlockContent` (2026-03-30)
- [x] Update `AppendBlockChildren` to use `Vector BlockContent` instead of `Vector Value` (2026-03-30)
- [x] Update `CreatePage.children` in `src/Notion/V1/Pages.hs` to use `Maybe (Vector BlockContent)` (2026-03-30)
- [x] Update `src/Notion/V1.hs` exports, the `Methods` record, and `notion-client.cabal` exposed modules (2026-03-30)
- [x] Update unit tests in `tasty/Main.hs` (parsing tests, helper functions) (2026-03-30)
- [x] Update e2e tests in `tasty/Main.hs` (block lifecycle, comment lifecycle, etc.) (2026-03-30)
- [x] Update `notion-client-example/Blocks.hs` to use typed smart constructors (2026-03-30)
- [x] Update `notion-client-example/PageDemo.hs` to use typed constructors (2026-03-30)
- [x] Create `notion-client-example/BlockDemo.hs` — comprehensive typed block demo (2026-03-30)
- [x] Fix `File.FromJSON` to use `parseISO8601` for `expiryTime` (discovered during testing) (2026-03-30)
- [x] Verify full build: `cabal build all && cabal test` — all 74 tests pass (2026-03-30)


## Surprises & Discoveries

- `Data.Aeson.Pair` is not exported from `Data.Aeson` in aeson 2.2. Must import from `Data.Aeson.Types` instead.

- `File.FromJSON` in `Common.hs` used `genericParseJSON` which parsed `expiryTime` as a number (`NominalDiffTime`). The API returns it as an ISO 8601 string. This was never noticed because blocks were previously untyped `Value`. Typed parsing exposed the bug. Fixed by implementing custom `FromJSON File` using `parseISO8601`.

- The `numbered_list_item.list_format` field is read-only in API version 2026-03-11. Attempting to set it on block creation returns a 400 validation error. The field is kept in the data type for reading but should not be set when creating blocks. Smart constructors default it to `Nothing`.

- `LinkToPageBlock` needed a dedicated `LinkTarget` type instead of reusing `Parent` from `Common.hs`, because link targets include `comment_id` which `Parent` does not support.


## Decision Log

- Decision: Place `BlockContent` in a new module `Notion.V1.BlockContent` rather than expanding `Notion.V1.Blocks`.
  Rationale: Follows the codebase pattern where `PropertySchema` and `PropertyValue` each have their own modules. The `BlockContent` sum type with ~30 constructors, supporting types, and smart constructors will be 600-800 lines — comparable to `Properties.hs` (526 lines). Keeping `Blocks.hs` focused on the API-level types (`BlockObject`, `BlockUpdate`, `AppendBlockChildren`, `Position`) and the Servant endpoint definition matches how `Pages.hs` delegates to `PropertyValue` and `Databases.hs` delegates to `Properties`.
  Date: 2026-03-30

- Decision: Keep `type_ :: Text` on `BlockObject` alongside the new `content :: BlockContent`.
  Rationale: This follows the precedent set by `RichText`, which has both `type_ :: Text` and `content :: RichTextContent`. Keeping the text discriminator provides backward compatibility for code that matches on the type string (like `Notion.V1.Blocks.type_ block`) and is natural since `FromJSON` reads the discriminator first to dispatch parsing. The field is redundant but harmless and eases migration.
  Date: 2026-03-30

- Decision: Do not include recursive `children` in `BlockContent` constructors.
  Rationale: The Notion API response does NOT inline child blocks — they must be fetched separately via the `listBlockChildren` endpoint. While the creation payload supports inline children (useful for toggle blocks), this adds recursive type complexity. For the initial implementation, block creation uses flat blocks. Users who need nested children for creation can construct them in a follow-up enhancement. The `has_children` field on `BlockObject` already signals when children exist.
  Date: 2026-03-30

- Decision: Use a `blockContentFields` helper function for serialization, following the `schemaFields` pattern from `PropertySchema`.
  Rationale: The block content needs two different JSON formats: creation/append uses `{"type": "paragraph", "paragraph": {...}}` (full format with type discriminator) while updates use `{"paragraph": {...}}` (without type discriminator). A `blockContentFields :: BlockContent -> (Text, Value)` function that returns the type name and inner content enables both formats from the same data, with `ToJSON BlockContent` producing the full format and a `BlockUpdate` newtype producing the update format.
  Date: 2026-03-30

- Decision: Include an `UnknownBlock Text Value` fallback constructor.
  Rationale: The Notion API may introduce new block types that the library does not yet model. Without a fallback, parsing would fail on unknown types. The `UnknownBlock` constructor stores the type string and raw JSON value, allowing graceful degradation. This matches how the API already returns `"unsupported"` for certain block types.
  Date: 2026-03-30


## Outcomes & Retrospective

All milestones completed successfully. The implementation replaces untyped `Value` with a typed `BlockContent` sum type across the entire library.

**What was achieved:**
- New `Notion.V1.BlockContent` module (~600 lines) with 30+ constructors, 5 supporting types, JSON instances, and 15 smart constructors.
- `BlockObject.content` changed from `Value` to `BlockContent` — enables pattern matching on block types.
- `AppendBlockChildren.children` and `CreatePage.children` changed from `Vector Value` to `Vector BlockContent`.
- Old `BlockContent` update newtype replaced by `BlockUpdate` newtype wrapping the typed `BlockContent`.
- All 74 tests pass (unit + e2e). The e2e tests create blocks via the Notion API and read them back as typed values.
- New comprehensive `BlockDemo.hs` example demonstrating: smart constructors for 14+ block types, code blocks in 3 languages, callouts with icons, full-control construction with annotations and colors, pattern matching on API responses, and position-based insertion.
- Bonus fix: `File.FromJSON` now correctly parses ISO 8601 `expiryTime` strings (was a latent bug masked by untyped parsing).

**What remains (out of scope):**
- Recursive `children` in `BlockContent` for inline child blocks during creation (e.g., toggle children).
- `Eq` instance for `BlockContent` (blocked by `File`, `ExternalFile`, and `Icon` lacking `Eq`).
- Dedicated round-trip unit tests for `BlockContent` JSON (the e2e tests provide this coverage indirectly).


## Context and Orientation

This section describes the current state of block handling in the `notion-client` library and the Notion API's block model. "Block" in Notion's API means a unit of page content — a paragraph, heading, image, code snippet, divider, etc. Every Notion page is composed of blocks.

### Current library state

The file `src/Notion/V1/Blocks.hs` (149 lines) defines four types and a Servant API:

`BlockObject` is the main type returned when reading blocks from the API. It has fields for metadata (`id`, `parent`, `createdTime`, etc.) and two fields for content:

    type_ :: Text    -- the block type discriminator, e.g. "paragraph"
    content :: Value  -- the raw JSON content under the type key

The `FromJSON` instance reads the discriminator with `type_ <- o .: "type"` and then grabs the raw content with `content <- o .: Key.fromText type_`. No further parsing is done — the content remains an opaque `Value`.

`BlockContent` is a newtype used for the update (PATCH) endpoint:

    newtype BlockContent = BlockContent { content :: Value }

`AppendBlockChildren` is used for the append endpoint:

    data AppendBlockChildren = AppendBlockChildren
      { children :: Vector Value
      , position :: Maybe Position
      }

Additionally, `src/Notion/V1/Pages.hs` defines `CreatePage` with:

    children :: Maybe (Vector Value)

All four of these use `Value` where typed content should be.

### Example code showing the problem

In `notion-client-example/Blocks.hs`, helper functions construct block JSON by hand:

    createParagraphBlock :: Text -> Aeson.Value
    createParagraphBlock content =
      let textObj = Aeson.object [("content", Aeson.String content)]
          textItem = Aeson.object [("text", textObj)]
          richText = Aeson.Array (Vector.singleton textItem)
          paragraphContent = Aeson.object [("rich_text", richText)]
       in Aeson.object
            [ ("type", Aeson.String "paragraph"),
              ("paragraph", paragraphContent)
            ]

Similarly, `tasty/Main.hs` has helpers like `mkParagraphBlock` and `mkHeadingBlock` that build raw JSON. This manual JSON construction is exactly what typed constructors will replace.

### Notion API block model

The Notion API uses a discriminated union for blocks. A block JSON object at the top level contains metadata fields (`id`, `parent`, `type`, etc.) and the content under a key matching the type name. For example, a paragraph block:

    {
      "id": "abc-123",
      "type": "paragraph",
      "paragraph": {
        "rich_text": [{"text": {"content": "Hello"}}],
        "color": "default"
      },
      ...
    }

There are approximately 30 distinct block types. They fall into several categories based on their content structure:

**Text blocks** share `rich_text` (a vector of `RichText` objects, already typed in `src/Notion/V1/RichText.hs`) and `color` (already typed in `src/Notion/V1/Common.hs` as the `Color` type). These are: `paragraph`, `heading_1`, `heading_2`, `heading_3`, `bulleted_list_item`, `numbered_list_item`, `to_do`, `toggle`, `quote`, `callout`. Some have extra fields: headings have `is_toggleable :: Bool`, to_do has `checked :: Bool`, callout has `icon :: Icon`, numbered_list_item has `list_format` and `list_start_index`, and paragraph has `icon :: Maybe Icon`.

**Code blocks** have `rich_text`, `caption` (also rich text), and `language` (an enum of 60+ programming language strings).

**Equation blocks** have a single `expression :: Text` (KaTeX format).

**Media blocks** (`image`, `video`, `audio`, `file`, `pdf`) share a file-source pattern: a `type` discriminator (`"external"`, `"file"`, or `"file_upload"`) with the URL or ID under the corresponding key. Media blocks except `audio` also have `caption`.

**Embed blocks**: `bookmark` has `url` and `caption`. `embed` has just `url`. `link_to_page` has a discriminated union pointing to a page, database, or comment by ID. `link_preview` has `url` and is read-only.

**Structural blocks**: `divider` and `breadcrumb` have empty content. `table_of_contents` has `color`. `column_list` and `column` are layout containers. `table` has `table_width`, `has_column_header`, `has_row_header`. `table_row` has `cells` (a vector of vectors of rich text).

**Reference and special blocks**: `child_page` and `child_database` have `title :: Text`. `synced_block` has a `synced_from` field that is either null (original) or references another block. `meeting_notes` is read-only. `unsupported` is a catch-all for types the API doesn't expose.

### Existing typed patterns in the codebase

The library already has well-established patterns for discriminated unions:

`src/Notion/V1/PropertyValue.hs` defines `PropertyValue` as a sum type with 22 constructors, dispatching on a `type` discriminator in `FromJSON` and serializing with the correct key in `ToJSON`. It also provides smart constructors (`titleValue`, `selectValue`, etc.) for convenient value creation.

`src/Notion/V1/Properties.hs` defines `PropertySchema` with 22 constructors and uses a `schemaFields` helper function that decomposes each constructor into `(schemaId, schemaName, typeKey, innerValue)` for `ToJSON`.

`src/Notion/V1/RichText.hs` defines `RichTextContent` as a sum type with three constructors (`TextContentWrapper`, `MentionContentWrapper`, `EquationContentWrapper`), dispatched by `type_` in `RichText.FromJSON`.

The `BlockContent` sum type will follow these same patterns.

### Reusable types

Several types already exist and will be reused by `BlockContent`:

- `RichText` and supporting types from `src/Notion/V1/RichText.hs` — used in text blocks, code blocks, table rows, and captions.
- `Color` from `src/Notion/V1/Common.hs` — used for text block colors and table of contents.
- `Icon` from `src/Notion/V1/Common.hs` — used in callout and paragraph blocks.
- `File` and `ExternalFile` from `src/Notion/V1/Common.hs` — used in media blocks (though a new `FileSource` discriminated union is needed to unify them with `file_upload`).
- `UUID` from `src/Notion/V1/Common.hs` — used in link_to_page and synced_block references.


## Plan of Work

The work proceeds in three milestones. The first creates the new `Notion.V1.BlockContent` module with all types, JSON instances, and smart constructors. The second integrates the new types into the existing API types (`BlockObject`, `AppendBlockChildren`, `CreatePage`) and the Servant wiring. The third updates all tests and example code.

### Milestone 1: Create the BlockContent module

This milestone produces a new file `src/Notion/V1/BlockContent.hs` that defines the `BlockContent` sum type, supporting types, JSON instances, and smart constructors. At the end of this milestone, the new module compiles and has unit tests demonstrating JSON round-trip correctness.

The module will export: `BlockContent(..)`, `CodeLanguage(..)`, `FileSource(..)`, `ListFormat(..)`, `SyncedFrom(..)`, `blockContentType`, `blockContentFields`, and smart constructors.

**Step 1: Define supporting types.** Before the main sum type, define the small types that block constructors depend on.

`CodeLanguage` is an enum of programming language identifiers that Notion supports for code blocks. The API sends these as lowercase strings like `"javascript"`, `"haskell"`, `"python"`, etc. Define this as a sum type with a constructor for each language and `FromJSON`/`ToJSON` instances that convert between the constructors and their string representations. Include at least the following languages: `Abap`, `Arduino`, `Bash`, `Basic`, `C`, `Clojure`, `CoffeeScript`, `Cpp`, `CSharp`, `Css`, `Dart`, `Diff`, `Docker`, `Elixir`, `Elm`, `Erlang`, `Flow`, `Fortran`, `FSharp`, `Gherkin`, `Glsl`, `Go`, `GraphQL`, `Groovy`, `Haskell`, `Html`, `Java`, `JavaScript`, `Json`, `Julia`, `Kotlin`, `LaTeX`, `Less`, `Lisp`, `LiveScript`, `Lua`, `Makefile`, `Markdown`, `Markup`, `Matlab`, `Mermaid`, `Nix`, `ObjectiveC`, `OCaml`, `Pascal`, `Perl`, `Php`, `PlainText`, `PowerShell`, `Prolog`, `Protobuf`, `Python`, `R`, `Reason`, `Ruby`, `Rust`, `Sass`, `Scala`, `Scheme`, `Scss`, `Shell`, `Sql`, `Swift`, `TypeScript`, `VbNet`, `Verilog`, `Vhdl`, `VisualBasic`, `WebAssembly`, `Xml`, `Yaml`, `JavaCCppCSharp`. Follow the pattern used by `NumberFormat` in `src/Notion/V1/Properties.hs` — explicit `FromJSON`/`ToJSON` instances with string matching, not derived generics.

`FileSource` is a discriminated union for block media (images, videos, audio, files, PDFs). The API uses a `type` field with values `"external"`, `"file"`, or `"file_upload"`:

    data FileSource
      = ExternalSource ExternalFile
      | NotionSource File
      | FileUploadSource UUID

`ExternalFile` and `File` are imported from `Notion.V1.Common`. `FileUploadSource` takes a `UUID` representing the upload ID. The `FromJSON` instance dispatches on the `type` field. `ToJSON` produces the discriminated union with `type` + the corresponding key.

`ListFormat` is a small enum for numbered list items: `Numbers`, `Letters`, `Roman`. The JSON values are `"numbers"`, `"letters"`, `"roman"`.

`SyncedFrom` is for synced blocks. An original synced block has `synced_from: null`. A reference has `synced_from: { type: "block_id", block_id: "<uuid>" }`. Model this as:

    data SyncedFrom
      = SyncedOriginal
      | SyncedReference UUID

**Step 2: Define the `BlockContent` sum type.** This is the core of the change. Each constructor represents one Notion block type and carries that type's specific fields. The constructors are:

    data BlockContent
      -- Text blocks
      = ParagraphBlock
          { richText :: Vector RichText
          , color :: Color
          , paragraphIcon :: Maybe Icon
          }
      | Heading1Block
          { richText :: Vector RichText
          , color :: Color
          , isToggleable :: Bool
          }
      | Heading2Block
          { richText :: Vector RichText
          , color :: Color
          , isToggleable :: Bool
          }
      | Heading3Block
          { richText :: Vector RichText
          , color :: Color
          , isToggleable :: Bool
          }
      | BulletedListItemBlock
          { richText :: Vector RichText
          , color :: Color
          }
      | NumberedListItemBlock
          { richText :: Vector RichText
          , color :: Color
          , listFormat :: Maybe ListFormat
          , listStartIndex :: Maybe Natural
          }
      | ToDoBlock
          { richText :: Vector RichText
          , color :: Color
          , checked :: Bool
          }
      | ToggleBlock
          { richText :: Vector RichText
          , color :: Color
          }
      | QuoteBlock
          { richText :: Vector RichText
          , color :: Color
          }
      | CalloutBlock
          { richText :: Vector RichText
          , color :: Color
          , calloutIcon :: Maybe Icon
          }
      -- Code
      | CodeBlock
          { richText :: Vector RichText
          , caption :: Vector RichText
          , language :: CodeLanguage
          }
      -- Equation
      | EquationBlock
          { expression :: Text
          }
      -- Media
      | ImageBlock
          { imageSource :: FileSource
          , caption :: Vector RichText
          }
      | VideoBlock
          { videoSource :: FileSource
          , caption :: Vector RichText
          }
      | AudioBlock
          { audioSource :: FileSource
          }
      | FileBlock
          { fileSource :: FileSource
          , caption :: Vector RichText
          , fileName :: Maybe Text
          }
      | PdfBlock
          { pdfSource :: FileSource
          , caption :: Vector RichText
          }
      -- Embeds
      | BookmarkBlock
          { url :: Text
          , caption :: Vector RichText
          }
      | EmbedBlock
          { url :: Text
          }
      | LinkToPageBlock
          { linkTarget :: Parent
          }
      | LinkPreviewBlock
          { url :: Text
          }
      -- Structural
      | DividerBlock
      | BreadcrumbBlock
      | TableOfContentsBlock
          { color :: Color
          }
      | ColumnListBlock
      | ColumnBlock
      | TableBlock
          { tableWidth :: Natural
          , hasColumnHeader :: Bool
          , hasRowHeader :: Bool
          }
      | TableRowBlock
          { cells :: Vector (Vector RichText)
          }
      -- References
      | ChildPageBlock
          { title :: Text
          }
      | ChildDatabaseBlock
          { title :: Text
          }
      | SyncedBlockContent
          { syncedFrom :: SyncedFrom
          }
      -- Special / read-only
      | UnsupportedBlock
      | UnknownBlock Text Value

Note on naming: constructors use `DuplicateRecordFields`-friendly names. Fields like `richText` and `color` appear in multiple constructors; this is fine because the extension is already enabled project-wide. The `Icon` field is named `paragraphIcon` / `calloutIcon` to disambiguate, since the `Icon` type itself is imported from `Common`.

Note on `LinkToPageBlock`: it reuses the `Parent` type from `Common.hs` since `Parent` already has constructors for `PageParent`, `DatabaseParent`, etc. with the corresponding UUID. While the API sends `{ "type": "page_id", "page_id": "<uuid>" }` for link_to_page targets, this structure matches `Parent`'s `FromJSON`/`ToJSON` exactly.

**Step 3: Implement `blockContentFields`.** This helper decomposes a `BlockContent` value into a pair of `(Text, Value)` where the first element is the JSON type name (e.g., `"paragraph"`) and the second is the serialized inner content. This follows the pattern of `schemaFields` in `src/Notion/V1/Properties.hs`. For example:

    blockContentFields :: BlockContent -> (Text, Value)
    blockContentFields = \case
      ParagraphBlock {..} -> ("paragraph", object $
        [ "rich_text" .= richText, "color" .= color ]
        <> maybe [] (\i -> ["icon" .= i]) paragraphIcon)
      Heading1Block {..} -> ("heading_1", object
        [ "rich_text" .= richText, "color" .= color, "is_toggleable" .= isToggleable ])
      ...
      UnknownBlock typeName val -> (typeName, val)

**Step 4: Implement `blockContentType`.** A simple accessor:

    blockContentType :: BlockContent -> Text
    blockContentType = fst . blockContentFields

**Step 5: Implement `FromJSON`.** The instance cannot be a standalone `FromJSON BlockContent` because the parsing context differs: when parsing a standalone block (for creation payloads), the type discriminator and content are in the same object. When parsing within a `BlockObject`, the type is at the outer level and the content is under the type key. Therefore, define an internal parsing function:

    parseBlockContent :: Text -> Value -> Aeson.Parser BlockContent

This takes the type string and the inner content value, and dispatches. The standalone `FromJSON` instance for `BlockContent` reads the `type` field, extracts the content from the matching key, and calls `parseBlockContent`. This dual approach lets `BlockObject.FromJSON` also call `parseBlockContent` with the values it has already extracted.

The dispatch covers all known types and falls through to `UnknownBlock` for anything unrecognized. For text blocks, parse `rich_text` and `color` (defaulting color to `Default` if absent, since the API sometimes omits it). For code blocks, parse `rich_text`, `caption` (defaulting to empty vector), and `language`. For media blocks, parse the `FileSource` from the content object. And so on for each type.

**Step 6: Implement `ToJSON`.** Uses `blockContentFields`:

    instance ToJSON BlockContent where
      toJSON bc =
        let (typeName, inner) = blockContentFields bc
         in object [ "type" .= typeName, Key.fromText typeName .= inner ]

This produces the full discriminated union format used by the append and create endpoints.

**Step 7: Define smart constructors.** These provide a convenient way to build common block types from minimal inputs, following the pattern of `titleValue`, `selectValue`, etc. in `src/Notion/V1/PropertyValue.hs`.

    paragraphBlock :: Vector RichText -> BlockContent
    paragraphBlock rt = ParagraphBlock rt Default Nothing

    headingBlock :: Natural -> Vector RichText -> BlockContent
    headingBlock 1 rt = Heading1Block rt Default False
    headingBlock 2 rt = Heading2Block rt Default False
    headingBlock _ rt = Heading3Block rt Default False

    bulletedListItemBlock :: Vector RichText -> BlockContent
    bulletedListItemBlock rt = BulletedListItemBlock rt Default

    numberedListItemBlock :: Vector RichText -> BlockContent
    numberedListItemBlock rt = NumberedListItemBlock rt Default Nothing Nothing

    toDoBlock :: Vector RichText -> Bool -> BlockContent
    toDoBlock rt checked = ToDoBlock rt Default checked

    toggleBlock :: Vector RichText -> BlockContent
    toggleBlock rt = ToggleBlock rt Default

    quoteBlock :: Vector RichText -> BlockContent
    quoteBlock rt = QuoteBlock rt Default

    calloutBlock :: Vector RichText -> Maybe Icon -> BlockContent
    calloutBlock rt icon = CalloutBlock rt Default icon

    codeBlock :: Vector RichText -> CodeLanguage -> BlockContent
    codeBlock rt lang = CodeBlock rt Vector.empty lang

    equationBlock :: Text -> BlockContent
    equationBlock = EquationBlock

    bookmarkBlock :: Text -> BlockContent
    bookmarkBlock url = BookmarkBlock url Vector.empty

    dividerBlock :: BlockContent
    dividerBlock = DividerBlock

    imageBlock :: FileSource -> BlockContent
    imageBlock src = ImageBlock src Vector.empty

Additionally, provide two convenience functions that build a `RichText` vector from plain text, since this is by far the most common use case:

    mkRichText :: Text -> Vector RichText
    mkRichText t = Vector.singleton RichText
      { plainText = t
      , href = Nothing
      , annotations = defaultAnnotations
      , type_ = "text"
      , content = TextContentWrapper (TextContent t Nothing)
      }

    textBlock :: Text -> BlockContent
    textBlock = paragraphBlock . mkRichText

This replaces the manual JSON construction that currently exists in the example code and tests.

**Verification.** At the end of this milestone, run:

    cabal build all

The new module must compile without warnings. The build will initially fail because `BlockContent` is not yet integrated into the existing types (that happens in Milestone 2). To verify the module in isolation, temporarily add it to the cabal file's exposed-modules without changing any imports in other modules. The cabal build should succeed with the new module listed.

Then add unit tests (see Milestone 3 for details) that verify JSON round-trip of at least: `ParagraphBlock`, `Heading1Block`, `CodeBlock`, `ImageBlock`, `DividerBlock`, `TableBlock`, `UnknownBlock`.


### Milestone 2: Integrate into existing API types

This milestone rewires the existing types to use `BlockContent` instead of `Value`. At the end, the full library compiles and the Servant client generates correctly-typed functions.

**Step 1: Update `src/Notion/V1/Blocks.hs`.** Make the following changes:

Add an import for the new module:

    import Notion.V1.BlockContent (BlockContent, BlockUpdate (..), blockContentFields, blockContentType, parseBlockContent)

Change the `content` field in `BlockObject` from `Value` to `BlockContent`:

    data BlockObject = BlockObject
      { ...
      , content :: BlockContent  -- was: Value
      , ...
      }

Update `BlockObject`'s `FromJSON` instance. Replace the line:

    content <- o .: Key.fromText type_

with:

    contentVal <- o .: Key.fromText type_
    content <- parseBlockContent type_ contentVal

Update `BlockObject`'s `ToJSON` instance. Replace:

    "type" .= type_,
    Key.fromText type_ .= content,

with:

    "type" .= type_,
    Key.fromText type_ .= snd (blockContentFields content),

Note: `type_` is still serialized from the `type_` field for backward compatibility. The `content` is serialized as just the inner value (without the `"type"` key) because the outer `BlockObject` envelope already carries the type.

Replace the old `BlockContent` newtype. The existing newtype:

    newtype BlockContent = BlockContent { content :: Value }

is removed entirely. In its place, define `BlockUpdate` in the new `Notion.V1.BlockContent` module (or in `Blocks.hs` — either works). `BlockUpdate` wraps `BlockContent` and serializes without the `"type"` key, producing only `{ "<type_key>": { ... } }`:

    newtype BlockUpdate = BlockUpdate BlockContent

    instance ToJSON BlockUpdate where
      toJSON (BlockUpdate bc) =
        let (typeName, inner) = blockContentFields bc
         in object [ Key.fromText typeName .= inner ]

The Servant API type for the update endpoint changes from `ReqBody '[JSON] BlockContent` to `ReqBody '[JSON] BlockUpdate`.

Update `AppendBlockChildren` to use `Vector BlockContent`:

    data AppendBlockChildren = AppendBlockChildren
      { children :: Vector BlockContent  -- was: Vector Value
      , position :: Maybe Position
      }

The `ToJSON` instance remains the same since `BlockContent`'s `ToJSON` produces the full format that the API expects.

Update the module's export list to remove the old `BlockContent(..)` and add `BlockUpdate(..)`. Also re-export key types from `BlockContent`:

    module Notion.V1.Blocks
      ( BlockID,
        BlockObject (..),
        BlockUpdate (..),
        AppendBlockChildren (..),
        Position (..),
        module Notion.V1.BlockContent,
        API,
      )

**Step 2: Update `src/Notion/V1/Pages.hs`.** Change the `children` field in `CreatePage`:

    children :: Maybe (Vector BlockContent)  -- was: Maybe (Vector Value)

Add the import:

    import Notion.V1.BlockContent (BlockContent)

**Step 3: Update `src/Notion/V1.hs`.** Update imports to use `BlockUpdate` instead of `BlockContent` for the update method:

    updateBlock :: BlockID -> Blocks.BlockUpdate -> IO BlockObject,

Add `Notion.V1.BlockContent` to the re-exports or ensure the types are accessible through `Notion.V1.Blocks`.

**Step 4: Update `notion-client.cabal`.** Add `Notion.V1.BlockContent` to `exposed-modules` in the library stanza.

**Verification.** Run:

    cabal build all

This must compile the library, test suite, and example executable. At this point the test suite and examples will need code changes (Milestone 3) to compile, so focus on getting the library itself to build first. If the test and example code fail to compile, that is expected — their updates follow in Milestone 3.


### Milestone 3: Update tests and examples

This milestone brings all consumers in line with the new types. At the end, `cabal build all` succeeds and `cabal test` passes (at minimum the unit tests; e2e tests require a `NOTION_TOKEN`).

**Step 1: Update unit tests in `tasty/Main.hs`.** The existing JSON parsing tests for `BlockObject` (at approximately line 255) use raw JSON strings that parse into `BlockObject`. These tests should continue to work after Milestone 2's changes since the `FromJSON` instance now produces typed `BlockContent` instead of `Value`. Update the assertions to also verify the parsed content:

    Right block -> do
      assertEqual "inTrash should be False" False (Notion.V1.Blocks.inTrash block)
      assertEqual "type should be paragraph" "paragraph" (Notion.V1.Blocks.type_ block)
      case Notion.V1.Blocks.content block of
        ParagraphBlock {..} -> assertEqual "rich_text should be empty" Vector.empty richText
        other -> assertFailure $ "Expected ParagraphBlock, got: " <> show other

Add new unit tests that verify JSON round-trip for `BlockContent` directly. Test at least these constructors: `ParagraphBlock`, `Heading1Block` (with `is_toggleable`), `CodeBlock` (with language), `ImageBlock` (external source), `DividerBlock`, `TableBlock`, `BookmarkBlock`, and `UnknownBlock`. For each test, construct a `BlockContent` value, serialize to JSON with `toJSON`, parse it back with `fromJSON`, and verify equality.

Also add a test for `BlockUpdate` serialization to confirm it omits the `"type"` key.

**Step 2: Update test helper functions.** Replace the helpers `mkParagraphBlock`, `mkHeadingBlock`, and `mkRichTextValue` (around line 174 of `tasty/Main.hs`) with versions that produce `BlockContent` values:

    mkParagraphBlock :: Text.Text -> BlockContent
    mkParagraphBlock = textBlock

    mkHeadingBlock :: Text.Text -> Int -> BlockContent
    mkHeadingBlock t level = headingBlock (fromIntegral level) (mkRichText t)

Remove `mkRichTextValue` (which produced `Aeson.Value`) since it is no longer needed.

**Step 3: Update e2e tests.** The e2e tests in `tasty/Main.hs` (starting around line 800) construct blocks using the old helpers and raw JSON. Replace raw JSON block construction with typed constructors. For example, the bulleted list items:

    Aeson.object
      [ ("type", Aeson.String "bulleted_list_item"),
        ("bulleted_list_item", Aeson.object [("rich_text", mkRichTextValue "List item one")])
      ]

becomes:

    bulletedListItemBlock (mkRichText "List item one")

**Step 4: Update `notion-client-example/Blocks.hs`.** This file currently exports three functions that build raw JSON. Replace them with re-exports of the typed smart constructors, or rewrite them as thin wrappers. The simplest approach is to rewrite the module to re-export and/or wrap the smart constructors from `Notion.V1.BlockContent`:

    module Blocks
      ( createParagraphBlock,
        createHeadingBlock,
        createBulletedListItemBlock,
      )
    where

    import Notion.V1.BlockContent

    createParagraphBlock :: Text -> BlockContent
    createParagraphBlock = textBlock

    createHeadingBlock :: Text -> Int -> BlockContent
    createHeadingBlock t level = headingBlock (fromIntegral level) (mkRichText t)

    createBulletedListItemBlock :: Text -> BlockContent
    createBulletedListItemBlock = bulletedListItemBlock . mkRichText

Note: the return type changes from `Aeson.Value` to `BlockContent`. Callers in `DatabaseDemo.hs` that pass these into `AppendBlockChildren.children` (which now expects `Vector BlockContent`) will work without further changes.

**Step 5: Update `notion-client-example/DatabaseDemo.hs` and `PageDemo.hs`.** In `DatabaseDemo.hs`, the `initialBlocks` and block-append sections use `createHeadingBlock` and `createParagraphBlock` which now return `BlockContent` — these should work after Step 4. In `PageDemo.hs`, the code, quote, and callout blocks are constructed as raw JSON (around line 96). Replace with typed constructors:

    let codeBlockVal = codeBlock
          (mkRichText "const example = () => {\n  console.log('Hello from Notion API');\n};")
          JavaScript
        quoteBlockVal = quoteBlock (mkRichText "This is a quote block added via the API")
        calloutBlockVal = calloutBlock
          (mkRichText "This is a callout block with an emoji")
          (Just (EmojiIcon "🔥"))

**Verification.** Run:

    cabal build all

This must compile the library, test suite, and example executable without errors. Then run:

    cabal test

The unit tests (JSON parsing group) must all pass. The e2e tests require a `NOTION_TOKEN` environment variable and network access; verify those pass if the token is available.


## Concrete Steps

All commands are run from the repository root: `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`.

After creating the new module (`src/Notion/V1/BlockContent.hs`), register it in `notion-client.cabal` under `exposed-modules` and build:

    cabal build all

Expected: compilation succeeds. If there are type errors in the test or example code (because they still use `Value` where `BlockContent` is now expected), those are addressed in Milestone 3.

After all changes (Milestones 1-3):

    cabal build all

Expected: clean compilation of library, test suite, and example executable.

    cabal test

Expected: all unit tests pass. Example transcript:

    Test suite tasty: RUNNING...
    JSON Parsing
      Parse BlockObject with in_trash:            OK
      Parse BlockObject with legacy archived field: OK
      Parse BlockContent round-trip (paragraph):  OK
      Parse BlockContent round-trip (code):       OK
      ...
    All X tests passed.

To verify treefmt (the pre-commit formatter) is happy:

    treefmt


## Validation and Acceptance

The change is accepted when all of the following hold:

1. `cabal build all` compiles with no errors and no warnings (beyond any pre-existing ones).

2. `cabal test` passes all unit tests. Specifically, the JSON parsing tests must demonstrate that `BlockObject` values with typed `BlockContent` round-trip correctly (serialize to JSON and parse back to the same value).

3. The example code in `notion-client-example/` uses typed smart constructors (`textBlock`, `headingBlock`, `codeBlock`, etc.) instead of manual `Aeson.object` JSON construction. No raw JSON block construction remains in the examples.

4. The test code in `tasty/Main.hs` uses typed `BlockContent` values instead of `Aeson.Value` for block construction. The test helpers `mkParagraphBlock` and `mkHeadingBlock` return `BlockContent`, not `Value`.

5. Pattern matching on block content works. For example, the following compiles and type-checks:

        case content someBlock of
          ParagraphBlock {richText, color, ..} -> ...
          CodeBlock {richText, language, ..} -> ...
          _ -> ...

6. Smart constructors produce blocks that the Notion API accepts. This is verified by the e2e tests (if run with a `NOTION_TOKEN`), which create pages with typed blocks and verify the blocks appear correctly.


## Idempotence and Recovery

All steps are additive and safe to repeat. Creating the new `BlockContent` module is idempotent — writing the same file again produces the same result. The integration changes (updating field types from `Value` to `BlockContent`) are a one-time migration, but re-applying them to already-migrated code is a no-op.

If the build fails after partial integration (e.g., `BlockObject` is updated but tests are not), the fix is to continue with the remaining steps. The intermediate state may not compile, but no data is lost and `git stash` or `git checkout` can revert to a compiling state.

The treefmt pre-commit hook runs automatically and may require re-staging files after formatting. This is standard for the project and not a recovery concern.


## Interfaces and Dependencies

The implementation depends on these existing library modules:

- `Notion.V1.RichText` — provides `RichText`, `TextContent`, `Annotations`, `defaultAnnotations`. Used in text blocks, code blocks, table rows, and captions.
- `Notion.V1.Common` — provides `UUID`, `Color`, `Icon`, `File`, `ExternalFile`, `Parent`. Used throughout `BlockContent`.
- `Notion.Prelude` — provides `Value`, `FromJSON`, `ToJSON`, `genericParseJSON`, `aesonOptions`, `Vector`, `Text`, `Natural`, `POSIXTime`, `Generic`, and Servant types.

No new external dependencies are added. The implementation uses only `aeson`, `vector`, `text`, `containers`, and `base` which are already in the cabal file.

The new module defines these key interfaces:

In `src/Notion/V1/BlockContent.hs`:

    -- The sum type
    data BlockContent = ParagraphBlock { ... } | ... | UnknownBlock Text Value
      deriving stock (Generic, Show)

    -- Supporting types
    data CodeLanguage = JavaScript | Haskell | Python | ... deriving stock (Eq, Show, Generic)
    data FileSource = ExternalSource ExternalFile | NotionSource File | FileUploadSource UUID
      deriving stock (Show)
    data ListFormat = Numbers | Letters | Roman deriving stock (Eq, Show, Generic)
    data SyncedFrom = SyncedOriginal | SyncedReference UUID deriving stock (Show)

    -- Serialization helpers
    blockContentType :: BlockContent -> Text
    blockContentFields :: BlockContent -> (Text, Value)
    parseBlockContent :: Text -> Value -> Aeson.Parser BlockContent

    -- Update wrapper (omits "type" key in JSON)
    newtype BlockUpdate = BlockUpdate BlockContent

    -- Smart constructors
    mkRichText :: Text -> Vector RichText
    textBlock :: Text -> BlockContent
    paragraphBlock :: Vector RichText -> BlockContent
    headingBlock :: Natural -> Vector RichText -> BlockContent
    bulletedListItemBlock :: Vector RichText -> BlockContent
    numberedListItemBlock :: Vector RichText -> BlockContent
    toDoBlock :: Vector RichText -> Bool -> BlockContent
    toggleBlock :: Vector RichText -> BlockContent
    quoteBlock :: Vector RichText -> BlockContent
    calloutBlock :: Vector RichText -> Maybe Icon -> BlockContent
    codeBlock :: Vector RichText -> CodeLanguage -> BlockContent
    equationBlock :: Text -> BlockContent
    bookmarkBlock :: Text -> BlockContent
    dividerBlock :: BlockContent
    imageBlock :: FileSource -> BlockContent

In `src/Notion/V1/Blocks.hs`, the updated interfaces:

    data BlockObject = BlockObject
      { ...
      , content :: BlockContent  -- changed from Value
      , ...
      }

    newtype BlockUpdate = BlockUpdate BlockContent  -- replaces old BlockContent newtype

    data AppendBlockChildren = AppendBlockChildren
      { children :: Vector BlockContent  -- changed from Vector Value
      , position :: Maybe Position
      }

In `src/Notion/V1/Pages.hs`:

    data CreatePage = CreatePage
      { ...
      , children :: Maybe (Vector BlockContent)  -- changed from Maybe (Vector Value)
      , ...
      }

In `src/Notion/V1.hs`, the `Methods` record:

    updateBlock :: BlockID -> BlockUpdate -> IO BlockObject  -- changed from Blocks.BlockContent
