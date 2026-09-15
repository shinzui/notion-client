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
--     manager <- newTlsManager
--
--     let methods = makeMethodsWith defaultClientConfig manager (Text.pack token)
--
--     page <- retrievePage methods "page-id-here"
--
--     print page
-- @
module Notion.V1
  ( -- * Methods
    getClientEnv,
    makeMethods,
    makeMethodsWith,
    makeMethodsWithEnv,
    Methods (..),

    -- * Configuration
    ClientConfig (..),
    defaultClientConfig,
    legacyClientConfig,
    defaultBaseUrl,
    defaultNotionVersion,
    RetryOptions (..),
    defaultRetryOptions,
    noRetries,
    LogLevel (..),
    Logger,
    stderrLogger,

    -- * Runtime building blocks
    RequestContext (..),
    requestContextFor,
    standardHeaders,
    responseTimeoutFor,
    withRetries,

    -- * Servant
    API,
  )
where

import Data.Maybe (fromMaybe)
import Data.Proxy (Proxy (..))
import Data.Text qualified as Text
import Network.HTTP.Client (Manager)
import Network.HTTP.Client.TLS qualified as TLS
import Notion.Prelude
import Notion.V1.AsyncTasks (AllowAsync (..), AsyncOr, AsyncTask, AsyncTaskID, fromAsyncUnion)
import Notion.V1.AsyncTasks qualified as AsyncTasks
import Notion.V1.Blocks (BlockID, BlockObject)
import Notion.V1.Blocks qualified as Blocks
import Notion.V1.Client
  ( ClientConfig (..),
    LogLevel (..),
    Logger,
    RequestContext (..),
    RetryOptions (..),
    configureClientEnv,
    defaultBaseUrl,
    defaultClientConfig,
    defaultNotionVersion,
    defaultRetryOptions,
    legacyClientConfig,
    noRetries,
    requestContextFor,
    responseTimeoutFor,
    runClientWith,
    standardHeaders,
    stderrLogger,
    withRetries,
  )
import Notion.V1.Comments (CommentContent, CommentObject, CommentResponse)
import Notion.V1.Comments qualified as Comments
import Notion.V1.Common (ParentID, UUID)
import Notion.V1.CustomEmojis (CustomEmoji)
import Notion.V1.CustomEmojis qualified as CustomEmojis
import Notion.V1.DataSources (DataSourceID, DataSourceObject)
import Notion.V1.DataSources qualified as DataSources
import Notion.V1.Databases (CreateDatabase, DatabaseID, DatabaseObject, QueryDatabase, UpdateDatabase)
import Notion.V1.Databases qualified as Databases
import Notion.V1.FileUploads (FileUploadID, FileUploadObject, FileUploadStatus)
import Notion.V1.FileUploads qualified as FileUploads
import Notion.V1.ListOf (ListOf (..))
import Notion.V1.MeetingNotes qualified as MeetingNotes
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
import Servant.Multipart.Client (genBoundary)

-- | Convenient utility to get a `ClientEnv` for the most common use case
getClientEnv ::
  -- | Base URL for API
  Text ->
  IO ClientEnv
getClientEnv baseUrlText = do
  baseUrl <- Client.parseBaseUrl (Text.unpack baseUrlText)
  manager <- TLS.newTlsManager
  pure (Client.mkClientEnv manager baseUrl)

-- | Get a record of API methods after providing an API token.
--
-- Uses 'legacyClientConfig': default API version, retries and @User-Agent@,
-- keeping the 'ClientEnv' manager's own timeout.
makeMethods ::
  ClientEnv ->
  -- | API token
  Text ->
  Methods
makeMethods = makeMethodsWithEnv legacyClientConfig

-- | Build 'Methods' from a configuration, a connection manager (for example
-- from 'Network.HTTP.Client.TLS.newTlsManager') and an API token. The base URL
-- comes from 'apiBaseUrl'.
makeMethodsWith :: ClientConfig -> Manager -> Text -> Methods
makeMethodsWith config manager =
  makeMethodsWithEnv config (Client.mkClientEnv manager (apiBaseUrl config))

-- | Build 'Methods' from a configuration, an existing 'ClientEnv' (which
-- supplies the manager and base URL) and an API token.
makeMethodsWithEnv ::
  ClientConfig ->
  ClientEnv ->
  -- | API token
  Text ->
  Methods
