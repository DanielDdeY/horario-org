{-# LANGUAGE OverloadedStrings #-}

-- | Ejecución asíncrona de los trabajos de generación (M3).
-- Cada trabajo persiste en SQLite; un semáforo limita cuántos corren a la vez.
-- La generación en sí es el caso de uso 'generarHorarios' de M2.
module Adapters.Api.Trabajos
  ( Ejecutor
  , nuevoEjecutor
  , encolar
  , reanudar
  , solicitudGeneracion
  ) where

import Adapters.Api.Errores
import Adapters.Sqlite.Codificacion (numeroVersionDeEntero, politicaDeTexto)
import Adapters.Sqlite.Conexion (BaseDatos)
import Adapters.Sqlite.Repositorio (repositorioSqlite)
import Adapters.Sqlite.Trabajos
import Control.Concurrent (forkIO)
import Control.Concurrent.QSem
import Control.Exception (SomeException, bracket_, displayException, try)
import Control.Monad (forM_, void, when)
import Data.Aeson
import qualified Data.ByteString.Lazy as BL
import qualified Data.List.NonEmpty as NE
import Data.Text (Text)
import qualified Data.Text.Encoding as TE
import Domain.Tipos
import System.IO (hPutStrLn, stderr)
import UseCases.Generacion
import UseCases.Horarios (DetalleHorario (..))
import UseCases.Solver

newtype Ejecutor = Ejecutor QSem

nuevoEjecutor :: Int -> IO Ejecutor
nuevoEjecutor n = Ejecutor <$> newQSem (max 1 n)

-- | Traduce lo que pidió la API al 'SolicitudGeneracion' de M2.
solicitudGeneracion :: SolicitudTrabajo -> Either Text SolicitudGeneracion
solicitudGeneracion s = do
  modo <- case (modoTrabajo s, baseTrabajo s) of
    ("generar", Nothing) -> Right GenerarDesdeCero
    ("generar", Just b) -> do
      politica <- maybe (Left "politica inválida.") Right (politicaDeTexto (maybe "conservar" id (politicaTrabajo s)))
      Right (Regenerar (HorarioId b) politica)
    ("completar", Just b) -> Right (Completar (HorarioId b))
    ("completar", Nothing) -> Left "El modo completar exige baseHorarioId."
    _ -> Left "modo inválido."
  version <- maybe (Left "maxVersiones debe estar entre 1 y 4.") Right (numeroVersionDeEntero (maxVersionesTrabajo s))
  Right (SolicitudGeneracion (PeriodoId (periodoTrabajo s)) modo version)

-- | Lanza el trabajo en un hilo propio. Espera turno en el semáforo antes de ejecutar.
encolar :: BaseDatos -> Solver IO -> Ejecutor -> Int -> IO ()
encolar bd motor (Ejecutor semaforo) identificador =
  void $ forkIO $ bracket_ (waitQSem semaforo) (signalQSem semaforo) $ do
    resultado <- try (ejecutar bd motor identificador)
    case resultado of
      Right () -> pure ()
      Left (e :: SomeException) -> do
        hPutStrLn stderr ("[trabajos] Trabajo " <> show identificador <> " falló: " <> displayException e)
        fallarTrabajo bd identificador (textoJson (errorAJson errorInterno))

ejecutar :: BaseDatos -> Solver IO -> Int -> IO ()
ejecutar bd motor identificador = do
  tomado <- marcarEjecutando bd identificador
  when tomado $ do
    trabajo <- buscarTrabajo bd identificador
    forM_ trabajo $ \t ->
      case solicitudGeneracion (solicitudTrabajo t) of
        Left mensaje -> fallarTrabajo bd identificador
          (textoJson (errorAJson (ErrorApi (estadoHttp errorInterno) "SOLICITUD_INVALIDA" mensaje [])))
        Right solicitud -> do
          resultado <- generarHorarios (repositorioSqlite bd) motor solicitud
          case resultado of
            Left e -> fallarTrabajo bd identificador (textoJson (errorAJson (desdeCasoUso e)))
            Right generacion -> terminarTrabajo bd identificador (textoJson (resultadoGeneracion generacion))

resultadoGeneracion :: Generacion -> Value
resultadoGeneracion g = object
  [ "tiempoMs" .= tiempoGeneracionMs g
  , "versiones" .=
      [ object
          [ "numeroVersion" .= n
          , "estadoMotor" .= estadoTexto (estadoVersion v)
          , "horarioId" .= (let HorarioId h = horarioId (horarioDetallado (detalleVersion v)) in h)
          ]
      | (n, v) <- zip [1 :: Int ..] (NE.toList (versionesGeneradas g)) ]
  ]
  where
    estadoTexto :: EstadoSolucion -> Text
    estadoTexto Optimo = "optimo"
    estadoTexto Factible = "factible"

textoJson :: Value -> Text
textoJson = TE.decodeUtf8 . BL.toStrict . encode

-- | Al arrancar: marca como error los trabajos que quedaron en ejecución y vuelve a encolar los pendientes.
reanudar :: BaseDatos -> Solver IO -> Ejecutor -> IO ()
reanudar bd motor ejecutor = do
  let interrumpido = ErrorApi (estadoHttp errorInterno) "TRABAJO_INTERRUMPIDO"
        "El servidor se reinició mientras el trabajo se ejecutaba. Vuelve a lanzarlo." []
  n <- interrumpirEjecutando bd (textoJson (errorAJson interrumpido))
  when (n > 0) $ hPutStrLn stderr ("[trabajos] " <> show n <> " trabajo(s) interrumpido(s) por el reinicio.")
  pendientes <- trabajosPendientes bd
  mapM_ (encolar bd motor ejecutor) pendientes


