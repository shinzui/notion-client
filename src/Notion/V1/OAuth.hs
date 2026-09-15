-- | @\/v1\/oauth@: exchange, revoke and introspect OAuth tokens.
--
-- These endpoints authenticate with HTTP Basic auth using the integration's
-- client ID and secret instead of a bearer token, so they have their own API
-- type and methods record.
--
-- @
-- manager <- newTlsManager
-- let oauth = makeOAuthMethodsWith defaultClientConfig
--       (mkClientEnv manager defaultBaseUrl)
--       OAuthCredentials {clientId = "...", clientSecret = "..."}
-- token <- createOAuthToken oauth (AuthorizationCode AuthorizationCodeGrant
--   {code = codeFromRedirect, redirectUri = Just callbackUrl, externalAccount = Nothing})
-- @
module Notion.V1.OAuth
  ( -- * Credentials
    OAuthCredentials (..),
    basicAuthorization,

    -- * Requests
    OAuthTokenRequest (..),
    AuthorizationCodeGrant (..),
    ExternalAccount (..),
    TokenBody (..),

    -- * Responses
    OAuthTokenResponse (..),
    OAuthOwner (..),
    OAuthOwnerUser (..),
    OAuthRevokeResponse (..),
    OAuthIntrospectResponse (..),

    -- * Methods
    OAuthMethods (..),
    makeOAuthMethods,
    makeOAuthMethodsWith,

    -- * Servant
    API,
  )
where

