---
id: 5
slug: fix-single-property-relation-serialization
title: "Fix single-property relation schema serialization"
kind: exec-plan
created_at: 2026-06-27
---

# Fix single-property relation schema serialization


## Purpose and intent

A "relation property" in Notion is a database column whose cells link to rows in another database (or, for a self-relation, the same database). When you create such a column through Notion's HTTP API you must send a small JSON object describing it. This library builds that JSON for callers. Today it builds the JSON **incorrectly for one-directional ("single property") relations**, so any attempt to provision a single-property relation column is rejected by Notion with HTTP 400 and the message `<Property Name> is not a valid property schema`. Two-directional ("dual property") relations work fine; only the single-property case is broken.

A relation column is "single property" when only the owning side shows the link and Notion does **not** create a mirrored column on the target database. It is "dual property" when Notion also creates a synced reverse column on the target. Notion's API requires that, even for the single-property case, the request include an (empty) `single_property` object as a sibling of `type` and `data_source_id`. This library omits that object, which is the bug.

After this change, a caller that constructs `RelationSchema { relationType = SingleProperty, ... }` and sends it through any of the schema-bearing endpoints (creating a database, creating a data source, or adding/updating a data-source property) will have the column created successfully instead of getting a 400. You can see the fix working by running the test suite: a new test asserts the exact JSON shape and would fail against today's code and pass after the change.

This is a small, surgical correctness fix in one function plus a regression test. It is internal to the library, but its impact is demonstrable both by the new unit test and by the real-world failure that motivated it (recorded under Surprises & Discoveries).


## Orientation: where the relevant code lives

All paths are relative to the repository root `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`.

The property-schema types and their JSON encoding live in `src/Notion/V1/Properties.hs`. The two pieces that matter:

First, the data type. A relation column is represented by the `RelationSchema` constructor of `PropertySchema`, which carries the target data source and the relation's directionality:

    data PropertySchema
      = ...
      | RelationSchema {schemaId :: Text, schemaName :: Text, relationDataSourceId :: UUID, relationType :: RelationType}
      | ...

    data RelationType
      = SingleProperty
      | DualProperty {syncedPropertyId :: Text, syncedPropertyName :: Text}

Second, the encoder. A single helper, `schemaFields :: PropertySchema -> (Text, Text, Aeson.Key, Value)`, returns for each schema its id, name, the JSON key for its type (e.g. `"relation"`), and the configuration object nested under that key. The `RelationSchema` case is where the bug is. As of this writing it reads:

    RelationSchema {..} ->
      let relObj = case relationType of
            SingleProperty -> object ["data_source_id" .= relationDataSourceId, "type" .= ("single_property" :: Text)]
            DualProperty {..} ->
              object
                [ "data_source_id" .= relationDataSourceId,
                  "type" .= ("dual_property" :: Text),
                  "dual_property" .= object ["synced_property_id" .= syncedPropertyId, "synced_property_name" .= syncedPropertyName]
                ]
       in (schemaId, schemaName, "relation", relObj)

Notice the asymmetry: the `DualProperty` branch includes a nested object under the type-name key (`"dual_property" .= object [...]`), but the `SingleProperty` branch includes **no** `"single_property"` key at all. Notion's API requires the nested object in both cases (empty for single property). That missing `"single_property" .= object []` is the entire defect.

The corresponding decoder (`FromJSON RelationType`, also in `Properties.hs`) reads `single_property` by matching only on the `"type"` discriminator and does not require the nested object to be present. This is why the existing round-trip test does not catch the bug: encoding drops the key, decoding does not need it, and the value round-trips to an equal Haskell value even though the emitted JSON is not what Notion accepts. The fix therefore needs a test that asserts the **exact JSON shape**, not merely a round-trip.

The test suite is a single `tasty` test executable whose source is `tasty/Main.hs` (declared as `test-suite tasty` in `notion-client.cabal`). Property-schema serialization tests are grouped together there; the existing relevant case is `testPropertySchemaRelationRoundTrip` (registered in a `testGroup` list alongside `testCase "PropertySchema relation dual round-trip" testPropertySchemaRelationRoundTrip`). That existing test only exercises `DualProperty`.


