---
id: 15
slug: preserve-page-property-response-metadata-and-expose-response-json-encoders
title: "Preserve page property response metadata and expose response JSON encoders"
kind: exec-plan
created_at: 2026-10-12T23:21:56Z
intention: "intention_01m4s6pz9wekf8a8tm26a2jn0v"
provenance:
  created_by:
    model: "gpt-6.1-sol"
    harness: "codex-cli"
    at: 2026-10-12T23:21:56Z
---

# Preserve page property response metadata and expose response JSON encoders

This ExecPlan is a living document. Maintain Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective as implementation proceeds. Promote durable decisions into `docs/adr/` before completion.


## Purpose / Big Picture


Callers will be able to decode a Notion page and serialize its modeled response data without losing property IDs, property types, or the supplied relation completeness flag. A relation links a page to other pages; `has_more: true` means that the returned reference array is incomplete. Missing `has_more` will remain different from false, regardless of the number of references. Callers will use two public functions, `propertyValueResponseJSON` and `pageResponseJSON`, while existing mutation requests continue using `ToJSON`.

This plan implements [IR-1](../improvement-requests/preserve-page-property-response-metadata-and-expose-response-json-encoders.md), including its published-release requirement. The requesting consumer is `mori://shinzui/notion-cli/plans/53-preserve-property-response-metadata-and-add-page-create-json-output`. Its page-create CLI option is separate consumer work. This plan does not fetch remaining relation references, change query pagination, or promise preservation of unmodeled response fields or the original JSON bytes.


## Progress


- [ ] Milestone 1: Relations retain true, false, and absent completeness states; the public property response encoder covers every constructor and nested rollups while mutation encoding remains unchanged (AC-1, AC-2, AC-4).
- [ ] Milestone 2: The public page response encoder preserves modeled page data and metadata through retrieve/create/query/search paths, with partial-result handling unchanged (AC-3).
- [ ] Milestone 3: Both packages and examples build, relevant tests pass, and breaking API migration and compatible release bounds are documented (AC-5).
- [ ] Milestone 4: Hackage releases and matching upstream tags provide the APIs, and a consumer using only published packages passes a response-encoding smoke test (AC-6).

Planning is complete; implementation and publication have not started. IR-1 is accepted and linked to this plan, with all delivery evidence still pending.


## Surprises & Discoveries



## Decision Log


On 2026-10-12, extend `RelationValue` to carry a trailing `Maybe Bool` and expose named response encoders. This gives callers direct access to the retained flag without introducing a second page model. It changes constructor arity, so it requires a breaking release. Keep the existing `ToJSON PropertyValue`, `ToJSON RollupResult`, and `ToJSON PageObject` behavior; response serialization is explicit and cannot silently change mutation builders or existing callers.

On 2026-10-12, treat an empty property ID as the existing model's absent-ID sentinel and omit it from response output. This preserves ID-less nested rollup entries without changing the ID field of every property constructor. Preserve nonempty IDs verbatim, including URL-encoded IDs. The model cannot distinguish an explicit empty ID from an absent ID; document this limitation rather than claiming raw response fidelity.

On 2026-10-12, retain publication as a separate acceptance gate. Local fixtures and compilation satisfy implementation criteria but do not fulfill a consumer that resolves published packages. Planning does not authorize uploading packages, pushing tags, or editing the consumer repository.


## Outcomes & Retrospective



## Context and Orientation


All local paths are relative to the repository root `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`. `cabal.project` contains both `notion-client` and `notion-client-effectful`. `notion-client.cabal` declares the core library, the `tasty` test suite, and the `notion-client-example` executable. The companion manifest is `notion-client-effectful/notion-client-effectful.cabal`; it currently has no test suite. Build both libraries and the example together, then run the core tests. `flake.nix` and `nix/haskell.nix` supply a GHC 9.12.4 development shell.

`src/Notion/V1/PropertyValue.hs` defines 25 property constructors. Each stores a `Text` ID first. Its decoder replaces a missing ID with an empty string, its relation branch currently drops `has_more`, and its `ToJSON` emits only the value key and payload. The public `relationValue :: [UUID] -> PropertyValue` smart constructor supplies an empty ID for writes. `UnknownPropertyValue Text Text Value` retains an unknown property's ID, type name, and raw value payload. `RollupArrayResult` holds a vector of `PropertyValue`; these nested values commonly have no ID. Its existing encoder calls the mutation-oriented property encoder. A response encoder must therefore recurse through arrays explicitly rather than reusing that path unchanged.

