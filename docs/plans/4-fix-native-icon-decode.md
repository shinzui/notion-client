# Fix Native Icon Decode for Notion API Read Responses

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Any `notion-client` consumer that fetches a page or database whose icon was selected
from Notion's built-in icon picker (a *native icon* — pictograms like *clipping*,
*check*, *book*) currently crashes with a JSON decode error of the form

    DecodeFailure "Error in $.icon: key \"name\" not found" (...)

The HTTP response is a perfectly valid `200 OK`; the failure is in our `FromJSON Icon`
instance. It expects the *write* shape Notion accepts on `PATCH` /`POST` calls
(`{"type":"icon","name":"check","color":"green"}`) but Notion's read endpoints return
the *nested* shape

    {"type":"icon","icon":{"name":"clipping","color":"lightgray"}}

The bug surfaced from `notion-cli`'s `ntn group add --page <url>` command, but it
affects every read path: `Pages.retrieve`, `Databases.retrieve`,
`DataSources.queryDataSource` (when results contain such pages), and any list endpoint
returning page or database objects. It is silent until a caller happens to encounter
a resource with a native icon.

After this fix:

* Decoding any page or database object with a native icon succeeds.
* `cabal test all` stays green; a new fixture-based test pinned to the exact JSON
  Notion sent in the bug report locks the behaviour in.
* The encoder is updated symmetrically so `read → modify → write` round-trips through
  the canonical wire shape Notion documents.

The next visible improvement, after a downstream pin bump in `notion-cli`'s
`flake.nix`, is that

    ntn group add --page 'https://www.notion.so/.../<page-id>' active-discussions

succeeds against pages whose icon was set from the picker. That bump is downstream of
this plan and is **not** part of its scope (it is a one-line `flake.nix` edit plus
`nix flake lock --update-input notion-client-src`).


## Progress

- [x] Milestone 1: Decoder + encoder fix in `src/Notion/V1/Common.hs` (2026-04-16)
  - [x] 1a. Update the `"icon"` branch in `FromJSON Icon` to read the nested object
  - [x] 1b. Update `ToJSON Icon` so `NativeIcon` emits the nested object
- [x] Milestone 2: Tests in `tasty/Main.hs` (2026-04-16)
  - [x] 2a. Update `testNativeIconRoundTrip` so its assertions match the new shape
  - [x] 2b. Add `testNativeIconReadShape` decoding the literal JSON from the bug report
  - [x] 2c. Register the new test case in the surrounding `testGroup`
- [x] Milestone 3: Build, test, commit (2026-04-16)
  - [x] 3a. `cabal build all` passes
  - [x] 3b. `cabal test all` passes — all 127 tests green; new `NativeIcon read shape` passes
  - [x] 3c. Commit `294d727` carries the `ExecPlan:` trailer
  - [x] 3d. Pushed to `origin/master`. Fix commit SHA: `294d727`; current `master` tip
        is `89f4328` (an unrelated `mori.dhall` cleanup commit landed on top mid-push —
        see Surprises). Either SHA pins `notion-client-src` correctly downstream.


## Surprises & Discoveries

- 2026-04-16: Between `git commit` (which produced fix SHA `294d727`) and `git push`,
  an unrelated commit `89f4328 chore: migrate mori.dhall to mk-form and add repo-id`
  appeared on local `master`. Most likely an out-of-band process or hook committed the
  pre-existing `mori.dhall` modification visible in the initial `git status`. Push then
  shipped both commits to `origin/master`. Net effect: the fix is in `294d727`, master
  tip is `89f4328`. No code interaction with the icon fix; logged for traceability.


## Decision Log

- Decision: Fix both `FromJSON` and `ToJSON` symmetrically, not just `FromJSON`.
  Rationale: A read-only fix would leave the encoder emitting a flat shape that Notion
  accepts on write but never returns on read, breaking the `decode → modify → encode`
  round-trip property the existing test asserted. Notion's `PATCH page` endpoint
  documents the nested shape as the canonical write form, so the symmetric fix is
  also the most accurate to the API.
  Date: 2026-04-16

