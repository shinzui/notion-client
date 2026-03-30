# Typed Database and Data Source Property Schemas, Filters, and Sorts

Intention: intention_01kmyd8ahae85t3yb4vxejyv8d

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

The notion-client library currently represents database and data source property schemas, query filters, and query sorts as untyped JSON (`Value`). This means users must hand-construct raw `Aeson.Value` objects for property definitions, filter conditions, and sort orders — a process that is error-prone and undiscoverable. After implementing this plan, users will be able to:

1. Inspect database and data source property schemas as typed Haskell values — for example, pattern-matching on a `SelectPropertyConfig` to enumerate its options, or reading a `FormulaPropertyConfig` to see its expression.
2. Construct query filters using a typed DSL — for example, `PropertyFilter "Status" (SelectFilter (Equals "Done"))` — instead of building raw JSON objects.
3. Construct query sorts using typed values — for example, `PropertySort "Name" Ascending` — instead of building raw JSON arrays.
4. Benefit from compile-time safety: if a filter condition is misspelled or a sort direction is wrong, the code will not compile.

The library's existing CRUD endpoints for databases and data sources remain unchanged. This plan replaces `Value` with typed alternatives in the property schema, filter, and sort fields across `Databases.hs` and `DataSources.hs`, and adds a new `Notion.V1.Properties.hs` module for the shared property schema types and a new `Notion.V1.Filter.hs` module for the filter DSL.


## Progress

- [x] Milestone 1: Typed Property Schemas (2026-03-29)
  - [x] Create `src/Notion/V1/Properties.hs` with `PropertySchema` sum type and per-type config records (2026-03-29)
  - [x] Add `SelectColor` enum for property option colors (2026-03-29)
  - [x] Add `NumberFormat` enum (39 formats) (2026-03-29)
  - [x] Add `RollupFunction` enum (25 functions) (2026-03-29)
  - [x] Add `RelationType` (single/dual property) (2026-03-29)
  - [x] Add `FromJSON` / `ToJSON` instances for all property schema types (2026-03-29)
  - [x] Replace `properties :: Maybe Value` in `DatabaseObject` with `Maybe (Map Text PropertySchema)` (2026-03-29)
  - [x] Replace `properties :: Value` in `DataSourceObject` with `Map Text PropertySchema` (2026-03-29)
  - [x] Replace `properties :: Value` in `CreateDataSource` with `Map Text PropertySchema` (2026-03-29)
  - [x] Replace `properties :: Maybe Value` in `UpdateDataSource` with `Maybe (Map Text PropertySchema)` (2026-03-29)
  - [x] Replace `properties :: Value` in `InitialDataSource` with `Map Text PropertySchema` (2026-03-29)
  - [x] Expose `Notion.V1.Properties` in cabal file (2026-03-29)
  - [x] Add JSON round-trip tests for property schema types (7 tests) (2026-03-29)
  - [x] Verify `cabal build all` succeeds — all 45 tests pass (2026-03-29)
- [ ] Milestone 2: Typed Query Filters
  - [ ] Create `src/Notion/V1/Filter.hs` with `Filter` sum type (compound + property + timestamp)
  - [ ] Add `TextFilter`, `NumberFilter`, `CheckboxFilter`, `SelectFilter`, `MultiSelectFilter`, `DateFilter`, `PeopleFilter`, `FilesFilter`, `RelationFilter`, `StatusFilter`, `UniqueIdFilter`, `VerificationFilter`, `FormulaFilter`, `RollupFilter` types
  - [ ] Add `ToJSON` instances for all filter types (filters are write-only; the API does not return filters in responses)
  - [ ] Replace `filter :: Maybe Value` in `QueryDatabase` with `Maybe Filter`
  - [ ] Replace `filter :: Maybe Value` in `QueryDataSource` with `Maybe Filter`
  - [ ] Expose `Notion.V1.Filter` in cabal file
  - [ ] Add JSON serialization tests for filter types
  - [ ] Verify `cabal build all` succeeds
- [ ] Milestone 3: Typed Query Sorts
  - [ ] Add `Sort` sum type (`PropertySort` and `TimestampSort`) and `SortDirection` enum to `Notion.V1.Filter` (or a dedicated module if needed)
  - [ ] Add `TimestampType` enum (`CreatedTime` / `LastEditedTime`)
  - [ ] Add `ToJSON` instances for sort types
  - [ ] Replace `sorts :: Maybe [Value]` in `QueryDatabase` with `Maybe [Sort]`
  - [ ] Replace `sorts :: Maybe [Value]` in `QueryDataSource` with `Maybe [Sort]`
  - [ ] Add JSON serialization tests for sort types
  - [ ] Verify `cabal build all` succeeds
