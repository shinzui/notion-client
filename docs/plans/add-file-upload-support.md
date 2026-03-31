# Add file upload support

Intention: intention_01kn25erjxe7crmsja6x666zf7

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, users of the notion-client library will be able to upload files to Notion
through the API — something previously impossible with this client. A user will be able to
create a file upload, send file content from disk, and then reference that upload in page
properties (files columns), block content (image, video, audio, file, and PDF blocks), page
icons, and page covers. The library will support all three upload modes that Notion offers:
single-part direct upload (files up to 20 MiB), multi-part direct upload (files up to 5 GiB
in chunks), and external URL import (Notion fetches a file from a public URL).

To verify the feature works, a user can run the example app with `cabal run notion-client-example`
and choose the file upload demo, which will create an upload, send a small file, and attach it
to an image block on a page — confirming the round trip from local file to Notion-rendered content.


## Progress

- [x] Create `src/Notion/V1/FileUploads.hs` with all types (2026-03-31)
- [x] Define the Servant API type for all five file upload endpoints (2026-03-31)
- [x] Write `ToMultipart Tmp` instance for `SendFileUpload` (2026-03-31)
- [x] Add `Notion.V1.FileUploads` to `notion-client.cabal` exposed-modules (2026-03-31)
- [x] Wire `FileUploads.API` into the composite `API` type in `src/Notion/V1.hs` (2026-03-31)
- [x] Add file upload methods to the `Methods` record in `src/Notion/V1.hs` (2026-03-31)
- [x] Destructure the new client functions in `makeMethods` and wrap `sendFileUploadContent` to hide boundary generation (2026-03-31)
- [x] Add `FileUploadFileValue` constructor to `FileValue` in `src/Notion/V1/PropertyValue.hs` (2026-03-31)
- [x] Add `FileUploadIcon` constructor to `Icon` in `src/Notion/V1/Common.hs` (2026-03-31)
- [x] Add `FileUploadCover` constructor to `Cover` in `src/Notion/V1/Common.hs` (2026-03-31)
- [x] Add unit tests for `FileUploadObject` JSON round-trip in `tasty/Main.hs` (2026-03-31)
- [x] Add unit tests for `CreateFileUpload` serialization (2026-03-31)
- [x] Add unit tests for updated `FileValue`, `Icon`, `Cover` with file_upload variant (2026-03-31)
- [x] Add `FileUploadDemo.hs` to `notion-client-example/` (2026-03-31)
- [x] Register `FileUploadDemo` in `notion-client-example/Main.hs` and `notion-client.cabal` (2026-03-31)
- [x] Verify `cabal build all` succeeds (2026-03-31)
- [x] Verify `cabal test` passes — 110 tests, all passing (2026-03-31)


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Use `Tmp` (file-path based) for the `ToMultipart` instance, not `Mem` (in-memory bytestring).
  Rationale: The library already imports and re-exports `Tmp` from the Prelude. File-path streaming
  is the natural fit for a client library — users have files on disk. `Mem` support can be added
  later if needed. Using `Tmp` means the servant-multipart-client library handles file streaming
  automatically.
  Date: 2026-03-31

- Decision: Hide multipart boundary generation inside the `Methods` wrapper.
  Rationale: The raw Servant client for a `MultipartForm Tmp a` endpoint takes
  `(LBS.ByteString, a)` where the `ByteString` is the multipart boundary. This is an implementation
  detail that users should not need to manage. The `Methods` record will expose a simpler
  `sendFileUploadContent :: FileUploadID -> SendFileUpload -> IO FileUploadObject` that calls
  `genBoundary` internally.
  Date: 2026-03-31

- Decision: Add `file_upload` variant to `FileValue`, `Icon`, and `Cover` types as part of this plan.
  Rationale: Without these, users cannot reference file uploads in page properties, page icons, or
  page covers — which are primary use cases for the file upload API. These are small, targeted
  additions that complete the file upload story.
  Date: 2026-03-31

