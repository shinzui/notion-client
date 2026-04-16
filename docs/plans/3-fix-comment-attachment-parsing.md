# Fix CommentAttachment Parsing for Notion API Read Responses

Intention: intention_01kpbda4x0e3xveey5w3jzbqne

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

When `notion-hub` (or any consumer) calls `GET /v1/comments?block_id=<page_id>`, the Notion
API returns comment objects whose `attachments` array has a **different JSON shape** than the
one `CommentAttachment` currently models.  The parser crashes with:

    key "name" not found

because the read response uses `{"category":"image","file":{…}}` while the type expects
`{"name":"…","type":"…",…}`.

After this fix, listing comments with attachments (images, files) will decode successfully.
A secondary fix captures the `resolved_name` field inside `display_name` that the current
`CommentDisplayName` type silently drops.


## Progress

- [x] Milestone 1: Fix `CommentAttachment` type and instances (2026-04-16)
  - [x] 1a. Restructure the `CommentAttachment` record
  - [x] 1b. Write a hand-rolled `FromJSON` instance for read responses
  - [x] 1c. Update the `ToJSON` instance for write requests
  - [x] 1d. Update test fixture in `tasty/Main.hs` for serialization
  - [x] 1e. Add deserialization test with real API response fixture
- [x] Milestone 2: Fix `CommentDisplayName` to capture `resolved_name` (2026-04-16)
  - [x] 2a. Add `resolvedName :: Maybe Text` field
  - [x] 2b. Write hand-rolled `FromJSON` instance (also hand-rolled `ToJSON` to keep write shape clean)
  - [x] 2c. Update test fixture
- [x] Milestone 3: Build, test, validate (2026-04-16)
  - [x] 3a. `cabal build all` passes
  - [x] 3b. `cabal test all` passes (126/126)
  - [ ] 3c. Verify fix in notion-hub sync scenario (left for user — requires live API token + target page)


## Surprises & Discoveries

- `DuplicateRecordFields` is enabled project-wide, and `Notion.V1.Comments`
  defines multiple records that share field names (`type_` appears on both
  `CommentAttachment` and `CommentDisplayName`; `displayName` appears on
  `CommentDisplayName`, `CommentObject`, and `CreateComment`). Qualified
  selectors like `Comments.type_` therefore fail to resolve with GHC-87543
  "Ambiguous occurrence". Fixed by using pattern-matching with
  `NamedFieldPuns` (enabled via GHC2024) inside the new tests instead of
  selector functions. Evidence: GHC-87543 error emitted on first test build.
- The plan's example `resolved_name` fixture used the user's real name. Per
  user feedback during implementation, test fixtures must use made-up
  Japanese names instead. Used "Tanaka Hiroshi".


## Decision Log

- Decision: Use a single `CommentAttachment` type with all fields optional rather than
  splitting into separate read/write types.
  Rationale: The type is already shared between `CommentObject` (read) and `CreateComment`
  (write).  Splitting would be a larger breaking change.  Making fields `Maybe` lets the
  same type round-trip both shapes while remaining simple.  The `category` field is added
  alongside `type_`; consumers pattern-match on whichever is present.
  Date: 2026-04-16

- Decision: Hand-roll `FromJSON`/`ToJSON` instances instead of using `genericParseJSON`.
  Rationale: The JSON key names diverge between read and write (`category` vs `type`,
  presence/absence of `name`).  A hand-rolled instance is explicit and avoids field-label
  modifier gymnastics.
  Date: 2026-04-16

- Decision: Use pattern-matching (via `NamedFieldPuns`) rather than qualified selector
  functions when reading record fields in the new tests.
  Rationale: `DuplicateRecordFields` is enabled project-wide and several records in
  `Notion.V1.Comments` share field names (`type_`, `displayName`). Selectors like
  `Comments.type_` hit GHC-87543 "ambiguous occurrence" at the call site. Pattern-
  matching the constructor in `case … of Right CommentAttachment {..}` resolves cleanly.
  Date: 2026-04-16

- Decision: Use a made-up Japanese name ("Tanaka Hiroshi") in the `resolved_name`
  test fixture rather than the real name shown in the plan's JSON example.
  Rationale: Per explicit user feedback during implementation — real identities
  should not appear in committed test data. Recorded as a persistent feedback
  memory.
  Date: 2026-04-16


## Outcomes & Retrospective

- `CommentAttachment` now models both API shapes with all fields `Maybe`, and
  its hand-rolled `FromJSON` decodes the read-side payload that previously
  crashed with `key "name" not found`.
- `CommentDisplayName` now captures `resolved_name`; the `ToJSON` instance
  was also hand-rolled (not just `FromJSON`) so that the write payload still
  omits unset optional fields correctly.
