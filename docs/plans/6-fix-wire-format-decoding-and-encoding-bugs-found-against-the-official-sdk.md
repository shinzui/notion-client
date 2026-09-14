---
id: 6
slug: fix-wire-format-decoding-and-encoding-bugs-found-against-the-official-sdk
title: "Fix Wire-Format Decoding and Encoding Bugs Found Against the Official SDK"
kind: exec-plan
created_at: 2026-09-14T18:46:51Z
master_plan: "docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md"
provenance:
  created_by:
    model: "claude-opus-5"
    harness: "claude-code"
    at: 2026-09-14T18:46:51Z
---

# Fix Wire-Format Decoding and Encoding Bugs Found Against the Official SDK

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Today the Haskell `notion-client` library throws a JSON parse error on several ordinary Notion responses, and it builds some requests in a shape Notion rejects. A page whose text uses the `default_background` color cannot be retrieved. A code block written in `toml` breaks listing the block children of its page. A page with a custom-emoji icon cannot be decoded. A bot owned by a user cannot be decoded, and neither can a person without a visible email. Meeting-notes blocks break decoding. Querying a data source with `filterProperties` set makes Notion reject the request. Creating a page with position `Start` or `End` sends a shape Notion does not accept. A webhook signature written in uppercase hex fails verification.

After this plan, every one of those responses decodes. Every one of those requests goes out in the shape the official Notion JavaScript SDK sends. Where Notion might later add a new color, icon kind, mention kind, parent kind, code language, number format or formula result kind, the value decodes into an explicit "unknown" constructor that carries the raw JSON instead of failing the whole response.

You can see it working in two ways. First, run the new unit-test module `tasty/WireFormatTests.hs` (`cabal test tasty --test-options='-p /WireFormat/'`). It decodes JSON fixtures copied from the SDK's type definitions, and it captures the HTTP request the client builds without touching the network. Second, if you have a Notion token, query a data source with `filterProperties = Just ["title"]` and see a normal result list instead of an HTTP 400.

This is EP-1 of the MasterPlan `docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md`. It contains only defects that cause a runtime failure today. Missing-but-harmless fields belong to the other child plans.


## Progress

- [ ] Milestone 1: Create `tasty/WireFormatTests.hs`, wire it into `notion-client.cabal` and `tasty/Main.hs`, and confirm the empty group runs.
- [ ] Milestone 1: `Color` gains `DefaultBackground` and `UnknownColor Text`, with hand-written instances (`src/Notion/V1/Common.hs`).
- [ ] Milestone 1: `Parent` gains `AgentParent` and `UnknownParent Value` (`src/Notion/V1/Common.hs`).
- [ ] Milestone 1: `Icon` decodes and encodes the nested `custom_emoji` object and gains `UnknownIcon Value` (`src/Notion/V1/Common.hs`); update `testCustomEmojiIconRoundTrip` in `tasty/Main.hs`.
- [ ] Milestone 1: `MentionContent` gains `UnknownMention Value` (`src/Notion/V1/RichText.hs`).
- [ ] Milestone 1: Ten Milestone-1 tests pass; CHANGELOG entries added.
- [ ] Milestone 2: `CodeLanguage` gains the 18 missing languages and `OtherLanguage Text` (`src/Notion/V1/BlockContent.hs`).
- [ ] Milestone 2: Meeting-notes payload typed (`MeetingNotesStatus`, `MeetingNotesChildren`, `MeetingCalendarEvent`, `MeetingRecording`), the `transcription` alias decodes, and `withChildren` no longer touches meeting notes; update `testBlockContentMeetingNotes` in `tasty/Main.hs`.
- [ ] Milestone 2: `PersonUser.email` becomes optional, and `UserOwner` reads the nested user object and gains `UnknownOwner` (`src/Notion/V1/Users.hs`).
- [ ] Milestone 2: `NumberFormat` gains `OtherNumberFormat Text` (`src/Notion/V1/Properties.hs`).
- [ ] Milestone 2: `UniqueIdResult.number` becomes `Maybe Natural`, and `FormulaResult` gains `FormulaUnsupportedResult` and `UnknownFormulaResult Value` (`src/Notion/V1/PropertyValue.hs`).
- [ ] Milestone 2: Ten Milestone-2 tests pass; CHANGELOG entries added.
- [ ] Milestone 3: `filter_properties` sent as a repeated query parameter for `queryDataSource` and `queryDatabase` (`DataSources.hs`, `Databases.hs`, `V1.hs`), with `Methods` signatures unchanged.
- [ ] Milestone 3: New `PagePosition` type used by `CreatePage.position` (`src/Notion/V1/Pages.hs`).
- [ ] Milestone 3: Four Milestone-3 tests pass; `cabal build all` builds `notion-client-effectful` unchanged; CHANGELOG entries added.
- [ ] Milestone 4: `WebhookEvent.accessibleBy` defaults to empty when absent, and `verifySignature` validates the prefix, length and hex and ignores hex case (`src/Notion/V1/Webhooks.hs`).
- [ ] Milestone 4: Three Milestone-4 tests pass; full `cabal test` passes; CHANGELOG finalized; MasterPlan EP-1 progress rows ticked.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Keep the `Methods` field signatures of `queryDataSource` and `queryDatabase` unchanged. `filterProperties` stays in the `QueryDataSource`/`QueryDatabase` records. It is removed from the JSON body and passed to a new `QueryParams "filter_properties" Text` route segment by a small wrapper inside `makeMethods`.
  Rationale: This fixes the wire format without breaking any caller. It follows the precedent `retrievePage pid = retrievePageFiltered pid []` in `src/Notion/V1.hs`. Because no `Methods` field changes, the `notion-client-effectful` companion needs no edit. That differs from the MasterPlan's Integration Points note, which expected a signature change mirrored in the effectful package. Only the exported Servant `API` type changes.
  Date: 2026-09-14

- Decision: Add an "unknown" fallback constructor to every closed sum this plan touches: `UnknownColor Text`, `UnknownParent Value`, `UnknownIcon Value`, `UnknownMention Value`, `OtherLanguage Text`, `OtherNumberFormat Text`, `UnknownFormulaResult Value`, `UnknownOwner`, and `UnknownMeetingNotesStatus Text`.
  Rationale: The MasterPlan's tolerant-decoding rule says decoders must never fail on a value Notion adds later. Each of these types has failed in exactly that way. Sum types this plan does not otherwise touch (for example `UserType`, `ObjectType`) are left to their resource plans.
  Date: 2026-09-14

- Decision: `CustomEmojiIcon` keeps its single field `customEmojiId :: UUID`. Only its JSON shape changes: it now reads and writes `{"type":"custom_emoji","custom_emoji":{"id":...}}`. The decoder also still accepts the old top-level `id` shape.
  Rationale: This fixes the crash and the rejected request without changing the constructor's arity, so existing pattern matches keep compiling. Capturing the response's `name` and `url` is a missing-field gap, not a crash. It is left for `docs/plans/11-close-page-block-property-value-user-file-upload-and-webhook-field-gaps.md`.
  Date: 2026-09-14

- Decision: Type the whole meeting-notes payload here (status enum with fallback, children object, calendar event, recording), not only the two fields that crash (`title`, `children`).
  Rationale: The coordinator's scoping for EP-1 says the minimal full typing can be done here and EP-6 will not touch it further. That differs from the MasterPlan's Dependency Graph text ("`MeetingNotes` block fields become fully typed" in EP-6). The MasterPlan should be reconciled. Timestamps inside the payload stay `Text`, so a format surprise cannot cause a new decode failure.
  Date: 2026-09-14

