-- | Error handling for Notion API
--
-- A failed request surfaces as one of these exceptions:
--
-- * 'NotionError': Notion answered with its JSON error envelope. 'code' is a
--   typed 'APIErrorCode'.
-- * 'UnknownHTTPResponseError': a non-2xx response whose body is not a Notion
--   error, for example an HTML page from Notion's edge proxy.
-- * 'RequestTimeoutError': connecting or waiting for response headers timed out.
-- * 'InvalidPathParameterError': the request path contained @..@ and was not sent.
--
-- Response decoding failures and other connection problems remain servant's
-- 'Client.ClientError'.
module Notion.V1.Error
  ( -- * Error codes
    APIErrorCode (..),
    apiErrorCodeText,
    parseAPIErrorCode,

    -- * Error types
    NotionError (..),
    HttpErrorResponse (..),
    UnknownHTTPResponseError (..),
    unknownResponseMessage,
    RequestTimeoutError (..),
    InvalidPathParameterError (..),

    -- * Building errors
    buildRequestError,
    notionErrorFromResponse,
    fromClientError,
    parseNotionError,
    lookupHeader,
  )
where

import Control.Exception (Exception (..), SomeException, toException)
import Data.Aeson ((.!=), (.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Foldable (toList)
import Data.Maybe (catMaybes, fromMaybe)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Network.HTTP.Client qualified as HTTP
import Network.HTTP.Types (HeaderName, ResponseHeaders, Status (..))
import Notion.Prelude
import Servant.Client qualified as Client

-- | The error codes Notion documents, plus a fallback for new ones.
data APIErrorCode
  = Unauthorized
  | RestrictedResource
  | ObjectNotFound
  | RateLimited
  | InvalidJSON
  | InvalidRequestURL
  | InvalidRequest
  | InvalidBeta
  | ValidationError
  | ConflictError
  | InternalServerError
  | ServiceOverload
  | ServiceUnavailable
  | GatewayTimeout
  | -- | A code this library does not know yet, carried verbatim.
    UnknownErrorCode Text
  deriving stock (Eq, Show)

knownErrorCodes :: [(APIErrorCode, Text)]
knownErrorCodes =
  [ (Unauthorized, "unauthorized"),
    (RestrictedResource, "restricted_resource"),
    (ObjectNotFound, "object_not_found"),
    (RateLimited, "rate_limited"),
    (InvalidJSON, "invalid_json"),
    (InvalidRequestURL, "invalid_request_url"),
    (InvalidRequest, "invalid_request"),
    (InvalidBeta, "invalid_beta"),
    (ValidationError, "validation_error"),
    (ConflictError, "conflict_error"),
    (InternalServerError, "internal_server_error"),
    (ServiceOverload, "service_overload"),
    (ServiceUnavailable, "service_unavailable"),
    (GatewayTimeout, "gateway_timeout")
  ]

-- | The wire string of a code, for example @"object_not_found"@.
apiErrorCodeText :: APIErrorCode -> Text
apiErrorCodeText = \case
  UnknownErrorCode t -> t
  c -> fromMaybe "" (lookup c knownErrorCodes)

-- | Parse a wire string; unrecognised strings become 'UnknownErrorCode'.
parseAPIErrorCode :: Text -> APIErrorCode
parseAPIErrorCode t =
  maybe (UnknownErrorCode t) fst (lookupByText t)
  where
    lookupByText x = case filter ((== x) . snd) knownErrorCodes of
      pair : _ -> Just pair
      [] -> Nothing

-- | Lets string literals such as @"validation_error"@ stand for codes.
instance IsString APIErrorCode where
  fromString = parseAPIErrorCode . Text.pack

instance FromJSON APIErrorCode where
  parseJSON = Aeson.withText "APIErrorCode" (pure . parseAPIErrorCode)

instance ToJSON APIErrorCode where
  toJSON = String . apiErrorCodeText

-- | Metadata of the HTTP response an error came from.
data HttpErrorResponse = HttpErrorResponse
  { httpStatus :: Int,
    -- | Response headers; names compare case-insensitively.
    errorHeaders :: ResponseHeaders,
    -- | The @x-notion-request-id@ header.
    notionRequestId :: Maybe Text,
    -- | The @cf-ray@ header (Cloudflare Ray ID).
    rayId :: Maybe Text,
    -- | The raw response body.
    errorBody :: ByteString
  }
  deriving stock (Eq, Show)

-- | A well-formed Notion API error response.
data NotionError = NotionError
  { -- | Always @"error"@.
    object :: Text,
    -- | The body's @status@, or else the HTTP status.
    status :: Natural,
    code :: APIErrorCode,
    message :: Text,
    -- | The body's @request_id@, or else the @x-notion-request-id@ header.
    requestId :: Maybe Text,
    -- | The body's @additional_data@.
    additionalData :: Maybe Value,
    -- | Legacy field, kept for compatibility.
    details :: Maybe Value,
    -- | 'Nothing' when decoded from bare JSON rather than an HTTP response.
    response :: Maybe HttpErrorResponse
  }
  deriving stock (Eq, Show)

instance Exception NotionError

instance FromJSON NotionError where
  parseJSON = Aeson.withObject "NotionError" $ \o -> do
    object <- o .:? "object" .!= "error"
    status <- o .:? "status" .!= 0
    code <- o .: "code"
    message <- o .: "message"
    requestId <- o .:? "request_id"
    additionalData <- o .:? "additional_data"
    details <- o .:? "details"
    pure NotionError {response = Nothing, ..}

instance ToJSON NotionError where
  toJSON NotionError {..} =
    Aeson.object $
      [ "object" .= object,
        "status" .= status,
        "code" .= code,
        "message" .= message
      ]
        <> catMaybes
          [ ("request_id" .=) <$> requestId,
            ("additional_data" .=) <$> additionalData,
            ("details" .=) <$> details
          ]

-- | A non-2xx response whose body is not a Notion error envelope.
newtype UnknownHTTPResponseError = UnknownHTTPResponseError {unknownResponse :: HttpErrorResponse}
  deriving stock (Eq, Show)

instance Exception UnknownHTTPResponseError where
  displayException = Text.unpack . unknownResponseMessage

-- | Human-readable description, matching the JS SDK. When the response came
-- from Notion's edge proxy (a @cf-ray@ header but no request ID), it explains
-- that and includes the Ray ID for support.
unknownResponseMessage :: UnknownHTTPResponseError -> Text
unknownResponseMessage (UnknownHTTPResponseError HttpErrorResponse {..}) =
  case rayId of
    Just ray
      | Nothing <- notionRequestId ->
          base
            <> ". The response was returned by Notion's edge proxy before reaching the Notion API"
            <> maybe "" (\ct -> " (content-type: " <> ct <> ")") (lookupHeader "content-type" errorHeaders)
            <> "."
            <> (if httpStatus == 403 then " This may mean the request was blocked by a network security rule." else "")
            <> " Cloudflare Ray ID: "
            <> ray
            <> ". Include this ID when contacting Notion support."
    _ -> base
  where
    base = "Request to Notion API failed with status: " <> Text.pack (show httpStatus)

-- | Connecting to Notion or waiting for its response headers timed out.
data RequestTimeoutError = RequestTimeoutError
  deriving stock (Eq, Show)

instance Exception RequestTimeoutError where
  displayException _ = "Request to Notion API has timed out"

-- | The request path contained a path traversal sequence; nothing was sent.
newtype InvalidPathParameterError = InvalidPathParameterError {invalidPath :: Text}
  deriving stock (Eq, Show)

instance Exception InvalidPathParameterError where
  displayException (InvalidPathParameterError p) =
    "Request path \"" <> Text.unpack p <> "\" contains path traversal sequence \"..\""

-- | First value of a header, decoded leniently as UTF-8.
lookupHeader :: HeaderName -> ResponseHeaders -> Maybe Text
lookupHeader name hs = Text.decodeUtf8Lenient <$> lookup name hs

-- | Classify a non-2xx response from its status, headers and body.
buildRequestError :: Int -> ResponseHeaders -> ByteString -> Either UnknownHTTPResponseError NotionError
buildRequestError httpStatus errorHeaders errorBody =
  case Aeson.decode errorBody of
    Just err@NotionError {status, requestId} ->
      Right
        err
          { status = if status == 0 then fromIntegral httpStatus else status,
            requestId = maybe notionRequestId Just requestId,
            response = Just meta
          }
    Nothing -> Left (UnknownHTTPResponseError meta)
  where
    notionRequestId = lookupHeader "x-notion-request-id" errorHeaders
    rayId = lookupHeader "cf-ray" errorHeaders
    meta = HttpErrorResponse {..}

-- | Typed exception for a non-2xx response: a 'NotionError' when the body is a
-- Notion error envelope, else an 'UnknownHTTPResponseError'. Throwing the result
-- with 'Control.Exception.throwIO' can be caught as either type.
notionErrorFromResponse :: Status -> ResponseHeaders -> ByteString -> SomeException
notionErrorFromResponse s hs b = either toException toException (buildRequestError (statusCode s) hs b)

-- | Convert a servant client error into the exception this library throws.
fromClientError :: Client.ClientError -> SomeException
fromClientError = \case
  Client.FailureResponse _ resp ->
    notionErrorFromResponse
      (Client.responseStatusCode resp)
      (toList (Client.responseHeaders resp))
      (Client.responseBody resp)
  err@(Client.ConnectionError e)
    | Just (HTTP.HttpExceptionRequest _ content) <- fromException e,
      isTimeout content ->
        toException RequestTimeoutError
    | otherwise -> toException err
  err -> toException err
  where
    isTimeout = \case
      HTTP.ResponseTimeout -> True
      HTTP.ConnectionTimeout -> True
      _ -> False

-- | Try to parse a 'NotionError' from a Servant 'Client.ClientError'.
--
-- Returns 'Just' if the error is a 'Client.FailureResponse' whose body is a
-- Notion error envelope, 'Nothing' otherwise.
parseNotionError :: Client.ClientError -> Maybe NotionError
parseNotionError = \case
  Client.FailureResponse _req resp ->
    either (const Nothing) Just $
      buildRequestError
        (statusCode (Client.responseStatusCode resp))
        (toList (Client.responseHeaders resp))
        (Client.responseBody resp)
  _ -> Nothing