## Progress

- [x] Milestone 1 (2026-06-27): added the missing `single_property` object to the `SingleProperty` encoding branch in `schemaFields` (`src/Notion/V1/Properties.hs:500-510`). `cabal build notion-client` succeeds with no new warnings.
- [x] Milestone 2 (2026-06-27): added `testPropertySchemaRelationSingleShape` and `testPropertySchemaRelationSingleRoundTrip` in `tasty/Main.hs`, registered in the `"JSON Serialization"` group alongside the existing dual round-trip. Proved the shape test FAILS against the unfixed encoder (diff showed `single_property: {}` present in expected, absent in actual) and PASSES with the fix; the round-trip test passes even unfixed, confirming round-trip cannot catch this.
- [x] Milestone 3 (2026-06-27): full `cabal test tasty` green — All 129 tests passed. Added a `## 0.7.0.2 (2026-06-27)` / `### Bug Fixes` entry to `CHANGELOG.md` in the file's actual style and bumped `version:` to `0.7.0.2` in `notion-client.cabal`. Formatted both changed sources with fourmolu.


## Surprises & Discoveries

- Real-world trigger (2026-06-27): the bug surfaced downstream in `notion-hub`'s `nhub okf sync`, which provisions a self-referential single-property relation (`Depends On` on an "Eng Projects" database). The sync failed with:

      Error: NotionApiError (NotionError {object = "error", status = 400, code = "validation_error",
        message = "Depends On is not a valid property schema", details = Nothing})

  Dual-property relations created in the *same* request (e.g. a `Features` relation) were accepted, isolating the fault to the single-property branch. The downstream workaround was to declare the relation as dual; that should be revertible to single once this fix ships.

- Why the existing test missed it: `testPropertySchemaRelationRoundTrip` does `Aeson.fromJSON (Aeson.toJSON schema)` and asserts equality. The `RelationType` decoder accepts `single_property` based on the `type` field alone and does not read a nested `single_property` object, so a malformed-for-Notion encoding still round-trips to an equal value. Shape-asserting tests are required for request-only encodings where the server, not the decoder, is the real consumer.

- Plan validation (2026-06-27): all code references in this plan were verified against the working tree before implementation. The bug at `schemaFields` (`src/Notion/V1/Properties.hs:500-509`) is confirmed exactly as quoted — the `SingleProperty` branch emits only `data_source_id` and `type`, with no `single_property` key. The `RelationType`/`PropertySchema` types, the `FromJSON RelationType` decoder (matches `single_property` on the `type` discriminator alone, lines 332-344), the `ToJSON PropertySchema` envelope (`id`/`name`/`type`/`<typeName>`, lines 475-483), and the test registration (`testCase "PropertySchema relation dual round-trip"` at `tasty/Main.hs:662`) all match the plan. The Milestone 2 expected JSON shape needs no adjustment: `UUID` derives `ToJSON` via `newtype` (`src/Notion/V1/Common.hs:23-24`), so `data_source_id` serializes as the bare string `"ds-123"`; `Text` is in scope unqualified in `tasty/Main.hs` (already used in `:: Text` annotations there); and `UUID` is imported unqualified in the test file. Cabal targets `notion-client` and `tasty` are correct. Only the CHANGELOG guidance needed correcting (see Decision Log / revision note).

- Implementation correction (2026-06-27): `Text` is **not** in scope unqualified in `tasty/Main.hs`. The validation note above wrongly claimed it was — the file imports only `import Data.Text qualified as Text`, and the pre-existing `:: Text` matches were actually `:: Text.Text`. The first compile of Milestone 2 failed with `Not in scope: type constructor or class 'Text'` on every annotated literal. Fixed by writing the annotations as `:: Text.Text` (qualified). The Milestone 2 code block below has been updated to match. Lesson: a `grep ':: Text'` count is not proof of an unqualified import — it also matches the qualified `Text.Text` prefix; check the import list, not just usages.

