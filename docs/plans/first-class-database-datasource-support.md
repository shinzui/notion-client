# First-Class Database and Data Source Support

Intention: intention_01kmyd8ahae85t3yb4vxejyv8d

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

The notion-client library has typed property schemas, filters, and sorts (added in `docs/plans/typed-database-datasource-support.md`), but page property values are still untyped `Maybe Value`, error handling throws raw Servant exceptions, several API fields and endpoints are missing, and there is no pagination helper. After implementing this plan, users will be able to:

1. Read and write page property values using typed Haskell values — pattern-matching on `TitleValue`, `SelectValue "Done"`, `DateValue (Date "2024-01-15" Nothing Nothing)` etc. — instead of manually constructing or parsing JSON.
2. Create pages with smart constructors like `titleValue "My Page"` and `selectValue "In Progress"` that produce correctly-shaped property values without touching `aeson`.
3. Retrieve individual page properties via the paginated property item endpoint (`GET /v1/pages/{page_id}/properties/{property_id}`).
4. Auto-paginate through query results with a single function call that follows `nextCursor` / `hasMore` until all results are collected.
5. Catch typed `NotionError` exceptions with Notion-specific error codes and messages instead of parsing raw HTTP errors.
6. Remove properties from data source schemas by setting them to `null` in update requests.
7. Use missing API fields: `public_url` on pages, `is_locked` on database updates, `filter_properties` on queries.


## Progress

- [x] Milestone 1: Typed Page Property Values (2026-03-29)
  - [x] Create `src/Notion/V1/PropertyValue.hs` with `PropertyValue` sum type (23 variants)
  - [x] Add `DateRange` type for date property values (reuse `RichText.Date`)
  - [x] Add `FormulaValue` sum type (string/number/boolean/date)
  - [x] Add `RollupValue` sum type (number/date/array/incomplete/unsupported)
  - [x] Add `RelationRef` type for relation property values
  - [x] Add `UniqueIdValue` type (number + optional prefix)
  - [x] Add `VerificationValue` type (state, verified_by, date)
  - [x] Add `FileValue` type for files property values
  - [x] Add `FromJSON` instance for `PropertyValue` that dispatches on the `type` discriminator
  - [x] Add `ToJSON` instance for `PropertyValue` that produces the correct wire format
  - [x] Add smart constructors: `titleValue`, `richTextValue`, `numberValue`, `selectValue`, `multiSelectValue`, `dateValue`, `checkboxValue`, `urlValue`, `emailValue`, `phoneNumberValue`, `relationValue`, `statusValue`, `peopleValue`, `filesValue`
  - [x] Replace `PropertyItem` in `Pages.hs` with a new record using the typed `PropertyValue`
  - [x] Remove old `PropertyValue`/`PropertyItem` types and `PropertyValueType` enum from `Pages.hs`
  - [x] Update `PageObject.properties` to `Map Text PropertyValue`
  - [x] Update `CreatePage.properties` and `UpdatePage.properties` to `Map Text PropertyValue`
  - [x] Update `PageProperties` type alias
  - [x] Update `mkCreatePage` and `mkUpdatePage` smart constructors
  - [x] Add JSON round-trip tests for each property value type (18 new tests)
  - [x] Update `notion-client-example/DatabaseDemo.hs` page creation to use smart constructors
  - [x] Update `notion-client-example/MarkdownDemo.hs` to use smart constructors
  - [x] Update `notion-client-example/TemplateDemo.hs` to use smart constructors
  - [x] Add `publicUrl :: Maybe Text` to `PageObject` (moved from Milestone 5)
  - [x] Verify `cabal build all && cabal test` — 71 tests pass
- [x] Milestone 2: Retrieve Page Property Item Endpoint (2026-03-29)
  - [x] Add `PropertyItemResponse` type (single-value or paginated list)
  - [x] Add `GET /v1/pages/{page_id}/properties/{property_id}` to Pages API type
  - [x] Wire `retrievePageProperty` into `Methods` record
  - [x] Verify `cabal build all && cabal test` — 71 tests pass
- [x] Milestone 3: Typed Error Handling (2026-03-29)
  - [x] Add `Exception` instance to `NotionError`
  - [x] Add `parseNotionError :: Client.ClientError -> Maybe NotionError` helper
  - [x] Update `run` in `makeMethods` to parse response body into `NotionError` on failure
  - [x] Add `ToJSON` instance for `NotionError` (for completeness)
  - [x] Add test that verifies `NotionError` parses from a sample error JSON
  - [x] Verify `cabal build all && cabal test` — 72 tests pass
