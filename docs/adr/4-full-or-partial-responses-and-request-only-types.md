# ADR 4: Full-or-partial responses are sum types, and request shapes get their own types

Status: Accepted
Date: 2026-09-15


## Context

The official JS SDK types many mutation responses as `Partial<X>ObjectResponse | <X>ObjectResponse`.
The partial shape is only `{object, id}`. A Haskell decoder that requires the full object's
fields fails on a partial response, so the whole call fails even though it succeeded.

Several Notion objects also have request shapes that share little with their response shapes.
A comment attachment is read as `{category, file}` but sent as `{file_upload_id, type}`. A comment
display name is read with `resolved_name` but sent as `{type: "custom", custom: {name}}`.
A comment is created with either `parent` or `discussion_id`, and with either `rich_text` or
`markdown`. Reusing one record for both directions, or one record with independent optional
fields, lets callers build requests Notion rejects. It also forces read-side decoders to
accept write-side shapes.

`docs/plans/8-add-comment-mutation-async-task-and-meeting-notes-endpoints.md` settled both
questions for comments and meeting notes.


## Decision

- **Partial responses.** When an endpoint may return a partial object, its result is a sum type
  with a full and a partial constructor, for example `CommentResponse = FullComment CommentObject | PartialComment CommentID`
  and `CreateMeetingNoteResponse = FullMeetingNote MeetingNoteBlock | PartialMeetingNote BlockID`.
  - **Decoding.** The decoder picks the full constructor when a key that only the full shape has
    is present (`parent`, `meeting_notes`). A full-looking response with missing fields then
    fails loudly instead of silently becoming partial.
  - **List endpoints.** They keep the plain full type when the JS SDK declares only full objects,
    so the read path is not weakened for everyone.
  - **Helpers.** Small functions such as `commentResponseId` and `commentResponseObject` cover
    the common access patterns.
- **Result unions.** Query and search results mix several object kinds, and each kind may be full
  or partial. They decode into one union, `PageOrDataSource`: `PageResult`, `PartialPageResult`,
  `DataSourceResult`, `PartialDataSourceResult`, and `UnknownResult Value` for unknown `object`
  values. It was added on 2026-09-15 by `docs/plans/10-type-data-source-database-and-search-results-and-close-query-and-filter-gaps.md`.
  - **Discriminators.** A page is full when it has `url`, and a data source is full when it has
    `title`. These match the JS SDK's `isFullPage`/`isFullDataSource`.
  - **Helpers.** `pageResults`, `dataSourceResults`, `resultId` and `resultCreatedTime` cover
    callers that want one kind.
  - **Single-object endpoints.** `retrieveDataSource`, `updateDatabase` and the rest keep their
    full return types, even though the JS SDK types them as full-or-partial. The integration always
    sees the object it addressed. The partial types are still exported for manual decoding.
- **Request shapes.** A request whose shape differs from the response gets its own request-only
  type (`CommentAttachmentRequest`, `CommentDisplayNameRequest`, `CreateMeetingNote`). Read-side
  types and their tolerant decoders stay unchanged.
- **Mutually exclusive fields.** Such request fields become small sum types (`CommentTarget`,
  `CommentContent`, `MeetingNoteSource`) instead of independent `Maybe` fields. Smart
  constructors (`mkCreateComment`, `mkReplyComment`, `mkCreateMeetingNote`) keep call sites short.
- **Enums.** Request-only enums need no unknown fallback for decoding. They may offer an escape
  constructor carrying raw text (for example `LanguageOther Text`). Filter DSLs may offer a raw
  JSON node (`MNRawNode Value`).


## Consequences

- Adopting this for an existing request record is a breaking change, as it was for `CreateComment`.
- Callers must handle the partial case explicitly. Live checks so far (2026-09-15) always
  received full comments.
- The partial page, data source and database types (`PartialPageObject`, `PartialDataSourceObject`,
  `PartialDatabaseObject`) follow the same pattern. Later partial types for pages and blocks
  should reuse them.