- [ ] Milestone 4: Update Example App and Validation
  - [ ] Update `notion-client-example/DatabaseDemo.hs` to use typed property schemas, filters, and sorts instead of raw `Aeson.Value`
  - [ ] Add E2E tests that exercise typed filters and sorts against live API
  - [ ] Run full test suite: `cabal build all && cabal test`
  - [ ] Update CHANGELOG.md


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Create separate modules `Notion.V1.Properties` and `Notion.V1.Filter` rather than adding types inline to `Databases.hs` / `DataSources.hs`.
  Rationale: The property schema types are shared between databases and data sources (and potentially views in the future). The filter and sort types are also shared between `QueryDatabase` and `QueryDataSource`. Separate modules keep each file focused and avoid circular imports. This follows the existing pattern where `Common.hs`, `RichText.hs`, and `ListOf.hs` are shared modules.
  Date: 2026-03-29

- Decision: Filters are `ToJSON`-only (no `FromJSON`). Sorts are `ToJSON`-only.
  Rationale: The Notion API accepts filters and sorts in request bodies but does not return them in database or data source response objects. Writing `FromJSON` instances would be dead code. Property schemas need both `FromJSON` (for reading database/data source responses) and `ToJSON` (for creating/updating data source schemas).
  Date: 2026-03-29

- Decision: Keep `SelectColor` as a dedicated enum rather than reusing the existing `Color` type from `Common.hs`.
  Rationale: The `Color` type in `Common.hs` includes background variants (`GrayBackground`, `BlueBackground`, etc.) that are specific to text annotations. Select option colors are a different, smaller set (`default`, `gray`, `brown`, `orange`, `yellow`, `green`, `blue`, `purple`, `pink`, `red`) that maps to the Notion API's `color` field on select options. Conflating the two would be misleading.
  Date: 2026-03-29

- Decision: Use `Scientific` (from `Data.Scientific`) for number filter values rather than `Double`.
  Rationale: The `aeson` library represents JSON numbers as `Scientific`, and the Notion API accepts arbitrary-precision numbers. Using `Scientific` avoids floating-point precision issues and matches what `aeson` already uses internally. The `scientific` package is already a transitive dependency via `aeson`.
  Date: 2026-03-29

- Decision: Include all 39 `NumberFormat` values in the enum even though most users will only use a few.
  Rationale: Completeness matters for a client library. If a user's database uses `philippine_peso` format and we don't have a constructor, parsing will fail. The cost of extra constructors is negligible.
  Date: 2026-03-29

- Decision: Sorts and sort direction live in `Notion.V1.Filter` alongside filters rather than in a separate module.
  Rationale: Filters and sorts are always used together in query requests. A separate `Notion.V1.Sort` module with only two types and an enum would be excessive. Users import `Notion.V1.Filter` when constructing queries and get both filter and sort types.
  Date: 2026-03-29


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

The notion-client library is a Haskell client for the Notion REST API. It uses Servant for type-safe endpoint definitions and `aeson` for JSON serialization. The library targets GHC 9.12.2 with the GHC2024 language edition.

Each API resource has its own module under `src/Notion/V1/`. These modules define request/response types with `FromJSON`/`ToJSON` instances and a Servant `API` type alias. The main entry point `src/Notion/V1.hs` composes all API types and bundles client functions into a `Methods` record.

JSON field names use `aesonOptions` from `src/Notion/Prelude.hs`, which converts camelCase to snake_case and strips trailing underscores (so `type_` becomes `"type"` in JSON). The `omitNothingFields` option is enabled, meaning `Nothing` values are excluded from serialized output.

The key modules relevant to this plan are:

`src/Notion/V1/Databases.hs` defines `DatabaseObject`, `CreateDatabase`, `UpdateDatabase`, `QueryDatabase`, and a `DataSource` reference type (lightweight, containing only `id` and `name`). The `DatabaseObject.properties` field is `Maybe Value` — it may contain the full property schema map or be absent (in API version 2025-09-03, properties moved to data sources). The `QueryDatabase` type has `filter :: Maybe Value` and `sorts :: Maybe [Value]`.

`src/Notion/V1/DataSources.hs` defines `DataSourceObject`, `CreateDataSource`, `UpdateDataSource`, `QueryDataSource`, and template-related types. The `DataSourceObject.properties` field is `Value` — it always contains the full property schema map as a JSON object. The `CreateDataSource.properties` and `UpdateDataSource.properties` fields are also `Value` / `Maybe Value`. The `QueryDataSource` type has `filter :: Maybe Value` and `sorts :: Maybe [Value]`.

`src/Notion/V1/Pages.hs` defines `PropertyValueType` — an enum of all 23 property types (Title, RichText, Number, Select, MultiSelect, Date, People, Files, Checkbox, Url, Email, PhoneNumber, Formula, Relation, Rollup, CreatedTime, CreatedBy, LastEditedTime, LastEditedBy, Status, UniqueId, Place, Button, Verification). This enum names the property types but does not describe their configuration schemas. There is also a `SelectOption` record (id, name, color as `Maybe Text`).

`src/Notion/V1/Common.hs` defines shared types including `UUID`, `Parent`, `ObjectType`, `Icon`, `Cover`, `Color`, and `File`. The `Color` type covers text annotation colors including background variants — it is not the same as select option colors.

