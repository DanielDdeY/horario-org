{-# LANGUAGE OverloadedStrings #-}

-- | Usuarios y tokens de sesión en SQLite (M3). Es infraestructura de autenticación, no un puerto de M2.
-- Solo se guardan el hash bcrypt de la contraseña y el SHA-256 del token; nunca sus valores en claro.
module Adapters.Sqlite.Usuarios
  ( Rol (..)
  , rolTexto
  , Credenciales (..)
  , SesionUsuario (..)
  , buscarCredenciales
  , guardarToken
  , buscarSesion
  , hayCoordinador
  , crearCoordinador
  ) where

import Adapters.Sqlite.Conexion
import Data.Text (Text)
import Database.SQLite.Simple
import Domain.Tipos (ProfesorId (..))

data Rol = RolProfesor | RolCoordinador
  deriving (Eq, Show)

rolTexto :: Rol -> Text
rolTexto RolProfesor = "profesor"
rolTexto RolCoordinador = "coordinador"

rolDeTexto :: Text -> Maybe Rol
rolDeTexto t = case t of
  "profesor" -> Just RolProfesor
  "coordinador" -> Just RolCoordinador
  _ -> Nothing

data Credenciales = Credenciales
  { usuarioId :: Int
  , hashGuardado :: Text
  , rolCredenciales :: Rol
  , profesorCredenciales :: Maybe ProfesorId
  }
  deriving (Eq, Show)

-- | Identidad autenticada que acompaña a cada petición.
data SesionUsuario = SesionUsuario
  { usuarioSesion :: Int
  , rolSesion :: Rol
  , profesorSesion :: Maybe ProfesorId
  }
  deriving (Eq, Show)

buscarCredenciales :: BaseDatos -> Text -> IO (Maybe Credenciales)
buscarCredenciales bd usuario = conConexion bd $ \c -> do
  filas <- query c "SELECT id, hash_contrasena, rol, profesor_id FROM usuarios WHERE usuario = ?" (Only usuario)
  pure $ case filas of
    (i, h, r, p) : _ -> (\rol -> Credenciales i h rol (ProfesorId <$> p)) <$> rolDeTexto r
    [] -> Nothing

-- | Guarda el hash del token y limpia los tokens vencidos.
guardarToken :: BaseDatos -> Text -> Int -> Text -> Text -> IO ()
guardarToken bd hashToken usuario expiraEn ahora = conConexion bd $ \c -> do
  execute c "DELETE FROM tokens WHERE expira_en <= ?" (Only ahora)
  execute c "INSERT INTO tokens (hash_token, usuario_id, expira_en) VALUES (?, ?, ?)" (hashToken, usuario, expiraEn)

-- | Sesión vigente para el hash del token, si existe y no venció.
-- Las fechas se comparan como texto ISO 8601 en UTC, que conserva el orden cronológico.
buscarSesion :: BaseDatos -> Text -> Text -> IO (Maybe SesionUsuario)
buscarSesion bd hashToken ahora = conConexion bd $ \c -> do
  filas <- query c
    "SELECT u.id, u.rol, u.profesor_id FROM tokens t JOIN usuarios u ON u.id = t.usuario_id \
    \WHERE t.hash_token = ? AND t.expira_en > ?"
    (hashToken, ahora)
  pure $ case filas of
    (i, r, p) : _ -> (\rol -> SesionUsuario i rol (ProfesorId <$> p)) <$> rolDeTexto r
    [] -> Nothing

hayCoordinador :: BaseDatos -> IO Bool
hayCoordinador bd = conConexion bd $ \c -> do
  filas <- query_ c "SELECT id FROM usuarios WHERE rol = 'coordinador' LIMIT 1" :: IO [Only Int]
  pure (not (null filas))

crearCoordinador :: BaseDatos -> Text -> Text -> IO ()
crearCoordinador bd usuario hash = conConexion bd $ \c ->
  execute c "INSERT INTO usuarios (usuario, hash_contrasena, rol, profesor_id) VALUES (?, ?, 'coordinador', NULL)"
    (usuario, hash)
