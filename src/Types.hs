module Types where

import qualified Data.Map as M

data NodeRole = Acceptor | Leader | Replica deriving (Eq)

instance Show NodeRole where
    show Acceptor = "dkvs.acceptor"
    show Leader   = "dkvs.leader"
    show Replica  = "dkvs.replica"

type Host = String

type Port = String

data Config = Config
    { nodesMap :: M.Map Int (NodeRole, Host, Port)
    , timeout  :: Int
    } deriving (Show)
