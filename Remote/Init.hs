-- | Exposes a high-level interface for starting a node of a distributed
-- program, taking into account a local configuration file, command
-- line arguments, and commonly-used system processes.
module Remote.Init (remoteInit) where

import Remote.Peer (startDiscoveryService)
import Remote.Task (__remoteCallMetaData)
import Remote.Process (startProcessRegistryService,suppressTransmitException,pbracket,localRegistryRegisterNode,localRegistryHello,localRegistryUnregisterNode,
                       startProcessMonitorService,startNodeMonitorService,startLoggingService,startSpawnerService,ProcessM,readConfig,initNode,startLocalRegistry,
                       forkAndListenAndDeliver,waitForThreads,roleDispatch,Node,runLocalProcess,performFinalization,startFinalizerService)
import Remote.Reg (registerCalls,RemoteCallMetaData)

import System.FilePath (FilePath)
import System.Environment (getEnvironment)
import Control.Concurrent (threadDelay)
import Control.Monad.Trans (liftIO)
import Control.Exception (finally)
import Control.Concurrent.MVar (MVar,takeMVar,putMVar,newEmptyMVar)

startServices :: ProcessM ()
startServices = 
           do
              startProcessRegistryService
              startNodeMonitorService
              startProcessMonitorService
              startLoggingService
              startDiscoveryService
              startSpawnerService
              startFinalizerService (suppressTransmitException localRegistryUnregisterNode >> return ())

dispatchServices :: MVar Node -> IO ()
dispatchServices node = do mv <- newEmptyMVar
                           runLocalProcess node (startServices >> liftIO (putMVar mv ()))
                           takeMVar mv

-- | This is the usual way create a single node of distributed program.
-- The intent is that 'remoteInit' be called in your program's 'Main.main'
-- function. A typical call takes this form:
--
-- > main = remoteInit (Just "config") [Main.__remoteCallMetaData] initialProcess
--
-- This will:
--
-- 1. Read the configuration file @config@ in the current directory or, if specified, from the file whose path is given by the environment variable @RH_CONFIG@. If the given file does not exist or is invalid, an exception will be thrown.
--
-- 2. Use the configuration given in the file as well as on the command-line to create a new node. The usual system processes will be started, including logging, discovery, and spawning.
--
-- 3. Compile-time metadata, generated by 'Remote.Call.remotable', will used for invoking closures. Metadata from each module must be explicitly mentioned.
--
-- 4. The function initialProcess will be called, given as a parameter a string indicating the value of the cfgRole setting of this node. initialProcess is provided by the user and provides an entrypoint for controlling node behavior on startup.
remoteInit :: Maybe FilePath -> [RemoteCallMetaData] -> (String -> ProcessM ()) -> IO ()
remoteInit defaultConfig metadata f = 
       let
          defaultMetaData = [Remote.Task.__remoteCallMetaData]
          lookup = registerCalls (defaultMetaData ++ metadata)
       in
       do
          configFileName <- getConfigFileName
          cfg <- readConfig True configFileName
              -- TODO sanity-check cfg
          node <- initNode cfg lookup
          _ <- startLocalRegistry cfg False -- potentially fails silently
          forkAndListenAndDeliver node cfg
          dispatchServices node
          (roleDispatch node userFunction >> waitForThreads node) `finally` (performFinalization node)
          threadDelay 500000 -- TODO make configurable, or something
   where  getConfigFileName = do env <- getEnvironment
                                 return $ maybe defaultConfig Just (lookup "RH_CONFIG" env)
          userFunction s = localRegistryHello >> localRegistryRegisterNode >> f s

