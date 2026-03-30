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

    -- * Block update wrapper
    BlockUpdate (..),

    -- * Supporting types
    CodeLanguage (..),
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
  )
where

import Data.Aeson (object, (.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.Types (Pair, Parser)
import Data.Maybe (fromMaybe)
import Data.Vector qualified as Vector
import Notion.Prelude
import Notion.V1.Common (Color (..), ExternalFile, File, Icon, UUID)
import Notion.V1.RichText (RichText (..), RichTextContent (..), TextContent (..), defaultAnnotations)

-- ---------------------------------------------------------------------------
-- Supporting types
-- ---------------------------------------------------------------------------

-- | Programming language for code blocks.
data CodeLanguage
  = Abap
  | Arduino
  | Bash
  | Basic
  | C
  | Clojure
  | CoffeeScript
  | Cpp
  | CSharp
  | Css
  | Dart
  | Diff
  | Docker
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
  | Html
  | Java
  | JavaScript
  | Json
  | Julia
  | Kotlin
  | LaTeX
  | Less
  | Lisp
  | LiveScript
  | Lua
  | Makefile
  | Markdown
  | Markup
  | Matlab
  | Mermaid
  | Nix
  | ObjectiveC
  | OCaml
  | Pascal
  | Perl
  | Php
  | PlainText
  | PowerShell
  | Prolog
  | Protobuf
  | Python
  | R
  | Reason
  | Ruby
  | Rust
  | Sass
  | Scala
  | Scheme
  | Scss
  | Shell
  | Sql
  | Swift
  | TypeScript
  | VbNet
  | Verilog
  | Vhdl
  | VisualBasic
  | WebAssembly
  | Xml
  | Yaml
  | JavaCCppCSharp
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
    "java/c/c++/c#" -> pure JavaCCppCSharp
    other -> fail $ "Unknown CodeLanguage: " <> unpack other

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
    JavaCCppCSharp -> Aeson.String "java/c/c++/c#"

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
        paragraphIcon :: Maybe Icon
      }
  | -- | Heading level 1.
    Heading1Block
      { richText :: Vector RichText,
        color :: Color,
        isToggleable :: Bool
      }
  | -- | Heading level 2.
    Heading2Block
      { richText :: Vector RichText,
        color :: Color,
        isToggleable :: Bool
      }
  | -- | Heading level 3.
    Heading3Block
      { richText :: Vector RichText,
        color :: Color,
        isToggleable :: Bool
      }
  | -- | Bulleted list item.
    BulletedListItemBlock
      { richText :: Vector RichText,
        color :: Color
      }
  | -- | Numbered list item with optional format and start index.
    NumberedListItemBlock
      { richText :: Vector RichText,
        color :: Color,
        listFormat :: Maybe ListFormat,
        listStartIndex :: Maybe Natural
      }
  | -- | To-do checkbox item.
    ToDoBlock
      { richText :: Vector RichText,
        color :: Color,
        checked :: Bool
      }
  | -- | Toggle block (content revealed on click).
    ToggleBlock
      { richText :: Vector RichText,
        color :: Color
      }
  | -- | Quote block.
    QuoteBlock
      { richText :: Vector RichText,
        color :: Color
      }
  | -- | Callout block with icon.
    CalloutBlock
      { richText :: Vector RichText,
        color :: Color,
        calloutIcon :: Maybe Icon
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
      { audioSource :: FileSource
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
      { url :: Text
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
    ColumnListBlock
  | -- | Single column within a column list.
    ColumnBlock
  | -- | Table block.
    TableBlock
      { tableWidth :: Natural,
        hasColumnHeader :: Bool,
        hasRowHeader :: Bool
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
    SyncedBlockContent
      { syncedFrom :: SyncedFrom
      }
  | -- | Unsupported block type returned by the API.
    UnsupportedBlock
  | -- | Fallback for block types not yet modeled.
    UnknownBlock Text Value
  deriving stock (Eq, Generic, Show)

-- ---------------------------------------------------------------------------
-- Serialization helpers
-- ---------------------------------------------------------------------------

-- | Extract the JSON type name from a 'BlockContent' value.
blockContentType :: BlockContent -> Text
blockContentType = fst . blockContentFields

-- | Decompose a 'BlockContent' into its JSON type name and inner content
-- value. This is the serialization primitive used by both 'ToJSON BlockContent'
-- (full format with @\"type\"@ key) and 'ToJSON BlockUpdate' (update format
-- without @\"type\"@ key).
blockContentFields :: BlockContent -> (Text, Value)
blockContentFields = \case
  ParagraphBlock {..} ->
    ( "paragraph",
      object $
        ["rich_text" .= richText, "color" .= color]
          <> maybe [] (\i -> ["icon" .= i]) paragraphIcon
    )
  Heading1Block {..} ->
    ("heading_1", object ["rich_text" .= richText, "color" .= color, "is_toggleable" .= isToggleable])
  Heading2Block {..} ->
    ("heading_2", object ["rich_text" .= richText, "color" .= color, "is_toggleable" .= isToggleable])
  Heading3Block {..} ->
    ("heading_3", object ["rich_text" .= richText, "color" .= color, "is_toggleable" .= isToggleable])
  BulletedListItemBlock {..} ->
    ("bulleted_list_item", object ["rich_text" .= richText, "color" .= color])
  NumberedListItemBlock {..} ->
    ( "numbered_list_item",
      object $
        ["rich_text" .= richText, "color" .= color]
          <> maybe [] (\f -> ["list_format" .= f]) listFormat
          <> maybe [] (\i -> ["list_start_index" .= i]) listStartIndex
    )
  ToDoBlock {..} ->
    ("to_do", object ["rich_text" .= richText, "color" .= color, "checked" .= checked])
  ToggleBlock {..} ->
    ("toggle", object ["rich_text" .= richText, "color" .= color])
  QuoteBlock {..} ->
    ("quote", object ["rich_text" .= richText, "color" .= color])
  CalloutBlock {..} ->
    ( "callout",
      object $
        ["rich_text" .= richText, "color" .= color]
          <> maybe [] (\i -> ["icon" .= i]) calloutIcon
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
    ("audio", object $ fileSourcePairs audioSource)
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
    ("embed", object ["url" .= url])
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
  ColumnListBlock ->
    ("column_list", object [])
  ColumnBlock ->
    ("column", object [])
  TableBlock {..} ->
    ("table", object ["table_width" .= tableWidth, "has_column_header" .= hasColumnHeader, "has_row_header" .= hasRowHeader])
  TableRowBlock {..} ->
    ("table_row", object ["cells" .= cells])
  ChildPageBlock {..} ->
    ("child_page", object ["title" .= title])
  ChildDatabaseBlock {..} ->
    ("child_database", object ["title" .= title])
  SyncedBlockContent {..} ->
    ("synced_block", object ["synced_from" .= syncedFrom])
  UnsupportedBlock ->
    ("unsupported", object [])
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
    pure ParagraphBlock {..}
  "heading_1" -> parseObj $ \o -> do
    richText <- o .: "rich_text"
    color <- fromMaybe Default <$> o .:? "color"
    isToggleable <- fromMaybe False <$> o .:? "is_toggleable"
    pure Heading1Block {..}
  "heading_2" -> parseObj $ \o -> do
    richText <- o .: "rich_text"
    color <- fromMaybe Default <$> o .:? "color"
    isToggleable <- fromMaybe False <$> o .:? "is_toggleable"
    pure Heading2Block {..}
  "heading_3" -> parseObj $ \o -> do
    richText <- o .: "rich_text"
    color <- fromMaybe Default <$> o .:? "color"
    isToggleable <- fromMaybe False <$> o .:? "is_toggleable"
    pure Heading3Block {..}
  "bulleted_list_item" -> parseObj $ \o -> do
    richText <- o .: "rich_text"
    color <- fromMaybe Default <$> o .:? "color"
    pure BulletedListItemBlock {..}
  "numbered_list_item" -> parseObj $ \o -> do
    richText <- o .: "rich_text"
    color <- fromMaybe Default <$> o .:? "color"
    listFormat <- o .:? "list_format"
    listStartIndex <- o .:? "list_start_index"
    pure NumberedListItemBlock {..}
  "to_do" -> parseObj $ \o -> do
    richText <- o .: "rich_text"
    color <- fromMaybe Default <$> o .:? "color"
    checked <- fromMaybe False <$> o .:? "checked"
    pure ToDoBlock {..}
  "toggle" -> parseObj $ \o -> do
    richText <- o .: "rich_text"
    color <- fromMaybe Default <$> o .:? "color"
    pure ToggleBlock {..}
  "quote" -> parseObj $ \o -> do
    richText <- o .: "rich_text"
    color <- fromMaybe Default <$> o .:? "color"
    pure QuoteBlock {..}
  "callout" -> parseObj $ \o -> do
    richText <- o .: "rich_text"
    color <- fromMaybe Default <$> o .:? "color"
    calloutIcon <- o .:? "icon"
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
  "column_list" -> pure ColumnListBlock
  "column" -> pure ColumnBlock
  "table" -> parseObj $ \o -> do
    tableWidth <- o .: "table_width"
    hasColumnHeader <- o .: "has_column_header"
    hasRowHeader <- o .: "has_row_header"
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
    pure SyncedBlockContent {..}
  "unsupported" -> pure UnsupportedBlock
  _ -> pure (UnknownBlock typeName val)
  where
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
-- BlockUpdate
-- ---------------------------------------------------------------------------

-- | Wrapper for block content used in the update (PATCH) endpoint.
--
-- Serializes without the @\"type\"@ key — only the type-named key with inner
-- content:
--
-- @
-- { "paragraph": { "rich_text": [...] } }
-- @
newtype BlockUpdate = BlockUpdate BlockContent
  deriving stock (Show)

instance ToJSON BlockUpdate where
  toJSON (BlockUpdate bc) =
    let (typeName, inner) = blockContentFields bc
     in object [Key.fromText typeName .= inner]

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
paragraphBlock rt = ParagraphBlock rt Default Nothing

-- | Create a heading block at the given level (1, 2, or 3; defaults to 3).
headingBlock :: Int -> Vector RichText -> BlockContent
headingBlock 1 rt = Heading1Block rt Default False
headingBlock 2 rt = Heading2Block rt Default False
headingBlock _ rt = Heading3Block rt Default False

-- | Create a bulleted list item block.
bulletedListItemBlock :: Vector RichText -> BlockContent
bulletedListItemBlock rt = BulletedListItemBlock rt Default

-- | Create a numbered list item block.
numberedListItemBlock :: Vector RichText -> BlockContent
numberedListItemBlock rt = NumberedListItemBlock rt Default Nothing Nothing

-- | Create a to-do block.
toDoBlock :: Vector RichText -> Bool -> BlockContent
toDoBlock rt isChecked = ToDoBlock rt Default isChecked

-- | Create a toggle block.
toggleBlock :: Vector RichText -> BlockContent
toggleBlock rt = ToggleBlock rt Default

-- | Create a quote block.
quoteBlock :: Vector RichText -> BlockContent
quoteBlock rt = QuoteBlock rt Default

-- | Create a callout block with an optional icon.
calloutBlock :: Vector RichText -> Maybe Icon -> BlockContent
calloutBlock rt icon = CalloutBlock rt Default icon

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
