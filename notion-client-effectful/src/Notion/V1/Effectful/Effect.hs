-- | The 'Notion' effect and its smart constructors.
--
-- One constructor per field of 'Notion.V1.Methods'. Each smart
-- constructor has the same name, same argument order, and same
-- argument types as the corresponding @Methods@ field — so migrating
-- an 'IO'-based call site amounts to dropping the explicit
-- @methods@ argument.
--
-- /Import note./ Every smart constructor name clashes with the
-- matching 'Notion.V1.Methods' record selector. Import one of the
-- two modules qualified (mirroring how 'Notion.V1' itself qualifies
-- @Pages@, @Databases@, etc.).
module Notion.V1.Effectful.Effect
  ( -- * Effect
    Notion (..),

    -- * Databases
    createDatabase,
    retrieveDatabase,
    updateDatabase,
    queryDatabase,

    -- * Data Sources
    retrieveDataSource,
    createDataSource,
    updateDataSource,
    queryDataSource,
    listDataSourceTemplates,

    -- * Pages
    createPage,
    retrievePage,
    retrievePageFiltered,
    updatePage,
    retrievePageProperty,
    retrievePageMarkdown,
    updatePageMarkdown,
    movePage,

    -- * Blocks
    retrieveBlock,
    updateBlock,
    listBlockChildren,
    appendBlockChildren,
    deleteBlock,

    -- * Users
    retrieveUser,
    listUsers,
    retrieveMyUser,

    -- * Search
    search,

    -- * Comments
    createComment,
    listComments,

    -- * Views
    createView,
    retrieveView,
    updateView,
    deleteView,
    listViews,
    queryView,

    -- * Custom Emojis
    listCustomEmojis,

    -- * File Uploads
    createFileUpload,
    retrieveFileUpload,
    sendFileUploadContent,
    completeFileUpload,
    listFileUploads,
  )
where

import Data.Aeson (Value)
import Data.Text (Text)
import Effectful (Dispatch (..), DispatchOf, Eff, Effect, (:>))
import Effectful.Dispatch.Dynamic (send)
import Notion.V1.Blocks (BlockID, BlockObject)
import Notion.V1.Blocks qualified as Blocks
import Notion.V1.Comments (CommentObject)
import Notion.V1.Comments qualified as Comments
import Notion.V1.Common (ParentID, UUID)
import Notion.V1.CustomEmojis (CustomEmoji)
import Notion.V1.DataSources (DataSourceID, DataSourceObject)
import Notion.V1.DataSources qualified as DataSources
import Notion.V1.Databases (CreateDatabase, DatabaseID, DatabaseObject, QueryDatabase, UpdateDatabase)
import Notion.V1.FileUploads (FileUploadID, FileUploadObject, FileUploadStatus)
import Notion.V1.FileUploads qualified as FileUploads
import Notion.V1.ListOf (ListOf)
import Notion.V1.Pages (CreatePage, MovePage, PageID, PageMarkdown, PageObject, PropertyItemResponse, UpdatePage, UpdatePageMarkdown)
import Notion.V1.Search (SearchRequest)
import Notion.V1.Users (UserID, UserObject)
import Notion.V1.Views (ViewObject)
import Notion.V1.Views qualified as Views
import Numeric.Natural (Natural)

