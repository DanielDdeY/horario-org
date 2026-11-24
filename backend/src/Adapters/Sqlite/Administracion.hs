{-# LANGUAGE OverloadedStrings #-}

-- | CRUD administrativo en SQLite (M3): categorías, profesores, aulas, cursos, secciones y sesiones,
-- configuración, listados de horarios, propuestas y avisos.
-- Según `docs/ANTES_DE_DESARROLLAR.md` (reparto del CRUD) esta persistencia es de M3.
-- No aplica reglas del horario: las reglas H01 a H09 y la normalización viven en M2.
module Adapters.Sqlite.Administracion
  ( ErrorAdmin (..)
    -- * Categorías
  , listarCategorias
  , crearCategoria
  , actualizarCategoria
  , borrarCategoria
    -- * Aulas
  , DatosAula (..)
  , listarAulas
  , crearAula
  , actualizarAula
  , borrarAula
    -- * Cursos
  , DatosCurso (..)
  , listarCursos
  , crearCurso
  , actualizarCurso
  , borrarCurso
    -- * Secciones y sesiones
  , SesionRegistro (..)
  , SeccionRegistro (..)
  , DatosSesion (..)
  , DatosSeccion (..)
  , listarSecciones
  , crearSeccion
  , actualizarSeccion
  , borrarSeccion
  , periodoDeSesion
    -- * Profesores
  , ProfesorRegistro (..)
  , listarProfesores
  , buscarProfesorRegistro
  , crearProfesor
  , CambiosProfesor (..)
  , actualizarProfesor
  , borrarProfesor
  , disponibilidadDe
    -- * Propuestas
  , PropuestaRegistro (..)
  , listarPropuestas
  , buscarPropuesta
  , buscarPropuestaPorClave
    -- * Configuración
  , obtenerConfiguracion
  , guardarConfiguracion
  , periodoMasReciente
    -- * Horarios y avisos
  , ResumenHorario (..)
  , listarHorarios
  , AvisoRegistro (..)
  , listarAvisos
  ) where

import Adapters.Sqlite.Codificacion
import Adapters.Sqlite.Conexion
import Adapters.Sqlite.Repositorio (leerConfiguracion, leerFranjasHorarioDocente)
import Control.Exception (SomeAsyncException, SomeException, fromException, throwIO, try)
import Control.Monad (forM, forM_)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes, isJust)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import Database.SQLite.Simple
import Domain.Tipos

data ErrorAdmin
  = NoEncontrado Text
  | Conflicto Text
  | Invalido Text
  | FalloBase Text
  deriving (Eq, Show)

-- | Ejecuta en transacción y traduce las violaciones de restricciones de SQLite en 'Conflicto'.
operar :: BaseDatos -> (Connection -> IO (Either ErrorAdmin a)) -> IO (Either ErrorAdmin a)
operar bd accion = do
  r <- try (enTransaccion bd accion)
  case r of
    Right valor -> pure valor
    Left e
      | Just (_ :: SomeAsyncException) <- fromException e -> throwIO e
      | esViolacionRestriccion e -> pure (Left (Conflicto (mensajeRestriccion (detalleSqlite e))))
      | otherwise -> pure (Left (FalloBase (detalleSqlite (e :: SomeException))))

mensajeRestriccion :: Text -> Text
mensajeRestriccion detalle
  | "UNIQUE" `Text.isInfixOf` detalle = "Ya existe un registro con ese valor único (" <> detalle <> ")."
  | "FOREIGN KEY" `Text.isInfixOf` detalle =
      "El registro está en uso por otros datos o referencia un registro inexistente."
  | otherwise = "La operación viola una restricción de integridad (" <> detalle <> ")."

leer :: BaseDatos -> (Connection -> IO a) -> IO (Either ErrorAdmin a)
leer bd accion = operar bd (fmap Right . accion)

-- | Comprueba que una sentencia afectó alguna fila; si no, el registro no existe.
alMenosUna :: Connection -> Text -> IO (Either ErrorAdmin ())
alMenosUna c recurso = do
  n <- changes c
  pure (if n > 0 then Right () else Left (NoEncontrado recurso))

diaODefecto :: Int -> Dia
diaODefecto n = maybe Lunes id (diaDeEntero n)

-- Categorías ----------------------------------------------------------------------------------

