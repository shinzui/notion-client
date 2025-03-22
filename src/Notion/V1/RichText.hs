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

import Notion.Prelude
import Notion.V1.Common (Color (..), UUID)

-- | Rich text object in Notion
data RichText = RichText
  { plain_text :: Text,
    href :: Maybe Text,
    annotations :: Annotations,
    type_ :: Text,
    content :: RichTextContent
  }
  deriving stock (Generic, Show)

instance FromJSON RichText where
  parseJSON = genericParseJSON aesonOptions {fieldLabelModifier = \s -> if s == "type_" then "type" else labelModifier s}

instance ToJSON RichText where
  toJSON = genericToJSON aesonOptions {fieldLabelModifier = \s -> if s == "type_" then "type" else labelModifier s}

-- | Text content
data TextContent = TextContent
  { content :: Text,
    link :: Maybe Link
  }
  deriving stock (Generic, Show)

instance FromJSON TextContent where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON TextContent where
  toJSON = genericToJSON aesonOptions

-- | Mention content
data MentionContent
  = UserMention {user :: UUID}
  | PageMention {page :: UUID}
  | DatabaseMention {database :: UUID}
  | DateMention {date :: Date}
  | LinkPreviewMention {url :: Text}
  deriving stock (Generic, Show)

instance FromJSON MentionContent where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON MentionContent where
  toJSON = genericToJSON aesonOptions

-- | Equation content
newtype EquationContent = EquationContent
  { expression :: Text
  }
  deriving stock (Generic, Show)

instance FromJSON EquationContent where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON EquationContent where
  toJSON = genericToJSON aesonOptions

-- | Content of a rich text object
data RichTextContent
  = TextContentWrapper TextContent
  | MentionContentWrapper MentionContent
  | EquationContentWrapper EquationContent
  deriving stock (Generic, Show)

instance FromJSON RichTextContent where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON RichTextContent where
  toJSON = genericToJSON aesonOptions

-- | Text annotations
data Annotations = Annotations
  { bold :: Bool,
    italic :: Bool,
    strikethrough :: Bool,
    underline :: Bool,
    code :: Bool,
    color :: Color
  }
  deriving stock (Generic, Show)

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
  deriving stock (Generic, Show)

instance FromJSON Link where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON Link where
  toJSON = genericToJSON aesonOptions

-- | Date object
data Date = Date
  { start :: Text,
    end :: Maybe Text,
    time_zone :: Maybe TimeZone
  }
  deriving stock (Generic, Show)

instance FromJSON Date where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON Date where
  toJSON = genericToJSON aesonOptions

-- | Time zone
newtype TimeZone = TimeZone
  { text :: Text
  }
  deriving newtype (FromJSON, IsString, Show, ToJSON)