- Decision: Scope the plan to the five CRUD/operational endpoints and exclude webhook-related file events.
  Rationale: Webhook types are receive-only and do not need file upload support. The existing
  `FileUploadSource UUID` in `BlockContent.hs` already handles referencing uploads in blocks, so
  blocks need no changes.
  Date: 2026-03-31


## Outcomes & Retrospective

All four milestones completed in a single session. The implementation adds:

- New `Notion.V1.FileUploads` module with 6 types, 4 smart constructors, a `ToMultipart Tmp`
  instance, and a Servant API covering all 5 file upload endpoints.
- 5 new methods in the `Methods` record (`createFileUpload`, `retrieveFileUpload`,
  `sendFileUploadContent`, `completeFileUpload`, `listFileUploads`).
- `file_upload` variant added to `FileValue`, `Icon`, and `Cover` for referencing uploads
  in page properties, page icons, and page covers.
- 9 new unit tests (110 total, all passing).
- `FileUploadDemo` example module.

No surprises encountered. The existing servant-multipart infrastructure was well-prepared —
all needed imports and dependencies were already in place.


## Context and Orientation

This section describes the state of the repository relevant to file upload support. It is written
for a reader who has never seen this codebase.

The project is a Haskell library at the repository root that provides a type-safe client for the
Notion API. It uses the Servant library for defining API types and generating HTTP client functions.
The build tool is Cabal; the project file is `notion-client.cabal`. The Haskell language standard
is GHC2024 with GHC 9.12.2.

**Module layout.** All library source code lives under `src/`. The main entry point is
`src/Notion/V1.hs`, which assembles all endpoint modules into a single Servant `API` type and
exposes a `Methods` record of ready-to-call `IO` functions. Each Notion resource has its own
module: `Blocks.hs`, `Pages.hs`, `Databases.hs`, `DataSources.hs`, `Comments.hs`, `Users.hs`,
`Search.hs`, `Views.hs`, `CustomEmojis.hs`, and `Webhooks.hs`. Shared types live in
`Common.hs`, `RichText.hs`, `Properties.hs`, `PropertyValue.hs`, `BlockContent.hs`, `Filter.hs`,
`ListOf.hs`, `Pagination.hs`, and `Error.hs`. A prelude module `src/Notion/Prelude.hs` re-exports
common dependencies.

**How a resource module is structured.** Each module (e.g., `src/Notion/V1/Comments.hs`) defines:
(1) data types for the API objects and request/response bodies, (2) `FromJSON`/`ToJSON` instances
for those types, and (3) a `type API = ...` Servant API type that describes the HTTP endpoints.
The module exports its types and the `API` type.

**How V1.hs assembles everything.** In `src/Notion/V1.hs`, the top-level `type API` combines all
sub-module API types with `:<|>`. The `makeMethods` function calls `Client.client @API Proxy` to
generate one large client function, then pattern-matches its result into individual functions using
`:<|>`. Each function is stored in the `Methods` record. A `run` helper wraps `ClientM a -> IO a`
with error handling, and `hoistClient` applies this wrapping to the entire client.

**Multipart support is already wired in.** The `notion-client.cabal` file declares dependencies
on `servant-multipart-api >=0.12 && <0.13` and `servant-multipart-client >=0.12 && <0.13`. The
prelude (`src/Notion/Prelude.hs`) re-exports `FileData(..)`, `Input(..)`, `MultipartData(..)`,
`MultipartForm`, `Tmp`, and `ToMultipart(..)` from `Servant.Multipart.API`. The entry point
(`src/Notion/V1.hs`) imports `Servant.Multipart.Client ()` which brings the `HasClient` instance
into scope — this is the orphan instance that tells Servant how to generate client functions for
`MultipartForm` endpoints. No existing endpoint uses multipart yet; these imports are preparatory.

**Existing file-related types.** The `FileSource` type in `src/Notion/V1/BlockContent.hs` has
three constructors: `ExternalSource ExternalFile` (external URL), `NotionSource File`
(Notion-hosted with expiring URL), and `FileUploadSource UUID` (reference to an API-uploaded file
by its ID). This means block content (images, videos, files, etc.) can already *reference* file
uploads. What is missing is the ability to *create* file uploads.

