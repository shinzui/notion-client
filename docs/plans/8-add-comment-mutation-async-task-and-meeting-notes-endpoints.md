---
id: 8
slug: add-comment-mutation-async-task-and-meeting-notes-endpoints
title: "Add Comment Mutation, Async Task, and Meeting Notes Endpoints"
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
      at: 2026-09-15T13:53:35Z
      mode: "implement"
      note: "Implementing milestones 1-4"
---

# Add Comment Mutation, Async Task, and Meeting Notes Endpoints

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.

This plan is child EP-3 of `docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md`.


## Purpose / Big Picture

The Haskell `notion-client` library can create and list comments, create pages, and edit page markdown, but it cannot do four things that Notion's official TypeScript client (`@notionhq/client`) can do on the published REST API. After this plan is implemented, a Haskell user can:

1. Retrieve, edit (with rich text or with Markdown) and delete a single comment, and create comments using Markdown, replies to an existing discussion without naming a parent, file-upload attachments, and a chosen display name. The request shapes will be exactly what Notion accepts.
2. Retrieve an *async task* (a long-running server-side job that Notion hands back instead of an immediate result) and wait for it to finish with a polling helper that honors the server's `poll_after_seconds` hint.
3. Ask Notion to run markdown page creation and markdown page updates in the background (`allow_async`), and receive either the finished page or an async task, in a type that forces the caller to handle both.
4. Create a meeting note from an uploaded audio or video file (or from an existing media block) and query meeting notes with a typed filter language (title, dates, people), sort and limit.

You can see it working in three ways: the new unit tests in `cabal test` decode and encode JSON copied from the official client's type definitions; the existing live comment test (when `NOTION_TOKEN` and `NOTION_TEST_PAGE_ID` are set) now also retrieves, edits and deletes a comment; and a short GHCi session queries your workspace's meeting notes.


## Progress

- [x] (2026-09-15) Milestone 1: Add `CommentResponse`, `CommentContent`, `CommentTarget`, request-only attachment and display-name types to `src/Notion/V1/Comments.hs`.
- [x] (2026-09-15) Milestone 1: Restructure `CreateComment`; add `mkCreateComment` and `mkReplyComment`.
- [x] (2026-09-15) Milestone 1: Add retrieve/update/delete comment routes, `Methods` fields and effectful constructors; change `createComment` to return `CommentResponse`.
- [x] (2026-09-15) Milestone 1: Update existing call sites (`tasty/Main.hs`, `notion-client-example/DatabaseDemo.hs`, `notion-client-example/PageDemo.hs`).
- [x] (2026-09-15) Milestone 1: Add `tasty/CommentTests.hs`, register it, extend live `testCommentLifecycle`; `cabal build all` and `cabal test` pass.
- [x] (2026-09-15) Milestone 2: Create `src/Notion/V1/AsyncTasks.hs` (`AsyncTask`, status union, `AsyncOr`, `AllowAsync`, `waitForAsyncTask`) and expose it in `notion-client.cabal`.
- [x] (2026-09-15) Milestone 2: Add `retrieveAsyncTask`, `createPageAsync`, `updatePageMarkdownAsync` routes, `Methods` fields and effectful constructors.
- [x] (2026-09-15) Milestone 2: Add `tasty/AsyncTaskTests.hs` (decoding, `AsyncOr`, `AllowAsync` encoding, polling loop); tests pass.
- [x] (2026-09-15) Milestone 3: Create `src/Notion/V1/MeetingNotes.hs` with `MeetingNotesContent`, `MeetingNoteBlock`, `CreateMeetingNote`, `CreateMeetingNoteResponse` and the create route.
- [x] (2026-09-15) Milestone 3: Add `createMeetingNote` to `Methods`, the top-level `API`, and the effectful package; add create tests to `tasty/MeetingNotesTests.hs`.
- [x] (2026-09-15) Milestone 4: Add the meeting-notes filter/sort DSL, `QueryMeetingNotes`, `QueryMeetingNotesResponse` and the query route.
- [x] (2026-09-15) Milestone 4: Add `queryMeetingNotes` to `Methods` and the effectful package; add query tests; tests pass.
- [ ] Final: CHANGELOG `## Unreleased` entries written; live checks run (or recorded as skipped); Outcomes & Retrospective filled.


## Surprises & Discoveries

- EP-1 and EP-2 had both landed before this plan started (2026-09-15). `APIErrorCode` exists in `src/Notion/V1/Error.hs`, and the four meeting-notes payload types exist in `src/Notion/V1/BlockContent.hs`, so no fallback paths were needed. `makeMethods` is now a wrapper over `makeMethodsWithEnv`, whose `where` block holds the pattern binding this plan extends.
- EP-2's `tasty/FakeNotion.hs` records request paths *without* the base URL prefix: a call to `GET /v1/comments/{id}` is recorded as `/comments/{id}`. Evidence from the first run of the route test: `but got: [("GET","/comments/2b0c5f7e-...")...]`.
- **Notion answers accepted background work with HTTP 202, and servant-client's `Post '[JSON]`/`Patch '[JSON]` verbs accept only status 200.** The first live `createPageAsync` call threw `Request to Notion API failed with status: 202`. servant-client-core's `HasClient (Verb method status ...)` instance calls `runRequestAcceptStatus (Just [status])`, so any other 2xx becomes a `FailureResponse`. `FakeNotion`-based tests could not catch this, because its middleware replaces the status-checking request function. The fix is the `AsyncVerb` route type (a `UVerb` accepting 200 and 202); see the Decision Log.
- Live async behaviour (2026-09-15): `createPageAsync` with `markdown` returned 202 with a task whose `operation` was `{surface: "rest", name: "POST /v1/pages"}`; polling reached `AsyncTaskSucceeded` and `result` was a full page object (`object: "page"`, `id`, `parent`, `properties`, `url`, ...). `updatePageMarkdownAsync` also returned 202, with operation name `"PATCH /v1/pages/:page_id/markdown"`, and reached a terminal state. `createComment` returned a full comment (`FullComment`).
- The test workspace's plan does not include AI meeting notes: every meeting-notes query returned HTTP 400 `validation_error` with "This endpoint requires a plan with AI meeting notes enabled". Notion validates the request body *before* this plan check, so a request that fails with this message has a valid body, and a malformed body fails with a schema message instead. That made it possible to validate the filter encoder live without results (2026-09-15).
- **The relative date strings are constrained, and the plan's `mnCreatedWithinPast` guess (`"today"` in a range condition) was rejected.** Live probes established the grammar. Point conditions (`date_is`, `date_is_before`, ...) with `type: "relative"` accept `today`, `tomorrow`, `yesterday`, `one_week_ago`, `one_week_from_now`, `one_month_ago` and `one_month_from_now`. Range conditions (`date_is_within`, `date_is_relative_to`) with `type: "relative"` accept `the_past_week`, `the_past_month`, `the_past_year`, `the_next_week`, `the_next_month`, `the_next_year` and `this_week`, or `custom`/`surrounding`, which require `unit` and `count`. With `type: "exact"`, a range takes a `daterange` object. Evidence: `body.filter.filters[0].filter.value.value should be "the_next_month", ..., or "this_week", instead was "today"` and `... value.count should be defined, instead was undefined`. `mnCreatedWithinPast`, `mnAttendeesInclude`, `mnCreatedOnOrAfter`, a two-user `MNPersonDoesNotContain`, and a nested `datetime` spec with `start_time` and `time_zone` all passed validation after the fix.
- The live `Page E2E` comment lifecycle (token present on 2026-09-15) passed with the new retrieve, Markdown update and delete steps, so the routes and the `{markdown}` PATCH body are accepted by Notion.


## Decision Log

- Decision: Model "full or partial comment" responses as a sum type `CommentResponse = FullComment CommentObject | PartialComment CommentID`, and change `createComment` to return it too.
  Rationale: The JS SDK types (`src/api-endpoints/comments.ts`, `CreateCommentResponse`, `GetCommentResponse`, `UpdateCommentResponse`, `DeleteCommentResponse`) all declare `PartialCommentObjectResponse | CommentObjectResponse`. A partial response (`{object, id}`) would make today's `CommentObject` decoder fail because it requires `parent`, `created_time` and more. A sum type keeps `CommentObject` intact for `listComments` (whose JS type returns only full objects) while making the partial case impossible to ignore. A Maybe-heavy `CommentObject` was rejected because it would weaken the list endpoint's type for everyone.
  Date: 2026-09-14

- Decision: Use separate request-only types (`CommentAttachmentRequest`, `CommentDisplayNameRequest`) for `CreateComment`, and leave the read-side `CommentAttachment` and `CommentDisplayName` types and instances unchanged.
  Rationale: `docs/plans/3-fix-comment-attachment-parsing.md` deliberately made those two types tolerant of the read shape (`category` + `file`, `resolved_name`). The request shapes (`{file_upload_id, type: "file_upload"}` and `{type: "integration"} | {type: "user"} | {type: "custom", custom: {name}}`) share almost nothing with the read shapes, so reusing one type for both directions encodes invalid requests. Separate types cannot regress read-side decoding.
  Date: 2026-09-14

- Decision: Replace `CreateComment`'s `parent`/`discussionId`/`richText` fields with `target :: CommentTarget` (parent or discussion) and `content :: CommentContent` (rich text or Markdown). This is a breaking change.
  Rationale: The JS body type is a four-way union: (parent or discussion_id) × (rich_text or markdown). Sending both `parent` and `discussion_id`, which the current record allows and `notion-client-example/DatabaseDemo.hs` does, is outside the accepted shape. Two small sum types make only valid combinations constructible. Smart constructors `mkCreateComment` and `mkReplyComment` keep call sites short.
  Date: 2026-09-14

- Decision: Expose `allow_async` as two new `Methods` fields, `createPageAsync :: CreatePage -> IO (AsyncOr PageObject)` and `updatePageMarkdownAsync :: PageID -> UpdatePageMarkdown -> IO (AsyncOr PageMarkdown)`, which always send `"allow_async": true`, instead of adding an `allowAsync` field to the request records.
  Rationale: The response type depends on the flag. With a field, `createPage` would have to return the union even for callers who never opt in, or would crash when they do. Separate methods keep `createPage` and `updatePageMarkdown` unchanged (no breaking change) and give the async variants an honest return type. The flag is injected by a `newtype AllowAsync a` whose `ToJSON` adds the key, so `UpdatePageMarkdown` (a sum type with no room for a top-level field) needs no restructuring. Per the JS field comments in `src/api-endpoints/pages.ts` (lines 433–435 and 761–764), only these two endpoints return async tasks, and create only does so when `markdown` is provided.
  Date: 2026-09-14

- Decision: Make `AsyncTask` general: `operation` is `{surface :: AsyncTaskSurface, name :: Text}` and a succeeded task's `result` is an `Aeson.Object`. The failed task's error `code` is `Text`.
  Rationale: `docs/masterplans/2-add-the-custom-agents-and-sessions-api-with-sse-streaming.md` reuses this type for `agents.batch`, whose result shape differs from page operations; the JS type is `Record<string, JSON>`. EP-2 (`docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md`) owns the typed `APIErrorCode`; at the time of writing `src/Notion/V1/Error.hs` has no such type (it has only `NotionError` with `code :: Text`), so per the MasterPlan this plan uses `Text`. If EP-2 has landed when this plan is implemented, use `APIErrorCode` instead and record that here.
  Date: 2026-09-14

- Decision: `waitForAsyncTask` takes the retrieve function as an argument and works in any `MonadIO`, and returns the last task seen rather than throwing.
  Rationale: `src/Notion/V1/AsyncTasks.hs` cannot import `Notion.V1.Methods` (that module imports `AsyncTasks`, which would be an import cycle). Taking `AsyncTaskID -> m AsyncTask` lets both `retrieveAsyncTask methods` (IO) and the effectful smart constructor (`Eff es` with `IOE`) use it. Returning the task lets callers pattern-match on succeeded/failed/still-running without a new exception type.
  Date: 2026-09-14