`src/Notion/Prelude.hs` re-exports common types (`Map`, `Vector`, `Text`, `Value`, `Generic`, `Natural`, `POSIXTime`) and defines `aesonOptions` plus ISO8601 timestamp parsing.

`notion-client.cabal` lists exposed modules. New modules must be added to `exposed-modules`.

`tasty/Main.hs` contains both JSON serialization unit tests and optional integration tests (gated on `NOTION_TOKEN` environment variable).


## Plan of Work

The work is organized into four milestones. Each milestone is independently compilable and testable. The milestones build sequentially: Milestone 1 establishes the property schema types that Milestones 2-3 reference, and Milestone 4 ties everything together with example updates and E2E testing.


### Milestone 1: Typed Property Schemas

This milestone creates a new `src/Notion/V1/Properties.hs` module containing typed representations of all Notion database property schemas, then replaces the `Value` fields in `Databases.hs` and `DataSources.hs` with these typed alternatives.

At the end of this milestone, when a user retrieves a database or data source, the `properties` field will be a `Map Text PropertySchema` instead of raw JSON. Each `PropertySchema` value will be a sum type that can be pattern-matched to inspect the property's configuration — for example, a `SelectProperty` variant contains a list of `SelectOption` values with typed colors.

The property schema represents the "shape" of a database column — not a page's property value (which is already handled by `PropertyItem` in `Pages.hs`). For example, a select property schema defines which options are available (names and colors), while a page's select property value is which option was chosen.

The Notion API returns property schemas as a JSON object where each key is the property name and each value has this shape:

    {
      "id": "abc123",
      "name": "Status",
      "type": "select",
      "select": {
        "options": [
          {"id": "...", "name": "Done", "color": "green"},
          {"id": "...", "name": "In Progress", "color": "yellow"}
        ]
      }
    }

The envelope fields (`id`, `name`, `type`) are common to all properties. The type-specific configuration lives under a key matching the `type` value.

**New file: `src/Notion/V1/Properties.hs`**

This module defines:

`SelectColor` — an enum for the 10 select option colors: `DefaultColor`, `Gray`, `Brown`, `Orange`, `Yellow`, `Green`, `Blue`, `Purple`, `Pink`, `Red`. The JSON values are `"default"`, `"gray"`, `"brown"`, etc. The constructor `DefaultColor` (rather than `Default`) avoids collision with the `Color` type's `Default` constructor in `Common.hs`.

`SelectOption` — replaces the existing `SelectOption` in `Pages.hs` with a properly typed version:

    data SelectOption = SelectOption
      { id :: Maybe Text
      , name :: Text
      , color :: Maybe SelectColor
      }

`StatusGroup` — represents a group in the status property schema:

    data StatusGroup = StatusGroup
      { id :: Maybe Text
      , name :: Text
      , color :: Maybe SelectColor
      , optionIds :: Vector Text
      }

`NumberFormat` — an enum with 39 constructors for all Notion number formats (`NumberPlain`, `NumberWithCommas`, `Percent`, `Dollar`, `CanadianDollar`, `Euro`, `Pound`, `Yen`, `Ruble`, `Rupee`, `Won`, `Yuan`, `Real`, `Lira`, `Rupiah`, `Franc`, `HongKongDollar`, `NewZealandDollar`, `Krona`, `NorwegianKrone`, `MexicanPeso`, `Rand`, `NewTaiwanDollar`, `DanishKrone`, `Zloty`, `Baht`, `Forint`, `Koruna`, `Shekel`, `ChileanPeso`, `PhilippinePeso`, `Dirham`, `ColombianPeso`, `Riyal`, `Ringgit`, `Leu`, `ArgentinePeso`, `UruguayanPeso`, `SingaporeDollar`). The JSON values are `"number"`, `"number_with_commas"`, `"percent"`, `"dollar"`, etc. Note: the plain number format serializes as `"number"` in JSON — the Haskell constructor is `NumberPlain` to avoid collision with the `Number` constructor elsewhere.

`RollupFunction` — an enum covering all rollup aggregation functions: `CountAll`, `CountValues`, `CountUniqueValues`, `CountEmpty`, `CountNotEmpty`, `PercentEmpty`, `PercentNotEmpty`, `Sum`, `Average`, `Median`, `Min`, `Max`, `Range`, `ShowOriginal`, `Checked`, `Unchecked`, `PercentChecked`, `PercentUnchecked`, `DateRange`, `EarliestDate`, `LatestDate`, `ShowUnique`, `Count`, `Empty`, `NotEmpty`. The Notion API documentation lists varying subsets across different reference pages; we include the union. The JSON values are `"count_all"`, `"count_values"`, etc.

`RelationType` — a sum type for relation property configuration:

    data RelationType
      = SingleProperty
      | DualProperty
        { syncedPropertyId :: Text
        , syncedPropertyName :: Text
        }