-- | Operations on a Notion workspace.
--
-- One constructor per field of 'Notion.V1.Methods'. The constructor
-- names are the @PascalCase@ form of the field names; argument order
-- matches the field signature.
data Notion :: Effect where
  -- Databases
  CreateDatabase :: CreateDatabase -> Notion m DatabaseObject
  RetrieveDatabase :: DatabaseID -> Notion m DatabaseObject
  UpdateDatabase :: DatabaseID -> UpdateDatabase -> Notion m DatabaseObject
  QueryDatabase :: DatabaseID -> QueryDatabase -> Notion m (ListOf PageObject)
  -- Data Sources
  RetrieveDataSource :: DataSourceID -> Notion m DataSourceObject
  CreateDataSource :: DataSources.CreateDataSource -> Notion m DataSourceObject
  UpdateDataSource :: DataSourceID -> DataSources.UpdateDataSource -> Notion m DataSourceObject
  QueryDataSource :: DataSourceID -> DataSources.QueryDataSource -> Notion m (ListOf PageObject)
  ListDataSourceTemplates ::
    DataSourceID ->
    Maybe Text ->
    Maybe Text ->
    Maybe Natural ->
    Notion m DataSources.ListTemplatesResponse
  -- Pages
  CreatePage :: CreatePage -> Notion m PageObject
  RetrievePage :: PageID -> Notion m PageObject
  RetrievePageFiltered :: PageID -> [Text] -> Notion m PageObject
  UpdatePage :: PageID -> UpdatePage -> Notion m PageObject
  RetrievePageProperty ::
    PageID ->
    Text ->
    Maybe Text ->
    Maybe Natural ->
    Notion m PropertyItemResponse
  RetrievePageMarkdown :: PageID -> Maybe Bool -> Notion m PageMarkdown
  UpdatePageMarkdown :: PageID -> UpdatePageMarkdown -> Notion m PageMarkdown
  MovePage :: PageID -> MovePage -> Notion m PageObject
  -- Blocks
  RetrieveBlock :: BlockID -> Notion m BlockObject
  UpdateBlock :: BlockID -> Blocks.BlockUpdate -> Notion m BlockObject
  ListBlockChildren :: ParentID -> Maybe Natural -> Maybe Text -> Notion m (ListOf BlockObject)
  AppendBlockChildren :: ParentID -> Blocks.AppendBlockChildren -> Notion m (ListOf BlockObject)
  DeleteBlock :: BlockID -> Notion m BlockObject
  -- Users
  RetrieveUser :: UserID -> Notion m UserObject
  ListUsers :: Maybe Natural -> Maybe Text -> Notion m (ListOf UserObject)
  RetrieveMyUser :: Notion m UserObject
  -- Search
  Search :: SearchRequest -> Notion m (ListOf Value)
  -- Comments
  CreateComment :: Comments.CreateComment -> Notion m CommentObject
  ListComments :: Maybe BlockID -> Maybe Text -> Maybe Natural -> Notion m (ListOf CommentObject)
  -- Views
  CreateView :: Views.CreateView -> Notion m ViewObject
  RetrieveView :: Views.ViewID -> Notion m ViewObject
  UpdateView :: Views.ViewID -> Views.UpdateView -> Notion m ViewObject
  DeleteView :: Views.ViewID -> Notion m ViewObject
  ListViews ::
    Maybe UUID ->
    Maybe UUID ->
    Maybe Text ->
    Maybe Natural ->
    Notion m (ListOf ViewObject)
  QueryView :: Views.ViewID -> Views.QueryView -> Notion m (ListOf PageObject)
  -- Custom Emojis
  ListCustomEmojis ::
    Maybe Text ->
    Maybe Text ->
    Maybe Natural ->
    Notion m (ListOf CustomEmoji)
  -- File Uploads
  CreateFileUpload :: FileUploads.CreateFileUpload -> Notion m FileUploadObject
  RetrieveFileUpload :: FileUploadID -> Notion m FileUploadObject
  SendFileUploadContent :: FileUploadID -> FileUploads.SendFileUpload -> Notion m FileUploadObject
  CompleteFileUpload :: FileUploadID -> Notion m FileUploadObject
  ListFileUploads ::
    Maybe FileUploadStatus ->
    Maybe Text ->
    Maybe Natural ->
    Notion m (ListOf FileUploadObject)

type instance DispatchOf Notion = 'Dynamic

-- ── Databases ─────────────────────────────────────────────────────

-- | See 'Notion.V1.Methods'.'Notion.V1.createDatabase'.
createDatabase :: (Notion :> es) => CreateDatabase -> Eff es DatabaseObject
createDatabase = send . CreateDatabase

-- | See 'Notion.V1.Methods'.'Notion.V1.retrieveDatabase'.
retrieveDatabase :: (Notion :> es) => DatabaseID -> Eff es DatabaseObject
retrieveDatabase = send . RetrieveDatabase

-- | See 'Notion.V1.Methods'.'Notion.V1.updateDatabase'.
updateDatabase :: (Notion :> es) => DatabaseID -> UpdateDatabase -> Eff es DatabaseObject
updateDatabase dbId upd = send (UpdateDatabase dbId upd)

