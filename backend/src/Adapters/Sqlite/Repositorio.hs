{-# LANGUAGE OverloadedStrings #-}

-- | Implementación SQLite del puerto 'Repositorio' de M2 (M3).
-- No contiene lógica de dominio: solo lee y escribe. Las operaciones que el puerto declara
-- atómicas se ejecutan en una sola transacción.
module Adapters.Sqlite.Repositorio
  ( repositorioSqlite
  , leerContexto
  , leerConfiguracion
  , leerHorario
  , leerFranjasHorarioDocente
  , protegido
  , DatoCorrupto (..)
  ) where

import Adapters.Sqlite.Codificacion
import Adapters.Sqlite.Conexion
import Control.Exception (Exception, SomeAsyncException, SomeException, fromException, throwIO, toException, try)
import Control.Monad (forM, forM_, when)
import Data.Aeson (eitherDecodeStrict, encode)
import Data.Aeson.Types (parseEither)
import qualified Data.ByteString.Lazy as BL
import Data.List.NonEmpty (NonEmpty)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TE
import Database.SQLite.Simple
import Domain.Tipos
import UseCases.Repositorio

-- | Un valor guardado no se puede traducir al dominio (por ejemplo, un día fuera de rango).
newtype DatoCorrupto = DatoCorrupto Text
  deriving (Show)

instance Exception DatoCorrupto

repositorioSqlite :: BaseDatos -> Repositorio IO
repositorioSqlite bd = Repositorio
  { cargarContexto = \periodo -> protegido $ conConexion bd $ \c ->
      maybe (Left RegistroNoEncontrado) Right <$> leerContexto c periodo
  , buscarHorario = \identificador -> protegido $ conConexion bd $ \c ->
      maybe (Left RegistroNoEncontrado) (Right . Horario identificador) <$> leerHorario c identificador
  , listarPublicados = \(PeriodoId p) -> protegido $ conConexion bd $ \c -> do
      ids <- query c "SELECT id FROM horarios WHERE periodo_id = ? AND estado = 'publicado' ORDER BY id" (Only p)
      horarios <- forM ids $ \(Only h) -> fmap (Horario (HorarioId h)) <$> leerHorario c (HorarioId h)
      pure (Right [h | Just h <- horarios])
  , guardarBorradores = \borradores -> protegido $ enTransaccion bd $ \c -> do
      momento <- ahoraIso
      Right <$> traverse (insertarHorario c momento) (borradores :: NonEmpty DatosHorario)
  , actualizarHorario = \identificador esperado nuevo -> protegido $ enTransaccion bd $ \c -> do
      actual <- leerHorario c identificador
      case actual of
        Nothing -> pure (Left RegistroNoEncontrado)
        Just datos
          | datos /= esperado -> pure (Left CambioConcurrente)
          | otherwise -> do
              momento <- ahoraIso
              reescribirHorario c momento identificador nuevo
              pure (Right (Horario identificador nuevo))
  , guardarDisponibilidad = \disponible avisos -> protegido $ enTransaccion bd $ \c -> do
      let ProfesorId profesor = profesorDisponible disponible
          PeriodoId periodo = periodoDisponible disponible
      execute c "INSERT OR IGNORE INTO disponibilidades (profesor_id, periodo_id) VALUES (?, ?)" (profesor, periodo)
      execute c "DELETE FROM disponibilidad_franjas WHERE profesor_id = ? AND periodo_id = ?" (profesor, periodo)
      forM_ (zip [0 :: Int ..] (franjasDisponibles disponible)) $ \(orden, Franja d (Intervalo i f)) ->
        execute c
          "INSERT INTO disponibilidad_franjas (profesor_id, periodo_id, orden, dia, inicio_min, fin_min) VALUES (?, ?, ?, ?, ?, ?)"
          (profesor, periodo, orden, diaAEntero d, i, f)
      momento <- ahoraIso
      forM_ avisos $ \(AvisoDisponibilidad (HorarioId h) u) ->
        execute c
          "INSERT INTO avisos (horario_id, sesion_id, profesor_id, aula_id, dia, inicio_min, creado_en) VALUES (?, ?, ?, ?, ?, ?, ?)"
          (h, idSesion (sesionUbicada u), idProfesor (profesorAsignado u), idAula (aulaAsignada u),
           diaAEntero (diaAsignado u), inicioAsignadoMin u, momento)
      pure (Right ())
  , guardarHorarioDocente = \propuesta -> protegido $ enTransaccion bd $ \c -> do
      existente <- buscarHorarioDocente c propuesta Propuesto
      identificador <- case existente of
        Just h -> do
          execute c "DELETE FROM horario_docente_franjas WHERE horario_docente_id = ?" (Only h)
          pure h
        Nothing -> do
          let (profesor, curso, periodo) = claveDocente propuesta
          execute c
            "INSERT INTO horarios_docentes (profesor_id, curso_id, periodo_id, estado) VALUES (?, ?, ?, 'propuesto')"
            (profesor, curso, periodo)
          fromIntegral <$> lastInsertRowId c
      escribirFranjasDocente c identificador (franjasDelHorarioDocente propuesta)
      pure (Right ())
  , aprobarHorarioDocente = \propuesta -> protegido $ enTransaccion bd $ \c -> do
      pendiente <- buscarHorarioDocente c propuesta Propuesto
      case pendiente of
        Nothing -> pure (Left CambioConcurrente)
        Just h -> do
          franjas <- leerFranjasHorarioDocente c h
          if franjas /= franjasDelHorarioDocente propuesta
            then pure (Left CambioConcurrente)
            else do
              let (profesor, curso, periodo) = claveDocente propuesta
              execute c
                "DELETE FROM horarios_docentes WHERE profesor_id = ? AND curso_id = ? AND periodo_id = ? AND estado = 'aprobado'"
                (profesor, curso, periodo)
              execute c "UPDATE horarios_docentes SET estado = 'aprobado' WHERE id = ?" (Only h)
              execute c "INSERT OR IGNORE INTO profesor_cursos (profesor_id, curso_id) VALUES (?, ?)" (profesor, curso)
              pure (Right ())
  , cerrarSesion = \(PeriodoId periodo) (SesionId sesion) -> protegido $ enTransaccion bd $ \c -> do
      existe <- query c
        "SELECT se.id FROM sesiones se JOIN secciones s ON s.id = se.seccion_id WHERE se.id = ? AND s.periodo_id = ?"
        (sesion, periodo) :: IO [Only Int]
      if null existe
        then pure (Left RegistroNoEncontrado)
        else do
          execute c "UPDATE sesiones SET cerrada = 1 WHERE id = ?" (Only sesion)
          execute c "DELETE FROM asignaciones WHERE sesion_id = ?" (Only sesion)
          execute c "DELETE FROM horario_sin_asignar WHERE sesion_id = ?" (Only sesion)
          pure (Right ())
  }

-- | Convierte excepciones de SQLite o de datos corruptos en 'FalloPersistencia'.
-- Las excepciones asíncronas (cancelación de hilos) se vuelven a lanzar.
protegido :: IO (Either ErrorRepositorio a) -> IO (Either ErrorRepositorio a)
protegido accion = do
  r <- try accion
  case r of
    Right valor -> pure valor
    Left e
      | Just (_ :: SomeAsyncException) <- fromException e -> throwIO e
      | Just (DatoCorrupto t) <- fromException e -> pure (Left (FalloPersistencia t))
      | otherwise -> pure (Left (FalloPersistencia (detalleSqlite (toException (e :: SomeException)))))

corrupto :: Text -> IO a
corrupto = throwIO . DatoCorrupto

diaSeguro :: Int -> IO Dia
diaSeguro n = maybe (corrupto ("Día inválido en la base: " <> Text.pack (show n))) pure (diaDeEntero n)

idSesion :: SesionId -> Int
idSesion (SesionId s) = s

idProfesor :: ProfesorId -> Int
idProfesor (ProfesorId p) = p

idAula :: AulaId -> Int
idAula (AulaId a) = a

claveDocente :: HorarioDocente -> (Int, Int, Int)
claveDocente h =
  ( idProfesor (profesorDelHorarioDocente h)
  , let CursoId c = cursoDelHorarioDocente h in c
  , let PeriodoId p = periodoDelHorarioDocente h in p
  )

buscarHorarioDocente :: Connection -> HorarioDocente -> EstadoAprobacion -> IO (Maybe Int)
buscarHorarioDocente c h estado = do
  let (profesor, curso, periodo) = claveDocente h
  filas <- query c
    "SELECT id FROM horarios_docentes WHERE profesor_id = ? AND curso_id = ? AND periodo_id = ? AND estado = ?"
    (profesor, curso, periodo, estadoAprobacionTexto estado)
  pure (case filas of
    Only i : _ -> Just i
    [] -> Nothing)

escribirFranjasDocente :: Connection -> Int -> [Franja] -> IO ()
escribirFranjasDocente c identificador franjas =
  forM_ (zip [0 :: Int ..] franjas) $ \(orden, Franja d (Intervalo i f)) ->
    execute c
      "INSERT INTO horario_docente_franjas (horario_docente_id, orden, dia, inicio_min, fin_min) VALUES (?, ?, ?, ?, ?)"
      (identificador, orden, diaAEntero d, i, f)

leerFranjasHorarioDocente :: Connection -> Int -> IO [Franja]
leerFranjasHorarioDocente c identificador = do
  filas <- query c
    "SELECT dia, inicio_min, fin_min FROM horario_docente_franjas WHERE horario_docente_id = ? ORDER BY orden"
    (Only identificador)
  forM filas $ \(d, i, f) -> (\dd -> Franja dd (Intervalo i f)) <$> diaSeguro d

-- | Configuración del período, o 'Nothing' si no existe.
leerConfiguracion :: Connection -> PeriodoId -> IO (Maybe Configuracion)
leerConfiguracion c (PeriodoId p) = do
  filas <- query c
    "SELECT inicio_dia_min, fin_dia_min, turno_min, peso_hueco, peso_piso, peso_edificio, peso_estabilidad, \
    \tolerancia_hueco_min, consecutivo_max_min, timeout_seg FROM configuraciones WHERE periodo_id = ?"
    (Only p)
  case filas of
    [] -> pure Nothing
    (inicio, fin, turnoN, hueco, pisoP, edificioP, estabilidad, tolerancia, consecutivo, tiempo) : _ -> do
      t <- maybe (corrupto "Turno inválido en la base.") pure (turnoDeEntero turnoN)
      dias <- query c "SELECT dia FROM configuracion_dias WHERE periodo_id = ? ORDER BY orden" (Only p)
      diasDominio <- mapM (diaSeguro . fromOnly) dias
      rs <- query c "SELECT inicio_min, fin_min FROM configuracion_recesos WHERE periodo_id = ? ORDER BY orden" (Only p)
      pure (Just (Configuracion (PeriodoId p) diasDominio (Intervalo inicio fin) t
        [Intervalo i f | (i, f) <- rs] (Pesos hueco pisoP edificioP estabilidad) tolerancia consecutivo tiempo))

-- | Contexto completo del período, o 'Nothing' si el período no tiene configuración.
-- Las sesiones cerradas no forman parte del contexto.
leerContexto :: Connection -> PeriodoId -> IO (Maybe ContextoHorario)
leerContexto c periodo@(PeriodoId p) = do
  configuracionPeriodo <- leerConfiguracion c periodo
  case configuracionPeriodo of
    Nothing -> pure Nothing
    Just config -> do
      habilitaciones <- query_ c "SELECT profesor_id, curso_id FROM profesor_cursos ORDER BY profesor_id, curso_id"
      let cursosDe = Map.fromListWith (flip (++)) [(pr, [CursoId cu]) | (pr, cu) <- habilitaciones :: [(Int, Int)]]
      filasProfesores <- query_ c "SELECT id, nombre, categoria_id FROM profesores ORDER BY id"
      let docentes =
            [ Profesor (ProfesorId i) nombre (CategoriaId cat) (Map.findWithDefault [] i cursosDe)
            | (i, nombre, cat) <- filasProfesores ]
      registrados <- query c "SELECT profesor_id FROM disponibilidades WHERE periodo_id = ? ORDER BY profesor_id" (Only p)
      filasFranjas <- query c
        "SELECT profesor_id, dia, inicio_min, fin_min FROM disponibilidad_franjas WHERE periodo_id = ? ORDER BY profesor_id, orden"
        (Only p)
      franjasPorProfesor <- agrupar <$> forM filasFranjas (\(pr, d, i, f) -> do
        dd <- diaSeguro d
        pure (pr :: Int, Franja dd (Intervalo i f)))
      let generales =
            [ Disponibilidad (ProfesorId pr) periodo (Map.findWithDefault [] pr franjasPorProfesor)
            | Only pr <- registrados ]
      filasDocentes <- query c
        "SELECT id, profesor_id, curso_id, estado FROM horarios_docentes WHERE periodo_id = ? ORDER BY id" (Only p)
      docentesHorario <- forM filasDocentes $ \(h, pr, cu, estadoT) -> do
        estado <- maybe (corrupto "Estado de aprobación inválido.") pure (estadoAprobacionDeTexto estadoT)
        franjas <- leerFranjasHorarioDocente c h
        pure (HorarioDocente (ProfesorId pr) (CursoId cu) periodo franjas estado)
      filasAulas <- query_ c "SELECT id, codigo, capacidad, edificio, piso, tipo FROM aulas ORDER BY id"
      let salas = [Aula (AulaId i) cod cap edif pisoA tipo | (i, cod, cap, edif, pisoA, tipo) <- filasAulas]
      filasCursos <- query_ c "SELECT id, codigo, nombre, categoria_id FROM cursos ORDER BY id"
      let materias = [Curso (CursoId i) cod nom (CategoriaId cat) | (i, cod, nom, cat) <- filasCursos]
      filasGrupos <- query c
        "SELECT g.seccion_id, g.grupo_id FROM seccion_grupos g JOIN secciones s ON s.id = g.seccion_id \
        \WHERE s.periodo_id = ? ORDER BY g.seccion_id, g.grupo_id" (Only p)
      let gruposDe = agrupar [(s, GrupoId g) | (s, g) <- filasGrupos :: [(Int, Int)]]
      filasSesiones <- query c
        "SELECT se.seccion_id, se.id, se.duracion_min, se.tipo_aula FROM sesiones se \
        \JOIN secciones s ON s.id = se.seccion_id WHERE s.periodo_id = ? AND se.cerrada = 0 \
        \ORDER BY se.seccion_id, se.orden, se.id" (Only p)
      let sesionesDe = agrupar [(s, Sesion (SesionId i) dur tipo) | (s, i, dur, tipo) <- filasSesiones :: [(Int, Int, Int, Text)]]
      filasSecciones <- query c
        "SELECT id, curso_id, codigo, matriculados FROM secciones WHERE periodo_id = ? ORDER BY id" (Only p)
      let seccionesPeriodo =
            [ Seccion (SeccionId s) (CursoId cu) periodo cod mat
                (Map.findWithDefault [] s gruposDe) (Map.findWithDefault [] s sesionesDe)
            | (s, cu, cod, mat) <- filasSecciones ]
      pure (Just (ContextoHorario config docentes generales docentesHorario salas materias seccionesPeriodo))
  where
    agrupar :: Ord k => [(k, v)] -> Map.Map k [v]
    agrupar pares = Map.fromListWith (flip (++)) [(k, [v]) | (k, v) <- pares]

-- | Datos de un horario guardado, o 'Nothing' si no existe.
leerHorario :: Connection -> HorarioId -> IO (Maybe DatosHorario)
leerHorario c (HorarioId h) = do
  filas <- query c
    "SELECT estado, origen, numero_version, politica, base_horario_id, configuracion_json FROM horarios WHERE id = ?"
    (Only h)
  case filas of
    [] -> pure Nothing
    (estadoT, origenT, version, politica, base, configT) : _ -> do
      estado <- maybe (corrupto "Estado de horario inválido.") pure (estadoHorarioDeTexto estadoT)
      origen <- maybe (corrupto "Origen de horario inválido.") pure (origenDePlano (OrigenPlano origenT version politica))
      config <- either (corrupto . Text.pack) pure
        (eitherDecodeStrict (TE.encodeUtf8 configT) >>= parseEither configuracionDeJson)
      filasAsignaciones <- query c
        "SELECT sesion_id, profesor_id, aula_id, dia, inicio_min, fijada, origen FROM asignaciones \
        \WHERE horario_id = ? ORDER BY orden" (Only h)
      asignadas <- forM filasAsignaciones $ \(s, pr, a, d, i, fij, origenA) -> do
        dd <- diaSeguro d
        o <- maybe (corrupto "Origen de asignación inválido.") pure (origenAsignacionDeTexto origenA)
        pure (Asignacion (UbicacionSesion (SesionId s) (ProfesorId pr) (AulaId a) dd i) fij o)
      pendientes <- query c "SELECT sesion_id FROM horario_sin_asignar WHERE horario_id = ? ORDER BY orden" (Only h)
      pure (Just (DatosHorario config estado origen (HorarioId <$> base) asignadas [SesionId s | Only s <- pendientes]))

insertarHorario :: Connection -> Text -> DatosHorario -> IO Horario
insertarHorario c momento datos = do
  let PeriodoId p = periodoConfiguracion (configuracionHorario datos)
      OrigenPlano origenT version politica = origenAPlano (origenHorario datos)
  execute c
    "INSERT INTO horarios (periodo_id, estado, origen, numero_version, politica, base_horario_id, configuracion_json, \
    \creado_en, actualizado_en) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
    ( p, estadoHorarioTexto (estadoHorario datos), origenT, version, politica
    , (\(HorarioId b) -> b) <$> baseHorarioId datos, configuracionTexto (configuracionHorario datos), momento, momento )
  identificador <- HorarioId . fromIntegral <$> lastInsertRowId c
  escribirContenido c identificador datos
  pure (Horario identificador datos)

reescribirHorario :: Connection -> Text -> HorarioId -> DatosHorario -> IO ()
reescribirHorario c momento identificador@(HorarioId h) datos = do
  let OrigenPlano origenT version politica = origenAPlano (origenHorario datos)
  execute c
    "UPDATE horarios SET estado = ?, origen = ?, numero_version = ?, politica = ?, base_horario_id = ?, \
    \configuracion_json = ?, actualizado_en = ? WHERE id = ?"
    ( estadoHorarioTexto (estadoHorario datos), origenT, version, politica
    , (\(HorarioId b) -> b) <$> baseHorarioId datos, configuracionTexto (configuracionHorario datos), momento, h )
  execute c "DELETE FROM asignaciones WHERE horario_id = ?" (Only h)
  execute c "DELETE FROM horario_sin_asignar WHERE horario_id = ?" (Only h)
  escribirContenido c identificador datos

escribirContenido :: Connection -> HorarioId -> DatosHorario -> IO ()
escribirContenido c (HorarioId h) datos = do
  forM_ (zip [0 :: Int ..] (asignaciones datos)) $ \(orden, Asignacion u fij origen) ->
    execute c
      "INSERT INTO asignaciones (horario_id, orden, sesion_id, profesor_id, aula_id, dia, inicio_min, fijada, origen) \
      \VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
      ( h, orden, idSesion (sesionUbicada u), idProfesor (profesorAsignado u), idAula (aulaAsignada u)
      , diaAEntero (diaAsignado u), inicioAsignadoMin u, fij, origenAsignacionTexto origen )
  let pendientes = sinAsignar datos
  when (not (null pendientes)) $
    forM_ (zip [0 :: Int ..] pendientes) $ \(orden, SesionId s) ->
      execute c "INSERT INTO horario_sin_asignar (horario_id, orden, sesion_id) VALUES (?, ?, ?)" (h, orden, s)

configuracionTexto :: Configuracion -> Text
configuracionTexto = TE.decodeUtf8 . BL.toStrict . encode . configuracionAJson