The JSON shape for `single_property` is `{"type": "single_property"}` with no extra fields. For `dual_property` it is `{"type": "dual_property", "dual_property": {"synced_property_id": "...", "synced_property_name": "..."}}`.

`PropertySchema` — the main sum type. Each constructor carries the common envelope fields (`id` and `name`) plus type-specific configuration:

    data PropertySchema
      = TitleSchema        { schemaId :: Text, schemaName :: Text }
      | RichTextSchema     { schemaId :: Text, schemaName :: Text }
      | NumberSchema       { schemaId :: Text, schemaName :: Text, numberFormat :: NumberFormat }
      | SelectSchema       { schemaId :: Text, schemaName :: Text, selectOptions :: Vector SelectOption }
      | MultiSelectSchema  { schemaId :: Text, schemaName :: Text, multiSelectOptions :: Vector SelectOption }
      | DateSchema         { schemaId :: Text, schemaName :: Text }
      | PeopleSchema       { schemaId :: Text, schemaName :: Text }
      | FilesSchema        { schemaId :: Text, schemaName :: Text }
      | CheckboxSchema     { schemaId :: Text, schemaName :: Text }
      | UrlSchema          { schemaId :: Text, schemaName :: Text }
      | EmailSchema        { schemaId :: Text, schemaName :: Text }
      | PhoneNumberSchema  { schemaId :: Text, schemaName :: Text }
      | FormulaSchema      { schemaId :: Text, schemaName :: Text, formulaExpression :: Text }
      | RelationSchema     { schemaId :: Text, schemaName :: Text, relationDataSourceId :: UUID, relationType :: RelationType }
      | RollupSchema       { schemaId :: Text, schemaName :: Text, rollupFunction :: RollupFunction, rollupRelationPropertyName :: Maybe Text, rollupRelationPropertyId :: Maybe Text, rollupPropertyName :: Maybe Text, rollupPropertyId :: Maybe Text }
      | CreatedTimeSchema  { schemaId :: Text, schemaName :: Text }
      | CreatedBySchema    { schemaId :: Text, schemaName :: Text }
      | LastEditedTimeSchema { schemaId :: Text, schemaName :: Text }
      | LastEditedBySchema { schemaId :: Text, schemaName :: Text }
      | StatusSchema       { schemaId :: Text, schemaName :: Text, statusOptions :: Vector SelectOption, statusGroups :: Vector StatusGroup }
      | UniqueIdSchema     { schemaId :: Text, schemaName :: Text, uniqueIdPrefix :: Maybe Text }
      | PlaceSchema        { schemaId :: Text, schemaName :: Text }
      | ButtonSchema       { schemaId :: Text, schemaName :: Text }
      | VerificationSchema { schemaId :: Text, schemaName :: Text }

The `FromJSON` instance reads the `type` field from the JSON object to determine which constructor to use, then extracts the type-specific configuration from the nested object keyed by the type name. The `ToJSON` instance produces the same shape — the common envelope plus the type-specific key.

For example, parsing `{"id": "abc", "name": "Priority", "type": "select", "select": {"options": [...]}}` yields `SelectSchema "abc" "Priority" [...]`.

For `ToJSON`, `SelectSchema "abc" "Priority" opts` produces `{"id": "abc", "name": "Priority", "type": "select", "select": {"options": [...]}}`.

**Changes to `src/Notion/V1/Databases.hs`:**

Change the `properties` field in `DatabaseObject` from `Maybe Value` to `Maybe (Map Text PropertySchema)`. Update the `FromJSON` instance to parse the properties map using the new typed parser. The `Maybe` wrapper stays because the Notion API may omit properties from database responses in API version 2025-09-03.

Change the `properties` field in `InitialDataSource` from `Value` to `Map Text PropertySchema`.

Remove the existing `import Notion.V1.Pages (PageObject)` is unchanged. Add `import Notion.V1.Properties (PropertySchema)`.

**Changes to `src/Notion/V1/DataSources.hs`:**

Change `DataSourceObject.properties` from `Value` to `Map Text PropertySchema`.

Change `CreateDataSource.properties` from `Value` to `Map Text PropertySchema`.

Change `UpdateDataSource.properties` from `Maybe Value` to `Maybe (Map Text PropertySchema)`.

Add `import Notion.V1.Properties (PropertySchema)`.

**Changes to `notion-client.cabal`:**

Add `Notion.V1.Properties` to `exposed-modules`.

Add `scientific` to `build-depends` (for `Scientific` type used in number filters in Milestone 2, but the dependency is also useful here for consistency). Actually, `scientific` is already a transitive dependency of `aeson`, but making it explicit is good practice. Check if it needs to be added.

**Changes to `src/Notion/V1/Pages.hs`:**

The existing `SelectOption` type in `Pages.hs` has `color :: Maybe Text`. This can either be left as-is (since page property values and property schemas are different contexts) or unified with the new `SelectOption` in `Properties.hs`. The decision is to keep `Pages.SelectOption` as-is for now to avoid a breaking change — the `Pages.SelectOption` represents a page's select value (which the API returns with a text color), while `Properties.SelectOption` represents a schema option (which also has a text color, but we want it typed). In a future cleanup, these could be unified. Add a note in the module.

