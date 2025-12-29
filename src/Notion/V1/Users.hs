{-# LANGUAGE LambdaCase #-}

-- | @\/v1\/users@
module Notion.V1.Users
  ( -- * Main types
    UserID,
    UserObject (..),
    UserType (..),
    PersonUser (..),
    BotUser (..),
    UserReference (..),

    -- * Servant
    API,
  )
where

import Data.Aeson.Types ((.:))
import Notion.Prelude
import Notion.V1.Common (ObjectType (..), UUID)
import Notion.V1.ListOf (ListOf)

-- | User ID
type UserID = UUID

-- | Notion user object
data UserObject = UserObject
  { id :: UserID,
    name :: Maybe Text,
    avatarUrl :: Maybe Text,
    type_ :: UserType,
    person :: Maybe PersonUser,
    bot :: Maybe BotUser,
    object :: ObjectType
  }
  deriving stock (Generic, Show)

instance FromJSON UserObject where
  parseJSON = genericParseJSON aesonOptions {fieldLabelModifier = \s -> if s == "type_" then "type" else labelModifier s}

-- | User type
data UserType
  = Person
  | Bot
  deriving stock (Generic, Show)

instance FromJSON UserType where
  parseJSON = genericParseJSON aesonOptions

-- | Person user
newtype PersonUser = PersonUser
  { email :: Text
  }
  deriving stock (Generic, Show)

instance FromJSON PersonUser where
  parseJSON = genericParseJSON aesonOptions

-- | Bot user
data BotUser = BotUser
  { owner :: Maybe UserOwner,
    workspaceName :: Maybe Text
  }
  deriving stock (Generic, Show)

instance FromJSON BotUser where
  parseJSON = genericParseJSON aesonOptions

-- | User owner
data UserOwner
  = UserOwner {type_ :: Text, user :: UserID}
  | WorkspaceOwner {type_ :: Text, workspace :: Bool}
  deriving stock (Generic, Show)

instance FromJSON UserOwner where
  parseJSON = \case
    Object o -> do
      ownerType <- o .: "type"
      case ownerType of
        "user" -> UserOwner <$> pure ownerType <*> o .: "user"
        "workspace" -> WorkspaceOwner <$> pure ownerType <*> o .: "workspace"
        _ -> fail $ "Unknown owner type: " <> unpack ownerType
    _ -> fail "Expected object for UserOwner"

-- | Simple user reference objects that appear in created_by and last_edited_by fields
data UserReference = UserReference
  { id :: UserID,
    object :: Text
  }
  deriving stock (Generic, Show)

instance FromJSON UserReference where
  parseJSON = \case
    Object o -> UserReference <$> o .: "id" <*> o .: "object"
    _ -> fail "Expected object for UserReference"

-- | Servant API
type API =
  "users"
    :> ( Capture "user_id" UserID
           :> Get '[JSON] UserObject
           :<|> QueryParam "page_size" Natural
           :> QueryParam "start_cursor" Text
           :> Get '[JSON] (ListOf UserObject)
           :<|> "me"
           :> Get '[JSON] UserObject
       )
