---
id: 11
slug: close-page-block-property-value-user-file-upload-and-webhook-field-gaps
title: "Close Page, Block, Property Value, User, File Upload, and Webhook Field Gaps"
kind: exec-plan
created_at: 2026-09-14T18:46:51Z
master_plan: "docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md"
intention: intention_01m2jjvjgpef9tyyp50524jfwq
provenance:
  created_by:
    model: "claude-opus-5"
    harness: "claude-code"
    at: 2026-09-14T18:46:51Z
  revisions:
    - model: "claude-opus-5[1m]"
      harness: "claude-code"
      at: 2026-09-15T15:08:04Z
      mode: "implement"
      note: "Implemented EP-6 milestones"
---

# Close Page, Block, Property Value, User, File Upload, and Webhook Field Gaps

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

`notion-client` is a Haskell client for the Notion HTTP API. Notion also publishes an official TypeScript client, `@notionhq/client` v5.26.0, whose request and response types are generated from Notion's own API schema. In this plan "the JS SDK" means the checkout of that client at `/Users/shinzui/Keikaku/hub/notion-sdk-js`. Its types are the reference for what goes over the wire.

This plan is child EP-6 of the MasterPlan `docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md`. It closes the gaps that remain in pages, blocks, page property values, rich-text mentions, users, file uploads and webhooks. The work is additive for the most part, but some of it is breaking.

After this plan lands, a Haskell user can do the following:

1. **Partial block updates.** Update part of a block without resending all of it. For example, tick a to-do's checkbox by sending `{"to_do":{"checked":true}}`, change only a table's header flags, or move a block to the trash by sending `{"in_trash":true}`. Today `updateBlock` sends a whole `BlockContent`, including `table_width` and `children`, and Notion rejects those fields on update.
2. **Page requests.** Create a page with no parent or no properties, ask for filtered properties in the create and update responses, and insert markdown at the start or end of a page. The client also stops accepting shapes that Notion rejects: a `none` template on update, and `position` on move.
3. **Typed values.** Read typed place, verification and group-member values, rollup arrays, and the pagination metadata of property items.
4. **Mentions.** Read `link_mention` and `custom_emoji` mentions, and the full user object inside a user mention.
5. **File uploads and objects.** Read `upload_url`, `complete_url` and a typed `created_by` on file uploads, and send a typed upload `mode`. Custom-emoji icons keep their `name` and `url`, native icon colors are typed, and the new object types are recognized.
6. **Webhooks.** Decode file-upload and transcript-deleted webhook events, `workspace_name` and `api_version`, and typed event `data` for every event family.

To see it working, run `cabal test` and watch the new `ObjectFieldTests` group pass. Each of its tests decodes or encodes a JSON fixture copied from the JS SDK types.


## Progress

- [x] Prerequisite check: EP-1 (`docs/plans/6-fix-wire-format-decoding-and-encoding-bugs-found-against-the-official-sdk.md`) has landed (see Concrete Steps, step 0). (2026-09-15)
- [x] Milestone 1: create `tasty/ObjectFieldTests.hs`, register it in `notion-client.cabal` and `tasty/Main.hs`. (2026-09-15)
- [x] Milestone 1: `CreatePage.parent` optional; empty `properties` omitted on create and update. (2026-09-15)
- [x] Milestone 1: `createPageFiltered` / `updatePageFiltered` methods with `filter_properties` query parameter, mirrored in `notion-client-effectful`. (2026-09-15)
- [x] Milestone 1: `UpdatePageTemplate` (no `none`) on `UpdatePage`; `UpdatePage.icon`/`cover` are `Clearable`. (2026-09-15)
- [x] Milestone 1: `MovePage` narrowed to `MovePageParent`, `position` removed. (2026-09-15)
- [x] Milestone 1: `InsertContentRequest.position` (`InsertAtStart` / `InsertAtEnd`). (2026-09-15)
- [x] Milestone 1: `BlockUpdatePayload` / `BlockUpdateContent` replace `BlockUpdate`; `blockUpdateFromContent`, `trashBlockUpdate`; `updateBlock` route and effectful constructor updated. (2026-09-15)
- [x] Milestone 1: audio and embed `caption`; `UnsupportedBlock` carries `block_type`; `tabBlock` smart constructor. (2026-09-15)
- [x] Milestone 1: fix existing tests and examples that break; `cabal build all` and `cabal test` green (325 tests). (2026-09-15)
- [x] Milestone 2: `SelectOptionValue.description`. (2026-09-15)
- [x] Milestone 2: `UserValue`, `GroupObject`, `PeopleEntry` in `Notion.V1.Users`; `PeopleValue` uses `PeopleEntry`; `Eq` derived on user types. (2026-09-15)
- [x] Milestone 2: typed `Place`, `VerificationResult` with `VerificationState`, smart constructors `placeValue`, `verifiedValue`, `unverifiedValue`. (2026-09-15)
- [x] Milestone 2: typed `RollupArrayResult`, `RollupUnknownResult`, `UnknownPropertyValue`, `id` optional on property values. (2026-09-15)
- [x] Milestone 2: `PropertyItemList` with `next_url` and rollup summary. (2026-09-15)
- [x] Milestone 2: `CustomEmojiRef` in `Common.hs`; `LinkMention`, `CustomEmojiMention`, `UserMention` carrying `UserValue`. EP-1's two mention fallback tests already used made-up types (`future_mention`, `future_emoji`), so they needed no change. (2026-09-15)
- [x] Milestone 2: tests green (337 tests). (2026-09-15)
- [x] Milestone 3: `CustomEmojiIcon` carries `CustomEmojiRef` (id, name, url); EP-1's custom-emoji icon tests updated (the decode test now expects the `name` and `url` its fixture already carried). (2026-09-15)
- [x] Milestone 3: `NoticonColor` on `NativeIcon`; `ObjectType` additions with `UnknownObjectType` fallback; `PageMarkdown.object`. (2026-09-15)
- [x] Milestone 3: `FileUploadObject.uploadUrl`, `completeUrl`, typed `createdBy`; typed `FileUploadMode` on `CreateFileUpload`. (2026-09-15)
- [x] Milestone 3: bot user `{}` decode test (passed without a decoder change); tests green (344 tests). (2026-09-15)
- [x] Milestone 4: webhook event types and entity types; `workspaceName`, `apiVersion`. (2026-09-15)
- [x] Milestone 4: `WebhookEventData` typed per event family with raw fallback. (2026-09-15)
- [x] Milestone 4: tests green (354 tests, 46 in `Object Field Gaps`); CHANGELOG `## Unreleased` entries complete. (2026-09-15)
- [x] Validation: live partial to-do update and trash against a real page. (2026-09-15)
- [x] ADR distillation: amended ADRs 1, 4 and 5. (2026-09-15)


## Surprises & Discoveries

- The plan was drafted before EP-2 to EP-5 landed. EP-3 had already added `createPageAsync`, which wraps `CreatePage` in `AllowAsync` and uses its own `AsyncVerb` route, so `createPage`'s return type is still `PageObject` and `createPageFiltered` uses it too. EP-4 had added `Notion.V1.Clearable` (ADR 5), and `docs/adr/` now exists, so the "no ADRs" statement in Context and Orientation is out of date.
- Naming the payload field `content`, as the plan specified, broke `Blocks.content block` in `notion-client-example/BlockDemo.hs`. `Notion.V1.Blocks` re-exports `Notion.V1.BlockContent`, so the two `content` fields became ambiguous at every qualified use site:

    ```text
    notion-client-example/BlockDemo.hs:188:10: error: [GHC-87543]
        Ambiguous occurrence ‘Blocks.content’.
    ```

- EP-1's mention fallback tests in `tasty/WireFormatTests.hs` had already been rewritten during MasterPlan review to use `future_mention` and `future_emoji`, so the Milestone 2 step that renames them was unnecessary.
- The live check in Validation and Acceptance passed on 2026-09-15. A partial `to_do` update kept the block's text, and `trashBlockUpdate` trashed it:

    ```text
    AFTER PARTIAL UPDATE: ToDoBlock {richText = [RichText {plainText = "EP-6 live check: check me", ...}], color = Default, checked = True, children = []}
    AFTER TRASH in_trash=True
    ```

- `"bot":{}` already decoded, because every `BotUser` field is `Maybe`, so the bot-user test passed without a decoder change.
- Lazy `Data.ByteString.Lazy.Char8` string literals truncate non-ASCII characters, so a fixture containing `こんにちは` failed with `Invalid UTF-8 stream`. `tasty/ObjectFieldTests.hs` takes fixtures as `Text` and encodes them as UTF-8.


## Decision Log

- Decision: Replace the `BlockUpdate` newtype with a new request type, `BlockUpdatePayload`. It holds an optional `BlockUpdateContent` plus an optional `inTrash`. `blockUpdateFromContent :: BlockContent -> Maybe BlockUpdateContent` is provided as the migration path.
  Rationale: The JS SDK's `UpdateBlockBodyParameters` (`blocks.ts:825-1061`) is a different shape from block creation. `table` accepts only `has_column_header`/`has_row_header`. Media blocks accept `{caption?, external?, file_upload?, name?}`. No update variant has `children`. There is a variant that carries only `in_trash`. Some block types (`child_page`, `column_list`, `meeting_notes`, `link_preview`, `unsupported`) cannot be updated at all. Reusing `BlockContent` makes invalid requests easy to write, and Notion rejects them. A conversion function keeps old call sites one line away from compiling.
  Date: 2026-09-14

- Decision: Model only the update fields the JS SDK actually marks optional. The rich text of paragraph, code, to_do and callout updates is `Maybe`. The rich text of heading, bulleted/numbered list, quote, toggle and template updates stays required.
  Rationale: `ContentWithRichTextColorAndIconUpdateRequest` (`common.ts:301-305`) and the inline `code`, `to_do` and `callout` shapes make `rich_text` optional. `ContentWithRichTextAndColorRequest`, `HeaderContentWithRichTextAndColorRequest` and `ContentWithRichTextRequest` (`common.ts:2730-2749`) keep `rich_text` required. The gap report's claim that every update field is optional is only partly true.
  Date: 2026-09-14

- Decision: Remove `position` from `MovePage`, and narrow `parent` to a new `MovePageParent = MoveToPage UUID | MoveToDataSource UUID`.
  Rationale: `MovePageBodyParameters` (`pages.ts:657-674`) has only `parent`, which is `page_id` or `data_source_id`. The JS SDK is the reference for the wire format. Sending an unknown body key risks a `validation_error`. EP-1 explicitly left `MovePage.position` unchanged and deferred it to this plan, because it is not a proven runtime failure.
  Date: 2026-09-14

- Decision: Reuse EP-1's `PagePosition` (`PageAfterBlock UUID | PageStart | PageEnd`, in `src/Notion/V1/Pages.hs`) for `CreatePage.position`, and do not define another page-position type.
  Rationale: EP-1 owns the `CreatePage.position` encoding fix. This plan only rewrites `CreatePage`'s ToJSON (to omit empty properties), so it must keep emitting `position` through EP-1's type.
  Date: 2026-09-14

- Decision: Leave the `unsupported` formula result and the unknown-formula fallback to EP-1. That plan adds `FormulaUnsupportedResult` and `UnknownFormulaResult Value`.
  Rationale: This is the coordinator's scoping, and EP-1's draft already includes both. Duplicating them would conflict.
  Date: 2026-09-14

- Decision: This plan owns the `name` and `url` of custom-emoji icons. `CustomEmojiIcon {customEmojiId :: UUID}` becomes `CustomEmojiIcon {customEmoji :: CustomEmojiRef}`, sharing the `CustomEmojiRef {id, name?, url?}` type with the new `CustomEmojiMention`.
  Rationale: EP-1 fixes only the nesting (`{"type":"custom_emoji","custom_emoji":{"id":...}}`) and keeps the single-field constructor. Its Decision Log hands `name`/`url` to this plan. A shared record avoids two parallel shapes for the same wire object (`common.ts:393-400` response, `2222-2233` request). Adding two `Maybe` fields beside `customEmojiId` was rejected: existing record-syntax constructions would compile with only a warning and then crash at encode time on the missing fields.
  Date: 2026-09-14

- Decision: When adding typed `link_mention` and `custom_emoji` mentions, rewrite EP-1's two tests that use those mention types as examples of `UnknownMention`, so they use a made-up type such as `"hologram_mention"`.
  Rationale: Once the mentions are typed, those fixtures no longer produce `UnknownMention`. The fallback behavior those tests protect is still worth testing.
  Date: 2026-09-14

- Decision: Add `filter_properties` to page create and update as two new `Methods` fields, `createPageFiltered` and `updatePageFiltered`. The existing `createPage` and `updatePage` become wrappers that pass `[]`.
  Rationale: This mirrors the existing `retrievePage`/`retrievePageFiltered` pair in `src/Notion/V1.hs`. The change is non-breaking. `createPage` (`pages.ts:455-473`) and `updatePage` (`pages.ts:633-650`) both list `filter_properties` in `queryParams`.
  Date: 2026-09-14