**Tests in `tasty/Main.hs`:**

Add JSON round-trip tests for:

1. A select property schema with two options — serialize to JSON and parse back, verify equality.
2. A number property schema with `Dollar` format.
3. A formula property schema with an expression.
4. A relation property schema with dual property configuration.
5. A status property schema with options and groups.
6. A `NumberFormat` round-trip test (all 39 values, or a representative subset).
7. A `RollupFunction` round-trip test.

**Acceptance:** `cabal build all` succeeds. All existing tests pass. New property schema tests pass. Retrieving a data source via `retrieveDataSource` returns a `DataSourceObject` with typed `properties` instead of raw JSON.

    cabal build all
    cabal test


### Milestone 2: Typed Query Filters

This milestone creates a `src/Notion/V1/Filter.hs` module with a typed filter DSL, then replaces the `filter :: Maybe Value` fields in `QueryDatabase` and `QueryDataSource` with `Maybe Filter`.

At the end of this milestone, users can construct query filters like:

    let myFilter = And
          [ PropertyFilter "Status" (StatusCondition (StatusEquals "Done"))
          , PropertyFilter "Priority" (SelectCondition (SelectEquals "High"))
          ]

    let query = QueryDataSource
          { filter = Just myFilter
          , sorts = Nothing
          , startCursor = Nothing
          , pageSize = Just 10
          , inTrash = Nothing
          }

The Notion API filter structure is a discriminated union. At the top level, a filter is either a compound filter (`and` / `or` containing a list of filters) or a leaf filter. Leaf filters come in two varieties: property filters (which have a `property` field naming the property and a type-specific condition object) and timestamp filters (which have a `timestamp` field instead of `property`).

Compound filters can nest up to 2 levels deep per Notion API limits. We do not enforce this at the type level — the Notion API will return an error if nesting is too deep.

**New file: `src/Notion/V1/Filter.hs`**

This module defines:

`Filter` — the top-level filter type:

    data Filter
      = And [Filter]
      | Or [Filter]
      | PropertyFilter Text PropertyCondition
      | TimestampFilter TimestampType DateCondition

The `Text` in `PropertyFilter` is the property name. `TimestampType` is an enum with `FilterCreatedTime` and `FilterLastEditedTime` (prefixed to avoid collision with `PropertyValueType` constructors).

`PropertyCondition` — a sum type covering all property-type-specific filter conditions:

    data PropertyCondition
      = TitleCondition TextCondition
      | RichTextCondition TextCondition
      | NumberCondition NumberCondition
      | CheckboxCondition CheckboxCondition
      | SelectCondition SelectCondition
      | MultiSelectCondition MultiSelectCondition
      | DateCondition DateCondition
      | PeopleCondition PeopleCondition
      | FilesCondition FilesCondition
      | RelationCondition RelationCondition
      | StatusCondition StatusCondition
      | UniqueIdCondition UniqueIdCondition
      | VerificationCondition VerificationCondition
      | FormulaCondition FormulaCondition
      | RollupCondition RollupCondition
      | CreatedTimeCondition DateCondition
      | CreatedByCondition PeopleCondition
      | LastEditedTimeCondition DateCondition
      | LastEditedByCondition PeopleCondition
      | PhoneNumberCondition TextCondition
      | UrlCondition TextCondition
      | EmailCondition TextCondition

Each condition variant maps to the JSON key the API expects (e.g., `TitleCondition` serializes under the `"title"` key, `SelectCondition` under `"select"`).

`TextCondition` — for title, rich_text, phone_number, url, email filters:

    data TextCondition
      = TextEquals Text
      | TextDoesNotEqual Text
      | TextContains Text
      | TextDoesNotContain Text
      | TextStartsWith Text
      | TextEndsWith Text
      | TextIsEmpty
      | TextIsNotEmpty

`NumberCondition`:

    data NumberCondition
      = NumEquals Scientific
      | NumDoesNotEqual Scientific
      | NumGreaterThan Scientific
      | NumGreaterThanOrEqualTo Scientific
      | NumLessThan Scientific
      | NumLessThanOrEqualTo Scientific
      | NumIsEmpty
      | NumIsNotEmpty

`CheckboxCondition`:

    data CheckboxCondition
      = CheckboxEquals Bool
      | CheckboxDoesNotEqual Bool

`SelectCondition`:

    data SelectCondition
      = SelectEquals Text
      | SelectDoesNotEqual Text
      | SelectIsEmpty
      | SelectIsNotEmpty

`MultiSelectCondition`:

    data MultiSelectCondition
      = MultiSelectContains Text
      | MultiSelectDoesNotContain Text
      | MultiSelectIsEmpty
      | MultiSelectIsNotEmpty

