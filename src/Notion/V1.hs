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
--     clientEnv <- getClientEnv "https://api.notion.com/v1"
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
import Data.Proxy (Proxy (..))
import Data.Text qualified as Text
import Network.HTTP.Client.TLS qualified as TLS
import Notion.Prelude
import Notion.V1.Blocks (BlockID, BlockObject)
import Notion.V1.Blocks qualified as Blocks
import Notion.V1.Comments (CommentObject)
import Notion.V1.Comments qualified as Comments
import Notion.V1.Common (ParentID, UUID)
import Notion.V1.CustomEmojis (CustomEmoji)
import Notion.V1.CustomEmojis qualified as CustomEmojis
import Notion.V1.DataSources (DataSourceID, DataSourceObject)
import Notion.V1.DataSources qualified as DataSources
import Notion.V1.Databases (CreateDatabase, DatabaseID, DatabaseObject, QueryDatabase, UpdateDatabase)
import Notion.V1.Databases qualified as Databases
import Notion.V1.Error (parseNotionError)
import Notion.V1.ListOf (ListOf (..))
import Notion.V1.Pages (CreatePage, MovePage, PageID, PageMarkdown, PageObject, PropertyItemResponse, UpdatePage, UpdatePageMarkdown)
import Notion.V1.Pages qualified as Pages
import Notion.V1.Search (SearchRequest)
import Notion.V1.Search qualified as Search
import Notion.V1.Users (UserID, UserObject)
import Notion.V1.Users qualified as Users
import Notion.V1.Views (ViewObject)
import Notion.V1.Views qualified as Views
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
    notionVersion = "2026-03-11" -- Notion API version with markdown content support
    -- If you experience 400 errors, check for updated versions at
    -- https://developers.notion.com/reference/versioning
    ( ( createDatabase
          :<|> retrieveDatabase
          :<|> updateDatabase
          :<|> queryDatabase
        )
        :<|> ( retrieveDataSource
                 :<|> createDataSource
                 :<|> updateDataSource
                 :<|> queryDataSource
                 :<|> listDataSourceTemplates_
               )
        :<|> ( retrievePage
                 :<|> createPage
                 :<|> updatePage
                 :<|> retrievePageProperty
                 :<|> retrievePageMarkdown
                 :<|> updatePageMarkdown
                 :<|> movePage
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
        :<|> ( createView
                 :<|> retrieveView
                 :<|> updateView
                 :<|> deleteView
                 :<|> listViews_
                 :<|> queryView
               )
        :<|> listCustomEmojis_
      ) = Client.hoistClient @API Proxy run (Client.client @API Proxy) authorization notionVersion

    authorization = "Bearer " <> token

    run :: Client.ClientM a -> IO a
    run clientM = do
      result <- Client.runClientM clientM clientEnv
      case result of
        Left err -> case parseNotionError err of
          Just notionErr -> Exception.throwIO notionErr
          Nothing -> Exception.throwIO err
        Right a -> return a

    -- Keep the ListOf structure
    listBlockChildren = retrieveBlockChildren_
    listUsers = listUsers_
    listComments = listComments_
    search = search_
    listDataSourceTemplates = listDataSourceTemplates_
    listViews = listViews_
    listCustomEmojis = listCustomEmojis_

-- | API methods
data Methods = Methods
  { -- \* Databases
    createDatabase :: CreateDatabase -> IO DatabaseObject,
    retrieveDatabase :: DatabaseID -> IO DatabaseObject,
    updateDatabase :: DatabaseID -> UpdateDatabase -> IO DatabaseObject,
    -- | @Deprecated: Use 'queryDataSource' instead.@
    queryDatabase :: DatabaseID -> QueryDatabase -> IO (ListOf PageObject),
    -- \* Data Sources
    retrieveDataSource :: DataSourceID -> IO DataSourceObject,
    createDataSource :: DataSources.CreateDataSource -> IO DataSourceObject,
    updateDataSource :: DataSourceID -> DataSources.UpdateDataSource -> IO DataSourceObject,
    queryDataSource :: DataSourceID -> DataSources.QueryDataSource -> IO (ListOf PageObject),
    -- | List templates available for a data source
    listDataSourceTemplates ::
      DataSourceID ->
      Maybe Text ->
      -- \^ name filter (exact match)
      Maybe Text ->
      -- \^ start_cursor
      Maybe Natural ->
      -- \^ page_size
      IO DataSources.ListTemplatesResponse,
    -- \* Pages
    createPage :: CreatePage -> IO PageObject,
    retrievePage :: PageID -> IO PageObject,
    updatePage :: PageID -> UpdatePage -> IO PageObject,
    -- | Retrieve a single page property item.
    -- For title, rich_text, relation, and people properties, the response may be paginated.
    retrievePageProperty ::
      PageID ->
      Text ->
      -- \^ property_id
      Maybe Text ->
      -- \^ start_cursor
      Maybe Natural ->
      -- \^ page_size
      IO PropertyItemResponse,
    retrievePageMarkdown ::
      PageID ->
      Maybe Bool ->
      -- \^ include_transcript
      IO PageMarkdown,
    -- | Update page content using markdown. Supports targeted search-and-replace
    -- edits, full content replacement, and legacy insert/replace commands.
    updatePageMarkdown ::
      PageID ->
      UpdatePageMarkdown ->
      IO PageMarkdown,
    -- | Move a page to a new parent (page or data source)
    movePage ::
      PageID ->
      MovePage ->
      IO PageObject,
    -- \* Blocks
    retrieveBlock :: BlockID -> IO BlockObject,
    updateBlock :: BlockID -> Blocks.BlockUpdate -> IO BlockObject,
    listBlockChildren ::
      ParentID ->
      Maybe Natural ->
      -- \^ page_size
      Maybe Text ->
      -- \^ start_cursor
      IO (ListOf BlockObject),
    appendBlockChildren :: ParentID -> Blocks.AppendBlockChildren -> IO (ListOf BlockObject),
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
    search :: SearchRequest -> IO (ListOf Value),
    -- \* Comments
    createComment :: Comments.CreateComment -> IO CommentObject,
    -- | List comments on a block or page. To list comments on a page, use the page ID
    -- as the block_id parameter (pages are blocks in Notion).
    listComments ::
      Maybe BlockID ->
      -- \^ block_id (use page ID here for page comments)
      Maybe Text ->
      -- \^ start_cursor
      Maybe Natural ->
      -- \^ page_size
      IO (ListOf CommentObject),
    -- \* Views
    createView :: Views.CreateView -> IO ViewObject,
    retrieveView :: Views.ViewID -> IO ViewObject,
    updateView :: Views.ViewID -> Views.UpdateView -> IO ViewObject,
    deleteView :: Views.ViewID -> IO ViewObject,
    listViews ::
      Maybe UUID ->
      -- \^ database_id
      Maybe UUID ->
      -- \^ data_source_id
      Maybe Text ->
      -- \^ start_cursor
      Maybe Natural ->
      -- \^ page_size
      IO (ListOf ViewObject),
    queryView :: Views.ViewID -> Views.QueryView -> IO (ListOf PageObject),
    -- \* Custom Emojis
    listCustomEmojis ::
      Maybe Text ->
      -- \^ name filter (exact match)
      Maybe Text ->
      -- \^ start_cursor
      Maybe Natural ->
      -- \^ page_size
      IO (ListOf CustomEmoji)
  }

-- | Servant API
type API =
  Header' [Required, Strict] "Authorization" Text
    :> Header' [Required, Strict] "Notion-Version" Text
    :> ( Databases.API
           :<|> DataSources.API
           :<|> Pages.API
           :<|> Blocks.API
           :<|> Users.API
           :<|> Search.API
           :<|> Comments.API
           :<|> Views.API
           :<|> CustomEmojis.API
       )