listarCategorias :: BaseDatos -> IO (Either ErrorAdmin [Categoria])
listarCategorias bd = leer bd $ \c ->
  map (\(i, n) -> Categoria (CategoriaId i) n) <$> query_ c "SELECT id, nombre FROM categorias ORDER BY id"

crearCategoria :: BaseDatos -> Text -> IO (Either ErrorAdmin Categoria)
crearCategoria bd nombre = operar bd $ \c -> do
  execute c "INSERT INTO categorias (nombre) VALUES (?)" (Only nombre)
  i <- fromIntegral <$> lastInsertRowId c
  pure (Right (Categoria (CategoriaId i) nombre))

actualizarCategoria :: BaseDatos -> CategoriaId -> Text -> IO (Either ErrorAdmin Categoria)
actualizarCategoria bd (CategoriaId i) nombre = operar bd $ \c -> do
  execute c "UPDATE categorias SET nombre = ? WHERE id = ?" (nombre, i)
  fmap (const (Categoria (CategoriaId i) nombre)) <$> alMenosUna c "categoría"

borrarCategoria :: BaseDatos -> CategoriaId -> IO (Either ErrorAdmin ())
borrarCategoria bd (CategoriaId i) = operar bd $ \c -> do
  execute c "DELETE FROM categorias WHERE id = ?" (Only i)
  alMenosUna c "categoría"

-- Aulas ---------------------------------------------------------------------------------------

data DatosAula = DatosAula
  { codigoNuevaAula :: Text
  , capacidadNuevaAula :: Int
  , edificioNuevaAula :: Text
  , pisoNuevaAula :: Int
  , tipoNuevaAula :: Text
  }
  deriving (Eq, Show)

listarAulas :: BaseDatos -> IO (Either ErrorAdmin [Aula])
listarAulas bd = leer bd $ \c ->
  map (\(i, cod, cap, edif, p, t) -> Aula (AulaId i) cod cap edif p t)
    <$> query_ c "SELECT id, codigo, capacidad, edificio, piso, tipo FROM aulas ORDER BY id"

crearAula :: BaseDatos -> DatosAula -> IO (Either ErrorAdmin Aula)
crearAula bd (DatosAula cod cap edif p t) = operar bd $ \c -> do
  execute c "INSERT INTO aulas (codigo, capacidad, edificio, piso, tipo) VALUES (?, ?, ?, ?, ?)" (cod, cap, edif, p, t)
  i <- fromIntegral <$> lastInsertRowId c
  pure (Right (Aula (AulaId i) cod cap edif p t))

actualizarAula :: BaseDatos -> AulaId -> DatosAula -> IO (Either ErrorAdmin Aula)
actualizarAula bd (AulaId i) (DatosAula cod cap edif p t) = operar bd $ \c -> do
  execute c "UPDATE aulas SET codigo = ?, capacidad = ?, edificio = ?, piso = ?, tipo = ? WHERE id = ?"
    (cod, cap, edif, p, t, i)
  fmap (const (Aula (AulaId i) cod cap edif p t)) <$> alMenosUna c "aula"

borrarAula :: BaseDatos -> AulaId -> IO (Either ErrorAdmin ())
borrarAula bd (AulaId i) = operar bd $ \c -> do
  execute c "DELETE FROM aulas WHERE id = ?" (Only i)
  alMenosUna c "aula"

-- Cursos --------------------------------------------------------------------------------------

data DatosCurso = DatosCurso
  { codigoNuevoCurso :: Text
  , nombreNuevoCurso :: Text
  , categoriaNuevoCurso :: CategoriaId
  }
  deriving (Eq, Show)

-- | Lista cursos; con una categoría, solo los de esa categoría.
listarCursos :: BaseDatos -> Maybe CategoriaId -> IO (Either ErrorAdmin [Curso])
listarCursos bd filtro = leer bd $ \c -> do
  filas <- case filtro of
    Nothing -> query_ c "SELECT id, codigo, nombre, categoria_id FROM cursos ORDER BY id"
    Just (CategoriaId cat) ->
      query c "SELECT id, codigo, nombre, categoria_id FROM cursos WHERE categoria_id = ? ORDER BY id" (Only cat)
  pure [Curso (CursoId i) cod nom (CategoriaId cat) | (i, cod, nom, cat) <- filas]