`DateCondition` — used for date properties and timestamp filters:

    data DateCondition
      = DateAfter Text
      | DateBefore Text
      | DateEquals Text
      | DateOnOrAfter Text
      | DateOnOrBefore Text
      | DateIsEmpty
      | DateIsNotEmpty
      | DateNextWeek
      | DateNextMonth
      | DateNextYear
      | DateThisWeek
      | DatePastWeek
      | DatePastMonth
      | DatePastYear

The `Text` values are ISO 8601 date strings (e.g., `"2024-01-15"` or `"2024-01-15T00:00:00Z"`). We use `Text` rather than a time type because the Notion API accepts both date-only and datetime formats and the user knows which they need.

`PeopleCondition`:

    data PeopleCondition
      = PeopleContains Text
      | PeopleDoesNotContain Text
      | PeopleIsEmpty
      | PeopleIsNotEmpty

The `Text` is a user UUID.

`FilesCondition`:

    data FilesCondition
      = FilesIsEmpty
      | FilesIsNotEmpty

`RelationCondition`:

    data RelationCondition
      = RelationContains Text
      | RelationDoesNotContain Text
      | RelationIsEmpty
      | RelationIsNotEmpty

The `Text` is a page UUID.

`StatusCondition`:

    data StatusCondition
      = StatusEquals Text
      | StatusDoesNotEqual Text
      | StatusIsEmpty
      | StatusIsNotEmpty

`UniqueIdCondition`:

    data UniqueIdCondition
      = UniqueIdEquals Natural
      | UniqueIdDoesNotEqual Natural
      | UniqueIdGreaterThan Natural
      | UniqueIdGreaterThanOrEqualTo Natural
      | UniqueIdLessThan Natural
      | UniqueIdLessThanOrEqualTo Natural

`VerificationCondition`:

    data VerificationCondition
      = VerificationStatus Text

The `Text` is one of `"verified"`, `"expired"`, `"none"`.

`FormulaCondition` — wraps a condition by the formula's return type:

    data FormulaCondition
      = FormulaString TextCondition
      | FormulaNumber NumberCondition
      | FormulaDate DateCondition
      | FormulaCheckbox CheckboxCondition

`RollupCondition` — rollup filters come in three flavors:

    data RollupCondition
      = RollupAny PropertyCondition
      | RollupEvery PropertyCondition
      | RollupNone PropertyCondition
      | RollupNumber NumberCondition
      | RollupDate DateCondition

The `ToJSON` instances must produce the exact JSON shapes the Notion API expects. For `Filter`:

    -- And:  {"and": [...]}
    -- Or:   {"or": [...]}
    -- PropertyFilter "Status" (SelectCondition (SelectEquals "Done")):
    --   {"property": "Status", "select": {"equals": "Done"}}
    -- TimestampFilter FilterCreatedTime (DateAfter "2024-01-01"):
    --   {"timestamp": "created_time", "created_time": {"after": "2024-01-01"}}

For `PropertyCondition`, the `ToJSON` produces a JSON object fragment (without the `"property"` key — that is added by the `Filter.ToJSON`). Each condition variant produces a key matching the property type and a nested object with the condition. For example, `SelectCondition (SelectEquals "Done")` produces `{"select": {"equals": "Done"}}`.

**Changes to `src/Notion/V1/Databases.hs`:**

Replace `filter :: Maybe Value` in `QueryDatabase` with `filter :: Maybe Filter`. Replace `sorts :: Maybe [Value]` with `sorts :: Maybe [Value]` (sorts are typed in Milestone 3). Add `import Notion.V1.Filter (Filter)`.

**Changes to `src/Notion/V1/DataSources.hs`:**

Replace `filter :: Maybe Value` in `QueryDataSource` with `filter :: Maybe Filter`. Add `import Notion.V1.Filter (Filter)`.

**Changes to `notion-client.cabal`:**

Add `Notion.V1.Filter` to `exposed-modules`. Add `scientific >= 0.3 && < 0.4` to `build-depends` if not already present.

**Tests in `tasty/Main.hs`:**

Add JSON serialization tests for:

1. A simple property filter: `PropertyFilter "Name" (TitleCondition (TextContains "test"))` should serialize to `{"property": "Name", "title": {"contains": "test"}}`.
2. A compound filter with `And`: `And [PropertyFilter "Status" (SelectCondition (SelectEquals "Done")), PropertyFilter "Priority" (SelectCondition (SelectEquals "High"))]`.
3. A timestamp filter: `TimestampFilter FilterCreatedTime (DateAfter "2024-01-01")`.
4. A number filter: `PropertyFilter "Score" (NumberCondition (NumGreaterThan 90))`.
5. A date filter with relative condition: `PropertyFilter "Due" (DateCondition DateNextWeek)`.
6. A formula filter: `PropertyFilter "Computed" (FormulaCondition (FormulaString (TextContains "yes")))`.

**Acceptance:** `cabal build all` succeeds. All filter serialization tests pass. The existing integration tests still pass (they may need minor updates if they construct filters — check and update as needed).


