{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DeriveGeneric #-}

module Server where

import GHC.Generics
import Data.Binary (Binary)
import Data.Typeable (Typeable)
import Control.Monad (forM_, void, forever)
import Control.Concurrent (threadDelay)
import Control.Distributed.Process.Node (initRemoteTable)
import Control.Distributed.Process (Process, ProcessId, liftIO, send, getSelfPid
                                  , spawnLocal, match, receiveWait, register)

import qualified Data.Map as M
import qualified Control.Distributed.Backend.P2P as P2P

import Types
import Config

data Ping = Ping ProcessId deriving (Generic, Typeable)

instance Binary Ping

pingMessage :: Ping -> Process ()
pingMessage (Ping from) = putIO $ "ping from " ++ show from

putIO :: String -> Process ()
putIO = liftIO . putStrLn

threadDelayMS :: Int -> Process ()
threadDelayMS s = liftIO $ threadDelay $ s * (1000 :: Int)

getNodes :: NodeRole -> Process [ProcessId]
getNodes = P2P.getCapable . show

serverHandler :: Int -> Config -> Process ()
serverHandler nodeId Config{..} = do
    -- Start listener thread
    listenerPid <- spawnLocal $ forever $ do
        receiveWait [match pingMessage]

    let (myRole, _, _) = nodesMap M.! nodeId
    register (show myRole) listenerPid

    putIO "Waiting for nodes to appear"
    threadDelayMS 1000

    -- Spawn sender thread
    void $ spawnLocal $ forever $ do
        senderPid <- getSelfPid
        availableNodes <- getNodes Acceptor
        putIO $ "Available nodes: " ++ show availableNodes
        forM_ availableNodes $ \pid -> do
           send pid (Ping senderPid)
        threadDelayMS 1000

    forever (threadDelayMS 1000)

serve :: Int -> IO ()
serve nodeId = do
    -- Parser config file
    cfg@Config{..} <- readConfigFile
    let (_, myHost, myPort) = nodesMap M.! nodeId
    let f = \k (_, h, p) ids -> if k == nodeId then ids else P2P.makeNodeId (h++":"++p) : ids
    let otherNodesIds = M.foldrWithKey f [] nodesMap

    -- Start P2P node
    P2P.bootstrap myHost myPort otherNodesIds initRemoteTable (serverHandler nodeId cfg)