crearCurso :: BaseDatos -> DatosCurso -> IO (Either ErrorAdmin Curso)
crearCurso bd (DatosCurso cod nom (CategoriaId cat)) = operar bd $ \c -> do
  execute c "INSERT INTO cursos (codigo, nombre, categoria_id) VALUES (?, ?, ?)" (cod, nom, cat)
  i <- fromIntegral <$> lastInsertRowId c
  pure (Right (Curso (CursoId i) cod nom (CategoriaId cat)))

actualizarCurso :: BaseDatos -> CursoId -> DatosCurso -> IO (Either ErrorAdmin Curso)
actualizarCurso bd (CursoId i) (DatosCurso cod nom (CategoriaId cat)) = operar bd $ \c -> do
  execute c "UPDATE cursos SET codigo = ?, nombre = ?, categoria_id = ? WHERE id = ?" (cod, nom, cat, i)
  fmap (const (Curso (CursoId i) cod nom (CategoriaId cat))) <$> alMenosUna c "curso"

borrarCurso :: BaseDatos -> CursoId -> IO (Either ErrorAdmin ())
borrarCurso bd (CursoId i) = operar bd $ \c -> do
  execute c "DELETE FROM cursos WHERE id = ?" (Only i)
  alMenosUna c "curso"

-- Secciones y sesiones ------------------------------------------------------------------------

data SesionRegistro = SesionRegistro
  { sesionRegistrada :: Sesion
  , sesionCerrada :: Bool
  }
  deriving (Eq, Show)

data SeccionRegistro = SeccionRegistro
  { idSeccion :: SeccionId
  , cursoDeSeccion :: CursoId
  , periodoDeSeccion :: PeriodoId
  , codigoDeSeccion :: Text
  , matriculadosDeSeccion :: Int
  , gruposDeSeccion :: [GrupoId]
  , sesionesDeSeccion :: [SesionRegistro]
  }
  deriving (Eq, Show)

-- | Sesión de entrada: con ID se actualiza, sin ID se crea.
data DatosSesion = DatosSesion
  { idDatosSesion :: Maybe SesionId
  , duracionDatosSesion :: Int
  , tipoAulaDatosSesion :: Text
  }
  deriving (Eq, Show)

data DatosSeccion = DatosSeccion
  { periodoDatosSeccion :: PeriodoId
  , codigoDatosSeccion :: Text
  , matriculadosDatosSeccion :: Int
  , gruposDatosSeccion :: [GrupoId]
  , sesionesDatosSeccion :: [DatosSesion]
  }
  deriving (Eq, Show)

existeCurso :: Connection -> CursoId -> IO Bool
existeCurso c (CursoId i) = not . null <$> (query c "SELECT id FROM cursos WHERE id = ?" (Only i) :: IO [Only Int])

leerSecciones :: Connection -> CursoId -> Maybe PeriodoId -> Maybe SeccionId -> IO [SeccionRegistro]
leerSecciones c (CursoId cu) periodo seccion = do
  filas <- query c
    "SELECT id, periodo_id, codigo, matriculados FROM secciones WHERE curso_id = ? \
    \AND (? IS NULL OR periodo_id = ?) AND (? IS NULL OR id = ?) ORDER BY id"
    (cu, p, p, s, s)
  forM filas $ \(i, per, cod, mat) -> do
    grupos <- query c "SELECT grupo_id FROM seccion_grupos WHERE seccion_id = ? ORDER BY grupo_id" (Only (i :: Int))
    sesionesFilas <- query c
      "SELECT id, duracion_min, tipo_aula, cerrada FROM sesiones WHERE seccion_id = ? ORDER BY orden, id" (Only i)
    pure (SeccionRegistro (SeccionId i) (CursoId cu) (PeriodoId per) cod mat [GrupoId g | Only g <- grupos]
      [SesionRegistro (Sesion (SesionId si) dur t) cer | (si, dur, t, cer) <- sesionesFilas])
  where
    p = (\(PeriodoId x) -> x) <$> periodo
    s = (\(SeccionId x) -> x) <$> seccion

listarSecciones :: BaseDatos -> CursoId -> Maybe PeriodoId -> IO (Either ErrorAdmin [SeccionRegistro])
listarSecciones bd curso periodo = operar bd $ \c -> do
  existe <- existeCurso c curso
  if existe then Right <$> leerSecciones c curso periodo Nothing else pure (Left (NoEncontrado "curso"))

