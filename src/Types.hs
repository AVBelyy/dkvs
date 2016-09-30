{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE DuplicateRecordFields #-}

module Types where

import           Control.Distributed.Process (ProcessId)
import           Data.Binary                 (Binary)
import qualified Data.Map                    as M
import           Data.Typeable               (Typeable)
import           GHC.Generics

data NodeRole
    = Acceptor
    | Leader
    | Replica
    | PingNode
    deriving (Eq)

instance Show NodeRole where
    show Acceptor = "dkvs.acceptor"
    show Leader   = "dkvs.leader"
    show Replica  = "dkvs.replica"
    show PingNode = "dkvs.ping"

type Host = String

type Port = String

data Config = Config
    { nodesMap :: M.Map Integer (NodeRole, Host, Port)
    , timeout  :: Integer
    } deriving (Show)

data PingMessage = PingMessage
    { to :: ProcessId
    } deriving (Generic, Typeable, Show)

data PongMessage = PongMessage
    { from :: ProcessId
    } deriving (Generic, Typeable, Show)

instance Binary PingMessage

instance Binary PongMessage
