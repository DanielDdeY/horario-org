module UseCases.Repositorio
  ( ErrorRepositorio (..)
  , Repositorio (..)
  ) where

import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text)
import Domain.Tipos

data ErrorRepositorio
  = RegistroNoEncontrado
  | CambioConcurrente
  | FalloPersistencia Text
  deriving (Eq, Show)

data Repositorio m = Repositorio
  { cargarContexto :: PeriodoId -> m (Either ErrorRepositorio ContextoHorario)
  , buscarHorario :: HorarioId -> m (Either ErrorRepositorio Horario)
  , listarPublicados :: PeriodoId -> m (Either ErrorRepositorio [Horario])
  -- Inserta los borradores juntos y devuelve sus identificadores en el mismo orden.
  , guardarBorradores :: NonEmpty DatosHorario -> m (Either ErrorRepositorio (NonEmpty Horario))
  -- Recibe primero el estado esperado y luego el nuevo.
  , actualizarHorario :: HorarioId -> DatosHorario -> DatosHorario -> m (Either ErrorRepositorio Horario)
  -- La disponibilidad y los avisos se persisten juntos.
  , guardarDisponibilidad :: Disponibilidad -> [AvisoDisponibilidad] -> m (Either ErrorRepositorio ())
  , guardarHorarioDocente :: HorarioDocente -> m (Either ErrorRepositorio ())
  -- Al aprobar se registra también que el profesor puede dictar el curso.
  , aprobarHorarioDocente :: HorarioDocente -> m (Either ErrorRepositorio ())
  -- Cierra la sesión y retira sus referencias a horarios en una operación.
  , cerrarSesion :: PeriodoId -> SesionId -> m (Either ErrorRepositorio ())
  }