The `FileValue` type in `src/Notion/V1/PropertyValue.hs` has two constructors:
`InternalFileValue` and `ExternalFileValue`. It is missing a `FileUploadValue` variant for
referencing uploads in page properties (files columns).

The `Icon` and `Cover` types in `src/Notion/V1/Common.hs` have `FileIcon`/`ExternalIcon` and
`FileCover`/`ExternalCover` variants but lack a `FileUploadIcon`/`FileUploadCover` variant.

**The Notion File Upload API.** The Notion API (version 2026-03-11) exposes five endpoints under
`/v1/file_uploads`:

1. `POST /v1/file_uploads` — Create a file upload. Takes a JSON body with `mode` (one of
   `"single_part"`, `"multi_part"`, or `"external_url"`), optional `filename`, optional
   `content_type`, optional `number_of_parts` (required for multi-part), and optional
   `external_url` (required for external_url mode). Returns a `file_upload` object.

2. `POST /v1/file_uploads/{file_upload_id}/send` — Send file content. Uses
   `multipart/form-data` with a `file` field (binary) and optional `part_number` field (for
   multi-part uploads). Returns the updated `file_upload` object.

3. `POST /v1/file_uploads/{file_upload_id}/complete` — Finalize a multi-part upload. No request
   body. Returns the updated `file_upload` object.

4. `GET /v1/file_uploads/{file_upload_id}` — Retrieve a file upload by ID. Returns the
   `file_upload` object.

5. `GET /v1/file_uploads` — List file uploads. Accepts query parameters `status`, `start_cursor`,
   and `page_size`. Returns a `ListOf FileUploadObject`.

The `file_upload` object contains: `id` (UUID), `object` (always `"file_upload"`), `status`
(one of `"pending"`, `"uploaded"`, `"expired"`, `"failed"`), `filename` (nullable string),
`content_type` (nullable string), `content_length` (nullable integer), `created_time` (ISO 8601),
`last_edited_time` (ISO 8601), `created_by` (user reference with `id` and `type` fields),
`in_trash` (boolean), `expiry_time` (nullable ISO 8601), `number_of_parts` (object with `total`
and `sent` integer fields), and `file_import_result` (object with `imported_time`, `type`, and
either `success` or `error` details).

File size limits: free workspaces allow 5 MiB per file; paid workspaces allow up to 5 GiB.
Single-part uploads handle files up to 20 MiB. Multi-part uploads split larger files into parts
of 5–20 MiB each (maximum 10,000 parts). Uploaded files must be attached to a page, block, or
property within one hour or they expire.


## Plan of Work

The work is divided into four milestones. Each builds on the previous and is independently
verifiable.


### Milestone 1: FileUploads module with types and Servant API

This milestone creates the new `src/Notion/V1/FileUploads.hs` module containing all types needed
for the file upload API and the Servant API type definition. At the end of this milestone, the
module compiles and is registered in the cabal file, but is not yet wired into `V1.hs`.

**Types to define:**

`FileUploadID` is a type alias for `UUID`, following the pattern of `PageID`, `BlockID`, etc.

`FileUploadStatus` is a sum type with four constructors: `Pending`, `Uploaded`, `Expired`, and
`Failed`. It needs manual `FromJSON`/`ToJSON` instances that map to/from the snake_case strings
`"pending"`, `"uploaded"`, `"expired"`, and `"failed"`. It also needs a `ToHttpApiData` instance
so it can be used as a query parameter in the list endpoint.

`NumberOfParts` is a record with two fields: `total :: Natural` and `sent :: Natural`. It uses
generic JSON instances with `aesonOptions`.