crearSeccion :: BaseDatos -> CursoId -> DatosSeccion -> IO (Either ErrorAdmin SeccionRegistro)
crearSeccion bd curso@(CursoId cu) datos = operar bd $ \c -> do
  existe <- existeCurso c curso
  if not existe
    then pure (Left (NoEncontrado "curso"))
    else case validarDatosSeccion datos of
      Just problema -> pure (Left (Invalido problema))
      Nothing -> if any (isJust . idDatosSesion) (sesionesDatosSeccion datos)
        then pure (Left (Invalido "Las sesiones de una sección nueva no llevan id."))
        else do
          let PeriodoId p = periodoDatosSeccion datos
          execute c "INSERT INTO secciones (curso_id, periodo_id, codigo, matriculados) VALUES (?, ?, ?, ?)"
            (cu, p, codigoDatosSeccion datos, matriculadosDatosSeccion datos)
          s <- fromIntegral <$> lastInsertRowId c
          escribirGrupos c s (gruposDatosSeccion datos)
          forM_ (zip [0 :: Int ..] (sesionesDatosSeccion datos)) $ \(orden, DatosSesion _ dur t) ->
            execute c "INSERT INTO sesiones (seccion_id, orden, duracion_min, tipo_aula) VALUES (?, ?, ?, ?)" (s, orden, dur, t)
          unaSeccion c curso (SeccionId s)

actualizarSeccion :: BaseDatos -> CursoId -> SeccionId -> DatosSeccion -> IO (Either ErrorAdmin SeccionRegistro)
actualizarSeccion bd curso@(CursoId cu) seccion@(SeccionId s) datos = operar bd $ \c -> do
  actuales <- leerSecciones c curso Nothing (Just seccion)
  case (actuales, validarDatosSeccion datos) of
    ([], _) -> pure (Left (NoEncontrado "sección"))
    (_, Just problema) -> pure (Left (Invalido problema))
    (registro : _, Nothing) -> do
      let existentes = Set.fromList [sesionId (sesionRegistrada r) | r <- sesionesDeSeccion registro]
          enviados = catMaybes (map idDatosSesion (sesionesDatosSeccion datos))
          ajenos = filter (`Set.notMember` existentes) enviados
          PeriodoId p = periodoDatosSeccion datos
      if not (null ajenos)
        then pure (Left (Invalido "Una sesión enviada con id no pertenece a la sección."))
        else do
          execute c "UPDATE secciones SET curso_id = ?, periodo_id = ?, codigo = ?, matriculados = ? WHERE id = ?"
            (cu, p, codigoDatosSeccion datos, matriculadosDatosSeccion datos, s)
          execute c "DELETE FROM seccion_grupos WHERE seccion_id = ?" (Only s)
          escribirGrupos c s (gruposDatosSeccion datos)
          let retiradas = Set.toList (existentes `Set.difference` Set.fromList enviados)
          forM_ retiradas $ \(SesionId si) -> execute c "DELETE FROM sesiones WHERE id = ?" (Only si)
          forM_ (zip [0 :: Int ..] (sesionesDatosSeccion datos)) $ \(orden, DatosSesion ident dur t) ->
            case ident of
              Just (SesionId si) ->
                execute c "UPDATE sesiones SET orden = ?, duracion_min = ?, tipo_aula = ? WHERE id = ?" (orden, dur, t, si)
              Nothing ->
                execute c "INSERT INTO sesiones (seccion_id, orden, duracion_min, tipo_aula) VALUES (?, ?, ?, ?)" (s, orden, dur, t)
          unaSeccion c curso seccion

borrarSeccion :: BaseDatos -> CursoId -> SeccionId -> IO (Either ErrorAdmin ())
borrarSeccion bd curso seccion@(SeccionId s) = operar bd $ \c -> do
  actuales <- leerSecciones c curso Nothing (Just seccion)
  if null actuales
    then pure (Left (NoEncontrado "sección"))
    else do
      execute c "DELETE FROM sesiones WHERE seccion_id = ?" (Only s)
      execute c "DELETE FROM secciones WHERE id = ?" (Only s)
      pure (Right ())