- Decision: Put meeting notes in a new module `src/Notion/V1/MeetingNotes.hs` with its own Servant `API` (`"blocks" :> "meeting_notes" :> ...`) appended to the top-level `API`. Reuse EP-1's meeting-notes sub-types (`MeetingNotesStatus`, `MeetingNotesChildren`, `MeetingCalendarEvent`, `MeetingRecording` from `src/Notion/V1/BlockContent.hs`) inside a `MeetingNotesContent` record rather than defining parallel types.
  Rationale: EP-1 (`docs/plans/6-fix-wire-format-decoding-and-encoding-bugs-found-against-the-official-sdk.md`) fully types the meeting-notes block payload while fixing its crashing decoder. The coordinator's cross-plan review (2026-09-14) found that the first draft of this plan defined identically named types (`MeetingNotesChildren`), which would collide for users importing both modules. Milestones 3 and 4 therefore hard-depend on EP-1. Milestones 1 and 2 do not.
  Date: 2026-09-14

- Decision: Add a ninth test to `tasty/CommentTests.hs` that drives `retrieveComment`, `updateComment` and `deleteComment` through EP-2's `FakeNotion` and checks the HTTP method and path of each request.
  Rationale: The eight planned tests cover only JSON shapes; a wrong `Capture` or verb would compile and pass them. `FakeNotion` makes the route check free of network access.
  Date: 2026-09-15

- Decision: `AsyncTaskError.code` is EP-2's `APIErrorCode`, and `src/Notion/V1/AsyncTasks.hs` imports `Notion.V1.Error` for it.
  Rationale: EP-2 landed first, so per the MasterPlan the shared type is used directly. `Notion.V1.Error` imports no resource module, so there is no import cycle. The JS type lists codes such as `missing_version` and `row_limit_exceeded` that `APIErrorCode` lacks; they decode as `UnknownErrorCode`.
  Date: 2026-09-15

- Decision: The two async page routes use a new route type `AsyncVerb method a = UVerb method '[JSON] '[WithStatus 200 (AsyncOr a), WithStatus 202 (AsyncOr a)]`, exported from `Notion.V1.AsyncTasks` with `AsyncStatuses` and `fromAsyncUnion :: Union (AsyncStatuses a) -> AsyncOr a`. `makeMethods` applies `fromAsyncUnion`, so the `Methods` fields keep the planned `IO (AsyncOr ...)` types.
  Rationale: Notion returns 202 for queued work (see Surprises & Discoveries), and a plain `Post '[JSON]` route rejects it. Both statuses decode with `AsyncOr`'s key-based instance, so a 200 carrying a task (or a 202 carrying a result) still decodes correctly. Alternatives rejected: a custom `ClientEnv` middleware rewriting 202 to 200 would hide real statuses from every route and from EP-2's runtime; a 202-only `Verb` would reject synchronous completions. MasterPlan 2's `agents.batch` should reuse `AsyncVerb`.
  Date: 2026-09-15

- Decision: Add two request-level tests to `tasty/AsyncTaskTests.hs`: one builds the `createPageAsync` request without sending it and checks `POST /v1/pages` with `"allow_async": true` in the body; one drives `retrieveAsyncTask` and `updatePageMarkdownAsync` through `FakeNotion`, with the latter answering 202.
  Rationale: The nine planned tests do not show that the flag reaches the wire or that the 202 response union decodes.
  Date: 2026-09-15

- Decision: `Notion.V1.MeetingNotes` re-exports EP-1's `MeetingNotesStatus (..)`, `MeetingNotesChildren (..)`, `MeetingCalendarEvent (..)` and `MeetingRecording (..)`.
  Rationale: Users pattern-matching on a `MeetingNotesContent` need those constructors; re-exporting the very same types (not copies) lets them import one module and cannot cause a name collision with `Notion.V1.BlockContent`.
  Date: 2026-09-15

- Decision: Keep `createMeetingNote` on a plain `Post '[JSON]` route (status 200 only) and do not live-test it.
  Rationale: The JS SDK types describe a synchronous block response, and creating a meeting note consumes a real recording that cannot be cleanly undone (see Idempotence and Recovery). If Notion turns out to answer 201 or 202, the fix is the same as for the async page routes: switch to a `UVerb` accepting that status.
  Date: 2026-09-15

- Decision: `mnCreatedWithinPast n u` encodes `{"type":"relative","value":"custom","direction":"past","unit":u,"count":n}` instead of `"value":"today"`. The date value strings stay `Text`, with the accepted strings listed in the Haddock of `MNDatePointText` and `MNDateRangeText`.
  Rationale: The live check (Surprises & Discoveries) showed that `"today"` is invalid in a range condition and that `"custom"` with `unit` and `count` is the shape meaning "within the last n units". Typed enums for the relative strings were considered but not added: the JS SDK types them as `string`, and the accepted set came only from server error messages, which may grow. The date-range encoding test now uses `"custom"`, and it also asserts `mnCreatedWithinPast`'s full encoding.
  Date: 2026-09-15

- Decision: The meeting-notes query response gets its own record `QueryMeetingNotesResponse {results, hasMore}`, not `ListOf`.
  Rationale: The response has no `object: "list"` and no `next_cursor` (`src/api-endpoints/meeting-notes.ts` lines 368–392), and the MasterPlan's Integration Points assign this record to EP-3.
  Date: 2026-09-14

- Decision: The meeting-notes filter DSL is recursive (combinators nest to any depth) and includes a `MNRawNode Value` escape hatch; person values are always encoded as a JSON array.
  Rationale: The hand-written JS helper type in `src/meeting-notes.ts` (`MeetingNotesFilterNode`) is recursive, while the generated type in `src/api-endpoints/meeting-notes.ts` spells out only three levels. The server is the authority on depth, so the client does not enforce it. The JS API accepts either one person object or an array; the array form covers both cases, and the JS SDK's own test (`test/Client.test.ts`, "calls query meeting notes API with filter") sends an array.
  Date: 2026-09-14

- Decision: Request-only enums (meeting-note language) get an `...Other Text` escape constructor, and every enum decoded from a response (`AsyncTaskSurface`, `AsyncTaskStatus`, `MeetingNotesStatus`) gets an unknown fallback carrying the raw value. `CommentResponse` and `CreateMeetingNoteResponse` are distinguished by the presence of a key rather than an enum, so they need no fallback.
  Rationale: The MasterPlan's tolerant-decoding rule. Notion adds enum values without a version bump.
  Date: 2026-09-14


## Outcomes & Retrospective

- Milestone 1 (2026-09-15): comment retrieve/update/delete and the restructured `CreateComment` are in. `cabal test` went from 198 to 207 passing tests: the eight planned `Comment mutation (EP-3)` tests plus one network-free route test using `FakeNotion`. The live comment lifecycle passes.
- Milestone 2 (2026-09-15): `Notion.V1.AsyncTasks`, `retrieveAsyncTask`, `createPageAsync` and `updatePageMarkdownAsync` are in. 11 `Async tasks (EP-3)` tests pass (the nine planned plus two request-level tests), for 218 in total. Live checks created a markdown page asynchronously, updated its markdown asynchronously, waited for both tasks and trashed the page. The live check found the 202 status problem that no offline test could reveal.
- Milestone 3 (2026-09-15): `Notion.V1.MeetingNotes` with `createMeetingNote` is in; 7 create tests pass (225 in total). Not exercised live, by design.
- Milestone 4 (2026-09-15): `queryMeetingNotes` and the typed filter/sort DSL are in; the `Meeting notes (EP-3)` group has 14 tests and the suite has 232. The workspace plan returns no meeting notes, but live requests confirmed every helper's body passes Notion's validation, and they caught one invalid helper.


## Context and Orientation

### The repository

The repository root is the directory containing `notion-client.cabal` and `cabal.project`. `cabal.project` lists two packages: `.` (the `notion-client` library, an example executable `notion-client-example`, and a test suite `tasty`) and `notion-client-effectful`. The compiler is GHC 9.12.2 with the `GHC2024` language edition (which already enables `LambdaCase`, `NamedFieldPuns` and `TypeApplications`). The library's cabal stanza also enables `DuplicateRecordFields`, `OverloadedLabels`, `OverloadedStrings` and `RecordWildCards` for every module. A pre-commit hook runs `treefmt`, which reformats Haskell files; if a commit fails because files were reformatted, re-stage them and commit again.

There is no `docs/adr/` directory in this repository; no relevant ADR exists.

### How an endpoint is wired

A *Servant API type* is a Haskell type that describes an HTTP route: path segments separated by `:>`, alternatives separated by `:<|>`, `Capture "x" T` for a path parameter, `ReqBody '[JSON] T` for a JSON body, and a final verb such as `Get '[JSON] R`, `Post '[JSON] R`, `Patch '[JSON] R` or `Delete '[JSON] R` giving the response type. The `servant-client` library turns such a type into ordinary functions.

Each resource module under `src/Notion/V1/` (for example `src/Notion/V1/Comments.hs`) exports its own `API` type. `src/Notion/V1.hs` combines them into one top-level `API`, prefixed with two required headers (`Authorization` and `Notion-Version`), in this order: `Databases.API :<|> DataSources.API :<|> Pages.API :<|> Blocks.API :<|> Users.API :<|> Search.API :<|> Comments.API :<|> Views.API :<|> CustomEmojis.API :<|> FileUploads.API`.

In the same file, `makeMethods :: ClientEnv -> Text -> Methods` calls `Client.hoistClient @API Proxy run (Client.client @API Proxy) authorization notionVersion` and destructures the result with one large pattern whose shape mirrors the `API` type exactly, alternative for alternative. For example the comments part is currently `:<|> ( createComment :<|> listComments_ )`. Names ending in `_` are raw client functions that `makeMethods` then wraps or renames in its `where` clause (for example `listComments = listComments_`). Finally the `Methods` record (also in `src/Notion/V1.hs`) lists one field per operation, such as `createComment :: Comments.CreateComment -> IO CommentObject`. Adding an endpoint therefore always means three coordinated edits: the route in the resource module's `API`, the pattern binding in `makeMethods` at the same position, and the field in `Methods`. If the positions disagree, GHC reports a type mismatch in `makeMethods`.

The `run` function in `makeMethods` executes a request and throws `NotionError` (from `src/Notion/V1/Error.hs`, fields `object`, `status`, `code :: Text`, `message`, `details`) when Notion returns an error body. EP-2 will rewrite `run` and `makeMethods`, but promises to keep `makeMethods :: ClientEnv -> Text -> Methods` working; nothing in this plan depends on `run`'s internals.

### The effectful companion package (lockstep rule)

`notion-client-effectful` re-exposes every `Methods` field as an operation of an `effectful` effect. In `notion-client-effectful/src/Notion/V1/Effectful/Effect.hs` there is a GADT `data Notion :: Effect where` with one constructor per `Methods` field (PascalCase name, same argument types, for example `CreateComment :: Comments.CreateComment -> Notion m CommentObject`), a smart constructor per field with the same name and argument order as the field (for example `createComment = send . CreateComment`), and the export list. In `notion-client-effectful/src/Notion/V1/Effectful/Interpreter.hs`, `runNotion` has one case per constructor (`CreateComment req -> runIO (Notion.createComment methods req)`) and an import list naming every constructor. The rule, stated in the MasterPlan: every change to a `Methods` field must change the constructor, smart constructor, export and interpreter case in the same commit. `cabal build all` builds both packages and catches omissions (a missing interpreter case is a `-Wincomplete-patterns` warning, so read the build output, not only the exit code).

### JSON conventions