`FileImportResult` is a sum type representing the outcome of a file import. It has two variants:
`FileImportSuccess` with an `importedTime` field (ISO 8601 timestamp as `POSIXTime`), and
`FileImportError` with fields `importedTime :: POSIXTime`, `errorType :: Text`,
`errorCode :: Text`, `errorMessage :: Text`, `errorParameter :: Maybe Text`, and
`errorStatusCode :: Maybe Int`. The JSON format uses a `type` discriminator with values
`"success"` and `"error"`.

`FileUploadObject` is the main response type. It is a record with fields: `id :: FileUploadID`,
`object :: Text`, `status :: FileUploadStatus`, `filename :: Maybe Text`,
`contentType :: Maybe Text`, `contentLength :: Maybe Natural`, `createdTime :: POSIXTime`,
`lastEditedTime :: POSIXTime`, `createdBy :: Value` (kept as raw JSON since the creator reference
has a simpler schema than `UserReference` — just `id` and `type`),
`inTrash :: Bool`, `expiryTime :: Maybe POSIXTime`, `numberOfParts :: Maybe NumberOfParts`,
`fileImportResult :: Maybe FileImportResult`. It needs a custom `FromJSON` instance because
timestamp fields need `parseISO8601`, and a generic-like `ToJSON`.

`CreateFileUpload` is the request body for the create endpoint. It has fields:
`mode :: Maybe Text` (defaults to `"single_part"` when omitted), `filename :: Maybe Text`,
`contentType_ :: Maybe Text` (field name `contentType_` maps to JSON key `content_type` —
note the trailing underscore is needed because `contentType` would collide with the field in
`FileUploadObject` due to `DuplicateRecordFields`, but actually with DuplicateRecordFields this
should be fine; use `contentType` directly), `numberOfParts :: Maybe Natural`
(for multi-part mode), and `externalUrl :: Maybe Text` (for external_url mode). Uses generic
`ToJSON` with `aesonOptions`.

`SendFileUpload` is the type used with the multipart send endpoint. It has fields:
`filePath :: FilePath` (path to the file on disk), `fileName :: Text` (the filename to send in
the multipart header), `fileContentType :: Text` (MIME type like `"image/png"`), and
`partNumber :: Maybe Natural` (for multi-part uploads). It needs a `ToMultipart Tmp` instance
that constructs a `MultipartData Tmp` with one `FileData` entry for the `"file"` field and an
optional `Input` entry for `"part_number"`.

**Servant API type.** The API type covers all five endpoints under `"file_uploads"`:

    type API =
      "file_uploads"
        :> ( ReqBody '[JSON] CreateFileUpload
               :> Post '[JSON] FileUploadObject
             :<|> Capture "file_upload_id" FileUploadID
               :> Get '[JSON] FileUploadObject
             :<|> Capture "file_upload_id" FileUploadID
               :> "send"
               :> MultipartForm Tmp SendFileUpload
               :> Post '[JSON] FileUploadObject
             :<|> Capture "file_upload_id" FileUploadID
               :> "complete"
               :> Post '[JSON] FileUploadObject
             :<|> QueryParam "status" FileUploadStatus
               :> QueryParam "start_cursor" Text
               :> QueryParam "page_size" Natural
               :> Get '[JSON] (ListOf FileUploadObject)
           )

Note that the list endpoint (`GET /v1/file_uploads`) and the create endpoint
(`POST /v1/file_uploads`) share the same path but different HTTP methods. The retrieve endpoint
(`GET /v1/file_uploads/{id}`) has a capture segment. The send endpoint uses `MultipartForm Tmp`
instead of `ReqBody`. The complete endpoint has no request body.

**Cabal registration.** Add `Notion.V1.FileUploads` to the `exposed-modules` list in
`notion-client.cabal`, alphabetically after `Notion.V1.Filter`.

**Smart constructors.** Provide three convenience functions for the most common `CreateFileUpload`
configurations:

    mkSinglePartUpload :: Maybe Text -> CreateFileUpload

Creates a single-part upload with an optional filename. All other fields are `Nothing`.

    mkMultiPartUpload :: Text -> Natural -> Maybe Text -> CreateFileUpload

