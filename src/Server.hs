{-# LANGUAGE RecordWildCards #-}

module Server where

import           Control.Distributed.Process      (Process, ProcessId, getSelfPid, liftIO,
                                                   match, receiveWait, reconnect,
                                                   register, send, spawnLocal)
import           Control.Distributed.Process.Node (initRemoteTable)
import           Control.Monad                    (forM_, forever, void, when)
import           Data.Binary                      (Binary)
import           Data.IORef                       (atomicModifyIORef', atomicWriteIORef)
import           Data.Typeable                    (Typeable)
import           GHC.Generics

import qualified Control.Distributed.Backend.P2P  as P2P
import qualified Data.Map                         as M
import qualified Data.Set                         as S

import           Config
import           Paxos
import           Types
import           Utils

serverHandler :: Integer -> Config -> Process ()
serverHandler nodeId Config {..}
                     -- Wait to discover peers
 = do
    threadDelayMS 1000
    -- Start worker
    let (myRole, _, _) = nodesMap M.! nodeId
    workerPid <-
        spawnLocal $
        case myRole of
            Acceptor -> acceptor
            Leader   -> leader nodeId
            Replica  -> replica nodeId
    -- Register worker
    register (show myRole) workerPid
    -- Start ping service
    pendingSet <- newRef S.empty
    let pingMessage pingPid' PingMessage {..} = send to $ PongMessage pingPid'
    pingPid <-
        spawnLocal $
        getSelfPid >>= \self -> forever $ receiveWait [match $ pingMessage self]
    register (show PingNode) pingPid
    let pongMessage PongMessage {..} =
            liftIO $ atomicModifyIORef' pendingSet $ \s -> (S.delete from s, ())
    pongPid <- spawnLocal $ forever $ receiveWait [match pongMessage]
    void $
        spawnLocal $
        forever $
        do pendingSet' <- readRef pendingSet
           when (S.size pendingSet' > 0) $
               sayError $
               "Nodes not responding cnt: " ++ show (S.size pendingSet')
           forM_ pendingSet' reconnect
           allOtherNodes <- filter (/= pingPid) <$> getNodes PingNode
           liftIO $ atomicWriteIORef pendingSet (S.fromList allOtherNodes)
           forM_ allOtherNodes $ flip send $ PingMessage pongPid
           threadDelayMS timeout
    -- Execute indefinitely
    forever $ threadDelayMS 100

serve :: Integer -> IO ()
serve nodeId
      -- Parser config file
 = do
    cfg@Config {..} <- readConfigFile
    let (_, myHost, myPort) = nodesMap M.! nodeId
    let f k (_, h, p) ids =
            if k == nodeId
                then ids
                else P2P.makeNodeId (h ++ ":" ++ p) : ids
    let otherNodesIds = M.foldrWithKey f [] nodesMap
    -- Start P2P node
    P2P.bootstrap
        myHost
        myPort
        otherNodesIds
        initRemoteTable
        (serverHandler nodeId cfg)
