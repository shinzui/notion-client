# ADR 1: Response decoders fall back to an "unknown" constructor instead of failing

Status: Accepted
Date: 2026-09-15


## Context

`notion-client` decodes Notion responses with `aeson` `FromJSON` instances. A single failing
decoder anywhere in a response fails the entire call, so one unfamiliar value (a new color, a
new code-block language, a new mention kind) used to make a whole page, block list or query
result unreadable. Notion adds such values without changing the API version, and its official
JavaScript SDK types several of these sets as open (for example `NumberFormat = string`).

The comparison against the official SDK in
`docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md`
found this failure in `Color`, `Parent`, `Icon`, `MentionContent`, `CodeLanguage`,
`NumberFormat`, `FormulaResult` and `UserOwner`. Users hit it on ordinary pages (a
`default_background` text span, a `toml` code block).


## Decision

Every closed enum or sum type that is decoded from a Notion response has an explicit fallback
constructor that carries the raw wire value, and its decoder uses that constructor instead of
calling `fail` on an unrecognised discriminator:

- string enums carry the raw `Text` (`UnknownColor Text`, `OtherLanguage Text`,
  `OtherNumberFormat Text`, `UnknownMeetingNotesStatus Text`);
- tagged objects carry the raw JSON `Value` (`UnknownParent Value`, `UnknownIcon Value`,
  `UnknownMention Value`, `UnknownFormulaResult Value`), or the discriminator plus the value
  (`UnknownOwner`, and the older `UnknownBlock Text Value`).

The matching `ToJSON` instance re-emits the raw value unchanged, so a decoded response round-trips.
Decoders still fail on structurally wrong input (for example, a non-object where an object is
required); the fallback is only for unrecognised discriminator values.

One refinement (2026-09-15, from `docs/plans/9-add-view-queries-and-typed-view-configuration.md`)
applies to values nested inside a larger response whose typed model is known to be incomplete.
Examples are view configurations (`ViewConfig`, `GroupByConfig`, `FormulaSubGroupBy`) and view
filters, sorts and quick filters. For these, the fallback also catches a failed typed parse of a
recognised discriminator (`typed <|> pure (Unknown… v)`). That way one unmodelled field shape
cannot fail the whole view. Tests for such types assert the typed constructor of nested values,
not only a byte-for-byte round trip, because a broken typed decoder would still round-trip
through the fallback.

The filter and sort DSL in `Notion.V1.Filter` applies the refinement in its own decoders
(2026-09-15, from `docs/plans/10-type-data-source-database-and-search-results-and-close-query-and-filter-gaps.md`).
`Filter`, `PropertyCondition` and `Sort` carry `UnknownFilter Value`, `UnknownCondition Text Value`
and `UnknownSort Value`, and the condition decoder picks the condition key before parsing. A
malformed known condition then keeps its key in `UnknownCondition`. The same applies to
`UnknownSchema` for property schemas and `UnknownResult` for query and search results. Wrappers
that callers added before these fallbacks existed (`RawViewFilter`, `RawViewSort`) are no longer
reached, but stay for compatibility.

Page objects, users and webhooks apply the same rule (2026-09-15, from
`docs/plans/11-close-page-block-property-value-user-file-upload-and-webhook-field-gaps.md`).
`PropertyValue` gains `UnknownPropertyValue Text Text Value`, `RollupResult` gains
`RollupUnknownResult`, and `ObjectType`, `NoticonColor`, `VerificationState` and the webhook
enumerations gain `Unknown…` constructors. Two decoders use the parse-failure refinement:

- A user inside a mention, people value or verification value (`UserValue`) that has a `type` key
  but does not decode as a full `UserObject` becomes `PartialUser`, keeping its ID.
- `parseEventData` never fails. When a webhook's `data` does not match the typed shape for its
  event type, or the event type is untyped, the object is kept as `RawEventData Value`. The event
  still decodes.

When a later change types a value that was previously falling back, it adds a new constructor
and keeps the fallback. Tests for the fallback use made-up discriminators, so they keep
exercising it after new kinds are typed.


## Consequences

- Responses containing values newer than the library decode; callers see the unknown value
  instead of an exception.
- Adding a fallback constructor is a breaking change under the Haskell Package Versioning Policy
  (exhaustive pattern matches gain a missing case), so introducing one requires a major version
  bump.
- Handwritten instances replace generic ones for these types (for example, `Color` now uses a
  lookup table), which is slightly more code to maintain.
- When a type-directed parser replaces `fail $ "..." <> unpack t` with a fallback, the
  discriminator's type must be annotated (`t :: Text <- o .: "type"`). Before, `unpack` was what
  fixed its type.