Creates a multi-part upload with a required filename, required number of parts, and optional
content type.

    mkExternalUrlUpload :: Text -> Maybe Text -> CreateFileUpload

Creates an external URL import with the URL and optional filename.

Also provide:

    mkSendFileUpload :: FilePath -> Text -> Text -> SendFileUpload

Creates a `SendFileUpload` for a single-part upload (no part number) given a file path, filename,
and content type.

**Verification.** Run `cabal build all` from the repository root. It must compile without errors
or warnings (other than existing ones). The new module should appear in the build output.


### Milestone 2: Wire into V1.hs

This milestone integrates the file upload endpoints into the `Methods` record so users can call
them through the standard library interface. At the end of this milestone, all five file upload
operations are available as methods.

**Imports.** In `src/Notion/V1.hs`, add:

    import Notion.V1.FileUploads (FileUploadID, FileUploadObject, FileUploadStatus)
    import Notion.V1.FileUploads qualified as FileUploads
    import Servant.Multipart.Client (genBoundary)

The existing `import Servant.Multipart.Client ()` can be replaced with this explicit import
(or kept alongside it — either works since `genBoundary` re-establishes the orphan instance
import).

**API type.** Add `:<|> FileUploads.API` to the composite `type API` in `src/Notion/V1.hs`,
after `CustomEmojis.API`.

**Methods record.** Add these fields to the `Methods` record:

    -- \* File Uploads
    createFileUpload :: FileUploads.CreateFileUpload -> IO FileUploadObject,
    retrieveFileUpload :: FileUploadID -> IO FileUploadObject,
    sendFileUploadContent :: FileUploadID -> FileUploads.SendFileUpload -> IO FileUploadObject,
    completeFileUpload :: FileUploadID -> IO FileUploadObject,
    listFileUploads ::
      Maybe FileUploadStatus ->
      Maybe Text ->    -- start_cursor
      Maybe Natural -> -- page_size
      IO (ListOf FileUploadObject),

**Client destructuring.** In the `makeMethods` `where` clause, extend the pattern match to
include the new client functions. After the `:<|> listCustomEmojis_` line, add:

    :<|> ( createFileUpload
             :<|> retrieveFileUpload
             :<|> sendFileUploadContent_
             :<|> completeFileUpload
             :<|> listFileUploads_
           )

The multipart endpoint produces a client function with signature
`(ByteString, SendFileUpload) -> IO FileUploadObject`. We bind it to `sendFileUploadContent_`
(with trailing underscore) and wrap it:

    sendFileUploadContent fid upload = do
      boundary <- genBoundary
      sendFileUploadContent_ fid (boundary, upload)

    listFileUploads = listFileUploads_

**Verification.** Run `cabal build all`. The build must succeed. Then inspect the `Methods` record
in GHCi or via the compiler to confirm the new fields are present:

    cabal repl notion-client
    > :info Methods


### Milestone 3: Update existing types for file_upload references

This milestone adds `file_upload` as a recognized type variant in `FileValue` (page properties),
`Icon`, and `Cover`. These types can currently represent external URLs and Notion-hosted files
but cannot represent API-uploaded files referenced by ID.

**FileValue in `src/Notion/V1/PropertyValue.hs`.** Add a third constructor:

    data FileValue
      = InternalFileValue {name :: Text, file :: File}
      | ExternalFileValue {name :: Text, external :: ExternalFile}
      | FileUploadFileValue {name :: Text, fileUploadId :: UUID}

Update the `FromJSON` instance to handle `"file_upload"`:

    "file_upload" -> do
      uploadObj <- o .: "file_upload"
      uploadId <- uploadObj .: "id"
      pure (FileUploadFileValue n uploadId)

Update the `ToJSON` instance:

    toJSON (FileUploadFileValue n uid) =
      Aeson.object
        [ "type" .= ("file_upload" :: Text),
          "name" .= n,
          "file_upload" .= Aeson.object ["id" .= uid]
        ]

Add a smart constructor:

    fileUploadFilesValue :: [(Text, UUID)] -> PropertyValue

