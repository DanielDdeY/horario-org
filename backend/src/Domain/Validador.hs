{-# LANGUAGE OverloadedStrings #-}

module Domain.Validador
  ( CodigoProblema (..)
  , ProblemaHorario (..)
  , EvaluacionHorario (..)
  , validarContexto
  , validarHorario
  , sesionesDelPeriodo
  , sesionesPendientes
  , franjaSesion
  , diagnosticarPendientes
  ) where

import Data.List (sortOn, tails)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import Domain.Disponibilidad
import Domain.Tipos

data CodigoProblema
  = ConfiguracionInvalida
  | IdentificadorInvalido
  | IdentificadorDuplicado
  | ReferenciaInvalida
  | DuracionInvalida
  | DisponibilidadInvalida
  deriving (Eq, Show)

data ProblemaHorario = ProblemaHorario
  { codigoProblema :: CodigoProblema
  , detalleProblema :: Text
  }
  deriving (Eq, Show)

data EvaluacionHorario = EvaluacionHorario
  { problemasEstructurales :: [ProblemaHorario]
  , violacionesDuras :: [Violacion]
  , puntajeHorario :: Puntaje
  }
  deriving (Eq, Show)

sesionesDelPeriodo :: ContextoHorario -> [(Seccion, Sesion)]
sesionesDelPeriodo contexto =
  [ (seccion, sesion)
  | seccion <- secciones contexto
  , periodoSeccion seccion == periodoConfiguracion (configuracion contexto)
  , sesion <- sesiones seccion
  ]

sesionesPendientes :: ContextoHorario -> [Asignacion] -> [SesionId]
sesionesPendientes contexto existentes =
  [ sesionId s | (_, s) <- sesionesDelPeriodo contexto, Set.notMember (sesionId s) idsAsignados ]
  where
    idsAsignados = Set.fromList (map (sesionUbicada . ubicacion) existentes)

minutosTurno :: Turno -> Int
minutosTurno Min45 = 45
minutosTurno Min50 = 50
minutosTurno Min60 = 60
minutosTurno Min90 = 90

mostrar :: Show a => a -> Text
mostrar = Text.pack . show

validarContexto :: ContextoHorario -> [ProblemaHorario]
validarContexto contexto =
  [ ProblemaHorario ConfiguracionInvalida "La jornada, sus días, recesos, pesos o tiempo límite son inválidos."
  | not configValida
  ] ++
  concat
    [ validarIds "profesor" [i | ProfesorId i <- map profesorId docentes]
    , validarIds "curso" [i | CursoId i <- map cursoId materias]
    , validarIds "aula" [i | AulaId i <- map aulaId (aulas contexto)]
    , validarIds "sección" [i | SeccionId i <- map seccionId seccionesPeriodo]
    , validarIds "sesión" [i | SesionId i <- map (sesionId . snd) catalogo]
    ] ++
  [ ProblemaHorario IdentificadorInvalido "Los IDs de período, categoría y grupo deben ser positivos."
  | not idsVinculadosValidos
  ] ++
  [ ProblemaHorario ConfiguracionInvalida "La capacidad y el número de matriculados no pueden ser negativos."
  | any ((< 0) . capacidad) (aulas contexto) || any ((< 0) . matriculados) seccionesPeriodo
  ] ++
  [ ProblemaHorario ReferenciaInvalida ("Curso de sección inexistente: " <> mostrar (cursoSeccion seccion))
  | seccion <- seccionesPeriodo, Set.notMember (cursoSeccion seccion) idsCursos
  ] ++
  [ ProblemaHorario ReferenciaInvalida ("Curso habilitado inexistente: " <> mostrar curso)
  | profesor <- docentes, curso <- cursosAprobados profesor, Set.notMember curso idsCursos
  ] ++
  [ ProblemaHorario DuracionInvalida ("Duración inválida para la sesión " <> mostrar (sesionId sesion))
  | (_, sesion) <- catalogo
  , let duracion = duracionMin sesion
  , duracion <= 0 || duracion > 1440 || duracion `mod` minutosTurno (turno config) /= 0
  ] ++
  concat [ validarFranjas (profesorDisponible d) (franjasDisponibles d)
         | d <- disponibilidades contexto, periodoDisponible d == periodo ] ++
  concat [ validarFranjas (profesorDelHorarioDocente h) (franjasDelHorarioDocente h) ++
           [ ProblemaHorario ReferenciaInvalida ("Curso de horario docente inexistente: " <> mostrar (cursoDelHorarioDocente h))
           | Set.notMember (cursoDelHorarioDocente h) idsCursos ]
         | h <- horariosDocentes contexto, periodoDelHorarioDocente h == periodo ]
  where
    config = configuracion contexto
    periodo@(PeriodoId periodoInt) = periodoConfiguracion config
    docentes = profesores contexto
    materias = cursos contexto
    seccionesPeriodo = filter ((== periodo) . periodoSeccion) (secciones contexto)
    catalogo = sesionesDelPeriodo contexto
    idsDocentes = Set.fromList (map profesorId docentes)
    idsCursos = Set.fromList (map cursoId materias)
    pesosConfig = pesos config
    configValida =
      intervaloValido (jornada config) && not (null (diasActivos config)) &&
      length (diasActivos config) == Set.size (Set.fromList (diasActivos config)) &&
      all intervaloValido (recesos config) && timeoutSeg config > 0 &&
      all (>= 0) [ toleranciaHuecoMin config, consecutivoMaxMin config, pesoHueco pesosConfig
                 , pesoPiso pesosConfig, pesoEdificio pesosConfig, pesoEstabilidad pesosConfig ]
    idsVinculadosValidos = all (> 0) $
      periodoInt :
      [i | CategoriaId i <- map categoriaProfesor docentes ++ map categoriaCurso materias] ++
      [i | GrupoId i <- concatMap grupos seccionesPeriodo]
    validarIds entidad ids =
      [ ProblemaHorario IdentificadorInvalido ("ID de " <> entidad <> " no positivo.") | any (<= 0) ids ] ++
      [ ProblemaHorario IdentificadorDuplicado ("ID de " <> entidad <> " repetido.")
      | length ids /= Set.size (Set.fromList ids) ]
    validarFranjas profesor franjas =
      [ ProblemaHorario ReferenciaInvalida ("Profesor inexistente: " <> mostrar profesor) | Set.notMember profesor idsDocentes ] ++
      [ ProblemaHorario DisponibilidadInvalida ("Intervalo inválido del profesor " <> mostrar profesor)
      | any (not . intervaloValido . intervaloFranja) franjas ]

data Clase = Clase
  { ubicacionClase :: UbicacionSesion
  , seccionClase :: Seccion
  , sesionClase :: Sesion
  , aulaClase :: Aula
  }

franjaSesion :: Sesion -> UbicacionSesion -> Franja
franjaSesion sesion asignada =
  Franja (diaAsignado asignada) (Intervalo inicio (inicio + duracionMin sesion))
  where
    inicio = inicioAsignadoMin asignada

franjaClase :: Clase -> Franja
franjaClase clase = franjaSesion (sesionClase clase) (ubicacionClase clase)

solapados :: Intervalo -> Intervalo -> Bool
solapados a b = inicioMin a < finMin b && inicioMin b < finMin a

respetaJornada :: Configuracion -> Sesion -> Franja -> Bool
respetaJornada config sesion (Franja dia intervalo) =
  intervaloValido intervalo && dia `elem` diasActivos config &&
  inicio >= inicioJornada && finMin intervalo <= finMin (jornada config) &&
  (inicio - inicioJornada) `mod` turnoMin == 0 &&
  duracionMin sesion > 0 && duracionMin sesion `mod` turnoMin == 0 &&
  all (not . solapados intervalo) (recesos config)
  where
    inicio = inicioMin intervalo
    inicioJornada = inicioMin (jornada config)
    turnoMin = minutosTurno (turno config)

armarClases :: ContextoHorario -> [Asignacion] -> ([ProblemaHorario], [Clase])
armarClases contexto existentes = (duplicados ++ faltantes, clases)
  where
    catalogo = Map.fromList [(sesionId sesion, (seccion, sesion)) | (seccion, sesion) <- sesionesDelPeriodo contexto]
    salas = Map.fromList [(aulaId aula, aula) | aula <- aulas contexto]
    idsDocentes = Set.fromList (map profesorId (profesores contexto))
    ubicaciones = map ubicacion existentes
    ids = map sesionUbicada ubicaciones
    duplicados =
      [ ProblemaHorario IdentificadorDuplicado "Una sesión tiene más de una asignación."
      | length ids /= Set.size (Set.fromList ids) ]
    (faltantes, clases) = foldr resolver ([], []) ubicaciones
    resolver asignada (errores, validas) =
      case (Map.lookup (sesionUbicada asignada) catalogo, Map.lookup (aulaAsignada asignada) salas) of
        (Just (seccion, sesion), Just aula) | Set.member (profesorAsignado asignada) idsDocentes ->
          (errores, Clase asignada seccion sesion aula : validas)
        _ -> (ProblemaHorario ReferenciaInvalida
               ("La asignación refiere a una sesión, aula o profesor desconocido: " <> mostrar asignada) : errores, validas)

reglasEntre :: Clase -> Clase -> [(ReglaDura, Text)]
reglasEntre a b
  | diaAsignado ua /= diaAsignado ub = []
  | otherwise =
      [ (H01, "El profesor dicta dos sesiones solapadas.") | cruzan && profesorAsignado ua == profesorAsignado ub ] ++
      [ (H02, "Dos sesiones ocupan el aula a la vez.") | cruzan && aulaAsignada ua == aulaAsignada ub ] ++
      [ (H05, "Dos sesiones de un mismo grupo se solapan.") | cruzan && compartenGrupo ] ++
      [ (H09, "Dos sesiones de la sección se asignaron al mismo día.")
      | seccionId (seccionClase a) == seccionId (seccionClase b) ]
  where
    ua = ubicacionClase a
    ub = ubicacionClase b
    cruzan = solapados (intervaloFranja (franjaClase a)) (intervaloFranja (franjaClase b))
    compartenGrupo = any (`elem` grupos (seccionClase b)) (grupos (seccionClase a))

validarHorario :: ContextoHorario -> [UbicacionSesion] -> DatosHorario -> EvaluacionHorario
validarHorario contexto previas horario = EvaluacionHorario estructurales duras puntaje
  where
    (estructurales, clases) = armarClases contexto (asignaciones horario)
    config = configuracionHorario horario
    aprobacion = Map.fromList [((profesor, curso), franjas) | (profesor, curso, franjas) <- disponibilidadesPorCurso contexto]
    reglasDe clase =
      [ (H03, "La clase queda fuera de la disponibilidad aprobada.")
      | estadoHorario horario /= Publicado && not (cubreFranja franjas (franjaClase clase)) ] ++
      [ (H04, "Los matriculados superan la capacidad del aula.")
      | matriculados seccion > capacidad aula ] ++
      [ (H06, "El profesor no está habilitado para el curso.")
      | Map.notMember clave aprobacion ] ++
      [ (H07, "El tipo de aula no coincide con el requerido.")
      | tipoAula aula /= tipoAulaRequerida sesion ] ++
      [ (H08, "La clase no respeta la jornada, el turno o los recesos.")
      | not (respetaJornada config sesion (franjaClase clase)) ]
      where
        clave = (profesorAsignado (ubicacionClase clase), cursoSeccion seccion)
        franjas = Map.findWithDefault [] clave aprobacion
        seccion = seccionClase clase
        aula = aulaClase clase
        sesion = sesionClase clase
    duras =
      [ Violacion codigo [sesionId (sesionClase clase)] detalle
      | clase <- clases, (codigo, detalle) <- reglasDe clase ] ++
      [ Violacion codigo [sesionId (sesionClase a), sesionId (sesionClase b)] detalle
      | a : resto <- tails clases, b <- resto, (codigo, detalle) <- reglasEntre a b ]
    fijadas = Set.fromList [sesionUbicada (ubicacion a) | a <- asignaciones horario, fijada a]
    comparables = filter ((`Set.notMember` fijadas) . sesionUbicada) previas
    puntaje = calcularPuntaje config comparables clases (length (sesionesPendientes contexto (asignaciones horario)))

calcularPuntaje :: Configuracion -> [UbicacionSesion] -> [Clase] -> Int -> Puntaje
calcularPuntaje config previas clases pendientes =
  Puntaje (sum (map snd porRegla)) pendientes porRegla porProfesor
  where
    codigos = [S01, S02, S07]
    pesosConfig = pesos config
    ubicacionesPrevias = Map.fromList [(sesionUbicada u, u) | u <- previas]
    porDia = Map.fromListWith (++)
      [ ((profesorAsignado u, diaAsignado u), [clase]) | clase <- clases, let u = ubicacionClase clase ]
    porProfesor = [CostoPorProfesor profesor [(codigo, valor codigo costos) | codigo <- codigos]
                  | (profesor, costos) <- Map.toAscList acumulados]
    porRegla = [(codigo, sum [valor codigo costos | costos <- Map.elems acumulados]) | codigo <- codigos]
    acumulados = Map.fromListWith (Map.unionWith (+))
      [ (profesor, costosDia agenda) | ((profesor, _), agenda) <- Map.toList porDia ]
    valor codigo = Map.findWithDefault 0 codigo
    costosDia agenda = Map.fromList
      [ (S01, sum [toInteger (pesoHueco pesosConfig) *
                     max 0 (hueco a b - toInteger (toleranciaHuecoMin config)) | (a, b) <- pares])
      , (S02, sum [traslado a b | (a, b) <- pares, let h = hueco a b
                               , h >= 0 && h <= toInteger (consecutivoMaxMin config)])
      , (S07, sum [toInteger (pesoEstabilidad pesosConfig) | clase <- agenda
               , let u = ubicacionClase clase
               , Just previa <- [Map.lookup (sesionUbicada u) ubicacionesPrevias], previa /= u])
      ]
      where
        orden = sortOn (inicioAsignadoMin . ubicacionClase) agenda
        pares = zip orden (drop 1 orden)
    hueco a b =
      toInteger (inicioAsignadoMin (ubicacionClase b)) -
      toInteger (inicioAsignadoMin (ubicacionClase a)) - toInteger (duracionMin (sesionClase a))
    traslado a b =
      toInteger (pesoPiso pesosConfig) * abs (toInteger (piso (aulaClase a)) - toInteger (piso (aulaClase b))) +
      sum [toInteger (pesoEdificio pesosConfig) | edificio (aulaClase a) /= edificio (aulaClase b)]

diagnosticarPendientes :: ContextoHorario -> DatosHorario -> [MotivoSinAsignar]
diagnosticarPendientes contexto horario =
  [ diagnosticar seccion sesion
  | (seccion, sesion) <- sesionesDelPeriodo contexto, Set.member (sesionId sesion) pendientes ]
  where
    config = configuracionHorario horario
    pendientes = Set.fromList (sesionesPendientes contexto (asignaciones horario))
    (_, existentes) = armarClases contexto (asignaciones horario)
    aprobaciones = disponibilidadesPorCurso contexto
    diagnosticar seccion sesion
      | null elegibles = motivo (Just H06) "Ningún profesor está habilitado para el curso."
      | null franjas = motivo (Just H08) "La sesión no cabe en la jornada y los turnos activos."
      | null docentesConFranja = motivo (Just H03) "Los profesores habilitados carecen de una franja aprobada suficiente."
      | null conCapacidad = motivo (Just H04) "Ningún aula tiene capacidad para los matriculados."
      | null compatibles = motivo (Just H07) "Ningún aula con capacidad es del tipo requerido."
      | any null impedimentos = motivo Nothing "Hay candidatos compatibles. La sesión quedó pendiente en el resultado."
      | otherwise = case foldr1 Set.intersection impedimentos of
          comunes | Set.null comunes -> motivo Nothing "Los candidatos compiten por varios recursos con las sesiones asignadas."
          comunes -> motivo (Set.lookupMin comunes) "Todos los candidatos chocan con sesiones asignadas."
      where
        curso = cursoSeccion seccion
        elegibles = [(profesor, aprobadas) | (profesor, materia, aprobadas) <- aprobaciones, materia == curso]
        motivo regla detalle = MotivoSinAsignar (sesionId sesion) curso (map fst elegibles) regla detalle
        conCapacidad = filter ((>= matriculados seccion) . capacidad) (aulas contexto)
        compatibles = filter ((== tipoAulaRequerida sesion) . tipoAula) conCapacidad
        intervalo = jornada config
        inicio = inicioMin intervalo
        franjas =
          [ franja | intervaloValido intervalo, duracionMin sesion > 0, duracionMin sesion <= 1440
                   , dia <- diasActivos config
                   , minuto <- [inicio, inicio + minutosTurno (turno config) .. finMin intervalo - duracionMin sesion]
                   , let franja = Franja dia (Intervalo minuto (minuto + duracionMin sesion))
                   , respetaJornada config sesion franja ]
        docentesConFranja = [(profesor, franja) | (profesor, disponibles) <- elegibles
                                               , franja <- franjas, cubreFranja disponibles franja]
        impedimentos =
          [ Set.fromList [codigo | establecida <- existentes, (codigo, _) <- reglasEntre candidata establecida]
          | (profesor, Franja dia (Intervalo desde _)) <- docentesConFranja, aula <- compatibles
          , let candidata = Clase (UbicacionSesion (sesionId sesion) profesor (aulaId aula) dia desde) seccion sesion aula ]