- Proof the shape test catches the bug (2026-06-27): running the new test against the unfixed encoder produced:

      PropertySchema relation single shape:  FAIL
        single-property relation JSON shape
        expected: ... ("relation",Object (fromList [("data_source_id",String "ds-123"),("single_property",Object (fromList [])),("type",String "single_property")])) ...
         but got: ... ("relation",Object (fromList [("data_source_id",String "ds-123"),("type",String "single_property")])) ...

  while `PropertySchema relation single round-trip` reported `OK` against the same unfixed encoder — direct confirmation that round-trip equality cannot detect the missing request-only key.

(Append further discoveries here as work proceeds.)


## Decision Log

- Decision (2026-06-27): Fix by emitting `"single_property" .= object []` rather than by changing the decoder or the data model. Rationale: the data model (`SingleProperty` as a nullary constructor) and the decoder are already correct for Notion's responses; only the request encoding is wrong. Mirroring the `dual_property` branch's structure (nested object under the type-name key) keeps the two branches symmetric and matches Notion's documented request shape.

- Decision (2026-06-27): Add a shape-asserting test (compare against an explicitly constructed `Value`) instead of relying on the existing round-trip test. Rationale: round-trip equality cannot detect a missing request-only key, as explained under Surprises & Discoveries.

- Decision (2026-06-27): Bump `version:` in `notion-client.cabal` from `0.7.0.1` to `0.7.0.2` alongside the new `## 0.7.0.2 (2026-06-27)` CHANGELOG heading. Rationale: in this repo every CHANGELOG version heading corresponds to a released package version; adding a dated version heading without bumping the cabal version would leave the two out of sync. The fix is a backward-compatible bug fix, so a patch-level bump is correct.


## Outcomes & Retrospective

Completed 2026-06-27. The `SingleProperty` branch of `schemaFields` now emits the required empty `single_property` object, matching Notion's request shape and mirroring the existing `dual_property` branch. The defect and the fix are demonstrable without a live Notion token: the new `PropertySchema relation single shape` test fails against the unfixed encoder (its emitted `relation` object lacks `single_property`) and passes after the one-line change; the companion `PropertySchema relation single round-trip` passes in both states, confirming why round-trip testing missed the bug in the first place. The full suite is green: **All 129 tests passed**, including the pre-existing `PropertySchema relation dual round-trip`, proving the dual path is unaffected. `CHANGELOG.md` records the fix under a new `## 0.7.0.2 (2026-06-27)` heading and `notion-client.cabal` is bumped to `0.7.0.2`.

Compared against the original purpose, the goal is fully met: a caller constructing `RelationSchema { relationType = SingleProperty, ... }` now produces Notion-valid JSON, so provisioning one-directional and self-referential relation columns will no longer return HTTP 400 `... is not a valid property schema`. The downstream `notion-hub` workaround (declaring the `Depends On` relation as dual to dodge the bug) can revert to a single-property relation once a release carrying this fix is consumed.

One process lesson, captured in Surprises & Discoveries: the pre-implementation validation incorrectly asserted that `Text` was in scope unqualified in `tasty/Main.hs`, based on a `grep ':: Text'` count that also matched the qualified `Text.Text` prefix. The first compile caught it; the test now uses `:: Text.Text`. Verifying an import requires reading the import list, not counting usages.


## Milestones


### Milestone 1 — Emit the required `single_property` object

The goal of this milestone is that the library produces Notion-valid JSON for a single-property relation column. At the end, the `SingleProperty` branch of `schemaFields` in `src/Notion/V1/Properties.hs` includes an empty `single_property` object, symmetric with the existing `dual_property` branch.

Edit the `SingleProperty` line so it reads:

    SingleProperty ->
      object
        [ "data_source_id" .= relationDataSourceId,
          "type" .= ("single_property" :: Text),
          "single_property" .= object []
        ]

