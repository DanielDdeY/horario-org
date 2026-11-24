{-# LANGUAGE OverloadedStrings #-}

-- | Aplica en orden los scripts numerados de @backend/migrations@ (M3).
-- Cada script se aplica una sola vez, dentro de una transacción, y queda registrado en @schema_migraciones@.
-- Una migración ya aplicada nunca se edita: los cambios van en un archivo nuevo.
module Adapters.Sqlite.Migraciones
  ( migrar
  ) where

import Adapters.Sqlite.Conexion
import Control.Exception (try)
import Control.Monad (forM)
import Data.Char (isDigit)
import Data.List (sort)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Database.SQLite.Simple
import qualified Database.SQLite3 as Base
import System.Directory (listDirectory)
import System.FilePath (takeExtension, (</>))

-- | Activa WAL, crea la tabla de control y aplica las migraciones pendientes.
-- Devuelve los nombres de los scripts aplicados en esta llamada.
migrar :: BaseDatos -> FilePath -> IO [FilePath]
migrar bd directorio = do
  archivos <- sort . filter esMigracion <$> listDirectory directorio
  conConexion bd $ \conexion -> do
    _ <- query_ conexion "PRAGMA journal_mode = WAL" :: IO [Only Text]
    execute_ conexion
      "CREATE TABLE IF NOT EXISTS schema_migraciones (nombre TEXT PRIMARY KEY, aplicada_en TEXT NOT NULL)"
    aplicadas <- Set.fromList . map fromOnly <$>
      (query_ conexion "SELECT nombre FROM schema_migraciones" :: IO [Only Text])
    concat <$> forM archivos (\archivo ->
      if Set.member (Text.pack archivo) aplicadas
        then pure []
        else aplicar conexion archivo >> pure [archivo])
  where
    esMigracion archivo = takeExtension archivo == ".sql" && length archivo > 4 && all isDigit (take 4 archivo)
    aplicar conexion archivo = do
      script <- TextIO.readFile (directorio </> archivo)
      momento <- ahoraIso
      execute_ conexion "BEGIN IMMEDIATE"
      intento <- try (Base.exec (connectionHandle conexion) script) :: IO (Either Base.SQLError ())
      case intento of
        Left e -> do
          execute_ conexion "ROLLBACK"
          ioError (userError ("Falló la migración " <> archivo <> ": " <> show e))
        Right () -> do
          execute conexion "INSERT INTO schema_migraciones (nombre, aplicada_en) VALUES (?, ?)"
            (Text.pack archivo, momento)
          execute_ conexion "COMMIT"
