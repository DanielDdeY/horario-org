module UseCases.Solver
  ( DisponibilidadAprobada (..)
  , RestriccionAsignacion (..)
  , SolicitudSolver (..)
  , EstadoSolucion (..)
  , SolucionSolver (..)
  , ResultadoSolver (..)
  , Solver (..)
  ) where

import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text)
import Domain.Tipos

-- Profesor habilitado para este curso y franjas aprobadas para esta búsqueda.
data DisponibilidadAprobada = DisponibilidadAprobada
  { profesorHabilitado :: ProfesorId
  , cursoHabilitado :: CursoId
  , franjasAprobadas :: [Franja]
  }
  deriving (Eq, Show)

data RestriccionAsignacion = RestriccionAsignacion
  { sesionRestringida :: SesionId
  , profesorRestringido :: Maybe ProfesorId
  , aulaRestringida :: Maybe AulaId
  , diaRestringido :: Maybe Dia
  , inicioRestringidoMin :: Maybe Int
  }
  deriving (Eq, Show)

data SolicitudSolver = SolicitudSolver
  { configuracionSolver :: Configuracion
  , disponibilidadesAprobadas :: [DisponibilidadAprobada]
  , aulasSolver :: [Aula]
  , seccionesSolver :: [Seccion]
  -- Las asignaciones conservadas existen y mantienen todos sus campos de ubicación.
  , asignacionesConservadas :: [UbicacionSesion]
  , restriccionesParciales :: [RestriccionAsignacion]
  , asignacionesPrevias :: [UbicacionSesion]
  , hastaVersionSolver :: NumeroVersion
  }
  deriving (Eq, Show)

data EstadoSolucion = Optimo | Factible
  deriving (Eq, Show)

data SolucionSolver = SolucionSolver
  { estadoSolucion :: EstadoSolucion
  , costoBlando :: Integer
  , sesionesUbicadas :: [UbicacionSesion]
  , sesionesSinUbicar :: [SesionId]
  }
  deriving (Eq, Show)

data ResultadoSolver
  = SolucionesEncontradas (NonEmpty SolucionSolver) Int
  | TiempoAgotado Int
  | ErrorMotor Text
  deriving (Eq, Show)

newtype Solver m = Solver
  { resolver :: SolicitudSolver -> m ResultadoSolver
  }