Leave the `DualProperty` branch and the surrounding `(schemaId, schemaName, "relation", relObj)` tuple unchanged.

Build to confirm it compiles, from the repository root:

    cabal build notion-client

Expected: a successful build with no new warnings (the module is compiled with `-Wall`).


### Milestone 2 — Regression test asserting the exact JSON shape

The goal is a test that pins the emitted JSON so this cannot silently regress. At the end, `tasty/Main.hs` contains a new assertion that encodes a `SingleProperty` `RelationSchema` and compares the relation configuration object to an explicitly written expected `Value`.

Add a test function near the existing `testPropertySchemaRelationRoundTrip` in `tasty/Main.hs`:

    testPropertySchemaRelationSingleShape :: Assertion
    testPropertySchemaRelationSingleShape = do
      let schema =
            Props.RelationSchema
              { schemaId = "r1",
                schemaName = "Depends On",
                relationDataSourceId = UUID "ds-123",
                relationType = Props.SingleProperty
              }
          json = Aeson.toJSON schema
          expected =
            Aeson.object
              [ "id" Aeson..= ("r1" :: Text.Text),
                "name" Aeson..= ("Depends On" :: Text.Text),
                "type" Aeson..= ("relation" :: Text.Text),
                "relation"
                  Aeson..= Aeson.object
                    [ "data_source_id" Aeson..= ("ds-123" :: Text.Text),
                      "type" Aeson..= ("single_property" :: Text.Text),
                      "single_property" Aeson..= Aeson.object []
                    ]
              ]
      assertEqual "single-property relation JSON shape" expected json

Note: write the literal annotations as `:: Text.Text` (qualified), not `:: Text` — `tasty/Main.hs` imports `Data.Text` only as the qualified alias `Text`, so a bare `Text` type is not in scope and will not compile.

Note on the expected top-level shape: `schemaFields` returns the id, name, type-key, and config object, and a wrapper (the full `ToJSON PropertySchema` instance) assembles them into an object with `id`, `name`, `type`, and the config nested under the type name (here `relation`). If the assembled top-level keys differ in your tree, read the `ToJSON PropertySchema` instance in `src/Notion/V1/Properties.hs` and adjust `expected` to match the real envelope — the **essential assertion** is that the nested `relation` object contains `data_source_id`, `type = "single_property"`, and an empty `single_property` object. If matching the whole envelope proves brittle, narrow the test to pull just the `relation` value out of the encoded object and assert on that.

Also add a single-property round-trip alongside the existing dual one, to confirm decoding still works:

    testPropertySchemaRelationSingleRoundTrip :: Assertion
    testPropertySchemaRelationSingleRoundTrip = do
      let schema =
            Props.RelationSchema
              { schemaId = "r1",
                schemaName = "Depends On",
                relationDataSourceId = UUID "ds-123",
                relationType = Props.SingleProperty
              }
      case Aeson.fromJSON (Aeson.toJSON schema) of
        Aeson.Success decoded -> assertEqual "round-trip" schema decoded
        Aeson.Error err -> assertFailure $ "Failed to decode: " <> err

Register both in the same `testGroup` that holds `testCase "PropertySchema relation dual round-trip" testPropertySchemaRelationRoundTrip`, e.g.:

      testCase "PropertySchema relation single shape" testPropertySchemaRelationSingleShape,
      testCase "PropertySchema relation single round-trip" testPropertySchemaRelationSingleRoundTrip,

Prove the test catches the bug. First, temporarily confirm against the **unfixed** encoder (if you still have it, or by reverting Milestone 1) that the shape test fails:

    cabal test tasty 2>&1 | grep -A3 "relation single shape"

Expected against unfixed code: a failure showing the emitted JSON lacks the `single_property` key, for example a diff where `expected` has `"single_property": {}` under `relation` and the actual value does not.

Then, with Milestone 1 applied, run the suite again and expect the case to pass.