### Milestone 3: Typed Query Sorts

This milestone adds typed sort types to `Notion.V1.Filter` and replaces the `sorts :: Maybe [Value]` fields.

At the end of this milestone, users can construct sorts like:

    let mySorts =
          [ PropertySort "Name" Ascending
          , TimestampSort SortCreatedTime Descending
          ]

    let query = QueryDataSource
          { filter = Just myFilter
          , sorts = Just mySorts
          , ...
          }

**Types to add in `src/Notion/V1/Filter.hs`:**

`SortDirection` — an enum:

    data SortDirection = Ascending | Descending

The JSON values are `"ascending"` and `"descending"`.

`Sort` — a sum type:

    data Sort
      = PropertySort Text SortDirection
      | TimestampSort TimestampType SortDirection

`PropertySort "Name" Ascending` serializes as `{"property": "Name", "direction": "ascending"}`.

`TimestampSort SortCreatedTime Descending` serializes as `{"timestamp": "created_time", "direction": "descending"}`.

The `TimestampType` enum is already defined in Milestone 2 for timestamp filters. It is reused here. Its JSON serialization is `"created_time"` / `"last_edited_time"`.

**Changes to `src/Notion/V1/Databases.hs`:**

Replace `sorts :: Maybe [Value]` in `QueryDatabase` with `sorts :: Maybe [Sort]`. Add `Sort` to the import from `Notion.V1.Filter`.

**Changes to `src/Notion/V1/DataSources.hs`:**

Replace `sorts :: Maybe [Value]` in `QueryDataSource` with `sorts :: Maybe [Sort]`. Add `Sort` to the import from `Notion.V1.Filter`.

**Tests in `tasty/Main.hs`:**

Add JSON serialization tests for:

1. `PropertySort "Name" Ascending` serializes correctly.
2. `TimestampSort SortCreatedTime Descending` serializes correctly.
3. A list of mixed sorts serializes as a JSON array.

**Acceptance:** `cabal build all` succeeds. All sort serialization tests pass.


### Milestone 4: Update Example App and Validation

This milestone updates the example application to demonstrate the typed APIs and runs a full validation pass.

At the end of this milestone, the example app in `notion-client-example/DatabaseDemo.hs` constructs property schemas, filters, and sorts using typed values instead of raw `Aeson.Value`. The full test suite passes.

**Changes to `notion-client-example/DatabaseDemo.hs`:**

The current code constructs property schemas as raw `Aeson.object` calls (lines 79-151). Replace these with typed `PropertySchema` constructors. For example, the `Name` title property becomes:

    import Notion.V1.Properties (PropertySchema(..), SelectOption(..), SelectColor(..))

    let newDsProperties = Map.fromList
          [ ("Name", TitleSchema { schemaId = "", schemaName = "Name" })
          , ("Description", RichTextSchema { schemaId = "", schemaName = "Description" })
          ]

The Status and Priority select properties (lines 114-151) become:

    let statusOptions = Vector.fromList
          [ SelectOption { id = Nothing, name = "Not Started", color = Just Red }
          , SelectOption { id = Nothing, name = "In Progress", color = Just Yellow }
          , SelectOption { id = Nothing, name = "Done", color = Just Green }
          ]
        priorityOptions = Vector.fromList
          [ SelectOption { id = Nothing, name = "High", color = Just Red }
          , SelectOption { id = Nothing, name = "Medium", color = Just Yellow }
          , SelectOption { id = Nothing, name = "Low", color = Just Gray }
          ]
        combinedProperties = Map.fromList
          [ ("Status", SelectSchema { schemaId = "", schemaName = "Status", selectOptions = statusOptions })
          , ("Priority", SelectSchema { schemaId = "", schemaName = "Priority", selectOptions = priorityOptions })
          ]

The query construction (lines 62-69) gets a typed filter:

    import Notion.V1.Filter (Filter(..), PropertyCondition(..), SelectCondition(..), Sort(..), SortDirection(..))

    let dsQueryParams = QueryDataSource
          { filter = Nothing  -- or Just (PropertyFilter "Status" (SelectCondition (SelectEquals "Done")))
          , sorts = Just [PropertySort "Name" Ascending]
          , startCursor = Nothing
          , pageSize = Just 5
          , inTrash = Nothing
          }

**Changes to `tasty/Main.hs`:**

Update any integration tests that construct raw `Value` filters or property schemas to use the new typed constructors. The existing `testQueryDataSource` function likely passes `Nothing` for filter/sorts (verify and update if needed).

Add an E2E test that queries a data source with a typed filter and sort, verifying that the API accepts the serialized JSON and returns results.

**Changes to `CHANGELOG.md`:**

Add a new entry describing the typed property schema, filter, and sort additions.

**Acceptance:** `cabal build all` succeeds. `cabal test` passes all tests (unit and integration when token is available). The example app compiles and runs correctly.

    cabal build all
    cabal test


## Concrete Steps