import Data.Aeson ((.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.ByteString.Base64 qualified as Base64
import Data.Maybe (catMaybes)
import Data.Proxy (Proxy (..))
import Data.Text.Encoding qualified as Text
import Notion.Prelude
import Notion.V1.Client (ClientConfig (..), configureClientEnv, legacyClientConfig, runClientWith)
import Notion.V1.Common (UUID)
import Servant.Client (ClientEnv)
import Servant.Client qualified as Client
import Prelude hiding (id)

-- | An integration's OAuth client ID and secret.
data OAuthCredentials = OAuthCredentials
  { clientId :: Text,
    clientSecret :: Text
  }

-- | @Basic base64(client_id:client_secret)@
basicAuthorization :: OAuthCredentials -> Text
basicAuthorization OAuthCredentials {clientId, clientSecret} =
  "Basic " <> Text.decodeUtf8 (Base64.encode (Text.encodeUtf8 (clientId <> ":" <> clientSecret)))

-- | Body of @POST /v1/oauth/token@.
data OAuthTokenRequest
  = -- | Exchange the code from the OAuth redirect.
    AuthorizationCode AuthorizationCodeGrant
  | -- | Exchange a refresh token.
    RefreshToken Text
  deriving stock (Eq, Show)

data AuthorizationCodeGrant = AuthorizationCodeGrant
  { code :: Text,
    redirectUri :: Maybe Text,
    externalAccount :: Maybe ExternalAccount
  }
  deriving stock (Eq, Show)

data ExternalAccount = ExternalAccount
  { key :: Text,
    name :: Text
  }
  deriving stock (Eq, Show)

instance ToJSON ExternalAccount where
  toJSON ExternalAccount {key, name} = Aeson.object ["key" .= key, "name" .= name]

instance ToJSON OAuthTokenRequest where
  toJSON = \case
    AuthorizationCode AuthorizationCodeGrant {code, redirectUri, externalAccount} ->
      Aeson.object $
        ["grant_type" .= ("authorization_code" :: Text), "code" .= code]
          <> catMaybes
            [ ("redirect_uri" .=) <$> redirectUri,
              ("external_account" .=) <$> externalAccount
            ]
    RefreshToken token ->
      Aeson.object ["grant_type" .= ("refresh_token" :: Text), "refresh_token" .= token]

-- | Body of the revoke and introspect endpoints.
newtype TokenBody = TokenBody {token :: Text}
  deriving stock (Eq, Show)

instance ToJSON TokenBody where
  toJSON TokenBody {token} = Aeson.object ["token" .= token]

-- | Response of @POST /v1/oauth/token@.
data OAuthTokenResponse = OAuthTokenResponse
  { accessToken :: Text,
    -- | Always @"bearer"@.
    tokenType :: Text,
    refreshToken :: Maybe Text,
    botId :: Text,
    workspaceIcon :: Maybe Text,
    workspaceName :: Maybe Text,
    workspaceId :: Text,
    owner :: OAuthOwner,
    duplicatedTemplateId :: Maybe Text,
    requestId :: Maybe Text
  }
  deriving stock (Eq, Generic, Show)

instance FromJSON OAuthTokenResponse where
  parseJSON = genericParseJSON aesonOptions

-- | Who owns the integration's access.
data OAuthOwner
  = OAuthUserOwner OAuthOwnerUser
  | OAuthWorkspaceOwner
  | -- | An owner kind this library does not model yet; holds the raw object.
    UnknownOAuthOwner Value
  deriving stock (Eq, Show)

instance FromJSON OAuthOwner where
  parseJSON = Aeson.withObject "OAuthOwner" $ \o -> do
    ownerType :: Text <- o .: "type"
    case ownerType of
      "user" -> OAuthUserOwner <$> o .: "user"
      "workspace" -> pure OAuthWorkspaceOwner
      _ -> pure (UnknownOAuthOwner (Object o))

-- | A full person user or a partial user (only @id@ and @object@); the
-- person-only fields are 'Nothing' for a partial user.
data OAuthOwnerUser = OAuthOwnerUser
  { id :: UUID,
    object :: Text,
    type_ :: Maybe Text,
    name :: Maybe Text,
    avatarUrl :: Maybe Text,
    -- | From @person.email@.
    email :: Maybe Text
  }
  deriving stock (Eq, Show)

instance FromJSON OAuthOwnerUser where
  parseJSON = Aeson.withObject "OAuthOwnerUser" $ \o -> do
    id <- o .: "id"
    object <- o .: "object"
    type_ <- o .:? "type"
    name <- o .:? "name"
    avatarUrl <- o .:? "avatar_url"
    person <- o .:? "person"
    email <- maybe (pure Nothing) (.:? "email") person
    pure OAuthOwnerUser {..}

-- | Response of @POST /v1/oauth/revoke@.
newtype OAuthRevokeResponse = OAuthRevokeResponse {requestId :: Maybe Text}
  deriving stock (Eq, Show)

instance FromJSON OAuthRevokeResponse where
  parseJSON = Aeson.withObject "OAuthRevokeResponse" $ \o -> OAuthRevokeResponse <$> o .:? "request_id"

-- | Response of @POST /v1/oauth/introspect@.
data OAuthIntrospectResponse = OAuthIntrospectResponse
  { active :: Bool,
    scope :: Maybe Text,
    -- | Issued-at time, in seconds since the Unix epoch.
    iat :: Maybe Integer,
    requestId :: Maybe Text
  }
  deriving stock (Eq, Generic, Show)

instance FromJSON OAuthIntrospectResponse where
  parseJSON = genericParseJSON aesonOptions

-- | Servant API
type API =
  Header' [Required, Strict] "Authorization" Text
    :> Header' [Required, Strict] "Notion-Version" Text
    :> "oauth"
    :> ( "token"
           :> ReqBody '[JSON] OAuthTokenRequest
           :> Post '[JSON] OAuthTokenResponse
           :<|> "revoke"
           :> ReqBody '[JSON] TokenBody
           :> Post '[JSON] OAuthRevokeResponse
           :<|> "introspect"
           :> ReqBody '[JSON] TokenBody
           :> Post '[JSON] OAuthIntrospectResponse
       )

-- | OAuth endpoints, authenticated with the integration's credentials.
data OAuthMethods = OAuthMethods
  { createOAuthToken :: OAuthTokenRequest -> IO OAuthTokenResponse,
    revokeOAuthToken :: Text -> IO OAuthRevokeResponse,
    introspectOAuthToken :: Text -> IO OAuthIntrospectResponse
  }

-- | OAuth methods with 'legacyClientConfig', like 'Notion.V1.makeMethods'.
makeOAuthMethods :: ClientEnv -> OAuthCredentials -> OAuthMethods
makeOAuthMethods = makeOAuthMethodsWith legacyClientConfig

-- | OAuth methods with a configuration. The routes are relative to the
-- 'ClientEnv' base URL (normally @https://api.notion.com/v1@) and use the same
-- runtime (retries, timeout, logging) as 'Notion.V1.Methods'.
makeOAuthMethodsWith :: ClientConfig -> ClientEnv -> OAuthCredentials -> OAuthMethods
makeOAuthMethodsWith config env creds =
  OAuthMethods
    { createOAuthToken,
      revokeOAuthToken = revoke_ . TokenBody,
      introspectOAuthToken = introspect_ . TokenBody
    }
  where
    createOAuthToken :<|> revoke_ :<|> introspect_ =
      Client.hoistClient
        @API
        Proxy
        (runClientWith (configureClientEnv config env))
        (Client.client @API Proxy)
        (basicAuthorization creds)
        (notionVersion config)