`src/Notion/Prelude.hs` defines `aesonOptions`: record field names are converted from camelCase to snake_case (`discussionId` becomes `discussion_id`), a trailing underscore is dropped (`type_` becomes `type`), and `Nothing` fields are omitted (`omitNothingFields = True`). Most response types use hand-written `FromJSON` instances with `\case Object o -> ...` or `Aeson.withObject`, reading fields with `.:` (required) and `.:?` (optional). Timestamps are parsed with `parseISO8601 :: Text -> Parser POSIXTime` and written back with `posixToISO8601`. Modules that have a record field called `id` import `Prelude hiding (id)`. `UUID` (in `src/Notion/V1/Common.hs`) is `newtype UUID = UUID {text :: Text}` with JSON as a plain string. `UserReference` (in `src/Notion/V1/Users.hs`) is `{id :: UserID, object :: Text}` and decodes Notion's partial user `{"object":"user","id":"..."}`. `RichText` (in `src/Notion/V1/RichText.hs`) decodes objects that have `plain_text`, `annotations` (all six keys `bold`, `italic`, `strikethrough`, `underline`, `code`, `color`), `type` and the matching payload key; `Notion.V1.BlockContent.mkRichText :: Text -> Vector RichText` builds a one-element plain-text array. `SortDirection` (`Ascending | Descending`, encoding `"ascending"`/`"descending"`) lives in `src/Notion/V1/Filter.hs`.

"Tolerant decoding" in this plan means: every closed set of string values decoded from a response has a final constructor carrying the raw value (for example `UnknownMeetingNotesStatus Text`), so a new value from Notion never makes decoding fail.

### Comments today

`src/Notion/V1/Comments.hs` defines:

- `CommentAttachment {name, type_, category :: Maybe Text, external :: Maybe ExternalFile, file :: Maybe File}` with hand-written instances that accept both the read shape `{category, file}` and an older write shape. `docs/plans/3-fix-comment-attachment-parsing.md` explains why; its tests `testDeserializeCommentAttachmentReadShape` and `testDeserializeCommentDisplayNameResolvedName` in `tasty/Main.hs` must keep passing.
- `CommentDisplayName {type_ :: Text, emoji, displayName, resolvedName :: Maybe Text}`.
- `CommentObject {id, parent :: Parent, discussionId, createdTime, lastEditedTime, createdBy :: UserReference, richText, attachments, displayName, object :: ObjectType}` with a hand-written decoder requiring `parent`, `discussion_id`, both timestamps, `created_by`, `rich_text` and `object`.
- `CreateComment {parent :: Parent, richText :: Vector RichText, discussionId :: Maybe UUID, attachments :: Maybe (Vector CommentAttachment), displayName :: Maybe CommentDisplayName}` encoded with `genericToJSON aesonOptions`.
- `type API = "comments" :> (ReqBody '[JSON] CreateComment :> Post '[JSON] CommentObject :<|> QueryParam "block_id" BlockID :> QueryParam "start_cursor" Text :> QueryParam "page_size" Natural :> Get '[JSON] (ListOf CommentObject))`.

`CreateComment` is constructed in `tasty/Main.hs` (`testCommentLifecycle` around lines 1170–1190 and `testSerializeCreateComment` around lines 1641–1673), in `notion-client-example/DatabaseDemo.hs` (around lines 321–359, which sends both `parent` and `discussionId` for a reply) and in `notion-client-example/PageDemo.hs` (around lines 72–81).

The JS SDK's wire shapes (`/Users/shinzui/Keikaku/hub/notion-sdk-js/src/api-endpoints/comments.ts`), transcribed so the implementer need not open that repository:

```typescript
// Response of POST comments, GET/PATCH/DELETE comments/{comment_id}
type PartialCommentObjectResponse = { object: "comment"; id: string }
type CommentObjectResponse = {
  object: "comment"; id: string
  parent: { type: "page_id"; page_id: string } | { type: "block_id"; block_id: string }
  discussion_id: string; created_time: string; last_edited_time: string
  created_by: { id: string; object: "user" }
  rich_text: RichTextItemResponse[]
  display_name: { type: "custom" | "user" | "integration"; resolved_name: string | null }
  attachments?: Array<{ category: "audio" | "image" | "pdf" | "productivity" | "video"; file: { url: string; expiry_time: string } }>
}

// POST comments body
type CreateCommentBodyParameters = {
  attachments?: Array<{ file_upload_id: string; type?: "file_upload" }>   // max 3
  display_name?: { type: "integration" } | { type: "user" } | { type: "custom"; custom: { name: string } }
} & (
  | { parent: { page_id: string; type?: "page_id" } | { block_id: string; type?: "block_id" }; rich_text: RichTextItemRequest[] }
  | { parent: /* same */ ...; markdown: string }
  | { discussion_id: string; rich_text: RichTextItemRequest[] }
  | { discussion_id: string; markdown: string }
)

// GET comments/{comment_id}: no body
// PATCH comments/{comment_id} body
type UpdateCommentBodyParameters = { rich_text: RichTextItemRequest[] } | { markdown: string }
// DELETE comments/{comment_id}: no body
```

Comment Markdown supports inline formatting only (bold, italic, strikethrough, code, links), inline equations and mentions; block-level Markdown does not become blocks.

### Async tasks

There is no async-task support in the Haskell client today. The JS type (`src/api-endpoints/async-tasks.ts`), route `GET async_tasks/{task_id}` where `task_id` is a plain string:

```typescript
type GetAsyncTaskResponse = {
  object: "async_task"; id: string; status_url: string; created_time: string
  operation: { surface: "rest" | "mcp"; name: string }
} & (
  | { status: "queued" | "running" | "retrying"; poll_after_seconds: number }
  | { status: "succeeded"; result: Record<string, JSONValue> }
  | { status: "failed"; error: {
        object: "error"; message: string
        additional_data?: Record<string, string | string[]>
        status: 400 | 401 | 403 | 404 | 409 | 429 | 500 | 503 | 504 | 529
        code: string  // e.g. "validation_error", "object_not_found", "conflict_error", "rate_limited", "service_overload"
      } }
)
```

The JS SDK's `CreatePageBodyParameters` (`src/api-endpoints/pages.ts` line 435) has `allow_async?: boolean` with the comment "Set to true to receive an async_task response for markdown page creation. Only supported when markdown is provided." `UpdatePageMarkdownBodyParameters` (line 764) has a top-level `allow_async?: boolean`: "Set to true to opt into receiving an async_task result when this update operation is accepted for background execution. If omitted or false, the endpoint keeps the existing synchronous response shape." The JS response types (`CreatePageResponse`, `UpdatePageMarkdownResponse`) do not mention async tasks; only these comments do. No other published endpoint in the JS SDK mentions `allow_async`.

In Haskell, `src/Notion/V1/Pages.hs` defines `CreatePage` (a record encoded with `genericToJSON aesonOptions`), `UpdatePageMarkdown` (a sum of `UpdateContent | ReplaceContent | InsertContent | ReplaceContentRange`, each encoded as `{"type": ..., "<type>": {...}}`), `PageObject` and `PageMarkdown`. Its `API` has seven alternatives in the order: retrieve (filtered), create, update, retrieve property, retrieve markdown, update markdown, move.

### Meeting notes

A *meeting note* is a Notion block of type `meeting_notes` produced by Notion AI from a recording: it has a title, a processing status, and three child tabs (summary, notes, transcript). The existing `MeetingNotesBlock` constructor in `src/Notion/V1/BlockContent.hs` (around line 581) decodes `title` as `Text`, but Notion sends an array of rich text, so it fails; EP-1 fixes that. This plan does not touch `BlockContent.hs`.

JS wire shapes (`src/api-endpoints/meeting-notes.ts` and the helper types in `src/meeting-notes.ts`):

```typescript
// POST blocks/meeting_notes
type CreateMeetingNoteBodyParameters = {
  title?: string
  language?: "auto" | "en" | "zh-CN" | "zh-TW" | "es" | "fr" | "de" | "ja" | "ko" | "pt" | "ru"
           | "th" | "vi" | "id" | "da" | "fi" | "no" | "nl" | "it" | "sv" | "ar" | "he" | "pl"
  options?: { kickoff_summary?: boolean }
} & (
  | { source: { type: "file_upload"; file_upload_id: string }; parent: { type: "page_id"; page_id: string } }
  | { source: { type: "block"; block_id: string } }   // parent not accepted
)

type MeetingNotesPayload = {
  title?: RichTextItemResponse[]
  status?: "transcription_not_started" | "transcription_paused" | "transcription_in_progress"
         | "transcription_failed" | "summary_in_progress" | "notes_ready"
  children?: { summary_block_id?: string; notes_block_id?: string; transcript_block_id?: string }
  calendar_event?: { start_time: string; end_time: string; attendees?: string[] }
  recording?: { start_time?: string; end_time?: string }
}

type MeetingNoteBlock = {
  object: "block"; id: string; type: "meeting_notes"; meeting_notes: MeetingNotesPayload
  created_time: string; last_edited_time: string
  created_by: { id: string; object: "user" }; last_edited_by: { id: string; object: "user" }
  has_children: boolean; in_trash: boolean; archived: boolean   // note: no `parent`
}
type CreateMeetingNoteResponse = { object: "block"; id: string } | MeetingNoteBlock

// POST blocks/meeting_notes/query
type QueryMeetingNotesParameters = {
  filter?: MeetingNotesCombinatorFilter
  sort?: Array<{ property: "title" | "created_time" | "last_edited_time" | "created_by" | "last_edited_by" | "attendees";
                 direction: "ascending" | "descending" }>
  limit?: number   // default 50
}
type QueryMeetingNotesResponse = { results: MeetingNoteBlock[]; has_more: boolean }  // no next_cursor

type MeetingNotesCombinatorFilter = { operator: "and" | "or"; filters?: MeetingNotesFilterNode[] }
type MeetingNotesFilterNode = MeetingNotesCombinatorFilter | { property: P; filter: ConditionFor<P> }

// title:
//   { operator: "string_is" | "string_is_not" | "string_contains" | "string_does_not_contain"
//              | "string_starts_with" | "string_ends_with"; value: { type: "exact"; value: string } }
// created_time, last_edited_time:
//   { operator: "date_is" | "date_is_before" | "date_is_after" | "date_is_on_or_before" | "date_is_on_or_after";
//     value: { type: "relative" | "exact";
//              value: string | { type: "date" | "datetime"; start_date: string; start_time?: string; time_zone?: string } } }
//   { operator: "date_is_within" | "date_is_relative_to";
//     value: { type: "relative" | "exact";
//              value: string | { type: "daterange"; start_date: string; end_date?: string };
//              direction?: "past" | "future"; unit?: "day" | "week" | "month" | "year"; count?: number } }
// created_by, last_edited_by, attendees:
//   { operator: "person_contains" | "person_does_not_contain";
//     value: PersonValue | PersonValue[] }  where PersonValue = { type: "exact"; value: { table: "notion_user"; id: string } }
// every property also accepts { operator: "is_empty" | "is_not_empty" } with no value
```

The query endpoint's status enum omits `transcription_failed`; decoding the union of both lists with a fallback covers both. The JS SDK's test sends an empty query as the body `{}`, so the Haskell encoding of an all-`Nothing` query must be `{}`.

### Tests

The test suite `tasty` (stanza `test-suite tasty` in `notion-client.cabal`, `hs-source-dirs: tasty`, `main-is: Main.hs`, currently no `other-modules`) is one 2298-line file, `tasty/Main.hs`. Its `tests :: IO TestTree` ends with:

```haskell
  pure $
    testGroup
      "Notion Client Tests"
      [ jsonParsingTests,
        jsonSerializationTests,
        propertyValueTests,
        fileUploadTests,
        basicIntegration,
        markdownE2E,
        pageE2E,
        databaseE2E,
        viewE2E
      ]
```