- [ ] Milestone 4: Property Schema Deletion and Nullable Properties
  - [ ] Change `UpdateDataSource.properties` from `Maybe (Map Text PropertySchema)` to `Maybe (Map Text (Maybe PropertySchema))`
  - [ ] Update `ToJSON` for `UpdateDataSource` to emit `null` for `Nothing` values in the properties map
  - [ ] Update example and tests
  - [ ] Verify `cabal build all && cabal test`
- [ ] Milestone 5: Missing API Fields
  - [x] Add `publicUrl :: Maybe Text` to `PageObject` and update `FromJSON`/`ToJSON` (done in Milestone 1)
  - [ ] Add `isLocked :: Maybe Bool` to `UpdateDatabase`
  - [ ] Add `filterProperties :: Maybe [Text]` to `QueryDatabase` and `QueryDataSource`
  - [ ] Add `resultType :: Maybe Text` to `QueryDataSource`
  - [ ] Add `description :: Maybe (Vector RichText)` to `CreateDataSource`
  - [ ] Add `cover :: Maybe Cover` to `CreateDataSource`
  - [ ] Verify `cabal build all && cabal test`
- [ ] Milestone 6: Auto-Pagination Helper
  - [ ] Add `paginateAll` function to `Notion.V1.Pagination`
  - [ ] Add `paginateCollect` variant that returns all results as a single `Vector`
  - [ ] Wire helper usage into example app for data source queries
  - [ ] Add test demonstrating pagination
  - [ ] Verify `cabal build all && cabal test`
- [ ] Milestone 7: Final Validation and Cleanup
  - [ ] Mark `queryDatabase` as deprecated in Haddock docs
  - [ ] Update CHANGELOG.md
  - [ ] Run full test suite including integration
  - [ ] Update README.md with typed property value examples


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Create a new `Notion.V1.PropertyValue` module rather than expanding `Pages.hs`.
  Rationale: `Pages.hs` is already 466 lines. Property values are conceptually distinct from page CRUD operations and will be imported by both `Pages.hs` (for `PageObject.properties`) and potentially by user code directly. A dedicated module keeps concerns separated and matches the pattern of `Properties.hs` (schemas) vs `PropertyValue.hs` (values).
  Date: 2026-03-29

- Decision: Replace the existing `PropertyValue`/`PropertyItem`/`PropertyValueType` types entirely rather than wrapping them.
  Rationale: The current `PropertyValue` type is a two-field record `{ type_ :: PropertyValueType, value :: Maybe Value }` with a fragile `ToJSON` instance. The `PropertyItem` type has `{ id :: Text, type_ :: PropertyValueType, value :: Maybe Value }`. Both store raw JSON. Replacing them with a proper sum type is a clean break. The `PropertyValueType` enum becomes unnecessary because the sum type constructors encode the type. This is a breaking change but the current API is already awkward to use, and the typed alternative is strictly better.
  Date: 2026-03-29

- Decision: Reuse `RichText.Date` for date property values rather than creating a new type.
  Rationale: The `Date` type in `RichText.hs` already has `{ start :: Text, end :: Maybe Text, timeZone :: Maybe TimeZone }`, which matches the Notion API's date property value shape exactly. Creating a duplicate type would be confusing.
  Date: 2026-03-29

- Decision: Smart constructors return `PropertyValue` directly (not `(Text, PropertyValue)` pairs).
  Rationale: The property name is the map key, not part of the value. Users write `Map.fromList [("Status", selectValue "Done")]`. The constructor produces only the value part.
  Date: 2026-03-29

- Decision: Use a single `PropertyValue` sum type for both reading (API responses) and writing (create/update requests).
  Rationale: The Notion API uses the same JSON shape for property values in both directions (with some read-only types like formula, rollup, unique_id that are only present in responses). Using one type means users can pattern-match on what they read and construct what they write with the same constructors. Read-only variants will simply never be used in write contexts.
  Date: 2026-03-29

