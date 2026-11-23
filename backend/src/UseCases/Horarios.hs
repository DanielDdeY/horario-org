{-# LANGUAGE OverloadedStrings #-}

module UseCases.Horarios
  ( CambioHorario (..)
  , AplicacionCambio (..)
  , DetalleHorario (..)
  , crearHorarioVacio
  , consultarHorario
  , editarHorario
  , publicarHorario
  , describirHorario
  , dividirBase
  , avisosVigentes
  ) where

import Control.Monad (foldM, unless, when)
import Control.Monad.Trans.Except (runExceptT, throwE)
import Data.List (find)
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as NE
import qualified Data.Map.Strict as Map
import Domain.Disponibilidad (cubreFranja, normalizarFranjas)
import Domain.Tipos
import Domain.Validador
import UseCases.Errores
import UseCases.Repositorio

data CambioHorario
  = CrearAsignacion UbicacionSesion
  | MoverAsignacion UbicacionSesion
  | BorrarAsignacion SesionId
  | FijarAsignacion SesionId Bool
  deriving (Eq, Show)

data AplicacionCambio = Simular | Guardar
  deriving (Eq, Show)

data DetalleHorario = DetalleHorario
  { horarioDetallado :: Horario
  , evaluacion :: EvaluacionHorario
  , motivosPendientes :: [MotivoSinAsignar]
  , alertasDisponibilidad :: [AvisoDisponibilidad]
  }
  deriving (Eq, Show)

describirHorario :: ContextoHorario -> [UbicacionSesion] -> Horario -> DetalleHorario
describirHorario contexto previas horario =
  DetalleHorario vigente (validarHorario contexto previas datos) (diagnosticarPendientes contexto datos)
    (avisosVigentes contexto vigente)
  where
    almacenado = datosHorario horario
    datos = almacenado { sinAsignar = sesionesPendientes contexto (asignaciones almacenado) }
    vigente = horario { datosHorario = datos }

avisosVigentes :: ContextoHorario -> Horario -> [AvisoDisponibilidad]
avisosVigentes contexto horario =
  [ AvisoDisponibilidad (horarioId horario) u
  | estadoHorario datos == Publicado
  , a <- asignaciones datos
  , let u = ubicacion a
  , Just sesion <- [Map.lookup (sesionUbicada u) catalogo]
  , Just franjas <- [Map.lookup (profesorAsignado u) disponibilidad]
  , not (cubreFranja franjas (franjaSesion sesion u))
  ]
  where
    datos = datosHorario horario
    periodo = periodoConfiguracion (configuracionHorario datos)
    catalogo = Map.fromList [(sesionId s, s) | (_, s) <- sesionesDelPeriodo contexto]
    disponibilidad = Map.map normalizarFranjas $ Map.fromListWith (++)
      [ (profesorDisponible d, franjasDisponibles d)
      | d <- disponibilidades contexto, periodoDisponible d == periodo ]

dividirBase :: [Asignacion] -> ([Asignacion], [Asignacion])
dividirBase = foldr seleccionar ([], [])
  where
    seleccionar asignada (conservar, mover)
      | origenAsignacion asignada == AsignacionManual || fijada asignada = (asignada : conservar, mover)
      | otherwise = (conservar, asignada : mover)

crearHorarioVacio :: Monad m => Repositorio m -> PeriodoId -> m (Either ErrorCasoUso DetalleHorario)
crearHorarioVacio repo periodo = runExceptT $ do
  contexto <- cargarContextoValidado repo periodo
  let nuevo = DatosHorario (configuracion contexto) Borrador HorarioManual Nothing [] (sesionesPendientes contexto [])
  guardados <- desdeRepositorio (guardarBorradores repo (nuevo :| []))
  pure (describirHorario contexto [] (NE.head guardados))

consultarHorario :: Monad m => Repositorio m -> HorarioId -> m (Either ErrorCasoUso DetalleHorario)
consultarHorario repo identificador = runExceptT $ do
  (horario, contexto, previas) <- cargarDetalle repo identificador
  pure (describirHorario contexto previas horario)

editarHorario
  :: Monad m
  => Repositorio m
  -> HorarioId
  -> AplicacionCambio
  -> NonEmpty CambioHorario
  -> m (Either ErrorCasoUso DetalleHorario)
editarHorario repo identificador aplicacion cambios = runExceptT $ do
  (horario, contexto, previas) <- cargarDetalle repo identificador
  let actuales = datosHorario horario
  unless (estadoHorario actuales == Borrador) $
    throwE (OperacionInvalida "Solo se puede editar un borrador.")
  modificadas <- foldM aplicar (asignaciones actuales) cambios
  let nuevos = actuales { asignaciones = modificadas, sinAsignar = sesionesPendientes contexto modificadas }
      resultado = describirHorario contexto previas (horario { datosHorario = nuevos })
  verificarEstructura (evaluacion resultado)
  case aplicacion of
    Simular -> pure resultado
    Guardar -> do
      guardado <- desdeRepositorio (actualizarHorario repo identificador actuales nuevos)
      pure (describirHorario contexto previas guardado)

publicarHorario :: Monad m => Repositorio m -> HorarioId -> m (Either ErrorCasoUso DetalleHorario)
publicarHorario repo identificador = runExceptT $ do
  (horario, contexto, previas) <- cargarDetalle repo identificador
  let detalle = describirHorario contexto previas horario
      actuales = datosHorario horario
      vista = datosHorario (horarioDetallado detalle)
      resultado = evaluacion detalle
  case estadoHorario actuales of
    Publicado -> pure detalle
    Borrador -> do
      verificarEstructura resultado
      unless (null (violacionesDuras resultado) && null (sinAsignar vista)) $
        throwE (PublicacionInvalida (violacionesDuras resultado) (sinAsignar vista))
      publicado <- desdeRepositorio (actualizarHorario repo identificador actuales (vista { estadoHorario = Publicado }))
      pure (describirHorario contexto previas publicado)

cargarDetalle
  :: Monad m => Repositorio m -> HorarioId -> ResultadoCasoUso m (Horario, ContextoHorario, [UbicacionSesion])
cargarDetalle repo identificador = do
  horario <- desdeRepositorio (buscarHorario repo identificador)
  let datos = datosHorario horario
  contexto <- cargarContextoValidado repo (periodoConfiguracion (configuracionHorario datos))
  previas <- case (origenHorario datos, baseHorarioId datos) of
    (HorarioRegenerado _ ConservarCambios, Just baseId) -> do
      base <- desdeRepositorio (buscarHorario repo baseId)
      pure (map ubicacion (snd (dividirBase (asignaciones (datosHorario base)))))
    _ -> pure []
  pure (horario, contexto, previas)

verificarEstructura :: Monad m => EvaluacionHorario -> ResultadoCasoUso m ()
verificarEstructura resultado =
  unless (null problemas) (throwE (EntradaInvalida problemas))
  where
    problemas = problemasEstructurales resultado

aplicar :: Monad m => [Asignacion] -> CambioHorario -> ResultadoCasoUso m [Asignacion]
aplicar existentes cambio =
  case cambio of
    CrearAsignacion nueva -> do
      when (any (coincide (sesionUbicada nueva)) existentes) $
        throwE (OperacionInvalida "La sesión ya está asignada.")
      pure (existentes ++ [Asignacion nueva False AsignacionManual])
    MoverAsignacion nueva ->
      sobre (sesionUbicada nueva) $ \actual ->
        Just (actual { ubicacion = nueva, origenAsignacion = AsignacionManual })
    BorrarAsignacion sesion -> sobre sesion (const Nothing)
    FijarAsignacion sesion valor -> sobre sesion (\actual -> Just (actual { fijada = valor }))
  where
    coincide buscada = (== buscada) . sesionUbicada . ubicacion
    sobre sesion transformar =
      case find (coincide sesion) existentes of
        Nothing -> throwE (OperacionInvalida "La sesión todavía no tiene una asignación.")
        Just actual -> pure (concatMap (reemplazar sesion (transformar actual)) existentes)
    reemplazar sesion nuevo actual
      | coincide sesion actual = maybe [] pure nuevo
      | otherwise = [actual]