Per the MasterPlan, this plan's new tests go in new modules (`tasty/CommentTests.hs`, `tasty/AsyncTaskTests.hs`, `tasty/MeetingNotesTests.hs`), each exporting `tests :: TestTree`, listed under a new `other-modules:` field of `test-suite tasty`, and added as one line each to that list. Live tests that need a token already exist in `tasty/Main.hs` (`pageE2E` runs `testCommentLifecycle` when `NOTION_TOKEN` and `NOTION_TEST_PAGE_ID` are set); this plan extends that one function because it must edit it anyway. Test fixtures never use the maintainer's real name; use made-up Japanese names such as "Tanaka Hanako" or "Sato Kenji". The test suite depends on `aeson`, `bytestring`, `containers`, `tasty`, `tasty-hunit`, `text`, `vector` and others; no new dependency is needed.


## Plan of Work

The work has four milestones. Each ends with a green `cabal build all` and `cabal test` and adds its own tests, so the plan can stop after any of them.

### Milestone 1: comment mutation and correct create-comment requests

At the end of this milestone a user can retrieve, update and delete a comment and create comments in every shape Notion accepts. All edits are in `src/Notion/V1/Comments.hs`, `src/Notion/V1.hs`, the two effectful modules, the call sites listed above, `tasty/CommentTests.hs`, `tasty/Main.hs` and `notion-client.cabal`.

In `src/Notion/V1/Comments.hs`, keep `CommentAttachment`, `CommentDisplayName` and `CommentObject` exactly as they are, but update their Haddock comments to say they describe the read shape and that requests use the new request types. Add these types and export them (with constructors) from the module header:

```haskell
-- | A comment endpoint response: Notion may return the full comment or only its id.
data CommentResponse
  = FullComment CommentObject
  | PartialComment CommentID
  deriving stock (Generic, Show)

instance FromJSON CommentResponse where
  parseJSON = Aeson.withObject "CommentResponse" $ \o ->
    if KeyMap.member "parent" o
      then FullComment <$> Aeson.parseJSON (Object o)
      else PartialComment <$> o .: "id"

-- | The id carried by either response shape.
commentResponseId :: CommentResponse -> CommentID

-- | The full comment, if Notion returned one.
commentResponseObject :: CommentResponse -> Maybe CommentObject

-- | Where a new comment goes.
data CommentTarget
  = -- | Start a new discussion on a page ('PageParent') or block ('BlockParent').
    -- Other 'Parent' constructors are rejected by Notion.
    CommentOnParent Parent
  | -- | Reply in an existing discussion. Notion requires @parent@ to be absent.
    CommentInDiscussion UUID
  deriving stock (Generic, Show)

-- | The body of a comment: rich text or inline Markdown.
data CommentContent
  = CommentRichText (Vector RichText)
  | CommentMarkdown Text
  deriving stock (Generic, Show)

instance ToJSON CommentContent where
  toJSON (CommentRichText rt) = Aeson.object ["rich_text" .= rt]
  toJSON (CommentMarkdown md) = Aeson.object ["markdown" .= md]

-- | Attach a completed file upload to a new comment. Encodes as
-- @{"file_upload_id": "...", "type": "file_upload"}@.
newtype CommentAttachmentRequest = CommentAttachmentRequest {fileUploadId :: UUID}
  deriving stock (Generic, Show)

-- | How the new comment's author is displayed.
data CommentDisplayNameRequest
  = DisplayAsIntegration          -- {"type":"integration"}
  | DisplayAsUser                 -- {"type":"user"}
  | DisplayAsCustom Text          -- {"type":"custom","custom":{"name":...}}
  deriving stock (Generic, Show)

data CreateComment = CreateComment
  { target :: CommentTarget,
    content :: CommentContent,
    attachments :: Maybe (Vector CommentAttachmentRequest),
    displayName :: Maybe CommentDisplayNameRequest
  }
  deriving stock (Generic, Show)

mkCreateComment :: Parent -> CommentContent -> CreateComment
mkReplyComment :: UUID -> CommentContent -> CreateComment
```

`KeyMap` is `Data.Aeson.KeyMap` (import qualified). Deciding "full or partial" by the presence of `parent` is deliberate: if `parent` is present but another required field is missing, decoding fails loudly instead of silently becoming `PartialComment`.

Write `ToJSON CreateComment` by hand: build the object from `target` (either `"parent" .= p` or `"discussion_id" .= d`), merge the one key produced by `content` (pattern-match on the constructor rather than decoding the `toJSON` result), and add `attachments` and `display_name` only when `Just`. Write `ToJSON CommentAttachmentRequest` and `ToJSON CommentDisplayNameRequest` by hand to produce exactly the shapes in the comments above. `mkCreateComment p c` and `mkReplyComment d c` set the optional fields to `Nothing`.

Replace the `API` type with:

```haskell
type API =
  "comments"
    :> ( ReqBody '[JSON] CreateComment
           :> Post '[JSON] CommentResponse
           :<|> QueryParam "block_id" BlockID
           :> QueryParam "start_cursor" Text
           :> QueryParam "page_size" Natural
           :> Get '[JSON] (ListOf CommentObject)
           :<|> Capture "comment_id" CommentID
           :> Get '[JSON] CommentResponse
           :<|> Capture "comment_id" CommentID
           :> ReqBody '[JSON] CommentContent
           :> Patch '[JSON] CommentResponse
           :<|> Capture "comment_id" CommentID
           :> Delete '[JSON] CommentResponse
       )
```

The update body type is `CommentContent` itself, because the PATCH body is exactly `{rich_text}` or `{markdown}`.

In `src/Notion/V1.hs`, import `CommentResponse` and `CommentContent` from `Notion.V1.Comments`, change the comments part of the `makeMethods` pattern to `( createComment :<|> listComments_ :<|> retrieveComment :<|> updateComment :<|> deleteComment )`, and in `Methods` change and add, under `-- \* Comments`:

```haskell
    createComment :: Comments.CreateComment -> IO CommentResponse,
    listComments :: ... unchanged ...,
    retrieveComment :: Comments.CommentID -> IO CommentResponse,
    -- | Replace a comment's content with rich text or Markdown.
    updateComment :: Comments.CommentID -> CommentContent -> IO CommentResponse,
    deleteComment :: Comments.CommentID -> IO CommentResponse,
```

In `notion-client-effectful/src/Notion/V1/Effectful/Effect.hs`, change `CreateComment`'s result to `CommentResponse`, add `RetrieveComment :: Comments.CommentID -> Notion m CommentResponse`, `UpdateComment :: Comments.CommentID -> Comments.CommentContent -> Notion m CommentResponse` and `DeleteComment :: Comments.CommentID -> Notion m CommentResponse`, their smart constructors (`retrieveComment = send . RetrieveComment`, `updateComment cid c = send (UpdateComment cid c)`, `deleteComment = send . DeleteComment`) with `-- | See 'Notion.V1.Methods'...` comments, and the export entries under `-- * Comments`. In `Interpreter.hs`, add the three constructors to the import list and the cases `RetrieveComment cid -> runIO (Notion.retrieveComment methods cid)`, and so on.

Update call sites. In `tasty/Main.hs` `testCommentLifecycle`, build requests with `mkCreateComment PageParent {pageId} (CommentRichText (Vector.singleton (mkTypedRichText "...")))`, get ids with `Comments.commentResponseId`, and after the list assertions add: retrieve `comment1Id` and assert its id matches; `updateComment comment1Id (CommentMarkdown "Edited by **E2E** tests.")` and, if the result is `FullComment`, assert `plainText` of the first rich text item contains `"Edited by"`; `deleteComment comment2Id`; then list comments on the block again (deleted comments should no longer be returned; if Notion still returns it, record that in Surprises & Discoveries rather than failing the test, and assert only that the call succeeded). Destructure `methods@Methods {..}` to get the new fields. Rewrite `testSerializeCreateComment` to use `CreateComment {target = CommentOnParent ..., content = CommentRichText ..., attachments = Just (Vector.singleton (CommentAttachmentRequest (UUID "fu-1"))), displayName = Just (DisplayAsCustom "Sato Kenji")}` and keep its two `KeyMap.member` assertions. Update the import on line 16 to bring in the new names. In `notion-client-example/DatabaseDemo.hs` use `mkCreateComment commentParent (CommentRichText commentRichText)` for the first comment and `mkReplyComment discId (CommentRichText replyRichText)` for the reply; results are now `CommentResponse`, so print `commentResponseId` and obtain `discId` by matching `FullComment CommentObject {discussionId}` (fall back to skipping the reply with a printed message on `PartialComment`). Do the same in `notion-client-example/PageDemo.hs`.

Create `tasty/CommentTests.hs` (details in Concrete Steps) and register it.

### Milestone 2: async tasks and `allow_async`

At the end of this milestone `retrieveAsyncTask`, `createPageAsync` and `updatePageMarkdownAsync` exist and a polling helper waits for completion.

Create `src/Notion/V1/AsyncTasks.hs` and add `Notion.V1.AsyncTasks` to `exposed-modules` in `notion-client.cabal` (keep the list alphabetical: after `Notion.V1`). It imports only `Notion.Prelude`, `Data.Aeson` helpers, `Data.Aeson.KeyMap`, `Control.Concurrent (threadDelay)` and `Control.Monad.IO.Class (MonadIO, liftIO)`; it must not import `Notion.V1`, `Pages` or `Error` (to avoid cycles and to stay independent of EP-2). Contents:

```haskell
type AsyncTaskID = Text

data AsyncTask = AsyncTask
  { id :: AsyncTaskID,
    statusUrl :: Text,
    createdTime :: POSIXTime,
    operation :: AsyncTaskOperation,
    status :: AsyncTaskStatus,
    object :: Text                       -- always "async_task"
  }
  deriving stock (Generic, Show)

data AsyncTaskOperation = AsyncTaskOperation
  { surface :: AsyncTaskSurface,
    name :: Text                         -- e.g. the operation that created the task
  }
  deriving stock (Eq, Generic, Show)

data AsyncTaskSurface = SurfaceRest | SurfaceMcp | UnknownSurface Text
  deriving stock (Eq, Generic, Show)

data AsyncTaskStatus
  = AsyncTaskQueued Double               -- poll_after_seconds
  | AsyncTaskRunning Double
  | AsyncTaskRetrying Double
  | AsyncTaskSucceeded Aeson.Object      -- result
  | AsyncTaskFailed AsyncTaskError
  | UnknownAsyncTaskStatus Text          -- raw status string; the full object is still in AsyncTask
  deriving stock (Generic, Show)

data AsyncTaskError = AsyncTaskError
  { object :: Text,                      -- always "error"
    status :: Natural,                   -- HTTP-style status, e.g. 400
    code :: Text,                        -- use EP-2's APIErrorCode instead if Error.hs exports it
    message :: Text,
    additionalData :: Maybe Aeson.Object
  }
  deriving stock (Generic, Show)

-- | A response that is either the finished result or an accepted async task.
data AsyncOr a
  = AcceptedAsync AsyncTask
  | CompletedSync a
  deriving stock (Generic, Show)

-- | Request wrapper that adds @"allow_async": true@ to an object body.
newtype AllowAsync a = AllowAsync a
  deriving stock (Show)

data WaitOptions = WaitOptions
  { maxAttempts :: Natural,              -- retrieve calls before giving up (default 120)
    maxPollSeconds :: Double             -- upper bound on any single wait (default 30)
  }
  deriving stock (Eq, Show)

defaultWaitOptions :: WaitOptions
isTerminal :: AsyncTask -> Bool          -- True for Succeeded, Failed and UnknownAsyncTaskStatus
pollAfterSeconds :: AsyncTask -> Maybe Double
waitForAsyncTask :: MonadIO m => WaitOptions -> (AsyncTaskID -> m AsyncTask) -> AsyncTask -> m AsyncTask
```