- Decision: Add a fixture-based read test (`testNativeIconReadShape`) that decodes a
  literal `ByteString` taken verbatim from the failing Notion response, in addition
  to keeping a round-trip test.
  Rationale: The original `testNativeIconRoundTrip` was self-consistent — encoder and
  decoder agreed with each other — yet still missed the real Notion shape. A
  fixture-based decode test would have caught this immediately. The same lesson came
  out of the prior `CommentAttachment` fix (commit `cd729e6`); apply it here.
  Date: 2026-04-16

- Decision: Do not attempt a backwards-compatible decoder that accepts both the flat
  and nested shapes.
  Rationale: There is no evidence Notion ever returns the flat shape on reads. Adding
  fallback parsing would muddy the error message ("expected one of two shapes") and
  obscure future regressions. A clean cut is simpler and easier to reason about.
  Date: 2026-04-16

- Decision: Do not touch `Cover` or any other `FromJSON` instance in this plan, even
  though they share the "type-tagged sum" pattern.
  Rationale: The bug report only covers icons. Notion's native-icon picker is the
  source of the read-shape mismatch; covers do not have a "native" variant. A full
  audit of every `FromJSON` instance against live Notion responses is its own piece
  of work and should be tracked separately if needed.
  Date: 2026-04-16

- Decision: Place this plan in `notion-client/docs/plans/` (where the fix lives), not
  in the downstream `notion-cli` repo where the user originally observed the bug.
  Rationale: The fix is entirely in this repo; commit history and the `ExecPlan:`
  trailer should point to a path that lives next to the change. Downstream bumps are
  trivial follow-ups and do not warrant their own ExecPlan.
  Date: 2026-04-16


## Outcomes & Retrospective

Completed 2026-04-16. Commit `294d727` on `master` (pushed; `origin/master` tip is
`89f4328` due to the unrelated mori.dhall commit noted in Surprises).

What landed:
- `FromJSON Icon` "icon" branch now reads `name`/`color` from the inner `icon` object.
- `ToJSON Icon` for `NativeIcon` emits the symmetric nested shape.
- `testNativeIconRoundTrip` updated to assert the nested encode shape.
- `testNativeIconReadShape` added: decodes the literal payload from the bug report.
- `cabal test all` reports 127/127 passing in 30.32s, including the new case.

Acceptance check (vs. Validation and Acceptance section):
1. ✅ Read-shape unit test passes against the literal Notion JSON.
2. ✅ Round-trip unit test passes with the nested encode shape.
3. ✅ No regressions; 127 tests green including all other Icon/Cover paths.
4. ✅ Build is clean — no unused-import or partial-pattern warnings introduced.
5. ✅ Commit `294d727` carries the `ExecPlan:` trailer.
6. ✅ Hand-off ready: `294d727` (fix) or `89f4328` (current tip) can be pinned by
   `notion-cli`'s `flake.nix`.

Lesson confirmed (already in Decision Log): fixture-based decode tests pinned to
real Notion responses catch read/write shape mismatches that round-trip-only tests
miss. Same lesson as the `CommentAttachment` fix in `cd729e6`. Future `FromJSON`
work on this codebase should default to a fixture test alongside any round-trip.


## Context and Orientation

### What this repository is

`notion-client` is a type-safe Haskell binding to Notion's REST API, built on Servant.
Its public surface is the `Notion.V1.*` module hierarchy under `src/`. Tests are a
single Tasty file at `tasty/Main.hs`. The Cabal package is declared in
`notion-client.cabal`; build/test commands are plain `cabal build all` and
`cabal test all`.

### The buggy decoder

The `Icon` sum type and its JSON instances live in `src/Notion/V1/Common.hs` (lines
129–164 at the time of writing). Constructors:

* `EmojiIcon { emoji :: Text }` — Unicode emoji.
* `FileIcon { file :: File }` — Notion-hosted uploaded image.
* `ExternalIcon { external :: ExternalFile }` — external image URL.
* `NativeIcon { iconName :: Text, iconColor :: Maybe Text }` — built-in pictogram
  from Notion's icon picker.
* `CustomEmojiIcon { customEmojiId :: UUID }` — custom emoji uploaded by a workspace.
* `FileUploadIcon { fileUploadId :: UUID }` — file-upload-API reference.

The `FromJSON Icon` instance dispatches on the `"type"` field. The relevant line
(roughly line 150) is:

    "icon" -> NativeIcon <$> o .: "name" <*> o .:? "color"