{-# DEPRECATED queryDatabase "Use 'queryDataSource' instead." #-}

-- | See 'Notion.V1.Methods'.'Notion.V1.queryDatabase'. Deprecated upstream;
-- the constructor is retained for parity so existing call sites can migrate
-- in lockstep with the base library.
queryDatabase ::
  (Notion :> es) =>
  DatabaseID ->
  QueryDatabase ->
  Eff es (ListOf PageObject)
queryDatabase dbId q = send (QueryDatabase dbId q)

-- ── Data Sources ──────────────────────────────────────────────────

-- | See 'Notion.V1.Methods'.'Notion.V1.retrieveDataSource'.
retrieveDataSource :: (Notion :> es) => DataSourceID -> Eff es DataSourceObject
retrieveDataSource = send . RetrieveDataSource

-- | See 'Notion.V1.Methods'.'Notion.V1.createDataSource'.
createDataSource :: (Notion :> es) => DataSources.CreateDataSource -> Eff es DataSourceObject
createDataSource = send . CreateDataSource

-- | See 'Notion.V1.Methods'.'Notion.V1.updateDataSource'.
updateDataSource ::
  (Notion :> es) =>
  DataSourceID ->
  DataSources.UpdateDataSource ->
  Eff es DataSourceObject
updateDataSource dsId upd = send (UpdateDataSource dsId upd)

-- | See 'Notion.V1.Methods'.'Notion.V1.queryDataSource'.
queryDataSource ::
  (Notion :> es) =>
  DataSourceID ->
  DataSources.QueryDataSource ->
  Eff es (ListOf PageObject)
queryDataSource dsId q = send (QueryDataSource dsId q)

-- | See 'Notion.V1.Methods'.'Notion.V1.listDataSourceTemplates'.
listDataSourceTemplates ::
  (Notion :> es) =>
  DataSourceID ->
  Maybe Text ->
  Maybe Text ->
  Maybe Natural ->
  Eff es DataSources.ListTemplatesResponse
listDataSourceTemplates dsId nameFilter startCursor pageSize =
  send (ListDataSourceTemplates dsId nameFilter startCursor pageSize)

-- ── Pages ─────────────────────────────────────────────────────────

-- | See 'Notion.V1.Methods'.'Notion.V1.createPage'.
createPage :: (Notion :> es) => CreatePage -> Eff es PageObject
createPage = send . CreatePage

-- | See 'Notion.V1.Methods'.'Notion.V1.retrievePage'.
retrievePage :: (Notion :> es) => PageID -> Eff es PageObject
retrievePage = send . RetrievePage

-- | See 'Notion.V1.Methods'.'Notion.V1.retrievePageFiltered'.
retrievePageFiltered :: (Notion :> es) => PageID -> [Text] -> Eff es PageObject
retrievePageFiltered pid props = send (RetrievePageFiltered pid props)

-- | See 'Notion.V1.Methods'.'Notion.V1.updatePage'.
updatePage :: (Notion :> es) => PageID -> UpdatePage -> Eff es PageObject
updatePage pid upd = send (UpdatePage pid upd)

-- | See 'Notion.V1.Methods'.'Notion.V1.retrievePageProperty'.
retrievePageProperty ::
  (Notion :> es) =>
  PageID ->
  Text ->
  Maybe Text ->
  Maybe Natural ->
  Eff es PropertyItemResponse
retrievePageProperty pid prop cursor size =
  send (RetrievePageProperty pid prop cursor size)

-- | See 'Notion.V1.Methods'.'Notion.V1.retrievePageMarkdown'.
retrievePageMarkdown :: (Notion :> es) => PageID -> Maybe Bool -> Eff es PageMarkdown
retrievePageMarkdown pid includeTx = send (RetrievePageMarkdown pid includeTx)

-- | See 'Notion.V1.Methods'.'Notion.V1.updatePageMarkdown'.
updatePageMarkdown :: (Notion :> es) => PageID -> UpdatePageMarkdown -> Eff es PageMarkdown
updatePageMarkdown pid upd = send (UpdatePageMarkdown pid upd)

-- | See 'Notion.V1.Methods'.'Notion.V1.movePage'.
movePage :: (Notion :> es) => PageID -> MovePage -> Eff es PageObject
movePage pid mv = send (MovePage pid mv)

-- ── Blocks ────────────────────────────────────────────────────────

-- | See 'Notion.V1.Methods'.'Notion.V1.retrieveBlock'.
retrieveBlock :: (Notion :> es) => BlockID -> Eff es BlockObject
retrieveBlock = send . RetrieveBlock

-- | See 'Notion.V1.Methods'.'Notion.V1.updateBlock'.
updateBlock :: (Notion :> es) => BlockID -> Blocks.BlockUpdate -> Eff es BlockObject
updateBlock bid upd = send (UpdateBlock bid upd)

-- | See 'Notion.V1.Methods'.'Notion.V1.listBlockChildren'.
listBlockChildren ::
  (Notion :> es) =>
  ParentID ->
  Maybe Natural ->
  Maybe Text ->
  Eff es (ListOf BlockObject)
listBlockChildren pid pageSize startCursor =
  send (ListBlockChildren pid pageSize startCursor)

-- | See 'Notion.V1.Methods'.'Notion.V1.appendBlockChildren'.
appendBlockChildren ::
  (Notion :> es) =>
  ParentID ->
  Blocks.AppendBlockChildren ->
  Eff es (ListOf BlockObject)
appendBlockChildren pid append = send (AppendBlockChildren pid append)

-- | See 'Notion.V1.Methods'.'Notion.V1.deleteBlock'.
deleteBlock :: (Notion :> es) => BlockID -> Eff es BlockObject
deleteBlock = send . DeleteBlock

-- ── Users ─────────────────────────────────────────────────────────

-- | See 'Notion.V1.Methods'.'Notion.V1.retrieveUser'.
retrieveUser :: (Notion :> es) => UserID -> Eff es UserObject
retrieveUser = send . RetrieveUser

-- | See 'Notion.V1.Methods'.'Notion.V1.listUsers'.
listUsers :: (Notion :> es) => Maybe Natural -> Maybe Text -> Eff es (ListOf UserObject)
listUsers pageSize startCursor = send (ListUsers pageSize startCursor)

-- | See 'Notion.V1.Methods'.'Notion.V1.retrieveMyUser'.
retrieveMyUser :: (Notion :> es) => Eff es UserObject
retrieveMyUser = send RetrieveMyUser

-- ── Search ────────────────────────────────────────────────────────

-- | See 'Notion.V1.Methods'.'Notion.V1.search'.
search :: (Notion :> es) => SearchRequest -> Eff es (ListOf Value)
search = send . Search

-- ── Comments ──────────────────────────────────────────────────────

-- | See 'Notion.V1.Methods'.'Notion.V1.createComment'.
createComment :: (Notion :> es) => Comments.CreateComment -> Eff es CommentObject
createComment = send . CreateComment

-- | See 'Notion.V1.Methods'.'Notion.V1.listComments'.
listComments ::
  (Notion :> es) =>
  Maybe BlockID ->
  Maybe Text ->
  Maybe Natural ->
  Eff es (ListOf CommentObject)
listComments bid startCursor pageSize = send (ListComments bid startCursor pageSize)

-- ── Views ─────────────────────────────────────────────────────────

-- | See 'Notion.V1.Methods'.'Notion.V1.createView'.
createView :: (Notion :> es) => Views.CreateView -> Eff es ViewObject
createView = send . CreateView

-- | See 'Notion.V1.Methods'.'Notion.V1.retrieveView'.
retrieveView :: (Notion :> es) => Views.ViewID -> Eff es ViewObject
retrieveView = send . RetrieveView

-- | See 'Notion.V1.Methods'.'Notion.V1.updateView'.
updateView :: (Notion :> es) => Views.ViewID -> Views.UpdateView -> Eff es ViewObject
updateView vid upd = send (UpdateView vid upd)

-- | See 'Notion.V1.Methods'.'Notion.V1.deleteView'.
deleteView :: (Notion :> es) => Views.ViewID -> Eff es ViewObject
deleteView = send . DeleteView

-- | See 'Notion.V1.Methods'.'Notion.V1.listViews'.
listViews ::
  (Notion :> es) =>
  Maybe UUID ->
  Maybe UUID ->
  Maybe Text ->
  Maybe Natural ->
  Eff es (ListOf ViewObject)
listViews dbId dsId startCursor pageSize =
  send (ListViews dbId dsId startCursor pageSize)

-- | See 'Notion.V1.Methods'.'Notion.V1.queryView'.
queryView :: (Notion :> es) => Views.ViewID -> Views.QueryView -> Eff es (ListOf PageObject)
queryView vid q = send (QueryView vid q)

-- ── Custom Emojis ─────────────────────────────────────────────────

-- | See 'Notion.V1.Methods'.'Notion.V1.listCustomEmojis'.
listCustomEmojis ::
  (Notion :> es) =>
  Maybe Text ->
  Maybe Text ->
  Maybe Natural ->
  Eff es (ListOf CustomEmoji)
listCustomEmojis nameFilter startCursor pageSize =
  send (ListCustomEmojis nameFilter startCursor pageSize)

-- ── File Uploads ──────────────────────────────────────────────────

-- | See 'Notion.V1.Methods'.'Notion.V1.createFileUpload'.
createFileUpload :: (Notion :> es) => FileUploads.CreateFileUpload -> Eff es FileUploadObject
createFileUpload = send . CreateFileUpload

-- | See 'Notion.V1.Methods'.'Notion.V1.retrieveFileUpload'.
retrieveFileUpload :: (Notion :> es) => FileUploadID -> Eff es FileUploadObject
retrieveFileUpload = send . RetrieveFileUpload

-- | See 'Notion.V1.Methods'.'Notion.V1.sendFileUploadContent'.
sendFileUploadContent ::
  (Notion :> es) =>
  FileUploadID ->
  FileUploads.SendFileUpload ->
  Eff es FileUploadObject
sendFileUploadContent fid payload = send (SendFileUploadContent fid payload)

-- | See 'Notion.V1.Methods'.'Notion.V1.completeFileUpload'.
completeFileUpload :: (Notion :> es) => FileUploadID -> Eff es FileUploadObject
completeFileUpload = send . CompleteFileUpload

-- | See 'Notion.V1.Methods'.'Notion.V1.listFileUploads'.
listFileUploads ::
  (Notion :> es) =>
  Maybe FileUploadStatus ->
  Maybe Text ->
  Maybe Natural ->
  Eff es (ListOf FileUploadObject)
listFileUploads statusFilter startCursor pageSize =
  send (ListFileUploads statusFilter startCursor pageSize)
