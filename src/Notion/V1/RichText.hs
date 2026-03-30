-- | Rich Text objects in Notion API
module Notion.V1.RichText
  ( -- * Rich Text types
    RichText (..),
    RichTextContent (..),
    TextContent (..),
    MentionContent (..),
    EquationContent (..),
    Annotations (..),
    defaultAnnotations,
    Link (..),
    Date (..),
    TimeZone (..),
  )
where

import Data.Aeson (object, (.:), (.:?), (.=))
import Notion.Prelude
import Notion.V1.Common (Color (..), UUID)

-- | Rich text object in Notion
data RichText = RichText
  { plainText :: Text,
    href :: Maybe Text,
    annotations :: Annotations,
    type_ :: Text,
    content :: RichTextContent
  }
  deriving stock (Eq, Generic, Show)

instance FromJSON RichText where
  parseJSON = \case
    Object o -> do
      plainText <- o .: "plain_text"
      href <- o .:? "href"
      annotations <- o .: "annotations"
      type_ <- o .: "type"
      content <- case type_ of
        "text" -> TextContentWrapper <$> o .: "text"
        "mention" -> MentionContentWrapper <$> o .: "mention"
        "equation" -> EquationContentWrapper <$> o .: "equation"
        other -> fail $ "Unknown rich text type: " <> unpack other
      return RichText {..}
    _ -> fail "Expected object for RichText"

instance ToJSON RichText where
  toJSON RichText {..} =
    object $
      [ "type" .= type_,
        "plain_text" .= plainText,
        "annotations" .= annotations
      ]
        ++ maybe [] (\h -> ["href" .= h]) href
        ++ case content of
          TextContentWrapper tc -> ["text" .= tc]
          MentionContentWrapper mc -> ["mention" .= mc]
          EquationContentWrapper ec -> ["equation" .= ec]

-- | Text content
data TextContent = TextContent
  { content :: Text,
    link :: Maybe Link
  }
  deriving stock (Eq, Generic, Show)

instance FromJSON TextContent where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON TextContent where
  toJSON = genericToJSON aesonOptions

-- | Mention content
--
-- Notion mentions have a @type@ discriminator and the content nested under
-- the corresponding field name. For example:
--
-- @
-- { "type": "user", "user": { "id": "..." } }
-- @
data MentionContent
  = UserMention {user :: UUID}
  | PageMention {page :: UUID}
  | DatabaseMention {database :: UUID}
  | DateMention {date :: Date}
  | LinkPreviewMention {url :: Text}
  deriving stock (Eq, Generic, Show)

instance FromJSON MentionContent where
  parseJSON = \case
    Object o -> do
      mentionType <- o .: "type"
      case mentionType of
        "user" -> do
          userObj <- o .: "user"
          UserMention <$> parseIdField userObj
        "page" -> do
          pageObj <- o .: "page"
          PageMention <$> parseIdField pageObj
        "database" -> do
          dbObj <- o .: "database"
          DatabaseMention <$> parseIdField dbObj
        "date" -> DateMention <$> o .: "date"
        "link_preview" -> do
          lpObj <- o .: "link_preview"
          LinkPreviewMention <$> parseUrlField lpObj
        other -> fail $ "Unknown mention type: " <> unpack other
    _ -> fail "Expected object for MentionContent"
    where
      parseIdField = \case
        Object o -> o .: "id"
        _ -> fail "Expected object with id field"
      parseUrlField = \case
        Object o -> o .: "url"
        _ -> fail "Expected object with url field"

instance ToJSON MentionContent where
  toJSON = \case
    UserMention uid ->
      object ["type" .= ("user" :: Text), "user" .= object ["id" .= uid]]
    PageMention pid ->
      object ["type" .= ("page" :: Text), "page" .= object ["id" .= pid]]
    DatabaseMention dbid ->
      object ["type" .= ("database" :: Text), "database" .= object ["id" .= dbid]]
    DateMention d ->
      object ["type" .= ("date" :: Text), "date" .= d]
    LinkPreviewMention u ->
      object ["type" .= ("link_preview" :: Text), "link_preview" .= object ["url" .= u]]

-- | Equation content
newtype EquationContent = EquationContent
  { expression :: Text
  }
  deriving stock (Eq, Generic, Show)

instance FromJSON EquationContent where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON EquationContent where
  toJSON = genericToJSON aesonOptions

-- | Content of a rich text object
data RichTextContent
  = TextContentWrapper TextContent
  | MentionContentWrapper MentionContent
  | EquationContentWrapper EquationContent
  deriving stock (Eq, Generic, Show)

-- | Text annotations
data Annotations = Annotations
  { bold :: Bool,
    italic :: Bool,
    strikethrough :: Bool,
    underline :: Bool,
    code :: Bool,
    color :: Color
  }
  deriving stock (Eq, Generic, Show)

instance FromJSON Annotations where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON Annotations where
  toJSON = genericToJSON aesonOptions

-- | Default annotations
defaultAnnotations :: Annotations
defaultAnnotations =
  Annotations
    { bold = False,
      italic = False,
      strikethrough = False,
      underline = False,
      code = False,
      color = Default
    }

-- | Link object
newtype Link = Link
  { url :: Text
  }
  deriving stock (Eq, Generic, Show)

instance FromJSON Link where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON Link where
  toJSON = genericToJSON aesonOptions

-- | Date object
data Date = Date
  { start :: Text,
    end :: Maybe Text,
    timeZone :: Maybe TimeZone
  }
  deriving stock (Eq, Generic, Show)

instance FromJSON Date where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON Date where
  toJSON = genericToJSON aesonOptions

-- | Time zone
newtype TimeZone = TimeZone
  { text :: Text
  }
  deriving newtype (Eq, FromJSON, IsString, Show, ToJSON)
