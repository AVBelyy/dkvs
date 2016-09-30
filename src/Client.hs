{-# LANGUAGE RecordWildCards #-}

module Client where

import           Control.Distributed.Process      (NodeId, Process, ProcessId, exit,
                                                   getSelfPid, liftIO, match,
                                                   processNodeId, receiveWait, register,
                                                   send, spawnLocal)
import           Control.Distributed.Process.Node (initRemoteTable)
import           Control.Monad                    (forM_, forever, void)
import           Control.Monad.Loops              (whileM_)
import           Data.Binary                      (Binary)
import           Data.IORef                       (IORef)
import           Data.Typeable                    (Typeable)
import           GHC.Generics

import qualified Control.Distributed.Backend.P2P  as P2P
import qualified Data.Map                         as M

import           Config
import           Paxos
import           PaxosTypes
import           Types
import           Utils

responseMessage :: IORef Bool -> ResponseMessage -> Process ()
responseMessage wait (ResponseMessage (Command _ _ (Reply reply))) = do
    case reply of
        Left err  -> sayError err
        Right msg -> saySuccess msg
    writeRef wait False

clientHandler :: Config -> Operation -> NodeId -> Process ()
clientHandler Config {..} op nodeId = do
    wait <- newRef True
    self <- getSelfPid
    -- Wait to discover peers
    threadDelayMS 1000
    replicas <- P2P.getCapable (show Replica)
    listenerPid <- spawnLocal $ receiveWait [match (responseMessage wait)]
    sayDebug $ "Discovered replicas: " ++ show replicas
    case filter (\pid -> nodeId == processNodeId pid) replicas of
        [] -> do
            sayError $ "invalid or offline replica (" ++ show nodeId ++ ")"
            exit self ()
        rep:_ -> do
            let requestId = 0 -- we don't need to distunguish requests
            let command = RequestMessage (Command listenerPid requestId op)
            send rep command
            -- Serve forever
            whileM_ (readRef wait) (threadDelayMS 100)

client :: Integer -> Port -> Operation -> IO ()
client nodeNum myPort op
                      -- Parser config file
 = do
    cfg@Config {..} <- readConfigFile
    let f (_, h, p) = P2P.makeNodeId (h ++ ":" ++ p)
    let nodeId = f (nodesMap M.! nodeNum)
    let otherNodesIds = M.foldr ((:) . f) [] nodesMap
    -- Start P2P node
    P2P.bootstrap
        "localhost"
        myPort
        otherNodesIds
        initRemoteTable
        (clientHandler cfg op nodeId)