The `FromJSON AsyncTask` instance reads `id`, `status_url`, `created_time` (via `parseISO8601`), `operation`, `object`, then `status :: Text` and branches: `"queued"`, `"running"`, `"retrying"` read `poll_after_seconds`; `"succeeded"` reads `result` (as an object; use `fromMaybe mempty <$> o .:? "result"` so a missing result decodes as empty); `"failed"` reads `error`; any other string becomes `UnknownAsyncTaskStatus s`. `AsyncTaskSurface` decodes `"rest"`, `"mcp"` and anything else as `UnknownSurface`. Treating an unknown status as terminal means `waitForAsyncTask` returns it to the caller immediately instead of polling a state it does not understand (for example a future `"cancelled"`). Provide `ToJSON` instances for `AsyncTask`, `AsyncTaskOperation`, `AsyncTaskSurface` and `AsyncTaskError` that write the same wire shape, so tests can round-trip.

`FromJSON (AsyncOr a)` checks whether the value is an object whose `object` key equals the string `"async_task"`; if so it decodes `AcceptedAsync`, otherwise `CompletedSync` with `a`'s decoder. `ToJSON (AllowAsync a)` calls `toJSON` on the inner value and, if the result is an object, inserts `"allow_async"` with `Bool True` (non-object values pass through unchanged).

`waitForAsyncTask opts retrieve task` loops with an attempt counter starting at 0: if `isTerminal task` or the counter has reached `maxAttempts`, return `task`; otherwise sleep for `min maxPollSeconds (max 0 secs)` seconds where `secs` is the task's `poll_after_seconds` (`liftIO (threadDelay (round (secs * 1000000)))`), call `retrieve (id task)`, and loop with the counter plus one. Callers check `isTerminal` on the result to detect a timeout.

In `src/Notion/V1/Pages.hs`, import `Notion.V1.AsyncTasks (AllowAsync, AsyncOr)` and append two alternatives at the end of `API` (after move):

```haskell
           :<|> ReqBody '[JSON] (AllowAsync CreatePage)
           :> AsyncVerb 'POST PageObject
           :<|> Capture "page_id" PageID
           :> "markdown"
           :> ReqBody '[JSON] (AllowAsync UpdatePageMarkdown)
           :> AsyncVerb 'PATCH PageMarkdown
```