- Decision: Do not add a `content` field to `CreatePage`.
  Rationale: `content` and `children` are aliases (`pages.ts:429-430`) with identical element types, and `CreatePage.children` already covers it. Two fields with the same meaning would only let users set conflicting values.
  Date: 2026-09-14

- Decision: Make `CreatePage.parent` a `Maybe Parent`, but keep `properties :: PageProperties` (a `Map`) on both `CreatePage` and `UpdatePage`. The ToJSON instances omit the key when the map is empty.
  Rationale: Omitting an empty map on encode gives the JS SDK's "optional properties" semantics without breaking every record literal that sets `properties = Map.empty`. `parent` has no such "empty" encoding, so it must become `Maybe`. `mkCreatePage :: Parent -> PageProperties -> CreatePage` keeps its signature.
  Date: 2026-09-14

- Decision: Introduce `UpdatePageTemplate` (default template or template by ID) for `UpdatePage.template`. `Template` with its `NoTemplate` constructor stays for `CreatePage`.
  Rationale: `UpdatePageBodyParameters.template` (`pages.ts:607-613`) has no `{type:"none"}` variant.
  Date: 2026-09-14

- Decision: Represent users inside mentions, people values and verification values as `UserValue = PartialUser UUID | FullUser UserObject`, and people entries as `PeopleEntry = PersonEntry UserValue | GroupEntry GroupObject`. The `created_by` and `last_edited_by` property values stay `UserReference`.
  Rationale: JS `UserValueResponse` is `PartialUserObjectResponse | UserObjectResponse` (`common.ts:1618`), and people arrays may contain `GroupObjectResponse` (`common.ts:2902-2905`). `UserReference` already decodes both partial and full users for `created_by`/`last_edited_by` without failing, so changing them would add breakage without fixing a decode failure.
  Date: 2026-09-14

- Decision: Defer "partial object" responses (`PartialBlockObjectResponse {object, id}`, `blocks.ts:573`; `PartialPageObjectResponse`, `common.ts:2007-2012`). Methods returning `BlockObject`/`PageObject` are not changed.
  Rationale: Supporting partial objects means changing the return type of about ten `Methods` fields across pages and blocks, and the same question exists for data sources and view queries in EP-5 and EP-4. One shared representation should be decided once, at the MasterPlan level, rather than invented here. This is recorded as an integration concern for the MasterPlan coordinator.
  Date: 2026-09-14

- Decision: Type `file_upload.upload_failed` webhook data with the existing `Notion.V1.FileUploads.FileImportResult`, not EP-3's `AsyncTask`.
  Rationale: The webhook `file_import_result` shape (`webhooks.ts:294-325`) is the same `{type, imported_time, success|error}` object that `FileImportResult` already decodes (`src/Notion/V1/FileUploads.hs:80-111`). EP-3 therefore provides nothing this plan needs, and the MasterPlan's soft dependency on EP-3 for this item is moot. The other three `file_upload.*` events carry no `data` at all (`webhooks.ts:265-284`).
  Date: 2026-09-14

- Decision: Keep `TabBlock.children :: Vector BlockContent` rather than restricting it at the type level. Add a `tabBlock` smart constructor that builds only valid tab items (paragraphs).
  Rationale: JS restricts tab children to paragraph "tab items" (`common.ts:2476-2478`, `2698-2706`, `2751-2755`). Responses may still decode arbitrary children, so the read type must stay general. The smart constructor makes the valid write shape the easy one.
  Date: 2026-09-14

- Decision: Name the `BlockUpdatePayload` content field `updateContent`, not `content`.
  Rationale: `Notion.V1.Blocks` re-exports `Notion.V1.BlockContent`, so a `content` field would clash with `BlockObject.content` for every user who reads blocks through `Blocks.content` (see Surprises & Discoveries).
  Date: 2026-09-15

- Decision: Make `UpdatePage.icon` and `UpdatePage.cover` `Clearable` (from `Notion.V1.Clearable`) instead of `Maybe`, and keep `CreatePage.icon`/`cover` as `Maybe`.
  Rationale: `UpdatePageBodyParameters` accepts `icon?: PageIconRequest | null` and `cover?: PageCoverRequest | null` (`pages.ts:596-597`), and `null` is the only way to remove a page icon or cover. ADR 5 (`docs/adr/5-clearable-request-fields-and-shared-configuration-types.md`) prescribes `Clearable` for such fields. On create, `null` means the same as leaving the key out. Since the hand-written `UpdatePage` encoder was already being written, the cost was five record literals in tests and examples.
  Date: 2026-09-15

- Decision: `FromJSON UserValue` falls back to `PartialUser` (reading only `id`) when an object with a `type` key does not decode as a full `UserObject`.
  Rationale: A user mention or people entry sits deep inside rich text and page properties. A new user type, or any other shape `UserObject` cannot read, would otherwise fail the whole page. This follows ADR 1's parse-failure fallback rule for nested, partially modelled values (`docs/adr/1-tolerant-response-decoders.md`).
  Date: 2026-09-15

- Decision: Add an `UnknownPropertyValue Text Text Value` fallback to `PropertyValue`, and make the `id` key optional when decoding a property value (default `""`).
  Rationale: This follows the MasterPlan's tolerant-decoding rule. It is also required for typed rollup arrays, whose elements are property values without `id` (`ArrayPartialRollupValueResponse`, `common.ts:2806-2810`).
  Date: 2026-09-14


## Outcomes & Retrospective

Completed 2026-09-15 in four commits, one per milestone. Everything in Purpose / Big Picture now works:

- **Partial block updates.** `updateBlock` takes a `BlockUpdatePayload` that sends only the fields Notion accepts, and the live check confirmed a checked-only update keeps the text.
- **Page requests.** Page create and update accept `filter_properties`. Page create has an optional parent and omits empty properties. Page update can clear icons and covers, and has no `none` template. Moves send only a page or data source parent, and markdown can be inserted at the start or end.
- **Typed values.** Property values decode typed place, verification, group people and rollup arrays. Unknown property types decode to a fallback, and paginated property items expose `next_url` and the rollup summary.
- **Mentions.** Rich text decodes `link_mention`, `custom_emoji` and full-user mentions.
- **Objects and file uploads.** Custom-emoji icons keep name and URL. Native icon colors and object types are typed with fallbacks. File uploads expose their URLs and creator, and accept a typed mode.
- **Webhooks.** Events decode file-upload and transcript-deleted events, `workspace_name`, `api_version` and typed data per event family, with a raw fallback.

The suite grew from 325 to 354 tests. `cabal build all` builds `notion-client`, `notion-client-effectful` and `notion-client-example`.

What remains: partial page and block responses for `createPage`, `updatePage` and the block endpoints are still deferred, as recorded in the Decision Log. `FileUploadStatus`, `SelectColor` and `RelationType` still fail on unknown values. The package version bump belongs to the MasterPlan's release step.

Lessons:

- A plan drafted before its sibling plans land has to be re-read against the tree. Here that meant `createPageAsync`, `Clearable` and the ADR directory.
- A record field name that is fine inside one module can clash once a module re-exports another, as `Notion.V1.Blocks` does with `Notion.V1.BlockContent`.
- Test fixtures with non-ASCII text must not be `Char8` literals.


## Context and Orientation

### Repository and toolchain

The repository root is `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`. It is a cabal project (`cabal.project` lists `.` and `notion-client-effectful`) built with GHC 9.12.2 in the `GHC2024` language edition. Build everything with `cabal build all` and run the tests with `cabal test`. A pre-commit hook runs `treefmt`, which may reformat files and require re-staging them before a commit succeeds.

The library's default extensions (see `notion-client.cabal`) are `DuplicateRecordFields`, `OverloadedLabels`, `OverloadedStrings` and `RecordWildCards`. `DuplicateRecordFields` lets several record types in one module share field names such as `id` or `name`. `LambdaCase` (`\case`) is part of GHC2024.

### How JSON is handled

JSON is handled by `aeson` 2.2. The shared helper module `src/Notion/Prelude.hs` defines `aesonOptions`. Its `fieldLabelModifier` turns camelCase into snake_case (`createdTime` becomes `created_time`) and strips a trailing underscore (`type_` becomes `type`). It also sets `omitNothingFields = True`, so a field holding `Nothing` is left out of the encoded JSON. The same modifier is applied to constructor tags.

Simple records use `genericParseJSON aesonOptions` and `genericToJSON aesonOptions`. Sum types and irregular shapes get hand-written instances, usually in this style:

```haskell
instance FromJSON Thing where
  parseJSON = \case
    Object o -> do
      t <- o .: "type"
      case t of
        "a" -> ThingA <$> o .: "a"
        other -> fail ("Unknown thing: " <> unpack other)
    _ -> fail "Expected object for Thing"
```

Modules whose records have an `id` field write `import Prelude hiding (id)`. `.:` reads a required key and `.:?` reads an optional key as `Maybe`.

"Tolerant decoding" is a MasterPlan rule. Every closed enumeration or sum type decoded from a response gets a fallback constructor carrying the raw value (for example `UnknownX Text`), so that a new value from Notion does not crash decoding.

### How API methods are wired

`src/Notion/V1.hs` defines three things:

- A Servant API type, `API`. Servant is a library that describes HTTP routes as Haskell types. It combines each resource module's `API` (for example `Notion.V1.Pages.API`) behind two required headers.
- A record of functions, `Methods`, with one `IO` action per endpoint.
- `makeMethods :: ClientEnv -> Text -> Methods`. It pattern-matches the generated Servant client functions in exactly the order the routes appear (`retrievePageFiltered :<|> createPage :<|> updatePage :<|> ...`) and fills the `Methods` record with `RecordWildCards`.

Some fields are wrappers defined in `makeMethods`'s `where` clause. For example, `retrievePage pid = retrievePageFiltered pid []`.

Adding an endpoint variant means editing three places, which must stay in the same order:

1. The route in the resource module's `API` type.
2. The pattern binding in `makeMethods`.
3. The field in `Methods`.

### The effectful companion package

The package `notion-client-effectful` re-exposes every `Methods` field as an `effectful` effect:

- `notion-client-effectful/src/Notion/V1/Effectful/Effect.hs` holds the `Notion` GADT constructors and smart constructors.
- `notion-client-effectful/src/Notion/V1/Effectful/Interpreter.hs` holds one case per constructor.

The module header of `Effect.hs` promises that each smart constructor has "the same name, same argument order, and same argument types as the corresponding `Methods` field". The MasterPlan therefore requires a lockstep rule: any added or changed `Methods` field must be mirrored there in the same commit. This plan adds `createPageFiltered` and `updatePageFiltered`, and changes the argument type of `updateBlock`.

### Files this plan edits and what they contain today

`src/Notion/V1/Pages.hs` defines:

- `CreatePage` (line 144) with a required `parent :: Parent` and `properties :: PageProperties`, encoded with `genericToJSON aesonOptions`.
- `mkCreatePage` (line 160).
- `UpdatePage` (line 174), whose `template :: Maybe Template` allows `NoTemplate`.
- `Template` (line 118).
- `MovePage` (line 224), which has `parent :: Parent` and `position :: Maybe Position` (the block `Position` from `Notion.V1.Blocks`).
- `InsertContentRequest` (line 305), which has only `content` and `after`.
- `PageMarkdown` (line 209), which has no `object` field.
- `PropertyItemResponse` (line 331). Its `PaginatedPropertyItems (ListOf PropertyValue) Text` keeps only the property type from `property_item`.
- The `API` type (line 351). Its create route is `ReqBody '[JSON] CreatePage :> Post` with no query parameters, and its update route is `Capture "page_id" PageID :> ReqBody '[JSON] UpdatePage :> Patch`.

`src/Notion/V1/BlockContent.hs` defines:

- The `BlockContent` sum type (line 393). `AudioBlock` has no `caption` (line 489). `EmbedBlock` has only `url` (line 509). `UnsupportedBlock` is nullary (line 594).
- `blockContentFields` (line 617), which produces `(typeName, innerJSON)`.
- `parseBlockContent` (line 777).
- The `BlockUpdate` newtype (line 962). Its ToJSON writes `{typeName: blockContentFields ...}` after clearing read-only numbered-list fields.

`src/Notion/V1/Blocks.hs` re-exports `module Notion.V1.BlockContent`, lists `BlockUpdate (..)` in its export list (line 6), and routes `PATCH blocks/{id}` with `ReqBody '[JSON] BlockUpdate` (line 130).

`src/Notion/V1/PropertyValue.hs` defines:

