{-# LANGUAGE RecordWildCards #-}

module Config where

import           Data.List.Split   (splitOn)
import           Data.String.Utils (startswith)

import qualified Data.Map          as M

import           Types

defaultConfig :: Config
defaultConfig = Config M.empty 10000

readConfigFile :: IO Config
readConfigFile = do
    contents <- readFile "./dkvs.properties"
    let params = map (splitOn "=") (lines contents)
    return $ parse' defaultConfig params
  where
    parse' cfg [] = cfg
    parse' cfg (["timeout", val]:xs) =
        parse'
            (cfg
             { timeout = read val
             })
            xs
    parse' cfg ([key, val]:xs)
        | startswith "node." key =
            parse'
                (cfg
                 { nodesMap = nodesMap' cfg
                 })
                xs
      where
        nodesMap' Config {..} = M.insert k v nodesMap
        (k, v) = (read kStr, (role, host, port))
        role =
            case roleStr of
                "a" -> Acceptor
                "l" -> Leader
                "r" -> Replica
        [host, port] = splitOn ":" val
        [kStr, roleStr] = splitOn "." (drop 5 key)
