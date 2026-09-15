-- | @\/v1\/file_uploads@
module Notion.V1.FileUploads
  ( -- * Main types
    FileUploadID,
    FileUploadObject (..),
    FileUploadStatus (..),
    CreateFileUpload (..),
    SendFileUpload (..),

    -- * Supporting types
    NumberOfParts (..),
    FileImportResult (..),
    FileUploadCreator (..),
    FileUploadCreatorType (..),
    FileUploadMode (..),

    -- * Smart constructors
    mkSinglePartUpload,
    mkMultiPartUpload,
    mkExternalUrlUpload,
    mkSendFileUpload,

    -- * Servant
    API,
  )
where

import Data.Aeson ((.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Notion.Prelude
import Notion.V1.Common (UUID)
import Notion.V1.ListOf (ListOf)
import Prelude hiding (id)

-- | File upload ID
type FileUploadID = UUID

-- | Status of a file upload
data FileUploadStatus
  = Pending
  | Uploaded
  | Expired
  | Failed
  deriving stock (Eq, Show)

instance FromJSON FileUploadStatus where
  parseJSON = \case
    String "pending" -> pure Pending
    String "uploaded" -> pure Uploaded
    String "expired" -> pure Expired
    String "failed" -> pure Failed
    String other -> fail $ "Unknown FileUploadStatus: " <> unpack other
    _ -> fail "Expected string for FileUploadStatus"

instance ToJSON FileUploadStatus where
  toJSON = \case
    Pending -> String "pending"
    Uploaded -> String "uploaded"
    Expired -> String "expired"
    Failed -> String "failed"

instance ToHttpApiData FileUploadStatus where
  toQueryParam = \case
    Pending -> "pending"
    Uploaded -> "uploaded"
    Expired -> "expired"
    Failed -> "failed"

-- | Number of parts for multi-part uploads
data NumberOfParts = NumberOfParts
  { total :: Natural,
    sent :: Natural
  }
  deriving stock (Eq, Generic, Show)

instance FromJSON NumberOfParts where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON NumberOfParts where
  toJSON = genericToJSON aesonOptions

-- | Result of a file import operation
data FileImportResult
  = FileImportSuccess
      { importedTime :: POSIXTime
      }
  | FileImportError
      { importedTime :: POSIXTime,
        errorType :: Text,
        errorCode :: Text,
        errorMessage :: Text,
        errorParameter :: Maybe Text,
        errorStatusCode :: Maybe Int
      }
  deriving stock (Show)

instance FromJSON FileImportResult where
  parseJSON = \case
    Object o -> do
      resultType <- o .: "type"
      importedTimeStr <- o .: "imported_time"
      importedTime <- parseISO8601 importedTimeStr
      case resultType of
        "success" -> pure FileImportSuccess {..}
        "error" -> do
          errObj <- o .: "error"
          errorType <- errObj .: "type"
          errorCode <- errObj .: "code"
          errorMessage <- errObj .: "message"
          errorParameter <- errObj .:? "parameter"
          errorStatusCode <- errObj .:? "status_code"
          pure FileImportError {..}
        other -> fail $ "Unknown FileImportResult type: " <> unpack (other :: Text)
    _ -> fail "Expected object for FileImportResult"

instance ToJSON FileImportResult where
  toJSON FileImportSuccess {..} =
    Aeson.object
      [ "type" .= ("success" :: Text),
        "imported_time" .= posixToISO8601 importedTime,
        "success" .= Aeson.object []
      ]
  toJSON FileImportError {..} =
    Aeson.object
      [ "type" .= ("error" :: Text),
        "imported_time" .= posixToISO8601 importedTime,
        "error"
          .= Aeson.object
            ( [ "type" .= errorType,
                "code" .= errorCode,
                "message" .= errorMessage
              ]
                <> maybe [] (\p -> ["parameter" .= p]) errorParameter
                <> maybe [] (\s -> ["status_code" .= s]) errorStatusCode
            )
      ]

-- | Notion file upload object
data FileUploadObject = FileUploadObject
  { id :: FileUploadID,
    object :: Text,
    status :: FileUploadStatus,
    filename :: Maybe Text,
    contentType :: Maybe Text,
    contentLength :: Maybe Natural,
    createdTime :: POSIXTime,
    lastEditedTime :: POSIXTime,
    createdBy :: FileUploadCreator,
    inTrash :: Bool,
    expiryTime :: Maybe POSIXTime,
    numberOfParts :: Maybe NumberOfParts,
    fileImportResult :: Maybe FileImportResult,
    -- | URL to send the file content to, while the upload is pending.
    uploadUrl :: Maybe Text,
    -- | URL that completes a multi-part upload, while the upload is pending.
    completeUrl :: Maybe Text
  }
  deriving stock (Generic, Show)

instance FromJSON FileUploadObject where
  parseJSON = \case
    Object o -> do
      id <- o .: "id"
      object <- o .: "object"
      status <- o .: "status"
      filename <- o .:? "filename"
      contentType <- o .:? "content_type"
      contentLength <- o .:? "content_length"
      createdTimeStr <- o .: "created_time"
      createdTime <- parseISO8601 createdTimeStr
      lastEditedTimeStr <- o .: "last_edited_time"
      lastEditedTime <- parseISO8601 lastEditedTimeStr
      createdBy <- o .: "created_by"
      inTrash <- o .: "in_trash"
      mExpiryStr <- o .:? "expiry_time"
      expiryTime <- case mExpiryStr of
        Nothing -> pure Nothing
        Just str -> Just <$> parseISO8601 str
      numberOfParts <- o .:? "number_of_parts"
      fileImportResult <- o .:? "file_import_result"
      uploadUrl <- o .:? "upload_url"
      completeUrl <- o .:? "complete_url"
      pure FileUploadObject {..}
    _ -> fail "Expected object for FileUploadObject"

instance ToJSON FileUploadObject where
  toJSON FileUploadObject {..} =
    Aeson.object $
      [ "id" .= id,
        "object" .= object,
        "status" .= status,
        "created_time" .= posixToISO8601 createdTime,
        "last_edited_time" .= posixToISO8601 lastEditedTime,
        "created_by" .= createdBy,
        "in_trash" .= inTrash
      ]
        <> maybe [] (\f -> ["filename" .= f]) filename
        <> maybe [] (\ct -> ["content_type" .= ct]) contentType
        <> maybe [] (\cl -> ["content_length" .= cl]) contentLength
        <> maybe [] (\et -> ["expiry_time" .= posixToISO8601 et]) expiryTime
        <> maybe [] (\np -> ["number_of_parts" .= np]) numberOfParts
        <> maybe [] (\fir -> ["file_import_result" .= fir]) fileImportResult
        <> maybe [] (\u -> ["upload_url" .= u]) uploadUrl
        <> maybe [] (\u -> ["complete_url" .= u]) completeUrl

-- | Kind of creator of a file upload.
data FileUploadCreatorType
  = CreatorPerson
  | CreatorBot
  | CreatorAgent
  | -- | A creator type this library does not know yet; holds the raw string.
    UnknownCreatorType Text
  deriving stock (Eq, Generic, Show)

instance FromJSON FileUploadCreatorType where
  parseJSON = Aeson.withText "FileUploadCreatorType" $ \case
    "person" -> pure CreatorPerson
    "bot" -> pure CreatorBot
    "agent" -> pure CreatorAgent
    other -> pure (UnknownCreatorType other)

instance ToJSON FileUploadCreatorType where
  toJSON = \case
    CreatorPerson -> String "person"
    CreatorBot -> String "bot"
    CreatorAgent -> String "agent"
    UnknownCreatorType t -> String t

-- | Who created a file upload: @{"id": ..., "type": "person" | "bot" | "agent"}@.
data FileUploadCreator = FileUploadCreator
  { id :: UUID,
    type_ :: FileUploadCreatorType
  }
  deriving stock (Eq, Generic, Show)

instance FromJSON FileUploadCreator where
  parseJSON = genericParseJSON aesonOptions

instance ToJSON FileUploadCreator where
  toJSON = genericToJSON aesonOptions

-- | How the file content will be sent.
data FileUploadMode
  = -- | One request with the whole file (the default)
    SinglePart
  | -- | Several parts, then a complete call
    MultiPart
  | -- | Notion imports the file from a public HTTPS URL
    ExternalUrl
  deriving stock (Eq, Generic, Show)

instance ToJSON FileUploadMode where
  toJSON = \case
    SinglePart -> String "single_part"
    MultiPart -> String "multi_part"
    ExternalUrl -> String "external_url"

-- | Request body for creating a file upload
data CreateFileUpload = CreateFileUpload
  { mode :: Maybe FileUploadMode,
    filename :: Maybe Text,
    contentType :: Maybe Text,
    numberOfParts :: Maybe Natural,
    externalUrl :: Maybe Text
  }
  deriving stock (Generic, Show)

instance ToJSON CreateFileUpload where
  toJSON = genericToJSON aesonOptions

-- | Data for sending file content via multipart/form-data
data SendFileUpload = SendFileUpload
  { filePath :: FilePath,
    fileName :: Text,
    fileContentType :: Text,
    partNumber :: Maybe Natural
  }
  deriving stock (Show)

instance ToMultipart Tmp SendFileUpload where
  toMultipart SendFileUpload {..} =
    MultipartData
      { inputs = maybe [] (\n -> [Input "part_number" (pack (show n))]) partNumber,
        files = [FileData "file" fileName fileContentType filePath]
      }

-- ---------------------------------------------------------------------------
-- Smart constructors
-- ---------------------------------------------------------------------------

-- | Create a single-part file upload request with an optional filename.
mkSinglePartUpload :: Maybe Text -> CreateFileUpload
mkSinglePartUpload fname =
  CreateFileUpload
    { mode = Nothing,
      filename = fname,
      contentType = Nothing,
      numberOfParts = Nothing,
      externalUrl = Nothing
    }

-- | Create a multi-part file upload request.
mkMultiPartUpload ::
  -- | filename (required)
  Text ->
  -- | number of parts (required)
  Natural ->
  -- | content type (optional)
  Maybe Text ->
  CreateFileUpload
mkMultiPartUpload fname parts ct =
  CreateFileUpload
    { mode = Just MultiPart,
      filename = Just fname,
      contentType = ct,
      numberOfParts = Just parts,
      externalUrl = Nothing
    }

-- | Create an external URL file upload request.
mkExternalUrlUpload ::
  -- | external URL (required, must be HTTPS)
  Text ->
  -- | filename (optional)
  Maybe Text ->
  CreateFileUpload
mkExternalUrlUpload url fname =
  CreateFileUpload
    { mode = Just ExternalUrl,
      filename = fname,
      contentType = Nothing,
      numberOfParts = Nothing,
      externalUrl = Just url
    }

-- | Create a 'SendFileUpload' for a single-part upload.
mkSendFileUpload ::
  -- | path to the file on disk
  FilePath ->
  -- | filename
  Text ->
  -- | MIME content type (e.g., @"image\/png"@)
  Text ->
  SendFileUpload
mkSendFileUpload fp fname ct =
  SendFileUpload
    { filePath = fp,
      fileName = fname,
      fileContentType = ct,
      partNumber = Nothing
    }

-- | Servant API
type API =
  "file_uploads"
    :> ( ReqBody '[JSON] CreateFileUpload
           :> Post '[JSON] FileUploadObject
           :<|> Capture "file_upload_id" FileUploadID
           :> Get '[JSON] FileUploadObject
           :<|> Capture "file_upload_id" FileUploadID
           :> "send"
           :> MultipartForm Tmp SendFileUpload
           :> Post '[JSON] FileUploadObject
           :<|> Capture "file_upload_id" FileUploadID
           :> "complete"
           :> Post '[JSON] FileUploadObject
           :<|> QueryParam "status" FileUploadStatus
           :> QueryParam "start_cursor" Text
           :> QueryParam "page_size" Natural
           :> Get '[JSON] (ListOf FileUploadObject)
       )
