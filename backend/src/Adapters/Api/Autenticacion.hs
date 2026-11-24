{-# LANGUAGE OverloadedStrings #-}

-- | Contraseñas con bcrypt (hash con sal) y tokens opacos con expiración (M3).
-- El token viaja una sola vez al cliente; en la base solo queda su SHA-256. Nada de esto se escribe en logs.
module Adapters.Api.Autenticacion
  ( hashContrasena
  , contrasenaCorrecta
  , TokenEmitido (..)
  , emitirToken
  , sesionDeToken
  , hashDeToken
  ) where

import Adapters.Sqlite.Conexion (BaseDatos)
import Adapters.Sqlite.Usuarios
import Crypto.Hash (SHA256 (..), hashWith)
import qualified Crypto.KDF.BCrypt as BCrypt
import Crypto.Random (getRandomBytes)
import Data.ByteString (ByteString)
import qualified Data.ByteString.Base16 as Base16
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TE
import Data.Time (addUTCTime, getCurrentTime)
import Data.Time.Format.ISO8601 (iso8601Show)

-- | Hash bcrypt con sal aleatoria. El costo se configura en el servidor.
hashContrasena :: Int -> Text -> IO Text
hashContrasena costo contrasena = do
  h <- BCrypt.hashPassword costo (TE.encodeUtf8 contrasena) :: IO ByteString
  pure (TE.decodeUtf8 h)

contrasenaCorrecta :: Text -> Text -> Bool
contrasenaCorrecta contrasena hash = BCrypt.validatePassword (TE.encodeUtf8 contrasena) (TE.encodeUtf8 hash)

hashDeToken :: Text -> Text
hashDeToken token = Text.pack (show (hashWith SHA256 (TE.encodeUtf8 token)))

data TokenEmitido = TokenEmitido
  { tokenEmitido :: Text
  , expiraEnEmitido :: Text
  }

-- | Genera 32 bytes aleatorios, guarda su hash y devuelve el token y su vencimiento (ISO 8601, UTC).
emitirToken :: BaseDatos -> Int -> Credenciales -> IO TokenEmitido
emitirToken bd horas credenciales = do
  aleatorio <- getRandomBytes 32 :: IO ByteString
  ahora <- getCurrentTime
  let token = TE.decodeUtf8 (Base16.encode aleatorio)
      expira = Text.pack (iso8601Show (addUTCTime (fromIntegral (horas * 3600)) ahora))
  guardarToken bd (hashDeToken token) (usuarioId credenciales) expira (Text.pack (iso8601Show ahora))
  pure (TokenEmitido token expira)

-- | Sesión vigente a partir de la cabecera @Authorization: Bearer <token>@.
sesionDeToken :: BaseDatos -> Maybe Text -> IO (Maybe SesionUsuario)
sesionDeToken bd cabecera =
  case Text.stripPrefix "Bearer " . Text.strip =<< cabecera of
    Nothing -> pure Nothing
    Just token
      | Text.null (Text.strip token) -> pure Nothing
      | otherwise -> do
          ahora <- Text.pack . iso8601Show <$> getCurrentTime
          buscarSesion bd (hashDeToken (Text.strip token)) ahora
