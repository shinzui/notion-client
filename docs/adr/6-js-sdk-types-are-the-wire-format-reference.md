# ADR 6: The official JS SDK types are the wire-format reference, and the API version stays pinned

Status: Accepted
Date: 2026-09-15


## Context

Notion's prose API reference is incomplete and sometimes out of date. Earlier gap analyses in this
repository (`docs/plans/1-notion-api-gap-analysis.md`, `docs/plans/2-close-api-gaps.md`) used it
as their source, and the client still shipped decoders that failed on real responses. It also
shipped encoders Notion rejected, for example `filter_properties` sent in the body and `children`
sent on block updates.

Notion's TypeScript SDK, `@notionhq/client`, generates its request and response types in
`src/api-endpoints/*.ts` from Notion's own API schema. Comparing against v5.26.0 in
`docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md`
found every one of those defects.

The SDK defaults to `Notion-Version: 2025-09-03`, but its types describe `2026-03-11` behavior.
This library had already migrated to `2026-03-11` (`docs/plans/complete-2026-03-11-upgrade.md`),
where `in_trash` replaces `archived`.


## Decision

- **Reference.** When the wire format is in question, the JS SDK's generated types decide it:
  which keys a request may carry, which fields are optional or nullable, and which variants a
  union has. Prose documentation is secondary. Plans cite the SDK file and line they transcribe,
  and tests use fixtures transcribed from those types.
- **Version.** The default `Notion-Version` stays `2026-03-11` (`defaultNotionVersion` in
  `Notion.V1.Client`). Callers can change it through `ClientConfig.notionVersion`. The library
  does not follow the SDK's older default.
- **Live checks.** A live check against the API overrides the SDK types when they disagree. For
  example, the HTTP 202 responses recorded in
  [ADR 3](3-background-operations-accept-200-or-202-and-return-asyncor.md) were found live.


## Consequences

- Parity work is a mechanical comparison against a checkout of the SDK. Upgrading the reference
  means diffing `src/api-endpoints` between SDK tags.
- Types the SDK marks as unpublished (see [ADR 8](8-core-parity-scope-exclusions.md)) are not a
  reference for this library's core API.
- The SDK types do not show HTTP status codes or runtime behavior, so the library still needs live
  checks for those.
