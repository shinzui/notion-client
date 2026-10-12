---
type: Improvement Request
title: Preserve page property response metadata and expose response JSON encoders
description: >-
  Retain relation has_more when decoding page properties and expose response-specific
  property/page JSON encoders that preserve property IDs and types without changing
  mutation request encoding.
requestId: IR-1
status: accepted
targetPlan: docs/plans/15-preserve-page-property-response-metadata-and-expose-response-json-encoders.md
origin: mori://shinzui/notion-cli/plans/53-preserve-property-response-metadata-and-add-page-create-json-output
generated:
  by: openai-codex/gpt-6.1-sol
  at: "2026-10-12T23:24:56Z"
reviews:
  - kind: model
    reviewer: openai-codex/gpt-6.1-sol
    reviewed_at: "2026-10-12T22:57:32Z"
    document_timestamp: "2026-10-12T22:57:07Z"
    scope: technical-accuracy
    outcome: commented
    context: >-
      Author source audit against PropertyValue's relation decoder/request encoder,
      PageObject encoding, ADRs 1/4/7, and the requesting consumer plan. This records
      observed implementation gaps, not an independent approval or delivery evidence.
    provider: openai
    model: gpt-6.1-sol
    effort: high
acceptanceCriteria:
  - id: AC-1
    statement: >-
      Decoding a relation property preserves has_more true, false, and absent as distinct
      states available to callers; no state is inferred from the number of references.
    verification: >-
      Decode three otherwise-identical relation fixtures and assert the retained states
      are Just True, Just False, and Nothing (or equivalent explicitly modeled states).
  - id: AC-2
    statement: >-
      A public response-specific property encoder emits the property's actual ID, type
      discriminator, value payload, and supplied relation has_more. It supports every
      modeled property variant and preserves unknown type names and their raw payloads.
    verification: >-
      Compare decoded fixtures with response-encoded JSON values for relations, null
      select/number, formulas, people, all remaining constructors, and a fabricated
      unknown type. Assert absent metadata is not fabricated, including IDs absent
      from nested rollup array values.
  - id: AC-3
    statement: >-
      A public page response encoder preserves the page's modeled response fields and
      applies response-specific property serialization. Properties in retrievePage,
      createPage, and full query/search page results retain the same metadata.
    verification: >-
      Encode a decoded PageObject fixture through the public helper, check page ID/URL
      and modeled fields, and assert property ID/type/has_more are present as supplied.
      Exercise full page query/search fixtures without changing partial-result handling.
  - id: AC-4
    statement: >-
      Existing mutation encoders and smart constructors continue producing valid
      request-shaped property payloads without newly added response-only ID, type,
      or has_more fields at the property envelope.
    verification: >-
      Regression-test existing PropertyValue ToJSON and create/update request builders,
      including relationValue and peopleValue. Keep legitimate nested object IDs and
      type fields, such as relation reference IDs, unchanged.
  - id: AC-5
    statement: >-
      Both notion-client and notion-client-effectful compile and pass their relevant
      tests together; any changed constructor/API and required version-bound migration
      are documented.
    verification: >-
      Run the repository's build/test workflow for both packages, migrate in-repository
      pattern matches and examples, and document compatibility in the changelog.
  - id: AC-6
    statement: >-
      The response metadata and encoder APIs are available in a published Hackage release
      with a matching upstream tag, with a compatible effectful package release if needed.
    verification: >-
      Verify Hackage package metadata and upstream tags, then compile a small consumer
      importing the public response encoders using only published packages.
---

# Preserve page property response metadata and expose response JSON encoders

## Consumer problem

The requesting consumer is `mori://shinzui/notion-cli`. Its report
`mori://shinzui/notion-cli/okf/bug-reports/concepts/BUG-3` records that page/query JSON drops
property `id`, `type`, and relation `has_more`. Consumer work is tracked by
`mori://shinzui/notion-cli/plans/53-preserve-property-response-metadata-and-add-page-create-json-output`.

