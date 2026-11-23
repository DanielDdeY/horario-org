{-# LANGUAGE OverloadedStrings #-}

module UseCases.Generacion
  ( VersionGenerada (..)
  , Generacion (..)
  , generarHorarios
  , generarConRestricciones
  ) where

import Control.Monad (unless)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (runExceptT, throwE)
import Data.List (sortOn)
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as NE
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import Domain.Disponibilidad (disponibilidadesPorCurso)
import Domain.Tipos
import Domain.Validador
import UseCases.Errores
import UseCases.Horarios
import UseCases.Repositorio
import UseCases.Solver

data VersionGenerada = VersionGenerada
  { estadoVersion :: EstadoSolucion
  , detalleVersion :: DetalleHorario
  }
  deriving (Eq, Show)

data Generacion = Generacion
  { versionesGeneradas :: NonEmpty VersionGenerada
  , tiempoGeneracionMs :: Int
  }
  deriving (Eq, Show)

generarHorarios
  :: Monad m => Repositorio m -> Solver m -> SolicitudGeneracion -> m (Either ErrorCasoUso Generacion)
generarHorarios repo motor solicitud = generarConRestricciones repo motor solicitud []

generarConRestricciones
  :: Monad m
  => Repositorio m -> Solver m -> SolicitudGeneracion -> [RestriccionAsignacion]
  -> m (Either ErrorCasoUso Generacion)
generarConRestricciones repo motor solicitud restricciones = runExceptT $ do
  contexto <- cargarContextoValidado repo periodo
  (conservadas, previas) <- case modo of
    GenerarDesdeCero -> pure ([], [])
    Regenerar baseId DescartarCambios -> cargarBase baseId >> pure ([], [])
    Regenerar baseId ConservarCambios -> do
      base <- cargarBase baseId
      let (estables, movibles) = dividirBase (asignaciones base)
      pure (estables, map ubicacion movibles)
    Completar baseId -> do
      base <- cargarBase baseId
      pure (asignaciones base, [])
  let config = configuracion contexto
      inicial = armarBorrador contexto Version1 conservadas
      revision = validarHorario contexto previas inicial
      idsPeriodo = Set.fromList (map (sesionId . snd) (sesionesDelPeriodo contexto))
      porSesion = Map.fromList [(sesionUbicada (ubicacion a), a) | a <- conservadas]
      buscar = SolicitudSolver
        { configuracionSolver = config
        , disponibilidadesAprobadas = [DisponibilidadAprobada docente curso horas
                                     | (docente, curso, horas) <- disponibilidadesPorCurso contexto]
        , aulasSolver = aulas contexto
        , seccionesSolver = filter ((== periodo) . periodoSeccion) (secciones contexto)
        , asignacionesConservadas = map ubicacion conservadas
        , restriccionesParciales = restricciones
        , asignacionesPrevias = previas
        , hastaVersionSolver = hastaVersion solicitud
        }
  unless (null (problemasEstructurales revision)) $
    throwE (EntradaInvalida (problemasEstructurales revision))
  unless (null (violacionesDuras revision)) $
    throwE (RestriccionesIncompatibles (violacionesDuras revision))
  unless (validarRestricciones contexto idsPeriodo porSesion) $
    throwE (OperacionInvalida "Las restricciones parciales contienen datos desconocidos o repiten una sesión.")
  respuesta <- if null (sinAsignar inicial)
    then pure (SolucionesEncontradas (SolucionSolver Optimo (totalBlando (puntajeHorario revision))
          (map ubicacion conservadas) [] :| []) 0)
    else lift (resolver motor buscar)
  (soluciones, tiempo) <- case respuesta of
    TiempoAgotado ms -> throwE (MotorAgotoTiempo ms)
    ErrorMotor mensaje -> throwE (MotorFallo mensaje)
    SolucionesEncontradas encontradas ms -> pure (encontradas, ms)
  verificarGrupo soluciones tiempo
  let numeradas = (Version1, NE.head soluciones) :|
        zip [Version2, Version3, Version4] (NE.tail soluciones)
      convertirVersion (numero, solucion) = do
        borrador <- verificarSolucion contexto idsPeriodo porSesion previas numero solucion
        pure (estadoSolucion solucion, borrador)
  preparadas <- traverse convertirVersion numeradas
  guardadas <- desdeRepositorio (guardarBorradores repo (fmap snd preparadas))
  pure (Generacion (NE.zipWith (\(estado, _) h -> VersionGenerada estado (describirHorario contexto previas h))
    preparadas guardadas) tiempo)
  where
    modo = modoGeneracion solicitud
    periodo = periodoSolicitado solicitud
    origen numero = case modo of
      GenerarDesdeCero -> HorarioGenerado numero
      Regenerar _ politica -> HorarioRegenerado numero politica
      Completar _ -> HorarioCompletado numero
    idBase = case modo of
      GenerarDesdeCero -> Nothing
      Regenerar identificador _ -> Just identificador
      Completar identificador -> Just identificador
    cargarBase identificador = do
      base <- datosHorario <$> desdeRepositorio (buscarHorario repo identificador)
      unless (periodoConfiguracion (configuracionHorario base) == periodo) $
        throwE (OperacionInvalida "El horario base pertenece a otro período.")
      pure base
    armarBorrador contexto numero ubicadas = DatosHorario
      (configuracion contexto) Borrador (origen numero) idBase ubicadas (sesionesPendientes contexto ubicadas)
    validarRestricciones contexto idsPeriodo conservadas =
      sinDuplicados (map sesionRestringida restricciones) && all valida restricciones
      where
        docentes = Set.fromList (map profesorId (profesores contexto))
        salas = Set.fromList (map aulaId (aulas contexto))
        valida r = Set.member (sesionRestringida r) idsPeriodo &&
          Map.notMember (sesionRestringida r) conservadas &&
          maybe True (`Set.member` docentes) (profesorRestringido r) &&
          maybe True (`Set.member` salas) (aulaRestringida r) &&
          maybe True (\minuto -> 0 <= minuto && minuto < 1440) (inicioRestringidoMin r)
    verificarGrupo soluciones tiempo = do
      let lista = NE.toList soluciones
          costos = map costoBlando lista
          pendientesPrimera = length (sesionesSinUbicar (NE.head soluciones))
          firmas = map (sortOn sesionUbicada . sesionesUbicadas) lista
          maximo = length (takeWhile (<= hastaVersion solicitud) [Version1, Version2, Version3, Version4])
      exigir (tiempo >= 0 && length lista <= maximo) "Cantidad de versiones o tiempo del motor inválidos."
      exigir (all ((== pendientesPrimera) . length . sesionesSinUbicar) lista) "Las versiones difieren en la cantidad de sesiones asignadas."
      exigir (and (zipWith (<=) costos (drop 1 costos))) "Las versiones no vienen ordenadas por costo."
      exigir (sinDuplicados firmas) "El motor devolvió dos versiones iguales."
    verificarSolucion contexto idsPeriodo conservadas previas numero solucion = do
      let ubicadas = sesionesUbicadas solucion
          idsAsignadas = map sesionUbicada ubicadas
          idsTotales = idsAsignadas ++ sesionesSinUbicar solucion
          ubicadasPorSesion = Map.fromList (zip idsAsignadas ubicadas)
          recupera u = Map.findWithDefault (Asignacion u False AsignacionAutomatica) (sesionUbicada u) conservadas
          borrador = armarBorrador contexto numero (map recupera ubicadas)
          revision = validarHorario contexto previas borrador
      exigir (length idsTotales == Set.size idsPeriodo && Set.fromList idsTotales == idsPeriodo)
        "Cada sesión del período debe aparecer una sola vez, asignada o pendiente."
      exigir (and [Map.lookup s ubicadasPorSesion == Just (ubicacion a) | (s, a) <- Map.toList conservadas])
        "El motor cambió u omitió una asignación que debía conservar."
      exigir (all (respetaRestriccion ubicadasPorSesion) restricciones)
        "El motor asignó una sesión fuera de su restricción parcial."
      exigir (null (problemasEstructurales revision)) "La salida refiere a identificadores desconocidos."
      unless (null (violacionesDuras revision)) $
        throwE (SalidaMotorInvalida "El horario del motor contiene violaciones duras." (violacionesDuras revision))
      exigir (costoBlando solucion == totalBlando (puntajeHorario revision))
        "El costo del motor difiere del puntaje calculado en Haskell."
      pure borrador

respetaRestriccion :: Map.Map SesionId UbicacionSesion -> RestriccionAsignacion -> Bool
respetaRestriccion ubicadas restriccion =
  case Map.lookup (sesionRestringida restriccion) ubicadas of
    Nothing -> True
    Just u -> and
      [ maybe True (== profesorAsignado u) (profesorRestringido restriccion)
      , maybe True (== aulaAsignada u) (aulaRestringida restriccion)
      , maybe True (== diaAsignado u) (diaRestringido restriccion)
      , maybe True (== inicioAsignadoMin u) (inicioRestringidoMin restriccion)
      ]

exigir :: Monad m => Bool -> Text -> ResultadoCasoUso m ()
exigir cumple mensaje = unless cumple (throwE (SalidaMotorInvalida mensaje []))

sinDuplicados :: Eq a => [a] -> Bool
sinDuplicados [] = True
sinDuplicados (primero : resto) = primero `notElem` resto && sinDuplicados resto