- Decision: `UpdateDataSource.properties` changes to `Maybe (Map Text (Maybe PropertySchema))` for nullable property deletion.
  Rationale: The Notion API allows setting a property to `null` to delete it from the schema. The current `Map Text PropertySchema` cannot represent this. Wrapping the value in `Maybe` allows `Nothing` to emit `null` in the JSON output. The outer `Maybe` (on the whole `properties` field) still means "don't touch properties at all" when `Nothing`.
  Date: 2026-03-29

- Decision: `NotionError` parsing is best-effort in the `run` function — if the response body cannot be parsed as `NotionError`, fall back to throwing the raw `ClientError`.
  Rationale: Not all HTTP errors from the Notion API have a JSON body (e.g., network errors, 502 gateway errors). The `run` function should try to parse the body but gracefully degrade.
  Date: 2026-03-29

- Decision: The `filterProperties` query parameter is modeled as a field on the request body types rather than as Servant `QueryParam`s.
  Rationale: The Notion API documentation shows `filter_properties` as a query parameter (repeated, e.g., `?filter_properties=X&filter_properties=Y`). However, Servant's `QueryParam` does not natively support repeated parameters. Using `QueryParams` (plural) would work but requires changing the API type. Alternatively, since the query endpoints already use `POST` with a JSON body, some implementations pass it in the body. We will use `QueryParams` in the Servant type since it is the correct HTTP representation.
  Date: 2026-03-29

- Decision: The auto-pagination helper uses a callback style rather than conduit/streaming.
  Rationale: Adding a streaming dependency (conduit, streaming, pipes) would be heavyweight for a simple utility. A callback-based `paginateAll` that accumulates results into a `Vector` is simple, dependency-free, and covers the common case. Users needing streaming can easily implement it on top of the existing cursor-based API.
  Date: 2026-03-29


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

The notion-client library is a Haskell client for the Notion REST API, built with Servant for type-safe endpoint definitions and `aeson` for JSON serialization. It targets GHC 9.12.2 with GHC2024.

A prior plan (`docs/plans/typed-database-datasource-support.md`) added typed property schemas (`Notion.V1.Properties`), a typed filter/sort DSL (`Notion.V1.Filter`), and replaced `Value` fields in database/data source types. That plan is complete and all 53 tests pass.

The key modules and their current state:

`src/Notion/V1/Pages.hs` (466 lines) defines `PageObject`, `CreatePage`, `UpdatePage`, and the current untyped property value types. `PageObject.properties` is `Map Text PropertyItem` where `PropertyItem` has `{ id :: Text, type_ :: PropertyValueType, value :: Maybe Value }`. The `PropertyValueType` enum (23 constructors: Title, RichText, Number, Select, ...) names property types but carries no typed data. The `PropertyValue` type used for writes is `{ type_ :: PropertyValueType, value :: Maybe Value }` with a fragile `ToJSON` that special-cases `Title` and falls through to raw JSON for everything else. The `propertyTypeToKey` function maps enum values to JSON key names (e.g., `Select -> "select"`).

`src/Notion/V1/Properties.hs` defines `PropertySchema` — the typed representation of database/data source property definitions (column schemas). This is the "shape" of a property, not its value. It includes `SelectOption`, `SelectColor`, `NumberFormat`, `RollupFunction`, `RelationType`, `StatusGroup`.

`src/Notion/V1/Filter.hs` defines `Filter`, `PropertyCondition` (22 variants), 14 leaf condition types, `Sort`, `SortDirection`, and `TimestampType`.

`src/Notion/V1/RichText.hs` defines `RichText`, `Annotations`, `TextContent`, `MentionContent`, `EquationContent`, `Date` (with `start`, `end`, `timeZone`), `TimeZone`, and `Link`. The `Date` type is already the correct shape for date property values.

`src/Notion/V1/Common.hs` defines `UUID`, `Parent`, `ObjectType`, `Icon`, `Cover`, `Color`, `File`, `ExternalFile`.

`src/Notion/V1/Users.hs` defines `UserReference` (a lightweight `{ id, object }` record used in `created_by`/`last_edited_by` fields).

`src/Notion/V1/Error.hs` defines `NotionError` with `FromJSON` but no `Exception` instance and no integration with the client's error handling. The `run` function in `V1.hs` throws raw `Client.ClientError`.

`src/Notion/V1/ListOf.hs` defines `ListOf a` (paginated response) with `results`, `nextCursor`, `hasMore`.

`src/Notion/V1/Pagination.hs` defines `PaginationParams` (unused in practice — query types define their own pagination fields).