unaSeccion :: Connection -> CursoId -> SeccionId -> IO (Either ErrorAdmin SeccionRegistro)
unaSeccion c curso seccion = do
  r <- leerSecciones c curso Nothing (Just seccion)
  pure (case r of
    registro : _ -> Right registro
    [] -> Left (NoEncontrado "sección"))

escribirGrupos :: Connection -> Int -> [GrupoId] -> IO ()
escribirGrupos c s grupos =
  forM_ (Set.toList (Set.fromList [g | GrupoId g <- grupos])) $ \g ->
    execute c "INSERT INTO seccion_grupos (seccion_id, grupo_id) VALUES (?, ?)" (s, g)

-- | Comprobaciones de forma (no de reglas): IDs positivos y textos no vacíos.
validarDatosSeccion :: DatosSeccion -> Maybe Text
validarDatosSeccion datos
  | let PeriodoId p = periodoDatosSeccion datos in p <= 0 = Just "periodoId debe ser positivo."
  | any (\(GrupoId g) -> g <= 0) (gruposDatosSeccion datos) = Just "Los grupos deben ser IDs positivos."
  | any ((<= 0) . duracionDatosSesion) (sesionesDatosSeccion datos) = Just "duracionMin debe ser positiva."
  | any (Text.null . tipoAulaDatosSesion) (sesionesDatosSeccion datos) = Just "tipoAula no puede estar vacío."
  | let ids = catMaybes (map idDatosSesion (sesionesDatosSeccion datos)) in length ids /= Set.size (Set.fromList ids) =
      Just "Una sesión aparece dos veces."
  | otherwise = Nothing

periodoDeSesion :: BaseDatos -> SesionId -> IO (Either ErrorAdmin PeriodoId)
periodoDeSesion bd (SesionId si) = operar bd $ \c -> do
  filas <- query c "SELECT s.periodo_id FROM sesiones se JOIN secciones s ON s.id = se.seccion_id WHERE se.id = ?" (Only si)
  pure (case filas of
    Only p : _ -> Right (PeriodoId p)
    [] -> Left (NoEncontrado "sesión"))

-- Profesores ----------------------------------------------------------------------------------

data ProfesorRegistro = ProfesorRegistro
  { profesorRegistrado :: Profesor
  , usuarioDelProfesor :: Maybe Text
  }
  deriving (Eq, Show)

leerProfesores :: Connection -> Maybe ProfesorId -> IO [ProfesorRegistro]
leerProfesores c filtro = do
  filas <- query c
    "SELECT p.id, p.nombre, p.categoria_id, u.usuario FROM profesores p \
    \LEFT JOIN usuarios u ON u.profesor_id = p.id WHERE (? IS NULL OR p.id = ?) ORDER BY p.id"
    (f, f)
  habilitaciones <- query c
    "SELECT profesor_id, curso_id FROM profesor_cursos WHERE (? IS NULL OR profesor_id = ?) ORDER BY profesor_id, curso_id"
    (f, f)
  let cursosDe = Map.fromListWith (flip (++)) [(p, [CursoId cu]) | (p, cu) <- habilitaciones :: [(Int, Int)]]
  pure [ ProfesorRegistro (Profesor (ProfesorId i) n (CategoriaId cat) (Map.findWithDefault [] i cursosDe)) u
       | (i, n, cat, u) <- filas ]
  where
    f = (\(ProfesorId x) -> x) <$> filtro

listarProfesores :: BaseDatos -> IO (Either ErrorAdmin [ProfesorRegistro])
listarProfesores bd = leer bd (\c -> leerProfesores c Nothing)

buscarProfesorRegistro :: BaseDatos -> ProfesorId -> IO (Either ErrorAdmin ProfesorRegistro)
buscarProfesorRegistro bd p = operar bd $ \c -> unProfesor c p

unProfesor :: Connection -> ProfesorId -> IO (Either ErrorAdmin ProfesorRegistro)
unProfesor c p = do
  r <- leerProfesores c (Just p)
  pure (case r of
    registro : _ -> Right registro
    [] -> Left (NoEncontrado "profesor"))

-- | Crea el profesor y, si se indica, su usuario con el hash ya calculado.
crearProfesor
  :: BaseDatos -> Text -> CategoriaId -> [CursoId] -> Maybe (Text, Text) -> IO (Either ErrorAdmin ProfesorRegistro)
