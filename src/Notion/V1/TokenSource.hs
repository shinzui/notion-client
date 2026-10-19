-- | Per-request bearer authorization and a single reactive renewal.
module Notion.V1.TokenSource (TokenSource (..), staticTokenSource, withAuthorization) where

import Control.Exception (throwIO, try)
import Data.Text (Text)
import Notion.V1.Error (APIErrorCode (Unauthorized), NotionError (..))

-- | One source per installation. Tokens exclude the @Bearer @ prefix.
data TokenSource = TokenSource
  { currentToken :: IO Text,
    -- | Renew after rejection, or return a token another request obtained.
    -- Nothing means no renewal is available. Exceptions propagate in IO.
    renewToken :: Text -> IO (Maybe Text)
  }

staticTokenSource :: Text -> TokenSource
staticTokenSource token = TokenSource (pure token) (const (pure Nothing))

-- | Replay once only on typed Unauthorized. The action must be replayable.
-- Scope this to request acquisition, never a stream body or user callback.
withAuthorization :: TokenSource -> (Text -> IO a) -> IO a
withAuthorization TokenSource {currentToken, renewToken} action = do
  token <- currentToken
  result <- try (action ("Bearer " <> token))
  case result of
    Right a -> pure a
    Left e@NotionError {code = Unauthorized} -> do
      replacement <- renewToken token
      maybe (throwIO e) (action . ("Bearer " <>)) replacement
    Left e -> throwIO e