`src/Notion/V1.hs` composes all API types, derives Servant clients, and bundles them into `Methods`. The `makeMethods` function uses `hoistClient` with a `run` function that calls `Client.runClientM` and throws on `Left`.

`notion-client.cabal` lists all exposed modules and dependencies. The library uses `aeson`, `servant`, `servant-client`, `http-client-tls`, `scientific`, `text`, `vector`, `containers`, `time`.

`tasty/Main.hs` has 53 tests: JSON parsing, JSON serialization, and optional integration tests gated on `NOTION_TOKEN`.

`notion-client-example/DatabaseDemo.hs` demonstrates the database/data source workflow using typed property schemas but still constructs page property values as raw `Aeson.object` calls.

The Notion API returns page property values in this JSON shape (within the `properties` map of a page object):

    {
      "Status": {
        "id": "abc",
        "type": "select",
        "select": {
          "id": "opt-1",
          "name": "Done",
          "color": "green"
        }
      }
    }

The envelope has `id` (the property's schema ID) and `type` (the property type name). The actual value lives under a key matching the type name. For creating/updating pages, the write format is simpler — just the type key with the value:

    {
      "Status": {
        "select": {
          "name": "Done"
        }
      }
    }

The full Notion API property value reference documents the read and write shapes for all 23 property types. The key insight is that read responses include the `id` and `type` envelope, while write requests only need the type-keyed value.


## Plan of Work

The work is organized into seven milestones. Milestone 1 is the largest and most impactful — it replaces the untyped property value system. Milestones 2-6 are smaller, independent improvements. Milestone 7 ties everything together.


### Milestone 1: Typed Page Property Values

This is the core milestone. It creates a new `src/Notion/V1/PropertyValue.hs` module with a `PropertyValue` sum type that replaces `Maybe Value` in page property items and values, then updates `Pages.hs`, `PageObject`, `CreatePage`, `UpdatePage`, and the example app.

At the end of this milestone, users can read page properties by pattern-matching:

    let PageObject { properties } = page
    case Map.lookup "Status" properties of
      Just (SelectValue _ (Just opt)) -> putStrLn $ "Status: " <> name opt
      _ -> putStrLn "No status"

And write properties with smart constructors:

    let props = Map.fromList
          [ ("title", titleValue [mkPlainText "My Page"])
          , ("Status", selectValue "In Progress")
          , ("Due", dateValue "2024-06-01" Nothing)
          , ("Priority", numberValue 1)
          ]
    createPage (mkCreatePage parent props)

The new module defines:

`PropertyValue` — the main sum type. Each constructor carries the property's schema ID (a `Text`, present when reading from the API, empty string when writing) and the typed value. Read-only types (formula, rollup, unique_id, created_time, created_by, last_edited_time, last_edited_by) only appear in API responses.

    data PropertyValue
      = TitleValue Text (Vector RichText)
      | RichTextValue Text (Vector RichText)
      | NumberValue Text (Maybe Scientific)
      | SelectValue Text (Maybe SelectOptionValue)
      | MultiSelectValue Text (Vector SelectOptionValue)
      | DateValue Text (Maybe Date)
      | PeopleValue Text (Vector UserReference)
      | FilesValue Text (Vector FileValue)
      | CheckboxValue Text Bool
      | UrlValue Text (Maybe Text)
      | EmailValue Text (Maybe Text)
      | PhoneNumberValue Text (Maybe Text)
      | FormulaValue Text FormulaResult          -- read-only
      | RelationValue Text (Vector RelationRef)
      | RollupValue Text RollupResult             -- read-only
      | CreatedTimeValue Text Text                -- read-only, ISO 8601
      | CreatedByValue Text UserReference         -- read-only
      | LastEditedTimeValue Text Text             -- read-only, ISO 8601
      | LastEditedByValue Text UserReference      -- read-only
      | StatusValue Text (Maybe SelectOptionValue)
      | UniqueIdValue Text UniqueIdResult         -- read-only
      | PlaceValue Text (Maybe Value)             -- minimal API support
      | ButtonValue Text (Maybe Value)            -- minimal API support
      | VerificationValue Text (Maybe VerificationResult) -- read-only

The first `Text` field in every constructor is the property schema ID (`"abc"` from the API, or `""` when constructing for writes).

Supporting types:

    data SelectOptionValue = SelectOptionValue
      { id :: Maybe Text
      , name :: Text
      , color :: Maybe Text
      }

Note: `color` is `Maybe Text` (not `SelectColor`) because the API returns color names as strings in property values, and the set may differ from schema colors.

    data FileValue
      = InternalFileValue { name :: Text, file :: File }
      | ExternalFileValue { name :: Text, external :: ExternalFile }

Reuses `File` and `ExternalFile` from `Common.hs`.

    newtype RelationRef = RelationRef { id :: UUID }

    data FormulaResult
      = FormulaStringResult (Maybe Text)
      | FormulaNumberResult (Maybe Scientific)
      | FormulaBooleanResult (Maybe Bool)
      | FormulaDateResult (Maybe Date)

    data RollupResult
      = RollupNumberResult (Maybe Scientific) RollupFunction
      | RollupDateResult (Maybe Date) RollupFunction
      | RollupArrayResult (Vector Value) RollupFunction
      | RollupIncompleteResult RollupFunction
      | RollupUnsupportedResult RollupFunction

    data UniqueIdResult = UniqueIdResult
      { number :: Natural
      , prefix :: Maybe Text
      }

    data VerificationResult = VerificationResult
      { state :: Text                  -- "verified", "expired", etc.
      , verifiedBy :: Maybe UserReference
      , date :: Maybe Date
      }

The `FromJSON` instance for `PropertyValue` reads the `id` and `type` fields from the envelope, then dispatches on the type name to parse the value from the type-keyed field. For example, when `type` is `"select"`, it reads the `"select"` key and parses a `Maybe SelectOptionValue`.

The `ToJSON` instance for `PropertyValue` produces the write format: just the type key with the value. It omits the `id` and `type` envelope fields since the API infers the type from the key. For example, `SelectValue "" (Just (SelectOptionValue Nothing "Done" Nothing))` produces `{"select": {"name": "Done"}}`.

Smart constructors (all return `PropertyValue`):

    titleValue :: Vector RichText -> PropertyValue
    titleValue = TitleValue ""

    richTextValue :: Vector RichText -> PropertyValue
    richTextValue = RichTextValue ""

    numberValue :: Scientific -> PropertyValue
    numberValue n = NumberValue "" (Just n)

    selectValue :: Text -> PropertyValue
    selectValue name = SelectValue "" (Just (SelectOptionValue Nothing name Nothing))

    multiSelectValue :: [Text] -> PropertyValue
    multiSelectValue names = MultiSelectValue "" (Vector.fromList (map (\n -> SelectOptionValue Nothing n Nothing) names))

    dateValue :: Text -> Maybe Text -> PropertyValue
    dateValue start end = DateValue "" (Just (Date start end Nothing))

    checkboxValue :: Bool -> PropertyValue
    checkboxValue = CheckboxValue ""

    urlValue :: Text -> PropertyValue
    urlValue t = UrlValue "" (Just t)

    emailValue :: Text -> PropertyValue
    emailValue t = EmailValue "" (Just t)

    phoneNumberValue :: Text -> PropertyValue
    phoneNumberValue t = PhoneNumberValue "" (Just t)

    relationValue :: [UUID] -> PropertyValue
    relationValue ids = RelationValue "" (Vector.fromList (map RelationRef ids))

    statusValue :: Text -> PropertyValue
    statusValue name = StatusValue "" (Just (SelectOptionValue Nothing name Nothing))

    peopleValue :: [UUID] -> PropertyValue
    peopleValue ids = PeopleValue "" (Vector.fromList (map (\i -> UserReference i "user") ids))

    filesValue :: [Text] -> PropertyValue
    filesValue urls = FilesValue "" (Vector.fromList (map (\u -> ExternalFileValue "" (ExternalFile u)) urls))

Changes to `src/Notion/V1/Pages.hs`:

Remove `PropertyValue`, `PropertyItem`, `PropertyValueType`, `SelectOption`, `propertyTypeToKey`, and their instances. Replace `PageProperties` type alias with `type PageProperties = Map Text PV.PropertyValue` (importing from `PropertyValue` module). Update `PageObject`:

    data PageObject = PageObject
      { ...
      , properties :: Map Text PV.PropertyValue
      , ...
      }

Update `FromJSON` for `PageObject` to parse `properties` using the new typed parser. Update `ToJSON` for `PageObject` similarly. Update `CreatePage.properties` and `UpdatePage.properties` to use `Map Text PV.PropertyValue`.

Update exports: re-export key types from `PropertyValue` and remove old exports. Keep `mkCreatePage` and `mkUpdatePage` working.

Changes to `notion-client-example/DatabaseDemo.hs`:

Replace the raw `Aeson.object` construction of page properties (the `textObj`, `textItem`, `titleArray`, `titleProp`, `statusProp`, `priorityProp` block at lines 141-160) with smart constructors:

    let pageProperties = Map.fromList
          [ ("title", titleValue (Vector.singleton (mkPlainRichText "Test Page from API")))
          , ("Status", selectValue "In Progress")
          , ("Priority", selectValue "High")
          ]

Add a helper `mkPlainRichText :: Text -> RichText` to the example (or import one if available).

Changes to `tasty/Main.hs`:

Add JSON round-trip tests for: `TitleValue`, `SelectValue`, `NumberValue`, `CheckboxValue`, `DateValue`, `RelationValue`, `StatusValue`, `MultiSelectValue`, `UrlValue`, `FormulaValue` (read-only, FromJSON only). Update any existing tests that reference the old `PropertyValue`/`PropertyItem` types.

Changes to `notion-client.cabal`:

Add `Notion.V1.PropertyValue` to `exposed-modules`.

Acceptance: `cabal build all` succeeds. All tests pass. The example app creates pages with typed properties.


### Milestone 2: Retrieve Page Property Item Endpoint

This milestone adds the `GET /v1/pages/{page_id}/properties/{property_id}` endpoint. The Notion API returns either a single property value or a paginated list (for title, rich_text, relation, and people properties that can have many items).

At the end of this milestone, users can call `retrievePageProperty` to get individual property values, including paginated ones.

Add a `PropertyItemResponse` type that handles both shapes:

    data PropertyItemResponse
      = SinglePropertyItem PropertyValue
      | PaginatedPropertyItems (ListOf PropertyValue) Text  -- the Text is the property type

The Servant API route:

    :<|> Capture "page_id" PageID
         :> "properties"
         :> Capture "property_id" Text
         :> QueryParam "start_cursor" Text
         :> QueryParam "page_size" Natural
         :> Get '[JSON] PropertyItemResponse

Wire into `Methods`:

    retrievePageProperty ::
      PageID ->
      Text ->          -- property_id
      Maybe Text ->    -- start_cursor
      Maybe Natural -> -- page_size
      IO PropertyItemResponse

Acceptance: `cabal build all` succeeds. Tests pass.


### Milestone 3: Typed Error Handling

This milestone wires `NotionError` into the client's error handling so users get typed exceptions.

Add `Exception` instance to `NotionError` in `Error.hs`:

    instance Exception NotionError

Add a helper function:

    parseNotionError :: Client.ClientError -> Maybe NotionError

This extracts the response body from `FailureResponse` and attempts to decode it as `NotionError`.

Update the `run` function in `V1.hs`:

    run clientM = do
      result <- Client.runClientM clientM clientEnv
      case result of
        Left err -> case parseNotionError err of
          Just notionErr -> Exception.throwIO notionErr
          Nothing -> Exception.throwIO err
        Right a -> return a

This way, users can catch `NotionError` specifically:

    import Control.Exception (catch)
    retrieveDatabase methods dbId `catch` \(e :: NotionError) ->
      putStrLn $ "Notion error: " <> code e <> " - " <> message e

Add a `ToJSON` instance for `NotionError` for completeness and testing.

Acceptance: `cabal build all` succeeds. A test verifies `NotionError` parses from sample JSON. A test verifies `parseNotionError` extracts errors from `FailureResponse`.


### Milestone 4: Property Schema Deletion and Nullable Properties

This milestone allows removing properties from a data source schema.

Change `UpdateDataSource.properties` from `Maybe (Map Text PropertySchema)` to `Maybe (Map Text (Maybe PropertySchema))`.

Update the `ToJSON` instance to emit `null` for `Nothing` values within the map. The default `genericToJSON aesonOptions` with `omitNothingFields = True` would skip `Nothing` values, which is wrong — we need to emit them as `null`. This requires a custom `ToJSON` instance for the properties field.

Example usage:

    let updateReq = UpdateDataSource
          { properties = Just $ Map.fromList
              [ ("OldColumn", Nothing)                -- delete this property
              , ("NewColumn", Just (TitleSchema ...)) -- add this property
              ]
          , ...
          }

Acceptance: `cabal build all` succeeds. A serialization test verifies that `Nothing` values in the map emit `null` in JSON.


### Milestone 5: Missing API Fields

This milestone adds fields that the API returns or accepts but are not currently modeled.

Add `publicUrl :: Maybe Text` to `PageObject`. Update `FromJSON` to parse `public_url` and `ToJSON` to emit it.

Add `isLocked :: Maybe Bool` to `UpdateDatabase`.

Add `filterProperties :: Maybe [Text]` as a `QueryParams` to the Servant API types for `queryDatabase` and `queryDataSource`. This requires changing the API type to include `QueryParams "filter_properties" Text` and updating the client destructuring in `V1.hs`. The `QueryDatabase` and `QueryDataSource` request body types remain unchanged — `filter_properties` is a query parameter, not a body field. The `Methods` record signatures will gain an additional `Maybe [Text]` parameter, or the query parameter can be wired through a wrapper.

Actually, on reflection, adding `QueryParams` to the Servant route changes the `Methods` signatures in a way that breaks existing callers. A simpler approach is to add `filterProperties` as a field on the request body types since some API implementations accept it either way, but the canonical Notion API uses query parameters. The safest approach is to add it as a query parameter and update `Methods` accordingly.

Add `resultType :: Maybe Text` to `QueryDataSource`.

Add `description :: Maybe (Vector RichText)` and `cover :: Maybe Cover` to `CreateDataSource`.

Acceptance: `cabal build all` succeeds. Tests pass.


### Milestone 6: Auto-Pagination Helper

This milestone adds a helper to `Notion.V1.Pagination` that automatically follows cursors.

    paginateAll :: (Maybe Text -> IO (ListOf a)) -> IO (Vector a)

The function takes a callback that accepts an optional cursor and returns a paginated response. It calls the callback repeatedly, collecting results, until `hasMore` is `False` or `nextCursor` is `Nothing`.

Example usage:

    allPages <- paginateAll $ \cursor ->
      queryDataSource methods dsId QueryDataSource
        { filter = Nothing
        , sorts = Nothing
        , startCursor = cursor
        , pageSize = Just 100
        , inTrash = Nothing
        }

Add a `paginateCollect` variant that also returns metadata:

    data PaginationResult a = PaginationResult
      { allResults :: Vector a
      , totalPages :: Natural
      }

    paginateCollect :: (Maybe Text -> IO (ListOf a)) -> IO (PaginationResult a)

Acceptance: `cabal build all` succeeds. A unit test verifies pagination logic with a mock callback.


### Milestone 7: Final Validation and Cleanup

This milestone ties everything together.

Add a `{-# DEPRECATED queryDatabase "Use queryDataSource instead (API 2025-09-03)" #-}` pragma to the `queryDatabase` field in `Methods`.

Update `CHANGELOG.md` with a version entry documenting all changes.

Update `README.md` with examples showing typed property values, smart constructors, error handling, and auto-pagination.

Run the full test suite including integration tests.

Acceptance: `cabal build all` succeeds. All tests pass. README examples are accurate.


## Concrete Steps

All commands run from the repository root: `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`.

After each milestone:

    cabal build all

Expected: compilation succeeds with no errors.

    cabal test

Expected: all tests pass with `OK` status.

This section will be updated with specific outputs as implementation proceeds.


## Validation and Acceptance

**Compilation:** `cabal build all` must succeed after every milestone.

**Unit tests:** JSON round-trip tests verify typed property values serialize and deserialize correctly. Filter/sort tests from the prior plan continue to pass. Error handling tests verify `NotionError` parsing.

**Integration (when token available):** After Milestone 7, run integration tests with `NOTION_TOKEN` to verify:

1. Retrieving a page returns typed `PropertyValue` variants that can be pattern-matched.
2. Creating a page with smart constructors produces a valid page.
3. Retrieving a page property via the new endpoint returns typed results.
4. Querying a data source with `filterProperties` limits the returned properties.
5. `NotionError` is thrown as a typed exception for invalid requests.
6. Auto-pagination collects all results from a multi-page query.

**Regression:** All existing tests must continue to pass.


## Idempotence and Recovery

All steps are file edits and recompilation — fully idempotent. Each milestone commits its changes. To recover from a bad state:

    git log --oneline -5
    git checkout <last-good-commit> -- src/ tasty/ notion-client-example/


## Interfaces and Dependencies

No new Cabal dependencies required. All types use existing libraries: `aeson`, `scientific`, `containers`, `text`, `vector`, `time`, `servant`, `servant-client`.

**New module interfaces at end of plan:**

In `src/Notion/V1/PropertyValue.hs`, define and export:

    data PropertyValue
      = TitleValue Text (Vector RichText)
      | RichTextValue Text (Vector RichText)
      | NumberValue Text (Maybe Scientific)
      | SelectValue Text (Maybe SelectOptionValue)
      | MultiSelectValue Text (Vector SelectOptionValue)
      | DateValue Text (Maybe Date)
      | PeopleValue Text (Vector UserReference)
      | FilesValue Text (Vector FileValue)
      | CheckboxValue Text Bool
      | UrlValue Text (Maybe Text)
      | EmailValue Text (Maybe Text)
      | PhoneNumberValue Text (Maybe Text)
      | FormulaValue Text FormulaResult
      | RelationValue Text (Vector RelationRef)
      | RollupValue Text RollupResult
      | CreatedTimeValue Text Text
      | CreatedByValue Text UserReference
      | LastEditedTimeValue Text Text
      | LastEditedByValue Text UserReference
      | StatusValue Text (Maybe SelectOptionValue)
      | UniqueIdValue Text UniqueIdResult
      | PlaceValue Text (Maybe Value)
      | ButtonValue Text (Maybe Value)
      | VerificationValue Text (Maybe VerificationResult)

    data SelectOptionValue = SelectOptionValue { id :: Maybe Text, name :: Text, color :: Maybe Text }
    data FileValue = InternalFileValue { name :: Text, file :: File } | ExternalFileValue { name :: Text, external :: ExternalFile }
    newtype RelationRef = RelationRef { id :: UUID }
    data FormulaResult = FormulaStringResult (Maybe Text) | FormulaNumberResult (Maybe Scientific) | FormulaBooleanResult (Maybe Bool) | FormulaDateResult (Maybe Date)
    data RollupResult = RollupNumberResult (Maybe Scientific) RollupFunction | RollupDateResult (Maybe Date) RollupFunction | RollupArrayResult (Vector Value) RollupFunction | RollupIncompleteResult RollupFunction | RollupUnsupportedResult RollupFunction
    data UniqueIdResult = UniqueIdResult { number :: Natural, prefix :: Maybe Text }
    data VerificationResult = VerificationResult { state :: Text, verifiedBy :: Maybe UserReference, date :: Maybe Date }

    -- Smart constructors
    titleValue :: Vector RichText -> PropertyValue
    richTextValue :: Vector RichText -> PropertyValue
    numberValue :: Scientific -> PropertyValue
    selectValue :: Text -> PropertyValue
    multiSelectValue :: [Text] -> PropertyValue
    dateValue :: Text -> Maybe Text -> PropertyValue
    checkboxValue :: Bool -> PropertyValue
    urlValue :: Text -> PropertyValue
    emailValue :: Text -> PropertyValue
    phoneNumberValue :: Text -> PropertyValue
    relationValue :: [UUID] -> PropertyValue
    statusValue :: Text -> PropertyValue
    peopleValue :: [UUID] -> PropertyValue
    filesValue :: [Text] -> PropertyValue

In `src/Notion/V1/Error.hs`, add:

    instance Exception NotionError
    parseNotionError :: Client.ClientError -> Maybe NotionError

In `src/Notion/V1/Pagination.hs`, add:

    paginateAll :: (Maybe Text -> IO (ListOf a)) -> IO (Vector a)
    paginateCollect :: (Maybe Text -> IO (ListOf a)) -> IO (PaginationResult a)
    data PaginationResult a = PaginationResult { allResults :: Vector a, totalPages :: Natural }

In `src/Notion/V1/Pages.hs`, update:

    type PageProperties = Map Text PV.PropertyValue
    data PageObject = PageObject { ..., properties :: PageProperties, publicUrl :: Maybe Text, ... }
    data PropertyItemResponse = SinglePropertyItem PV.PropertyValue | PaginatedPropertyItems (ListOf PV.PropertyValue) Text

In `src/Notion/V1.hs`, add to Methods:

    retrievePageProperty :: PageID -> Text -> Maybe Text -> Maybe Natural -> IO PropertyItemResponse