This is the bug. `o` here is the *outer* JSON object (the value of the page's `icon`
field). Notion's read endpoints actually send:

    {"type":"icon","icon":{"name":"clipping","color":"lightgray"}}

so `o .: "name"` raises `key "name" not found`. The `name`/`color` are nested inside
an inner `icon` object.

The encoder side (the `ToJSON Icon` instance, ~line 162) currently emits the flat
shape, matching what the decoder expects:

    toJSON (NativeIcon name color) =
      object $ ["type" .= ("icon" :: Text), "name" .= name]
            <> maybe [] (\c -> ["color" .= c]) color

Both sides need updating so that they use the nested shape consistently.

### Where the existing test is

`tasty/Main.hs` line 651 registers a `testCase "NativeIcon round-trip"` which calls
`testNativeIconRoundTrip` (~line 808). That test:

1. Encodes a `NativeIcon "check" (Just "green")` and asserts the resulting JSON object
   has `name` and `color` at the top level.
2. Round-trips it through `Aeson.fromJSON` and asserts the `NativeIcon` it gets back
   has the same field values.

Both halves of the test pass today **only because they agree with each other** about
the wrong shape. The fix flips both halves to the nested shape and adds a separate
fixture-based decode test that proves the decoder accepts what Notion actually sends.

### Prior art for this same kind of bug

The earlier ExecPlan `docs/plans/3-fix-comment-attachment-parsing.md` (committed as
`cd729e6 fix: decode Notion read-shape for comment attachments`) addressed the same
class of issue for `CommentAttachment` and `CommentDisplayName`. The pattern there
was: hand-roll `FromJSON`/`ToJSON`, add a deserialization test against a literal
Notion JSON fixture, and document the read/write shape divergence in the Decision
Log. This plan deliberately mirrors that approach.

### Mori (project metadata)

`notion-client` is a Mori-registered project (`mori.dhall` at the repo root). To
re-discover the path or dependency information, run

    mori show --full

from this directory; or, from any project that depends on `notion-client`,

    mori registry show shinzui/notion-client --full


## Plan of Work

### Milestone 1 — Decoder + encoder fix

Open `src/Notion/V1/Common.hs`. In the `FromJSON Icon` instance, change the `"icon"`
branch from

    "icon" -> NativeIcon <$> o .: "name" <*> o .:? "color"

to

    "icon" -> do
      inner <- o .: "icon"
      NativeIcon <$> inner .: "name" <*> inner .:? "color"