crearProfesor bd nombre (CategoriaId cat) cursosAptos credenciales = operar bd $ \c -> do
  execute c "INSERT INTO profesores (nombre, categoria_id) VALUES (?, ?)" (nombre, cat)
  i <- fromIntegral <$> lastInsertRowId c
  escribirCursos c i cursosAptos
  forM_ credenciales $ \(usuario, hash) ->
    execute c "INSERT INTO usuarios (usuario, hash_contrasena, rol, profesor_id) VALUES (?, ?, 'profesor', ?)"
      (usuario, hash, i)
  unProfesor c (ProfesorId i)

data CambiosProfesor = CambiosProfesor
  { nuevoNombre :: Maybe Text
  , nuevaCategoria :: Maybe CategoriaId
  , nuevosCursos :: Maybe [CursoId]
  , nuevoHashContrasena :: Maybe Text
  }
  deriving (Eq, Show)

actualizarProfesor :: BaseDatos -> ProfesorId -> CambiosProfesor -> IO (Either ErrorAdmin ProfesorRegistro)
actualizarProfesor bd p@(ProfesorId i) cambios = operar bd $ \c -> do
  actual <- unProfesor c p
  case actual of
    Left e -> pure (Left e)
    Right registro -> do
      forM_ (nuevoNombre cambios) $ \n -> execute c "UPDATE profesores SET nombre = ? WHERE id = ?" (n, i)
      forM_ (nuevaCategoria cambios) $ \(CategoriaId cat) ->
        execute c "UPDATE profesores SET categoria_id = ? WHERE id = ?" (cat, i)
      forM_ (nuevosCursos cambios) $ \cursosAptos -> do
        execute c "DELETE FROM profesor_cursos WHERE profesor_id = ?" (Only i)
        escribirCursos c i cursosAptos
      case nuevoHashContrasena cambios of
        Nothing -> unProfesor c p
        Just hash
          | usuarioDelProfesor registro == Nothing ->
              pure (Left (Invalido "El profesor no tiene usuario; no se puede cambiar su contraseña."))
          | otherwise -> do
              execute c "UPDATE usuarios SET hash_contrasena = ? WHERE profesor_id = ?" (hash, i)
              execute c "DELETE FROM tokens WHERE usuario_id IN (SELECT id FROM usuarios WHERE profesor_id = ?)" (Only i)
              unProfesor c p

escribirCursos :: Connection -> Int -> [CursoId] -> IO ()
escribirCursos c i cursosAptos =
  forM_ (Set.toList (Set.fromList [cu | CursoId cu <- cursosAptos])) $ \cu ->
    execute c "INSERT INTO profesor_cursos (profesor_id, curso_id) VALUES (?, ?)" (i, cu)

borrarProfesor :: BaseDatos -> ProfesorId -> IO (Either ErrorAdmin ())
borrarProfesor bd (ProfesorId i) = operar bd $ \c -> do
  execute c "DELETE FROM profesores WHERE id = ?" (Only i)
  alMenosUna c "profesor"

-- | Franjas registradas del profesor en el período, o 'Nothing' si no registró disponibilidad.
disponibilidadDe :: BaseDatos -> ProfesorId -> PeriodoId -> IO (Either ErrorAdmin (Maybe [Franja]))
disponibilidadDe bd (ProfesorId pr) (PeriodoId p) = leer bd $ \c -> do
  cabecera <- query c "SELECT profesor_id FROM disponibilidades WHERE profesor_id = ? AND periodo_id = ?" (pr, p)
  if null (cabecera :: [Only Int])
    then pure Nothing
    else do
      filas <- query c
        "SELECT dia, inicio_min, fin_min FROM disponibilidad_franjas WHERE profesor_id = ? AND periodo_id = ? ORDER BY orden"
        (pr, p)
      pure (Just [Franja (diaODefecto d) (Intervalo i f) | (d, i, f) <- filas])

-- Propuestas ----------------------------------------------------------------------------------

data PropuestaRegistro = PropuestaRegistro
  { idPropuesta :: Int
  , propuestaDocente :: HorarioDocente
  }
  deriving (Eq, Show)

