# ADR 5: Clearable request fields, and one type for a configuration read and sent back

Status: Accepted
Date: 2026-09-15


## Context

Some Notion update endpoints distinguish three states for a field: the key is absent (leave the
setting unchanged), the key is `null` (clear the setting), or the key holds a value. The
update-view body is the first case in this library. `filter`, `sorts`, `quick_filters` and most
view configuration fields accept `null` to clear them.

The shared `aesonOptions` in `src/Notion/Prelude.hs` set `omitNothingFields = True`. A `Maybe`
field can therefore only be omitted, never sent as `null`. `Maybe (Maybe a)` could model the
three states, but `Just Nothing` says nothing at a call site, and generic instances do not
produce the right wire shape for it.

View configurations raise a second question. Unlike comment attachments (see
[ADR 4](4-full-or-partial-responses-and-request-only-types.md)), their request and response
shapes differ only in a few response-only convenience fields (`property_name`,
`date_property_name`, `map_by_property_name`), in nullability, and in a response-only dashboard
configuration. A user typically retrieves a view, changes one setting and sends the
configuration back.

`docs/plans/9-add-view-queries-and-typed-view-configuration.md` settled both questions for views.


## Decision

- **Three-state fields.** Request fields that Notion lets callers clear with `null` use
  `Clearable a = Unset | Clear | Set a` from `Notion.V1.Clearable`. Its `ToJSON` instance
  overrides aeson 2.2's `omitField`, so `Unset` omits the key inside any record encoded with
  `genericToJSON aesonOptions`. Its `FromJSON` instance overrides `omittedField`, so a missing key
  decodes as `Unset` and `null` as `Clear`. Records keep using generic instances. Outside a
  record, for example as a `Map` value, use `Maybe` instead, because there `Unset` also encodes as
  `null`.
- **One type for both directions.** When the request and response shapes differ only in
  response-only names and nullability, one record serves both. Its encoder drops the
  response-only keys (`dropKeys` in `Notion.V1.ViewConfig`), so a decoded value can be sent back
  unchanged. When the shapes differ structurally, ADR 4's separate request-only types still apply.
- **Typed values with a raw escape hatch.** A response value that the library's typed DSL
  cannot always express, such as a view filter, is wrapped as `Typed | Raw Value`
  (`ViewFilter`/`RawViewFilter`, `ViewSort`, `QuickFilter`). The raw constructor is also available
  in requests, so callers are never blocked by a missing type.


## Consequences

- The `aeson >=2.2` lower bound is now load-bearing: `omitField` and `omittedField` do not exist
  in earlier versions.
- Switching an existing `Maybe` request field to `Clearable` is a breaking change.
- Record literals must name every field, and record-update syntax on these request types is
  ambiguous under `DuplicateRecordFields`. The tests and examples write full literals.
- The dashboard configuration encodes even though Notion does not accept it in requests. Its
  Haddock comment says so.
