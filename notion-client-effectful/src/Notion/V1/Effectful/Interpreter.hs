-- | Default interpreter for the 'Notion' effect.
--
-- 'runNotion' dispatches every 'Notion' constructor through a
-- concrete 'Notion.V1.Methods' value. Any 'NotionError' thrown by
-- the underlying 'IO' action is caught and re-raised via the
-- 'Error' effect, so callers can branch on Notion API error shapes
-- (e.g. @object_not_found@) without resorting to 'IO'-level exception
-- handling. Other 'Servant.Client.ClientError' values (network
-- failures, decoding errors) are intentionally /not/ caught: they
-- remain 'IO' exceptions, preserving the existing 'Notion.V1' contract.
module Notion.V1.Effectful.Interpreter
  ( runNotion,
  )
where

import Control.Exception qualified as Exception
import Effectful (Eff, IOE, liftIO, (:>))
import Effectful.Dispatch.Dynamic (interpret)
import Effectful.Error.Static (Error, throwError)
import Notion.V1 (Methods)
import Notion.V1 qualified as Notion
import Notion.V1.Effectful.Effect
  ( Notion
      ( AppendBlockChildren,
        CompleteFileUpload,
        CreateComment,
        CreateDataSource,
        CreateDatabase,
        CreateFileUpload,
        CreatePage,
        CreateView,
        DeleteBlock,
        DeleteView,
        ListBlockChildren,
        ListComments,
        ListCustomEmojis,
        ListDataSourceTemplates,
        ListFileUploads,
        ListUsers,
        ListViews,
        MovePage,
        QueryDataSource,
        QueryDatabase,
        QueryView,
        RetrieveBlock,
        RetrieveDataSource,
        RetrieveDatabase,
        RetrieveFileUpload,
        RetrieveMyUser,
        RetrievePage,
        RetrievePageFiltered,
        RetrievePageMarkdown,
        RetrievePageProperty,
        RetrieveUser,
        RetrieveView,
        Search,
        SendFileUploadContent,
        UpdateBlock,
        UpdateDataSource,
        UpdateDatabase,
        UpdatePage,
        UpdatePageMarkdown,
        UpdateView
      ),
  )
import Notion.V1.Error (NotionError)

-- | Interpret 'Notion' using a concrete 'Methods' value.
--
-- >>> runEff . runErrorNoCallStack @NotionError . runNotion methods $ retrievePage pid
--
-- The dispatched 'IO' action is wrapped with 'Control.Exception.try':
-- a 'NotionError' is re-thrown via 'throwError', anything else
-- propagates as an 'IO' exception.
runNotion ::
  (IOE :> es, Error NotionError :> es) =>
  Methods ->
  Eff (Notion : es) a ->
  Eff es a
runNotion methods = interpret $ \_ -> \case
  -- Databases
  CreateDatabase req -> runIO (Notion.createDatabase methods req)
  RetrieveDatabase dbId -> runIO (Notion.retrieveDatabase methods dbId)
  UpdateDatabase dbId req -> runIO (Notion.updateDatabase methods dbId req)
  QueryDatabase dbId req -> runIO (Notion.queryDatabase methods dbId req)
  -- Data Sources
  RetrieveDataSource dsId -> runIO (Notion.retrieveDataSource methods dsId)
  CreateDataSource req -> runIO (Notion.createDataSource methods req)
  UpdateDataSource dsId req -> runIO (Notion.updateDataSource methods dsId req)
  QueryDataSource dsId req -> runIO (Notion.queryDataSource methods dsId req)
  ListDataSourceTemplates dsId nameFilter cursor pageSize ->
    runIO (Notion.listDataSourceTemplates methods dsId nameFilter cursor pageSize)
  -- Pages
  CreatePage req -> runIO (Notion.createPage methods req)
  RetrievePage pid -> runIO (Notion.retrievePage methods pid)
  RetrievePageFiltered pid props -> runIO (Notion.retrievePageFiltered methods pid props)
  UpdatePage pid req -> runIO (Notion.updatePage methods pid req)
  RetrievePageProperty pid prop cursor size ->
    runIO (Notion.retrievePageProperty methods pid prop cursor size)
  RetrievePageMarkdown pid includeTx ->
    runIO (Notion.retrievePageMarkdown methods pid includeTx)
  UpdatePageMarkdown pid req -> runIO (Notion.updatePageMarkdown methods pid req)
  MovePage pid req -> runIO (Notion.movePage methods pid req)
  -- Blocks
  RetrieveBlock bid -> runIO (Notion.retrieveBlock methods bid)
  UpdateBlock bid req -> runIO (Notion.updateBlock methods bid req)
  ListBlockChildren pid pageSize cursor ->
    runIO (Notion.listBlockChildren methods pid pageSize cursor)
  AppendBlockChildren pid req -> runIO (Notion.appendBlockChildren methods pid req)
  DeleteBlock bid -> runIO (Notion.deleteBlock methods bid)
  -- Users
  RetrieveUser uid -> runIO (Notion.retrieveUser methods uid)
  ListUsers pageSize cursor -> runIO (Notion.listUsers methods pageSize cursor)
  RetrieveMyUser -> runIO (Notion.retrieveMyUser methods)
  -- Search
  Search req -> runIO (Notion.search methods req)
  -- Comments
  CreateComment req -> runIO (Notion.createComment methods req)
  ListComments bid cursor pageSize ->
    runIO (Notion.listComments methods bid cursor pageSize)
  -- Views
  CreateView req -> runIO (Notion.createView methods req)
  RetrieveView vid -> runIO (Notion.retrieveView methods vid)
  UpdateView vid req -> runIO (Notion.updateView methods vid req)
  DeleteView vid -> runIO (Notion.deleteView methods vid)
  ListViews dbId dsId cursor pageSize ->
    runIO (Notion.listViews methods dbId dsId cursor pageSize)
  QueryView vid req -> runIO (Notion.queryView methods vid req)
  -- Custom Emojis
  ListCustomEmojis nameFilter cursor pageSize ->
    runIO (Notion.listCustomEmojis methods nameFilter cursor pageSize)
  -- File Uploads
  CreateFileUpload req -> runIO (Notion.createFileUpload methods req)
  RetrieveFileUpload fid -> runIO (Notion.retrieveFileUpload methods fid)
  SendFileUploadContent fid payload ->
    runIO (Notion.sendFileUploadContent methods fid payload)
  CompleteFileUpload fid -> runIO (Notion.completeFileUpload methods fid)
  ListFileUploads statusFilter cursor pageSize ->
    runIO (Notion.listFileUploads methods statusFilter cursor pageSize)

-- | Run an 'IO' action, funneling any thrown 'NotionError' through
-- the 'Error' effect.
runIO :: (IOE :> es, Error NotionError :> es) => IO a -> Eff es a
runIO action = do
  result <- liftIO (Exception.try action)
  case result of
    Left (ne :: NotionError) -> throwError ne
    Right a -> pure a