leerPropuestas :: Connection -> Maybe Int -> Maybe ProfesorId -> Maybe PeriodoId -> Maybe EstadoAprobacion -> IO [PropuestaRegistro]
leerPropuestas c ident profesor periodo estado = do
  let pr = (\(ProfesorId x) -> x) <$> profesor
      per = (\(PeriodoId x) -> x) <$> periodo
      est = estadoAprobacionTexto <$> estado
  filas <- query c
    "SELECT id, profesor_id, curso_id, periodo_id, estado FROM horarios_docentes \
    \WHERE (? IS NULL OR id = ?) AND (? IS NULL OR profesor_id = ?) AND (? IS NULL OR periodo_id = ?) \
    \AND (? IS NULL OR estado = ?) ORDER BY id"
    ((ident, ident, pr, pr, per, per) :. (est, est))
  fmap catMaybes $ forM filas $ \(i, profesorFila, cu, periodoFila, estadoT) -> do
    franjas <- leerFranjasHorarioDocente c i
    pure ((\e -> PropuestaRegistro i
        (HorarioDocente (ProfesorId profesorFila) (CursoId cu) (PeriodoId periodoFila) franjas e))
      <$> estadoAprobacionDeTexto estadoT)

listarPropuestas
  :: BaseDatos -> Maybe ProfesorId -> Maybe PeriodoId -> Maybe EstadoAprobacion -> IO (Either ErrorAdmin [PropuestaRegistro])
listarPropuestas bd profesor periodo estado = leer bd (\c -> leerPropuestas c Nothing profesor periodo estado)

buscarPropuesta :: BaseDatos -> Int -> IO (Either ErrorAdmin PropuestaRegistro)
buscarPropuesta bd i = operar bd $ \c -> do
  r <- leerPropuestas c (Just i) Nothing Nothing Nothing
  pure (case r of
    registro : _ -> Right registro
    [] -> Left (NoEncontrado "propuesta"))

buscarPropuestaPorClave
  :: BaseDatos -> ProfesorId -> CursoId -> PeriodoId -> EstadoAprobacion -> IO (Either ErrorAdmin PropuestaRegistro)
buscarPropuestaPorClave bd profesor curso periodo estado = operar bd $ \c -> do
  r <- leerPropuestas c Nothing (Just profesor) (Just periodo) (Just estado)
  pure (case filter ((== curso) . cursoDelHorarioDocente . propuestaDocente) r of
    registro : _ -> Right registro
    [] -> Left (NoEncontrado "propuesta"))

-- Configuración -------------------------------------------------------------------------------

obtenerConfiguracion :: BaseDatos -> PeriodoId -> IO (Either ErrorAdmin Configuracion)
obtenerConfiguracion bd periodo = operar bd $ \c ->
  maybe (Left (NoEncontrado "configuración")) Right <$> leerConfiguracion c periodo

guardarConfiguracion :: BaseDatos -> Configuracion -> IO (Either ErrorAdmin Configuracion)
guardarConfiguracion bd config = operar bd $ \c -> do
  let PeriodoId p = periodoConfiguracion config
      ps = pesos config
  execute c "DELETE FROM configuracion_dias WHERE periodo_id = ?" (Only p)
  execute c "DELETE FROM configuracion_recesos WHERE periodo_id = ?" (Only p)
  execute c
    "INSERT INTO configuraciones (periodo_id, inicio_dia_min, fin_dia_min, turno_min, peso_hueco, peso_piso, peso_edificio, \
    \peso_estabilidad, tolerancia_hueco_min, consecutivo_max_min, timeout_seg) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) \
    \ON CONFLICT (periodo_id) DO UPDATE SET inicio_dia_min = excluded.inicio_dia_min, fin_dia_min = excluded.fin_dia_min, \
    \turno_min = excluded.turno_min, peso_hueco = excluded.peso_hueco, peso_piso = excluded.peso_piso, \
    \peso_edificio = excluded.peso_edificio, peso_estabilidad = excluded.peso_estabilidad, \
    \tolerancia_hueco_min = excluded.tolerancia_hueco_min, consecutivo_max_min = excluded.consecutivo_max_min, \
    \timeout_seg = excluded.timeout_seg"
    ( (p, inicioMin (jornada config), finMin (jornada config), turnoAEntero (turno config), pesoHueco ps, pesoPiso ps)
      :. (pesoEdificio ps, pesoEstabilidad ps, toleranciaHuecoMin config, consecutivoMaxMin config, timeoutSeg config) )
  forM_ (zip [0 :: Int ..] (diasActivos config)) $ \(orden, d) ->
    execute c "INSERT INTO configuracion_dias (periodo_id, orden, dia) VALUES (?, ?, ?)" (p, orden, diaAEntero d)
  forM_ (zip [0 :: Int ..] (recesos config)) $ \(orden, Intervalo i f) ->
    execute c "INSERT INTO configuracion_recesos (periodo_id, orden, inicio_min, fin_min) VALUES (?, ?, ?, ?)" (p, orden, i, f)
  maybe (Left (FalloBase "La configuración no se pudo releer.")) Right <$> leerConfiguracion c (PeriodoId p)