### Milestone 3 — Full suite green and changelog

Run the entire test suite from the repository root:

    cabal test tasty

Expected: all tests pass, including the two new cases and the pre-existing `PropertySchema relation dual round-trip` (proving the dual path is unaffected). Note the total passing count in Outcomes & Retrospective.

Add a one-line entry to `CHANGELOG.md`, matching the conventions already used there. Note the real format before editing: the file has no "Unreleased" section, headings are versioned with a date (e.g. `## 0.7.0.1 (2026-04-16)`), and bug entries live under a `### Bug Fixes` subheading (not `### Fixed`) as bullet lines beginning with `*`. Add a new top version heading above the current `## 0.7.0.1 (2026-04-16)` entry (choosing the next patch version, e.g. `## 0.7.0.2 (<today's date>)`) with a `### Bug Fixes` subsection, for example:

    ## 0.7.0.2 (2026-06-27)

    ### Bug Fixes
    * Relation property schemas with `single_property` now serialize the required empty `single_property` object, so creating one-directional and self-referential relation columns no longer fails Notion validation with "is not a valid property schema"

Format the code before finishing (the repo uses fourmolu; configuration is `fourmolu.yaml`):

    fourmolu --mode inplace src/Notion/V1/Properties.hs tasty/Main.hs


## Validation and acceptance

Acceptance is observable through the test suite without needing a live Notion token:

1. Before the fix, the new `PropertySchema relation single shape` test fails because the encoded `relation` object omits `single_property`.
2. After the one-line change in `schemaFields`, that test passes, the new single-property round-trip passes, and the existing dual round-trip still passes.
3. `cabal build notion-client` and `cabal test tasty` both succeed with no new warnings.

End-to-end (optional, requires credentials): with a `NOTION_TOKEN` and a target page, creating a database whose schema contains a `RelationSchema { relationType = SingleProperty }` column (including a self-relation, where `relationDataSourceId` is the database's own data source) returns 200 and the column appears in Notion, where previously it returned HTTP 400 `... is not a valid property schema`.


## Revision protocol note

This plan was authored on 2026-06-27 to capture a fix discovered while syncing an OKF bundle to Notion via the downstream `notion-hub` tool, where a self-referential single-property relation ("Depends On") was rejected by Notion. If the `ToJSON PropertySchema` envelope or the `schemaFields` signature changes before this is implemented, update the Orientation and Milestone 2 expected-shape accordingly and record the reason here.

Revision (2026-06-27, implementation): Implemented all three milestones. The one substantive correction during implementation was that `Text` is not in scope unqualified in `tasty/Main.hs`, so the Milestone 2 expected-shape annotations were changed from `:: Text` to `:: Text.Text` (the plan's Milestone 2 code block and a new note now reflect this; full detail in Surprises & Discoveries). Additionally bumped `notion-client.cabal` to `0.7.0.2` to stay in sync with the new dated CHANGELOG heading (Decision Log). Final state: `cabal test tasty` reports All 129 tests passed; the shape test was verified to fail against the unfixed encoder beforehand.

Revision (2026-06-27): Validated the plan against the working tree. Every code reference (file paths, line-level quotes, type definitions, decoder behavior, the `ToJSON PropertySchema` envelope, `UUID`'s newtype-derived `ToJSON`, the test registration site, and the `notion-client`/`tasty` cabal targets) was confirmed accurate; findings recorded under Surprises & Discoveries. The only correction: Milestone 3 previously instructed adding a `### Fixed` entry under an "unreleased/next-version heading," but `CHANGELOG.md` has no Unreleased section and uses dated version headings (e.g. `## 0.7.0.1 (2026-04-16)`) with bug entries under `### Bug Fixes` as `*`-prefixed bullets. Milestone 3 was rewritten to add a new top `## 0.7.0.2 (2026-06-27)` heading with a `### Bug Fixes` subsection in the file's actual style, so a novice following the plan produces a changelog entry consistent with the existing file rather than inventing a new heading convention.