All commands run from the repository root: `/Users/shinzui/Keikaku/bokuno/libraries/haskell/notion-client`.

After each milestone:

    cabal build all

Expected: compilation succeeds with no errors.

    cabal test

Expected: all tests pass with `OK` status.

After Milestone 4, optionally run the example:

    NOTION_TOKEN=<your-token> NOTION_TEST_DATABASE_ID=<db-id> cabal run notion-client-example

This section will be updated with specific outputs as implementation proceeds.


## Validation and Acceptance

**Compilation:** `cabal build all` must succeed after every milestone.

**Unit tests:** JSON serialization tests verify that typed Haskell values produce the JSON structures the Notion API expects, and that property schemas parsed from JSON match the expected typed values.

**Integration (manual):** After Milestone 4, run the example app and integration tests with a valid `NOTION_TOKEN` to verify that typed filters, sorts, and property schemas work correctly against the live API. Specifically:

1. Retrieve a data source and inspect its typed `properties` — verify select options have typed colors.
2. Query a data source with a typed filter (e.g., select equals) — verify results are returned.
3. Query a data source with a typed sort (e.g., property ascending) — verify results are ordered.
4. Create a data source with typed property schemas — verify the API accepts the request.

**Regression:** All 22+ existing tests must continue to pass. No existing public API types change shape in a breaking way (the `Value` -> typed replacements are a breaking change at the Haskell type level but a compatible change at the JSON wire level).


## Idempotence and Recovery

All steps are file edits and recompilation — fully idempotent. If a step fails partway:

- Compilation failures from partial edits: complete the edit or revert with `git checkout -- <file>`.
- Test failures: compare serialized JSON output against expected API format.
- `cabal build` always performs clean incremental builds; no cache clearing needed.

Each milestone commits its changes. To recover:

    git log --oneline -5
    git checkout <last-good-commit> -- src/ tasty/ notion-client-example/


## Interfaces and Dependencies

No new Cabal dependencies beyond `scientific` (which may already be a transitive dependency — verify). All types use existing libraries: `aeson`, `containers`, `text`, `vector`, `scientific`.

**New module interfaces at end of plan:**

In `src/Notion/V1/Properties.hs`, define and export:

    data SelectColor = DefaultColor | Gray | Brown | Orange | Yellow | Green | Blue | Purple | Pink | Red

    data SelectOption = SelectOption
      { id :: Maybe Text, name :: Text, color :: Maybe SelectColor }

    data StatusGroup = StatusGroup
      { id :: Maybe Text, name :: Text, color :: Maybe SelectColor, optionIds :: Vector Text }

    data NumberFormat = NumberPlain | NumberWithCommas | Percent | Dollar | ... (39 total)

    data RollupFunction = CountAll | CountValues | ... (25 total)

    data RelationType = SingleProperty | DualProperty { syncedPropertyId :: Text, syncedPropertyName :: Text }

    data PropertySchema
      = TitleSchema { schemaId :: Text, schemaName :: Text }
      | RichTextSchema { ... }
      | NumberSchema { ..., numberFormat :: NumberFormat }
      | SelectSchema { ..., selectOptions :: Vector SelectOption }
      | ... (23 constructors total)

In `src/Notion/V1/Filter.hs`, define and export:

    data Filter = And [Filter] | Or [Filter] | PropertyFilter Text PropertyCondition | TimestampFilter TimestampType DateCondition

    data PropertyCondition = TitleCondition TextCondition | RichTextCondition TextCondition | NumberCondition NumberCondition | ... (21 variants)

    data TextCondition = TextEquals Text | TextDoesNotEqual Text | TextContains Text | ...
    data NumberCondition = NumEquals Scientific | NumDoesNotEqual Scientific | ...
    data CheckboxCondition = CheckboxEquals Bool | CheckboxDoesNotEqual Bool
    data SelectCondition = SelectEquals Text | SelectDoesNotEqual Text | SelectIsEmpty | SelectIsNotEmpty
    data MultiSelectCondition = MultiSelectContains Text | MultiSelectDoesNotContain Text | ...
    data DateCondition = DateAfter Text | DateBefore Text | DateEquals Text | ... | DateNextWeek | DatePastYear
    data PeopleCondition = PeopleContains Text | PeopleDoesNotContain Text | ...
    data FilesCondition = FilesIsEmpty | FilesIsNotEmpty
    data RelationCondition = RelationContains Text | ...
    data StatusCondition = StatusEquals Text | ...
    data UniqueIdCondition = UniqueIdEquals Natural | ...
    data VerificationCondition = VerificationStatus Text
    data FormulaCondition = FormulaString TextCondition | FormulaNumber NumberCondition | ...
    data RollupCondition = RollupAny PropertyCondition | RollupEvery PropertyCondition | ...

    data TimestampType = FilterCreatedTime | FilterLastEditedTime

    data SortDirection = Ascending | Descending
    data Sort = PropertySort Text SortDirection | TimestampSort TimestampType SortDirection