`src/Notion/V1/Users.hs` has request-only `ToJSON UserValue`, which reduces `FullUser` to object/ID; `UserObject` and its person/bot support types currently have only decoders. `PeopleEntry` delegates to this instance for users. `VerificationResult.verifiedBy` and `src/Notion/V1/RichText.hs`'s `UserMention` also contain `UserValue`. A property response helper cannot reuse these request encoders for full users and still preserve its modeled value payload. Response-specific nested helpers are needed while those existing instances remain unchanged.

`src/Notion/V1/Pages.hs` defines `PageObject`, `PageProperties = Map Text PropertyValue`, and create/update request builders. `ToJSON PageObject` currently uses `ToJSON PropertyValue` for the properties map. It also serializes modeled page ID, times, users, parent, cover/icon, URL, object kind, trash state, and optional archive/lock/public URL fields. The new page helper must preserve this modeled data while replacing property serialization. Optional fields retain existing omission/null behavior; this task does not widen the page model.

`src/Notion/V1.hs` exposes `Methods`, including retrieve/create/update page, data-source query, and search functions. It imports resource types rather than re-exporting the entire resource modules; expose the helpers in the already-public `Notion.V1.PropertyValue` and `Notion.V1.Pages` modules. `src/Notion/V1/DataSources.hs` decodes query results into `PageOrDataSource`: `PageResult` contains a full `PageObject`, `PartialPageResult` contains an ID only, with equivalent data-source cases and an unknown raw result. Full pages are identified by the `url` key. `src/Notion/V1/Search.hs` uses the same union. No new union encoder or endpoint signature is needed; consumers extract a full page and call the page helper.

Relevant existing tests are `tasty/Main.hs`'s `Property Value` group, `tasty/ObjectFieldTests.hs`'s property and request assertions, and `tasty/DataSourceSearchTests.hs`'s full/partial query fixtures. `tasty/FakeNotion.hs` provides `fakeClientEnv` and `jsonReply` for scripted HTTP responses without network access; `tasty/RuntimeTests.hs` shows how to use them with `makeMethodsWithEnv`. Request-body capture examples are in `tasty/ObjectFieldTests.hs`. Use these facilities for endpoint decoding tests; no live token is required.

[ADR 1](../adr/1-tolerant-response-decoders.md) requires unknown discriminator fallbacks to survive serialization. [ADR 4](../adr/4-full-or-partial-responses-and-request-only-types.md) separates incompatible read/write shapes and requires explicit partial cases. [ADR 6](../adr/6-js-sdk-types-are-the-wire-format-reference.md) keeps the API version at `2026-03-11` and uses generated SDK types as the wire reference. [ADR 7](../adr/7-effectful-package-mirrors-methods-in-lockstep.md) requires matching effectful changes whenever `Methods` changes and compatible core bounds on a breaking release. Here helpers are pure, so no new effect operation is needed. Existing ADRs use local Markdown without an OKF profile; preserve that convention when recording the response-serialization decision.

