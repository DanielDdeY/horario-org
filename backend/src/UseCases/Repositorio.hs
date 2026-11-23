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
  -- Guarda la propuesta pendiente y conserva la aprobación vigente.
  , guardarHorarioDocente :: HorarioDocente -> m (Either ErrorRepositorio ())
  -- Verifica que siga pendiente y registra su aprobación y la habilitación del curso en una operación.
  , aprobarHorarioDocente :: HorarioDocente -> m (Either ErrorRepositorio ())
  -- Cierra la sesión y retira sus referencias a horarios en una operación.
  , cerrarSesion :: PeriodoId -> SesionId -> m (Either ErrorRepositorio ())
  }