- `PropertyValue` (line 66). `PeopleValue` holds `Vector UserReference`, `PlaceValue` holds `Maybe Value`, and there is no unknown fallback (line 124 fails).
- `SelectOptionValue` (line 162), which has no `description`.
- `FormulaResult` (line 223). EP-1 adds its `unsupported` and unknown fallbacks, and this plan leaves it alone.
- `RollupResult` (line 250), where `RollupArrayResult (Vector Value)`.
- `VerificationResult` (line 294), where `state :: Text`.
- Smart constructors (line 311 onward) that build `SelectOptionValue Nothing name Nothing` positionally.

`src/Notion/V1/RichText.hs` defines `MentionContent` (line 80), where `UserMention {user :: UUID}` keeps only the ID. It has no `link_mention` or `custom_emoji`. `RichText` derives `Eq`, so every type nested inside a mention must also derive `Eq`.

`src/Notion/V1/Common.hs` defines:

- `ObjectType` (line 30), with generic instances and seven constructors.
- `Icon` (line 130), where `NativeIcon {iconName :: Text, iconColor :: Maybe Text}`.
- `Color` and `Parent`.

`src/Notion/V1/Users.hs` defines `UserObject`, `UserType`, `PersonUser`, `BotUser`, `UserOwner` and `UserReference`. None of them derives `Eq`.

`src/Notion/V1/FileUploads.hs` defines:

- `FileUploadObject` (line 136), where `createdBy :: Value` and there are no `uploadUrl`/`completeUrl`.
- `CreateFileUpload` (line 196), where `mode :: Maybe Text`.
- `FileImportResult` (line 80).

`src/Notion/V1/Webhooks.hs` defines:

- `EventType` (line 56), which has no file-upload or transcript events but does fall back to `UnknownEvent`.
- `EntityType` (line 154), which has no `file_upload` or `block`.
- `WebhookEvent` (line 249), which has no `workspaceName`/`apiVersion` and has `data_ :: Maybe Value`.

Tests live in `tasty/Main.hs`, a 2298-line tasty suite. Its top-level `testGroup "Notion Client Tests"` list is at lines 159-170. The `test-suite tasty` stanza is in `notion-client.cabal` (line 90). Before this repository's parity work it had no `other-modules`; EP-1 adds `WireFormatTests`, and other plans may add their own modules. The example executable lives in `notion-client-example/`.

### What EP-1 already did, and what this plan must not redo

This plan hard-depends on EP-1, `docs/plans/6-fix-wire-format-decoding-and-encoding-bugs-found-against-the-official-sdk.md`. EP-1 owns the following, and none of it is repeated here:

- `Color` `DefaultBackground` and an `UnknownColor Text` fallback.
- The nested `custom_emoji` icon shape. EP-1 keeps `CustomEmojiIcon {customEmojiId :: UUID}` and still accepts the legacy top-level `id` when reading.
- An `UnknownIcon Value` fallback on `Icon`.
- `CodeLanguage` additions and its `OtherLanguage Text` fallback.
- The `UnknownMention Value` fallback. EP-1 rewrites the `MentionContent` decoder head as `parseJSON v = case v of Object o -> ...`, so the whole value is in scope.
- `AgentParent` and an `UnknownParent Value` fallback.
- An optional `PersonUser.email`.
- `UserOwner` reading the nested user object's `id`, plus `UnknownOwner`.
- The fully typed meeting-notes block payload (with the `transcription` alias).
- `filter_properties` as a query parameter on data source and database queries.
- A new `PagePosition` type for `CreatePage.position` (`PageAfterBlock UUID | PageStart | PageEnd`).
- The `OtherNumberFormat` fallback.
- `FormulaUnsupportedResult` and `UnknownFormulaResult Value`.
- `accessible_by` defaulting to an empty vector.
- Webhook signature prefix, length and case handling.
- A nullable `UniqueIdResult.number`.

EP-1's tests live in `tasty/WireFormatTests.hs`, which is already listed under `other-modules` of the test suite.

When this plan edits a function EP-1 also touched, keep EP-1's behavior. For example, add the new mention cases above EP-1's fallback branch.

EP-3 (`docs/plans/8-add-comment-mutation-async-task-and-meeting-notes-endpoints.md`) owns the comment endpoints and write shapes, `AsyncTask`, `allow_async` on `CreatePage` and `UpdatePageMarkdown`, and the meeting-notes endpoints. This plan reads `Comments.hs` but does not edit it. If EP-3 has already changed `createPage`'s return type (to allow an async task), the new `createPageFiltered` must use that same return type.

### ADRs

When this plan was drafted, the repository had no `docs/adr/` directory. By the time it was implemented, EP-1 to EP-5 had added five ADRs. Three of them apply here:

- [docs/adr/1-tolerant-response-decoders.md](../adr/1-tolerant-response-decoders.md): every decoded enum or sum type has an unknown fallback. Nested values whose model is incomplete also fall back when their typed parse fails. Examples in this plan are `UnknownPropertyValue`, `UnknownNoticonColor`, `UnknownObjectType`, the `UserValue` partial fallback and `RawEventData`.
- [docs/adr/4-full-or-partial-responses-and-request-only-types.md](../adr/4-full-or-partial-responses-and-request-only-types.md): request shapes that differ from responses get request-only types, as `BlockUpdatePayload` does.
- [docs/adr/5-clearable-request-fields-and-shared-configuration-types.md](../adr/5-clearable-request-fields-and-shared-configuration-types.md): fields that accept `null` to clear use `Clearable`, as `UpdatePage.icon` and `cover` do.

### Reference wire shapes (transcribed from the JS SDK)

**Create page query parameters and optional fields** (`pages.ts:326-445`):

```typescript
type CreatePageQueryParameters = { filter_properties?: Array<string> }
type CreatePageBodyParameters = {
  parent?: { page_id } | { database_id } | { data_source_id } | { workspace: true }
  properties?: Record<string, PropertyValueRequest>
  icon?: PageIconRequest | null
  cover?: PageCoverRequest | null
  content?: Array<BlockObjectRequest>   // alias of children
  children?: Array<BlockObjectRequest>
  markdown?: string
  allow_async?: boolean                 // owned by EP-3
  template?: { type: "none" } | { type: "default"; timezone? } | { type: "template_id"; template_id; timezone? }
  position?: PagePositionSchema         // owned by EP-1
}
```

**Update page** (`pages.ts:506-622`): the query parameters are `filter_properties?: Array<string>`, and every body field is optional. The template variant has no `none`:

```typescript
template?:
  | { type: "default"; timezone?: TemplateTimezone }
  | { type: "template_id"; template_id: IdRequest; timezone?: TemplateTimezone }
```

**Move page** (`pages.ts:657-674`):

```typescript
type MovePageBodyParameters = {
  parent: { page_id: IdRequest; type?: "page_id" } | { data_source_id: IdRequest; type?: "data_source_id" }
}
```

**Insert markdown position** (`pages.ts:770-787`):

```typescript
insert_content: { content: string; after?: string; position?: { type: "start" } | { type: "end" } }
```

**Select, multi-select and status option requests** (`pages.ts:342-356`) accept `{ id?, name?, color?, description?: string | null }`. **People requests** accept `Array<{id, object?: "user"} | {id, name?: string | null, object?: "group"}>` (`common.ts:690-694`, `1980-1985`). **Place and verification requests** (`pages.ts:409-425`):

```typescript
place: { lat: number; lon: number; name?: string | null; address?: string | null;
         aws_place_id?: string | null; google_place_id?: string | null } | null
verification: { state: "verified"; date?: DateRequest } | { state: "unverified" }
```

**Update block** (`blocks.ts:825-1061`, helper types in `common.ts`). Every variant also accepts `in_trash?: boolean`, and one variant is only `{ in_trash?: boolean }`:

```typescript
embed | bookmark:           { url?: string; caption?: RichTextItemRequest[] }
image | video | pdf | audio: { caption?: RichTextItemRequest[]; external?: { url }; file_upload?: { id } }
file:                        { caption?; external?; file_upload?; name?: string }
code:      { rich_text?; language?; caption? }
equation:  { expression: string }
divider | breadcrumb | tab: {}
table_of_contents: { color?: ApiColor }
link_to_page: { page_id } | { database_id } | { comment_id }
table_row: { cells: RichTextItemRequest[][] }
heading_1..heading_4: { rich_text: RichTextItemRequest[]; color?; is_toggleable?: boolean }
paragraph: { rich_text?; icon?: PageIconRequest; color? }
bulleted_list_item | numbered_list_item | quote | toggle: { rich_text: RichTextItemRequest[]; color? }
to_do:     { rich_text?; checked?: boolean; color? }
template:  { rich_text: RichTextItemRequest[] }
callout:   { rich_text?; icon?; color? }
synced_block: { synced_from: { block_id } | null }
table:     { has_column_header?: boolean; has_row_header?: boolean }
column:    { width_ratio?: number }
```

**Block responses**:

- `audio` is `MediaContentWithFileAndCaptionResponse`, so it includes `caption` (`blocks.ts:37-51`, `326-330`).
- `embed` is `{ url: string; caption: RichTextItemResponse[] }` (`blocks.ts:292-296`, `497-500`).
- `unsupported` is `{ block_type: string }` (`blocks.ts:765-771`).
- A tab item request is `{ paragraph: {rich_text, color?, icon?, children?}, type?: "paragraph" }` (`common.ts:2698-2706`, `2751-2755`).

**Page property value responses** (`common.ts`):

- `people: Array<UserValueResponse | GroupObjectResponse>` (2902-2905).
- `GroupObjectResponse = { id, object: "group", name: string | null }` (696-703).
- `PlacePropertyValueResponse` has the same fields as the request (3005-3012).
- `VerificationPropertyValueResponse = { state: "verified" | "expired"; date: DateResponse | null; verified_by: UserValueResponse | null } | { state: "unverified"; date: null; verified_by: null }` (3021-3023, 3077-3089).
- Rollup `{ type: "array"; array: Array<SimpleOrArrayPropertyValueResponse> }`, whose elements are property values *without* `id` (2806-2810).
- `UserValueResponse = PartialUserObjectResponse | UserObjectResponse` (1618), where the partial form is `{ id, object: "user" }` (1014-1018) and the full form adds `type`, `name`, `avatar_url` and `person` or `bot`.
- `bot: EmptyObject | BotInfoResponse` (123-128).

**Property item list** (`pages.ts:192-245`):

```typescript
{ object: "list"; type: "property_item"; next_cursor; has_more; results: PropertyItemObjectResponse[];
  property_item:
    | { type: "title" | "rich_text" | "people" | "relation"; <type>: {}; next_url: string | null; id: string }
    | { type: "rollup"; rollup: <number|date|array|unsupported|incomplete with function>; next_url: string | null; id: string } }
```

**Mentions** (`common.ts:757-782`, `393-400`, `812-873`):

```typescript
{ type: "user"; user: UserValueResponse }
{ type: "link_mention"; link_mention: { href: string; title?; description?; link_author?; link_provider?;
  thumbnail_url?; icon_url?; iframe_url?; height?: number; padding?: number; padding_top?: number } }
{ type: "custom_emoji"; custom_emoji: { id: string; name: string; url: string } }
// request side of custom_emoji: { id; name?; url? } (common.ts:2456-2466)
```

**Native icon color** (`common.ts:896-915`, `2275-2287`): `"gray" | "lightgray" | "brown" | "yellow" | "orange" | "green" | "blue" | "purple" | "pink" | "red"`.

**Page markdown** (`common.ts:973-985`): `{ object: "page_markdown"; id; markdown; truncated; unknown_block_ids }`.

**File upload** (`file-uploads.ts:11-82`):

```typescript
{ object: "file_upload"; id; created_time; created_by: { id; type: "person" | "bot" | "agent" };
  last_edited_time; in_trash; archived; expiry_time: string | null;
  status: "pending" | "uploaded" | "expired" | "failed"; filename; content_type; content_length;
  upload_url?: string; complete_url?: string; file_import_result?: ...; number_of_parts?: { total; sent } }
// create body: mode?: "single_part" | "multi_part" | "external_url"
```

**Webhooks** (`webhooks.ts`):

- The base payload (6-55) adds `workspace_name: string` and `api_version: "2022-06-28" | "2025-09-03" | "2026-03-11"` to the fields the client already reads.
- Parent block (520-527): `{ id; type: "space"|"block"|"page"|"database"|"team"|"agent"; data_source_id? }`.
- External block and updated block (499-504, 529-534): `{ id; type: "page"|"database"|"block" }`.
- Event data by type:
  - `page.created|deleted|undeleted|moved|locked|unlocked`, `database.created|deleted|undeleted|moved`, `data_source.created|deleted|undeleted|moved` and `view.deleted` carry `{ parent }`.
  - `page.content_updated`, `database.content_updated` and `data_source.content_updated` carry `{ parent, updated_blocks: UpdatedBlock[] }`.
  - `page.properties_updated` carries `{ parent, updated_properties: string[] }` (391-403).
  - `database.schema_updated` and `data_source.schema_updated` carry `{ parent, updated_properties?: {id, name: string|null, action: "created"|"updated"|"deleted"}[] }` (149-168, 232-251).
  - `view.created` carries `{ parent, view_type: string }` (444-457).
  - `view.updated` carries `{ parent, updated_fields: ("name"|"filter"|"sorts"|"configuration")[] }` (471-483).
  - `comment.created|updated|deleted` carry `{ parent: ExternalBlock, page_id }` (57-97).
  - `file_upload.created|completed|expired` carry no `data` (265-284).
  - `file_upload.upload_failed` carries `{ file_import_result }` (286-327).
  - `page.transcription_block.transcript_deleted` carries `{ target: ExternalBlock, transcript_id: string | null }` (405-418).
