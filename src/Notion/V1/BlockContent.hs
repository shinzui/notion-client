-- | Typed block content for Notion API blocks.
--
-- Each Notion block carries a @type@ discriminator (e.g., @\"paragraph\"@,
-- @\"heading_1\"@, @\"code\"@) and the actual content nested under a key
-- matching that type name. This module replaces the untyped @Value@ with a
-- proper Haskell sum type so consumers can pattern-match on block types and
-- use smart constructors to build well-formed blocks.
module Notion.V1.BlockContent
  ( -- * Block content
    BlockContent (..),
    blockContentType,
    blockContentFields,
    parseBlockContent,

    -- * Block updates
    BlockUpdatePayload (..),
    BlockUpdateContent (..),
    ParagraphUpdate (..),
    HeadingUpdate (..),
    TextColorUpdate (..),
    ToDoUpdate (..),
    CodeUpdate (..),
    MediaUpdate (..),
    MediaSourceUpdate (..),
    UrlCaptionUpdate (..),
    TableUpdate (..),
    mkBlockUpdate,
    trashBlockUpdate,
    blockUpdateFromContent,

    -- * Supporting types
    CodeLanguage (..),
    MeetingNotesStatus (..),
    MeetingNotesChildren (..),
    MeetingCalendarEvent (..),
    MeetingRecording (..),
    FileSource (..),
    ListFormat (..),
    SyncedFrom (..),
    LinkTarget (..),

    -- * Smart constructors
    mkRichText,
    textBlock,
    paragraphBlock,
    headingBlock,
    bulletedListItemBlock,
    numberedListItemBlock,
    toDoBlock,
    toggleBlock,
    quoteBlock,
    calloutBlock,
    codeBlock,
    equationBlock,
    bookmarkBlock,
    dividerBlock,
    imageBlock,
    tabBlock,

    -- * Combinators
    withChildren,
  )
where

import Data.Aeson (object, (.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.Types (Pair, Parser)
import Data.Maybe (fromMaybe)
import Data.Vector qualified as Vector
import Notion.Prelude
import Notion.V1.Common (Color (..), ExternalFile (ExternalFile), File, Icon, UUID)
import Notion.V1.RichText (RichText (..), RichTextContent (..), TextContent (..), defaultAnnotations)

-- ---------------------------------------------------------------------------
-- Supporting types
-- ---------------------------------------------------------------------------

-- | Programming language for code blocks.
data CodeLanguage
  = Abap
  | Abc
  | Agda
  | Arduino
  | AsciiArt
  | Assembly
  | Bash
  | Basic
  | Bnf
  | C
  | Clojure
  | CoffeeScript
  | Coq
  | Cpp
  | CSharp
  | Css
  | Dart
  | Dhall
  | Diff
  | Docker
  | Ebnf
  | Elixir
  | Elm
  | Erlang
  | Flow
  | Fortran
  | FSharp
  | Gherkin
  | Glsl
  | Go
  | GraphQL
  | Groovy
  | Haskell
  | Hcl
  | Html
  | Idris
  | Java
  | JavaScript
  | Json
  | Julia
  | Kotlin
  | LaTeX
  | Less
  | Lisp
  | LiveScript
  | LlvmIr
  | Lua
  | Makefile
  | Markdown
  | Markup
  | Mathematica
  | Matlab
  | Mermaid
  | Nix
  | NotionFormula
  | ObjectiveC
  | OCaml
  | Pascal
  | Perl
  | Php
  | PlainText
  | PowerShell
  | Prolog
  | Protobuf
  | PureScript
  | Python
  | R
  | Racket
  | Reason
  | Ruby
  | Rust
  | Sass
  | Scala
  | Scheme
  | Scss
  | Shell
  | Smalltalk
  | Solidity
  | Sql
  | Swift
  | Toml
  | TypeScript
  | VbNet
  | Verilog
  | Vhdl
  | VisualBasic
  | WebAssembly
  | Xml
  | Yaml
  | JavaCCppCSharp
  | -- | A language this library does not know yet; holds the raw string.
    OtherLanguage Text
  deriving stock (Eq, Show, Generic)

instance FromJSON CodeLanguage where
  parseJSON = Aeson.withText "CodeLanguage" $ \case
    "abap" -> pure Abap
    "arduino" -> pure Arduino
    "bash" -> pure Bash
    "basic" -> pure Basic
    "c" -> pure C
    "clojure" -> pure Clojure
    "coffeescript" -> pure CoffeeScript
    "c++" -> pure Cpp
    "c#" -> pure CSharp
    "css" -> pure Css
    "dart" -> pure Dart
    "diff" -> pure Diff
    "docker" -> pure Docker
    "elixir" -> pure Elixir
    "elm" -> pure Elm
    "erlang" -> pure Erlang
    "flow" -> pure Flow
    "fortran" -> pure Fortran
    "f#" -> pure FSharp
    "gherkin" -> pure Gherkin
    "glsl" -> pure Glsl
    "go" -> pure Go
    "graphql" -> pure GraphQL
    "groovy" -> pure Groovy
    "haskell" -> pure Haskell
    "html" -> pure Html
    "java" -> pure Java
    "javascript" -> pure JavaScript
    "json" -> pure Json
    "julia" -> pure Julia
    "kotlin" -> pure Kotlin
    "latex" -> pure LaTeX
    "less" -> pure Less
    "lisp" -> pure Lisp
    "livescript" -> pure LiveScript
    "lua" -> pure Lua
    "makefile" -> pure Makefile
    "markdown" -> pure Markdown
    "markup" -> pure Markup
    "matlab" -> pure Matlab
    "mermaid" -> pure Mermaid
    "nix" -> pure Nix
    "objective-c" -> pure ObjectiveC
    "ocaml" -> pure OCaml
    "pascal" -> pure Pascal
    "perl" -> pure Perl
    "php" -> pure Php
    "plain text" -> pure PlainText
    "powershell" -> pure PowerShell
    "prolog" -> pure Prolog
    "protobuf" -> pure Protobuf
    "python" -> pure Python
    "r" -> pure R
    "reason" -> pure Reason
    "ruby" -> pure Ruby
    "rust" -> pure Rust
    "sass" -> pure Sass
    "scala" -> pure Scala
    "scheme" -> pure Scheme
    "scss" -> pure Scss
    "shell" -> pure Shell
    "sql" -> pure Sql
    "swift" -> pure Swift
    "typescript" -> pure TypeScript
    "vb.net" -> pure VbNet
    "verilog" -> pure Verilog
    "vhdl" -> pure Vhdl
    "visual basic" -> pure VisualBasic
    "webassembly" -> pure WebAssembly
    "xml" -> pure Xml
    "yaml" -> pure Yaml
    "abc" -> pure Abc
    "agda" -> pure Agda
    "ascii art" -> pure AsciiArt
    "assembly" -> pure Assembly
    "bnf" -> pure Bnf
    "coq" -> pure Coq
    "dhall" -> pure Dhall
    "ebnf" -> pure Ebnf
    "hcl" -> pure Hcl
    "idris" -> pure Idris
    "llvm ir" -> pure LlvmIr
    "mathematica" -> pure Mathematica
    "notion formula" -> pure NotionFormula
    "purescript" -> pure PureScript
    "racket" -> pure Racket
    "smalltalk" -> pure Smalltalk
    "solidity" -> pure Solidity
    "toml" -> pure Toml
    "java/c/c++/c#" -> pure JavaCCppCSharp
    other -> pure (OtherLanguage other)

instance ToJSON CodeLanguage where
  toJSON = \case
    Abap -> Aeson.String "abap"
    Arduino -> Aeson.String "arduino"
    Bash -> Aeson.String "bash"
    Basic -> Aeson.String "basic"
    C -> Aeson.String "c"
    Clojure -> Aeson.String "clojure"
    CoffeeScript -> Aeson.String "coffeescript"
    Cpp -> Aeson.String "c++"
    CSharp -> Aeson.String "c#"
    Css -> Aeson.String "css"
    Dart -> Aeson.String "dart"
    Diff -> Aeson.String "diff"
    Docker -> Aeson.String "docker"
    Elixir -> Aeson.String "elixir"
    Elm -> Aeson.String "elm"
    Erlang -> Aeson.String "erlang"
    Flow -> Aeson.String "flow"
    Fortran -> Aeson.String "fortran"
    FSharp -> Aeson.String "f#"
    Gherkin -> Aeson.String "gherkin"
    Glsl -> Aeson.String "glsl"
    Go -> Aeson.String "go"
    GraphQL -> Aeson.String "graphql"
    Groovy -> Aeson.String "groovy"
    Haskell -> Aeson.String "haskell"
    Html -> Aeson.String "html"
    Java -> Aeson.String "java"
    JavaScript -> Aeson.String "javascript"
    Json -> Aeson.String "json"
    Julia -> Aeson.String "julia"
    Kotlin -> Aeson.String "kotlin"
    LaTeX -> Aeson.String "latex"
    Less -> Aeson.String "less"
    Lisp -> Aeson.String "lisp"
    LiveScript -> Aeson.String "livescript"
    Lua -> Aeson.String "lua"
    Makefile -> Aeson.String "makefile"
    Markdown -> Aeson.String "markdown"
    Markup -> Aeson.String "markup"
    Matlab -> Aeson.String "matlab"
    Mermaid -> Aeson.String "mermaid"
    Nix -> Aeson.String "nix"
    ObjectiveC -> Aeson.String "objective-c"
    OCaml -> Aeson.String "ocaml"
    Pascal -> Aeson.String "pascal"
    Perl -> Aeson.String "perl"
    Php -> Aeson.String "php"
    PlainText -> Aeson.String "plain text"
    PowerShell -> Aeson.String "powershell"
    Prolog -> Aeson.String "prolog"
    Protobuf -> Aeson.String "protobuf"
    Python -> Aeson.String "python"
    R -> Aeson.String "r"
    Reason -> Aeson.String "reason"
    Ruby -> Aeson.String "ruby"
    Rust -> Aeson.String "rust"
    Sass -> Aeson.String "sass"
    Scala -> Aeson.String "scala"
    Scheme -> Aeson.String "scheme"
    Scss -> Aeson.String "scss"
    Shell -> Aeson.String "shell"
    Sql -> Aeson.String "sql"
    Swift -> Aeson.String "swift"
    TypeScript -> Aeson.String "typescript"
    VbNet -> Aeson.String "vb.net"
    Verilog -> Aeson.String "verilog"
    Vhdl -> Aeson.String "vhdl"
    VisualBasic -> Aeson.String "visual basic"
    WebAssembly -> Aeson.String "webassembly"
    Xml -> Aeson.String "xml"
    Yaml -> Aeson.String "yaml"
    Abc -> Aeson.String "abc"
    Agda -> Aeson.String "agda"
    AsciiArt -> Aeson.String "ascii art"
    Assembly -> Aeson.String "assembly"
    Bnf -> Aeson.String "bnf"
    Coq -> Aeson.String "coq"
    Dhall -> Aeson.String "dhall"
    Ebnf -> Aeson.String "ebnf"
    Hcl -> Aeson.String "hcl"
    Idris -> Aeson.String "idris"
    LlvmIr -> Aeson.String "llvm ir"
    Mathematica -> Aeson.String "mathematica"
    NotionFormula -> Aeson.String "notion formula"
    PureScript -> Aeson.String "purescript"
    Racket -> Aeson.String "racket"
    Smalltalk -> Aeson.String "smalltalk"
    Solidity -> Aeson.String "solidity"
    Toml -> Aeson.String "toml"
    JavaCCppCSharp -> Aeson.String "java/c/c++/c#"
    OtherLanguage t -> Aeson.String t

-- | Processing state of a meeting-notes block.
data MeetingNotesStatus
  = TranscriptionNotStarted
  | TranscriptionPaused
  | TranscriptionInProgress
  | TranscriptionFailed
  | SummaryInProgress
  | NotesReady
  | -- | A status this library does not know yet; holds the raw string.
    UnknownMeetingNotesStatus Text
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

instance ToJSON MeetingNotesStatus where
  toJSON = \case
    TranscriptionNotStarted -> Aeson.String "transcription_not_started"
    TranscriptionPaused -> Aeson.String "transcription_paused"
    TranscriptionInProgress -> Aeson.String "transcription_in_progress"
    TranscriptionFailed -> Aeson.String "transcription_failed"
    SummaryInProgress -> Aeson.String "summary_in_progress"
    NotesReady -> Aeson.String "notes_ready"
    UnknownMeetingNotesStatus t -> Aeson.String t

-- | IDs of the child blocks Notion creates under a meeting-notes block.
data MeetingNotesChildren = MeetingNotesChildren
  { summaryBlockId :: Maybe UUID,
    notesBlockId :: Maybe UUID,
    transcriptBlockId :: Maybe UUID
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON MeetingNotesChildren where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON MeetingNotesChildren where
  toJSON = genericToJSON aesonOptions

-- | Calendar event linked to a meeting; times are ISO 8601 strings as sent.
data MeetingCalendarEvent = MeetingCalendarEvent
  { calendarStartTime :: Text,
    calendarEndTime :: Text,
    calendarAttendees :: Maybe (Vector UUID)
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON MeetingCalendarEvent where
  parseJSON = Aeson.withObject "MeetingCalendarEvent" $ \o -> do
    calendarStartTime <- o .: "start_time"
    calendarEndTime <- o .: "end_time"
    calendarAttendees <- o .:? "attendees"
    pure MeetingCalendarEvent {..}

instance ToJSON MeetingCalendarEvent where
  toJSON MeetingCalendarEvent {..} =
    object $
      ["start_time" .= calendarStartTime, "end_time" .= calendarEndTime]
        <> maybe [] (\as -> ["attendees" .= as]) calendarAttendees

-- | Recording window of a meeting; times are ISO 8601 strings as sent.
data MeetingRecording = MeetingRecording
  { recordingStartTime :: Maybe Text,
    recordingEndTime :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON MeetingRecording where
  parseJSON = Aeson.withObject "MeetingRecording" $ \o -> do
    recordingStartTime <- o .:? "start_time"
    recordingEndTime <- o .:? "end_time"
    pure MeetingRecording {..}

instance ToJSON MeetingRecording where
  toJSON MeetingRecording {..} =
    object $
      maybe [] (\t -> ["start_time" .= t]) recordingStartTime
        <> maybe [] (\t -> ["end_time" .= t]) recordingEndTime

-- | File source for media blocks (image, video, audio, file, pdf).
--
-- The API uses a @type@ discriminator with values @\"external\"@, @\"file\"@,
-- or @\"file_upload\"@, and the content nested under the corresponding key.
data FileSource
  = ExternalSource ExternalFile
  | NotionSource File
  | FileUploadSource UUID
  deriving stock (Eq, Show)

parseFileSource :: Aeson.Object -> Parser FileSource
parseFileSource o = do
  srcType <- o .: "type"
  case srcType of
    "external" -> ExternalSource <$> o .: "external"
    "file" -> NotionSource <$> o .: "file"
    "file_upload" -> do
      uploadObj <- o .: "file_upload"
      FileUploadSource <$> uploadObj .: "id"
    other -> fail $ "Unknown file source type: " <> unpack (other :: Text)

instance FromJSON FileSource where
  parseJSON = \case
    Object o -> parseFileSource o
    _ -> fail "Expected object for FileSource"

instance ToJSON FileSource where
  toJSON = object . fileSourcePairs

fileSourcePairs :: FileSource -> [Pair]
fileSourcePairs = \case
  ExternalSource ef -> ["type" .= ("external" :: Text), "external" .= ef]
  NotionSource f -> ["type" .= ("file" :: Text), "file" .= f]
  FileUploadSource uid -> ["type" .= ("file_upload" :: Text), "file_upload" .= object ["id" .= uid]]

-- | List format for numbered list items.
data ListFormat
  = Numbers
  | Letters
  | Roman
  deriving stock (Eq, Show, Generic)

instance FromJSON ListFormat where
  parseJSON = Aeson.withText "ListFormat" $ \case
    "numbers" -> pure Numbers
    "letters" -> pure Letters
    "roman" -> pure Roman
    other -> fail $ "Unknown ListFormat: " <> unpack other

instance ToJSON ListFormat where
  toJSON = \case
    Numbers -> Aeson.String "numbers"
    Letters -> Aeson.String "letters"
    Roman -> Aeson.String "roman"

-- | Synced block origin. An original synced block has @synced_from: null@ in
-- the API; a reference points to the original block by ID.
data SyncedFrom
  = SyncedOriginal
  | SyncedReference UUID
  deriving stock (Eq, Show)

instance FromJSON SyncedFrom where
  parseJSON = \case
    Null -> pure SyncedOriginal
    Object o -> SyncedReference <$> o .: "block_id"
    _ -> fail "Expected null or object for SyncedFrom"

instance ToJSON SyncedFrom where
  toJSON SyncedOriginal = Null
  toJSON (SyncedReference bid) =
    object ["type" .= ("block_id" :: Text), "block_id" .= bid]

-- | Target of a @link_to_page@ block.
data LinkTarget
  = LinkToPage UUID
  | LinkToDatabase UUID
  | LinkToComment UUID
  deriving stock (Eq, Show)

instance FromJSON LinkTarget where
  parseJSON = \case
    Object o -> do
      t <- o .: "type"
      case t of
        "page_id" -> LinkToPage <$> o .: "page_id"
        "database_id" -> LinkToDatabase <$> o .: "database_id"
        "comment_id" -> LinkToComment <$> o .: "comment_id"
        other -> fail $ "Unknown LinkTarget type: " <> unpack (other :: Text)
    _ -> fail "Expected object for LinkTarget"

instance ToJSON LinkTarget where
  toJSON (LinkToPage pid) = object ["type" .= ("page_id" :: Text), "page_id" .= pid]
  toJSON (LinkToDatabase did) = object ["type" .= ("database_id" :: Text), "database_id" .= did]
  toJSON (LinkToComment cid) = object ["type" .= ("comment_id" :: Text), "comment_id" .= cid]

-- ---------------------------------------------------------------------------
-- BlockContent
-- ---------------------------------------------------------------------------

-- | Typed block content. Each constructor corresponds to one Notion block type.
--
-- Use the smart constructors ('paragraphBlock', 'headingBlock', 'codeBlock',
-- etc.) to build blocks conveniently, or construct values directly for full
-- control over all fields.
data BlockContent
  = -- | Paragraph block with rich text, color, and optional icon.
    ParagraphBlock
      { richText :: Vector RichText,
        color :: Color,
        paragraphIcon :: Maybe Icon,
        children :: Vector BlockContent
      }
  | -- | Heading level 1.
    --
    -- Children are only accepted by the API when @isToggleable@ is @True@.
    Heading1Block
      { richText :: Vector RichText,
        color :: Color,
        isToggleable :: Bool,
        children :: Vector BlockContent
      }
  | -- | Heading level 2.
    --
    -- Children are only accepted by the API when @isToggleable@ is @True@.
    Heading2Block
      { richText :: Vector RichText,
        color :: Color,
        isToggleable :: Bool,
        children :: Vector BlockContent
      }
  | -- | Heading level 3.
    --
    -- Children are only accepted by the API when @isToggleable@ is @True@.
    Heading3Block
      { richText :: Vector RichText,
        color :: Color,
        isToggleable :: Bool,
        children :: Vector BlockContent
      }
  | -- | Bulleted list item.
    BulletedListItemBlock
      { richText :: Vector RichText,
        color :: Color,
        children :: Vector BlockContent
      }
  | -- | Numbered list item with optional format and start index.
    NumberedListItemBlock
      { richText :: Vector RichText,
        color :: Color,
        listFormat :: Maybe ListFormat,
        listStartIndex :: Maybe Natural,
        children :: Vector BlockContent
      }
  | -- | To-do checkbox item.
    ToDoBlock
      { richText :: Vector RichText,
        color :: Color,
        checked :: Bool,
        children :: Vector BlockContent
      }
  | -- | Toggle block (content revealed on click).
    ToggleBlock
      { richText :: Vector RichText,
        color :: Color,
        children :: Vector BlockContent
      }
  | -- | Quote block.
    QuoteBlock
      { richText :: Vector RichText,
        color :: Color,
        children :: Vector BlockContent
      }
  | -- | Callout block with icon.
    CalloutBlock
      { richText :: Vector RichText,
        color :: Color,
        calloutIcon :: Maybe Icon,
        children :: Vector BlockContent
      }
  | -- | Code block with language.
    CodeBlock
      { richText :: Vector RichText,
        caption :: Vector RichText,
        language :: CodeLanguage
      }
  | -- | KaTeX equation block.
    EquationBlock
      { expression :: Text
      }
  | -- | Image block.
    ImageBlock
      { imageSource :: FileSource,
        caption :: Vector RichText
      }
  | -- | Video block.
    VideoBlock
      { videoSource :: FileSource,
        caption :: Vector RichText
      }
  | -- | Audio block.
    AudioBlock
      { audioSource :: FileSource,
        caption :: Vector RichText
      }
  | -- | File attachment block.
    FileBlock
      { fileSource :: FileSource,
        caption :: Vector RichText,
        fileName :: Maybe Text
      }
  | -- | PDF block.
    PdfBlock
      { pdfSource :: FileSource,
        caption :: Vector RichText
      }
  | -- | Bookmark block.
    BookmarkBlock
      { url :: Text,
        caption :: Vector RichText
      }
  | -- | Embed block.
    EmbedBlock
      { url :: Text,
        caption :: Vector RichText
      }
  | -- | Link to another page, database, or comment.
    LinkToPageBlock
      { linkTarget :: LinkTarget
      }
  | -- | Link preview (read-only).
    LinkPreviewBlock
      { url :: Text
      }
  | -- | Horizontal divider.
    DividerBlock
  | -- | Breadcrumb navigation.
    BreadcrumbBlock
  | -- | Table of contents.
    TableOfContentsBlock
      { color :: Color
      }
  | -- | Column list (container for columns).
    --
    -- Children must be 'ColumnBlock' values, with at least 2 entries.
    ColumnListBlock
      { children :: Vector BlockContent
      }
  | -- | Single column within a column list.
    ColumnBlock
      { widthRatio :: Maybe Double,
        children :: Vector BlockContent
      }
  | -- | Table block.
    --
    -- Children must be 'TableRowBlock' values.
    TableBlock
      { tableWidth :: Natural,
        hasColumnHeader :: Bool,
        hasRowHeader :: Bool,
        children :: Vector BlockContent
      }
  | -- | Table row.
    TableRowBlock
      { cells :: Vector (Vector RichText)
      }
  | -- | Child page reference (read-only, created via the Pages endpoint).
    ChildPageBlock
      { title :: Text
      }
  | -- | Child database reference (read-only, created via the Databases endpoint).
    ChildDatabaseBlock
      { title :: Text
      }
  | -- | Synced block (original or reference).
    --
    -- Children are only valid when @syncedFrom@ is 'SyncedOriginal'.
    SyncedBlockContent
      { syncedFrom :: SyncedFrom,
        children :: Vector BlockContent
      }
  | -- | Heading level 4.
    --
    -- Children are only accepted by the API when @isToggleable@ is @True@.
    Heading4Block
      { richText :: Vector RichText,
        color :: Color,
        isToggleable :: Bool,
        children :: Vector BlockContent
      }
  | -- | Tab block (container).
    TabBlock
      { children :: Vector BlockContent
      }
  | -- | Meeting notes block (read-only). Also decoded from the deprecated
    -- @transcription@ block type.
    MeetingNotesBlock
      { meetingTitle :: Maybe (Vector RichText),
        meetingStatus :: Maybe MeetingNotesStatus,
        calendarEvent :: Maybe MeetingCalendarEvent,
        recording :: Maybe MeetingRecording,
        meetingChildren :: Maybe MeetingNotesChildren
      }
  | -- | Template block (deprecated, but still returned by the API).
    TemplateBlock
      { richText :: Vector RichText,
        children :: Vector BlockContent
      }
  | -- | Block type the API does not support; carries the underlying
    -- @block_type@ when Notion reports it.
    UnsupportedBlock (Maybe Text)
  | -- | Fallback for block types not yet modeled.
    UnknownBlock Text Value
  deriving stock (Eq, Generic, Show)

-- ---------------------------------------------------------------------------
-- Serialization helpers
-- ---------------------------------------------------------------------------

-- | Include @\"children\"@ key only when the vector is non-empty.
childrenPairs :: Vector BlockContent -> [Pair]
childrenPairs cs
  | Vector.null cs = []
  | otherwise = ["children" .= cs]

-- | Extract the JSON type name from a 'BlockContent' value.
blockContentType :: BlockContent -> Text
blockContentType = fst . blockContentFields

-- | Decompose a 'BlockContent' into its JSON type name and inner content
-- value. This is the serialization primitive used by both 'ToJSON BlockContent'
-- (full format with @\"type\"@ key) and 'blockUpdateFromContent'.
blockContentFields :: BlockContent -> (Text, Value)
blockContentFields = \case
  ParagraphBlock {..} ->
    ( "paragraph",
      object $
        ["rich_text" .= richText, "color" .= color]
          <> maybe [] (\i -> ["icon" .= i]) paragraphIcon
          <> childrenPairs children
    )
  Heading1Block {..} ->
    ( "heading_1",
      object $
        ["rich_text" .= richText, "color" .= color, "is_toggleable" .= isToggleable]
          <> childrenPairs children
    )
  Heading2Block {..} ->
    ( "heading_2",
      object $
        ["rich_text" .= richText, "color" .= color, "is_toggleable" .= isToggleable]
          <> childrenPairs children
    )
  Heading3Block {..} ->
    ( "heading_3",
      object $
        ["rich_text" .= richText, "color" .= color, "is_toggleable" .= isToggleable]
          <> childrenPairs children
    )
  BulletedListItemBlock {..} ->
    ( "bulleted_list_item",
      object $
        ["rich_text" .= richText, "color" .= color]
          <> childrenPairs children
    )
  NumberedListItemBlock {..} ->
    ( "numbered_list_item",
      object $
        ["rich_text" .= richText, "color" .= color]
          <> maybe [] (\f -> ["list_format" .= f]) listFormat
          <> maybe [] (\i -> ["list_start_index" .= i]) listStartIndex
          <> childrenPairs children
    )
  ToDoBlock {..} ->
    ( "to_do",
      object $
        ["rich_text" .= richText, "color" .= color, "checked" .= checked]
          <> childrenPairs children
    )
  ToggleBlock {..} ->
    ( "toggle",
      object $
        ["rich_text" .= richText, "color" .= color]
          <> childrenPairs children
    )
  QuoteBlock {..} ->
    ( "quote",
      object $
        ["rich_text" .= richText, "color" .= color]
          <> childrenPairs children
    )
  CalloutBlock {..} ->
    ( "callout",
      object $
        ["rich_text" .= richText, "color" .= color]
          <> maybe [] (\i -> ["icon" .= i]) calloutIcon
          <> childrenPairs children
    )
  CodeBlock {..} ->
    ("code", object ["rich_text" .= richText, "caption" .= caption, "language" .= language])
  EquationBlock {..} ->
    ("equation", object ["expression" .= expression])
  ImageBlock {..} ->
    ("image", object $ fileSourcePairs imageSource <> ["caption" .= caption])
  VideoBlock {..} ->
    ("video", object $ fileSourcePairs videoSource <> ["caption" .= caption])
  AudioBlock {..} ->
    ("audio", object $ fileSourcePairs audioSource <> ["caption" .= caption])
  FileBlock {..} ->
    ( "file",
      object $
        fileSourcePairs fileSource
          <> ["caption" .= caption]
          <> maybe [] (\n -> ["name" .= n]) fileName
    )
  PdfBlock {..} ->
    ("pdf", object $ fileSourcePairs pdfSource <> ["caption" .= caption])
  BookmarkBlock {..} ->
    ("bookmark", object ["url" .= url, "caption" .= caption])
  EmbedBlock {..} ->
    ("embed", object ["url" .= url, "caption" .= caption])
  LinkToPageBlock {..} ->
    ("link_to_page", toJSON linkTarget)
  LinkPreviewBlock {..} ->
    ("link_preview", object ["url" .= url])
  DividerBlock ->
    ("divider", object [])
  BreadcrumbBlock ->
    ("breadcrumb", object [])
  TableOfContentsBlock {..} ->
    ("table_of_contents", object ["color" .= color])
  ColumnListBlock {..} ->
    ("column_list", object $ childrenPairs children)
  ColumnBlock {..} ->
    ( "column",
      object $
        maybe [] (\r -> ["width_ratio" .= r]) widthRatio
          <> childrenPairs children
    )
  TableBlock {..} ->
    ( "table",
      object $
        ["table_width" .= tableWidth, "has_column_header" .= hasColumnHeader, "has_row_header" .= hasRowHeader]
          <> childrenPairs children
    )
  TableRowBlock {..} ->
    ("table_row", object ["cells" .= cells])
  ChildPageBlock {..} ->
    ("child_page", object ["title" .= title])
  ChildDatabaseBlock {..} ->
    ("child_database", object ["title" .= title])
  SyncedBlockContent {..} ->
    ( "synced_block",
      object $
        ["synced_from" .= syncedFrom]
          <> childrenPairs children
    )
  Heading4Block {..} ->
    ( "heading_4",
      object $
        ["rich_text" .= richText, "color" .= color, "is_toggleable" .= isToggleable]
          <> childrenPairs children
    )
  TabBlock {..} ->
    ("tab", object $ childrenPairs children)
  MeetingNotesBlock {..} ->
    ( "meeting_notes",
      object $
        maybe [] (\t -> ["title" .= t]) meetingTitle
          <> maybe [] (\s -> ["status" .= s]) meetingStatus
          <> maybe [] (\ce -> ["calendar_event" .= ce]) calendarEvent
          <> maybe [] (\r -> ["recording" .= r]) recording
          <> maybe [] (\c -> ["children" .= c]) meetingChildren
    )
  TemplateBlock {..} ->
    ( "template",
      object $
        ["rich_text" .= richText]
          <> childrenPairs children
    )
  UnsupportedBlock blockType ->
    ("unsupported", object (maybe [] (\t -> ["block_type" .= t]) blockType))
  UnknownBlock typeName val ->
    (typeName, val)

-- ---------------------------------------------------------------------------
-- JSON instances
-- ---------------------------------------------------------------------------

-- | Parse block content from a type name and the inner JSON value (the value
-- under the type key). This is called by 'BlockObject'\'s 'FromJSON' instance
-- and by the standalone 'FromJSON BlockContent'.
parseBlockContent :: Text -> Value -> Parser BlockContent
parseBlockContent typeName val = case typeName of
  "paragraph" -> parseObj $ \o -> do
    richText <- o .: "rich_text"
    color <- fromMaybe Default <$> o .:? "color"
    paragraphIcon <- o .:? "icon"
    children <- fromMaybe Vector.empty <$> o .:? "children"
    pure ParagraphBlock {..}
  "heading_1" -> parseObj $ \o -> do
    richText <- o .: "rich_text"
    color <- fromMaybe Default <$> o .:? "color"
    isToggleable <- fromMaybe False <$> o .:? "is_toggleable"
    children <- fromMaybe Vector.empty <$> o .:? "children"
    pure Heading1Block {..}
  "heading_2" -> parseObj $ \o -> do
    richText <- o .: "rich_text"
    color <- fromMaybe Default <$> o .:? "color"
    isToggleable <- fromMaybe False <$> o .:? "is_toggleable"
    children <- fromMaybe Vector.empty <$> o .:? "children"
    pure Heading2Block {..}
  "heading_3" -> parseObj $ \o -> do
    richText <- o .: "rich_text"
    color <- fromMaybe Default <$> o .:? "color"
    isToggleable <- fromMaybe False <$> o .:? "is_toggleable"
    children <- fromMaybe Vector.empty <$> o .:? "children"
    pure Heading3Block {..}
  "bulleted_list_item" -> parseObj $ \o -> do
    richText <- o .: "rich_text"
    color <- fromMaybe Default <$> o .:? "color"
    children <- fromMaybe Vector.empty <$> o .:? "children"
    pure BulletedListItemBlock {..}
  "numbered_list_item" -> parseObj $ \o -> do
    richText <- o .: "rich_text"
    color <- fromMaybe Default <$> o .:? "color"
    listFormat <- o .:? "list_format"
    listStartIndex <- o .:? "list_start_index"
    children <- fromMaybe Vector.empty <$> o .:? "children"
    pure NumberedListItemBlock {..}
  "to_do" -> parseObj $ \o -> do
    richText <- o .: "rich_text"
    color <- fromMaybe Default <$> o .:? "color"
    checked <- fromMaybe False <$> o .:? "checked"
    children <- fromMaybe Vector.empty <$> o .:? "children"
    pure ToDoBlock {..}
  "toggle" -> parseObj $ \o -> do
    richText <- o .: "rich_text"
    color <- fromMaybe Default <$> o .:? "color"
    children <- fromMaybe Vector.empty <$> o .:? "children"
    pure ToggleBlock {..}
  "quote" -> parseObj $ \o -> do
    richText <- o .: "rich_text"
    color <- fromMaybe Default <$> o .:? "color"
    children <- fromMaybe Vector.empty <$> o .:? "children"
    pure QuoteBlock {..}
  "callout" -> parseObj $ \o -> do
    richText <- o .: "rich_text"
    color <- fromMaybe Default <$> o .:? "color"
    calloutIcon <- o .:? "icon"
    children <- fromMaybe Vector.empty <$> o .:? "children"
    pure CalloutBlock {..}
  "code" -> parseObj $ \o -> do
    richText <- o .: "rich_text"
    caption <- fromMaybe Vector.empty <$> o .:? "caption"
    language <- o .: "language"
    pure CodeBlock {..}
  "equation" -> parseObj $ \o -> do
    expression <- o .: "expression"
    pure EquationBlock {..}
  "image" -> parseObj $ \o -> do
    imageSource <- parseFileSource o
    caption <- fromMaybe Vector.empty <$> o .:? "caption"
    pure ImageBlock {..}
  "video" -> parseObj $ \o -> do
    videoSource <- parseFileSource o
    caption <- fromMaybe Vector.empty <$> o .:? "caption"
    pure VideoBlock {..}
  "audio" -> parseObj $ \o -> do
    audioSource <- parseFileSource o
    caption <- fromMaybe Vector.empty <$> o .:? "caption"
    pure AudioBlock {..}
  "file" -> parseObj $ \o -> do
    fileSource <- parseFileSource o
    caption <- fromMaybe Vector.empty <$> o .:? "caption"
    fileName <- o .:? "name"
    pure FileBlock {..}
  "pdf" -> parseObj $ \o -> do
    pdfSource <- parseFileSource o
    caption <- fromMaybe Vector.empty <$> o .:? "caption"
    pure PdfBlock {..}
  "bookmark" -> parseObj $ \o -> do
    url <- o .: "url"
    caption <- fromMaybe Vector.empty <$> o .:? "caption"
    pure BookmarkBlock {..}
  "embed" -> parseObj $ \o -> do
    url <- o .: "url"
    caption <- fromMaybe Vector.empty <$> o .:? "caption"
    pure EmbedBlock {..}
  "link_to_page" -> do
    linkTarget <- Aeson.parseJSON val
    pure LinkToPageBlock {..}
  "link_preview" -> parseObj $ \o -> do
    url <- o .: "url"
    pure LinkPreviewBlock {..}
  "divider" -> pure DividerBlock
  "breadcrumb" -> pure BreadcrumbBlock
  "table_of_contents" -> parseObj $ \o -> do
    color <- fromMaybe Default <$> o .:? "color"
    pure TableOfContentsBlock {..}
  "column_list" -> parseObj $ \o -> do
    children <- fromMaybe Vector.empty <$> o .:? "children"
    pure ColumnListBlock {..}
  "column" -> parseObj $ \o -> do
    widthRatio <- o .:? "width_ratio"
    children <- fromMaybe Vector.empty <$> o .:? "children"
    pure ColumnBlock {..}
  "table" -> parseObj $ \o -> do
    tableWidth <- o .: "table_width"
    hasColumnHeader <- o .: "has_column_header"
    hasRowHeader <- o .: "has_row_header"
    children <- fromMaybe Vector.empty <$> o .:? "children"
    pure TableBlock {..}
  "table_row" -> parseObj $ \o -> do
    cells <- o .: "cells"
    pure TableRowBlock {..}
  "child_page" -> parseObj $ \o -> do
    title <- o .: "title"
    pure ChildPageBlock {..}
  "child_database" -> parseObj $ \o -> do
    title <- o .: "title"
    pure ChildDatabaseBlock {..}
  "synced_block" -> parseObj $ \o -> do
    syncedFrom <- o .: "synced_from"
    children <- fromMaybe Vector.empty <$> o .:? "children"
    pure SyncedBlockContent {..}
  "heading_4" -> parseObj $ \o -> do
    richText <- o .: "rich_text"
    color <- fromMaybe Default <$> o .:? "color"
    isToggleable <- fromMaybe False <$> o .:? "is_toggleable"
    children <- fromMaybe Vector.empty <$> o .:? "children"
    pure Heading4Block {..}
  "tab" -> parseObj $ \o -> do
    children <- fromMaybe Vector.empty <$> o .:? "children"
    pure TabBlock {..}
  "meeting_notes" -> parseMeetingNotes
  "transcription" -> parseMeetingNotes
  "template" -> parseObj $ \o -> do
    richText <- o .: "rich_text"
    children <- fromMaybe Vector.empty <$> o .:? "children"
    pure TemplateBlock {..}
  "unsupported" -> case val of
    Object o -> UnsupportedBlock <$> o .:? "block_type"
    _ -> pure (UnsupportedBlock Nothing)
  _ -> pure (UnknownBlock typeName val)
  where
    parseMeetingNotes = parseObj $ \o -> do
      meetingTitle <- o .:? "title"
      meetingStatus <- o .:? "status"
      calendarEvent <- o .:? "calendar_event"
      recording <- o .:? "recording"
      meetingChildren <- o .:? "children"
      pure MeetingNotesBlock {..}
    parseObj :: (Aeson.Object -> Parser BlockContent) -> Parser BlockContent
    parseObj f = case val of
      Object o -> f o
      _ -> fail $ "Expected object for block type " <> unpack typeName

instance FromJSON BlockContent where
  parseJSON = \case
    Object o -> do
      typeName <- o .: "type"
      contentVal <- o .: Key.fromText typeName
      parseBlockContent typeName contentVal
    _ -> fail "Expected object for BlockContent"

instance ToJSON BlockContent where
  toJSON bc =
    let (typeName, inner) = blockContentFields bc
     in object ["type" .= typeName, Key.fromText typeName .= inner]

-- ---------------------------------------------------------------------------
-- Block updates
-- ---------------------------------------------------------------------------

-- | Body of @PATCH \/v1\/blocks\/{block_id}@. Every field is optional: send
-- only 'inTrash' to trash or restore a block ('trashBlockUpdate').
--
-- Updates are a different shape from block creation: no update accepts
-- @children@, a table update accepts only its header flags, and some block
-- types cannot be updated at all. Build one with 'mkBlockUpdate', or convert
-- full block content with 'blockUpdateFromContent'.
data BlockUpdatePayload = BlockUpdatePayload
  { -- | Named @updateContent@ so it does not clash with
    -- 'Notion.V1.Blocks.BlockObject'\'s @content@.
    updateContent :: Maybe BlockUpdateContent,
    inTrash :: Maybe Bool
  }
  deriving stock (Eq, Generic, Show)

-- | Paragraph and callout update. Every field is optional.
data ParagraphUpdate = ParagraphUpdate
  { richText :: Maybe (Vector RichText),
    color :: Maybe Color,
    icon :: Maybe Icon
  }
  deriving stock (Eq, Generic, Show)

-- | Heading update. The API requires the rich text.
data HeadingUpdate = HeadingUpdate
  { richText :: Vector RichText,
    color :: Maybe Color,
    isToggleable :: Maybe Bool
  }
  deriving stock (Eq, Generic, Show)

-- | List item, quote and toggle update. The API requires the rich text.
data TextColorUpdate = TextColorUpdate
  { richText :: Vector RichText,
    color :: Maybe Color
  }
  deriving stock (Eq, Generic, Show)

-- | To-do update. Every field is optional.
data ToDoUpdate = ToDoUpdate
  { richText :: Maybe (Vector RichText),
    checked :: Maybe Bool,
    color :: Maybe Color
  }
  deriving stock (Eq, Generic, Show)

-- | Code block update. Every field is optional.
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

-- | Image, video, PDF, audio and file update.
data MediaUpdate = MediaUpdate
  { caption :: Maybe (Vector RichText),
    source :: Maybe MediaSourceUpdate
  }
  deriving stock (Eq, Generic, Show)

-- | Embed and bookmark update.
data UrlCaptionUpdate = UrlCaptionUpdate
  { url :: Maybe Text,
    caption :: Maybe (Vector RichText)
  }
  deriving stock (Eq, Generic, Show)

-- | Table update: only the header flags can change.
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

instance ToJSON BlockUpdatePayload where
  toJSON BlockUpdatePayload {..} =
    object $
      maybe [] (\c -> let (k, v) = blockUpdateFields c in [Key.fromText k .= v]) updateContent
        <> maybe [] (\t -> ["in_trash" .= t]) inTrash

-- | The block type key and inner object of an update.
blockUpdateFields :: BlockUpdateContent -> (Text, Value)
blockUpdateFields = \case
  UpdateParagraph u -> ("paragraph", paragraphUpdate u)
  UpdateHeading1 u -> ("heading_1", headingUpdate u)
  UpdateHeading2 u -> ("heading_2", headingUpdate u)
  UpdateHeading3 u -> ("heading_3", headingUpdate u)
  UpdateHeading4 u -> ("heading_4", headingUpdate u)
  UpdateBulletedListItem u -> ("bulleted_list_item", textColorUpdate u)
  UpdateNumberedListItem u -> ("numbered_list_item", textColorUpdate u)
  UpdateQuote u -> ("quote", textColorUpdate u)
  UpdateToggle u -> ("toggle", textColorUpdate u)
  UpdateToDo ToDoUpdate {..} ->
    ( "to_do",
      object $ opt "rich_text" richText <> opt "checked" checked <> opt "color" color
    )
  UpdateCallout u -> ("callout", paragraphUpdate u)
  UpdateTemplateBlock rt -> ("template", object ["rich_text" .= rt])
  UpdateCode CodeUpdate {..} ->
    ( "code",
      object $ opt "rich_text" richText <> opt "language" language <> opt "caption" caption
    )
  UpdateEquation e -> ("equation", object ["expression" .= e])
  UpdateImage u -> ("image", object (mediaUpdatePairs u))
  UpdateVideo u -> ("video", object (mediaUpdatePairs u))
  UpdatePdf u -> ("pdf", object (mediaUpdatePairs u))
  UpdateAudio u -> ("audio", object (mediaUpdatePairs u))
  UpdateFile u name -> ("file", object (mediaUpdatePairs u <> opt "name" name))
  UpdateEmbed u -> ("embed", urlCaptionUpdate u)
  UpdateBookmark u -> ("bookmark", urlCaptionUpdate u)
  UpdateDivider -> ("divider", object [])
  UpdateBreadcrumb -> ("breadcrumb", object [])
  UpdateTab -> ("tab", object [])
  UpdateTableOfContents c -> ("table_of_contents", object (opt "color" c))
  UpdateLinkToPage t -> ("link_to_page", toJSON t)
  UpdateTableRow cells -> ("table_row", object ["cells" .= cells])
  UpdateSyncedBlock sf -> ("synced_block", object ["synced_from" .= sf])
  UpdateTable TableUpdate {..} ->
    ( "table",
      object $ opt "has_column_header" hasColumnHeader <> opt "has_row_header" hasRowHeader
    )
  UpdateColumn r -> ("column", object (opt "width_ratio" r))
  where
    opt :: (ToJSON a) => Aeson.Key -> Maybe a -> [Pair]
    opt k = maybe [] (\v -> [k .= v])
    paragraphUpdate ParagraphUpdate {..} =
      object $ opt "rich_text" richText <> opt "color" color <> opt "icon" icon
    headingUpdate HeadingUpdate {..} =
      object $ ["rich_text" .= richText] <> opt "color" color <> opt "is_toggleable" isToggleable
    textColorUpdate TextColorUpdate {..} =
      object $ ["rich_text" .= richText] <> opt "color" color
    urlCaptionUpdate UrlCaptionUpdate {..} =
      object $ opt "url" url <> opt "caption" caption
    mediaUpdatePairs MediaUpdate {..} =
      opt "caption" caption
        <> case source of
          Nothing -> []
          Just (UpdateExternalSource u) -> ["external" .= object ["url" .= u]]
          Just (UpdateFileUploadSource i) -> ["file_upload" .= object ["id" .= i]]

-- | An update that changes the given block content.
mkBlockUpdate :: BlockUpdateContent -> BlockUpdatePayload
mkBlockUpdate c = BlockUpdatePayload {updateContent = Just c, inTrash = Nothing}

-- | An update that moves the block to the trash: @{"in_trash": true}@.
trashBlockUpdate :: BlockUpdatePayload
trashBlockUpdate = BlockUpdatePayload {updateContent = Nothing, inTrash = Just True}

-- | Convert full block content to the equivalent \"set every updatable
-- field\" update. Returns 'Nothing' for block types the API cannot update
-- (child_page, child_database, column_list, link_preview, meeting_notes,
-- unsupported, unknown). Read-only fields (@table_width@, @children@,
-- @list_format@, @list_start_index@, Notion-hosted file URLs) are dropped.
blockUpdateFromContent :: BlockContent -> Maybe BlockUpdateContent
blockUpdateFromContent = \case
  ParagraphBlock {..} -> Just (UpdateParagraph (ParagraphUpdate (Just richText) (Just color) paragraphIcon))
  Heading1Block {..} -> Just (UpdateHeading1 (HeadingUpdate richText (Just color) (Just isToggleable)))
  Heading2Block {..} -> Just (UpdateHeading2 (HeadingUpdate richText (Just color) (Just isToggleable)))
  Heading3Block {..} -> Just (UpdateHeading3 (HeadingUpdate richText (Just color) (Just isToggleable)))
  Heading4Block {..} -> Just (UpdateHeading4 (HeadingUpdate richText (Just color) (Just isToggleable)))
  BulletedListItemBlock {..} -> Just (UpdateBulletedListItem (TextColorUpdate richText (Just color)))
  NumberedListItemBlock {..} -> Just (UpdateNumberedListItem (TextColorUpdate richText (Just color)))
  ToDoBlock {..} -> Just (UpdateToDo (ToDoUpdate (Just richText) (Just checked) (Just color)))
  ToggleBlock {..} -> Just (UpdateToggle (TextColorUpdate richText (Just color)))
  QuoteBlock {..} -> Just (UpdateQuote (TextColorUpdate richText (Just color)))
  CalloutBlock {..} -> Just (UpdateCallout (ParagraphUpdate (Just richText) (Just color) calloutIcon))
  CodeBlock {..} -> Just (UpdateCode (CodeUpdate (Just richText) (Just language) (Just caption)))
  EquationBlock {..} -> Just (UpdateEquation expression)
  ImageBlock {..} -> Just (UpdateImage (media imageSource caption))
  VideoBlock {..} -> Just (UpdateVideo (media videoSource caption))
  AudioBlock {..} -> Just (UpdateAudio (media audioSource caption))
  PdfBlock {..} -> Just (UpdatePdf (media pdfSource caption))
  FileBlock {..} -> Just (UpdateFile (media fileSource caption) fileName)
  BookmarkBlock {..} -> Just (UpdateBookmark (UrlCaptionUpdate (Just url) (Just caption)))
  EmbedBlock {..} -> Just (UpdateEmbed (UrlCaptionUpdate (Just url) (Just caption)))
  LinkToPageBlock {..} -> Just (UpdateLinkToPage linkTarget)
  DividerBlock -> Just UpdateDivider
  BreadcrumbBlock -> Just UpdateBreadcrumb
  TableOfContentsBlock {..} -> Just (UpdateTableOfContents (Just color))
  ColumnBlock {..} -> Just (UpdateColumn widthRatio)
  TableBlock {..} -> Just (UpdateTable (TableUpdate (Just hasColumnHeader) (Just hasRowHeader)))
  TableRowBlock {..} -> Just (UpdateTableRow cells)
  SyncedBlockContent {..} -> Just (UpdateSyncedBlock syncedFrom)
  TabBlock {} -> Just UpdateTab
  TemplateBlock {..} -> Just (UpdateTemplateBlock richText)
  LinkPreviewBlock {} -> Nothing
  ColumnListBlock {} -> Nothing
  ChildPageBlock {} -> Nothing
  ChildDatabaseBlock {} -> Nothing
  MeetingNotesBlock {} -> Nothing
  UnsupportedBlock _ -> Nothing
  UnknownBlock _ _ -> Nothing
  where
    media src cap = MediaUpdate (Just cap) (sourceUpdate src)
    sourceUpdate = \case
      ExternalSource (ExternalFile u) -> Just (UpdateExternalSource u)
      FileUploadSource i -> Just (UpdateFileUploadSource i)
      NotionSource _ -> Nothing

-- ---------------------------------------------------------------------------
-- Smart constructors
-- ---------------------------------------------------------------------------

-- | Build a 'RichText' vector containing a single plain-text segment.
-- This is the most common way to create block content.
mkRichText :: Text -> Vector RichText
mkRichText t =
  Vector.singleton
    RichText
      { plainText = t,
        href = Nothing,
        annotations = defaultAnnotations,
        type_ = "text",
        content = TextContentWrapper (TextContent {content = t, link = Nothing})
      }

-- | Create a paragraph block from plain text.
textBlock :: Text -> BlockContent
textBlock = paragraphBlock . mkRichText

-- | Create a paragraph block.
paragraphBlock :: Vector RichText -> BlockContent
paragraphBlock rt = ParagraphBlock rt Default Nothing Vector.empty

-- | Create a heading block at the given level (1, 2, 3, or 4; defaults to 3).
headingBlock :: Int -> Vector RichText -> BlockContent
headingBlock 1 rt = Heading1Block rt Default False Vector.empty
headingBlock 2 rt = Heading2Block rt Default False Vector.empty
headingBlock 4 rt = Heading4Block rt Default False Vector.empty
headingBlock _ rt = Heading3Block rt Default False Vector.empty

-- | Create a bulleted list item block.
bulletedListItemBlock :: Vector RichText -> BlockContent
bulletedListItemBlock rt = BulletedListItemBlock rt Default Vector.empty

-- | Create a numbered list item block.
numberedListItemBlock :: Vector RichText -> BlockContent
numberedListItemBlock rt = NumberedListItemBlock rt Default Nothing Nothing Vector.empty

-- | Create a to-do block.
toDoBlock :: Vector RichText -> Bool -> BlockContent
toDoBlock rt isChecked = ToDoBlock rt Default isChecked Vector.empty

-- | Create a toggle block.
toggleBlock :: Vector RichText -> BlockContent
toggleBlock rt = ToggleBlock rt Default Vector.empty

-- | Create a quote block.
quoteBlock :: Vector RichText -> BlockContent
quoteBlock rt = QuoteBlock rt Default Vector.empty

-- | Create a callout block with an optional icon.
calloutBlock :: Vector RichText -> Maybe Icon -> BlockContent
calloutBlock rt icon = CalloutBlock rt Default icon Vector.empty

-- | Create a code block with a language.
codeBlock :: Vector RichText -> CodeLanguage -> BlockContent
codeBlock rt lang = CodeBlock rt Vector.empty lang

-- | Create an equation block from a KaTeX expression.
equationBlock :: Text -> BlockContent
equationBlock = EquationBlock

-- | Create a bookmark block from a URL.
bookmarkBlock :: Text -> BlockContent
bookmarkBlock u = BookmarkBlock u Vector.empty

-- | Create a divider block.
dividerBlock :: BlockContent
dividerBlock = DividerBlock

-- | Create an image block from a file source.
imageBlock :: FileSource -> BlockContent
imageBlock src = ImageBlock src Vector.empty

-- | Build a tab block. Each tab item is a paragraph (its title), an optional
-- icon, and the tab's content blocks — the only child shape the API accepts.
tabBlock :: Vector (Vector RichText, Maybe Icon, Vector BlockContent) -> BlockContent
tabBlock items =
  TabBlock (fmap (\(rt, ic, cs) -> ParagraphBlock rt Default ic cs) items)

-- | Attach children to a block. For constructors that do not support
-- children, the block is returned unchanged.
withChildren :: BlockContent -> Vector BlockContent -> BlockContent
withChildren block cs = case block of
  ParagraphBlock {} -> block {children = cs}
  Heading1Block {} -> block {children = cs}
  Heading2Block {} -> block {children = cs}
  Heading3Block {} -> block {children = cs}
  BulletedListItemBlock {} -> block {children = cs}
  NumberedListItemBlock {} -> block {children = cs}
  ToDoBlock {} -> block {children = cs}
  ToggleBlock {} -> block {children = cs}
  QuoteBlock {} -> block {children = cs}
  CalloutBlock {} -> block {children = cs}
  ColumnListBlock {} -> block {children = cs}
  ColumnBlock {} -> block {children = cs}
  TableBlock {} -> block {children = cs}
  SyncedBlockContent {} -> block {children = cs}
  Heading4Block {} -> block {children = cs}
  TabBlock {} -> block {children = cs}
  TemplateBlock {} -> block {children = cs}
  _ -> block
