{-# LANGUAGE OverloadedStrings #-}

-- | Acceso a SQLite (M3). Una conexión por operación: SQLite es un archivo local y abrirlo es barato.
-- Cada conexión activa las claves foráneas y espera hasta 5 s si otro escritor tiene el candado.
-- El modo WAL es persistente y lo activa 'Adapters.Sqlite.Migraciones.migrar'.
module Adapters.Sqlite.Conexion
  ( BaseDatos (..)
  , conConexion
  , enTransaccion
  , ahoraIso
  , esViolacionRestriccion
  , detalleSqlite
  ) where

import Control.Exception (SomeException, fromException, mask, onException)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime)
import Data.Time.Format.ISO8601 (iso8601Show)
import Database.SQLite.Simple
import qualified Database.SQLite3 as Base

-- | Ruta del archivo de la base.
newtype BaseDatos = BaseDatos {rutaBase :: FilePath}
  deriving (Eq, Show)

abrir :: BaseDatos -> IO Connection
abrir bd = do
  conexion <- open (rutaBase bd)
  execute_ conexion "PRAGMA foreign_keys = ON"
  execute_ conexion "PRAGMA busy_timeout = 5000"
  pure conexion

conConexion :: BaseDatos -> (Connection -> IO a) -> IO a
conConexion bd accion = mask $ \restaurar -> do
  conexion <- abrir bd
  resultado <- restaurar (accion conexion) `onException` close conexion
  close conexion
  pure resultado

-- | Ejecuta la acción en una transacción inmediata (toma el candado de escritura al empezar).
-- Confirma si devuelve 'Right' y revierte si devuelve 'Left' o lanza una excepción.
enTransaccion :: BaseDatos -> (Connection -> IO (Either e a)) -> IO (Either e a)
enTransaccion bd accion = conConexion bd $ \conexion -> do
  execute_ conexion "BEGIN IMMEDIATE"
  resultado <- accion conexion `onException` revertir conexion
  case resultado of
    Left _ -> revertir conexion
    Right _ -> execute_ conexion "COMMIT"
  pure resultado
  where
    revertir conexion = execute_ conexion "ROLLBACK"

ahoraIso :: IO Text
ahoraIso = Text.pack . iso8601Show <$> (getCurrentTime :: IO UTCTime)

esViolacionRestriccion :: SomeException -> Bool
esViolacionRestriccion e =
  case fromException e of
    Just err -> Base.sqlError err == Base.ErrorConstraint
    Nothing -> False

detalleSqlite :: SomeException -> Text
detalleSqlite e =
  case fromException e of
    Just err -> Base.sqlErrorDetails err
    Nothing -> Text.pack (show e)
