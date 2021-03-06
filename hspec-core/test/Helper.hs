module Helper (
  module Test.Hspec.Meta
, module Test.Hspec.Core.Compat
, module Test.QuickCheck
, module System.IO.Silently
, sleep
, timeout
, defaultParams
, noOpProgressCallback
, captureLines
, normalizeSummary

, ignoreExitCode
, ignoreUserInterrupt
, throwException

, withEnvironment
, inTempDirectory

, shouldUseArgs

, removeLocations
) where

import           Prelude ()
import           Test.Hspec.Core.Compat

import           Data.List
import           Data.Char
import           Control.Monad (guard)
import           System.Environment (withArgs, getEnvironment)
import           System.Exit
import qualified Control.Exception as E
import           Control.Exception (bracket)
import qualified System.Timeout as System
import           System.IO.Silently
import           System.SetEnv
import           System.Directory
import           System.IO.Temp

import           Test.Hspec.Meta
import           Test.QuickCheck hiding (Result(..))

import qualified Test.Hspec.Core.Spec as H
import qualified Test.Hspec.Core.Runner as H
import           Test.Hspec.Core.QuickCheckUtil (mkGen)
import           Test.Hspec.Core.Clock

throwException :: IO ()
throwException = E.throwIO (E.ErrorCall "foobar")

ignoreExitCode :: IO () -> IO ()
ignoreExitCode action = action `E.catch` \e -> let _ = e :: ExitCode in return ()

ignoreUserInterrupt :: IO () -> IO ()
ignoreUserInterrupt action = E.catchJust (guard . (== E.UserInterrupt)) action return

captureLines :: IO a -> IO [String]
captureLines = fmap lines . capture_

-- replace times in summary with zeroes
normalizeSummary :: [String] -> [String]
normalizeSummary = map f
  where
    f x | "Finished in " `isPrefixOf` x = map g x
        | otherwise = x
    g x | isNumber x = '0'
        | otherwise  = x

defaultParams :: H.Params
defaultParams = H.defaultParams {H.paramsQuickCheckArgs = stdArgs {replay = Just (mkGen 23, 0), maxSuccess = 1000}}

noOpProgressCallback :: H.ProgressCallback
noOpProgressCallback _ = return ()

timeout :: Seconds -> IO a -> IO (Maybe a)
timeout = System.timeout . toMicroseconds

shouldUseArgs :: [String] -> (Args -> Bool) -> Expectation
shouldUseArgs args p = do
  spy <- newIORef (H.paramsQuickCheckArgs defaultParams)
  let interceptArgs item = item {H.itemExample = \params action progressCallback -> writeIORef spy (H.paramsQuickCheckArgs params) >> H.itemExample item params action progressCallback}
      spec = H.mapSpecItem_ interceptArgs $
        H.it "foo" False
  (silence . ignoreExitCode . withArgs args . H.hspec) spec
  readIORef spy >>= (`shouldSatisfy` p)

removeLocations :: H.SpecWith a -> H.SpecWith a
removeLocations = H.mapSpecItem_ (\item -> item{H.itemLocation = Nothing})

withEnvironment :: [(String, String)] -> IO a -> IO a
withEnvironment environment action = bracket saveEnv restoreEnv $ const action
  where
    saveEnv :: IO [(String, String)]
    saveEnv = do
      env <- clearEnv
      forM_ environment $ uncurry setEnv
      return env
    restoreEnv :: [(String, String)] -> IO ()
    restoreEnv env = do
      _ <- clearEnv
      forM_ env $ uncurry setEnv
    clearEnv :: IO [(String, String)]
    clearEnv = do
      env <- getEnvironment
      forM_ env (unsetEnv . fst)
      return env

inTempDirectory :: IO a -> IO a
inTempDirectory action = withSystemTempDirectory "mockery" $ \path -> do
  bracket getCurrentDirectory setCurrentDirectory $ \_ -> do
    setCurrentDirectory path
    action
