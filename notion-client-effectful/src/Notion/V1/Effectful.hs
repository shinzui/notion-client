-- | Effectful surface for @notion-client@.
--
-- This module re-exports the 'Notion' effect, its smart constructors,
-- and the default 'runNotion' interpreter. A caller typically writes:
--
-- @
-- import Notion.V1                    (Methods, getClientEnv, makeMethods)
-- import Notion.V1.Effectful qualified as NE
-- @
--
-- and then uses @NE.retrievePage@, @NE.search@, @NE.runNotion@, etc.
-- The qualified import avoids name clashes with the matching
-- 'Notion.V1.Methods' record selectors — every smart constructor
-- here shares its name with a field of @Methods@ on purpose, so
-- migrating an IO call site is a near-mechanical rewrite.
--
-- Error handling: 'runNotion' catches 'NotionError' from the
-- underlying 'Methods' value and re-throws via the @Error NotionError@
-- effect. Other 'Servant.Client.ClientError' values (network
-- failures, decoding errors) remain 'IO' exceptions.
module Notion.V1.Effectful
  ( -- * Effect
    Notion,

    -- * Interpreter
    runNotion,

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

import Notion.V1.Effectful.Effect
  ( Notion,
    appendBlockChildren,
    completeFileUpload,
    createComment,
    createDataSource,
    createDatabase,
    createFileUpload,
    createPage,
    createView,
    deleteBlock,
    deleteView,
    listBlockChildren,
    listComments,
    listCustomEmojis,
    listDataSourceTemplates,
    listFileUploads,
    listUsers,
    listViews,
    movePage,
    queryDataSource,
    queryDatabase,
    queryView,
    retrieveBlock,
    retrieveDataSource,
    retrieveDatabase,
    retrieveFileUpload,
    retrieveMyUser,
    retrievePage,
    retrievePageFiltered,
    retrievePageMarkdown,
    retrievePageProperty,
    retrieveUser,
    retrieveView,
    search,
    sendFileUploadContent,
    updateBlock,
    updateDataSource,
    updateDatabase,
    updatePage,
    updatePageMarkdown,
    updateView,
  )
import Notion.V1.Effectful.Interpreter (runNotion)
