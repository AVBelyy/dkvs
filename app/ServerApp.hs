import qualified Server

import System.Environment (getArgs)

main :: IO ()
main
-- Parse command line args
 = do
    args <- getArgs
    let nodeId = read (head args)
    -- Start server
    Server.serve nodeId
