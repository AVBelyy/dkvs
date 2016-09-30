{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE DuplicateRecordFields #-}

module PaxosTypes where

import           Control.Distributed.Process (ProcessId)
import           Data.Binary                 (Binary)
import qualified Data.Dequeue                as Q
import qualified Data.Map                    as M
import qualified Data.Set                    as S
import           Data.Typeable               (Typeable)
import           GHC.Generics

type Error = String

-- Messages
data Operation
    = Get String
    | Set String
          String
    | Delete String
    | Ping
    | Reply (Either Error String)
    deriving (Generic, Typeable, Eq, Ord, Show)

data BallotNumber = BallotNumber
    { round    :: Integer
    , leaderId :: Integer
    } deriving (Generic, Typeable, Eq, Ord, Show)

data Command = Command
    { clientId  :: ProcessId
    , requestId :: Integer
    , op        :: Operation
    } deriving (Generic, Typeable, Eq, Ord, Show)

data PValue = PValue
    { ballotNumber :: BallotNumber
    , slotNumber   :: Integer
    , command      :: Command
    } deriving (Generic, Typeable, Eq, Ord, Show)

data P1aMessage = P1aMessage
    { from         :: ProcessId
    , ballotNumber :: BallotNumber
    } deriving (Generic, Typeable, Show)

data P1bMessage = P1bMessage
    { from         :: ProcessId
    , ballotNumber :: BallotNumber
    , accepted     :: S.Set PValue
    } deriving (Generic, Typeable, Show)

data P2aMessage = P2aMessage
    { from         :: ProcessId
    , ballotNumber :: BallotNumber
    , slotNumber   :: Integer
    , command      :: Command
    } deriving (Generic, Typeable, Show)

data P2bMessage = P2bMessage
    { from         :: ProcessId
    , ballotNumber :: BallotNumber
    } deriving (Generic, Typeable, Show)

data PreemptedMessage = PreemptedMessage
    { ballotNumber :: BallotNumber
    } deriving (Generic, Typeable, Show)

data AdoptedMessage = AdoptedMessage
    { ballotNumber :: BallotNumber
    , accepted     :: S.Set PValue
    } deriving (Generic, Typeable, Show)

data DecisionMessage = DecisionMessage
    { from       :: ProcessId
    , slotNumber :: Integer
    , command    :: Command
    } deriving (Generic, Typeable, Show)

data RequestMessage = RequestMessage
    { command :: Command
    } deriving (Generic, Typeable, Show)

data ProposeMessage = ProposeMessage
    { slotNumber :: Integer
    , command    :: Command
    } deriving (Generic, Typeable, Show)

data ResponseMessage = ResponseMessage
    { command :: Command
    } deriving (Generic, Typeable, Show)

instance Binary Operation

instance Binary BallotNumber

instance Binary Command

instance Binary PValue

instance Binary P1aMessage

instance Binary P1bMessage

instance Binary P2aMessage

instance Binary P2bMessage

instance Binary PreemptedMessage

instance Binary AdoptedMessage

instance Binary DecisionMessage

instance Binary RequestMessage

instance Binary ProposeMessage

instance Binary ResponseMessage

-- State
data ReplicaState = ReplicaState
    { storage   :: M.Map String String
    , slotIn    :: Integer
    , slotOut   :: Integer
    , proposals :: M.Map Integer Command
    , decisions :: M.Map Integer Command
    , requests  :: [Command]
    } deriving (Generic, Typeable, Show)

data RequestReplicaState = RequestReplicaState
    { from :: ProcessId
    } deriving (Generic, Typeable, Show)

data ResponseReplicaState = ResponseReplicaState
    { state :: ReplicaState
    } deriving (Generic, Typeable, Show)

instance Binary ReplicaState

instance Binary RequestReplicaState

instance Binary ResponseReplicaState