makeMethodsWithEnv config clientEnv token = Methods {..}
  where
    context = requestContextFor config clientEnv token
    configuredEnv = configureClientEnv config clientEnv
    ( ( createDatabase
          :<|> retrieveDatabase
          :<|> updateDatabase
          :<|> queryDatabase_
        )
        :<|> ( retrieveDataSource
                 :<|> createDataSource
                 :<|> updateDataSource
                 :<|> queryDataSource_
                 :<|> listDataSourceTemplates_
               )
        :<|> ( retrievePageFiltered
                 :<|> createPage
                 :<|> updatePage
                 :<|> retrievePageProperty
                 :<|> retrievePageMarkdown
                 :<|> updatePageMarkdown
                 :<|> movePage
                 :<|> createPageAsync_
                 :<|> updatePageMarkdownAsync_
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
                 :<|> retrieveComment
                 :<|> updateComment
                 :<|> deleteComment
               )
        :<|> ( createView
                 :<|> retrieveView
                 :<|> updateView
                 :<|> deleteView
                 :<|> listViews_
                 :<|> queryView
               )
        :<|> listCustomEmojis_
        :<|> ( createFileUpload
                 :<|> retrieveFileUpload
                 :<|> sendFileUploadContent_
                 :<|> completeFileUpload
                 :<|> listFileUploads_
               )
        :<|> retrieveAsyncTask
        :<|> createMeetingNote
      ) =
        Client.hoistClient
          @API
          Proxy
          run
          (Client.client @API Proxy)
          (contextAuthorization context)
          (notionVersion config)

    run :: Client.ClientM a -> IO a
    run = runClientWith configuredEnv

    -- Wrap retrievePageFiltered to provide backward-compatible retrievePage
    retrievePage pid = retrievePageFiltered pid []

    -- The async variants always send allow_async: true
    createPageAsync req = fromAsyncUnion <$> createPageAsync_ (AllowAsync req)
    updatePageMarkdownAsync pid req = fromAsyncUnion <$> updatePageMarkdownAsync_ pid (AllowAsync req)

    -- filter_properties is sent as repeated query parameters (see DataSources.API)
    queryDataSource dsId q@DataSources.QueryDataSource {filterProperties = props} =
      queryDataSource_ dsId (fromMaybe [] props) q
    queryDatabase dbId q@Databases.QueryDatabase {filterProperties = props} =
      queryDatabase_ dbId (fromMaybe [] props) q

    -- Keep the ListOf structure
    listBlockChildren = retrieveBlockChildren_
    listUsers = listUsers_
    listComments = listComments_
    search = search_
    listDataSourceTemplates = listDataSourceTemplates_
    listViews = listViews_
    listCustomEmojis = listCustomEmojis_
    listFileUploads = listFileUploads_
    sendFileUploadContent fid upload = do
      boundary <- genBoundary
      sendFileUploadContent_ fid (boundary, upload)

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
    -- | Retrieve a page, optionally filtering which properties are returned.
    retrievePageFiltered :: PageID -> [Text] -> IO PageObject,
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
    -- | Like 'createPage' but sends @allow_async: true@, so Notion may answer
    -- with an async task instead of the page. Only meaningful when the
    -- request's @markdown@ is set.
    createPageAsync :: CreatePage -> IO (AsyncOr PageObject),
    -- | Like 'updatePageMarkdown' but sends @allow_async: true@, so Notion may
    -- answer with an async task instead of the result.
    updatePageMarkdownAsync :: PageID -> UpdatePageMarkdown -> IO (AsyncOr PageMarkdown),
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

    -- | Create a comment on a page or block, or a reply in a discussion.
    createComment :: Comments.CreateComment -> IO CommentResponse,
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
    retrieveComment :: Comments.CommentID -> IO CommentResponse,
    -- | Replace a comment's content with rich text or Markdown.
    updateComment :: Comments.CommentID -> CommentContent -> IO CommentResponse,
    deleteComment :: Comments.CommentID -> IO CommentResponse,
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
      IO (ListOf CustomEmoji),
    -- \* File Uploads
    createFileUpload :: FileUploads.CreateFileUpload -> IO FileUploadObject,
    retrieveFileUpload :: FileUploadID -> IO FileUploadObject,
    sendFileUploadContent :: FileUploadID -> FileUploads.SendFileUpload -> IO FileUploadObject,
    completeFileUpload :: FileUploadID -> IO FileUploadObject,
    listFileUploads ::
      Maybe FileUploadStatus ->
      -- \^ status filter
      Maybe Text ->
      -- \^ start_cursor
      Maybe Natural ->
      -- \^ page_size
      IO (ListOf FileUploadObject),
    -- \* Async tasks

    -- | Retrieve a background task; see 'Notion.V1.AsyncTasks.waitForAsyncTask'.
    retrieveAsyncTask :: AsyncTaskID -> IO AsyncTask,
    -- \* Meeting notes

    -- | Create a meeting note from an uploaded recording or an existing media block.
    createMeetingNote :: MeetingNotes.CreateMeetingNote -> IO MeetingNotes.CreateMeetingNoteResponse
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
           :<|> FileUploads.API
           :<|> AsyncTasks.API
           :<|> MeetingNotes.API
       )
