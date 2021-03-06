-- | Note: this module is re-exported as a whole from "Test.Tasty.Runners"
module Test.Tasty.Runners.Utils where

import Control.Exception
import Control.Applicative
import Data.Typeable (Typeable)
import Prelude  -- Silence AMP import warnings
import Text.Printf
import Foreign.C (CInt)

-- We install handlers only on UNIX (obviously) and on GHC >= 7.6.
-- GHC 7.4 lacks mkWeakThreadId (see #181), and this is not important
-- enough to look for an alternative implementation, so we just disable it
-- there.
#define INSTALL_HANDLERS defined __UNIX__ && MIN_VERSION_base(4,6,0)

#if INSTALL_HANDLERS
import Control.Concurrent (mkWeakThreadId, myThreadId)
import Control.Exception (Exception(..), throwTo)
import Control.Monad (forM_)
import System.Posix.Signals
import System.Mem.Weak (deRefWeak)
#endif

-- | Catch possible exceptions that may arise when evaluating a string.
-- For normal (total) strings, this is a no-op.
--
-- This function should be used to display messages generated by the test
-- suite (such as test result descriptions).
--
-- See e.g. <https://github.com/feuerbach/tasty/issues/25>
formatMessage :: String -> IO String
formatMessage = go 3
  where
    -- to avoid infinite recursion, we introduce the recursion limit
    go :: Int -> String -> IO String
    go 0        _ = return "exceptions keep throwing other exceptions!"
    go recLimit msg = do
      mbStr <- try $ evaluate $ forceElements msg
      case mbStr of
        Right () -> return msg
        Left e' -> printf "message threw an exception: %s" <$> go (recLimit-1) (show (e' :: SomeException))

-- https://ro-che.info/articles/2015-05-28-force-list
forceElements :: [a] -> ()
forceElements = foldr seq ()

-- from https://ro-che.info/articles/2014-07-30-bracket
-- | Install signal handlers so that e.g. the cursor is restored if the test
-- suite is killed by SIGTERM. Upon a signal, a 'SignalException' will be
-- thrown to the thread that has executed this action.
--
-- This function is called automatically from the @defaultMain*@ family of
-- functions. You only need to call it explicitly if you call
-- 'tryIngredients' yourself.
--
-- This function does nothing on non-UNIX systems or when compiled with GHC
-- older than 7.6.
installSignalHandlers :: IO ()
installSignalHandlers = do
#if INSTALL_HANDLERS
  main_thread_id <- myThreadId
  weak_tid <- mkWeakThreadId main_thread_id
  forM_ [ sigABRT, sigBUS, sigFPE, sigHUP, sigILL, sigQUIT, sigSEGV,
          sigSYS, sigTERM, sigUSR1, sigUSR2, sigXCPU, sigXFSZ ] $ \sig ->
    installHandler sig (Catch $ send_exception weak_tid sig) Nothing
  where
    send_exception weak_tid sig = do
      m <- deRefWeak weak_tid
      case m of
        Nothing  -> return ()
        Just tid -> throwTo tid (toException $ SignalException sig)
#else
  return ()
#endif

-- | This exception is thrown when the program receives a signal, assuming
-- 'installSignalHandlers' was called.
--
-- The 'CInt' field contains the signal number, as in
-- 'System.Posix.Signals.Signal'. We don't use that type synonym, however,
-- because it's not available on non-UNIXes.
newtype SignalException = SignalException CInt
  deriving (Show, Typeable)
instance Exception SignalException
