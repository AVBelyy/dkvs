{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE DuplicateRecordFields #-}

module PaxosTypes where

import           Control.Distributed.Process (ProcessId)
import           Data.Binary                 (Binary)
import           Data.Typeable               (Typeable)
import           GHC.Generics
import qualified Data.Set as S

type Error = String

data Operation
    = Get String
    | Set String
          String
    | Delete String
    | Reply (Either Error String)
    deriving (Generic, Typeable, Eq, Ord)

data BallotNumber = BallotNumber
    { round    :: Integer
    , leaderId :: Integer
    } deriving (Generic, Typeable, Eq, Ord)

data Command = Command
    { clientId  :: ProcessId
    , requestId :: Integer
    , op        :: Operation
    } deriving (Generic, Typeable, Eq, Ord)

data PValue = PValue
    { ballotNumber :: BallotNumber
    , slotNumber   :: Integer
    , command      :: Command
    } deriving (Generic, Typeable, Eq, Ord)

data P1aMessage = P1aMessage
    { from         :: ProcessId
    , ballotNumber :: BallotNumber
    } deriving (Generic, Typeable)

data P1bMessage = P1bMessage
    { from         :: ProcessId
    , ballotNumber :: BallotNumber
    , accepted     :: S.Set PValue
    } deriving (Generic, Typeable)

data P2aMessage = P2aMessage
    { from         :: ProcessId
    , ballotNumber :: BallotNumber
    , slotNumber   :: Integer
    , command      :: Command
    } deriving (Generic, Typeable)

data P2bMessage = P2bMessage
    { from         :: ProcessId
    , ballotNumber :: BallotNumber
    , slotNumber   :: Integer
    } deriving (Generic, Typeable)

data PreemptedMessage = PreemptedMessage
    { ballotNumber :: BallotNumber
    } deriving (Generic, Typeable)

data AdoptedMessage = AdoptedMessage
    { ballotNumber :: BallotNumber
    , accepted     :: S.Set PValue
    } deriving (Generic, Typeable)

data DecisionMessage = DecisionMessage
    { from       :: ProcessId
    , slotNumber :: Integer
    , command    :: Command
    } deriving (Generic, Typeable)

data RequestMessage = RequestMessage
    { command :: Command
    } deriving (Generic, Typeable)

data ProposeMessage = ProposeMessage
    { slotNumber :: Integer
    , command    :: Command
    } deriving (Generic, Typeable)

data ResponseMessage = ResponseMessage
    { command :: Command
    } deriving (Generic, Typeable)

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
