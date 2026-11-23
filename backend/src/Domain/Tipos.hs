module Domain.Tipos where

import Data.Text (Text)

newtype PeriodoId = PeriodoId Int deriving (Eq, Ord, Show)
newtype ProfesorId = ProfesorId Int deriving (Eq, Ord, Show)
newtype CategoriaId = CategoriaId Int deriving (Eq, Ord, Show)
newtype AulaId = AulaId Int deriving (Eq, Ord, Show)
newtype CursoId = CursoId Int deriving (Eq, Ord, Show)
newtype SeccionId = SeccionId Int deriving (Eq, Ord, Show)
newtype SesionId = SesionId Int deriving (Eq, Ord, Show)
newtype GrupoId = GrupoId Int deriving (Eq, Ord, Show)
newtype HorarioId = HorarioId Int deriving (Eq, Ord, Show)

data Dia
  = Lunes | Martes | Miercoles | Jueves | Viernes | Sabado | Domingo
  deriving (Eq, Ord, Show)

data Turno = Min45 | Min50 | Min60 | Min90
  deriving (Eq, Show)

-- Minutos desde medianoche. El intervalo incluye el inicio y excluye el fin.
data Intervalo = Intervalo
  { inicioMin :: Int
  , finMin :: Int
  }
  deriving (Eq, Show)

data Franja = Franja
  { diaFranja :: Dia
  , intervaloFranja :: Intervalo
  }
  deriving (Eq, Show)

data Pesos = Pesos
  { pesoHueco :: Int
  , pesoPiso :: Int
  , pesoEdificio :: Int
  , pesoEstabilidad :: Int
  }
  deriving (Eq, Show)

data Configuracion = Configuracion
  { periodoConfiguracion :: PeriodoId
  , diasActivos :: [Dia]
  , jornada :: Intervalo
  , turno :: Turno
  , recesos :: [Intervalo]
  , pesos :: Pesos
  , toleranciaHuecoMin :: Int
  , consecutivoMaxMin :: Int
  , timeoutSeg :: Int
  }
  deriving (Eq, Show)

data Categoria = Categoria
  { categoriaId :: CategoriaId
  , nombreCategoria :: Text
  }
  deriving (Eq, Show)

data Profesor = Profesor
  { profesorId :: ProfesorId
  , nombreProfesor :: Text
  , categoriaProfesor :: CategoriaId
  , cursosAprobados :: [CursoId]
  }
  deriving (Eq, Show)

data Disponibilidad = Disponibilidad
  { profesorDisponible :: ProfesorId
  , periodoDisponible :: PeriodoId
  , franjasDisponibles :: [Franja]
  }
  deriving (Eq, Show)

data EstadoAprobacion = Propuesto | Aprobado
  deriving (Eq, Show)

data HorarioDocente = HorarioDocente
  { profesorDelHorarioDocente :: ProfesorId
  , cursoDelHorarioDocente :: CursoId
  , periodoDelHorarioDocente :: PeriodoId
  , franjasDelHorarioDocente :: [Franja]
  , estadoAprobacion :: EstadoAprobacion
  }
  deriving (Eq, Show)

data Aula = Aula
  { aulaId :: AulaId
  , codigoAula :: Text
  , capacidad :: Int
  , edificio :: Text
  , piso :: Int
  , tipoAula :: Text
  }
  deriving (Eq, Show)

data Curso = Curso
  { cursoId :: CursoId
  , codigoCurso :: Text
  , nombreCurso :: Text
  , categoriaCurso :: CategoriaId
  }
  deriving (Eq, Show)

data Sesion = Sesion
  { sesionId :: SesionId
  , duracionMin :: Int
  , tipoAulaRequerida :: Text
  }
  deriving (Eq, Show)

data Seccion = Seccion
  { seccionId :: SeccionId
  , cursoSeccion :: CursoId
  , periodoSeccion :: PeriodoId
  , codigoSeccion :: Text
  , matriculados :: Int
  , grupos :: [GrupoId]
  , sesiones :: [Sesion]
  }
  deriving (Eq, Show)

