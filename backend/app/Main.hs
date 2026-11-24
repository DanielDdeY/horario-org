{-# LANGUAGE OverloadedStrings #-}

-- | Ejecutable del servidor (M3): migra SQLite, crea el primer coordinador si hace falta,
-- reanuda los trabajos pendientes y sirve la API con Warp.
module Main (main) where

import Adapters.Api.Autenticacion (hashContrasena)
import Adapters.Api.Configuracion
import Adapters.Api.Servidor
import Adapters.Api.Trabajos (nuevoEjecutor, reanudar)
import Adapters.Prolog.Proceso (solverProlog)
import Adapters.Sqlite.Conexion (BaseDatos (..))
import Adapters.Sqlite.Migraciones (migrar)
import Adapters.Sqlite.Usuarios (crearCoordinador, hayCoordinador)
import Control.Monad (forM_, unless)
import qualified Data.Text as Text
import Network.Wai.Handler.Warp (run)
import System.IO (BufferMode (..), hPutStrLn, hSetBuffering, stderr, stdout)

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  hSetBuffering stderr LineBuffering
  config <- leerConfiguracionServidor
  let bd = BaseDatos (rutaBaseDatos config)
  aplicadas <- migrar bd (directorioMigraciones config)
  forM_ aplicadas $ \m -> putStrLn ("[migraciones] Aplicada " <> m)
  existe <- hayCoordinador bd
  unless existe $
    case coordinadorInicial config of
      Just (usuario, contrasena) -> do
        hash <- hashContrasena (costoBcrypt config) contrasena
        crearCoordinador bd usuario hash
        putStrLn ("[arranque] Coordinador inicial creado: " <> Text.unpack usuario)
      Nothing -> hPutStrLn stderr
        "[arranque] No hay coordinador. Define HORARIO_COORDINADOR_USUARIO y HORARIO_COORDINADOR_CONTRASENA y reinicia."
  let motor = solverProlog (configuracionProlog config)
  ejecutor <- nuevoEjecutor (maxTrabajosConcurrentes config)
  reanudar bd motor ejecutor
  app <- aplicacion (Entorno bd motor ejecutor (horasToken config) (costoBcrypt config))
  putStrLn ("[arranque] API escuchando en http://localhost:" <> show (puerto config))
  run (puerto config) app