- Database-event entity types include `"block"` for linked databases (492-497). The file-upload entity is `"file_upload"` (506-511).


## Plan of Work

The work runs in four milestones. Each one compiles, passes `cabal build all` and `cabal test`, and adds a sub-group to one new test module, `tasty/ObjectFieldTests.hs`. That module exports `tests :: TestTree`, a `testGroup "Object Field Gaps"` holding the four milestone sub-groups. Fixtures are JSON string literals written with `OverloadedStrings` as lazy `ByteString`, the same style `tasty/Main.hs` uses. People in fixtures get made-up Japanese names such as "Tanaka Hanako" or "Sato Kenji", never the maintainer's real name.

Every breaking change gets a line under `### Breaking Changes` inside a single `## Unreleased` heading at the top of `CHANGELOG.md`. Create that heading directly under `# Changelog for notion-client` if it does not exist, and add to it if another plan already created it. Additive items go under `### New Features`. Do not change the package version.


### Milestone 1: page and block requests

At the end of this milestone:

- Page create and update requests match the JS SDK.
- Moving a page sends only a valid parent.
- Markdown can be inserted at the start or end of a page.
- Blocks can be partially updated or trashed with a dedicated request type.
- Audio and embed blocks keep their captions, and unsupported blocks report their underlying type.

First create the test module skeleton and register it. In `notion-client.cabal`, under `test-suite tasty`, append `ObjectFieldTests` to the `other-modules` field that EP-1 created (it already lists `WireFormatTests`). If no such field exists, add `other-modules: ObjectFieldTests` right after `main-is: Main.hs`. In `tasty/Main.hs`, add `import ObjectFieldTests qualified` and add `ObjectFieldTests.tests,` to the list inside `testGroup "Notion Client Tests"`.

In `src/Notion/V1/Pages.hs`:

1. **`CreatePage.parent`.** Change it to `Maybe Parent`, and have `mkCreatePage` set `parent = Just parent`.
2. **Hand-written ToJSON for `CreatePage` and `UpdatePage`.** Replace the generic instances with hand-written ones. They emit every field the generic encoding emitted today, with the same keys (`children`, `markdown`, `icon`, `cover`, `template`, `position`, `in_trash`, `is_locked`, `is_archived`, `erase_content`), each omitted when `Nothing`, and emit `properties` only when the map is non-empty. `position` is EP-1's `Maybe PagePosition` and is emitted with `"position" .= p`. Do not define a new position type. If EP-3 added `allow_async`, keep emitting it exactly as EP-3 does. Read the current record and instance first and preserve every field.
3. **`UpdatePageTemplate`.** Add the type below and change `UpdatePage.template` to `Maybe UpdatePageTemplate`.
4. **`MovePage`.** Replace it with the version below. Remove the `Notion.V1.Blocks (Position)` import only if nothing else in the module still uses it.
5. **`InsertContentRequest`.** Add `position :: Maybe InsertPosition`.
6. **API routes.** Change the create route to `QueryParams "filter_properties" Text :> ReqBody '[JSON] CreatePage :> Post '[JSON] PageObject`. Change the update route to `Capture "page_id" PageID :> QueryParams "filter_properties" Text :> ReqBody '[JSON] UpdatePage :> Patch '[JSON] PageObject`. `QueryParams` is already imported from `Servant.API`. (If EP-3 changed these routes' response type, keep that response type.)
7. **Exports.** Export `UpdatePageTemplate (..)`, `MovePageParent (..)` and `InsertPosition (..)`.

```haskell
-- | Template choice when updating a page. Unlike 'Template', there is no
-- "none" option: the API rejects @{"type":"none"}@ on update.
data UpdatePageTemplate
  = -- | Apply the data source's default template; optional IANA timezone.
    UpdateDefaultTemplate (Maybe Text)
  | -- | Apply a specific template page; optional IANA timezone.
    UpdateTemplateById UUID (Maybe Text)
  deriving stock (Eq, Generic, Show)

instance ToJSON UpdatePageTemplate where
  toJSON (UpdateDefaultTemplate mTz) =
    Aeson.object (["type" .= ("default" :: Text)] <> maybe [] (\tz -> ["timezone" .= tz]) mTz)
  toJSON (UpdateTemplateById tid mTz) =
    Aeson.object
      ( ["type" .= ("template_id" :: Text), "template_id" .= tid]
          <> maybe [] (\tz -> ["timezone" .= tz]) mTz
      )

-- | Destination of a page move. Only pages and data sources are valid targets.
data MovePageParent
  = MoveToPage UUID
  | MoveToDataSource UUID
  deriving stock (Eq, Generic, Show)

instance ToJSON MovePageParent where
  toJSON (MoveToPage pid) = Aeson.object ["type" .= ("page_id" :: Text), "page_id" .= pid]
  toJSON (MoveToDataSource dsid) =
    Aeson.object ["type" .= ("data_source_id" :: Text), "data_source_id" .= dsid]

newtype MovePage = MovePage {parent :: MovePageParent}
  deriving stock (Generic, Show)

instance ToJSON MovePage where
  toJSON (MovePage p) = Aeson.object ["parent" .= p]

-- | Where @insert_content@ places new markdown. Cannot be combined with @after@.
data InsertPosition = InsertAtStart | InsertAtEnd
  deriving stock (Eq, Generic, Show)

instance ToJSON InsertPosition where
  toJSON InsertAtStart = Aeson.object ["type" .= ("start" :: Text)]
  toJSON InsertAtEnd = Aeson.object ["type" .= ("end" :: Text)]
```

In `src/Notion/V1.hs`:

- In `makeMethods`, rename the pattern bindings `createPage` and `updatePage` to `createPageFiltered` and `updatePageFiltered`.
- In the `where` clause, add `createPage = createPageFiltered []` and `updatePage pid = updatePageFiltered pid []`.
- Add these `Methods` fields next to `createPage`/`updatePage`, each with a Haddock comment:

```haskell
    -- | Create a page, limiting which properties the response includes.
    createPageFiltered :: [Text] -> CreatePage -> IO PageObject,
    -- | Update a page, limiting which properties the response includes.
    updatePageFiltered :: PageID -> [Text] -> UpdatePage -> IO PageObject,
```

In `notion-client-effectful/src/Notion/V1/Effectful/Effect.hs`, add the matching constructors, export the smart constructors, and write the smart constructors in the style of `retrievePageFiltered`:

```haskell
  CreatePageFiltered :: [Text] -> CreatePage -> Notion m PageObject
  UpdatePageFiltered :: PageID -> [Text] -> UpdatePage -> Notion m PageObject
```

In `notion-client-effectful/src/Notion/V1/Effectful/Interpreter.hs`, import the two constructors and add their cases:

```haskell
  CreatePageFiltered props req -> runIO (Notion.createPageFiltered methods props req)
  UpdatePageFiltered pid props req -> runIO (Notion.updatePageFiltered methods pid props req)
```

In `src/Notion/V1/BlockContent.hs`:

- **Audio and embed captions.** Add `caption :: Vector RichText` to `AudioBlock` and `EmbedBlock`. Parse them with `fromMaybe Vector.empty <$> o .:? "caption"`. In `blockContentFields`, emit `"caption" .= caption` for both, matching `ImageBlock`.
- **Unsupported blocks.** Change `UnsupportedBlock` to `UnsupportedBlock (Maybe Text)`. Parse it from `o .:? "block_type"` when the value is an object, and use `Nothing` otherwise. Encode it as `object (maybe [] (\t -> ["block_type" .= t]) bt)`.
- **`tabBlock`.** Add it and export it:

```haskell
-- | Build a tab block. Each tab item is a paragraph (its title), an optional
-- icon, and the tab's content blocks — the only child shape the API accepts.
tabBlock :: Vector (Vector RichText, Maybe Icon, Vector BlockContent) -> BlockContent
tabBlock items =
  TabBlock (fmap (\(rt, ic, cs) -> ParagraphBlock rt Default ic cs) items)
```

- **Replace `BlockUpdate`.** Delete the `BlockUpdate` newtype, its instance and `stripReadOnlyFields`, and add the types below. Export `BlockUpdatePayload (..)`, `BlockUpdateContent (..)`, `ParagraphUpdate (..)`, `HeadingUpdate (..)`, `TextColorUpdate (..)`, `ToDoUpdate (..)`, `CodeUpdate (..)`, `MediaUpdate (..)`, `MediaSourceUpdate (..)`, `UrlCaptionUpdate (..)`, `TableUpdate (..)`, `mkBlockUpdate`, `trashBlockUpdate` and `blockUpdateFromContent`. In the export list, replace the `BlockUpdate (..)` entry under "Block update wrapper".

```haskell
-- | Body of @PATCH /v1/blocks/{block_id}@. Every field is optional:
-- send only 'inTrash' to trash or restore a block.
data BlockUpdatePayload = BlockUpdatePayload
  { content :: Maybe BlockUpdateContent,
    inTrash :: Maybe Bool
  }
  deriving stock (Eq, Generic, Show)

-- | Fields shared by paragraph and callout updates (all optional).
data ParagraphUpdate = ParagraphUpdate
  { richText :: Maybe (Vector RichText),
    color :: Maybe Color,
    icon :: Maybe Icon
  }
  deriving stock (Eq, Generic, Show)

-- | Heading update: rich text is required by the API.
data HeadingUpdate = HeadingUpdate
  { richText :: Vector RichText,
    color :: Maybe Color,
    isToggleable :: Maybe Bool
  }
  deriving stock (Eq, Generic, Show)

-- | List item, quote, and toggle update: rich text is required by the API.
data TextColorUpdate = TextColorUpdate
  { richText :: Vector RichText,
    color :: Maybe Color
  }
  deriving stock (Eq, Generic, Show)

data ToDoUpdate = ToDoUpdate
  { richText :: Maybe (Vector RichText),
    checked :: Maybe Bool,
    color :: Maybe Color
  }
  deriving stock (Eq, Generic, Show)

data CodeUpdate = CodeUpdate
  { richText :: Maybe (Vector RichText),
    language :: Maybe CodeLanguage,
    caption :: Maybe (Vector RichText)
  }
  deriving stock (Eq, Generic, Show)

-- | New source for a media block. Notion-hosted files cannot be set directly.
data MediaSourceUpdate
  = UpdateExternalSource Text
  | UpdateFileUploadSource UUID
  deriving stock (Eq, Generic, Show)

data MediaUpdate = MediaUpdate
  { caption :: Maybe (Vector RichText),
    source :: Maybe MediaSourceUpdate
  }
  deriving stock (Eq, Generic, Show)

data UrlCaptionUpdate = UrlCaptionUpdate
  { url :: Maybe Text,
    caption :: Maybe (Vector RichText)
  }
  deriving stock (Eq, Generic, Show)

data TableUpdate = TableUpdate
  { hasColumnHeader :: Maybe Bool,
    hasRowHeader :: Maybe Bool
  }
  deriving stock (Eq, Generic, Show)

-- | One constructor per block type the API allows updating.
data BlockUpdateContent
  = UpdateParagraph ParagraphUpdate
  | UpdateHeading1 HeadingUpdate
  | UpdateHeading2 HeadingUpdate
  | UpdateHeading3 HeadingUpdate
  | UpdateHeading4 HeadingUpdate
  | UpdateBulletedListItem TextColorUpdate
  | UpdateNumberedListItem TextColorUpdate
  | UpdateQuote TextColorUpdate
  | UpdateToggle TextColorUpdate
  | UpdateToDo ToDoUpdate
  | UpdateCallout ParagraphUpdate
  | UpdateTemplateBlock (Vector RichText)
  | UpdateCode CodeUpdate
  | UpdateEquation Text
  | UpdateImage MediaUpdate
  | UpdateVideo MediaUpdate
  | UpdatePdf MediaUpdate
  | UpdateAudio MediaUpdate
  | -- | File block; the 'Maybe Text' is the new file name.
    UpdateFile MediaUpdate (Maybe Text)
  | UpdateEmbed UrlCaptionUpdate
  | UpdateBookmark UrlCaptionUpdate
  | UpdateDivider
  | UpdateBreadcrumb
  | UpdateTab
  | UpdateTableOfContents (Maybe Color)
  | UpdateLinkToPage LinkTarget
  | UpdateTableRow (Vector (Vector RichText))
  | UpdateSyncedBlock SyncedFrom
  | UpdateTable TableUpdate
  | -- | Column width ratio between 0 and 1.
    UpdateColumn (Maybe Double)
  deriving stock (Eq, Generic, Show)

mkBlockUpdate :: BlockUpdateContent -> BlockUpdatePayload
mkBlockUpdate c = BlockUpdatePayload {content = Just c, inTrash = Nothing}

trashBlockUpdate :: BlockUpdatePayload
trashBlockUpdate = BlockUpdatePayload {content = Nothing, inTrash = Just True}

-- | Convert full block content to the equivalent "set every updatable field"
-- update. Returns 'Nothing' for block types the API cannot update
-- (child_page, child_database, column_list, link_preview, meeting_notes,
-- unsupported, unknown). Read-only fields (table_width, children,
-- list_format, list_start_index, Notion-hosted file URLs) are dropped.
blockUpdateFromContent :: BlockContent -> Maybe BlockUpdateContent
```

Write `ToJSON BlockUpdatePayload` by hand. It emits `in_trash` when `Just`, and, when `content` is `Just c`, a single key named after the block type (`"paragraph"`, `"heading_1"`, `"to_do"`, `"table_of_contents"`, ...) whose value is an object containing only the fields that are `Just`.

Some variants have their own encoding:

- **Required rich text.** Required rich-text fields are always emitted as `rich_text`.
- **Media blocks.** `MediaSourceUpdate` becomes `"external": {"url": u}` or `"file_upload": {"id": i}`, and `UpdateFile`'s name becomes `"name"`.
- **Simple payloads.** `UpdateEquation e` becomes `{"expression": e}`. `UpdateDivider`, `UpdateBreadcrumb` and `UpdateTab` become `{}`. `UpdateTableRow` becomes `{"cells": ...}`. `UpdateLinkToPage` uses `toJSON` of `LinkTarget`. `UpdateSyncedBlock` becomes `{"synced_from": toJSON syncedFrom}`, where the original encodes as `null`. `UpdateColumn` becomes `{"width_ratio": r}` when `Just`.

Write `blockUpdateFromContent` by pattern matching:

- **Text blocks.** For example, `ToDoBlock {..}` becomes `Just (UpdateToDo (ToDoUpdate (Just richText) (Just checked) (Just color)))`. `TableBlock {..}` becomes `UpdateTable (TableUpdate (Just hasColumnHeader) (Just hasRowHeader))`.
- **Media blocks.** `ImageBlock src cap` maps its `FileSource` as follows: `ExternalSource (ExternalFile u)` becomes `Just (UpdateExternalSource u)`, `FileUploadSource i` becomes `Just (UpdateFileUploadSource i)`, and `NotionSource _` becomes `Nothing`.
- **Code blocks.** `CodeBlock` becomes `UpdateCode (CodeUpdate (Just richText) (Just language) (Just caption))`.
- **Everything else.** Each other updatable type maps to the obvious constructor, and non-updatable types map to `Nothing`.

`ExternalFile` is a newtype with field `url` in `Notion.V1.Common`. Pattern-match it as `ExternalFile u`.

In `src/Notion/V1/Blocks.hs`:

- Replace `BlockUpdate (..)` in the export list with `BlockUpdatePayload (..)`. The rest comes through the `module Notion.V1.BlockContent` re-export.
- Change the update route's `ReqBody '[JSON] BlockUpdate` to `ReqBody '[JSON] BlockUpdatePayload`.
- In `src/Notion/V1.hs`, change the field to `updateBlock :: BlockID -> Blocks.BlockUpdatePayload -> IO BlockObject`.
- In `Effect.hs`, change the `UpdateBlock` constructor and the `updateBlock` smart constructor to take `Blocks.BlockUpdatePayload`.

Fix the existing code that stops compiling:

- **`tasty/Main.hs`.**
  - `testBlockUpdateWithChildren` (around line 585) asserted that updates *include* children, which is exactly the bug being fixed. Rewrite it to assert that `toJSON (mkBlockUpdate c)` for `Just c = blockUpdateFromContent (toggleBlock ... `withChildren` ...)` has a `toggle` object *without* a `children` key.
  - `testBlockUpdateSerialization` (around line 623) should build `mkBlockUpdate (UpdateParagraph (ParagraphUpdate (Just (mkRichText "Updated")) Nothing Nothing))` and keep its two assertions.
  - `testSerializeMovePage` (around line 872) should use `MovePage {parent = MoveToPage (UUID "target-page")}`.
  - `testSerializeUpdatePageTemplate` (around line 948) should use `UpdateDefaultTemplate (Just "America/Chicago")`.
  - `createTestPage` needs no change, because `mkCreatePage` keeps its signature. Check any record literal of `CreatePage` in the file.
- **`notion-client-example/MarkdownDemo.hs`.** Lines 152 and 169 should use `MovePage {parent = MoveToPage targetId}` and `MovePage {parent = MoveToPage parentPageId}`.

Search for any other breakage with `cabal build all` and fix each error the same way.

Add these tests to the "Page and block requests" sub-group of `tasty/ObjectFieldTests.hs`. Each one encodes with `Aeson.encode`/`Aeson.toJSON` and checks keys with `Data.Aeson.KeyMap`:

- **Create page without parent or properties.** `CreatePage` with `parent = Nothing`, empty `properties` and `markdown = Just "# こんにちは"` encodes to an object with a `markdown` key and no `parent` or `properties` keys.
- **Update page trash-only.** `(mkUpdatePage Map.empty) {inTrash = Just True}` encodes exactly to `{"in_trash":true}`.
- **Update page template by ID.** `UpdateTemplateById (UUID "tpl-1") Nothing` encodes to `{"type":"template_id","template_id":"tpl-1"}`.
- **Move page to data source.** Encodes to `{"parent":{"type":"data_source_id","data_source_id":"ds-1"}}`, with no `position` key.
- **Insert markdown at start.** `UpdatePageMarkdown` with `InsertContent (InsertContentRequest "- item" Nothing (Just InsertAtStart))` encodes an `insert_content.position` equal to `{"type":"start"}`.
- **Block update to_do checked only.** `mkBlockUpdate (UpdateToDo (ToDoUpdate Nothing (Just True) Nothing))` encodes exactly to `{"to_do":{"checked":true}}`.
- **Block update table headers only.** Encodes to `{"table":{"has_column_header":true}}`, with no `table_width` and no `children`.
- **Block update trash.** `trashBlockUpdate` encodes to `{"in_trash":true}`.
- **Block update image via file upload.** Encodes to `{"image":{"file_upload":{"id":"fu-1"}}}`.
- **`blockUpdateFromContent` for a child page.** Returns `Nothing` for `ChildPageBlock "x"`.
- **Parse audio block with caption.** Decoding the inner JSON `{"type":"external","external":{"url":"https://example.com/a.mp3"},"caption":[]}` via `parseBlockContent "audio"` yields `AudioBlock` with an empty caption. Do the same with a one-element caption, and check that the length is 1.
- **Parse embed block with caption.** `{"url":"https://example.com","caption":[]}` via `parseBlockContent "embed"` parses.
- **Parse unsupported block type.** `{"block_type":"form"}` via `parseBlockContent "unsupported"` yields `UnsupportedBlock (Just "form")`.

Record the Milestone 1 CHANGELOG entries.

Breaking changes:

- `BlockUpdate` is replaced by `BlockUpdatePayload`/`BlockUpdateContent`, with `blockUpdateFromContent` for migration.
- `MovePage` drops `position`, and `parent` becomes `MovePageParent`.
- `UpdatePage.template` becomes `UpdatePageTemplate`.
- `CreatePage.parent` becomes `Maybe Parent`.
- `AudioBlock` and `EmbedBlock` gain `caption`.
- `UnsupportedBlock` carries `Maybe Text`.
- `InsertContentRequest` gains `position`.

New features:

- `createPageFiltered` and `updatePageFiltered`.
- `trashBlockUpdate`, `mkBlockUpdate` and `tabBlock`.
- Empty `properties` are omitted on page create and update.


### Milestone 2: property values and mentions

At the end of this milestone:

- Page property values decode every JS SDK shape into typed Haskell values. That covers place, verification, group people, typed rollup arrays and unknown property types.
- Paginated property items expose `next_url` and the rollup summary.
- Rich text mentions decode `link_mention` and `custom_emoji` and keep the full user.

Start in `src/Notion/V1/Users.hs`. Add `Eq` to the `deriving stock` clauses of `UserObject`, `UserType`, `PersonUser`, `WorkspaceLimits`, `BotUser` and `UserOwner`. This is needed because `RichText` derives `Eq` and will contain users. If EP-1 changed those types, add `Eq` to its versions. Then add the following, and export `UserValue (..)`, `userValueId`, `GroupObject (..)` and `PeopleEntry (..)`. The module needs `Data.Aeson ((.:?), (.=), object)` and `Data.Aeson.KeyMap qualified as KeyMap` imports.

```haskell
-- | A user as it appears inside mentions, people values and verification
-- values: either just a reference (@{"object":"user","id":...}@) or a full
-- user object (has a @type@ key).
data UserValue
  = PartialUser UserID
  | FullUser UserObject
  deriving stock (Eq, Generic, Show)

userValueId :: UserValue -> UserID
userValueId (PartialUser i) = i
userValueId (FullUser UserObject {id = i}) = i

instance FromJSON UserValue where
  parseJSON = \case
    Object o
      | KeyMap.member "type" o -> FullUser <$> parseJSON (Object o)
      | otherwise -> PartialUser <$> o .: "id"
    _ -> fail "Expected object for UserValue"

-- | Encodes the request shape only (id + object); full user details are not
-- sent back to the API.
instance ToJSON UserValue where
  toJSON u = object ["object" .= ("user" :: Text), "id" .= userValueId u]

-- | A group (team) that can appear in a people property.
data GroupObject = GroupObject
  { id :: UUID,
    name :: Maybe Text
  }
  deriving stock (Eq, Generic, Show)

data PeopleEntry
  = PersonEntry UserValue
  | GroupEntry GroupObject
  deriving stock (Eq, Generic, Show)
```

`FromJSON PeopleEntry` reads `object` with `.:?`. If it is `"group"`, it builds `GroupEntry` from `id` and `name` (`.:?`). Otherwise it delegates to `PersonEntry <$> parseJSON (Object o)`. `ToJSON PeopleEntry` writes `PersonEntry u` via `toJSON u`, and `GroupEntry` as `{"object":"group","id":...}` plus `name` when `Just`. `Users.hs` has `{-# LANGUAGE LambdaCase #-}` but no `Prelude hiding (id)`. The `id` field already exists on `UserObject` and `UserReference` without it, so follow the module's existing pattern of `o .: "id"` and avoid the bare `id` function.

In `src/Notion/V1/RichText.hs`:

- Import `Notion.V1.Users (UserValue)`. `Users` does not import `RichText`, so no import cycle arises.
- Change `UserMention {user :: UUID}` to `UserMention {user :: UserValue}`, parsing it with `UserMention <$> o .: "user"` and encoding it with `"user" .= u`.
- Add the two constructors below. Add their parse branches *above* EP-1's unknown-mention fallback, and add their ToJSON cases.
- Export `LinkMentionValue (..)`.

```haskell
  | LinkMention {linkMention :: LinkMentionValue}
  | CustomEmojiMention {customEmoji :: CustomEmojiRef}

-- | Rich link preview metadata carried by a @link_mention@.
data LinkMentionValue = LinkMentionValue
  { href :: Text,
    title :: Maybe Text,
    description :: Maybe Text,
    linkAuthor :: Maybe Text,
    linkProvider :: Maybe Text,
    thumbnailUrl :: Maybe Text,
    iconUrl :: Maybe Text,
    iframeUrl :: Maybe Text,
    height :: Maybe Double,
    padding :: Maybe Double,
    paddingTop :: Maybe Double
  }
  deriving stock (Eq, Generic, Show)
-- FromJSON/ToJSON: genericParseJSON/genericToJSON aesonOptions
-- (camelToSnake maps linkAuthor -> link_author, paddingTop -> padding_top).
```

`CustomEmojiRef` is the `{id, name?, url?}` payload. EP-1 does not define such a type; its `CustomEmojiIcon` keeps only `customEmojiId`. Add this type to `src/Notion/V1/Common.hs` and export it. Milestone 3 reuses it for icons.

```haskell
-- | Reference to a workspace custom emoji. Responses always include name and
-- url; requests may send only the id.
data CustomEmojiRef = CustomEmojiRef
  { id :: UUID,
    name :: Maybe Text,
    url :: Maybe Text
  }
  deriving stock (Eq, Generic, Show)
-- FromJSON/ToJSON: genericParseJSON/genericToJSON aesonOptions
```

The mention encodings are `{"type":"link_mention","link_mention":v}` and `{"type":"custom_emoji","custom_emoji":r}`.

EP-1's `tasty/WireFormatTests.hs` has two tests that use exactly these mention types as examples of the fallback: "Unknown mention type falls back to UnknownMention" (a `link_mention`) and "custom_emoji mention decodes as UnknownMention". They will now fail. Change their fixtures to a made-up mention type, for example `{"type":"hologram_mention","hologram_mention":{"id":"x"}}`, and rename the second test to "second unknown mention type decodes as UnknownMention". Keep their assertions that the result is `UnknownMention _` and that re-encoding gives back the original object.

In `src/Notion/V1/PropertyValue.hs`:

1. **`SelectOptionValue`.** Add `description :: Maybe Text` as its last field. Update the smart constructors to `SelectOptionValue Nothing name Nothing Nothing`.
2. **`PeopleValue`.** Change it to `PeopleValue Text (Vector PeopleEntry)`. Update `peopleValue ids` to map `PersonEntry . PartialUser`, and add `peopleEntriesValue :: [PeopleEntry] -> PropertyValue`.
3. **`PlaceValue`.** Change it to `PlaceValue Text (Maybe Place)`, and add `placeValue :: Double -> Double -> PropertyValue` (latitude, longitude, other fields `Nothing`).
4. **`VerificationResult`.** Change it as shown below, with `state :: VerificationState` and `verifiedBy :: Maybe UserValue`. Add the smart constructors `verifiedValue :: Maybe Date -> PropertyValue` and `unverifiedValue :: PropertyValue`. Write `ToJSON VerificationResult` by hand: always `state`, plus `date` and `verified_by` when `Just`. That way the smart constructors produce exactly `{"state":"verified","date":{...}}` or `{"state":"unverified"}`.
5. **`RollupResult`.** Change `RollupArrayResult (Vector Value) RollupFunction` to `RollupArrayResult (Vector PropertyValue) RollupFunction`. Parse the array as `Vector Value`, drop elements that are empty objects (the property-item summary sends `{}`), and `parseJSON` the rest. Add `RollupUnknownResult Text Value` as the fallback for an unrecognized `type`.
6. **Unknown types and missing `id`.** Add the constructor `UnknownPropertyValue Text Text Value` (id, type name, the raw value under the type key or `Null`) and use it in place of the `fail` at line 124. Encode it as `object [Key.fromText t .= v]`. Change `pid <- o .: "id"` to `pid <- fromMaybe "" <$> o .:? "id"`, importing `Data.Maybe (fromMaybe)`.

```haskell
data Place = Place
  { lat :: Double,
    lon :: Double,
    name :: Maybe Text,
    address :: Maybe Text,
    awsPlaceId :: Maybe Text,
    googlePlaceId :: Maybe Text
  }
  deriving stock (Eq, Generic, Show)
-- generic instances with aesonOptions (awsPlaceId -> aws_place_id)

data VerificationState
  = Verified
  | Expired
  | Unverified
  | UnknownVerificationState Text
  deriving stock (Eq, Generic, Show)
-- hand-written: "verified" | "expired" | "unverified" | other -> Unknown

data VerificationResult = VerificationResult
  { state :: VerificationState,
    verifiedBy :: Maybe UserValue,
    date :: Maybe Date
  }
  deriving stock (Generic, Show)
```

Export `Place (..)`, `VerificationState (..)`, `placeValue`, `verifiedValue`, `unverifiedValue` and `peopleEntriesValue`. Import `Notion.V1.Users (PeopleEntry (..), UserValue (..), UserReference (..))`.

In `src/Notion/V1/Pages.hs`, replace the paginated constructor with a record. Parse `property_item` with `.:`, then read `type`, `id` (`.:?` with default `""`), `next_url` (`.:?`), and `rollup` (`.:?`, parsed as `RollupResult`). Export `PropertyItemList (..)`, importing `RollupResult` from `Notion.V1.PropertyValue`.

```haskell
data PropertyItemResponse
  = SinglePropertyItem PropertyValue
  | PaginatedPropertyItems PropertyItemList
  deriving stock (Show)

-- | A paginated property item response (title, rich_text, people, relation,
-- rollup). 'nextUrl' is the URL of the next page of items, if any; 'rollup'
-- is the rollup summary Notion attaches to paginated rollup properties.
data PropertyItemList = PropertyItemList
  { items :: ListOf PropertyValue,
    propertyType :: Text,
    propertyId :: Text,
    nextUrl :: Maybe Text,
    rollup :: Maybe RollupResult
  }
  deriving stock (Show)
```

Fix the existing code that stops compiling:

- Positional `SelectOptionValue` patterns get one more `_`. They are in `tasty/Main.hs` around lines 1799, 1850 and 1960, and in `notion-client-example/DatabaseDemo.hs` lines 210 and 218.
- In `notion-client-example/DatabaseDemo.hs` line 241, `PaginatedPropertyItems _list propType` becomes `PaginatedPropertyItems PropertyItemList {propertyType = propType}`.
- If `cabal build all` reports a `UserMention` or `PeopleValue` use elsewhere, adapt it with `userValueId`.

Add these tests to the "Property values and mentions" sub-group:

- **Select option with description encodes.** `SelectValue "" (Just (SelectOptionValue Nothing "急ぎ" Nothing (Just "今日中")))` encodes with `select.description == "今日中"`.
- **People with a group decodes.** Decode `{"id":"p1","type":"people","people":[{"object":"user","id":"u1"},{"object":"user","id":"u2","type":"person","name":"Tanaka Hanako","avatar_url":null,"person":{"email":"hanako@example.com"}},{"object":"group","id":"g1","name":"Design Team"}]}`. Expect three entries: a `PartialUser`, a `FullUser` whose name is `Just "Tanaka Hanako"`, and a `GroupEntry` named `Just "Design Team"`.
- **Group people entry encodes.** Encodes to `{"object":"group","id":"g1","name":"Design Team"}`.
- **Place decodes.** `{"id":"p2","type":"place","place":{"lat":35.6812,"lon":139.7671,"name":"東京駅","address":null,"google_place_id":"abc"}}` yields `Place` with `lat == 35.6812`, `name == Just "東京駅"` and `googlePlaceId == Just "abc"`.
- **Verification decodes.** `{"id":"p3","type":"verification","verification":{"state":"expired","date":{"start":"2026-01-01","end":null,"time_zone":null},"verified_by":{"object":"user","id":"u3"}}}` yields state `Expired` and `verifiedBy == Just (PartialUser "u3")`. An unknown state `"pending_review"` yields `UnknownVerificationState "pending_review"`.
- **Verification smart constructors encode.** `unverifiedValue` encodes to `{"verification":{"state":"unverified"}}`.
- **Rollup array decodes.** `{"id":"p5","type":"rollup","rollup":{"type":"array","function":"show_original","array":[{"type":"number","number":3},{"type":"title","title":[]}]}}` yields a `RollupArrayResult` with two elements, the first a `NumberValue "" (Just 3)`.
- **Unknown property type decodes.** `{"id":"p6","type":"hologram","hologram":{"x":1}}` yields `UnknownPropertyValue "p6" "hologram" _`.
- **Paginated rollup property item decodes.** Decode `{"object":"list","type":"property_item","results":[],"next_cursor":null,"has_more":false,"property_item":{"id":"r1","type":"rollup","next_url":"https://api.notion.com/v1/pages/x/properties/r1?start_cursor=abc","rollup":{"type":"number","number":7,"function":"count"}}}`. Expect `nextUrl` to be `Just ...` and `rollup` to be `Just (RollupNumberResult (Just 7) _)`.
- **Link mention decodes.** A `RichText` fixture with `"type":"mention"` and `"mention":{"type":"link_mention","link_mention":{"href":"https://github.com","title":"GitHub","padding_top":12}}` yields a `LinkMention` whose `paddingTop == Just 12`. Build the full fixture with `plain_text`, `href` and `annotations`, the same way the rich-text fixtures in `tasty/Main.hs` do.
- **Custom emoji mention decodes.** `"mention":{"type":"custom_emoji","custom_emoji":{"id":"e1","name":"bufo","url":"https://example.com/bufo.png"}}` yields `CustomEmojiMention`, and re-encoding it contains `custom_emoji.id == "e1"`.
- **User mention keeps full user.** `"mention":{"type":"user","user":{"object":"user","id":"u9","type":"person","name":"Sato Kenji","avatar_url":null,"person":{}}}` yields `UserMention (FullUser ...)` with the name `Sato Kenji`.

Record the Milestone 2 CHANGELOG entries.

Breaking changes:

- `SelectOptionValue` gains `description`.
- `PeopleValue` holds `PeopleEntry`.
- `PlaceValue` holds `Place`.
- `VerificationResult.state` is `VerificationState`, and `verifiedBy` is `UserValue`.
- `RollupArrayResult` holds `PropertyValue`.
- `PaginatedPropertyItems` holds `PropertyItemList`.
- `UserMention` holds `UserValue`.
- `PropertyValue` and `RollupResult` gain constructors.
- `MentionContent` gains `LinkMention` and `CustomEmojiMention`.

New features:

- `CustomEmojiRef`.
- The `placeValue`, `verifiedValue`, `unverifiedValue` and `peopleEntriesValue` smart constructors.
- `Eq` instances on user types.


### Milestone 3: users, file uploads, icons and object types

At the end of this milestone:

- Custom-emoji icons carry the emoji's `name` and `url` as well as its ID.
- Native icon colors are a typed enumeration.
- `ObjectType` knows `file_upload`, `page_markdown`, `async_task` and `group`, and tolerates unknown values.
- `PageMarkdown` exposes `object`.
- File uploads expose `upload_url`, `complete_url` and a typed creator, and accept a typed `mode`.
- A test pins down that bot users with `"bot":{}` decode.

In `src/Notion/V1/Common.hs`:

- **`CustomEmojiIcon`.** Change `CustomEmojiIcon {customEmojiId :: UUID}` (as left by EP-1) to `CustomEmojiIcon {customEmoji :: CustomEmojiRef}`, reusing the `CustomEmojiRef` added in Milestone 2.
  - **Decoder.** In the `"custom_emoji"` branch, when the nested `custom_emoji` object is present, parse it whole with `parseJSON`, so `id`, `name` and `url` are all kept. Keep EP-1's legacy branch, which reads a top-level `id` as `CustomEmojiRef i Nothing Nothing`.
  - **Encoder.** Emit `{"type":"custom_emoji","custom_emoji": toJSON ref}`. Because `CustomEmojiRef` uses `omitNothingFields`, an ID-only reference still encodes as `{"id":...}`, exactly as EP-1 does.
  - **Existing tests.** Update EP-1's "Custom emoji icon decodes nested object" and "Custom emoji icon encodes nested object" in `tasty/WireFormatTests.hs`, and `testCustomEmojiIconRoundTrip` in `tasty/Main.hs`, to construct and match `CustomEmojiIcon (CustomEmojiRef (UUID "...") Nothing Nothing)`. Their expected JSON does not change.
- **`NoticonColor`.** Add the type below. Change `NativeIcon`'s `iconColor` to `Maybe NoticonColor`. The existing FromJSON/ToJSON for `NativeIcon` need no other change, because they call `.:?` and `.=` on the field. Export `NoticonColor (..)`.

```haskell
-- | Color variant of a Notion native icon.
data NoticonColor
  = NoticonGray
  | NoticonLightgray
  | NoticonBrown
  | NoticonYellow
  | NoticonOrange
  | NoticonGreen
  | NoticonBlue
  | NoticonPurple
  | NoticonPink
  | NoticonRed
  | UnknownNoticonColor Text
  deriving stock (Eq, Generic, Show)
-- hand-written FromJSON (withText) / ToJSON mapping to "gray", "lightgray", ...
```

- **`ObjectType`.** Replace the generic instances with hand-written ones that keep the existing seven strings (`"database"`, `"data_source"`, `"page"`, `"block"`, `"user"`, `"comment"`, `"view"`). Add four constructors plus a fallback. The new constructors carry an `ObjectType` suffix so they do not clash with the `PageMarkdown`, `FileUploadObject`, `GroupObject` and (EP-3) `AsyncTask` data constructors in other modules.

```haskell
data ObjectType
  = Database
  | DataSource
  | Page
  | Block
  | User
  | Comment
  | View
  | FileUploadObjectType      -- "file_upload"
  | PageMarkdownObjectType    -- "page_markdown"
  | AsyncTaskObjectType       -- "async_task"
  | GroupObjectType           -- "group"
  | UnknownObjectType Text
  deriving stock (Eq, Show, Generic)
```

In `src/Notion/V1/Pages.hs`, add `object :: ObjectType` to `PageMarkdown` and replace its generic `FromJSON` with a hand-written one. It reads `object` with `.:?` and defaults to `PageMarkdownObjectType`, then reads `id`, `markdown`, `truncated` and `unknown_block_ids`. The generic `ToJSON` can stay.

In `src/Notion/V1/FileUploads.hs`:

- **Creator type.** Add the types below. Change `FileUploadObject.createdBy` to `FileUploadCreator`, and add `uploadUrl :: Maybe Text` and `completeUrl :: Maybe Text`, parsed with `.:?` and emitted when `Just`.
- **Upload mode.** Add `FileUploadMode`. Change `CreateFileUpload.mode` to `Maybe FileUploadMode`. Update `mkMultiPartUpload` to `Just MultiPart` and `mkExternalUrlUpload` to `Just ExternalUrl`.
- **Exports.** Export `FileUploadCreator (..)`, `FileUploadCreatorType (..)` and `FileUploadMode (..)`.

```haskell
data FileUploadCreatorType
  = CreatorPerson
  | CreatorBot
  | CreatorAgent
  | UnknownCreatorType Text
  deriving stock (Eq, Generic, Show)

-- | Who created a file upload: @{"id": ..., "type": "person" | "bot" | "agent"}@.
data FileUploadCreator = FileUploadCreator
  { id :: UUID,
    type_ :: FileUploadCreatorType
  }
  deriving stock (Eq, Generic, Show)

-- | How the file content will be sent (request only).
data FileUploadMode = SinglePart | MultiPart | ExternalUrl
  deriving stock (Eq, Generic, Show)

instance ToJSON FileUploadMode where
  toJSON = \case
    SinglePart -> String "single_part"
    MultiPart -> String "multi_part"
    ExternalUrl -> String "external_url"
```

Fix the existing code that stops compiling:

- `tasty/Main.hs` `testNativeIconRoundTrip` (around line 814) should use `iconColor = Just NoticonGreen` and compare against `Just NoticonGreen`.
- `testNativeIconReadShape` (around line 837) should compare against `Just NoticonLightgray`.
- If the file-upload serialization tests in `tasty/Main.hs` (around lines 2124-2126) compare `mode` to a `Text`, change them to compare the encoded JSON string, which is unchanged.

Add these tests to the "Users, file uploads, and object types" sub-group:

- **Custom emoji icon keeps name and url.** `{"type":"custom_emoji","custom_emoji":{"id":"e2","name":"sakura","url":"https://example.com/sakura.png"}}` decodes to `CustomEmojiIcon (CustomEmojiRef "e2" (Just "sakura") (Just "https://example.com/sakura.png"))` and re-encodes to the same object.
- **Native icon unknown color.** `{"type":"icon","icon":{"name":"pizza","color":"teal"}}` decodes with `iconColor == Just (UnknownNoticonColor "teal")`.
- **ObjectType new and unknown values.** `"file_upload"`, `"page_markdown"`, `"async_task"` and `"group"` decode to their constructors and re-encode to the same strings. `"meeting_room"` decodes to `UnknownObjectType "meeting_room"`.
- **PageMarkdown object.** `{"object":"page_markdown","id":"p1","markdown":"# hi","truncated":false,"unknown_block_ids":[]}` decodes with `object == PageMarkdownObjectType`. The same payload without `object` also decodes.
- **File upload with URLs and agent creator.** A `FileUploadObject` fixture with `"created_by":{"id":"a1","type":"agent"}`, `"upload_url":"https://api.notion.com/v1/file_uploads/fu1/send"` and `"complete_url":"https://api.notion.com/v1/file_uploads/fu1/complete"` decodes with `CreatorAgent` and both URLs present. Also include `"archived":false`, `"expiry_time":null`, `"filename":null`, `"content_type":null` and `"content_length":null`.
- **CreateFileUpload mode.** `mkMultiPartUpload "動画.mp4" 3 Nothing` encodes `mode` as `"multi_part"`.
- **Bot user with empty bot.** `{"object":"user","id":"b1","type":"bot","name":"Kaizen Bot","avatar_url":null,"bot":{}}` decodes as `UserObject` with `type_ == Bot`. If this fails, make every field of `BotUser` optional, or give `BotUser` a hand-written parser that accepts `{}`, and record that in Surprises & Discoveries.

Record the Milestone 3 CHANGELOG entries.

Breaking changes:

- `CustomEmojiIcon`'s field is now `customEmoji :: CustomEmojiRef` instead of `customEmojiId :: UUID`.
- `NativeIcon.iconColor` is `Maybe NoticonColor`.
- `ObjectType` gains constructors.
- `PageMarkdown` gains `object`.
- `FileUploadObject.createdBy` is `FileUploadCreator`.
- `CreateFileUpload.mode` is `Maybe FileUploadMode`.

New features:

- `FileUploadObject.uploadUrl` and `completeUrl`.


### Milestone 4: webhooks

At the end of this milestone, a webhook handler can decode the file-upload and transcript-deleted events, read `workspace_name` and `api_version`, and pattern-match on typed event data. Any `data` object the typed decoder cannot handle is preserved as a raw `Value`.

In `src/Notion/V1/Webhooks.hs`:

1. **Event types.** Add these `EventType` constructors, with FromJSON and ToJSON strings: `FileUploadCreated` (`"file_upload.created"`), `FileUploadCompleted` (`"file_upload.completed"`), `FileUploadExpired` (`"file_upload.expired"`), `FileUploadUploadFailed` (`"file_upload.upload_failed"`) and `PageTranscriptBlockTranscriptDeleted` (`"page.transcription_block.transcript_deleted"`).
2. **Entity types.** Add these `EntityType` constructors: `FileUploadEntity` (`"file_upload"`) and `BlockEntity` (`"block"`).
3. **New fields.** Add `workspaceName :: Maybe Text` and `apiVersion :: Maybe Text` to `WebhookEvent`. Both are `Maybe` because older deliveries may lack them, and they are parsed with `.:?`.
4. **Typed data.** Change `data_ :: Maybe Value` to `data_ :: Maybe WebhookEventData`. In `FromJSON WebhookEvent`, read `type_` first, then `mRaw <- o .:? "data"`, and set `data_ <- traverse (parseEventData type_) mRaw`.
5. **Imports and exports.** Add the types below, and import `Notion.V1.FileUploads (FileImportResult)` and `Control.Applicative ((<|>))`. Export `WebhookEventData (..)`, `WebhookParent (..)`, `WebhookParentType (..)`, `WebhookBlockRef (..)`, `WebhookRefType (..)`, `UpdatedPropertySchema (..)`, `PropertyAction (..)`, `ViewField (..)` and `parseEventData`.

```haskell
data WebhookParentType
  = WebhookParentSpace
  | WebhookParentBlock
  | WebhookParentPage
  | WebhookParentDatabase
  | WebhookParentTeam
  | WebhookParentAgent
  | UnknownWebhookParentType Text
  deriving stock (Eq, Show, Generic)

-- | The parent of the entity an event is about.
data WebhookParent = WebhookParent
  { id :: UUID,
    type_ :: WebhookParentType,
    dataSourceId :: Maybe UUID
  }
  deriving stock (Eq, Show, Generic)

data WebhookRefType = WebhookRefPage | WebhookRefDatabase | WebhookRefBlock | UnknownWebhookRefType Text
  deriving stock (Eq, Show, Generic)

-- | A page, database, or block referenced by an event (updated blocks,
-- comment parents, transcript targets).
data WebhookBlockRef = WebhookBlockRef
  { id :: UUID,
    type_ :: WebhookRefType
  }
  deriving stock (Eq, Show, Generic)

data PropertyAction = PropertyCreated | PropertyUpdated | PropertyDeleted | UnknownPropertyAction Text
  deriving stock (Eq, Show, Generic)

data UpdatedPropertySchema = UpdatedPropertySchema
  { id :: Text,
    name :: Maybe Text,
    action :: PropertyAction
  }
  deriving stock (Eq, Show, Generic)

data ViewField = ViewFieldName | ViewFieldFilter | ViewFieldSorts | ViewFieldConfiguration | UnknownViewField Text
  deriving stock (Eq, Show, Generic)

-- | Event-specific data, typed by event family.
data WebhookEventData
  = -- | created / deleted / undeleted / moved / locked / unlocked, view.deleted
    ParentData WebhookParent
  | -- | *.content_updated
    ContentUpdatedData WebhookParent (Vector WebhookBlockRef)
  | -- | page.properties_updated: IDs of the changed properties
    PagePropertiesUpdatedData WebhookParent (Vector Text)
  | -- | database.schema_updated / data_source.schema_updated
    SchemaUpdatedData WebhookParent (Vector UpdatedPropertySchema)
  | -- | view.created: the view type (e.g. "table", "board")
    ViewCreatedData WebhookParent Text
  | ViewUpdatedData WebhookParent (Vector ViewField)
  | -- | comment.*: the comment's parent and the containing page ID
    CommentEventData WebhookBlockRef UUID
  | FileUploadFailedData FileImportResult
  | -- | page.transcription_block.transcript_deleted
    TranscriptDeletedData WebhookBlockRef (Maybe Text)
  | -- | Any data the typed decoder does not recognize, kept verbatim.
    RawEventData Value
  deriving stock (Show, Generic)

-- | Decode an event's @data@ according to its event type. Never fails: if the
-- typed shape does not match, the raw value is returned as 'RawEventData'.
parseEventData :: EventType -> Value -> Parser WebhookEventData
parseEventData evType v = typed <|> pure (RawEventData v)
  where
    typed = case v of
      Object o -> case evType of
        PagePropertiesUpdated -> PagePropertiesUpdatedData <$> o .: "parent" <*> o .: "updated_properties"
        -- ... one branch per family, as listed in Context and Orientation ...
        _ -> fail "untyped"
      _ -> fail "data is not an object"
```

The enumeration FromJSON instances map the strings below and fall back to their `Unknown...` constructor:

- `WebhookParentType`: `"space"`, `"block"`, `"page"`, `"database"`, `"team"`, `"agent"`.
- `WebhookRefType`: `"page"`, `"database"`, `"block"`.
- `PropertyAction`: `"created"`, `"updated"`, `"deleted"`.
- `ViewField`: `"name"`, `"filter"`, `"sorts"`, `"configuration"`.

`WebhookParent` and `WebhookBlockRef` get hand-written FromJSON (`id`, `type`, and `data_source_id` via `.:?`). `SchemaUpdatedData` reads `updated_properties` with `.:?` and defaults to an empty vector.

`Parser` comes from `Data.Aeson.Types`. The `Notion.Prelude` re-export of `Data.Aeson` does not include it, so import it explicitly.

`WebhookEvent`'s `ToJSON` is `genericToJSON aesonOptions`, so every new type needs a `ToJSON` instance:

- `WebhookEventData` encodes the inner `data` object without any tag. For example, `ContentUpdatedData p bs` becomes `{"parent": p, "updated_blocks": bs}`, and `RawEventData v` becomes `v`.
- `WebhookParent` and `WebhookBlockRef` encode as their wire objects.
- Each enumeration encodes as its string.

Add these tests to the "Webhooks" sub-group. Build each event from one base fixture that you reuse:

```json
{"id":"evt-1","timestamp":"2026-09-14T10:00:00.000Z","workspace_id":"ws-1","workspace_name":"Yamada Lab","subscription_id":"sub-1","integration_id":"int-1","authors":[{"id":"u1","type":"person"}],"attempt_number":1,"api_version":"2026-03-11"}
```

Add `type`, `entity` and `data` per test, for example with `KeyMap.insert` on the decoded base object:

- **file_upload.upload_failed.** `type` `"file_upload.upload_failed"`, `entity` `{"id":"fu-1","type":"file_upload"}`, and `data` `{"file_import_result":{"type":"error","imported_time":"2026-09-14T10:00:00.000Z","error":{"type":"download_error","code":"timeout","message":"Download timed out","parameter":null,"status_code":504}}}`. It yields `FileUploadUploadFailed`, `FileUploadEntity`, `workspaceName == Just "Yamada Lab"`, `apiVersion == Just "2026-03-11"`, and `data_ == Just (FileUploadFailedData FileImportError {..})`. Pattern-match; `FileImportResult` has no `Eq`.
- **file_upload.created without data.** Yields `data_ == Nothing`, checked by pattern match.
- **page.transcription_block.transcript_deleted.** `data` `{"target":{"id":"b1","type":"block"},"transcript_id":null}` yields `TranscriptDeletedData (WebhookBlockRef "b1" WebhookRefBlock) Nothing`.
- **database.content_updated on linked database.** `entity` `{"id":"d1","type":"block"}` and `data` `{"parent":{"id":"p1","type":"page"},"updated_blocks":[{"id":"b2","type":"block"}]}` yield `BlockEntity` and `ContentUpdatedData` with one ref.
- **data_source.schema_updated.** `data` `{"parent":{"id":"db1","type":"database","data_source_id":"ds1"},"updated_properties":[{"id":"abc","name":null,"action":"deleted"}]}` yields `SchemaUpdatedData` with `dataSourceId == Just "ds1"` and `PropertyDeleted`.
- **page.properties_updated.** `data` `{"parent":{"id":"s1","type":"space"},"updated_properties":["title","xyz"]}` yields `PagePropertiesUpdatedData` with a `WebhookParentSpace` parent.
- **view.updated.** `updated_fields` `["filter","sorts"]` yields `ViewUpdatedData _ [ViewFieldFilter, ViewFieldSorts]`.
- **comment.created.** `data` `{"parent":{"id":"p1","type":"page"},"page_id":"p1"}` yields `CommentEventData`.
- **Mismatched data falls back to raw.** `page.created` with `data` `{"unexpected":true}` yields `RawEventData`, and the event still decodes.

Record the Milestone 4 CHANGELOG entries.

Breaking changes:

- `WebhookEvent.data_` is `Maybe WebhookEventData`.
- `WebhookEvent` gains `workspaceName` and `apiVersion`.
- `EventType` and `EntityType` gain constructors.

New features:

- Typed webhook event data.
- File-upload and transcript-deleted events.


## Concrete Steps

All commands run from the repository root, `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`.

**Step 0: confirm the hard dependency (EP-1) has landed.** Each of these searches should print at least one match:

```bash
grep -n "UnknownMention" src/Notion/V1/RichText.hs
grep -n "AgentParent" src/Notion/V1/Common.hs
grep -n "DefaultBackground\|default_background" src/Notion/V1/Common.hs
```

If any is empty, stop. EP-1 must be implemented first, because this plan edits the same parsers. Check whether EP-3 has landed with `ls src/Notion/V1/AsyncTasks.hs`. If it has, read `createPage`'s type in `src/Notion/V1.hs` and give `createPageFiltered` the same return type.

**Step 1: create the test module.** Create `tasty/ObjectFieldTests.hs` with this starting content:

```haskell
module ObjectFieldTests (tests) where

import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy.Char8 qualified as L8
import Data.Map qualified as Map
import Data.Vector qualified as Vector
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Object Field Gaps"
    [ testGroup "Page and block requests" [],
      testGroup "Property values and mentions" [],
      testGroup "Users, file uploads, and object types" [],
      testGroup "Webhooks" []
    ]
```

Register the module in `notion-client.cabal` and `tasty/Main.hs` as described in Milestone 1, then build. The first build compiles all dependencies and can take several minutes.

```bash
cabal build all
cabal test notion-client:test:tasty
```

A warning about unused imports is expected until tests are added. The expected result is that the existing suite still passes and the output lists an empty `Object Field Gaps` group.

**Steps 2 to 5: implement each milestone.** For each milestone in order, edit the files, add the tests, fix the broken call sites, and run:

```bash
cabal build all 2>&1 | grep -E "error|rror:" ; cabal test notion-client:test:tasty --test-show-details=direct
```

To run only this plan's tests, use a tasty pattern:

```bash
cabal test notion-client:test:tasty --test-options='-p "Object Field Gaps"'
```

Expected tail of the output once a milestone is done (the test count grows with each milestone):

```text
    Webhooks
      file_upload.upload_failed:                           OK
      ...
All 45 tests passed (0.02s)
```

**Step 6: format and commit.** Commit once per milestone. Run `treefmt` (or let the pre-commit hook run it), re-stage, and commit using Conventional Commits with both trailers:

```text
feat(blocks)!: add partial block update payloads

Replace BlockUpdate with BlockUpdatePayload/BlockUpdateContent so updates
send only the fields Notion accepts, add filter_properties to page create
and update, and narrow MovePage to page or data source parents.

MasterPlan: docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md
ExecPlan: docs/plans/11-close-page-block-property-value-user-file-upload-and-webhook-field-gaps.md
```

Suggested subjects for the remaining milestones: `feat(property-value)!: type place, verification, group people and rollup arrays`, `feat(file-uploads)!: type upload creator, mode, icon colors and object types`, and `feat(webhooks)!: add file upload events and typed event data`.


## Validation and Acceptance

The plan is accepted when all four of the following hold.

**1. Both packages build.** `cabal build all` succeeds for `notion-client`, `notion-client-effectful` and `notion-client-example`, with no new warnings in edited modules.

**2. The test suite passes.** `cabal test notion-client:test:tasty` reports `All N tests passed`. The `Object Field Gaps` group must contain at least these passing tests, which prove the behavior rather than just compilation:

- **Encoding.** The `to_do` checked-only update encodes to exactly `{"to_do":{"checked":true}}`. The table-header update carries no `table_width`/`children`. `trashBlockUpdate` encodes to `{"in_trash":true}`. `MovePage` has no `position`. The update template has no `none`.
- **Decoding.** Audio and embed captions, `unsupported.block_type`, group people, place, verification, typed rollup arrays, property item `next_url` and rollup summary, `link_mention`, `custom_emoji` and full-user mentions all decode.
- **Tolerance.** Unknown icon color, object type, verification state and property type all decode to their fallback constructors.
- **File uploads.** Objects with `upload_url`, `complete_url` and an `agent` creator decode.
- **Webhooks.** Every webhook event family in Milestone 4 decodes to its typed `WebhookEventData`, and mismatched data falls back to `RawEventData`.

These tests fail before the change (they do not compile, or the decoder fails) and pass after it.

**3. A live check, when a token is available.** It is optional, but recommended. With `NOTION_TOKEN` set to an integration token and `NOTION_TEST_PAGE_ID` set to a page the integration can edit, run:

```bash
cabal repl notion-client
```

Then enter:

```haskell
:set -XOverloadedStrings
import Notion.V1
import Notion.V1.Blocks
import Notion.V1.Common
import qualified Data.Text as T
import qualified Data.Vector as V
import System.Environment
tok <- T.pack <$> getEnv "NOTION_TOKEN"
pg <- T.pack <$> getEnv "NOTION_TEST_PAGE_ID"
env <- getClientEnv "https://api.notion.com/v1"
let m = makeMethods env tok
r <- appendBlockChildren m (UUID pg) (AppendBlockChildren (V.singleton (toDoBlock (mkRichText "check me") False)) Nothing)
let BlockObject {id = bid} = V.head (results r)
b <- updateBlock m bid (mkBlockUpdate (UpdateToDo (ToDoUpdate Nothing (Just True) Nothing)))
content b
_ <- updateBlock m bid trashBlockUpdate
```

Observe that `content b` prints a `ToDoBlock` with `checked = True` and the original rich text "check me". The partial update did not erase the text. The final call moves the block to the trash without error.

**4. The CHANGELOG is complete.** `CHANGELOG.md` has a `## Unreleased` section listing every breaking change and new feature named in the milestones.


## Idempotence and Recovery

All edits are ordinary source changes tracked by git, so every step is safe to repeat. Re-running `cabal build all` and `cabal test` has no side effects. The live GHCi check creates one to-do block and then trashes it. If it is interrupted, the leftover block can be deleted in the Notion UI or with `deleteBlock`.

Because each milestone is committed separately, a failed milestone can be abandoned with `git restore .` (or `git stash`) back to the previous milestone's commit, without losing earlier work. If a rebase onto EP-1, EP-3, EP-4 or EP-5 conflicts in `src/Notion/V1.hs`, `Pages.hs`, `Common.hs` or `CHANGELOG.md`, resolve it by keeping both sides' additions. These plans add different constructors, fields and routes, and do not change the same lines' meaning. Then rebuild both packages.

If the bot-user `{}` test fails, or `parseEventData` turns out to be too strict for real deliveries, prefer loosening the decoder (`.:?` with defaults) over deleting the test. Record the evidence in Surprises & Discoveries.


## Interfaces and Dependencies

No new package dependencies are needed. The plan uses `aeson` (already `>=2.2 && <2.3`), `servant` (`QueryParams`), `vector`, `containers` and `text`, all already in `notion-client.cabal`. The test suite already depends on `aeson`, `bytestring`, `containers`, `scientific`, `tasty`, `tasty-hunit`, `text` and `vector`.

At the end of Milestone 1 these must exist:

```haskell
-- Notion.V1
createPageFiltered :: Methods -> [Text] -> CreatePage -> IO PageObject
updatePageFiltered :: Methods -> PageID -> [Text] -> UpdatePage -> IO PageObject
updateBlock        :: Methods -> BlockID -> Blocks.BlockUpdatePayload -> IO BlockObject
-- Notion.V1.Pages
data UpdatePageTemplate = UpdateDefaultTemplate (Maybe Text) | UpdateTemplateById UUID (Maybe Text)
data MovePageParent = MoveToPage UUID | MoveToDataSource UUID
newtype MovePage = MovePage {parent :: MovePageParent}
data InsertPosition = InsertAtStart | InsertAtEnd
-- Notion.V1.BlockContent (re-exported by Notion.V1.Blocks)
data BlockUpdatePayload = BlockUpdatePayload {content :: Maybe BlockUpdateContent, inTrash :: Maybe Bool}
data BlockUpdateContent -- constructors listed in Milestone 1
mkBlockUpdate :: BlockUpdateContent -> BlockUpdatePayload
trashBlockUpdate :: BlockUpdatePayload
blockUpdateFromContent :: BlockContent -> Maybe BlockUpdateContent
tabBlock :: Vector (Vector RichText, Maybe Icon, Vector BlockContent) -> BlockContent
-- Notion.V1.Effectful.Effect
createPageFiltered :: (Notion :> es) => [Text] -> CreatePage -> Eff es PageObject
updatePageFiltered :: (Notion :> es) => PageID -> [Text] -> UpdatePage -> Eff es PageObject
updateBlock :: (Notion :> es) => BlockID -> Blocks.BlockUpdatePayload -> Eff es BlockObject
```

At the end of Milestone 2:

```haskell
-- Notion.V1.Users
data UserValue = PartialUser UserID | FullUser UserObject
userValueId :: UserValue -> UserID
data GroupObject = GroupObject {id :: UUID, name :: Maybe Text}
data PeopleEntry = PersonEntry UserValue | GroupEntry GroupObject
-- Notion.V1.Common
data CustomEmojiRef = CustomEmojiRef {id :: UUID, name :: Maybe Text, url :: Maybe Text}
-- Notion.V1.RichText
UserMention :: UserValue -> MentionContent
LinkMention :: LinkMentionValue -> MentionContent
CustomEmojiMention :: CustomEmojiRef -> MentionContent
-- Notion.V1.PropertyValue
data Place; data VerificationState; placeValue :: Double -> Double -> PropertyValue
verifiedValue :: Maybe Date -> PropertyValue; unverifiedValue :: PropertyValue
peopleEntriesValue :: [PeopleEntry] -> PropertyValue
UnknownPropertyValue :: Text -> Text -> Value -> PropertyValue
-- Notion.V1.Pages
data PropertyItemList = PropertyItemList {items, propertyType, propertyId, nextUrl, rollup}
```

At the end of Milestone 3:

```haskell
-- Notion.V1.Common
data NoticonColor -- 10 colors + UnknownNoticonColor Text
NativeIcon :: Text -> Maybe NoticonColor -> Icon
CustomEmojiIcon :: CustomEmojiRef -> Icon
-- ObjectType gains FileUploadObjectType, PageMarkdownObjectType, AsyncTaskObjectType,
-- GroupObjectType, UnknownObjectType Text
-- Notion.V1.FileUploads
data FileUploadCreator = FileUploadCreator {id :: UUID, type_ :: FileUploadCreatorType}
data FileUploadMode = SinglePart | MultiPart | ExternalUrl
```

At the end of Milestone 4:

```haskell
-- Notion.V1.Webhooks
data WebhookEventData -- constructors listed in Milestone 4
parseEventData :: EventType -> Value -> Parser WebhookEventData
-- WebhookEvent gains workspaceName, apiVersion :: Maybe Text; data_ :: Maybe WebhookEventData
```

Cross-plan dependencies:

- **EP-1** (hard dependency) supplies the lenient `MentionContent`, `Color`, `Icon` custom-emoji, `UserOwner`/`PersonUser`, `CodeLanguage` and webhook `accessible_by` changes that this plan builds on.
- **EP-3** (soft dependency) may have changed `createPage`'s return type and added `allow_async`. This plan mirrors any such return type in `createPageFiltered` and preserves `allow_async` encoding in the hand-written `CreatePage` ToJSON.
- **Partial page and block objects** are deliberately not handled here (see the Decision Log). The MasterPlan coordinator should assign one shared representation.


Revision 2026-09-15 (implementation): All four milestones and the live check are done. Progress, Surprises & Discoveries, the Decision Log and Outcomes & Retrospective record how the implementation differed from the draft. The payload field is `updateContent`, `UpdatePage.icon`/`cover` are `Clearable`, and `UserValue` falls back to a partial user. The draft's mention-test rename was unnecessary, and `Text` fixtures replaced `Char8` literals. The ADRs subsection of Context and Orientation now cites the ADRs that exist, and ADRs 1, 4 and 5 were amended with this plan's cases.