- Two new unit tests cover the read-side shapes
  (`testDeserializeCommentAttachmentReadShape`,
  `testDeserializeCommentDisplayNameResolvedName`). The existing
  `testSerializeCreateComment` fixture was updated for the new record
  layout.
- Full test suite (`cabal test all`) passes — 126/126, including live
  integration tests against the Notion API.
- Milestone 3c (re-run `nhub page sync` against the fixed client) is left
  to the user since it requires their workspace token and target page.


## Context and Orientation

### The bug

The Notion **List Comments** endpoint (`GET /v1/comments`) returns comment attachments in
this shape (observed 2026-04-16):

```json
{
  "category": "image",
  "file": {
    "url": "https://prod-files-secure.s3.us-west-2.amazonaws.com/…",
    "expiry_time": "2026-04-16T15:53:52.031Z"
  }
}
```

The Notion **Create Comment** endpoint (`POST /v1/comments`) *accepts* attachments in this
shape:

```json
{
  "name": "file.pdf",
  "type": "external",
  "external": { "url": "https://example.com/file.pdf" }
}
```

### Current type (broken for reads)

File: `src/Notion/V1/Comments.hs`, lines 27–32:

```haskell
data CommentAttachment = CommentAttachment
  { name :: Text,                   -- REQUIRED — crashes on read responses
    type_ :: Text,                  -- maps to "type" — absent in read responses
    external :: Maybe ExternalFile, -- present in write shape
    file :: Maybe File              -- present in read shape
  }
```

`FromJSON` uses `genericParseJSON` with a label modifier that maps `type_` → `"type"`.
Since `name` is non-optional, parsing a read response where `name` is absent fails.

### Secondary issue: CommentDisplayName

File: `src/Notion/V1/Comments.hs`, lines 42–46:

```haskell
data CommentDisplayName = CommentDisplayName
  { type_ :: Text,
    emoji :: Maybe Text,
    displayName :: Maybe Text
  }
```

The API returns `{"type":"user","resolved_name":"Nadeem Bitar"}`.  The `labelModifier`
maps `displayName` → `"display_name"`, but the API key is `"resolved_name"`, so the name
is silently dropped.  Fix: add a `resolvedName :: Maybe Text` field and hand-roll
`FromJSON`.

### Key files

| File | Role |
|------|------|
| `src/Notion/V1/Comments.hs` | `CommentAttachment`, `CommentDisplayName`, `CommentObject`, `CreateComment`, Servant API |
| `src/Notion/V1/Common.hs` | `File` (lines 192–207), `ExternalFile` (lines 216–225) |
| `src/Notion/Prelude.hs` | `aesonOptions`, `labelModifier`, `parseISO8601` |
| `tasty/Main.hs` | Unit + E2E tests; serialization test at line 1621 |
| `src/Notion/V1.hs` | Re-export module (needs updated export if types change) |

### Existing types reused

- `File` — `{ url :: Text, expiryTime :: Maybe POSIXTime }` with hand-rolled `FromJSON`
  that parses `expiry_time` via `parseISO8601`.
- `ExternalFile` — `{ url :: Text }` with generic instances.


## Plan of Work

### Milestone 1 — Fix `CommentAttachment`

**Goal:** Make `CommentAttachment` decode both the read shape (`category` + `file`) and the
write shape (`name` + `type` + `external`/`file`).

**1a. Restructure the record** in `src/Notion/V1/Comments.hs`:

```haskell
data CommentAttachment = CommentAttachment
  { name :: Maybe Text,
    type_ :: Maybe Text,
    category :: Maybe Text,
    external :: Maybe ExternalFile,
    file :: Maybe File
  }
  deriving stock (Generic, Show)
```

- `name` becomes `Maybe Text` (present only in write requests)
- `type_` becomes `Maybe Text` (present only in write requests, serialised as `"type"`)
- `category` is new `Maybe Text` (present only in read responses)
- `external` and `file` remain `Maybe`

**1b. Hand-roll `FromJSON`:**

```haskell
instance FromJSON CommentAttachment where
  parseJSON = withObject "CommentAttachment" $ \o ->
    CommentAttachment
      <$> o .:? "name"
      <*> o .:? "type"
      <*> o .:? "category"
      <*> o .:? "external"
      <*> o .:? "file"
```

**1c. Hand-roll `ToJSON`** (for write requests, omit Nothing fields):

```haskell
instance ToJSON CommentAttachment where
  toJSON CommentAttachment {..} =
    object $ catMaybes
      [ ("name" .=) <$> name,
        ("type" .=) <$> type_,
        ("category" .=) <$> category,
        ("external" .=) <$> external,
        ("file" .=) <$> file
      ]
```

Import `Data.Maybe (catMaybes)` — already available transitively but should be imported
explicitly.