- Decision: Leave `MovePage.position` (sent by Haskell, absent from the JS SDK's `movePage` body) unchanged.
  Rationale: No evidence was found that Notion rejects it, so it does not meet EP-1's "fails at runtime today" rule. It is recorded for `docs/plans/11-close-page-block-property-value-user-file-upload-and-webhook-field-gaps.md`.
  Date: 2026-09-14

- Decision: Exclude the non-page results of a data-source query (partial pages, data sources) from this plan, even though they also fail to decode.
  Rationale: The MasterPlan assigns the page-or-data-source result union to EP-5 (`docs/plans/10-type-data-source-database-and-search-results-and-close-query-and-filter-gaps.md`), which reshapes the same response type.
  Date: 2026-09-14

- Decision: Add `FormulaResult`'s `unsupported` kind, which the coordinator's list did not name.
  Rationale: The JS SDK's `FormulaPropertyValueResponse` union includes `{type:"unsupported", unsupported:{}}`, and `src/Notion/V1/PropertyValue.hs` fails with "Unknown formula result type". Any page with such a formula cannot be decoded, which meets the crash rule.
  Date: 2026-09-14

- Decision: Classify this plan as breaking under the Haskell Package Versioning Policy (PVP) and do not bump the version here.
  Rationale: Several existing record fields change type (listed in Plan of Work), and the PVP treats new constructors on exported types as breaking too. The MasterPlan's option of a standalone patch release such as `0.7.1.0` is therefore not PVP-compliant. The release must be a major bump (`0.8.0.0`), cut by the MasterPlan's release step.
  Date: 2026-09-14


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

The repository root is `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`. It holds a Haskell library, `notion-client`, that talks to the Notion HTTP API. It is built with `cabal` on GHC 9.12.2, with `GHC2024` as the default language. Every package enables the extensions `DuplicateRecordFields` (several record types may share a field name), `OverloadedStrings` (string literals can be `Text`), `OverloadedLabels` and `RecordWildCards` (`Foo {..}` binds or builds every field by name). They are set as `default-extensions` in `notion-client.cabal`. Modules that have a record field called `id` import `Prelude hiding (id)`. A pre-commit hook runs `treefmt`, which reformats files. If a commit fails because files were reformatted, stage them again and repeat the commit.

**What "wire format" means here.** The wire format is the exact JSON that travels over HTTP. A decoder is a `FromJSON` instance from the `aeson` library: it turns response JSON into a Haskell value, and a single failure anywhere makes the whole response fail with an exception. An encoder is a `ToJSON` instance, which turns a Haskell request value into JSON.

**Reference client.** The official Notion TypeScript SDK, version 5.26.0, is checked out at `/Users/shinzui/Keikaku/hub/notion-sdk-js`. Its files `src/api-endpoints/*.ts` are generated from Notion's own API schema. Every JS wire shape this plan needs is transcribed below, so you do not need to open that repository.

**How JSON instances are written in this repository.** `src/Notion/Prelude.hs` defines `aesonOptions`. It converts camelCase field names to snake_case (`createdTime` becomes `created_time`), strips a trailing underscore (`type_` becomes `type`), applies the same conversion to constructor names, and omits `Nothing` fields when encoding. Simple records use `genericParseJSON aesonOptions`. Anything with a discriminator is hand-written: a `\case` on `Object o`, reading `o .: "type"` and then the key named after the type. `Notion.Prelude` re-exports `Text`, `Value (..)` (so `String` and `Object` are in scope), `Vector`, `Natural`, `POSIXTime`, `FromJSON`, `ToJSON` and the Servant combinators `Capture`, `QueryParam`, `ReqBody`, `Get`, `Post`, `Patch`, `(:>)` and `(:<|>)`. It does not export `QueryParams`; import that from `Servant.API` as `src/Notion/V1/Pages.hs` already does. It also exports its own `stripPrefix :: String -> String -> String`, so use `Data.Text.stripPrefix` qualified.

**How endpoints are wired.** Each resource module (for example `src/Notion/V1/DataSources.hs`) ends with a Servant `API` type. Servant is a library that describes HTTP routes as a Haskell type and generates client functions from it. `src/Notion/V1.hs` combines all the resource `API` types under two required headers, `Authorization` and `Notion-Version`. Its function `makeMethods :: ClientEnv -> Text -> Methods` pattern-matches the generated client functions, in exactly the order of the routes, and fills a record called `Methods` whose fields are plain `IO` functions (for example `queryDataSource :: DataSourceID -> DataSources.QueryDataSource -> IO (ListOf PageObject)` at line 177). Wrappers that adapt a raw client function live in the `where` block of `makeMethods`; `retrievePage pid = retrievePageFiltered pid []` (line 150) is the model. The companion package `notion-client-effectful` (`notion-client-effectful/src/Notion/V1/Effectful/Effect.hs` and `Interpreter.hs`) mirrors every `Methods` field as an effect constructor with the same argument types. Any change to a `Methods` field's type must be mirrored there in the same commit. This plan deliberately changes no `Methods` field, so that package needs no edit, but `cabal build all` must still build it.

**Tests.** The test suite is `test-suite tasty` in `notion-client.cabal` (around line 90). Its only module today is `tasty/Main.hs` (about 2300 lines). There is no `other-modules` field yet. Its `tests :: IO TestTree` ends with a top-level `testGroup "Notion Client Tests"` whose list is `[jsonParsingTests, jsonSerializationTests, propertyValueTests, fileUploadTests, basicIntegration, markdownE2E, pageE2E, databaseE2E, viewE2E]`. Integration groups are skipped unless `NOTION_TOKEN` is set. By MasterPlan rule, this plan's tests go in a new module `tasty/WireFormatTests.hs` exporting `tests :: TestTree`. That module is listed under `other-modules` of the test suite and added as one line to that list. Two existing tests in `tasty/Main.hs` assert the old, wrong shapes and must be updated: `testCustomEmojiIconRoundTrip` (around line 843) and `testBlockContentMeetingNotes` (around line 1541). Fixtures must never use the maintainer's real name; use made-up Japanese names such as "Tanaka Hanako" or "Sato Kenji".

**ADRs.** This repository has no `docs/adr/` directory; no relevant ADR exists.

The defects, the files that contain them, and the JS shapes that are correct follow. Each was verified against both codebases on 2026-09-14.

**1. Colors (`src/Notion/V1/Common.hs`, `data Color`, lines 101–127).** `Color` has `Default`, nine plain colors and nine `*Background` colors, with generic instances. It lacks `default_background`. Because `Annotations.color` (in `src/Notion/V1/RichText.hs`) and every block's `color` use `Color`, a single rich-text span with that color fails the whole page or block list. JS (`src/api-endpoints/common.ts`, `ApiColor`, lines 26–46):

```typescript
export type ApiColor =
  | "default" | "gray" | "brown" | "orange" | "yellow" | "green" | "blue" | "purple" | "pink" | "red"
  | "default_background" | "gray_background" | "brown_background" | "orange_background"
  | "yellow_background" | "green_background" | "blue_background" | "purple_background"
  | "pink_background" | "red_background"
```

**2. Parents (`src/Notion/V1/Common.hs`, `data Parent`, lines 47–95).** The type-directed parser `parseByType` handles `database_id`, `data_source_id`, `page_id`, `block_id` and `workspace` (plus legacy spellings without `_id`), and otherwise calls `fail "Unknown parent type"`. JS (`common.ts` lines 4–9 and 992–998) adds an agent parent to `ParentForBlockBasedObjectResponse`, which is the parent type of pages and blocks:

```typescript
type AgentIdParentForBlockBasedObjectResponse = { type: "agent_id"; agent_id: IdResponse }
```

**3. Custom emoji icons (`src/Notion/V1/Common.hs`, `data Icon`, lines 130–170).** The decoder reads `"custom_emoji" -> CustomEmojiIcon <$> o .: "id"` (line 153), and the encoder writes `{"type":"custom_emoji","id":...}` (line 169). Both are wrong. JS response (`common.ts` lines 386–399) and request (lines 2222–2233):

```typescript
type CustomEmojiPageIconResponse = { type: "custom_emoji"; custom_emoji: { id: IdResponse; name: string; url: string } }
type CustomEmojiPageIconRequest = { type?: "custom_emoji"; custom_emoji: { id: IdRequest; name?: string; url?: string } }
```

**4. Mentions (`src/Notion/V1/RichText.hs`, `data MentionContent`, lines 80–146).** The decoder handles `user`, `page`, `database`, `date`, `link_preview` and `template_mention` (with subtypes `template_mention_date` and `template_mention_user`). It fails on anything else (lines 114–115). JS (`common.ts` lines 812–873) also sends `link_mention` and `custom_emoji` mentions:

```json
{ "type": "custom_emoji", "custom_emoji": { "id": "…", "name": "sakura", "url": "https://…" } }
{ "type": "link_mention", "link_mention": { "href": "https://…", "title": "…" } }
```

Typed constructors for these two are owned by EP-6 (`docs/plans/11-close-page-block-property-value-user-file-upload-and-webhook-field-gaps.md`). This plan only adds a fallback so they stop failing.

**5. Code languages (`src/Notion/V1/BlockContent.hs`, `data CodeLanguage`, lines 62–135; `FromJSON` lines 137–211; `ToJSON` from line 213).** The type has 72 constructors, and the parser ends with `other -> fail $ "Unknown CodeLanguage: "`. JS `LanguageRequest` (`common.ts` lines 2289–2379) is also the response type of a code block's `language`. It contains these 18 values the Haskell type lacks: `"abc"`, `"agda"`, `"ascii art"`, `"assembly"`, `"bnf"`, `"coq"`, `"dhall"`, `"ebnf"`, `"hcl"`, `"idris"`, `"llvm ir"`, `"mathematica"`, `"notion formula"`, `"purescript"`, `"racket"`, `"smalltalk"`, `"solidity"`, `"toml"`.

**6. Meeting-notes blocks (`src/Notion/V1/BlockContent.hs`).** The constructor (lines 580–587) is:

```haskell
MeetingNotesBlock
  { meetingTitle :: Text,
    meetingStatus :: Maybe Text,
    calendarEvent :: Maybe Value,
    recording :: Maybe Value,
    children :: Vector BlockContent
  }
```

The parser (lines 918–924) requires `title` as a string and reads `children` as an array of blocks. The encoder is at lines 750–757, and `withChildren` sets `children` on it at line 1076. Unknown block types fall through to `UnknownBlock Text Value` (line 930), so the deprecated `transcription` type currently becomes `UnknownBlock`. JS (`src/api-endpoints/blocks.ts` lines 30–35, 505–537 and 743–763):

```typescript
type ApiTranscriptionStatus =
  | "transcription_not_started" | "transcription_paused" | "transcription_in_progress"
  | "summary_in_progress" | "notes_ready"
// meeting-notes.ts additionally allows "transcription_failed"
export type TranscriptionBlockObjectResponse = { type: "transcription"; transcription: TranscriptionBlockResponse; /* common block fields */ }
export type MeetingNotesBlockObjectResponse = { type: "meeting_notes"; meeting_notes: TranscriptionBlockResponse; /* common block fields */ }
type TranscriptionBlockResponse = {
  title?: Array<RichTextItemResponse>
  status?: ApiTranscriptionStatus
  children?: { summary_block_id?: IdRequest; notes_block_id?: IdRequest; transcript_block_id?: IdRequest }
  calendar_event?: { start_time: string; end_time: string; attendees?: Array<IdRequest> }
  recording?: { start_time?: string; end_time?: string }
}
```

So any real meeting-notes block fails today: `title` is an array, not a string, and `children` is an object, not an array. The `transcription` block is the same payload under the old name, renamed in API version 2026-03-11.

**7. Users (`src/Notion/V1/Users.hs`).** `newtype PersonUser = PersonUser { email :: Text }` (lines 52–58) uses a generic decoder, so a person object `{}` without an email fails. `UserOwner` (lines 82–95; not exported today) decodes `"user" -> UserOwner ownerType <$> (o .: "user")` with `user :: UserID`, but Notion sends an object there, so decoding any bot owned by a user fails (for example `retrieveMyUser` for a public integration). JS (`common.ts` lines 77–111 and 1044–1052):

```typescript
export type PersonUserObjectResponse = { type: "person"; person: { email?: string } }
type BotInfoResponse = {
  owner:
    | { type: "user"; user: { id: IdResponse; object: "user"; name: string | null; avatar_url: string | null; type: "person"; person: { email?: string } } | { id: IdResponse; object: "user" } }
    | { type: "workspace"; workspace: true }
  workspace_id: string
  workspace_limits: { max_file_upload_size_in_bytes: number }
}
```

**8. Number formats (`src/Notion/V1/Properties.hs`, `data NumberFormat`, from line 103; `FromJSON` lines 145–186).** This is a closed enum of 39 values that ends with `fail "Unknown NumberFormat"`. JS (`common.ts` line 2506) declares `export type NumberFormat = string`: Notion documents the set as open, so any data source with a newer currency fails today.

**9. Property values (`src/Notion/V1/PropertyValue.hs`).** `data UniqueIdResult = UniqueIdResult { number :: Natural, prefix :: Maybe Text }` (lines 281–291) fails when `number` is null. `data FormulaResult` (lines 223–247) handles `string`, `number`, `boolean` and `date`, and fails on anything else. JS (`common.ts` lines 2973–2978, 3016–3019 and 3071–3075):

```typescript
type UniqueIdPropertyValueResponse = { prefix: string | null; number: number | null }
type FormulaPropertyValueResponse = Boolean… | Date… | Number… | String… | { type: "unsupported"; unsupported: EmptyObject }
```

**10. `filter_properties` on queries (`src/Notion/V1/DataSources.hs` lines 132–145 and 178–182; `src/Notion/V1/Databases.hs` lines 145–158 and 168–171).** Both `QueryDataSource` and `QueryDatabase` have `filterProperties :: Maybe [Text]` and a generic `ToJSON`. When it is set, the client sends `"filter_properties": [...]` inside the JSON body, which Notion rejects. JS (`src/api-endpoints/data-sources.ts` line 617):

```typescript
export const queryDataSource = {
  method: "post",
  pathParams: ["data_source_id"],
  queryParams: ["filter_properties"],
  bodyParams: ["archived", "sorts", "filter", "start_cursor", "page_size", "in_trash", "result_type"],
  path: (p) => `data_sources/${p.data_source_id}/query`,
}
```

`filter_properties?: Array<string>` becomes one `filter_properties=<id>` pair per element in the URL (`src/Client.ts` appends each array value with `url.searchParams.append`). The JS SDK has no `databases/{id}/query` endpoint at all; Notion has deprecated it. The Haskell `queryDatabase` gets the same fix for consistency.

**11. Page position on create (`src/Notion/V1/Pages.hs`, `data CreatePage`, lines 144–157).** `position :: Maybe Position` reuses `Notion.V1.Blocks.Position` (`src/Notion/V1/Blocks.hs`), whose `Start` and `End` encode as `{"type":"start","start":{}}` and `{"type":"end","end":{}}`. That is the correct shape for appending block children, but not for creating a page. JS (`common.ts` lines 987–990; used by `createPage` in `pages.ts` line 444):

```typescript
export type PagePositionSchema =
  | { type: "after_block"; after_block: { id: IdRequest } }
  | { type: "page_start" }
  | { type: "page_end" }
```

**12. Webhooks (`src/Notion/V1/Webhooks.hs`).** `WebhookEvent`'s decoder does `accessibleBy <- o .: "accessible_by"` (line 286). JS (`src/api-endpoints/webhooks.ts` lines 39–54) marks the field optional ("Only present for public integrations"), so every event to an internal integration fails. `verifySignature` (lines 334–347) byte-compares the header against the computed `sha256=<lowercase hex>`, so uppercase hex fails. JS `src/webhooks.ts` lines 44–66:

```typescript
if (typeof signature !== "string") return false
if (!signature.startsWith("sha256=")) return false
const providedHex = signature.slice("sha256=".length).toLowerCase()
if (providedHex.length !== 64) return false
if (!/^[0-9a-f]+$/.test(providedHex)) return false
const computedHex = await computeHmacSha256Hex(verificationToken, body)
return timingSafeEqualHex(providedHex, computedHex)
```


## Plan of Work

The work has four milestones. Each one compiles, passes its own tests, and leaves the library strictly better. Do them in order: Milestone 1 creates the test module the later milestones add to.

**Breaking changes.** The implementer must list these under `### Breaking Changes` in `CHANGELOG.md`. Changes that stop existing code from compiling:

- `PersonUser.email` changes from `Text` to `Maybe Text`.
- `UniqueIdResult.number` changes from `Natural` to `Maybe Natural`.
- `MeetingNotesBlock` fields change:
  - `meetingTitle` becomes `Maybe (Vector RichText)`.
  - `meetingStatus` becomes `Maybe MeetingNotesStatus`.
  - `calendarEvent` becomes `Maybe MeetingCalendarEvent`.
  - `recording` becomes `Maybe MeetingRecording`.
  - The `children` field is replaced by `meetingChildren :: Maybe MeetingNotesChildren`.
- `CreatePage.position` changes from `Maybe Blocks.Position` to `Maybe PagePosition`.
- The exported Servant `API` types of `Notion.V1.DataSources`, `Notion.V1.Databases` and `Notion.V1` gain a `QueryParams "filter_properties" Text` segment on the query routes. This only matters to code that derives its own client from those types.

Changes that only add constructors, so exhaustive `case` expressions get an incomplete-pattern warning: `Color` (`DefaultBackground`, `UnknownColor`), `Parent` (`AgentParent`, `UnknownParent`), `Icon` (`UnknownIcon`), `MentionContent` (`UnknownMention`), `CodeLanguage` (18 languages plus `OtherLanguage`), `NumberFormat` (`OtherNumberFormat`), `FormulaResult` (`FormulaUnsupportedResult`, `UnknownFormulaResult`). The PVP counts these as breaking too.

Behavior changes that are not type changes:

- `CustomEmojiIcon` now encodes in the nested shape.
- `withChildren` leaves meeting-notes blocks unchanged.
- `verifySignature` accepts uppercase hex.
- A `WebhookEvent` without `accessible_by` decodes with an empty vector.
- `queryDataSource` and `queryDatabase` move `filterProperties` to the URL.

The `Methods` record is unchanged.


### Milestone 1: Tolerant common decoders and the test module

Scope: the shared types in `src/Notion/V1/Common.hs` and the mention parser in `src/Notion/V1/RichText.hs`, plus the scaffolding for `tasty/WireFormatTests.hs`. At the end, pages and blocks with `default_background` text, custom-emoji icons, agent parents or unknown mention kinds decode. Custom-emoji icons are sent in the shape Notion expects. Ten tests in the `WireFormat / Common and rich text` group pass.

First create the test module and wire it in. In `notion-client.cabal`, inside `test-suite tasty`, add `other-modules: WireFormatTests` directly after `main-is: Main.hs`. In `tasty/Main.hs`, add `import WireFormatTests qualified` to the imports. Then add `WireFormatTests.tests` to the list in the final `testGroup "Notion Client Tests"`, right after `fileUploadTests`. Create `tasty/WireFormatTests.hs` with this header; later milestones fill in the four lists:

```haskell
module WireFormatTests (tests) where

import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Char8 qualified as B8
import Data.ByteString.Lazy.Char8 qualified as L8
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import Notion.V1.Common (Color (..), Icon (..), Parent (..), UUID (..))
import Notion.V1.RichText (MentionContent (..), RichText (..))
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "WireFormat"
    [ testGroup "Common and rich text" commonTests,
      testGroup "Blocks, users and property values" blockUserPropertyTests,
      testGroup "Request encoding" requestEncodingTests,
      testGroup "Webhooks" webhookTests
    ]

-- | Decode a lazy ByteString literal or fail the test with aeson's message.
decodeOrFail :: (Aeson.FromJSON a) => L8.ByteString -> IO a
decodeOrFail bytes = either (assertFailure . ("decode failed: " <>)) pure (Aeson.eitherDecode bytes)
```

Add imports as later milestones need them. GHC's `-Wall` flags unused imports, so a warning after Milestone 1 about `B8` or `Vector` is expected until they are used; you can also add those imports only when needed.

Now `Color`. Replace the generic instances with a lookup table so an unknown string falls back instead of failing. Insert `DefaultBackground` before `GrayBackground` and add `UnknownColor Text` last. Keep `deriving stock (Eq, Show, Generic)`. Add `withText` to the `Data.Aeson` import, `fromMaybe` from `Data.Maybe`, and `swap` from `Data.Tuple`:

```haskell
colorNames :: [(Color, Text)]
colorNames =
  [ (Default, "default"), (Gray, "gray"), (Brown, "brown"), (Orange, "orange"),
    (Yellow, "yellow"), (Green, "green"), (Blue, "blue"), (Purple, "purple"),
    (Pink, "pink"), (Red, "red"), (DefaultBackground, "default_background"),
    (GrayBackground, "gray_background"), (BrownBackground, "brown_background"),
    (OrangeBackground, "orange_background"), (YellowBackground, "yellow_background"),
    (GreenBackground, "green_background"), (BlueBackground, "blue_background"),
    (PurpleBackground, "purple_background"), (PinkBackground, "pink_background"),
    (RedBackground, "red_background")
  ]

instance FromJSON Color where
  parseJSON = withText "Color" $ \t ->
    pure (fromMaybe (UnknownColor t) (lookup t (map swap colorNames)))

instance ToJSON Color where
  toJSON = \case
    UnknownColor t -> String t
    c -> String (fromMaybe "default" (lookup c colorNames))
```

`Parent`: add two constructors after `WorkspaceParent`:

```haskell
  | AgentParent {agentId :: UUID}
  | -- | A parent kind this library does not model yet; holds the raw JSON object.
    UnknownParent Value
```

In `parseByType`, add `"agent_id" -> fmap AgentParent . (.: "agent_id")` and replace the `other -> \_ -> fail ...` branch with `_ -> pure . UnknownParent . Object`. In `parseByKey`, add `AgentParent <$> o .: "agent_id"` before the workspace alternative and `pure (UnknownParent (Object o))` as the last alternative. In `ToJSON Parent`, add `toJSON (AgentParent aId) = object ["type" .= ("agent_id" :: Text), "agent_id" .= aId]` and `toJSON (UnknownParent v) = v`.

`Icon`: add a final constructor `UnknownIcon Value` (with a doc comment saying it holds the raw icon object). Change the `custom_emoji` decode branch and the fallback:

```haskell
        "custom_emoji" -> do
          mInner <- o .:? "custom_emoji"
          case mInner of
            Just inner -> CustomEmojiIcon <$> inner .: "id"
            -- Shape written by notion-client <= 0.7.0.2; still accepted when reading.
            Nothing -> CustomEmojiIcon <$> o .: "id"
        _ -> pure (UnknownIcon (Object o))
```

Change the encoder to `toJSON (CustomEmojiIcon eid) = object ["type" .= ("custom_emoji" :: Text), "custom_emoji" .= object ["id" .= eid]]`, and add `toJSON (UnknownIcon v) = v`. In `tasty/Main.hs`, update `testCustomEmojiIconRoundTrip`. It should assert that the encoded object has no top-level `id` key and that `KeyMap.lookup "custom_emoji" o` is `Just (Aeson.object ["id" Aeson..= ("emoji-abc-123" :: Text.Text)])`. Keep its round-trip assertion.

`MentionContent`: add `| UnknownMention Value` with a doc comment saying it holds the whole mention object and that typed `link_mention`/`custom_emoji` constructors come later. Rewrite the decoder head as `parseJSON v = case v of Object o -> ...` so the whole value is in scope. Replace `other -> fail ...` with `_ -> pure (UnknownMention v)`, and the inner `other2 -> fail ...` for unknown template-mention subtypes with `_ -> pure (UnknownMention v)`. Add `UnknownMention raw -> raw` to the encoder.

Milestone 1 tests (`commonTests :: [TestTree]`), each a `testCase`:

- "Color default_background decodes and round-trips": decode `"\"default_background\""` to `DefaultBackground`, and check that `Aeson.encode DefaultBackground` is `"\"default_background\""`.
- "Color unknown value falls back to UnknownColor": `"\"ultraviolet_background\""` decodes to `UnknownColor "ultraviolet_background"` and re-encodes to the same string.
- "RichText with default_background annotation decodes": a full rich-text fixture with `"color":"default_background"`.
- "Parent agent_id decodes to AgentParent": `{"type":"agent_id","agent_id":"aaaaaaaa-0000-4000-8000-000000000001"}`.
- "Parent unknown type falls back to UnknownParent": `{"type":"team_id","team_id":"x"}`.
- "Custom emoji icon decodes nested object": `{"type":"custom_emoji","custom_emoji":{"id":"bbbbbbbb-0000-4000-8000-000000000002","name":"sakura","url":"https://example.com/sakura.png"}}` gives `CustomEmojiIcon (UUID "bbbbbbbb-0000-4000-8000-000000000002")`.
- "Custom emoji icon encodes nested object": encoding yields `{"type":"custom_emoji","custom_emoji":{"id":"…"}}`.
- "Unknown icon type falls back to UnknownIcon": `{"type":"sticker","sticker":{}}`.
- "Unknown mention type falls back to UnknownMention": a rich-text item whose `mention` is `{"type":"future_mention","future_mention":{"href":"https://example.com","title":"Example"}}` decodes. Use a made-up type name, not `link_mention` or `custom_emoji`: EP-6 (`docs/plans/11-close-page-block-property-value-user-file-upload-and-webhook-field-gaps.md`) later adds typed constructors for those, and a fixture that uses them would then stop exercising the fallback. Its `content` is `MentionContentWrapper (UnknownMention _)`, and re-encoding the `MentionContent` yields the original mention object.
- "Unknown mention decodes directly as MentionContent": `{"type":"future_emoji","future_emoji":{"id":"…","name":"sakura","url":"…"}}` decoded directly as `MentionContent` yields `UnknownMention`.

A reusable rich-text fixture (substitute the color as needed):

```json
{"type":"text","text":{"content":"Hello","link":null},"annotations":{"bold":false,"italic":false,"strikethrough":false,"underline":false,"code":false,"color":"default_background"},"plain_text":"Hello","href":null}
```

CHANGELOG (Milestone 1): at the top of `CHANGELOG.md`, directly under `# Changelog for notion-client`, create `## Unreleased` with `### Breaking Changes` and `### Bug Fixes` subsections. If another plan has already created `## Unreleased`, reuse it. Under Bug Fixes, add entries for `default_background`, agent parents, nested custom-emoji icons (read and write) and unknown mention kinds. Under Breaking Changes, add the new constructors.

Acceptance: `cabal build all` succeeds, and `cabal test tasty --test-options='-p /WireFormat/'` reports 10 passing tests. The existing `CustomEmojiIcon round-trip` test in `tasty/Main.hs` also passes.


### Milestone 2: Blocks, users and property values

Scope: `src/Notion/V1/BlockContent.hs`, `src/Notion/V1/Users.hs`, `src/Notion/V1/Properties.hs` and `src/Notion/V1/PropertyValue.hs`. At the end, the following decode:

- code blocks in any language;
- real meeting-notes blocks and deprecated `transcription` blocks;
- people without an email, and bots owned by a user;
- data sources with unfamiliar number formats;
- unique IDs with a null number, and `unsupported` formula results.

Ten more tests pass.

`CodeLanguage`: add these constructors, keeping alphabetical placement for readability. Each is followed by its wire string, to be added to both the `FromJSON` and `ToJSON` case lists:

- `Abc` ("abc"), `Agda` ("agda"), `AsciiArt` ("ascii art"), `Assembly` ("assembly")
- `Bnf` ("bnf"), `Coq` ("coq"), `Dhall` ("dhall"), `Ebnf` ("ebnf")
- `Hcl` ("hcl"), `Idris` ("idris"), `LlvmIr` ("llvm ir"), `Mathematica` ("mathematica")
- `NotionFormula` ("notion formula"), `PureScript` ("purescript"), `Racket` ("racket")
- `Smalltalk` ("smalltalk"), `Solidity` ("solidity"), `Toml` ("toml")

Finally add `| OtherLanguage Text` last. Change the parser's last branch to `other -> pure (OtherLanguage other)`, and add `OtherLanguage t -> Aeson.String t` to the encoder.

Meeting notes: add these types above `BlockContent` and export them (with `(..)`) from the module header next to `CodeLanguage (..)`:

```haskell
-- | Processing state of a meeting-notes block.
data MeetingNotesStatus
  = TranscriptionNotStarted
  | TranscriptionPaused
  | TranscriptionInProgress
  | TranscriptionFailed
  | SummaryInProgress
  | NotesReady
  | UnknownMeetingNotesStatus Text
  deriving stock (Eq, Show, Generic)

instance FromJSON MeetingNotesStatus where
  parseJSON = Aeson.withText "MeetingNotesStatus" $ \case
    "transcription_not_started" -> pure TranscriptionNotStarted
    "transcription_paused" -> pure TranscriptionPaused
    "transcription_in_progress" -> pure TranscriptionInProgress
    "transcription_failed" -> pure TranscriptionFailed
    "summary_in_progress" -> pure SummaryInProgress
    "notes_ready" -> pure NotesReady
    other -> pure (UnknownMeetingNotesStatus other)

-- ToJSON is the inverse mapping; UnknownMeetingNotesStatus t -> Aeson.String t.

-- | IDs of the child blocks Notion creates under a meeting-notes block.
data MeetingNotesChildren = MeetingNotesChildren
  { summaryBlockId :: Maybe UUID,
    notesBlockId :: Maybe UUID,
    transcriptBlockId :: Maybe UUID
  }
  deriving stock (Eq, Show, Generic)
-- FromJSON/ToJSON: genericParseJSON aesonOptions / genericToJSON aesonOptions.

-- | Calendar event linked to a meeting; times are ISO 8601 strings as sent.
data MeetingCalendarEvent = MeetingCalendarEvent
  { calendarStartTime :: Text,
    calendarEndTime :: Text,
    calendarAttendees :: Maybe (Vector UUID)
  }
  deriving stock (Eq, Show, Generic)
-- Hand-written instances mapping to "start_time", "end_time", "attendees" (.:? for attendees).

-- | Recording window of a meeting; times are ISO 8601 strings as sent.
data MeetingRecording = MeetingRecording
  { recordingStartTime :: Maybe Text,
    recordingEndTime :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)
-- Hand-written instances mapping to "start_time", "end_time" (both .:?).
```

The field names are prefixed (`calendarStartTime`, not `startTime`) because `Notion.V1.Blocks` re-exports this whole module, and short names would collide in user code. Replace the constructor with:

```haskell
  | -- | Meeting notes block (read-only). Also decoded from the deprecated
    -- @transcription@ block type.
    MeetingNotesBlock
      { meetingTitle :: Maybe (Vector RichText),
        meetingStatus :: Maybe MeetingNotesStatus,
        calendarEvent :: Maybe MeetingCalendarEvent,
        recording :: Maybe MeetingRecording,
        meetingChildren :: Maybe MeetingNotesChildren
      }
```

In `parseBlockContent`, replace the `"meeting_notes"` branch with two branches, `"meeting_notes" -> parseMeetingNotes` and `"transcription" -> parseMeetingNotes`. Define `parseMeetingNotes` in the existing `where` block:

```haskell
    parseMeetingNotes = parseObj $ \o -> do
      meetingTitle <- o .:? "title"
      meetingStatus <- o .:? "status"
      calendarEvent <- o .:? "calendar_event"
      recording <- o .:? "recording"
      meetingChildren <- o .:? "children"
      pure MeetingNotesBlock {..}
```

In `blockContentFields`, emit each field only when it is `Just`, under the keys `title`, `status`, `calendar_event`, `recording` and `children`. Delete the `MeetingNotesBlock {} -> block {children = cs}` line from `withChildren`; the constructor no longer has a `children` field, and GHC would reject the record update. `BlockObject` in `src/Notion/V1/Blocks.hs` keeps the original `type` string in `type_` and re-encodes under that key, so a `transcription` block round-trips under its own name. In `tasty/Main.hs`, update `testBlockContentMeetingNotes`. Its fixture must use `"title":[<rich-text item with plain_text "Weekly Sync">]`, and it must assert `fmap (Vector.map plainText) meetingTitle == Just (Vector.singleton "Weekly Sync")`. Its old `"status":"scheduled"` now decodes as `UnknownMeetingNotesStatus "scheduled"`, which is fine.

Users: change `PersonUser` to `newtype PersonUser = PersonUser { email :: Maybe Text }` and keep its generic decoder (a missing `Maybe` field decodes as `Nothing`). Change `UserOwner` and export it as `UserOwner (..)` from the module header:

```haskell
data UserOwner
  = UserOwner {type_ :: Text, user :: UserID}
  | WorkspaceOwner {type_ :: Text, workspace :: Bool}
  | -- | Owner kind not modelled yet; holds the raw owner object.
    UnknownOwner {type_ :: Text, ownerValue :: Value}
  deriving stock (Generic, Show)

instance FromJSON UserOwner where
  parseJSON = \case
    Object o -> do
      ownerType <- o .: "type"
      case ownerType of
        "user" -> do
          userObj <- o .: "user"
          UserOwner ownerType <$> userObj .: "id"
        "workspace" -> WorkspaceOwner ownerType <$> o .: "workspace"
        _ -> pure (UnknownOwner ownerType (Object o))
    _ -> fail "Expected object for UserOwner"
```

`userObj` has type `Aeson.Object`; add a type annotation (`userObj :: Object <- o .: "user"`) or import `Data.Aeson (Object)` if inference needs help.

`NumberFormat`: add `| OtherNumberFormat Text` last. Change the parser's last branch to `other -> pure (OtherNumberFormat other)`, and add `toJSON (OtherNumberFormat t) = Aeson.String t`.

`UniqueIdResult`: change `number :: Natural` to `number :: Maybe Natural`; the generic instances need no other change. `FormulaResult`: add `| FormulaUnsupportedResult | UnknownFormulaResult Value`. In the decoder, add `"unsupported" -> pure FormulaUnsupportedResult` and replace the `other -> fail` branch with `_ -> pure (UnknownFormulaResult (Object o))`. In the encoder, add `FormulaUnsupportedResult -> Aeson.object ["type" .= ("unsupported" :: Text), "unsupported" .= Aeson.object []]` and `UnknownFormulaResult v -> v`. Fix any pattern-match warnings in `tasty/Main.hs` or `notion-client-example/`; at drafting time, none matched these constructors exhaustively.

Milestone 2 tests (`blockUserPropertyTests`):

- "Code block with toml language decodes": `parseBlockContent` via `Aeson.eitherDecode` of `{"type":"code","code":{"rich_text":[],"caption":[],"language":"toml"}}` as `BlockContent` gives `CodeBlock {language = Toml}`. Check how `tasty/Main.hs` decodes a standalone `BlockContent` (for example `testBlockContentMeetingNotes`) and use the same form.
- "All 18 new code languages round-trip": `Aeson.fromJSON (Aeson.toJSON l) == Aeson.Success l` for each new constructor.
- "Unknown code language falls back to OtherLanguage": `"brainfuck"` gives `OtherLanguage "brainfuck"`, which re-encodes to `"brainfuck"`.
- "Meeting notes block object decodes": decode the full `BlockObject` fixture below and assert the title's plain text, `meetingStatus == Just NotesReady`, `summaryBlockId` and `calendarAttendees`.
- "Deprecated transcription block decodes as meeting notes": the same fixture with `"type":"transcription"` and the payload under `"transcription"`. `content` is a `MeetingNotesBlock`, and `type_ == "transcription"`.
- "Person user without email decodes": `{"object":"user","id":"…","name":"Tanaka Hanako","avatar_url":null,"type":"person","person":{}}` gives `person == Just (PersonUser Nothing)`.
- "Bot user owned by a user object decodes": `{"object":"user","id":"…","name":"Sakura Bot","avatar_url":null,"type":"bot","bot":{"owner":{"type":"user","user":{"object":"user","id":"cccccccc-0000-4000-8000-000000000003","name":"Sato Kenji","avatar_url":null,"type":"person","person":{"email":"sato.kenji@example.com"}}},"workspace_name":"Sakura Studio","workspace_id":"ws-1","workspace_limits":{"max_file_upload_size_in_bytes":5368709120}}}` decodes, and the owner is `UserOwner "user" (UUID "cccccccc-0000-4000-8000-000000000003")`.
- "Unknown number format falls back to OtherNumberFormat": `"kenyan_shilling"`.
- "Unique ID with null number decodes": decode `PropertyValue` `{"id":"a%3Db","type":"unique_id","unique_id":{"prefix":"TASK","number":null}}`.
- "Formula unsupported result decodes": decode `PropertyValue` `{"id":"f%3Dx","type":"formula","formula":{"type":"unsupported","unsupported":{}}}`.

The meeting-notes `BlockObject` fixture:

```json
{
  "object": "block",
  "id": "dddddddd-0000-4000-8000-000000000004",
  "parent": {"type": "page_id", "page_id": "eeeeeeee-0000-4000-8000-000000000005"},
  "created_time": "2026-09-01T10:00:00.000Z",
  "last_edited_time": "2026-09-01T11:00:00.000Z",
  "created_by": {"object": "user", "id": "cccccccc-0000-4000-8000-000000000003"},
  "last_edited_by": {"object": "user", "id": "cccccccc-0000-4000-8000-000000000003"},
  "has_children": true,
  "in_trash": false,
  "archived": false,
  "type": "meeting_notes",
  "meeting_notes": {
    "title": [{"type":"text","text":{"content":"Weekly Sync","link":null},"annotations":{"bold":false,"italic":false,"strikethrough":false,"underline":false,"code":false,"color":"default"},"plain_text":"Weekly Sync","href":null}],
    "status": "notes_ready",
    "children": {
      "summary_block_id": "11111111-0000-4000-8000-000000000011",
      "notes_block_id": "22222222-0000-4000-8000-000000000022",
      "transcript_block_id": "33333333-0000-4000-8000-000000000033"
    },
    "calendar_event": {"start_time": "2026-09-01T10:00:00.000Z", "end_time": "2026-09-01T10:30:00.000Z", "attendees": ["cccccccc-0000-4000-8000-000000000003"]},
    "recording": {"start_time": "2026-09-01T10:01:00.000Z", "end_time": "2026-09-01T10:29:00.000Z"}
  }
}
```

CHANGELOG (Milestone 2): add Bug Fixes entries for code languages, meeting-notes and `transcription` blocks, users without an email, bots owned by users, open number formats, null unique-ID numbers and unsupported formulas. Under Breaking Changes, add the field-type changes (`PersonUser.email`, `UniqueIdResult.number`, `MeetingNotesBlock`) and the new constructors. Add `### New Features` entries for the exported `UserOwner (..)` and the new meeting-notes types.

Acceptance: `cabal build all` succeeds, and `cabal test tasty --test-options='-p /WireFormat/'` reports 20 passing tests. The updated `meeting_notes` test in `tasty/Main.hs` passes.


### Milestone 3: Request encoding

Scope: `src/Notion/V1/DataSources.hs`, `src/Notion/V1/Databases.hs`, `src/Notion/V1.hs` and `src/Notion/V1/Pages.hs`. At the end, `filterProperties` travels as repeated `filter_properties=` query parameters, and `CreatePage` sends `page_start`/`page_end`/`after_block` positions. Four more tests pass. They capture the real HTTP request without opening a network connection.

In `src/Notion/V1/DataSources.hs`, add `import Servant.API (QueryParams)` and `import Data.Aeson.KeyMap qualified as KeyMap`. Change the query route to:

```haskell
           :<|> Capture "data_source_id" DataSourceID
           :> "query"
           :> QueryParams "filter_properties" Text
           :> ReqBody '[JSON] QueryDataSource
           :> Post '[JSON] (ListOf PageObject)
```

Then make the encoder drop the key so the body never carries it:

```haskell
-- | @filter_properties@ is a query parameter, not a body field; 'Notion.V1.makeMethods'
-- moves 'filterProperties' into the URL.
instance ToJSON QueryDataSource where
  toJSON q = case genericToJSON aesonOptions q of
    Object o -> Object (KeyMap.delete "filter_properties" o)
    other -> other
```

Make the identical change to `QueryDatabase` and the `"query"` route in `src/Notion/V1/Databases.hs`. In `src/Notion/V1.hs`, rename the bound client functions in the big pattern of `makeMethods`: `queryDatabase` becomes `queryDatabase_` (line 92) and `queryDataSource` becomes `queryDataSource_` (line 97). Add wrappers in the `where` block next to `retrievePage` (import `Data.Maybe (fromMaybe)`):

```haskell
    -- filter_properties is sent as repeated query parameters (see DataSources.API)
    queryDataSource dsId q@DataSources.QueryDataSource {filterProperties = props} =
      queryDataSource_ dsId (fromMaybe [] props) q
    queryDatabase dbId q@Databases.QueryDatabase {filterProperties = props} =
      queryDatabase_ dbId (fromMaybe [] props) q
```

The field types in `Methods` stay exactly as they are, so `notion-client-effectful` is unaffected. If GHC reports the `filterProperties` field as ambiguous, use a `case` on the constructor instead; do not change the `Methods` signature. If a future change does alter those signatures, the effectful package's `Notion` GADT constructor, smart constructor and interpreter case must change in the same commit. Servant renders `QueryParams` as one `key=value` pair per list element, the same way `retrievePageFiltered` already works.

In `src/Notion/V1/Pages.hs`, add and export `PagePosition (..)`:

```haskell
-- | Where to place a new page among its parent's content (@POST /v1/pages@).
-- Distinct from 'Notion.V1.Blocks.Position', which uses @start@/@end@.
data PagePosition
  = PageAfterBlock UUID
  | PageStart
  | PageEnd
  deriving stock (Eq, Generic, Show)

instance ToJSON PagePosition where
  toJSON (PageAfterBlock blockId) =
    Aeson.object ["type" .= ("after_block" :: Text), "after_block" .= Aeson.object ["id" .= blockId]]
  toJSON PageStart = Aeson.object ["type" .= ("page_start" :: Text)]
  toJSON PageEnd = Aeson.object ["type" .= ("page_end" :: Text)]
```

Change `CreatePage.position` to `Maybe PagePosition`. `MovePage` keeps using `Blocks.Position` (see Decision Log).

Milestone 3 tests (`requestEncodingTests`). For the capturing tests, override the `makeClientRequest` field of servant-client's `ClientEnv`. servant-client 0.20.3.0 calls that field (type `BaseUrl -> Request -> IO Client.Request`) to build the http-client request, before any network I/O. Record the built request and throw a private exception, so the call never reaches the network:

```haskell
import Control.Exception (Exception, throwIO, try)
import Data.IORef (newIORef, readIORef, writeIORef)
import Network.HTTP.Client qualified as HTTP
import Notion.V1 (Methods (..), makeMethods)
import Notion.V1.DataSources qualified as DataSources
import Notion.V1.Databases qualified as Databases
import Servant.Client qualified as Client

data RequestCaptured = RequestCaptured deriving stock (Show)

instance Exception RequestCaptured

captureRequest :: (Methods -> IO a) -> IO HTTP.Request
captureRequest call = do
  ref <- newIORef Nothing
  manager <- HTTP.newManager HTTP.defaultManagerSettings
  let env0 = Client.mkClientEnv manager (Client.BaseUrl Client.Https "api.notion.com" 443 "/v1")
      env =
        env0
          { Client.makeClientRequest = \burl req -> do
              built <- Client.defaultMakeClientRequest burl req
              writeIORef ref (Just built)
              throwIO RequestCaptured
          }
  _ <- try @RequestCaptured (call (makeMethods env "secret_test_token"))
  readIORef ref >>= maybe (assertFailure "no request was built") pure
```

The tests:

- "queryDataSource sends filter_properties as repeated query parameters": call `queryDataSource` with `DataSources.QueryDataSource {filter = Nothing, sorts = Nothing, startCursor = Nothing, pageSize = Just 5, inTrash = Nothing, filterProperties = Just ["title", "Xy12"]}`. Assert that `"filter_properties=title&filter_properties=Xy12"` is infix of `HTTP.queryString req` (`B8.isInfixOf`). Assert that `HTTP.path req` ends with `"/query"`. Assert that the body, extracted by matching `HTTP.RequestBodyLBS lbs`, decodes to an object without a `filter_properties` key and with `"page_size": 5`.
- "queryDatabase sends filter_properties as repeated query parameters": the same for `Databases.QueryDatabase`.
- "QueryDataSource JSON omits filter_properties": pure `Aeson.toJSON` check.
- "CreatePage position encodes page_start, page_end and after_block": `Aeson.toJSON PageStart == {"type":"page_start"}`, the same for `PageEnd`, and `PageAfterBlock (UUID "b1")` gives `{"type":"after_block","after_block":{"id":"b1"}}`.

`try @RequestCaptured` uses the `TypeApplications` extension, which is part of GHC2024. The test suite already depends on `http-client`, `servant-client` and `bytestring`, so `notion-client.cabal` needs no dependency change.

CHANGELOG (Milestone 3): add Bug Fixes entries for the `filter_properties` routing and the page positions. Under Breaking Changes, add `CreatePage.position`'s new type and the changed Servant `API` types. Under New Features, add `PagePosition`.

Acceptance: `cabal build all` succeeds for both `notion-client` and `notion-client-effectful` with no edits to the latter. `cabal test tasty --test-options='-p /WireFormat/'` reports 24 passing tests.


### Milestone 4: Webhooks

Scope: `src/Notion/V1/Webhooks.hs`. At the end, events delivered to internal integrations decode, and signature verification matches the JS SDK's rules. Three more tests pass, and the full suite is green.

In the `WebhookEvent` decoder, replace `accessibleBy <- o .: "accessible_by"` with `accessibleBy <- o .:? "accessible_by" .!= mempty` (import `(.!=)` from `Data.Aeson`). The field type stays `Vector AccessibleBy`. Replace `verifySignature`'s body (keep its type and Haddock, and add a sentence about the new rules). Add `import Data.Text qualified as T` and `import Data.Char (isHexDigit)`:

```haskell
verifySignature verificationToken body headerSignature =
  case T.stripPrefix "sha256=" headerSignature of
    Nothing -> False
    Just provided ->
      let providedHex = T.toLower provided
          computedHex = Base16.encode (SHA256.hmac (Text.encodeUtf8 verificationToken) body)
       in T.length providedHex == 64
            && T.all isHexDigit providedHex
            && constantTimeCompare (Text.encodeUtf8 providedHex) computedHex
```

`Base16.encode` from `base16-bytestring` emits lowercase hex, which is why `computeSignature` produces lowercase. `computeSignature` itself does not change.

Milestone 4 tests (`webhookTests`):

- "WebhookEvent without accessible_by decodes". Fixture:

  ```json
  {"id":"ffffffff-0000-4000-8000-000000000006","timestamp":"2026-09-01T12:00:00.000Z","workspace_id":"ws-1","workspace_name":"Sakura Studio","subscription_id":"sub-1","integration_id":"int-1","type":"page.created","authors":[{"id":"cccccccc-0000-4000-8000-000000000003","type":"person"}],"attempt_number":1,"api_version":"2026-03-11","entity":{"id":"eeeeeeee-0000-4000-8000-000000000005","type":"page"},"data":{"parent":{"id":"space-1","type":"space"}}}
  ```

  Assert `Vector.null accessibleBy`.
- "verifySignature accepts uppercase hex": with token `"tok"` and body `B8.pack "{\"a\":1}"`, let `sig = computeSignature "tok" body`. Assert that `verifySignature "tok" body ("sha256=" <> Text.toUpper (Text.drop 7 sig))` is `True`.
- "verifySignature rejects malformed signatures": `False` for the bare hex without the prefix, for `"sha256=abc"` (wrong length), and for `"sha256=" <> Text.replicate 64 "z"` (non-hex).

Finish the CHANGELOG with Bug Fixes entries for the optional `accessible_by` and case-insensitive signature verification. Then tick the two EP-1 rows in the Progress section of `docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md` and set EP-1's registry status to Complete.

Acceptance: `cabal test tasty --test-options='-p /WireFormat/'` reports 27 passing tests, and the full `cabal test` passes with integration groups skipped.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`.

Before starting, confirm the tree builds and the existing tests pass, so later failures are clearly yours:

```bash
cabal build all
cabal test tasty
```

The test output ends with a line of the form `All NNN tests passed`. The skipped integration groups show as, for example, `Integration Tests (skipped — no NOTION_TOKEN)`.

After each milestone's edits:

```bash
cabal build all
cabal test tasty --test-options='-p /WireFormat/'
```

Expected transcript after Milestone 1 (timings vary):

```text
Notion Client Tests
  WireFormat
    Common and rich text
      Color default_background decodes and round-trips:   OK
      Color unknown value falls back to UnknownColor:     OK
      ...
      Unknown mention decodes directly as MentionContent: OK

All 10 tests passed (0.01s)
```

After Milestones 2, 3 and 4, the final line reads `All 20 tests passed`, `All 24 tests passed` and `All 27 tests passed`. At the end of Milestone 4, also run the full suite:

```bash
cabal test tasty
```

A failing decode test prints aeson's message, for example `decode failed: Error in $.meeting_notes.title: parsing Text failed, expected String, but encountered Array`. That is exactly the pre-fix behavior, and it is a useful check that the fixture exercises the bug. You can confirm this by writing the test before the fix.

Commit after each milestone, using Conventional Commits with both trailers. For example:

```text
fix(common): decode default_background, agent parents and nested custom emoji icons

Add tolerant fallbacks for Color, Parent, Icon and MentionContent so
unknown values no longer fail whole responses.

MasterPlan: docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md
ExecPlan: docs/plans/6-fix-wire-format-decoding-and-encoding-bugs-found-against-the-official-sdk.md
```

Suggested subjects for the other milestones: `fix(blocks): decode all code languages, meeting notes and user owners`, `fix(query): send filter_properties as query parameters and use page positions`, and `fix(webhooks): make accessible_by optional and harden signature verification`. If the `treefmt` pre-commit hook reformats files, run `git add` on them and commit again.


## Validation and Acceptance

The plan is accepted when all of the following hold.

`cabal build all` completes without errors for `notion-client`, `notion-client-effectful` and `notion-client-example`.

`cabal test tasty --test-options='-p /WireFormat/'` prints `All 27 tests passed`. Each named test proves one observable behavior. JSON copied from the SDK's types (a `default_background` span, an `agent_id` parent, a nested custom-emoji icon, an unknown mention type, a `toml` code block, a real meeting-notes block, a person with no email, a user-owned bot, a null unique-ID number, an `unsupported` formula, a webhook without `accessible_by`) now decodes instead of failing. The captured HTTP request for `queryDataSource` has `filter_properties=title&filter_properties=Xy12` in its query string and no `filter_properties` in its body. `PageStart` encodes as `{"type":"page_start"}`. An uppercase-hex webhook signature verifies.

`cabal test tasty` (the full suite) prints `All NNN tests passed`, including the updated `CustomEmojiIcon round-trip` and `meeting_notes` tests in `tasty/Main.hs`.

Optional live check, when `NOTION_TOKEN` is set and you know a data source ID, from `cabal repl notion-client`:

```haskell
:set -XOverloadedStrings
import Notion.V1
import Notion.V1.Common (UUID (..))
import qualified Notion.V1.DataSources as DS
import qualified Data.Text as T
import System.Environment (getEnv)
token <- T.pack <$> getEnv "NOTION_TOKEN"
env <- getClientEnv "https://api.notion.com/v1"
let m = makeMethods env token
r <- queryDataSource m (UUID "<data-source-id>") DS.QueryDataSource {filter = Nothing, sorts = Nothing, startCursor = Nothing, pageSize = Just 3, inTrash = Nothing, filterProperties = Just ["title"]}
```

Before the fix, Notion responds with HTTP 400 (a `validation_error` about the body), which the client throws as a `NotionError`. After the fix, `r` is a `ListOf PageObject`, and each page's `properties` map contains only the title property. With the same setup, `retrieveMyUser m` for a public integration owned by a user returns a `UserObject` instead of throwing a parse error.


## Idempotence and Recovery

Every step is an ordinary source edit followed by a build and test run. Repeating a step does no harm. If a milestone goes wrong, `git checkout -- <file>` (or `git stash`) restores the files touched since the last milestone commit, and the previous milestone's commit is a known-good point. No step touches external state. The optional live check only reads data.

When creating `## Unreleased` in `CHANGELOG.md`, check first whether another child plan has already added it. If so, append to its subsections rather than creating a second heading. If a rebase conflicts in `src/Notion/V1.hs` with EP-2 (`docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md`, which rewrites `makeMethods`'s `run` function and adds a configurable constructor), keep EP-2's structure. Then reapply only three things: the `queryDatabase_`/`queryDataSource_` renames in the client pattern, and the two wrapper equations.


## Interfaces and Dependencies

No new package dependencies. The library already depends on `aeson`, `servant`, `servant-client` (0.20.x), `text`, `vector`, `base16-bytestring` and `cryptohash-sha256`. The test suite already depends on `aeson`, `bytestring`, `http-client`, `servant-client`, `tasty`, `tasty-hunit`, `text` and `vector`.

At the end of Milestone 1, `Notion.V1.Common` exports:

```haskell
data Color = Default | Gray | Brown | Orange | Yellow | Green | Blue | Purple | Pink | Red
  | DefaultBackground | GrayBackground | BrownBackground | OrangeBackground | YellowBackground
  | GreenBackground | BlueBackground | PurpleBackground | PinkBackground | RedBackground
  | UnknownColor Text
data Parent = DatabaseParent {databaseId :: UUID}
  | DataSourceParent {dataSourceId :: UUID, parentDatabaseId :: Maybe UUID}
  | PageParent {pageId :: UUID} | BlockParent {blockId :: UUID} | WorkspaceParent {workspace :: Bool}
  | AgentParent {agentId :: UUID} | UnknownParent Value
data Icon = EmojiIcon {emoji :: Text} | FileIcon {file :: File} | ExternalIcon {external :: ExternalFile}
  | NativeIcon {iconName :: Text, iconColor :: Maybe Text} | CustomEmojiIcon {customEmojiId :: UUID}
  | FileUploadIcon {fileUploadId :: UUID} | UnknownIcon Value
```

`Notion.V1.RichText.MentionContent` gains `UnknownMention Value`.

At the end of Milestone 2, `Notion.V1.BlockContent` (re-exported by `Notion.V1.Blocks`) exports `CodeLanguage (..)` with the 18 new constructors and `OtherLanguage Text`. It also exports `MeetingNotesStatus (..)`, `MeetingNotesChildren (..)`, `MeetingCalendarEvent (..)` and `MeetingRecording (..)`, and the `MeetingNotesBlock` constructor has the shape shown in Milestone 2. `Notion.V1.Users` exports `PersonUser (..)` with `email :: Maybe Text` and `UserOwner (..)` with `UnknownOwner`. `Notion.V1.Properties.NumberFormat` gains `OtherNumberFormat Text`. In `Notion.V1.PropertyValue`, `UniqueIdResult.number :: Maybe Natural`, and `FormulaResult` gains `FormulaUnsupportedResult` and `UnknownFormulaResult Value`. EP-3 (`docs/plans/8-add-comment-mutation-async-task-and-meeting-notes-endpoints.md`) should reuse the meeting-notes types for its create and query responses rather than define its own.

At the end of Milestone 3, `Notion.V1.Pages` exports `PagePosition (..)`, and `CreatePage.position :: Maybe PagePosition`. The `Methods` fields keep their current types exactly:

```haskell
queryDatabase :: DatabaseID -> QueryDatabase -> IO (ListOf PageObject)
queryDataSource :: DataSourceID -> DataSources.QueryDataSource -> IO (ListOf PageObject)
```

The Servant routes become `Capture "data_source_id" DataSourceID :> "query" :> QueryParams "filter_properties" Text :> ReqBody '[JSON] QueryDataSource :> Post '[JSON] (ListOf PageObject)`, and the same shape with `database_id`/`QueryDatabase`. EP-5 (`docs/plans/10-type-data-source-database-and-search-results-and-close-query-and-filter-gaps.md`) builds on this route when it adds `result_type` and the page-or-data-source result union.

At the end of Milestone 4, `Notion.V1.Webhooks` keeps `verifySignature :: Text -> ByteString -> Text -> Bool` and `computeSignature :: Text -> ByteString -> Text` with unchanged types. `WebhookEvent.accessibleBy :: Vector AccessibleBy` is empty when the field is absent.