The consumer currently serializes the decoded `PropertyValue` using its `ToJSON`
instance. That instance correctly builds mutation payloads, but does not serialize a
complete property response. Fetching the schema cannot recover a discarded relation
completeness flag. A relation's reference count cannot reliably determine the flag either.

The same consumer plan includes
`mori://shinzui/notion-cli/okf/improvement-requests/concepts/IR-5`, which requests
`page create --json`. That CLI option can be implemented independently; this upstream
request concerns the shared response serialization it will consume.

## Current implementation and evidence

In `src/Notion/V1/PropertyValue.hs`, each constructor retains a property ID, but
`RelationValue` stores only the ID and reference vector. The decoder's relation branch
ignores `has_more`. The encoder intentionally omits property IDs and type discriminators:

```haskell
RelationValue Text (Vector RelationRef)

-- FromJSON:
"relation" -> RelationValue pid <$> o .: key

-- ToJSON:
RelationValue _ v -> Aeson.object ["relation" .= v]
```

`src/Notion/V1/Pages.hs` serializes `PageObject.properties` with the same instance.
Consequently the information loss also affects consumers serializing full page results.
The property ID/type are recoverable from modeled constructors, but `has_more` must be
retained while decoding.

Relevant test locations include `tasty/Main.hs`'s property-value tests,
`tasty/ObjectFieldTests.hs`'s unknown-property coverage, and
`tasty/DataSourceSearchTests.hs`'s full/partial result fixtures. Preserve their existing
request-encoding assertions while adding explicit response-encoding coverage.

## Requested change

Expose a clear public distinction between response serialization and mutation serialization.
The suggested helper names and signatures are:

```haskell
propertyValueResponseJSON :: PropertyValue -> Aeson.Value
pageResponseJSON :: PageObject -> Aeson.Value
```

These names are proposals; an equivalent public interface is acceptable. Put the
property helper in `Notion.V1.PropertyValue` and the page helper in `Notion.V1.Pages`,
or document their final module locations for consumers.

Retain a relation's supplied completeness state, for example as `Maybe Bool`.
Missing `has_more` must remain distinct from false. Do not fabricate absent IDs for
nested rollup values, and apply response serialization recursively where rollups
contain property values. Unknown property type names and raw value payloads must
survive response encoding.

Keep the existing mutation `ToJSON` behavior. If the implementation extends the
`RelationValue` constructor, update its smart constructor and all pattern matches
consistently, document the breaking change, and choose the release version according
to the project's compatibility policy. An alternative response wrapper is acceptable
if it meets all criteria without losing metadata.

The page encoder needs to preserve modeled response data. This request does not
promise byte-for-byte raw HTTP responses or preservation of every currently unmodeled
top-level field; document that distinction. It also does not request automatic
retrieval of remaining relation references when `has_more` is true.

## Architecture and release constraints

[ADR 1](../adr/1-tolerant-response-decoders.md) requires unknown-value fallbacks.
[ADR 4](../adr/4-full-or-partial-responses-and-request-only-types.md) separates
incompatible request and response shapes and preserves explicit partial responses.
This work should follow both decisions.

[ADR 7](../adr/7-effectful-package-mirrors-methods-in-lockstep.md) requires corresponding
effectful changes whenever `Methods` changes and compatible bounds when the core
major version changes. Pure encoder helpers need no new effect constructors, but
the companion package must remain buildable against the chosen core release.

The consumer resolves published packages from Hackage under
`mori://shinzui/notion-cli` (project-relative path
`docs/adr/0001-resolve-released-notion-client-packages-from-hackage.md`;
the artifact-level URI is pending). A local source checkout does not fulfill the
consumer release gate. Confirm the published version against Hackage and upstream
tags before choosing consumer bounds or Nix pins.

## Delivery evidence

This request is accepted for implementation in
[ExecPlan 15](../plans/15-preserve-page-property-response-metadata-and-expose-response-json-encoders.md),
which covers all six acceptance criteria, including compatible published releases.
Implementation has not started. The criteria describe evidence to collect during implementation;
no upstream change or release is claimed here. The review record documents the author's
source audit; no independent approval or live acceptance evidence is claimed.
