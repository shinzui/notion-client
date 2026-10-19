-- | Example-only POSIX persistence. The complete command must hold the lock.
-- Atomic replacement protects complete JSON; it cannot transact with Notion.
module FileTokenStore
  ( fileTokenStore,
    tokenFileExists,
    withTokenFileLock,
    removeTokenFile,
  )
where

import Control.Exception
import Control.Monad (unless, when)
import Data.Aeson qualified as A
import Data.Bits ((.&.))
import Data.ByteString.Lazy qualified as L
import Notion.V1.OAuth.Refresh
import System.Directory qualified as D
import System.FilePath
import System.IO
import System.IO.Error (isAlreadyExistsError, isDoesNotExistError)
import System.Posix.Directory qualified as PD
import System.Posix.Files qualified as F
import System.Posix.IO qualified as P
import System.Posix.Temp (mkstemp)
import System.Posix.Unistd (fileSynchronise)
import System.Posix.User (getEffectiveUserID)

fileTokenStore :: FilePath -> TokenStore
fileTokenStore path =
  TokenStore
    { loadTokens = do
        exists <- tokenFileExists path
        unless exists (ioError (userError "No saved credentials. Run login again"))
        bytes <- L.readFile path
        either (const (ioError (userError "Invalid token file. Run login again"))) pure (A.eitherDecode bytes),
      saveTokens = save path
    }

-- Check using lstat, including dangling symlinks. Do not follow token symlinks.
tokenFileExists :: FilePath -> IO Bool
tokenFileExists path = do
  checkDirectory (takeDirectory path)
  status <- optionalStatus path
  case status of
    Nothing -> pure False
    Just s -> do
      uid <- getEffectiveUserID
      unless
        (F.isRegularFile s && F.fileOwner s == uid && F.fileMode s .&. 0o077 == 0)
        (ioError (userError "Token path must be an owner-only regular file"))
      pure True

optionalStatus :: FilePath -> IO (Maybe F.FileStatus)
optionalStatus path =
  (Just <$> F.getSymbolicLinkStatus path) `catch` \(e :: IOException) ->
    if isDoesNotExistError e then pure Nothing else throwIO e

checkDirectory :: FilePath -> IO ()
checkDirectory path = do
  s <- F.getSymbolicLinkStatus path
  uid <- getEffectiveUserID
  unless
    (F.isDirectory s && F.fileOwner s == uid && F.fileMode s .&. 0o022 == 0)
    (ioError (userError "Token directory must be owned by you and not writable by group or others"))

save :: FilePath -> OAuthTokens -> IO ()
save path tokens = mask $ \restore -> do
  _ <- tokenFileExists path
  let directory = takeDirectory path
      cleanup (temporary, tempHandle) = do
        ignoreIO (hClose tempHandle)
        ignoreIO (D.removeFile temporary)
  -- mkstemp creates exclusively with mode 0600 before any secret bytes exist.
  bracketOnError (mkstemp (directory </> takeFileName path <> ".tmp-")) cleanup $ \(temporary, tempHandle) -> do
    restore (L.hPut tempHandle (A.encode tokens) >> hFlush tempHandle)
    fd <- P.handleToFd tempHandle
    bracket (pure fd) P.closeFd (restore . fileSynchronise)
    -- Recheck destination before replacement; the directory is not attacker-writable.
    _ <- tokenFileExists path
    D.renameFile temporary path
    synchronizeDirectory directory

synchronizeDirectory :: FilePath -> IO ()
synchronizeDirectory directory = bracket (P.openFd directory P.ReadOnly P.defaultFileFlags) P.closeFd fileSynchronise

-- | The lock covers load, remote exchange and durable save. A crash may leave
-- the lock directory behind; remove it only after checking no command is active.
withTokenFileLock :: FilePath -> IO a -> IO a
withTokenFileLock path = bracket acquire (const (D.removeDirectory lock)) . const
  where
    lock = path <> ".lock"
    acquire = do
      checkDirectory (takeDirectory path)
      PD.createDirectory lock 0o700 `catch` \(e :: IOException) ->
        if isAlreadyExistsError e then ioError (userError "OAuth command already locked; check for an active process before removing the lock directory") else throwIO e

removeTokenFile :: FilePath -> IO ()
removeTokenFile path = do
  exists <- tokenFileExists path
  when exists (D.removeFile path >> synchronizeDirectory (takeDirectory path))

ignoreIO :: IO () -> IO ()
ignoreIO action = action `catch` \(_ :: IOException) -> pure ()
