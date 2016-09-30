module Utils where

import           Control.Concurrent              (threadDelay)
import qualified Control.Distributed.Backend.P2P as P2P
import           Control.Distributed.Process     (Process, ProcessId, exit, getSelfPid,
                                                  liftIO, match, receiveTimeout,
                                                  receiveWait, send, spawnLocal)
import           Data.IORef                      (IORef, modifyIORef, newIORef, readIORef,
                                                  writeIORef)
import           System.Console.ANSI             (Color (..), ColorIntensity (..),
                                                  ConsoleLayer (..), SGR (..), setSGR)

import           Types

newRef :: a -> Process (IORef a)
newRef = liftIO . newIORef

readRef :: IORef a -> Process a
readRef = liftIO . readIORef

writeRef :: IORef a -> a -> Process ()
writeRef = (liftIO .) . writeIORef

modifyRef :: IORef a -> (a -> a) -> Process ()
modifyRef = (liftIO .) . modifyIORef

getNodes :: NodeRole -> Process [ProcessId]
getNodes = P2P.getCapable . show

threadDelayMS :: Integer -> Process ()
threadDelayMS s = liftIO $ threadDelay $ fromInteger $ s * 1000

sayDebug :: String -> Process ()
sayDebug msg =
    liftIO $
    do setSGR [SetColor Foreground Dull Cyan]
       putStrLn msg
       setSGR [Reset]

sayBoring :: String -> Process ()
sayBoring msg =
    liftIO $
    do setSGR [SetColor Foreground Dull Green]
       putStrLn msg
       setSGR [Reset]

saySuccess :: String -> Process ()
saySuccess msg =
    liftIO $
    do setSGR [SetColor Foreground Vivid Green]
       putStrLn msg
       setSGR [Reset]

sayError :: String -> Process ()
sayError msg =
    liftIO $
    do setSGR [SetColor Foreground Vivid Red]
       putStrLn msg
       setSGR [Reset]

send' to msg = do
    self <- getSelfPid
    sayBoring $ show self ++ " -> " ++ show msg ++ " -> " ++ show to
    send to msg
