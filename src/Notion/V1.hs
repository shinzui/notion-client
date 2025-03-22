-- | Notion API v1
--
-- Example usage:
--
-- @
-- module Main where
--
-- import Notion.V1
-- import Notion.V1.Pages
-- import Data.Text qualified as Text
-- import System.Environment qualified as Environment
--
-- main :: IO ()
-- main = do
--     token <- Environment.getEnv "NOTION_TOKEN"
--
--     clientEnv <- getClientEnv "https://api.notion.com"
--
--     let Methods{ retrievePage } = makeMethods clientEnv (Text.pack token)
--
--     page <- retrievePage "page-id-here"
--
--     print page
-- @
module Notion.V1
  ( -- * Methods
    getClientEnv,
    makeMethods,
    Methods (..),

    -- * Servant
    API,
  )
where

import Control.Exception qualified as Exception
import Data.Aeson (encode, toJSON)
import Data.ByteString.Lazy (toStrict)
import Data.Proxy (Proxy (..))
import Data.Text qualified as Text
import Data.Text.Encoding (decodeUtf8)
import Network.HTTP.Client.TLS qualified as TLS
import Notion.Prelude
import Notion.V1.Blocks (BlockID, BlockObject)
import Notion.V1.Blocks qualified as Blocks
import Notion.V1.Comments (CommentObject)
import Notion.V1.Comments qualified as Comments
import Notion.V1.Common (ParentID)
import Notion.V1.Databases (CreateDatabase, DatabaseID, DatabaseObject, QueryDatabase, UpdateDatabase)
import Notion.V1.Databases qualified as Databases
import Notion.V1.ListOf (ListOf (..))
import Notion.V1.Pages (CreatePage, PageID, PageObject, UpdatePage)
import Notion.V1.Pages qualified as Pages
import Notion.V1.Search (SearchRequest)
import Notion.V1.Search qualified as Search
import Notion.V1.Users (UserID, UserObject)
import Notion.V1.Users qualified as Users
import Servant.Client (ClientEnv)
import Servant.Client qualified as Client
import Servant.Multipart.Client ()

-- | Convenient utility to get a `ClientEnv` for the most common use case
getClientEnv ::
  -- | Base URL for API
  Text ->
  IO ClientEnv
getClientEnv baseUrlText = do
  baseUrl <- Client.parseBaseUrl (Text.unpack baseUrlText)
  manager <- TLS.newTlsManager
  pure (Client.mkClientEnv manager baseUrl)

-- | Get a record of API methods after providing an API token
makeMethods ::
  ClientEnv ->
  -- | API token
  Text ->
  Methods
makeMethods clientEnv token = Methods {..}
  where
    notionVersion = "2022-06-28" -- Current Notion API version as of this implementation
    -- If you experience 400 errors, check for updated versions at
    -- https://developers.notion.com/reference/versioning
    ( ( createDatabase
          :<|> retrieveDatabase
          :<|> updateDatabase
          :<|> queryDatabase
        )
        :<|> ( retrievePage
                :<|> createPage
                :<|> updatePage
              )
        :<|> ( retrieveBlock
                :<|> updateBlock
                :<|> retrieveBlockChildren_
                :<|> appendBlockChildren
                :<|> deleteBlock
              )
        :<|> ( retrieveUser
                :<|> listUsers_
                :<|> retrieveMyUser
              )
        :<|> search_
        :<|> ( createComment
                :<|> listComments_
              )
      ) = Client.hoistClient @API Proxy run (Client.client @API Proxy) authorization notionVersion

    authorization = "Bearer " <> token

    run :: Client.ClientM a -> IO a
    run clientM = do
      result <- Client.runClientM clientM clientEnv
      case result of
        Left exception -> do
          -- For debugging purposes, provide more information about errors
          -- This helps diagnose issues like wrong API version or authentication problems
          putStrLn $ "Notion API Error: " ++ show exception
          Exception.throwIO exception
        Right a -> return a

    -- Function to encode JSON to Text
    encodeToText = decodeUtf8 . toStrict . encode

    -- Debug function to show JSON
    debugCreatePage createPageReq =
      pure . Text.unpack . encodeToText $ toJSON createPageReq

    -- Keep the ListOf structure
    listBlockChildren = retrieveBlockChildren_
    listUsers = listUsers_
    listComments = listComments_
    search = search_

-- | API methods
data Methods = Methods
  { -- \* Databases
    createDatabase :: CreateDatabase -> IO DatabaseObject,
    retrieveDatabase :: DatabaseID -> IO DatabaseObject,
    updateDatabase :: DatabaseID -> UpdateDatabase -> IO DatabaseObject,
    queryDatabase :: DatabaseID -> QueryDatabase -> IO (ListOf PageObject),
    -- \* Pages
    createPage :: CreatePage -> IO PageObject,
    retrievePage :: PageID -> IO PageObject,
    updatePage :: PageID -> UpdatePage -> IO PageObject,
    debugCreatePage :: CreatePage -> IO String, -- Debug version just returns the JSON
    -- \* Blocks
    retrieveBlock :: BlockID -> IO BlockObject,
    updateBlock :: BlockID -> Blocks.BlockContent -> IO BlockObject,
    listBlockChildren ::
      ParentID ->
      Maybe Natural ->
      -- \^ page_size
      Maybe Text ->
      -- \^ start_cursor
      IO (ListOf BlockObject),
    appendBlockChildren :: ParentID -> Blocks.AppendBlockChildren -> IO BlockObject,
    deleteBlock :: BlockID -> IO BlockObject,
    -- \* Users
    retrieveUser :: UserID -> IO UserObject,
    listUsers ::
      Maybe Natural ->
      -- \^ page_size
      Maybe Text ->
      -- \^ start_cursor
      IO (ListOf UserObject),
    retrieveMyUser :: IO UserObject,
    -- \* Search
    search :: SearchRequest -> IO (ListOf PageObject),
    -- \* Comments
    createComment :: Comments.CreateComment -> IO CommentObject,
    listComments :: Maybe BlockID -> IO (ListOf CommentObject)
  }

-- | Servant API
type API =
  Header' [Required, Strict] "Authorization" Text
    :> Header' [Required, Strict] "Notion-Version" Text
    :> ( Databases.API
          :<|> Pages.API
          :<|> Blocks.API
          :<|> Users.API
          :<|> Search.API
          :<|> Comments.API
       )
