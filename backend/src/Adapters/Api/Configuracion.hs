{-# LANGUAGE OverloadedStrings #-}

-- | Configuración del servidor por variables de entorno (M3). Ningún secreto vive en el repositorio.
module Adapters.Api.Configuracion
  ( ConfiguracionServidor (..)
  , leerConfiguracionServidor
  , configuracionProlog
  ) where

import Adapters.Prolog.Proceso (ConfiguracionProlog (..))
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as Text
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

data ConfiguracionServidor = ConfiguracionServidor
  { puerto :: Int
  , rutaBaseDatos :: FilePath
  , directorioMigraciones :: FilePath
  , maxTrabajosConcurrentes :: Int
  , horasToken :: Int
  , costoBcrypt :: Int
  , ejecutableMotor :: FilePath
  , argumentosMotor :: [String]
  , directorioMotor :: Maybe FilePath
  , maxTimeoutSegMotor :: Int
  , margenTimeoutMsMotor :: Int
  , coordinadorInicial :: Maybe (Text, Text)
  }

-- | Variables (todas opcionales salvo el coordinador inicial la primera vez):
--
-- * @HORARIO_PUERTO@ (8080), @HORARIO_BD@ (horario.db), @HORARIO_MIGRACIONES@ (migrations)
-- * @HORARIO_MAX_TRABAJOS@ (2), @HORARIO_TOKEN_HORAS@ (8), @HORARIO_BCRYPT_COSTO@ (10)
-- * @HORARIO_SWIPL@ (swipl), @HORARIO_MOTOR_ARGS@ (argumentos separados por espacios),
--   @HORARIO_MOTOR_DIR@, @HORARIO_MAX_TIMEOUT_SEG@ (300), @HORARIO_MARGEN_TIMEOUT_MS@ (2000)
-- * @HORARIO_COORDINADOR_USUARIO@ y @HORARIO_COORDINADOR_CONTRASENA@: crean el primer coordinador
--   si la base aún no tiene ninguno.
leerConfiguracionServidor :: IO ConfiguracionServidor
leerConfiguracionServidor = do
  p <- numero "HORARIO_PUERTO" 8080
  bd <- texto "HORARIO_BD" "horario.db"
  migraciones <- texto "HORARIO_MIGRACIONES" "migrations"
  trabajos <- numero "HORARIO_MAX_TRABAJOS" 2
  horas <- numero "HORARIO_TOKEN_HORAS" 8
  costo <- numero "HORARIO_BCRYPT_COSTO" 10
  swipl <- texto "HORARIO_SWIPL" "swipl"
  args <- words <$> texto "HORARIO_MOTOR_ARGS" ""
  dir <- lookupEnv "HORARIO_MOTOR_DIR"
  maxSeg <- numero "HORARIO_MAX_TIMEOUT_SEG" 300
  margen <- numero "HORARIO_MARGEN_TIMEOUT_MS" 2000
  usuario <- lookupEnv "HORARIO_COORDINADOR_USUARIO"
  contrasena <- lookupEnv "HORARIO_COORDINADOR_CONTRASENA"
  pure ConfiguracionServidor
    { puerto = p
    , rutaBaseDatos = bd
    , directorioMigraciones = migraciones
    , maxTrabajosConcurrentes = max 1 trabajos
    , horasToken = max 1 horas
    , costoBcrypt = max 4 costo
    , ejecutableMotor = swipl
    , argumentosMotor = args
    , directorioMotor = dir
    , maxTimeoutSegMotor = max 1 maxSeg
    , margenTimeoutMsMotor = max 0 margen
    , coordinadorInicial = (,) <$> fmap Text.pack usuario <*> fmap Text.pack contrasena
    }
  where
    texto nombre defecto = fromMaybe defecto <$> lookupEnv nombre
    numero nombre defecto = fromMaybe defecto . (>>= readMaybe) <$> lookupEnv nombre

configuracionProlog :: ConfiguracionServidor -> ConfiguracionProlog
configuracionProlog c = ConfiguracionProlog
  { ejecutableProlog = ejecutableMotor c
  , argumentosProlog = argumentosMotor c
  , directorioProlog = directorioMotor c
  , maxTimeoutSeg = maxTimeoutSegMotor c
  , margenTimeoutMs = margenTimeoutMsMotor c
  }