-- | Mayor período con configuración.
periodoMasReciente :: BaseDatos -> IO (Either ErrorAdmin (Maybe PeriodoId))
periodoMasReciente bd = leer bd $ \c -> do
  filas <- query_ c "SELECT MAX(periodo_id) FROM configuraciones" :: IO [Only (Maybe Int)]
  pure (case filas of
    Only (Just p) : _ -> Just (PeriodoId p)
    _ -> Nothing)

-- Horarios y avisos ---------------------------------------------------------------------------

data ResumenHorario = ResumenHorario
  { idResumen :: HorarioId
  , periodoResumen :: PeriodoId
  , estadoResumen :: Text
  , origenResumen :: Text
  , versionResumen :: Maybe Int
  , politicaResumen :: Maybe Text
  , baseResumen :: Maybe HorarioId
  , cantidadAsignacionesResumen :: Int
  , cantidadSinAsignarResumen :: Int
  , creadoEnResumen :: Text
  }
  deriving (Eq, Show)

listarHorarios :: BaseDatos -> Maybe PeriodoId -> Maybe EstadoHorario -> IO (Either ErrorAdmin [ResumenHorario])
listarHorarios bd periodo estado = leer bd $ \c -> do
  filas <- query c
    "SELECT h.id, h.periodo_id, h.estado, h.origen, h.numero_version, h.politica, h.base_horario_id, \
    \(SELECT COUNT(*) FROM asignaciones a WHERE a.horario_id = h.id), \
    \(SELECT COUNT(*) FROM horario_sin_asignar s WHERE s.horario_id = h.id), h.creado_en \
    \FROM horarios h WHERE (? IS NULL OR h.periodo_id = ?) AND (? IS NULL OR h.estado = ?) ORDER BY h.id"
    (per, per, est, est)
  pure [ ResumenHorario (HorarioId i) (PeriodoId p) e o v pol (HorarioId <$> b) na ns cr
       | (i, p, e, o, v, pol, b, na, ns, cr) <- filas ]
  where
    per = (\(PeriodoId x) -> x) <$> periodo
    est = estadoHorarioTexto <$> estado

data AvisoRegistro = AvisoRegistro
  { idAviso :: Int
  , avisoHorario :: HorarioId
  , avisoClase :: UbicacionSesion
  , avisoCreadoEn :: Text
  }
  deriving (Eq, Show)

-- | Avisos del más reciente al más antiguo; con un profesor, solo los suyos.
listarAvisos :: BaseDatos -> Maybe ProfesorId -> Maybe PeriodoId -> IO (Either ErrorAdmin [AvisoRegistro])
listarAvisos bd profesor periodo = leer bd $ \c -> do
  filas <- query c
    "SELECT a.id, a.horario_id, a.sesion_id, a.profesor_id, a.aula_id, a.dia, a.inicio_min, a.creado_en \
    \FROM avisos a JOIN horarios h ON h.id = a.horario_id \
    \WHERE (? IS NULL OR a.profesor_id = ?) AND (? IS NULL OR h.periodo_id = ?) ORDER BY a.id DESC"
    (prof, prof, per, per)
  pure [ AvisoRegistro i (HorarioId h) (UbicacionSesion (SesionId s) (ProfesorId pr) (AulaId a) (diaODefecto d) ini) cr
       | (i, h, s, pr, a, d, ini, cr) <- filas ]
  where
    prof = (\(ProfesorId x) -> x) <$> profesor
    per = (\(PeriodoId x) -> x) <$> periodo