This takes a list of `(name, fileUploadId)` pairs and builds a `FilesValue`.

**Icon in `src/Notion/V1/Common.hs`.** Add a constructor:

    | FileUploadIcon {fileUploadId :: UUID}

Update `FromJSON`:

    "file_upload" -> do
      uploadObj <- o .: "file_upload"
      FileUploadIcon <$> uploadObj .: "id"

Update `ToJSON`:

    toJSON (FileUploadIcon uid) =
      object ["type" .= ("file_upload" :: Text), "file_upload" .= object ["id" .= uid]]

Export `FileUploadIcon` — it is already exported via `Icon(..)`.

**Cover in `src/Notion/V1/Common.hs`.** Add a constructor:

    | FileUploadCover {fileUploadId :: UUID}

Update `FromJSON`:

    "file_upload" -> do
      uploadObj <- o .: "file_upload"
      FileUploadCover <$> uploadObj .: "id"

Update `ToJSON`:

    toJSON (FileUploadCover uid) =
      object ["type" .= ("file_upload" :: Text), "file_upload" .= object ["id" .= uid]]

**Verification.** Run `cabal build all` and `cabal test`. The build must succeed and all existing
tests must pass. The new constructors should not break any existing JSON parsing because
`"file_upload"` is a new type discriminator value that was not handled before (it would previously
cause a parse failure).


### Milestone 4: Demo and tests

This milestone adds a demonstration executable and unit tests that exercise the new file upload
types.

**Unit tests in `tasty/Main.hs`.** Add test cases for:

1. `FileUploadObject` JSON round-trip: construct a `FileUploadObject` value, serialize it to
   JSON, deserialize it back, and verify equality. Test both `Pending` and `Uploaded` statuses.

2. `CreateFileUpload` serialization: verify that `mkSinglePartUpload`, `mkMultiPartUpload`, and
   `mkExternalUrlUpload` produce the expected JSON structure (check for correct keys and values).

3. `FileValue` with `file_upload` type: parse a JSON object with `"type": "file_upload"` and
   verify it produces `FileUploadFileValue`. Also test round-trip.

4. `Icon` with `file_upload` type: parse and verify `FileUploadIcon`.

5. `Cover` with `file_upload` type: parse and verify `FileUploadCover`.

6. `FileUploadStatus` `ToHttpApiData`: verify that `toQueryParam Pending` produces `"pending"`, etc.

**Demo in `notion-client-example/FileUploadDemo.hs`.** Create a demo module that:

1. Creates a single-part file upload using `createFileUpload (mkSinglePartUpload (Just "test.txt"))`.
2. Prints the returned `FileUploadObject` showing its `id` and `status`.
3. Sends file content using `sendFileUploadContent` with a small text file.
4. Retrieves the upload to confirm its status changed to `Uploaded`.
5. Lists file uploads to show the new upload appears.

Register the demo module in `notion-client-example/Main.hs` (add a menu option) and in
`notion-client.cabal` under the executable's `other-modules`.

**Verification.** Run `cabal test` — all tests must pass. Run `cabal build all` — the example
must compile. The demo can be tested manually with a valid Notion API token by running
`cabal run notion-client-example` and selecting the file upload option.


## Concrete Steps

All commands should be run from the repository root directory:
`/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`.

**After Milestone 1:**

    cabal build all

Expected: compilation succeeds, output includes building the `Notion.V1.FileUploads` module.

**After Milestone 2:**

    cabal build all

Expected: compilation succeeds including the updated `Notion.V1` module.

    cabal repl notion-client <<< ':info Methods'

Expected: the `:info` output shows the new file upload fields in the `Methods` record.

**After Milestone 3:**

    cabal build all && cabal test

Expected: build succeeds; all existing tests pass.

**After Milestone 4:**

    cabal test

Expected output (relevant lines):

    All N tests passed.

    cabal build all

Expected: the example executable compiles successfully.


## Validation and Acceptance

The feature is accepted when all of the following hold:

