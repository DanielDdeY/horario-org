{-# LANGUAGE OverloadedStrings #-}

-- | Persistencia de los trabajos asíncronos de generación (M3).
-- Estados: pendiente → ejecutando → terminado | error.
module Adapters.Sqlite.Trabajos
  ( EstadoTrabajo (..)
  , estadoTrabajoTexto
  , SolicitudTrabajo (..)
  , Trabajo (..)
  , crearTrabajo
  , marcarEjecutando
  , terminarTrabajo
  , fallarTrabajo
  , buscarTrabajo
  , trabajosPendientes
  , interrumpirEjecutando
  ) where

import Adapters.Sqlite.Conexion
import Data.Text (Text)
import Database.SQLite.Simple

data EstadoTrabajo = Pendiente | Ejecutando | Terminado | ConError
  deriving (Eq, Show)

estadoTrabajoTexto :: EstadoTrabajo -> Text
estadoTrabajoTexto e = case e of
  Pendiente -> "pendiente"
  Ejecutando -> "ejecutando"
  Terminado -> "terminado"
  ConError -> "error"

estadoDeTexto :: Text -> EstadoTrabajo
estadoDeTexto t = case t of
  "pendiente" -> Pendiente
  "ejecutando" -> Ejecutando
  "terminado" -> Terminado
  _ -> ConError

-- | Lo que pidió el coordinador, tal como llegó a la API.
data SolicitudTrabajo = SolicitudTrabajo
  { periodoTrabajo :: Int
  , modoTrabajo :: Text
  , baseTrabajo :: Maybe Int
  , politicaTrabajo :: Maybe Text
  , maxVersionesTrabajo :: Int
  }
  deriving (Eq, Show)

data Trabajo = Trabajo
  { idTrabajo :: Int
  , estadoTrabajo :: EstadoTrabajo
  , solicitudTrabajo :: SolicitudTrabajo
  , resultadoJson :: Maybe Text
  , errorJson :: Maybe Text
  , creadoEnTrabajo :: Text
  , actualizadoEnTrabajo :: Text
  }
  deriving (Eq, Show)

crearTrabajo :: BaseDatos -> SolicitudTrabajo -> IO Int
crearTrabajo bd (SolicitudTrabajo p m b pol mx) = conConexion bd $ \c -> do
  momento <- ahoraIso
  execute c
    "INSERT INTO trabajos (estado, periodo_id, modo, base_horario_id, politica, max_versiones, creado_en, actualizado_en) \
    \VALUES ('pendiente', ?, ?, ?, ?, ?, ?, ?)"
    (p, m, b, pol, mx, momento, momento)
  fromIntegral <$> lastInsertRowId c

-- | Pasa a ejecutando solo si sigue pendiente. Devuelve si el cambio ocurrió.
marcarEjecutando :: BaseDatos -> Int -> IO Bool
marcarEjecutando bd i = conConexion bd $ \c -> do
  momento <- ahoraIso
  execute c "UPDATE trabajos SET estado = 'ejecutando', actualizado_en = ? WHERE id = ? AND estado = 'pendiente'" (momento, i)
  (> 0) <$> changes c

terminarTrabajo :: BaseDatos -> Int -> Text -> IO ()
terminarTrabajo bd i resultado = conConexion bd $ \c -> do
  momento <- ahoraIso
  execute c "UPDATE trabajos SET estado = 'terminado', resultado_json = ?, actualizado_en = ? WHERE id = ?"
    (resultado, momento, i)

fallarTrabajo :: BaseDatos -> Int -> Text -> IO ()
fallarTrabajo bd i errorTexto = conConexion bd $ \c -> do
  momento <- ahoraIso
  execute c "UPDATE trabajos SET estado = 'error', error_json = ?, actualizado_en = ? WHERE id = ?"
    (errorTexto, momento, i)

buscarTrabajo :: BaseDatos -> Int -> IO (Maybe Trabajo)
buscarTrabajo bd i = conConexion bd $ \c -> do
  filas <- query c
    "SELECT id, estado, periodo_id, modo, base_horario_id, politica, max_versiones, resultado_json, error_json, \
    \creado_en, actualizado_en FROM trabajos WHERE id = ?"
    (Only i)
  pure $ case filas of
    ((t, e, p, m, b, pol, mx, r, err, cr) :. Only ac) : _ ->
      Just (Trabajo t (estadoDeTexto e) (SolicitudTrabajo p m b pol mx) r err cr ac)
    [] -> Nothing

-- | IDs de los trabajos pendientes, del más antiguo al más reciente.
trabajosPendientes :: BaseDatos -> IO [Int]
trabajosPendientes bd = conConexion bd $ \c ->
  map fromOnly <$> query_ c "SELECT id FROM trabajos WHERE estado = 'pendiente' ORDER BY id"

-- | Al arrancar, un trabajo que quedó en ejecución se interrumpió con el servidor: se marca como error.
interrumpirEjecutando :: BaseDatos -> Text -> IO Int
interrumpirEjecutando bd errorTexto = conConexion bd $ \c -> do
  momento <- ahoraIso
  execute c "UPDATE trabajos SET estado = 'error', error_json = ?, actualizado_en = ? WHERE estado = 'ejecutando'"
    (errorTexto, momento)
  changes c
