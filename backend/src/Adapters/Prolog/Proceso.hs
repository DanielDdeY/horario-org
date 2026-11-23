{-# LANGUAGE OverloadedStrings #-}

module Adapters.Prolog.Proceso
  ( ConfiguracionProlog (..)
  , solverProlog
  ) where

import Adapters.Prolog.JSON (codificarSolicitud, leerRespuesta)
import Control.Concurrent.Async (wait, waitCatch, withAsync)
import Control.Exception (IOException, displayException, finally, onException, try)
import qualified Data.ByteString as BS
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Text.Encoding (decodeUtf8With)
import Data.Text.Encoding.Error (lenientDecode)
import Domain.Tipos (Configuracion (..))
import System.Exit (ExitCode (..))
import System.IO (hClose, hSetBinaryMode)
import System.Process
import System.Timeout (timeout)
import UseCases.Solver

data ConfiguracionProlog = ConfiguracionProlog
  { ejecutableProlog :: FilePath
  , argumentosProlog :: [String]
  , directorioProlog :: Maybe FilePath
  , maxTimeoutSeg :: Int
  , margenTimeoutMs :: Int
  }
  deriving (Eq, Show)

solverProlog :: ConfiguracionProlog -> Solver IO
solverProlog opciones = Solver $ \solicitud -> do
  let config = configuracionSolver solicitud
      segundos = min (timeoutSeg config) (maxTimeoutSeg opciones)
      limiteMs = toInteger segundos * 1000 + toInteger (margenTimeoutMs opciones)
  if segundos <= 0 || margenTimeoutMs opciones < 0 || limiteMs * 1000 > toInteger (maxBound :: Int)
    then pure (ErrorMotor "El límite de tiempo del motor es inválido.")
    else do
      let entrada = codificarSolicitud (solicitud { configuracionSolver = config { timeoutSeg = segundos } }) <> "\n"
      intento <- tryIO (timeout (fromInteger (limiteMs * 1000)) (intercambiar opciones entrada))
      pure $ case intento of
        Left problema -> ErrorMotor (Text.pack (displayException problema))
        Right Nothing -> TiempoAgotado (fromInteger limiteMs)
        Right (Just (Left problema)) -> ErrorMotor problema
        Right (Just (Right salida)) -> either ErrorMotor id (leerRespuesta salida)

tryIO :: IO a -> IO (Either IOException a)
tryIO = try

intercambiar :: ConfiguracionProlog -> BS.ByteString -> IO (Either Text BS.ByteString)
intercambiar opciones entrada =
  withCreateProcess proceso $ \stdin stdout stderr procesoActivo ->
    case (stdin, stdout, stderr) of
      (Just escribir, Just leer, Just errores) -> do
        mapM_ (\medio -> hSetBinaryMode medio True) [escribir, leer, errores]
        withAsync (BS.hGetContents leer) $ \lector ->
          withAsync (BS.hGetContents errores) $ \lectorErrores ->
            withAsync (BS.hPut escribir entrada `finally` hClose escribir) $ \escritor ->
              onException (recoger procesoActivo lector lectorErrores escritor) (terminateProcess procesoActivo)
      _ -> pure (Left "No se pudieron abrir los canales del proceso de Prolog.")
  where
    proceso = (proc (ejecutableProlog opciones) (argumentosProlog opciones))
      { cwd = directorioProlog opciones
      , std_in = CreatePipe
      , std_out = CreatePipe
      , std_err = CreatePipe
      }
    recoger procesoActivo lector lectorErrores escritor = do
      codigo <- waitForProcess procesoActivo
      salida <- wait lector
      textoError <- Text.strip . decodeUtf8With lenientDecode <$> wait lectorErrores
      enviado <- waitCatch escritor
      pure $ case codigo of
        ExitFailure n ->
          Left ("Prolog salió con código " <> Text.pack (show n) <>
            if Text.null textoError then "." else ": " <> textoError)
        ExitSuccess | not (Text.null textoError) -> Left ("Prolog escribió en stderr: " <> textoError)
        ExitSuccess -> case enviado of
          Left problema -> Left (Text.pack (displayException problema))
          Right () -> Right salida
