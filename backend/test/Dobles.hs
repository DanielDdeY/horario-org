module Dobles
  ( Memoria (..)
  , repositorioEnMemoria
  , solverFalso
  ) where

import Control.Monad.Trans.State.Strict (State, gets, state)
import Data.List.NonEmpty (NonEmpty)
import qualified Data.List.NonEmpty as NE
import qualified Data.Map.Strict as Map
import Domain.Tipos
import UseCases.Repositorio
import UseCases.Solver

data Memoria = Memoria
  { contextosMemoria :: Map.Map PeriodoId ContextoHorario
  , horariosMemoria :: Map.Map HorarioId Horario
  , avisosMemoria :: [AvisoDisponibilidad]
  }
  deriving (Eq, Show)

repositorioEnMemoria :: Repositorio (State Memoria)
repositorioEnMemoria = Repositorio
  { cargarContexto = \periodo -> gets (buscar periodo . contextosMemoria)
  , buscarHorario = \identificador -> gets (buscar identificador . horariosMemoria)
  , listarPublicados = \periodo -> gets (Right . filter (publicado periodo) . Map.elems . horariosMemoria)
  , guardarBorradores = insertar
  , actualizarHorario = actualizar
  , guardarDisponibilidad = \disponible avisos -> modificarPeriodo (periodoDisponible disponible) $ \contexto memoria ->
      let mismo d = profesorDisponible d == profesorDisponible disponible &&
                    periodoDisponible d == periodoDisponible disponible
          cambiado = contexto { disponibilidades = disponible : filter (not . mismo) (disponibilidades contexto) }
      in Right (cambiado, memoria { avisosMemoria = avisosMemoria memoria ++ avisos })
  , guardarHorarioDocente = \propuesto -> modificarPeriodo (periodoDelHorarioDocente propuesto) $ \contexto memoria ->
      Right (reemplazarDocente propuesto contexto, memoria)
  , aprobarHorarioDocente = \propuesto -> modificarPeriodo (periodoDelHorarioDocente propuesto) $ \contexto memoria ->
      if propuesto `elem` horariosDocentes contexto
        then let aprobada = propuesto { estadoAprobacion = Aprobado }
                 revisado = reemplazarDocente aprobada contexto
                 sinPropuesta = filter (/= propuesto) (horariosDocentes revisado)
             in Right (revisado { horariosDocentes = sinPropuesta
                                , profesores = map (habilitar aprobada) (profesores revisado) }, memoria)
        else Left CambioConcurrente
  , cerrarSesion = \periodo sesion -> modificarPeriodo periodo $ \contexto memoria ->
      let sinSesion seccion
            | periodoSeccion seccion /= periodo = seccion
            | otherwise = seccion { sesiones = filter ((/= sesion) . sesionId) (sesiones seccion) }
      in Right (contexto { secciones = map sinSesion (secciones contexto) },
           memoria { horariosMemoria = Map.map (retirarSesion periodo sesion) (horariosMemoria memoria) })
  }

solverFalso :: Applicative m => ResultadoSolver -> Solver m
solverFalso = Solver . const . pure

buscar :: Ord k => k -> Map.Map k v -> Either ErrorRepositorio v
buscar clave = maybe (Left RegistroNoEncontrado) Right . Map.lookup clave

periodoHorario :: Horario -> PeriodoId
periodoHorario = periodoConfiguracion . configuracionHorario . datosHorario

publicado :: PeriodoId -> Horario -> Bool
publicado periodo horario = periodoHorario horario == periodo && estadoHorario (datosHorario horario) == Publicado

insertar :: NonEmpty DatosHorario -> State Memoria (Either ErrorRepositorio (NonEmpty Horario))
insertar borradores = state $ \memoria ->
  let actuales = horariosMemoria memoria
      ultimo = maybe 0 (\(HorarioId numero, _) -> numero) (Map.lookupMax actuales)
      nuevos = NE.zipWith Horario (fmap HorarioId (NE.iterate (+ 1) (ultimo + 1))) borradores
      insertados = Map.fromList [(horarioId h, h) | h <- NE.toList nuevos]
  in (Right nuevos, memoria { horariosMemoria = Map.union insertados actuales })

actualizar :: HorarioId -> DatosHorario -> DatosHorario -> State Memoria (Either ErrorRepositorio Horario)
actualizar identificador esperado nuevo = state $ \memoria ->
  case buscar identificador (horariosMemoria memoria) of
    Left err -> (Left err, memoria)
    Right actual
      | datosHorario actual /= esperado -> (Left CambioConcurrente, memoria)
      | otherwise ->
          let guardado = actual { datosHorario = nuevo }
          in (Right guardado, memoria { horariosMemoria = Map.insert identificador guardado (horariosMemoria memoria) })

modificarPeriodo
  :: PeriodoId -> (ContextoHorario -> Memoria -> Either ErrorRepositorio (ContextoHorario, Memoria))
  -> State Memoria (Either ErrorRepositorio ())
modificarPeriodo periodo cambiar = state $ \memoria ->
  case buscar periodo (contextosMemoria memoria) >>= (\contexto -> cambiar contexto memoria) of
    Left err -> (Left err, memoria)
    Right (contexto, nueva) ->
      (Right (), nueva { contextosMemoria = Map.insert periodo contexto (contextosMemoria nueva) })

reemplazarDocente :: HorarioDocente -> ContextoHorario -> ContextoHorario
reemplazarDocente nuevo contexto =
  contexto { horariosDocentes = nuevo : filter (not . mismo) (horariosDocentes contexto) }
  where
    clave h = (profesorDelHorarioDocente h, cursoDelHorarioDocente h, periodoDelHorarioDocente h, estadoAprobacion h)
    mismo h = clave h == clave nuevo

habilitar :: HorarioDocente -> Profesor -> Profesor
habilitar aprobado profesor
  | profesorId profesor == profesorDelHorarioDocente aprobado && curso `notElem` cursosAprobados profesor =
      profesor { cursosAprobados = curso : cursosAprobados profesor }
  | otherwise = profesor
  where
    curso = cursoDelHorarioDocente aprobado

retirarSesion :: PeriodoId -> SesionId -> Horario -> Horario
retirarSesion periodo sesion horario
  | periodoHorario horario /= periodo = horario
  | otherwise = horario { datosHorario = datos
      { asignaciones = filter ((/= sesion) . sesionUbicada . ubicacion) (asignaciones datos)
      , sinAsignar = filter (/= sesion) (sinAsignar datos)
      } }
  where
    datos = datosHorario horario
