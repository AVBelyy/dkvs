{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE NoImplicitPrelude     #-}
{-# LANGUAGE RecordWildCards       #-}
{-# LANGUAGE ScopedTypeVariables   #-}

module Paxos where

import           Control.Concurrent              (threadDelay)
import           Control.Distributed.Process     (Process, ProcessId, exit, getSelfPid,
                                                  liftIO, match, receiveTimeout,
                                                  receiveWait, send, spawnLocal)
import           Control.Exception               (SomeException (..), catch)
import           Control.Monad                   (forM_, forever, unless, void, when)
import           Control.Monad.Loops             (whileM_)
import           Data.Binary                     (Binary, decodeFile, encodeFile)
import           Data.Binary.Get                 (ByteOffset)
import           Data.IORef                      (IORef, modifyIORef, newIORef, readIORef,
                                                  writeIORef)
import           Data.Maybe                      (fromJust, isNothing)
import           Prelude                         hiding (round)

import qualified Control.Distributed.Backend.P2P as P2P
import qualified Data.Dequeue                    as Q
import qualified Data.Map                        as M
import qualified Data.Set                        as S

import           PaxosTypes
import           Types
import           Utils

-- Global constants
window = 5

-- Acceptor
acceptor :: Process ()
acceptor = do
    self <- getSelfPid
    maxBN <- newRef (BallotNumber 0 0)
    acc <- newRef S.empty
    sayDebug $ "Started acceptor on " ++ show self
    forever $
        receiveWait
            [ match (p1aMessage self maxBN acc)
            , match (p2aMessage self maxBN acc)
            ]
  where
    p1aMessage self maxBN acc P1aMessage {..} = do
        modifyRef maxBN (max ballotNumber)
        maxBN' <- readRef maxBN
        acc' <- readRef acc
        send' from (P1bMessage self maxBN' acc')
    p2aMessage self maxBN acc P2aMessage {..} = do
        maxBN' <- readRef maxBN
        when (maxBN' == ballotNumber) $
            modifyRef acc (S.insert (PValue ballotNumber slotNumber command))
        send' from (P2bMessage self maxBN')

-- Leader
leader :: Integer -> Process ()
leader leaderId = do
    let bn' = BallotNumber 0 leaderId
    self <- getSelfPid
    bn <- newRef bn'
    active <- newRef False
    props <- newRef M.empty
    sayDebug $ "Started leader on " ++ show self
    void $ spawnLocal $ scout self bn'
    forever $
        receiveWait
            [ match (proposeMessage self props active bn)
            , match (adoptedMessage self props active bn)
            , match (preemptedMessage self leaderId active bn)
            ]
  where
    proposeMessage leaderPid props active bn ProposeMessage {..} = do
        props' <- readRef props
        active' <- readRef active
        bn' <- readRef bn
        when (slotNumber `M.notMember` props') $
            do modifyRef props (M.insert slotNumber command)
               when active' $
                   void $ spawnLocal $ commander leaderPid bn' slotNumber command
    adoptedMessage leaderPid props active bn AdoptedMessage {..} = do
        props' <- readRef props
        bn' <- readRef bn
        when (bn' == ballotNumber) $
            do max <- newRef M.empty
               forM_ accepted $
                   \PValue {..} -> do
                       max' <- readRef max
                       let bn'' = slotNumber `M.lookup` max'
                       when (isNothing bn'' || bn'' < Just ballotNumber) $
                           do modifyRef max $ M.insert slotNumber ballotNumber
                              modifyRef props $ M.insert slotNumber command
               forM_ (M.assocs props') $
                   \(slotNumber, command) ->
                        void $ spawnLocal $ commander leaderPid bn' slotNumber command
               writeRef active True
    preemptedMessage leaderPid leaderId active bn PreemptedMessage {..} = do
        bn' <- readRef bn
        when (ballotNumber > bn') $
            do let bn'' = BallotNumber (1 + round ballotNumber) leaderId
               writeRef bn bn''
               void $ spawnLocal $ scout leaderPid bn''

-- Replica
replica :: Integer -> Process ()
replica nodeId
        -- default values
 = do
    self <- getSelfPid
    storage <- newRef M.empty
    slotIn <- newRef (0 :: Integer)
    slotOut <- newRef (0 :: Integer)
    props <- newRef M.empty
    decs <- newRef M.empty
    reqs <- newRef (Q.empty :: Q.BankersDequeue Command)
    -- try to recover from disk state
    stateOrFail <- readStateFromDisk
    case stateOrFail of
        Just s' -> applyState s' storage slotIn slotOut props decs reqs
        Nothing -> return ()
    -- request state from other replicas
    rs <- getNodes Replica
    forM_ rs $
        \rep -> unless (self == rep) $ send' rep (RequestReplicaState self)
    sayDebug $ "Started replica on " ++ show self
    forever $
        receiveWait
            [ match (requestReplicaState reqs props decs slotIn slotOut storage)
            , match
                  (responseReplicaState reqs props decs slotIn slotOut storage)
            , match (requestMessage reqs props decs slotIn slotOut storage)
            , match (decisionMessage reqs props decs slotIn slotOut storage)
            ]
  where
    requestMessage reqs props decs slotIn slotOut storage RequestMessage {..} = do
        let flag = isLocal (op command)
        when flag $
            do ans <- mkReply storage (op command)
               send' (clientId command) $
                   ResponseMessage $
                   command
                   { op = Reply ans
                   }
        unless flag $
            do modifyRef reqs (`Q.pushFront` command)
               propose reqs props decs slotIn slotOut
    decisionMessage reqs props decs slotIn slotOut storage DecisionMessage {..} = do
        modifyRef decs (M.insert slotNumber command)
        whileM_ ((`fmap` readRef decs) . M.member =<< readRef slotOut) $
            do slotOut' <- readRef slotOut
               props' <- readRef props
               decs' <- readRef decs
               let prop' = fromJust $ slotOut' `M.lookup` props'
               let dec' = fromJust $ slotOut' `M.lookup` decs'
               when (slotOut' `M.member` props') $
                   do when (prop' /= dec') $
                          modifyRef reqs (`Q.pushFront` prop')
                      writeRef props (slotOut' `M.delete` props')
               let flag =
                       M.foldrWithKey
                           (\k v -> (||) (k >= 1 && k < slotOut' && v == dec'))
                           False
                           decs'
               unless flag $
               -- perform actual command
                   do ans <- mkReply storage (op dec')
                      -- safe state on disk
                      state' <- saveState storage slotIn slotOut props decs reqs
                      saveStateOnDisk state'
                      -- send response to client
                      send' (clientId dec') $
                          ResponseMessage $
                          dec'
                          { op = Reply ans
                          }
               modifyRef slotOut (+ 1)
        propose reqs props decs slotIn slotOut
    requestReplicaState reqs props decs slotIn slotOut storage RequestReplicaState {..} = do
        state' <- saveState storage slotIn slotOut props decs reqs
        send' from (ResponseReplicaState state')
    responseReplicaState reqs props decs slotIn slotOut storage ResponseReplicaState {..} =
        applyState state storage slotIn slotOut props decs reqs
    propose reqs props decs slotIn slotOut =
        whileM_
            (do slotIn' <- readRef slotIn
                slotOut' <- readRef slotOut
                reqs' <- readRef reqs
                return $ not (Q.null reqs') && slotIn' < slotOut' + window) $
        do slotIn' <- readRef slotIn
           decs' <- readRef decs
           when (slotIn' `M.notMember` decs') $
               do reqs' <- readRef reqs
                  let (cmd, reqs'') = fromJust $ Q.popBack reqs'
                  writeRef reqs reqs''
                  modifyRef props (M.insert slotIn' cmd)
                  ls <- getNodes Leader
                  forM_ ls $
                      \leader -> send' leader (ProposeMessage slotIn' cmd)
           modifyRef slotIn (+ 1)
    mkReply storage (Get k) =
        readRef storage >>=
        \s' ->
             case k `M.lookup` s' of
                 Nothing -> return (Left "not found")
                 Just v  -> return (Right v)
    mkReply storage (Set k v) = do
        modifyRef storage (M.insert k v)
        return (Right "stored")
    mkReply storage (Delete k) =
        readRef storage >>=
        \s' ->
             if k `M.member` s'
                 then modifyRef storage (M.delete k) >> return (Right "deleted")
                 else return (Left "not found")
    mkReply _ Ping = return (Right "pong")
    isLocal (Get _) = True
    isLocal Ping    = True
    isLocal _       = False
    filename = "dkvs_" ++ show nodeId ++ ".log"
    saveStateOnDisk state' = liftIO $ encodeFile filename state'
    readStateFromDisk =
        (liftIO $ go `catch` fallback) :: Process (Maybe ReplicaState)
      where
        go = Just <$> decodeFile filename
        fallback (e :: SomeException) = return Nothing
    saveState storage slotIn slotOut props decs reqs = do
        storage' <- readRef storage
        slotIn' <- readRef slotIn
        slotOut' <- readRef slotOut
        props' <- readRef props
        decs' <- readRef decs
        reqs' <- readRef reqs >>= \r -> return $ Q.takeFront (length r) r
        return $ ReplicaState storage' slotIn' slotOut' props' decs' reqs'
    applyState ReplicaState {..} _storage _slotIn _slotOut _props _decs _reqs = do
        writeRef _storage storage
        writeRef _slotIn slotIn
        writeRef _slotOut slotOut
        writeRef _props proposals
        writeRef _decs decisions
        writeRef _reqs $ Q.fromList requests

-- Scout
scout :: ProcessId -> BallotNumber -> Process ()
scout leaderPid bn = do
    self <- getSelfPid
    as <- getNodes Acceptor
    pvalues <- newRef S.empty
    waitfor <- newRef (S.fromList as)
    sayDebug $ "Started scout on " ++ show self
    forM_ as $ \acc -> send' acc (P1aMessage self bn)
    forever $
        receiveWait [match (p1bMessage self leaderPid bn as pvalues waitfor)]
  where
    p1bMessage self leaderPid bn as pvalues waitfor P1bMessage {..} = do
        waitfor' <- readRef waitfor
        let cond = ballotNumber == bn && from `S.member` waitfor'
        when cond $
            do modifyRef pvalues (S.union accepted)
               modifyRef waitfor (S.delete from)
               waitfor'' <- readRef waitfor
               when (S.size waitfor'' < (1 + length as) `div` 2) $
                   do pvalues' <- readRef pvalues
                      send' leaderPid (AdoptedMessage bn pvalues')
                      exit self "adopted"
        unless cond $
            do send' leaderPid (PreemptedMessage ballotNumber)
               exit self "preempted"

-- Commander
commander :: ProcessId -> BallotNumber -> Integer -> Command -> Process ()
commander leaderPid bn slotNumber command = do
    self <- getSelfPid
    as <- getNodes Acceptor
    rs <- getNodes Replica
    waitfor <- newRef (S.fromList as)
    sayDebug $ "Started commander on " ++ show self
    forM_ as $ \acc -> send' acc (P2aMessage self bn slotNumber command)
    forever $
        receiveWait
            [ match
                  (p2bMessage self leaderPid bn slotNumber command as rs waitfor)
            ]
  where
    p2bMessage self leaderPid bn slotNumber command as rs waitfor P2bMessage {..} = do
        waitfor' <- readRef waitfor
        let cond = ballotNumber == bn && from `S.member` waitfor'
        when cond $
            do modifyRef waitfor (S.delete from)
               waitfor'' <- readRef waitfor
               when (S.size waitfor'' < (1 + length as) `div` 2) $
                   do forM_ rs $
                          \rep ->
                               send'
                                   rep
                                   (DecisionMessage self slotNumber command)
                      exit self "adopted"
        unless cond $
            do send' leaderPid (PreemptedMessage ballotNumber)
               exit self "preempted"
