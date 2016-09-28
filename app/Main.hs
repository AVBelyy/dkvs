import qualified Server

import System.Environment (getArgs)

main :: IO ()
main = do
    -- Parse command line args
    args <- getArgs
    let nodeId = read (head args)

    -- Start server
    Server.serve nodeId