The SDK reference used by ADR 6 is `mori://makenotion/notion-sdk-js` (project-relative source `src/api-endpoints/common.ts`, artifact-level URI pending), tag `v5.26.0`: `PageObjectResponse` starts at line 2014, and `RelationArrayBasedPropertyValueResponse` at line 2919 describes type and reference array but omits `has_more`. Its `src/api-endpoints/pages.ts` models paginated list `has_more` separately at line 243. The official [page-property reference](https://developers.notion.com/reference/page-property-values) supplies the page-relation completeness flag; follow the explicit IR contract with an optional flag rather than making that omitted SDK field mandatory. A list-level flag and a property-level flag are different and must not be confused.

Discover dependencies through Mori before consulting their APIs. For Aeson, `mori registry search aeson`, `mori registry show haskell/aeson --full`, and `mori registry docs haskell/aeson` locate `mori://haskell/aeson/packages/aeson`. Its project-relative sources `aeson/src/Data/Aeson/Types/FromJSON.hs` and `aeson/src/Data/Aeson/KeyMap.hs` (artifact-level URIs pending) confirm optional field decoding and object-key insertion. The existing `.:?` operator preserves supplied false as `Just False` and missing as `Nothing`; it also treats null as absent. Keep malformed non-boolean flags as decoder errors. No Aeson upgrade is needed. Never inspect `/nix/store` or search filesystem root for dependencies.

On 2026-10-12, [Hackage core metadata](https://hackage.haskell.org/package/notion-client/preferred.json) reports latest normal version `0.8.0.0`, and [companion metadata](https://hackage.haskell.org/package/notion-client-effectful/preferred.json) reports `0.2.0.0`. `git ls-remote --tags https://github.com/shinzui/notion-client.git` confirms `v0.8.0.0` and `notion-client-effectful-v0.2.0.0`, both pointing to commit `73432e2935efb6e0853b250502cddfde91a88761`. The checked-in companion bound is `notion-client >=0.8 && <0.9`. Reverify before choosing release versions. The consumer's policy is in `mori://shinzui/notion-cli` (project-relative path `docs/adr/0001-resolve-released-notion-client-packages-from-hackage.md`, artifact-level URI pending): it requires Hackage packages and verified upstream tags, so a neighboring checkout does not satisfy delivery. Mori's registry currently cannot resolve the consumer plan URI, but the registered consumer working tree contains the file; keep the canonical URI.


## Plan of Work


### Milestone 1: Preserve relation metadata and encode property responses


In `src/Notion/V1/PropertyValue.hs`, change the constructor to `RelationValue Text (Vector RelationRef) (Maybe Bool)`. Decode the final field with `o .:? "has_more"`. Update `relationValue` to supply `Nothing` while preserving its public argument type. Adjust all in-repository patterns discovered with `rg -n 'RelationValue' src tasty notion-client-example notion-client-effectful`; initially `tasty/Main.hs` has the direct decode pattern. The mutation encoder discards the new field exactly as it discards the ID. Do not infer a value from an empty array or from a threshold such as 25 references.

Export `propertyValueResponseJSON :: PropertyValue -> Aeson.Value`. Use an exhaustive constructor match to obtain the stored ID, exact type text, and correctly encoded payload. The response envelope is the object containing `id` when nonempty, `type`, and the value under the key matching type. For relations, include `has_more` only for `Just` values. For unknown properties, reuse the unknown type text as both discriminator and payload key, and preserve the raw payload. Nullable modeled values still emit their type key with null. Do not change existing supporting-type instances that already encode their modeled response data. Add private response helpers in `src/Notion/V1/PropertyValue.hs` for `UserValue` and its nested modeled user data, using exported constructors from `Notion.V1.Users`. Partial users emit object/ID; full users emit object/ID/type and supplied name, avatar URL, person email, or bot owner/workspace/limits data. The modeled `UserOwner` user case emits a nested user object with ID, workspace owners emit their Boolean, and unknown owners reuse the raw value. Do not add guessed fields that the decoder never retained.

Use that response user helper for people entries, verification `verified_by`, and user mentions inside title/rich-text property values. Preserve verification state/date and the existing rich-text envelope fields, replace only nested user serialization, and leave other mention kinds and unknown raw mentions unchanged. Group entries retain their modeled object/ID/name. Implement these response-only traversals without modifying `ToJSON UserValue`, `ToJSON PeopleEntry`, `ToJSON MentionContent`, or any mutation instance. These are internal payload helpers; the only required new public APIs remain the property and page functions.

Add an internal response rollup encoder: for `RollupArrayResult`, emit its type, function, and an array obtained by mapping `propertyValueResponseJSON` over the values; for other rollup constructors preserve their existing type/payload/function and unknown raw object behavior. Recursion must work through nested arrays and ID-less unknown entries. Leave mutation `ToJSON RollupResult` unchanged.

Create `tasty/ResponseJSONTests.hs`, export `tests`, register it in `notion-client.cabal`'s test `other-modules`, and import/register it in `tasty/Main.hs` under the group name `Response JSON`. Add field-level response tests covering all 25 constructors, all formula and rollup result forms including fabricated unknown kinds, null select/number, full/partial people and groups, full-user mentions, verification with a full user, bot owners including an unknown owner, and a nested rollup containing an ID-less relation. Use decoded fixtures and typed constructor assertions so a fallback cannot disguise broken decoding. Add mutation regressions for decoded relations with both Boolean states and for `relationValue`/`peopleValue`; also retain existing mutation tests. Assert that a decoded full user still becomes object/ID in a mutation people value, while its response encoding retains its supplied details. This milestone passes when the focused group passes and request-shaped payloads remain identical.

### Milestone 2: Encode full pages and prove endpoint integration


Export `pageResponseJSON :: PageObject -> Aeson.Value` from `src/Notion/V1/Pages.hs`. Reuse its existing page envelope encoding and replace the `properties` object with a map encoded by `propertyValueResponseJSON`, or factor a private page-envelope function parameterized by the property encoder. Preserve the old `ToJSON PageObject` output and avoid duplicating two long field lists that could drift.

In `tasty/ResponseJSONTests.hs`, first prove a representative path: a scripted `retrievePage` response decodes to `PageObject`, the public page helper encodes it, and a relation property retains its ID/type/true flag. Then exercise `createPage`, full results from `queryDataSource`, and `search` using equivalent response fixtures. Extract `PageResult` explicitly and call the helper; assert partial page/data-source and unknown cases still decode as their original constructors. Check page fields independently from property fields, including populated and absent optional states. Extend `tasty/DataSourceSearchTests.hs` only where needed to preserve its mixed-result assertions. No `Methods` or effectful operation changes are expected. This milestone passes when scripted endpoint tests and existing full/partial tests pass without credentials.

### Milestone 3: Document and validate a compatible breaking release


Document the new helpers, `Maybe Bool` semantics, absent-ID sentinel, modeled-data guarantee, and unchanged request encoding in module Haddocks and `README.md`. Add migration examples to `CHANGELOG.md`: old `RelationValue pid refs` patterns become `RelationValue pid refs hasMore`, manually constructed mutation values supply `Nothing`, and callers writing JSON responses switch to the named helper. `relationValue` itself retains its type. Explain that true indicates incomplete relation references and performs no additional HTTP request.

Recheck registry versions and tags. With the verified baseline and no intervening release, choose core `0.9.0.0` for the constructor change, companion `0.3.0.0`, and companion bound `notion-client >=0.9 && <0.10`. If those versions have been taken, choose the next appropriate unoccupied breaking versions and update this plan's release commands and smoke bounds consistently. Update `notion-client.cabal`, `notion-client-effectful/notion-client-effectful.cabal`, and both changelogs together. Pure helpers need no interpreter cases. Build all packages and the example, run tests, generate Haddocks, and check both source distributions. Update ADR 4 to summarize explicit response serialization and update ADR 7 only if its compatibility rule actually changes. This milestone passes when the commands below succeed and migration documentation matches the final public API.

### Milestone 4: Verify published delivery


Prepare core and companion source distributions, confirm version/bound alignment, and use the project's release convention: core tag `v<version>` and companion tag `notion-client-effectful-v<version>`. There is no checked-in release script, so use Cabal source distributions and the maintainer's Hackage upload process. Obtain publication authorization if the implementation session has not already received it. Keep this milestone open while publication is pending, even if local tests pass.

After publication, verify both Hackage metadata and upstream tags again, confirm the released source contains the helpers, and build/run the isolated smoke project described below using only Hackage dependencies. Capture exact versions, tags, commit IDs, smoke output, and test evidence in this plan and IR-1's Delivery evidence. Only then mark IR-1 completed with `completedAt`, update its generated revision metadata and bundle log, and mark this milestone complete. Consumer CLI changes remain owned by the canonical consumer plan.


## Concrete Steps


Run implementation commands from the repository root. Inspect source and add focused regressions before fixing behavior; the new metadata assertions must demonstrate failure against the original implementation. A new helper's absence may initially fail compilation; also record a runtime metadata assertion that fails before retention is fixed.

```bash
cd /Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client
rg -n 'RelationValue|RollupArrayResult' src tasty notion-client-example notion-client-effectful
nix develop -c cabal test notion-client:tasty --test-options='-p "Response JSON"' --test-show-details=direct
nix develop -c cabal build all
nix develop -c cabal test all --test-show-details=direct
nix develop -c cabal haddock notion-client notion-client-effectful
nix develop -c cabal check
(cd notion-client-effectful && nix develop .. -c cabal check)
nix develop -c cabal sdist all
nix fmt
git diff --check
```

Use the already-entered development shell's `cabal` commands directly if available. Focused tests must report the Response JSON cases passing, the full suite must report all enabled tests passing, and both libraries/example must compile. The suite has optional live tests controlled by environment variables in `tasty/Main.hs`; absent credentials produce explicit skipped groups, which must be recorded as skipped rather than live evidence. Cabal source distributions appear under `dist-newstyle/sdist/`. Haddocks must expose both helper signatures. New Haskell files may need `git add` before Nix sees them; stage only intended changes. Do not create a branch unless asked.

Before release selection and after publication, run:

```bash
curl -fsSL https://hackage.haskell.org/package/notion-client/preferred.json
curl -fsSL https://hackage.haskell.org/package/notion-client-effectful/preferred.json
git ls-remote --tags https://github.com/shinzui/notion-client.git
```

After publication, create a temporary directory outside this checkout with a `cabal.project` containing only `packages: .`, a `response-json-smoke.cabal`, and `Main.hs`. Use these contents for the expected `0.9.0.0`/`0.3.0.0` release pair; update exact versions if Milestone 3 selected different ones. No source-repository-package or neighboring package paths are allowed.

```cabal
cabal-version: 3.4
name: response-json-smoke
version: 0.1.0.0
build-type: Simple
executable response-json-smoke
  main-is: Main.hs
  default-language: GHC2024
  build-depends: base, aeson >=2.2 && <2.3, notion-client ==0.9.0.0, notion-client-effectful ==0.3.0.0
```

```haskell
{-# LANGUAGE OverloadedStrings #-}
import Data.Aeson qualified as A
import Data.Aeson.KeyMap qualified as KM
import Notion.V1.Pages (PageObject, pageResponseJSON)
import Notion.V1.PropertyValue (PropertyValue, propertyValueResponseJSON)

main :: IO ()
main = do
  let prop = "{\"id\":\"rel\",\"type\":\"relation\",\"relation\":[],\"has_more\":true}"
      page = "{\"object\":\"page\",\"id\":\"p1\",\"created_time\":\"2026-10-12T00:00:00Z\",\"last_edited_time\":\"2026-10-12T00:00:00Z\",\"created_by\":{\"object\":\"user\",\"id\":\"u1\"},\"last_edited_by\":{\"object\":\"user\",\"id\":\"u1\"},\"parent\":{\"type\":\"workspace\",\"workspace\":true},\"in_trash\":false,\"properties\":{\"Related\":{\"id\":\"rel\",\"type\":\"relation\",\"relation\":[],\"has_more\":true}},\"url\":\"https://www.notion.so/p1\"}"
  p <- either fail pure (A.eitherDecode prop :: Either String PropertyValue)
  expected <- either fail pure (A.eitherDecode prop :: Either String A.Value)
  if propertyValueResponseJSON p /= expected then fail "property metadata lost" else pure ()
  pg <- either fail pure (A.eitherDecode page :: Either String PageObject)
  case pageResponseJSON pg of
    A.Object o | Just (A.Object ps) <- KM.lookup "properties" o,
                 KM.lookup "Related" ps == Just expected -> putStrLn "published response encoders: OK"
    _ -> fail "page metadata lost"
```

Run `cabal update`, `cabal build all`, and `cabal run response-json-smoke` from that temporary directory inside an available GHC 9.12 development environment. Success prints `published response encoders: OK`; the dependency solver must select the exact published versions of both packages. This proves a published consumer can import and exercise both public helpers without workspace overrides.

For IR edits, update `generated.at` to the meaningful revision time while preserving existing reviews and their historical `document_timestamp`. Append a bundle log entry with `okf log add docs/improvement-requests --kind Update -m '<concise change and plan path>'`, then run:

```bash
okf validate docs/improvement-requests --strict --profile docs/improvement-requests/profile.dhall --profile-enforce --log-enforce
git diff --check
```

Expected validation is `OK: 1 concepts (okf_version 0.2)` unless more requests have since been added. Record one provenance revision for the implementation session using the skill's `record-provenance.ts` and verified current-agent identity. Every implementation commit uses Conventional Commits and includes `ExecPlan: docs/plans/15-preserve-page-property-response-metadata-and-expose-response-json-encoders.md` and `Intention: intention_01m4s6pz9wekf8a8tm26a2jn0v` trailers.


## Validation and Acceptance


AC-1 passes only when three otherwise-identical relation fixtures decode as `Just True`, `Just False`, and `Nothing`, including empty reference arrays with true/false flags and a nonempty array with absent flag. Assert the constructor's metadata directly. Response encoding must include each supplied Boolean and omit the absent key.

AC-2 passes when every property constructor emits its actual nonempty ID, its exact type discriminator, and its modeled payload. Check null values explicitly, typed people and formulas, full user details in people/verification/mentions, both known and fabricated unknown payloads, nested rollups, and unchanged URL-encoded IDs. ID-less rollup entries must omit `id`, not emit an empty or invented value. Compare `Aeson.Value` structures or individual fields rather than encoded key order. Existing decoder filtering of empty rollup-summary placeholders is outside the modeled-data guarantee.

AC-3 passes when decoded pages from scripted retrieve/create/query/search responses retain property metadata through `pageResponseJSON` and preserve all other modeled fields under current encoding conventions. Tests must verify populated optional fields and absent ones, while mixed query/search fixtures still produce explicit partial and unknown constructors. This representative endpoint path is the early producer/consumer proof; compilation alone is insufficient.

AC-4 passes when `Aeson.toJSON` on both decoded response values and smart-constructed write values remains request-shaped. Create/update request-builder tests inspect each property envelope for absence of newly added `id`, `type`, and `has_more`, while retaining nested relation page IDs, user IDs, and legitimate nested type fields. A recursive ban on all IDs/types would be incorrect.

AC-5 passes after both package libraries and the example compile, all applicable core tests pass, public Haddocks and changelog examples match the API, and compatible breaking versions/bounds are ready. The effectful package has no separate test suite; do not claim one ran. AC-6 passes only after both required releases and matching tags exist and the isolated Hackage-only consumer smoke test succeeds. Local success without publication leaves Milestone 4 and IR completion open.


## Idempotence and Recovery


Offline tests, builds, docs, formatting, registry reads, and validation can be repeated. Preserve user edits and use focused diffs; do not reset the working tree. If a representative endpoint fixture fails, resolve decoder/encoder disagreement before expanding coverage. Keep mutation regression evidence valid after each encoder change.

Recheck versions immediately before release to avoid publishing over an existing version. Do not move existing release tags or assume an interrupted upload failed: inspect Hackage and upstream first, then finish only the missing release step. Publishing one package is partial delivery until the compatible pair is usable. Keep IR-1 accepted while only planned, in-progress during implementation, and completed only after all six criteria pass. Update historical review metadata only by adding a new review when one actually occurs; do not rewrite old audits as approvals.

Delete only the temporary smoke workspace created for this verification after capturing evidence. No workspace dependency override belongs in either the released package or the consumer's committed configuration.


## Interfaces and Dependencies


The public interfaces are:

```haskell
RelationValue :: Text -> Vector RelationRef -> Maybe Bool -> PropertyValue
relationValue :: [UUID] -> PropertyValue
propertyValueResponseJSON :: PropertyValue -> Aeson.Value
pageResponseJSON :: PageObject -> Aeson.Value
```

The property encoder belongs to `Notion.V1.PropertyValue`, and the page encoder belongs to `Notion.V1.Pages`. Both modules are already exposed in `notion-client.cabal`. Helpers serialize modeled response data; the existing `ToJSON` instances retain their established behavior. The optional relation flag adds no dependency and is not a pagination-fetch instruction.

Use the current Aeson, vector, containers, and Tasty dependencies; no new library or API-version upgrade is required. `notion-client-effectful` remains a companion of the same core API with revised bounds. This standalone plan has no parent MasterPlan or prerequisite implementation plan. Its downstream contract is IR-1 and `mori://shinzui/notion-cli/plans/53-preserve-property-response-metadata-and-add-page-create-json-output`; adopting releases and adding CLI JSON flags belong to that consumer work.