(Revised during implementation: the first draft used `Post '[JSON] (AsyncOr PageObject)` and `Patch '[JSON] (AsyncOr PageMarkdown)`, which reject Notion's 202 responses. `AsyncVerb` is defined in `src/Notion/V1/AsyncTasks.hs` as a `UVerb` accepting 200 and 202, and the `where` clause of `makeMethodsWithEnv` applies `fromAsyncUnion` to the raw client results.)

In `src/Notion/V1/AsyncTasks.hs` also define `type API = "async_tasks" :> Capture "task_id" AsyncTaskID :> Get '[JSON] AsyncTask`. In `src/Notion/V1.hs`, append `:<|> AsyncTasks.API` to the top-level `API` after `FileUploads.API`; extend the pages part of the `makeMethods` pattern with `:<|> createPageAsync_ :<|> updatePageMarkdownAsync_` after `movePage`; add `:<|> retrieveAsyncTask` as the last alternative of the whole pattern; and in the `where` clause define `createPageAsync req = fromAsyncUnion <$> createPageAsync_ (AllowAsync req)` and `updatePageMarkdownAsync pid req = fromAsyncUnion <$> updatePageMarkdownAsync_ pid (AllowAsync req)`. Add to `Methods`:

```haskell
    -- \* Pages
    -- | Like 'createPage' but sends @allow_async: true@. Notion may answer with an
    -- async task instead of the page. Only meaningful when 'markdown' is set.
    createPageAsync :: CreatePage -> IO (AsyncOr PageObject),
    -- | Like 'updatePageMarkdown' but sends @allow_async: true@.
    updatePageMarkdownAsync :: PageID -> UpdatePageMarkdown -> IO (AsyncOr PageMarkdown),
    -- \* Async tasks
    retrieveAsyncTask :: AsyncTaskID -> IO AsyncTask,
```

Mirror these three in the effectful package (`CreatePageAsync`, `UpdatePageMarkdownAsync`, `RetrieveAsyncTask`; smart constructors `createPageAsync`, `updatePageMarkdownAsync`, `retrieveAsyncTask`; exports under `-- * Pages` and a new `-- * Async Tasks` section; interpreter cases). Because `waitForAsyncTask` is polymorphic in `MonadIO`, effectful users call `waitForAsyncTask defaultWaitOptions retrieveAsyncTask task` with the effectful smart constructor; no effect change is needed for it. Mention that in the Haddock of `waitForAsyncTask`.

Create `tasty/AsyncTaskTests.hs` and register it.

### Milestone 3: create meeting notes

At the end of this milestone a user can call `createMeetingNote`, and meeting-note blocks decode into a fully typed record.

**Precondition (hard dependency for Milestones 3 and 4):** EP-1 (`docs/plans/6-fix-wire-format-decoding-and-encoding-bugs-found-against-the-official-sdk.md`) owns the meeting-notes payload sub-types. It adds them to `src/Notion/V1/BlockContent.hs` while fixing the `MeetingNotesBlock` decoder. Check that they exist before starting this milestone:

```bash
cd /Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client
grep -n "data MeetingNotesStatus\|data MeetingNotesChildren\|data MeetingCalendarEvent\|data MeetingRecording" src/Notion/V1/BlockContent.hs
```

Expect four lines. If any are missing, EP-1 has not landed. Stop, mark Milestones 3 and 4 blocked in Progress, and do not define local copies: two `MeetingNotesChildren` types in exported modules would collide in user code. Milestones 1 and 2 do not need EP-1.

EP-1 defines these types, reproduced here so this plan is self-contained. Do not redefine them.

```haskell
-- In Notion.V1.BlockContent (owned by EP-1), each with FromJSON/ToJSON:
data MeetingNotesStatus
  = TranscriptionNotStarted | TranscriptionPaused | TranscriptionInProgress
  | TranscriptionFailed | SummaryInProgress | NotesReady
  | UnknownMeetingNotesStatus Text
data MeetingNotesChildren = MeetingNotesChildren
  {summaryBlockId :: Maybe UUID, notesBlockId :: Maybe UUID, transcriptBlockId :: Maybe UUID}
data MeetingCalendarEvent = MeetingCalendarEvent
  {calendarStartTime :: Text, calendarEndTime :: Text, calendarAttendees :: Maybe (Vector UUID)}
data MeetingRecording = MeetingRecording
  {recordingStartTime :: Maybe Text, recordingEndTime :: Maybe Text}
```

Create `src/Notion/V1/MeetingNotes.hs` and add `Notion.V1.MeetingNotes` to `exposed-modules`. It imports:

- `Notion.Prelude`
- `Notion.V1.Common (BlockID, ObjectType, UUID)`
- `Notion.V1.RichText (RichText)`
- `Notion.V1.Users (UserID, UserReference)`
- `Notion.V1.BlockContent (MeetingNotesStatus (..), MeetingNotesChildren (..), MeetingCalendarEvent (..), MeetingRecording (..))`
- in Milestone 4, `Notion.V1.Filter (SortDirection (..))`
- `Prelude hiding (id)`

`BlockContent` does not import `MeetingNotes`, so there is no import cycle. Types for this milestone:

```haskell
-- | The meeting_notes payload as returned by the create and query endpoints.
-- Field types are EP-1's; field names are prefixed to avoid clashing with
-- the MeetingNotesBlock constructor fields re-exported from Notion.V1.Blocks.
data MeetingNotesContent = MeetingNotesContent
  { contentTitle :: Maybe (Vector RichText),
    contentStatus :: Maybe MeetingNotesStatus,
    contentChildren :: Maybe MeetingNotesChildren,
    contentCalendarEvent :: Maybe MeetingCalendarEvent,
    contentRecording :: Maybe MeetingRecording
  }

-- | A meeting-notes block as returned by the create and query endpoints (no @parent@).
data MeetingNoteBlock = MeetingNoteBlock
  { id :: BlockID,
    meetingNotes :: MeetingNotesContent,
    createdTime :: POSIXTime,
    lastEditedTime :: POSIXTime,
    createdBy :: UserReference,
    lastEditedBy :: UserReference,
    hasChildren :: Bool,
    inTrash :: Bool,
    object :: ObjectType
  }

data MeetingNoteLanguage
  = LanguageAuto | LanguageEn | LanguageZhCN | LanguageZhTW | LanguageEs | LanguageFr
  | LanguageDe | LanguageJa | LanguageKo | LanguagePt | LanguageRu | LanguageTh
  | LanguageVi | LanguageId | LanguageDa | LanguageFi | LanguageNo | LanguageNl
  | LanguageIt | LanguageSv | LanguageAr | LanguageHe | LanguagePl
  | LanguageOther Text
  deriving stock (Eq, Generic, Show)

data MeetingNoteSource
  = -- | An uploaded audio/video file (status @uploaded@) and the page to create the note in.
    FromFileUpload {fileUploadId :: UUID, parentPageId :: UUID}
  | -- | An existing audio, video or file block. No parent is sent.
    FromBlock {sourceBlockId :: BlockID}

data CreateMeetingNote = CreateMeetingNote
  { source :: MeetingNoteSource,
    title :: Maybe Text,
    language :: Maybe MeetingNoteLanguage,
    kickoffSummary :: Maybe Bool          -- sent as options.kickoff_summary
  }

mkCreateMeetingNote :: MeetingNoteSource -> CreateMeetingNote

data CreateMeetingNoteResponse
  = FullMeetingNote MeetingNoteBlock
  | PartialMeetingNote BlockID
```

Derive `Generic, Show` on all of them (and `Eq` where every field supports it). Calendar and recording times stay `Text` because the JS type only promises "ISO-8601" and an all-day calendar event may carry a date without a time, which `parseISO8601` would reject; the block's own `created_time` and `last_edited_time` use `POSIXTime` like every other object in the library.

Decoders: the status, children, calendar-event and recording decoders are EP-1's and are reused as-is. `MeetingNotesContent` is hand-written and reads `title`, `status`, `children`, `calendar_event` and `recording` with `.:?`. `MeetingNoteBlock` reads `meeting_notes`, both timestamps through `parseISO8601`, `in_trash` with the same fallback the library uses elsewhere (`(o .: "in_trash") <|> (o .: "archived") <|> pure False`), and ignores `type` and `archived`. `CreateMeetingNoteResponse` decodes `FullMeetingNote` when the key `meeting_notes` is present and `PartialMeetingNote <$> o .: "id"` otherwise. Provide `ToJSON` for the response-side types too, writing the same shape, so tests can round-trip.

Encoders: `MeetingNoteLanguage` writes the exact strings listed in the JS type (`LanguageZhCN` is `"zh-CN"`, `LanguageZhTW` is `"zh-TW"`, `LanguageNo` is `"no"`, `LanguageOther t` is `t`). `CreateMeetingNote` is hand-written: for `FromFileUpload` emit `"source": {"type":"file_upload","file_upload_id":...}` and `"parent": {"type":"page_id","page_id":...}`; for `FromBlock` emit `"source": {"type":"block","block_id":...}` and no `parent`; add `title` and `language` when `Just`; add `"options": {"kickoff_summary": b}` only when `kickoffSummary` is `Just b`.

Define the module's Servant API, which Milestone 4 extends:

```haskell
type API =
  "blocks"
    :> "meeting_notes"
    :> ( ReqBody '[JSON] CreateMeetingNote
           :> Post '[JSON] CreateMeetingNoteResponse
       )
```

In `src/Notion/V1.hs`, append `:<|> MeetingNotes.API` after `AsyncTasks.API`, add `:<|> createMeetingNote` at the very end of the `makeMethods` pattern, and add under a new `-- \* Meeting notes` heading in `Methods`: `createMeetingNote :: MeetingNotes.CreateMeetingNote -> IO MeetingNotes.CreateMeetingNoteResponse`. Mirror it in the effectful package.

Servant's client does not route requests, so having `blocks/meeting_notes` in a different API branch from `blocks/{block_id}` is harmless: each generated function builds its own path.

Create `tasty/MeetingNotesTests.hs` with the create tests and register it.

### Milestone 4: query meeting notes with a typed filter language

At the end of this milestone `queryMeetingNotes` exists with a filter DSL that can only express the operator/value combinations the JS helper types allow. All names carry an `MN` or `MeetingNotes` prefix because `src/Notion/V1/Filter.hs` already exports `Filter`, `PropertyFilter`, `And`, `Or`, `TextCondition`, `DateCondition` and `TextIsEmpty`, and tests import both modules.

Add to `src/Notion/V1/MeetingNotes.hs`:

```haskell
data MeetingNotesFilter = MeetingNotesFilter
  { operator :: MeetingNotesCombinator,
    filters :: [MeetingNotesFilterNode]
  }

data MeetingNotesCombinator = MNAnd | MNOr

data MeetingNotesFilterNode
  = MNNested MeetingNotesFilter
  | MNProperty MeetingNotesPropertyFilter
  | -- | Escape hatch for filter shapes this library does not model yet.
    MNRawNode Value

data MeetingNotesPropertyFilter
  = MNTitle MeetingNotesTextCondition
  | MNCreatedTime MeetingNotesDateCondition
  | MNLastEditedTime MeetingNotesDateCondition
  | MNCreatedBy MeetingNotesPersonCondition
  | MNLastEditedBy MeetingNotesPersonCondition
  | MNAttendees MeetingNotesPersonCondition

data MeetingNotesTextCondition
  = MNStringIs Text | MNStringIsNot Text | MNStringContains Text
  | MNStringDoesNotContain Text | MNStringStartsWith Text | MNStringEndsWith Text
  | MNTextIsEmpty | MNTextIsNotEmpty

data MeetingNotesDateCondition
  = MNDateIs MeetingNotesDatePoint | MNDateIsBefore MeetingNotesDatePoint
  | MNDateIsAfter MeetingNotesDatePoint | MNDateIsOnOrBefore MeetingNotesDatePoint
  | MNDateIsOnOrAfter MeetingNotesDatePoint
  | MNDateIsWithin MeetingNotesDateRange | MNDateIsRelativeTo MeetingNotesDateRange
  | MNDateIsEmpty | MNDateIsNotEmpty

data MeetingNotesPersonCondition
  = MNPersonContains (NonEmpty UserID)
  | MNPersonDoesNotContain (NonEmpty UserID)
  | MNPersonIsEmpty | MNPersonIsNotEmpty

data MeetingNotesDateValueType = MNRelative | MNExact

data MeetingNotesDatePoint = MeetingNotesDatePoint
  { valueType :: MeetingNotesDateValueType,
    value :: MeetingNotesDatePointValue
  }

data MeetingNotesDatePointValue
  = MNDatePointText Text                        -- "value": "<string>"
  | MNDatePointSpec MeetingNotesDateSpec         -- "value": {"type":"date"|"datetime", ...}

data MeetingNotesDateSpec = MeetingNotesDateSpec
  { withTime :: Bool,                            -- False => "date", True => "datetime"
    startDate :: Text,                           -- e.g. "2026-09-01"
    startTime :: Maybe Text,                     -- e.g. "09:30"
    timeZone :: Maybe Text                       -- IANA name, e.g. "Asia/Tokyo"
  }

data MeetingNotesDateRange = MeetingNotesDateRange
  { valueType :: MeetingNotesDateValueType,
    value :: MeetingNotesDateRangeValue,
    direction :: Maybe MeetingNotesDirection,
    unit :: Maybe MeetingNotesDateUnit,
    count :: Maybe Natural
  }

data MeetingNotesDateRangeValue
  = MNDateRangeText Text                         -- "value": "<string>"
  | MNDateRangeSpec Text (Maybe Text)            -- {"type":"daterange","start_date":..,"end_date"?:..}

data MeetingNotesDirection = MNPast | MNFuture
data MeetingNotesDateUnit = MNDay | MNWeek | MNMonth | MNYear

data MeetingNotesProperty
  = MNPropTitle | MNPropCreatedTime | MNPropLastEditedTime
  | MNPropCreatedBy | MNPropLastEditedBy | MNPropAttendees

data MeetingNotesSort = MeetingNotesSort
  { property :: MeetingNotesProperty,
    direction :: SortDirection                   -- from Notion.V1.Filter
  }

data QueryMeetingNotes = QueryMeetingNotes
  { filter :: Maybe MeetingNotesFilter,
    sort :: Maybe [MeetingNotesSort],
    limit :: Maybe Natural                       -- server default 50
  }

emptyQueryMeetingNotes :: QueryMeetingNotes      -- all Nothing; encodes as {}

data QueryMeetingNotesResponse = QueryMeetingNotesResponse
  { results :: Vector MeetingNoteBlock,
    hasMore :: Bool
  }
```

Derive `Eq, Generic, Show` on these. All of these are request types (except the response) and need only `ToJSON`; they are never decoded, so they need no unknown fallback. Encoding rules, written by hand:

- `MeetingNotesFilter` writes `{"operator":"and"|"or","filters":[...]}`.
- `MNNested f` writes `f`; `MNRawNode v` writes `v`; `MNProperty p` writes `{"property":"<name>","filter":<condition>}` where the name is `title`, `created_time`, `last_edited_time`, `created_by`, `last_edited_by` or `attendees`.
- A text condition with a value writes `{"operator":"string_contains","value":{"type":"exact","value":"standup"}}`; empty checks write `{"operator":"is_empty"}` with no `value` key.
- A point date condition writes `{"operator":"date_is_on_or_after","value":{"type":"exact","value":<string or spec>}}`; a spec writes `{"type":"date","start_date":...}` plus `start_time` and `time_zone` only when `Just`.
- A range date condition writes `{"operator":"date_is_within","value":{"type":...,"value":<string or daterange>,"direction"?,"unit"?,"count"?}}`, omitting absent optional keys.
- A person condition writes `{"operator":"person_contains","value":[{"type":"exact","value":{"table":"notion_user","id":"<uuid>"}}, ...]}` (always an array, one element per user).
- `MeetingNotesSort` writes `{"property":"<name>","direction":"ascending"|"descending"}`.
- `QueryMeetingNotes` writes only the `Just` keys, so `emptyQueryMeetingNotes` encodes to `{}`.

`QueryMeetingNotesResponse` gets `FromJSON` reading `results` and `has_more` (and `ToJSON` for round-tripping).

Add a handful of convenience constructors so common queries read naturally, and export them: `mnAnd, mnOr :: [MeetingNotesFilterNode] -> MeetingNotesFilter`; `mnTitleContains :: Text -> MeetingNotesFilterNode`; `mnAttendeesInclude :: UserID -> MeetingNotesFilterNode`; `mnCreatedOnOrAfter :: Text -> MeetingNotesFilterNode` (an exact `date` spec with the given `YYYY-MM-DD`); `mnCreatedWithinPast :: Natural -> MeetingNotesDateUnit -> MeetingNotesFilterNode` (a relative range with `value = MNDateRangeText "custom"`, `direction = Just MNPast`, the given unit and count). The JS types do not document which relative strings are valid. A live check found that range conditions accept `the_past_week`, `the_past_month`, `the_past_year`, `the_next_week`, `the_next_month`, `the_next_year` and `this_week`, or `custom`/`surrounding` with `unit` and `count`. Point conditions accept `today`, `tomorrow`, `yesterday`, `one_week_ago`, `one_week_from_now`, `one_month_ago` and `one_month_from_now`. (Revised during implementation: the first draft used `"today"`, which Notion rejects in a range condition.)

Extend the module's `API` to:

```haskell
type API =
  "blocks"
    :> "meeting_notes"
    :> ( ReqBody '[JSON] CreateMeetingNote
           :> Post '[JSON] CreateMeetingNoteResponse
           :<|> "query"
           :> ReqBody '[JSON] QueryMeetingNotes
           :> Post '[JSON] QueryMeetingNotesResponse
       )
```

In `src/Notion/V1.hs` change the tail of the pattern to `:<|> ( createMeetingNote :<|> queryMeetingNotes )` and add `queryMeetingNotes :: MeetingNotes.QueryMeetingNotes -> IO MeetingNotes.QueryMeetingNotesResponse` to `Methods`. Mirror it in the effectful package. Note that the record field `filter` shadows `Prelude.filter` only at use sites; `src/Notion/V1/DataSources.hs` already has a `filter` field, so follow its style (construct with record syntax; use `NamedFieldPuns` when reading).

Add the query tests to `tasty/MeetingNotesTests.hs`, then write the CHANGELOG entries.

### CHANGELOG

At the top of `CHANGELOG.md`, directly under `# Changelog for notion-client`, ensure a `## Unreleased` heading exists (create it if another plan has not) and add under its subsections:

```markdown
### Breaking Changes
* `CreateComment` is restructured: `target :: CommentTarget` (parent or discussion) and `content :: CommentContent` (rich text or Markdown) replace `parent`, `discussionId` and `richText`; `attachments` now holds `CommentAttachmentRequest` and `displayName` holds `CommentDisplayNameRequest`. Use `mkCreateComment` / `mkReplyComment`
* `createComment` returns `CommentResponse` (full or partial comment) instead of `CommentObject`
* `Methods` and the effectful `Notion` GADT gain fields/constructors: `retrieveComment`, `updateComment`, `deleteComment`, `createPageAsync`, `updatePageMarkdownAsync`, `retrieveAsyncTask`, `createMeetingNote`, `queryMeetingNotes`

### New Features
* Retrieve, update (rich text or Markdown) and delete comments; create comments with Markdown, discussion replies, file-upload attachments and display names
* New `Notion.V1.AsyncTasks` module: `AsyncTask`, `retrieveAsyncTask`, `waitForAsyncTask`, and `allow_async` page creation / markdown update via `createPageAsync` and `updatePageMarkdownAsync`
* New `Notion.V1.MeetingNotes` module: `createMeetingNote` and `queryMeetingNotes` with a typed filter and sort DSL
```

Do not change the version in `notion-client.cabal`; the MasterPlan bumps it once at the end.


## Concrete Steps

All commands run from the repository root (the directory containing `cabal.project`).

Before starting, confirm the starting state builds and record the passing test count:

```bash
cabal build all
cabal test 2>&1 | tail -5
```

Expected tail (the count grows as other plans land):

```text
All 1xx tests passed (x.xxs)
Test suite tasty: PASS
```

Check whether EP-2's error code type exists yet, and whether EP-1/EP-6 typed the meeting-notes payload, so you know which fallback to use:

```bash
grep -n "APIErrorCode" src/Notion/V1/Error.hs
grep -n "MeetingNotesContent\|meetingTitle" src/Notion/V1/BlockContent.hs
```

If the first prints a `data APIErrorCode` line, use it for `AsyncTaskError.code` (and its `FromJSON`) and record that in the Decision Log. If the second shows a typed payload type rather than `meetingTitle :: Text`, reuse that type in `MeetingNoteBlock.meetingNotes` and record it.

### Registering test modules

Edit `notion-client.cabal`, stanza `test-suite tasty`, adding after `main-is: Main.hs` (add only the modules that exist so far; add the rest in their milestones):

```cabal
  other-modules:
    AsyncTaskTests
    CommentTests
    MeetingNotesTests
```

In `tasty/Main.hs`, add `import CommentTests qualified` (and later the other two) with the other imports, and add `CommentTests.tests,` (and later `AsyncTaskTests.tests,` and `MeetingNotesTests.tests,`) to the top-level list right after `fileUploadTests,`.

Each test module has this skeleton:

```haskell
module CommentTests (tests) where

import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy.Char8 qualified as L8
import Notion.V1.Comments
import Notion.V1.Common (Parent (..), UUID (..))
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Comment mutation (EP-3)"
    [ testCase "CommentResponse decodes a full comment" testFullComment,
      ...
    ]
```

### Milestone 1 tests (`tasty/CommentTests.hs`)

Write these test cases, each comparing `Aeson.toJSON request` with a JSON literal decoded by `Aeson.decode` (compare `Value`s, not strings, so key order does not matter), or decoding a fixture and pattern-matching:

1. "CommentResponse decodes a full comment" using the fixture below; assert `FullComment`, the id, and that `displayName` has `resolvedName = Just "Tanaka Hanako"`.
2. "CommentResponse decodes a partial comment" from `{"object":"comment","id":"2b0c5f7e-0000-4000-8000-000000000002"}`; assert `PartialComment (UUID "2b0c5f7e-0000-4000-8000-000000000002")`.
3. "CommentResponse with parent but missing fields fails" from `{"object":"comment","id":"x","parent":{"type":"page_id","page_id":"p"}}`; assert `Aeson.eitherDecode` returns `Left`.
4. "CreateComment on a page with rich text": `mkCreateComment (PageParent (UUID "p-1")) (CommentRichText (mkRichText "Hello"))` encodes with `parent` and `rich_text` keys and no `discussion_id`, `markdown`, `attachments` or `display_name`.
5. "CreateComment reply with Markdown": `mkReplyComment (UUID "d-1") (CommentMarkdown "**Hi**")` encodes to exactly `{"discussion_id":"d-1","markdown":"**Hi**"}`.
6. "CreateComment attachments and custom display name": encodes `attachments` to `[{"file_upload_id":"fu-1","type":"file_upload"}]` and `display_name` to `{"type":"custom","custom":{"name":"Sato Kenji"}}`.
7. "Display name integration and user": `DisplayAsIntegration` encodes to `{"type":"integration"}`, `DisplayAsUser` to `{"type":"user"}`.
8. "Update comment body": `CommentMarkdown "edited"` encodes to `{"markdown":"edited"}`; `CommentRichText (mkRichText "x")` encodes to an object whose only key is `rich_text`.

Full comment fixture (transcribed from `CommentObjectResponse`):

```json
{
  "object": "comment",
  "id": "2b0c5f7e-0000-4000-8000-000000000001",
  "parent": { "type": "page_id", "page_id": "5c6a2821-0000-4000-8000-00000000000a" },
  "discussion_id": "f1d2d2f9-0000-4000-8000-00000000000b",
  "created_time": "2026-09-14T10:00:00.000Z",
  "last_edited_time": "2026-09-14T10:05:00.000Z",
  "created_by": { "object": "user", "id": "9a8b7c6d-0000-4000-8000-00000000000c" },
  "rich_text": [
    {
      "type": "text",
      "text": { "content": "Looks good", "link": null },
      "annotations": { "bold": false, "italic": false, "strikethrough": false, "underline": false, "code": false, "color": "default" },
      "plain_text": "Looks good",
      "href": null
    }
  ],
  "display_name": { "type": "user", "resolved_name": "Tanaka Hanako" },
  "attachments": [
    { "category": "image", "file": { "url": "https://example.com/a.png", "expiry_time": "2026-09-14T11:00:00.000Z" } }
  ]
}
```

Build and test:

```bash
cabal build all
cabal test --test-show-details=direct 2>&1 | grep -A12 "Comment mutation"
```

Expected:

```text
    Comment mutation (EP-3)
      CommentResponse decodes a full comment:              OK
      CommentResponse decodes a partial comment:           OK
      CommentResponse with parent but missing fields fails: OK
      CreateComment on a page with rich text:              OK
      CreateComment reply with Markdown:                   OK
      CreateComment attachments and custom display name:   OK
      Display name integration and user:                   OK
      Update comment body:                                 OK
```

The pre-existing "CommentAttachment decodes read-side shape" and "CommentDisplayName captures resolved_name" tests must still print `OK`.

Commit (the hook may reformat; re-stage and re-run the commit if so):

```bash
git add -A src/Notion/V1/Comments.hs src/Notion/V1.hs notion-client-effectful tasty notion-client.cabal notion-client-example CHANGELOG.md
git commit
```

Commit message example:

```text
feat(comments): add retrieve, update and delete comment endpoints

Add CommentResponse (full or partial), CommentContent (rich text or
Markdown) and CommentTarget (parent or discussion). Restructure
CreateComment to accept only request shapes Notion accepts, with
request-only attachment and display-name types. Mirror the new Methods
fields in notion-client-effectful.

BREAKING CHANGE: CreateComment fields changed; createComment returns
CommentResponse.

MasterPlan: docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md
ExecPlan: docs/plans/8-add-comment-mutation-async-task-and-meeting-notes-endpoints.md
```

### Milestone 2 tests (`tasty/AsyncTaskTests.hs`)

Fixtures (transcribed from `GetAsyncTaskResponse`):

```json
{
  "object": "async_task",
  "id": "task_01",
  "status_url": "https://api.notion.com/v1/async_tasks/task_01",
  "created_time": "2026-09-14T10:00:00.000Z",
  "operation": { "surface": "rest", "name": "pages.create" },
  "status": "running",
  "poll_after_seconds": 2
}
```

```json
{
  "object": "async_task",
  "id": "task_02",
  "status_url": "https://api.notion.com/v1/async_tasks/task_02",
  "created_time": "2026-09-14T10:00:00.000Z",
  "operation": { "surface": "mcp", "name": "pages.update_markdown" },
  "status": "failed",
  "error": {
    "object": "error",
    "status": 400,
    "code": "validation_error",
    "message": "markdown is required",
    "additional_data": { "field": ["markdown"] }
  }
}
```

The operation `name` values in these fixtures are illustrative; the JS type only says `string`.

Test cases:

1. "Decode running task": `AsyncTaskRunning 2.0`, `SurfaceRest`, `name = "pages.create"`.
2. "Decode succeeded task": the first fixture with `"status":"succeeded"`, no `poll_after_seconds`, and `"result":{"page_id":"5c6a2821-0000-4000-8000-00000000000a"}`; assert `AsyncTaskSucceeded` whose object has key `page_id`.
3. "Decode failed task": the second fixture; assert `AsyncTaskFailed` with `status = 400`, `code = "validation_error"`, `additionalData` containing key `field`, and surface `SurfaceMcp`.
4. "Unknown status and surface are tolerated": `"status":"cancelled"` and `"surface":"cli"` decode to `UnknownAsyncTaskStatus "cancelled"` and `UnknownSurface "cli"`.
5. "AsyncTask round-trips": `Aeson.decode (Aeson.encode task)` reproduces the same `show` output for each decoded fixture.
6. "AsyncOr picks async_task": decoding the running fixture as `AsyncOr Aeson.Value` gives `AcceptedAsync`; decoding `{"object":"page","id":"p"}` gives `CompletedSync`.
7. "AllowAsync adds the flag": `Aeson.toJSON (AllowAsync (ReplaceContent (ReplaceContentRequest "new" Nothing)))` equals `{"type":"replace_content","replace_content":{"new_str":"new"},"allow_async":true}`.
8. "waitForAsyncTask polls until terminal": create an `IORef` holding a list `[runningTask 0, succeededTask]` where `runningTask 0` has `poll_after_seconds = 0`; the fake retrieve pops the head and counts calls. Starting from `runningTask 0`, assert the result is `AsyncTaskSucceeded` and the fake was called twice.
9. "waitForAsyncTask stops at maxAttempts": a fake that always returns a running task with `poll_after_seconds = 0` and `WaitOptions {maxAttempts = 3, maxPollSeconds = 1}`; assert the result is not terminal and the fake was called 3 times.

Build, test and commit as in Milestone 1 (commit type `feat(async-tasks)`, same trailers). Expected output lists nine `OK` lines under `Async tasks (EP-3)`.

### Milestone 3 tests (`tasty/MeetingNotesTests.hs`, create part)

Meeting-note block fixture:

```json
{
  "object": "block",
  "id": "7e3f0a1b-0000-4000-8000-000000000101",
  "type": "meeting_notes",
  "meeting_notes": {
    "title": [
      {
        "type": "text",
        "text": { "content": "Weekly sync", "link": null },
        "annotations": { "bold": false, "italic": false, "strikethrough": false, "underline": false, "code": false, "color": "default" },
        "plain_text": "Weekly sync",
        "href": null
      }
    ],
    "status": "notes_ready",
    "children": {
      "summary_block_id": "7e3f0a1b-0000-4000-8000-000000000102",
      "notes_block_id": "7e3f0a1b-0000-4000-8000-000000000103",
      "transcript_block_id": "7e3f0a1b-0000-4000-8000-000000000104"
    },
    "calendar_event": {
      "start_time": "2026-09-14T09:00:00.000+09:00",
      "end_time": "2026-09-14T09:30:00.000+09:00",
      "attendees": ["9a8b7c6d-0000-4000-8000-00000000000c"]
    },
    "recording": { "start_time": "2026-09-14T09:01:00.000+09:00" }
  },
  "created_time": "2026-09-14T00:00:00.000Z",
  "last_edited_time": "2026-09-14T00:40:00.000Z",
  "created_by": { "object": "user", "id": "9a8b7c6d-0000-4000-8000-00000000000c" },
  "last_edited_by": { "object": "user", "id": "9a8b7c6d-0000-4000-8000-00000000000c" },
  "has_children": true,
  "in_trash": false,
  "archived": false
}
```

Test cases:

1. "Decode full meeting note block": `CreateMeetingNoteResponse` is `FullMeetingNote`; `contentStatus = Just NotesReady`; the first `plainText` of `contentTitle` is `"Weekly sync"`; `calendarAttendees` of `contentCalendarEvent` has one element.
2. "Decode partial create response": `{"object":"block","id":"7e3f0a1b-0000-4000-8000-000000000101"}` gives `PartialMeetingNote`.
3. "Unknown meeting-notes status is tolerated": `"status":"archiving"` decodes to `UnknownMeetingNotesStatus "archiving"`; `"transcription_failed"` decodes to `TranscriptionFailed`.
4. "Minimal payload decodes": a block whose `meeting_notes` is `{}` decodes with every content field `Nothing`.
5. "CreateMeetingNote from file upload": `(mkCreateMeetingNote (FromFileUpload (UUID "a02fc1d3-db8b-45c5-a222-27595b15aea7") (UUID "c02fc1d3-db8b-45c5-a222-27595b15aea7"))) {title = Just "Weekly sync", language = Just LanguageEn, kickoffSummary = Just True}` encodes to exactly the body the JS SDK test expects:

```json
{
  "source": { "type": "file_upload", "file_upload_id": "a02fc1d3-db8b-45c5-a222-27595b15aea7" },
  "parent": { "type": "page_id", "page_id": "c02fc1d3-db8b-45c5-a222-27595b15aea7" },
  "title": "Weekly sync",
  "language": "en",
  "options": { "kickoff_summary": true }
}
```

6. "CreateMeetingNote from block has no parent": `mkCreateMeetingNote (FromBlock (UUID "b-1"))` encodes to exactly `{"source":{"type":"block","block_id":"b-1"}}`.
7. "Language codes": `LanguageZhCN`, `LanguageZhTW`, `LanguageNo` and `LanguageOther "tl"` encode to `"zh-CN"`, `"zh-TW"`, `"no"` and `"tl"`.

Build, test and commit (`feat(meeting-notes): add create meeting note endpoint`, same trailers).

### Milestone 4 tests (`tasty/MeetingNotesTests.hs`, query part)

1. "Empty query encodes to {}": `Aeson.toJSON emptyQueryMeetingNotes == Aeson.object []`.
2. "Attendees filter matches the JS SDK test": `emptyQueryMeetingNotes {filter = Just (mnAnd [mnAttendeesInclude (UUID "a1b2c3d4-e5f6-7890-abcd-ef1234567890")])}` encodes to:

```json
{
  "filter": {
    "operator": "and",
    "filters": [
      {
        "property": "attendees",
        "filter": {
          "operator": "person_contains",
          "value": [ { "type": "exact", "value": { "table": "notion_user", "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890" } } ]
        }
      }
    ]
  }
}
```

3. "Nested combinators, title and date point": `mnOr [mnTitleContains "standup", MNNested (mnAnd [MNProperty (MNCreatedTime (MNDateIsOnOrAfter (MeetingNotesDatePoint MNExact (MNDatePointSpec (MeetingNotesDateSpec True "2026-09-01" (Just "09:30") (Just "Asia/Tokyo")))))), MNProperty (MNTitle MNTextIsNotEmpty)])]` encodes with `{"type":"datetime","start_date":"2026-09-01","start_time":"09:30","time_zone":"Asia/Tokyo"}` inside `value.value`, and the empty check has no `value` key.
4. "Date range condition": `MNLastEditedTime (MNDateIsWithin (MeetingNotesDateRange MNRelative (MNDateRangeText "custom") (Just MNPast) (Just MNWeek) (Just 2)))` encodes `value` to `{"type":"relative","value":"custom","direction":"past","unit":"week","count":2}`, and `mnCreatedWithinPast 1 MNYear` encodes its `filter` to `{"operator":"date_is_within","value":{"type":"relative","value":"custom","direction":"past","unit":"year","count":1}}`; with `MNDateRangeSpec "2026-09-01" Nothing` and the three optionals `Nothing`, `value` is `{"type":"exact","value":{"type":"daterange","start_date":"2026-09-01"}}`.
5. "Sort and limit": `[MeetingNotesSort MNPropCreatedTime Descending]` with `limit = Just 10` encodes to `"sort":[{"property":"created_time","direction":"descending"}],"limit":10`.
6. "Raw node passes through": `MNRawNode (Aeson.object ["property" .= ("title" :: Text)])` appears verbatim in `filters`.
7. "Decode query response": `{"results":[<block fixture>],"has_more":false}` decodes to one result and `hasMore = False`.

Build, test and commit (`feat(meeting-notes): add meeting notes query with typed filters`, same trailers).


## Validation and Acceptance

Run from the repository root:

```bash
cabal build all
cabal test --test-show-details=direct
```

Acceptance:

- `cabal build all` succeeds for both `notion-client` and `notion-client-effectful`, and the build log contains no `-Wincomplete-patterns` warning from `notion-client-effectful/src/Notion/V1/Effectful/Interpreter.hs` and no `-Wmissing-fields` warning from the files this plan edits.
- The test output contains the groups `Comment mutation (EP-3)` (8 tests), `Async tasks (EP-3)` (9 tests) and `Meeting notes (EP-3)` (14 tests), all `OK`, and ends with `All N tests passed` where N is the starting count plus 31. The pre-existing comment-attachment and display-name tests still pass.
- Every new endpoint is reachable from `Methods`: in `cabal repl notion-client`, `:t retrieveComment`, `:t updateComment`, `:t deleteComment`, `:t retrieveAsyncTask`, `:t createPageAsync`, `:t updatePageMarkdownAsync`, `:t createMeetingNote` and `:t queryMeetingNotes` (after `import Notion.V1`) print `Methods -> ...` types matching Interfaces and Dependencies below.

Live checks (optional; they need a Notion integration token with read, insert and update comment capabilities):

With `NOTION_TOKEN` and `NOTION_TEST_PAGE_ID` exported, `cabal test` runs `Page E2E` → "Create page, add comments, list comments, and clean up", which after Milestone 1 also retrieves, edits (Markdown) and deletes a comment. Expect `OK`. If Notion returns partial comments for your integration, the test still passes and you should record that in Surprises & Discoveries.

Meeting-notes query and async page creation from GHCi:

```bash
cabal repl notion-client
```

```haskell
:set -XOverloadedStrings -XOverloadedRecordDot
import Notion.V1
import Notion.V1.MeetingNotes
import Notion.V1.AsyncTasks
import Notion.V1.Pages
import Notion.V1.Common
import qualified Data.Map as Map
import qualified Data.Text as T
import System.Environment
token <- T.pack <$> getEnv "NOTION_TOKEN"
env <- getClientEnv "https://api.notion.com/v1"
let m = makeMethods env token
r <- queryMeetingNotes m emptyQueryMeetingNotes { limit = Just 5, sort = Just [MeetingNotesSort MNPropCreatedTime Descending] }
length r.results
r.hasMore
parentId <- UUID . T.pack <$> getEnv "NOTION_TEST_PAGE_ID"
let req = CreatePage { parent = PageParent parentId, properties = Map.empty, children = Nothing, markdown = Just "# Async test\n\nHello from Sato Kenji.", icon = Nothing, cover = Nothing, template = Nothing, position = Nothing }
res <- createPageAsync m req
case res of { AcceptedAsync t -> print =<< waitForAsyncTask defaultWaitOptions (retrieveAsyncTask m) t; CompletedSync p -> putStrLn ("completed synchronously: " <> show p.id) }
```

Observe: the query returns without a decoding error (an empty workspace yields `0` and `False`); the async create prints either a terminal `AsyncTask` whose status is `AsyncTaskSucceeded` with a result object, or "completed synchronously" (Notion decides whether to run the job in the background). Record the observed `result` keys and `operation.name` in Surprises & Discoveries, then trash the created page in the Notion UI. The `CreatePage` value is written out in full rather than as a record update of `mkCreatePage`, because `markdown` is a field of both `CreatePage` and `PageMarkdown` and GHC rejects an ambiguous record update. If `CreatePage` has gained fields from another plan by the time you run this, add them with `Nothing`.


## Idempotence and Recovery

All edits are additive source changes plus one restructuring of `CreateComment`; re-running the build and tests is always safe. If a milestone is half done and the build is broken, `git stash` or `git checkout -- <file>` returns to the last green commit, since each milestone ends with a commit. The `makeMethods` pattern is the most error-prone edit: if GHC reports a large type mismatch there, compare the nesting of the pattern with the top-level `API` alternative by alternative; a missing or extra `:<|>` is the usual cause. If another plan (EP-1, EP-2, EP-4, EP-5, EP-6) has appended to the top-level `API` or `Methods` in the meantime, rebase and keep both sets of additions, preserving the order in `API` and pattern. The live tests create a page under `NOTION_TEST_PAGE_ID` and trash it at the end; if a run aborts midway, trash the leftover "Comment Test" or "Async test" page manually. Meeting-note creation is not exercised live because it consumes a real recording and cannot be undone except by deleting the block.


## Interfaces and Dependencies

No new package dependencies. The library already depends on `aeson` (JSON, `Data.Aeson.KeyMap`), `servant` and `servant-client` (routes and client generation), `time` (timestamps) and `base` (`Control.Concurrent.threadDelay`, `Control.Monad.IO.Class`). The effectful package already depends on `effectful`.

At the end of Milestone 1, `Notion.V1.Comments` exports, in addition to its existing names: `CommentResponse (..)`, `commentResponseId :: CommentResponse -> CommentID`, `commentResponseObject :: CommentResponse -> Maybe CommentObject`, `CommentTarget (..)`, `CommentContent (..)`, `CommentAttachmentRequest (..)`, `CommentDisplayNameRequest (..)`, the restructured `CreateComment (..)`, `mkCreateComment :: Parent -> CommentContent -> CreateComment` and `mkReplyComment :: UUID -> CommentContent -> CreateComment`. `Notion.V1.Methods` has:

```haskell
createComment :: Comments.CreateComment -> IO CommentResponse
retrieveComment :: Comments.CommentID -> IO CommentResponse
updateComment :: Comments.CommentID -> CommentContent -> IO CommentResponse
deleteComment :: Comments.CommentID -> IO CommentResponse
```

At the end of Milestone 2, `Notion.V1.AsyncTasks` exports `AsyncTaskID`, `AsyncTask (..)`, `AsyncTaskOperation (..)`, `AsyncTaskSurface (..)`, `AsyncTaskStatus (..)`, `AsyncTaskError (..)` (whose `code` is `Notion.V1.Error.APIErrorCode`), `AsyncOr (..)`, `AllowAsync (..)`, `AsyncVerb`, `AsyncStatuses`, `fromAsyncUnion`, `WaitOptions (..)`, `defaultWaitOptions`, `isTerminal`, `pollAfterSeconds`, `waitForAsyncTask` and `API`. `Methods` has:

```haskell
createPageAsync :: CreatePage -> IO (AsyncOr PageObject)
updatePageMarkdownAsync :: PageID -> UpdatePageMarkdown -> IO (AsyncOr PageMarkdown)
retrieveAsyncTask :: AsyncTaskID -> IO AsyncTask
```

and `waitForAsyncTask :: MonadIO m => WaitOptions -> (AsyncTaskID -> m AsyncTask) -> AsyncTask -> m AsyncTask`. `docs/masterplans/2-add-the-custom-agents-and-sessions-api-with-sse-streaming.md` consumes `AsyncTask`, `retrieveAsyncTask` and `waitForAsyncTask` for `agents.batch`; do not rename them without updating that MasterPlan.

At the end of Milestone 3, `Notion.V1.MeetingNotes` exports `MeetingNotesContent (..)` (re-using EP-1's `MeetingNotesStatus`, `MeetingNotesChildren`, `MeetingCalendarEvent` and `MeetingRecording` from `Notion.V1.BlockContent`), `MeetingNoteBlock (..)`, `MeetingNoteLanguage (..)`, `MeetingNoteSource (..)`, `CreateMeetingNote (..)`, `mkCreateMeetingNote`, `CreateMeetingNoteResponse (..)` and `API`, and `Methods` has `createMeetingNote :: MeetingNotes.CreateMeetingNote -> IO MeetingNotes.CreateMeetingNoteResponse`.

At the end of Milestone 4, `Notion.V1.MeetingNotes` additionally exports `MeetingNotesFilter (..)`, `MeetingNotesCombinator (..)`, `MeetingNotesFilterNode (..)`, `MeetingNotesPropertyFilter (..)`, `MeetingNotesTextCondition (..)`, `MeetingNotesDateCondition (..)`, `MeetingNotesPersonCondition (..)`, `MeetingNotesDateValueType (..)`, `MeetingNotesDatePoint (..)`, `MeetingNotesDatePointValue (..)`, `MeetingNotesDateSpec (..)`, `MeetingNotesDateRange (..)`, `MeetingNotesDateRangeValue (..)`, `MeetingNotesDirection (..)`, `MeetingNotesDateUnit (..)`, `MeetingNotesProperty (..)`, `MeetingNotesSort (..)`, `QueryMeetingNotes (..)`, `emptyQueryMeetingNotes`, `QueryMeetingNotesResponse (..)`, `mnAnd`, `mnOr`, `mnTitleContains`, `mnAttendeesInclude`, `mnCreatedOnOrAfter` and `mnCreatedWithinPast`, and `Methods` has `queryMeetingNotes :: MeetingNotes.QueryMeetingNotes -> IO MeetingNotes.QueryMeetingNotesResponse`.

Top-level `Notion.V1.API` ends with `... :<|> FileUploads.API :<|> AsyncTasks.API :<|> MeetingNotes.API` (plus whatever other plans append). Every `Methods` field above has a same-named smart constructor, a PascalCase `Notion` GADT constructor and an interpreter case in `notion-client-effectful`.

Integration with sibling plans: EP-2 (`docs/plans/7-add-a-configurable-client-runtime-with-retries-typed-error-codes-and-oauth.md`) may replace `AsyncTaskError.code :: Text` with `APIErrorCode`; whichever lands second makes that switch. EP-1 (`docs/plans/6-fix-wire-format-decoding-and-encoding-bugs-found-against-the-official-sdk.md`) and EP-6 (`docs/plans/11-close-page-block-property-value-user-file-upload-and-webhook-field-gaps.md`) should make `BlockContent`'s `MeetingNotesBlock` reuse `Notion.V1.MeetingNotes.MeetingNotesContent` rather than define a second payload type; `MeetingNotes.hs` deliberately imports nothing from `Blocks` or `BlockContent` so that this is possible. EP-6 may type webhook `file_import_result` data with `AsyncTask`.