1. `cabal build all` compiles without errors.
2. `cabal test` passes all tests, including the new file upload tests.
3. The `Methods` record in `Notion.V1` exposes `createFileUpload`, `retrieveFileUpload`,
   `sendFileUploadContent`, `completeFileUpload`, and `listFileUploads`.
4. A user can write code like:

       let Methods{createFileUpload, sendFileUploadContent} = makeMethods env token
       upload <- createFileUpload (mkSinglePartUpload (Just "photo.png"))
       _ <- sendFileUploadContent (upload.id) (mkSendFileUpload "/path/to/photo.png" "photo.png" "image/png")

5. The `FileValue`, `Icon`, and `Cover` types can parse and produce JSON with
   `"type": "file_upload"`.
6. The example app includes a file upload demo that compiles.


## Idempotence and Recovery

All steps are file edits and builds. They can be repeated safely. If the build fails at any
milestone, fix the compilation errors and re-run `cabal build all`. No destructive operations
are involved. Each milestone is committed separately, so `git checkout` can roll back to any
previous state.

For the multipart client: the `genBoundary` function generates a random boundary string on
each call. This is safe to call multiple times — each call to `sendFileUploadContent` generates
a fresh boundary.


## Interfaces and Dependencies

**External library dependencies.** No new dependencies are needed. The project already depends on
`servant-multipart-api` and `servant-multipart-client` (both `>=0.12 && <0.13`). The multipart
support infrastructure is already in place.

**Types and signatures that must exist after each milestone:**

After Milestone 1, in `src/Notion/V1/FileUploads.hs`:

    type FileUploadID = UUID

    data FileUploadStatus = Pending | Uploaded | Expired | Failed

    data NumberOfParts = NumberOfParts { total :: Natural, sent :: Natural }

    data FileImportResult
      = FileImportSuccess { importedTime :: POSIXTime }
      | FileImportError { importedTime :: POSIXTime, errorType :: Text, ... }

    data FileUploadObject = FileUploadObject
      { id :: FileUploadID, object :: Text, status :: FileUploadStatus,
        filename :: Maybe Text, contentType :: Maybe Text,
        contentLength :: Maybe Natural, createdTime :: POSIXTime,
        lastEditedTime :: POSIXTime, createdBy :: Value,
        inTrash :: Bool, expiryTime :: Maybe POSIXTime,
        numberOfParts :: Maybe NumberOfParts,
        fileImportResult :: Maybe FileImportResult }

    data CreateFileUpload = CreateFileUpload
      { mode :: Maybe Text, filename :: Maybe Text,
        contentType :: Maybe Text, numberOfParts :: Maybe Natural,
        externalUrl :: Maybe Text }

    data SendFileUpload = SendFileUpload
      { filePath :: FilePath, fileName :: Text,
        fileContentType :: Text, partNumber :: Maybe Natural }

    instance ToMultipart Tmp SendFileUpload

    mkSinglePartUpload :: Maybe Text -> CreateFileUpload
    mkMultiPartUpload :: Text -> Natural -> Maybe Text -> CreateFileUpload
    mkExternalUrlUpload :: Text -> Maybe Text -> CreateFileUpload
    mkSendFileUpload :: FilePath -> Text -> Text -> SendFileUpload

    type API = ...  -- five endpoints

After Milestone 2, in `src/Notion/V1.hs`:

    data Methods = Methods { ..., createFileUpload :: ..., retrieveFileUpload :: ...,
      sendFileUploadContent :: ..., completeFileUpload :: ..., listFileUploads :: ... }

After Milestone 3, in `src/Notion/V1/PropertyValue.hs`:

    data FileValue = ... | FileUploadFileValue {name :: Text, fileUploadId :: UUID}
    fileUploadFilesValue :: [(Text, UUID)] -> PropertyValue

In `src/Notion/V1/Common.hs`:

    data Icon = ... | FileUploadIcon {fileUploadId :: UUID}
    data Cover = ... | FileUploadCover {fileUploadId :: UUID}