Note that `o .: "icon"` returns the inner JSON object as a value of type `Object`
(since `aeson`'s `(.:)` is type-driven by the result). The do-notation runs in the
`Parser` monad. No additional imports are needed — `Object` and `Parser` are already
in scope wherever `FromJSON` is defined.

In the `ToJSON Icon` instance, change the `NativeIcon` arm from

    toJSON (NativeIcon name color) =
      object $ ["type" .= ("icon" :: Text), "name" .= name]
            <> maybe [] (\c -> ["color" .= c]) color

to

    toJSON (NativeIcon name color) =
      object
        [ "type" .= ("icon" :: Text)
        , "icon" .= object (["name" .= name] <> maybe [] (\c -> ["color" .= c]) color)
        ]

Acceptance: the file still builds; `cabal build all` succeeds.

### Milestone 2 — Tests

Open `tasty/Main.hs`. In `testNativeIconRoundTrip` (~line 808), the encode-side
assertions need to look inside the new nested object. Replace the body that walks the
encoded `Aeson.Object o` so it matches:

    case json of
      Aeson.Object o -> do
        assertEqual "type" (Just (Aeson.String "icon")) (KeyMap.lookup "type" o)
        case KeyMap.lookup "icon" o of
          Just (Aeson.Object inner) -> do
            assertEqual "name" (Just (Aeson.String "check")) (KeyMap.lookup "name" inner)
            assertEqual "color" (Just (Aeson.String "green")) (KeyMap.lookup "color" inner)
          _ -> assertFailure "Expected nested icon object"
      _ -> assertFailure "Expected JSON object"

Leave the `Aeson.fromJSON` half of the round-trip alone — it already exercises the
new decoder via the just-encoded value.

Add a new test, `testNativeIconReadShape`, that decodes the exact JSON literal taken
from the failing Notion response. This proves the decoder accepts a real-world
payload, not just our own encoder's output:

    testNativeIconReadShape :: Assertion
    testNativeIconReadShape = do
      let payload :: Data.ByteString.Lazy.Char8.ByteString
          payload = "{\"type\":\"icon\",\"icon\":{\"name\":\"clipping\",\"color\":\"lightgray\"}}"
      case Aeson.eitherDecode payload of
        Right (NativeIcon n c) -> do
          assertEqual "name" "clipping" n
          assertEqual "color" (Just "lightgray") c
        Right _  -> assertFailure "Expected NativeIcon"
        Left err -> assertFailure $ "Decode failed: " <> err

If `Data.ByteString.Lazy.Char8` is not already imported in `tasty/Main.hs`, add the
import qualified or, if `OverloadedStrings` is enabled (verify by inspecting the
`{-# LANGUAGE … #-}` block at the top of the file), drop the explicit type signature
and let the literal be inferred. Prefer the explicit type signature if there is any
ambiguity — `eitherDecode` is heavily polymorphic and an inference miss produces
opaque GHC errors.

Register the new case in the `testGroup` near `testNativeIconRoundTrip` (~line 651):

    testCase "NativeIcon read shape" testNativeIconReadShape,

Acceptance: `cabal build all` succeeds; both the updated round-trip test and the new
fixture test pass.

### Milestone 3 — Build, test, commit

Run the full build and test suite from this repository's root:

    cabal build all
    cabal test all

Expected: build clean, every existing test continues to pass, the new
`NativeIcon read shape` case appears in the test report and passes.

Commit the change with the standard `ExecPlan:` trailer and push:

    git add src/Notion/V1/Common.hs tasty/Main.hs docs/plans/4-fix-native-icon-decode.md
    git commit -F /tmp/commit-msg.txt   # see suggested body in Concrete Steps
    git push origin master

Capture the new short SHA (`git rev-parse --short HEAD`); the downstream `notion-cli`
consumer needs it to bump `notion-client-src` in its `flake.nix`. That bump is not
part of this plan.


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`.

Edit-build-test loop:

    # 1. Apply edits to src/Notion/V1/Common.hs and tasty/Main.hs.
    cabal build all
    # Expected: "Resolving dependencies..." then "Building library..." then
    # "Building test suite 'notion-client-test'..." with no errors.

    cabal test all
    # Expected: ALL tests pass. The output ends with something like:
    #   notion-client-test
    #     ...
    #     NativeIcon round-trip:    OK
    #     NativeIcon read shape:    OK
    #     ...
    #   All N tests passed (X.XXs)

Commit and push:

    git add src/Notion/V1/Common.hs tasty/Main.hs docs/plans/4-fix-native-icon-decode.md
    git commit -m "$(cat <<'EOF'
    fix: decode Notion read-shape for native icons

    Notion's GET endpoints return native icons (built-in pictograms from
    the icon picker) as
    {"type":"icon","icon":{"name":"clipping","color":"lightgray"}}, but
    the previous FromJSON Icon decoder expected name/color at the top
    level and crashed with `key "name" not found` on every page or
    database carrying such an icon.

    Update both FromJSON and ToJSON for NativeIcon to use the nested
    shape, refresh the round-trip test, and add a fixture-based read
    test pinned to the exact JSON returned by the live API.

    ExecPlan: docs/plans/4-fix-native-icon-decode.md
    EOF
    )"
    git push origin master
    git rev-parse --short HEAD


## Validation and Acceptance

The change is accepted when **all** of the following hold:

1. **Read-shape unit test:** `cabal test all` includes a passing case
   `NativeIcon read shape` that decodes the literal JSON
   `{"type":"icon","icon":{"name":"clipping","color":"lightgray"}}` to
   `NativeIcon { iconName = "clipping", iconColor = Just "lightgray" }`. This is the
   regression lock — prior to the fix this test fails with
   `Error in $.icon: key "name" not found`.

2. **Round-trip unit test:** the updated `testNativeIconRoundTrip` passes; it asserts
   both that `toJSON` produces a JSON object whose top-level `"icon"` key is itself
   an object containing `"name"` and `"color"`, and that `fromJSON` recovers the
   original `NativeIcon`.

3. **No regressions:** every other test in `tasty/Main.hs` continues to pass.
   Specifically check that `CustomEmojiIcon round-trip`, all `EmojiIcon` /
   `FileIcon` / `ExternalIcon` paths exercised by other tests, and any
   page/database fixture tests stay green.

4. **Build is clean:** `cabal build all` produces no warnings about unused imports
   (the most likely new-import slip if you needed to add
   `Data.ByteString.Lazy.Char8`) and no warnings about partial pattern matches in
   `tasty/Main.hs`.

5. **Commit carries the trailer:** the commit on `master` includes the
   `ExecPlan: docs/plans/4-fix-native-icon-decode.md` trailer in its body, separated
   from the prose by a blank line.

6. **Hand-off ready:** `git rev-parse --short HEAD` after pushing yields a short
   SHA that the downstream `notion-cli` repo can drop into the
   `notion-client-src` rev in its `flake.nix`. (Bumping that pin is not part of this
   plan, but the consumer must be unblocked.)


## Idempotence and Recovery

Every step in this plan is safely repeatable:

* All edits are to Haskell source files tracked in git. `git diff` shows current
  uncommitted state; `git checkout -- <path>` reverts a single file; `git stash`
  parks unfinished work.
* `cabal build` and `cabal test` are pure with respect to the source tree. Rerunning
  has no side effects beyond updating `dist-newstyle/`.
* The push step is the only externally visible action. If the commit is wrong **and
  has not yet been depended on by anyone**, amend and force-push. Once a downstream
  pin (in `notion-cli`'s `flake.nix`) references the SHA, prefer creating a new
  commit on top instead of rewriting history — the lock-file contract requires the
  referenced object to keep existing.

If a step fails:

* Decoder fails to compile: most likely `o .: "icon"` is being inferred as the wrong
  type. Add an explicit `:: Object` annotation:
  `inner <- o .: "icon" :: Parser Object`.
* `testNativeIconReadShape` fails because of a different decode path: print the
  intermediate `Aeson.eitherDecode payload :: Either String Aeson.Value` to confirm
  the literal parses as JSON; the fixture itself can be retyped from the
  `responseBody` field of the original Notion response captured in the bug report.
* Existing tests break: this fix is contained to the `NativeIcon` constructor; if
  other tests fail it is almost certainly an unintended edit elsewhere in the file.
  `git diff src/Notion/V1/Common.hs` should show only the two `NativeIcon` arms.


## Interfaces and Dependencies

### Files changed

* `src/Notion/V1/Common.hs` — `FromJSON Icon` and `ToJSON Icon` for the `NativeIcon`
  constructor.
* `tasty/Main.hs` — adjust `testNativeIconRoundTrip`, add `testNativeIconReadShape`,
  register the new test in the surrounding `testGroup`.
* `docs/plans/4-fix-native-icon-decode.md` — this plan.

### Public types/functions (post-fix)

In `Notion.V1.Common`:

    data Icon
      = EmojiIcon       { emoji         :: Text }
      | FileIcon        { file          :: File }
      | ExternalIcon    { external      :: ExternalFile }
      | NativeIcon      { iconName      :: Text, iconColor :: Maybe Text }
      | CustomEmojiIcon { customEmojiId :: UUID }
      | FileUploadIcon  { fileUploadId  :: UUID }

    instance FromJSON Icon  -- decodes the nested read shape Notion returns:
                            --   {"type":"icon","icon":{"name":...,"color":...}}
    instance ToJSON   Icon  -- emits the nested shape for NativeIcon, matching
                            -- what Notion's PATCH endpoints accept.

The constructor names, field names, and arities are **unchanged**. Any caller that
constructs or pattern-matches `NativeIcon` values is unaffected. The change is on
the wire only.

### Dependencies

No new packages are required.

* `aeson` — already a dependency. Provides `withObject`, `Object`, `Parser`,
  `eitherDecode`, `(.:)`, `(.:?)`, `object`, `(.=)`.
* `bytestring` — already a transitive dependency via `aeson`. Used by the new test
  for the lazy `ByteString` literal that backs `eitherDecode`.

If the test file does not currently import `Data.ByteString.Lazy.Char8`, add

    import qualified Data.ByteString.Lazy.Char8 as L8

at the top of `tasty/Main.hs` and reference the literal as `L8.pack "..."` or with
an explicit type annotation. Prefer the explicit annotation form shown in
Milestone 2 — fewer moving parts.