**1d. Update test fixture** in `tasty/Main.hs` line 1628:

```haskell
CommentAttachment
  { name = Just "file.pdf",
    type_ = Just "external",
    category = Nothing,
    external = Just (ExternalFile {url = "https://example.com/file.pdf"}),
    file = Nothing
  }
```

**1e. Add a deserialization test** that parses the read-side JSON:

```haskell
testDeserializeCommentAttachment :: Assertion
testDeserializeCommentAttachment = do
  let json = [aesonQQ|{"category":"image","file":{"url":"https://example.com/img.png","expiry_time":"2026-04-16T15:53:52.000Z"}}|]
  -- Or use Aeson.decode on a ByteString literal
  case Aeson.fromJSON json of
    Aeson.Success att -> do
      assertEqual "category" (Just "image") (category (att :: CommentAttachment))
      assertBool "file should be Just" (isJust (file att))
      assertEqual "name" Nothing (name att)
    Aeson.Error e -> assertFailure e
```

If `aeson-qq` is not a dependency, use `Aeson.eitherDecode` on a ByteString literal
instead.

### Milestone 2 — Fix `CommentDisplayName`

**2a.** Add `resolvedName :: Maybe Text` to the record:

```haskell
data CommentDisplayName = CommentDisplayName
  { type_ :: Text,
    emoji :: Maybe Text,
    displayName :: Maybe Text,
    resolvedName :: Maybe Text
  }
  deriving stock (Generic, Show)
```

**2b.** Hand-roll `FromJSON`:

```haskell
instance FromJSON CommentDisplayName where
  parseJSON = withObject "CommentDisplayName" $ \o ->
    CommentDisplayName
      <$> o .: "type"
      <*> o .:? "emoji"
      <*> o .:? "display_name"
      <*> o .:? "resolved_name"
```

Update `ToJSON` similarly (keep `resolved_name` out of write payloads by omitting it, or
include it as optional).

**2c.** Update existing test to include the new field (set to `Nothing` for the write test,
add a read test with `"resolved_name"` present).

### Milestone 3 — Build, test, validate

Run `cabal build all && cabal test all` in the notion-client directory.  Then rebuild
notion-hub and re-run the page sync that triggered the original error.


## Concrete Steps

All commands are run from `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`.

```sh
# After edits:
cabal build all
# Expected: Build succeeds with no errors

cabal test all
# Expected: All tests pass, including new deserialization test

# Then in notion-hub:
cd /Users/shinzui/Keikaku/bokuno/notion-hub
cabal build all
cabal run nhub -- page sync 33601cd01a4981f89cfef921aa5bece4
# Expected: Sync completes without DecodeFailure
```


## Validation and Acceptance

1. **Unit test — write serialization**: The existing `testSerializeCreateComment` test
   passes with the updated `CommentAttachment` construction (all `Maybe` fields).

2. **Unit test — read deserialization**: A new test parses the JSON shape
   `{"category":"image","file":{"url":"…","expiry_time":"…"}}` into a `CommentAttachment`
   and asserts `category == Just "image"`, `file` is `Just`, `name == Nothing`.

3. **Unit test — CommentDisplayName round-trip**: A new test parses
   `{"type":"user","resolved_name":"Nadeem Bitar"}` and asserts
   `resolvedName == Just "Nadeem Bitar"`.

4. **Integration**: `nhub page sync 33601cd01a4981f89cfef921aa5bece4` succeeds in
   notion-hub after rebuilding against the fixed notion-client.

5. **No regressions**: `cabal test all` in both repos passes.


## Idempotence and Recovery

All edits are to Haskell source files tracked in git.  Each milestone can be re-run safely.
If a step fails, `git diff` shows what changed and `git checkout -- src/` reverts.  No
database migrations or external state changes.


## Interfaces and Dependencies

### Changed types after fix

In `src/Notion/V1/Comments.hs`:

```haskell
data CommentAttachment = CommentAttachment
  { name :: Maybe Text,
    type_ :: Maybe Text,
    category :: Maybe Text,
    external :: Maybe ExternalFile,
    file :: Maybe File
  }

data CommentDisplayName = CommentDisplayName
  { type_ :: Text,
    emoji :: Maybe Text,
    displayName :: Maybe Text,
    resolvedName :: Maybe Text
  }
```

### Re-exports

`src/Notion/V1.hs` already re-exports `CommentAttachment(..)` — no changes needed
since no constructors are added/removed.

### Downstream impact (notion-hub)

`notion-hub-core` imports `CommentAttachment` but only through `CommentObject` parsing
(read path).  The `name` field becoming `Maybe Text` may require updating any
pattern-matches on the constructor, but notion-hub does not currently construct
`CommentAttachment` values, only decodes them.