data UbicacionSesion = UbicacionSesion
  { sesionUbicada :: SesionId
  , profesorAsignado :: ProfesorId
  , aulaAsignada :: AulaId
  , diaAsignado :: Dia
  , inicioAsignadoMin :: Int
  }
  deriving (Eq, Show)

data OrigenAsignacion = AsignacionAutomatica | AsignacionManual
  deriving (Eq, Show)

data Asignacion = Asignacion
  { ubicacion :: UbicacionSesion
  , fijada :: Bool
  , origenAsignacion :: OrigenAsignacion
  }
  deriving (Eq, Show)

data NumeroVersion = Version1 | Version2 | Version3 | Version4
  deriving (Eq, Ord, Show)

data OrigenHorario = HorarioManual | HorarioGenerado NumeroVersion
  deriving (Eq, Show)

data EstadoHorario = Borrador | Publicado
  deriving (Eq, Show)

data DatosHorario = DatosHorario
  { configuracionHorario :: Configuracion
  , estadoHorario :: EstadoHorario
  , origenHorario :: OrigenHorario
  , baseHorarioId :: Maybe HorarioId
  , asignaciones :: [Asignacion]
  , sinAsignar :: [SesionId]
  }
  deriving (Eq, Show)

data Horario = Horario
  { horarioId :: HorarioId
  , datosHorario :: DatosHorario
  }
  deriving (Eq, Show)

data PoliticaCambios = ConservarCambios | DescartarCambios
  deriving (Eq, Show)

data ModoGeneracion
  = GenerarDesdeCero
  | Regenerar HorarioId PoliticaCambios
  | Completar HorarioId
  deriving (Eq, Show)

data SolicitudGeneracion = SolicitudGeneracion
  { periodoSolicitado :: PeriodoId
  , modoGeneracion :: ModoGeneracion
  , hastaVersion :: NumeroVersion
  }
  deriving (Eq, Show)

data ReglaDura = H01 | H02 | H03 | H04 | H05 | H06 | H07 | H08 | H09
  deriving (Eq, Ord, Show)

data ReglaBlanda = S01 | S02 | S07
  deriving (Eq, Ord, Show)

data Violacion = Violacion
  { reglaViolada :: ReglaDura
  , sesionesInvolucradas :: [SesionId]
  , detalleViolacion :: Text
  }
  deriving (Eq, Show)

data MotivoSinAsignar = MotivoSinAsignar
  { sesionPendiente :: SesionId
  , cursoPendiente :: CursoId
  , profesoresConsiderados :: [ProfesorId]
  , reglaDelMotivo :: Maybe ReglaDura
  , detalleMotivo :: Text
  }
  deriving (Eq, Show)

data CostoPorProfesor = CostoPorProfesor
  { profesorDelCosto :: ProfesorId
  , costoPorReglaDelProfesor :: [(ReglaBlanda, Integer)]
  }
  deriving (Eq, Show)

data Puntaje = Puntaje
  { totalBlando :: Integer
  , cantidadSinAsignar :: Int
  , costoPorRegla :: [(ReglaBlanda, Integer)]
  , costoPorProfesor :: [CostoPorProfesor]
  }
  deriving (Eq, Show)

-- Un mismo aviso tiene dos destinatarios: el profesor afectado y el coordinador.
data AvisoDisponibilidad = AvisoDisponibilidad
  { horarioAfectado :: HorarioId
  , claseAfectada :: UbicacionSesion
  }
  deriving (Eq, Show)

data ContextoHorario = ContextoHorario
  { configuracion :: Configuracion
  , profesores :: [Profesor]
  , disponibilidades :: [Disponibilidad]
  , horariosDocentes :: [HorarioDocente]
  , aulas :: [Aula]
  , cursos :: [Curso]
  , secciones :: [Seccion]
  }
  deriving (Eq, Show)
