{-# LANGUAGE LambdaCase #-}

-- | @\/v1\/users@
module Notion.V1.Users
  ( -- * Main types
    UserID,
    UserObject (..),
    UserType (..),
    PersonUser (..),
    BotUser (..),
    UserOwner (..),
    WorkspaceLimits (..),
    UserReference (..),

    -- * Users inside values
    UserValue (..),
    userValueId,
    GroupObject (..),
    PeopleEntry (..),

    -- * Servant
    API,
  )
where

import Control.Applicative ((<|>))
import Data.Aeson ((.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
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
  deriving stock (Eq, Generic, Show)

instance FromJSON UserObject where
  parseJSON = genericParseJSON aesonOptions {fieldLabelModifier = \s -> if s == "type_" then "type" else labelModifier s}

-- | User type
data UserType
  = Person
  | Bot
  deriving stock (Eq, Generic, Show)

instance FromJSON UserType where
  parseJSON = genericParseJSON aesonOptions

-- | Person user
newtype PersonUser = PersonUser
  { email :: Maybe Text
  }
  deriving stock (Eq, Generic, Show)

instance FromJSON PersonUser where
  parseJSON = genericParseJSON aesonOptions

-- | Workspace limits for bot users.
data WorkspaceLimits = WorkspaceLimits
  { maxFileUploadSizeInBytes :: Maybe Natural
  }
  deriving stock (Eq, Generic, Show)

instance FromJSON WorkspaceLimits where
  parseJSON = genericParseJSON aesonOptions

-- | Bot user
data BotUser = BotUser
  { owner :: Maybe UserOwner,
    workspaceName :: Maybe Text,
    workspaceId :: Maybe Text,
    workspaceLimits :: Maybe WorkspaceLimits
  }
  deriving stock (Eq, Generic, Show)

instance FromJSON BotUser where
  parseJSON = genericParseJSON aesonOptions

-- | User owner
data UserOwner
  = UserOwner {type_ :: Text, user :: UserID}
  | WorkspaceOwner {type_ :: Text, workspace :: Bool}
  | -- | Owner kind not modelled yet; holds the raw owner object.
    UnknownOwner {type_ :: Text, ownerValue :: Value}
  deriving stock (Eq, Generic, Show)

instance FromJSON UserOwner where
  parseJSON = \case
    Object o -> do
      ownerType :: Text <- o .: "type"
      case ownerType of
        "user" -> do
          -- Notion sends the owning user object, not a bare ID.
          userObj <- o .: "user"
          UserOwner ownerType <$> userObj .: "id"
        "workspace" -> WorkspaceOwner ownerType <$> (o .: "workspace")
        _ -> pure (UnknownOwner ownerType (Object o))
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

instance ToJSON UserReference where
  toJSON = genericToJSON aesonOptions

-- | A user as it appears inside mentions, people values and verification
-- values: either just a reference (@{"object":"user","id":...}@) or a full
-- user object (one with a @type@ key).
data UserValue
  = PartialUser UserID
  | FullUser UserObject
  deriving stock (Eq, Generic, Show)

-- | The ID of a partial or full user.
userValueId :: UserValue -> UserID
userValueId (PartialUser i) = i
userValueId (FullUser UserObject {id = i}) = i

-- | A full user object that this library cannot decode (for example a new
-- user type) is kept as a 'PartialUser' rather than failing the response.
instance FromJSON UserValue where
  parseJSON = \case
    Object o
      | KeyMap.member "type" o -> (FullUser <$> parseJSON (Object o)) <|> (PartialUser <$> o .: "id")
      | otherwise -> PartialUser <$> o .: "id"
    _ -> fail "Expected object for UserValue"

-- | Encodes the request shape only (@object@ and @id@); full user details are
-- not sent back to the API.
instance ToJSON UserValue where
  toJSON u = Aeson.object ["object" .= ("user" :: Text), "id" .= userValueId u]

-- | A group (team) that can appear in a people property.
data GroupObject = GroupObject
  { id :: UUID,
    name :: Maybe Text
  }
  deriving stock (Eq, Generic, Show)

-- | One entry of a people property: a user or a group.
data PeopleEntry
  = PersonEntry UserValue
  | GroupEntry GroupObject
  deriving stock (Eq, Generic, Show)

instance FromJSON PeopleEntry where
  parseJSON = \case
    Object o -> do
      objectType :: Maybe Text <- o .:? "object"
      case objectType of
        Just "group" -> GroupEntry <$> (GroupObject <$> o .: "id" <*> o .:? "name")
        _ -> PersonEntry <$> parseJSON (Object o)
    _ -> fail "Expected object for PeopleEntry"

instance ToJSON PeopleEntry where
  toJSON = \case
    PersonEntry u -> toJSON u
    GroupEntry (GroupObject gid gname) ->
      Aeson.object (["object" .= ("group" :: Text), "id" .= gid] <> maybe [] (\n -> ["name" .= n]) gname)

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
