{-# LANGUAGE OverloadedStrings #-}

-- | API REST con Scotty conforme a `contracts/openapi.yaml` (M3).
-- La API autentica, autoriza, traduce JSON y llama a los casos de uso de M2 o al CRUD de M3.
-- No valida reglas del horario: eso lo hacen los casos de uso (`simular`, `publicar`, `generar`).
module Adapters.Api.Servidor
  ( Entorno (..)
  , aplicacion
  ) where

import Adapters.Api.Autenticacion
import Adapters.Api.Errores
import Adapters.Api.Json
import Adapters.Api.Trabajos (Ejecutor, encolar, solicitudGeneracion)
import Adapters.Sqlite.Administracion
import Adapters.Sqlite.Codificacion (configuracionAJson, estadoAprobacionDeTexto, estadoHorarioDeTexto)
import Adapters.Sqlite.Conexion (BaseDatos)
import Adapters.Sqlite.Repositorio (repositorioSqlite)
import Adapters.Sqlite.Trabajos
import Adapters.Sqlite.Usuarios
import Control.Exception (SomeException, displayException, try)
import Control.Monad (forM_, unless, when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import Data.Aeson
import Data.Aeson.Types (Parser, parseEither)
import qualified Data.ByteString.Lazy as BL
import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TE
import qualified Data.Text.Lazy as TL
import Domain.Tipos
import Network.HTTP.Types.Status
import Network.Wai (Application)
import System.IO (hPutStrLn, stderr)
import UseCases.Docentes
import UseCases.Errores (ErrorCasoUso)
import UseCases.Horarios
import UseCases.Repositorio (Repositorio)
import UseCases.Solver (Solver)
import qualified Web.Scotty as S

data Entorno = Entorno
  { baseDatos :: BaseDatos
  , solverEntorno :: Solver IO
  , ejecutorEntorno :: Ejecutor
  , horasTokenEntorno :: Int
  , costoBcryptEntorno :: Int
  }

type Api = ExceptT ErrorApi IO

data Respuesta = Respuesta Status (Maybe Value)

data Peticion = Peticion
  { autorizacion :: Maybe Text
  , cuerpo :: BL.ByteString
  }

ok :: Value -> Respuesta
ok = Respuesta status200 . Just

creado :: Value -> Respuesta
creado = Respuesta status201 . Just

sinContenido :: Respuesta
sinContenido = Respuesta status204 Nothing

-- | Ejecuta un manejador y envía su respuesta o su error con el formato uniforme.
atender :: (Peticion -> Api Respuesta) -> S.ActionM ()
atender manejar = do
  cabecera <- S.header "Authorization"
  datos <- S.body
  resultado <- liftIO (try (runExceptT (manejar (Peticion (fmap TL.toStrict cabecera) datos))))
  case resultado of
    Left (e :: SomeException) -> do
      liftIO (hPutStrLn stderr ("[api] Error no controlado: " <> displayException e))
      enviarError errorInterno
    Right (Left e) -> enviarError e
    Right (Right (Respuesta s contenido)) -> do
      S.status s
      forM_ contenido S.json

-- | Envía el error. Un error interno (500) se registra completo en stderr y llega al cliente sin detalles.
enviarError :: ErrorApi -> S.ActionM ()
enviarError e
  | estadoHttp e == status500 = do
      liftIO (hPutStrLn stderr ("[api] " <> show (codigoError e, mensajeError e, detallesError e)))
      S.status status500
      S.json (errorAJson e {detallesError = []})
  | otherwise = do
      S.status (estadoHttp e)
      S.json (errorAJson e)

-- Utilidades de los manejadores ---------------------------------------------------------------

sesion :: Entorno -> Peticion -> Api SesionUsuario
sesion ent p = do
  s <- liftIO (sesionDeToken (baseDatos ent) (autorizacion p))
  maybe (throwE (noAutenticado "Falta el token, es inválido o expiró.")) pure s

coordinador :: Entorno -> Peticion -> Api SesionUsuario
coordinador ent p = do
  s <- sesion ent p
  unless (rolSesion s == RolCoordinador) $ throwE (prohibido "Operación reservada al coordinador.")
  pure s

esCoordinador :: SesionUsuario -> Bool
esCoordinador s = rolSesion s == RolCoordinador

leerCuerpo :: (Value -> Parser a) -> Peticion -> Api a
leerCuerpo parser p =
  case eitherDecode (cuerpo p) of
    Left e -> throwE (solicitudInvalida ("El cuerpo no es JSON válido: " <> Text.pack e))
    Right valor -> either (throwE . solicitudInvalida . limpiar) pure (parseEither parser valor)
  where
    limpiar = Text.pack

admin :: IO (Either ErrorAdmin a) -> Api a
admin accion = ExceptT (either (Left . desdeAdmin) Right <$> accion)

casoUso :: IO (Either ErrorCasoUso a) -> Api a
casoUso accion = ExceptT (either (Left . desdeCasoUso) Right <$> accion)


repo :: Entorno -> Repositorio IO
repo = repositorioSqlite . baseDatos

periodoOReciente :: Entorno -> Maybe Int -> Api (Maybe PeriodoId)
periodoOReciente _ (Just p) = pure (Just (PeriodoId p))
periodoOReciente ent Nothing = admin (periodoMasReciente (baseDatos ent))

-- Aplicación ----------------------------------------------------------------------------------

aplicacion :: Entorno -> IO Application
aplicacion ent = S.scottyApp (rutas ent)

rutas :: Entorno -> S.ScottyM ()
rutas ent = do
  let bd = baseDatos ent

  -- Autenticación
  S.post "/auth/login" $ atender $ \p -> do
    LoginEntrada usuario contrasena <- leerCuerpo loginEntrada p
    credenciales <- liftIO (buscarCredenciales bd usuario)
    case credenciales of
      Just c | contrasenaCorrecta contrasena (hashGuardado c) -> do
        TokenEmitido token expira <- liftIO (emitirToken bd (horasTokenEntorno ent) c)
        pure (ok (object
          [ "version" .= (1 :: Int), "token" .= token, "rol" .= rolTexto (rolCredenciales c)
          , "profesorId" .= fmap (\(ProfesorId i) -> i) (profesorCredenciales c), "expiraEn" .= expira ]))
      _ -> throwE (noAutenticado "Usuario o contraseña incorrectos.")

  -- Profesores
  S.get "/profesores" $ atender $ \p -> do
    _ <- coordinador ent p
    registros <- admin (listarProfesores bd)
    pure (ok (lista "profesores" (map profesorJson registros)))

  S.post "/profesores" $ atender $ \p -> do
    _ <- coordinador ent p
    e <- leerCuerpo profesorEntrada p
    credenciales <- case (usuarioProfesorEntrada e, contrasenaProfesorEntrada e) of
      (Just u, Just c) -> do
        h <- liftIO (hashContrasena (costoBcryptEntorno ent) c)
        pure (Just (u, h))
      _ -> pure Nothing
    registro <- admin (crearProfesor bd (nombreProfesorEntrada e) (categoriaProfesorEntrada e)
      (cursosProfesorEntrada e) credenciales)
    pure (creado (conVersion (profesorJson registro)))

  S.get "/profesores/:id" $ do
    i <- S.pathParam "id"
    periodo <- S.queryParamMaybe "periodoId"
    atender $ \p -> do
      s <- sesion ent p
      propio ent s (ProfesorId i)
      detalleProfesor ent (ProfesorId i) periodo []

  S.put "/profesores/:id" $ do
    i <- S.pathParam "id"
    atender $ \p -> do
      s <- sesion ent p
      let profesor = ProfesorId i
      propio ent s profesor
      cambios <- leerCuerpo profesorActualizacion p
      let datosCoordinador =
            isJust (nombreActualizado cambios) || isJust (categoriaActualizada cambios) ||
            isJust (cursosActualizados cambios) || isJust (contrasenaActualizada cambios)
      when (datosCoordinador && not (esCoordinador s)) $
        throwE (prohibido "Solo el coordinador modifica nombre, categoría, cursos aptos y contraseña.")
      when (isJust (disponibilidadActualizada cambios) && profesorSesion s /= Just profesor) $
        throwE (prohibido "Solo el profesor puede cambiar su propia disponibilidad.")
      when datosCoordinador $ do
        hash <- traverse (liftIO . hashContrasena (costoBcryptEntorno ent)) (contrasenaActualizada cambios)
        _ <- admin (actualizarProfesor bd profesor
          (CambiosProfesor (nombreActualizado cambios) (categoriaActualizada cambios) (cursosActualizados cambios) hash))
        pure ()
      avisos <- case (disponibilidadActualizada cambios, periodoActualizado cambios) of
        (Just franjas, Just periodo) ->
          casoUso (actualizarDisponibilidad (repo ent) profesor (Disponibilidad profesor periodo franjas))
        _ -> pure []
      detalleProfesor ent profesor ((\(PeriodoId x) -> x) <$> periodoActualizado cambios) avisos

  S.delete "/profesores/:id" $ do
    i <- S.pathParam "id"
    atender $ \p -> do
      _ <- coordinador ent p
      admin (borrarProfesor bd (ProfesorId i))
      pure sinContenido

  S.post "/profesores/:id/propuestas" $ do
    i <- S.pathParam "id"
    atender $ \p -> do
      s <- sesion ent p
      let profesor = ProfesorId i
      unless (profesorSesion s == Just profesor) $
        throwE (prohibido "Solo el profesor puede proponer su propio horario.")
      PropuestaEntrada curso periodo franjas <- leerCuerpo propuestaEntrada p
      casoUso (proponerHorario (repo ent) profesor (HorarioDocente profesor curso periodo franjas Propuesto))
      registro <- admin (buscarPropuestaPorClave bd profesor curso periodo Propuesto)
      pure (creado (conVersion (propuestaJson registro)))

  S.get "/propuestas" $ do
    periodo <- S.queryParamMaybe "periodoId"
    estadoT <- S.queryParamMaybe "estado"
    atender $ \p -> do
      _ <- coordinador ent p
      estado <- traverse (\t -> maybe (throwE (solicitudInvalida "estado debe ser propuesto o aprobado.")) pure
        (estadoAprobacionDeTexto t)) estadoT
      registros <- admin (listarPropuestas bd Nothing (PeriodoId <$> periodo) estado)
      pure (ok (lista "propuestas" (map propuestaJson registros)))

  S.post "/propuestas/:id/aprobar" $ do
    i <- S.pathParam "id"
    atender $ \p -> do
      _ <- coordinador ent p
      registro <- admin (buscarPropuesta bd i)
      unless (estadoAprobacion (propuestaDocente registro) == Propuesto) $
        throwE (conflicto "La propuesta ya fue aprobada.")
      casoUso (aprobarPropuesta (repo ent) (propuestaDocente registro))
      aprobado <- admin (buscarPropuesta bd i)
      pure (ok (conVersion (propuestaJson aprobado)))

  -- Categorías
  S.get "/categorias" $ atender $ \p -> do
    _ <- sesion ent p
    cs <- admin (listarCategorias bd)
    pure (ok (lista "categorias" (map categoriaJson cs)))

  S.post "/categorias" $ atender $ \p -> do
    _ <- coordinador ent p
    nombre <- leerCuerpo nombreEntrada p
    c <- admin (crearCategoria bd nombre)
    pure (creado (conVersion (categoriaJson c)))

  S.put "/categorias/:id" $ do
    i <- S.pathParam "id"
    atender $ \p -> do
      _ <- coordinador ent p
      nombre <- leerCuerpo nombreEntrada p
      c <- admin (actualizarCategoria bd (CategoriaId i) nombre)
      pure (ok (conVersion (categoriaJson c)))

  S.delete "/categorias/:id" $ do
    i <- S.pathParam "id"
    atender $ \p -> do
      _ <- coordinador ent p
      admin (borrarCategoria bd (CategoriaId i))
      pure sinContenido

  -- Aulas
  S.get "/aulas" $ atender $ \p -> do
    _ <- coordinador ent p
    as <- admin (listarAulas bd)
    pure (ok (lista "aulas" (map aulaJson as)))

  S.post "/aulas" $ atender $ \p -> do
    _ <- coordinador ent p
    datos <- leerCuerpo aulaEntrada p
    a <- admin (crearAula bd datos)
    pure (creado (conVersion (aulaJson a)))

  S.put "/aulas/:id" $ do
    i <- S.pathParam "id"
    atender $ \p -> do
      _ <- coordinador ent p
      datos <- leerCuerpo aulaEntrada p
      a <- admin (actualizarAula bd (AulaId i) datos)
      pure (ok (conVersion (aulaJson a)))

  S.delete "/aulas/:id" $ do
    i <- S.pathParam "id"
    atender $ \p -> do
      _ <- coordinador ent p
      admin (borrarAula bd (AulaId i))
      pure sinContenido

  -- Cursos, secciones y sesiones
  S.get "/cursos" $ atender $ \p -> do
    s <- sesion ent p
    filtro <- case profesorSesion s of
      Just profesor | not (esCoordinador s) -> do
        registro <- admin (buscarProfesorRegistro bd profesor)
        pure (Just (categoriaProfesor (profesorRegistrado registro)))
      _ -> pure Nothing
    cs <- admin (listarCursos bd filtro)
    pure (ok (lista "cursos" (map cursoJson cs)))

  S.post "/cursos" $ atender $ \p -> do
    _ <- coordinador ent p
    datos <- leerCuerpo cursoEntrada p
    c <- admin (crearCurso bd datos)
    pure (creado (conVersion (cursoJson c)))

  S.put "/cursos/:id" $ do
    i <- S.pathParam "id"
    atender $ \p -> do
      _ <- coordinador ent p
      datos <- leerCuerpo cursoEntrada p
      c <- admin (actualizarCurso bd (CursoId i) datos)
      pure (ok (conVersion (cursoJson c)))

  S.delete "/cursos/:id" $ do
    i <- S.pathParam "id"
    atender $ \p -> do
      _ <- coordinador ent p
      admin (borrarCurso bd (CursoId i))
      pure sinContenido

  S.get "/cursos/:id/secciones" $ do
    i <- S.pathParam "id"
    periodo <- S.queryParamMaybe "periodoId"
    atender $ \p -> do
      _ <- coordinador ent p
      ss <- admin (listarSecciones bd (CursoId i) (PeriodoId <$> periodo))
      pure (ok (lista "secciones" (map seccionJson ss)))

  S.post "/cursos/:id/secciones" $ do
    i <- S.pathParam "id"
    atender $ \p -> do
      _ <- coordinador ent p
      datos <- leerCuerpo seccionEntrada p
      s <- admin (crearSeccion bd (CursoId i) datos)
      pure (creado (conVersion (seccionJson s)))

  S.put "/cursos/:id/secciones/:seccionId" $ do
    i <- S.pathParam "id"
    s <- S.pathParam "seccionId"
    atender $ \p -> do
      _ <- coordinador ent p
      datos <- leerCuerpo seccionEntrada p
      r <- admin (actualizarSeccion bd (CursoId i) (SeccionId s) datos)
      pure (ok (conVersion (seccionJson r)))

  S.delete "/cursos/:id/secciones/:seccionId" $ do
    i <- S.pathParam "id"
    s <- S.pathParam "seccionId"
    atender $ \p -> do
      _ <- coordinador ent p
      admin (borrarSeccion bd (CursoId i) (SeccionId s))
      pure sinContenido

  S.post "/sesiones/:id/cerrar" $ do
    i <- S.pathParam "id"
    atender $ \p -> do
      _ <- coordinador ent p
      periodo <- admin (periodoDeSesion bd (SesionId i))
      casoUso (cerrarSesionDelPeriodo (repo ent) periodo (SesionId i))
      pure sinContenido

  -- Configuración
  S.get "/configuracion" $ do
    periodo <- S.queryParamMaybe "periodoId"
    atender $ \p -> do
      _ <- coordinador ent p
      elegido <- periodoOReciente ent periodo
      case elegido of
        Nothing -> throwE (noEncontrado "configuración")
        Just per -> ok . conVersion . configuracionAJson <$> admin (obtenerConfiguracion bd per)

  S.put "/configuracion" $ atender $ \p -> do
    _ <- coordinador ent p
    config <- leerCuerpo configuracionEntrada p
    guardada <- admin (guardarConfiguracion bd config)
    pure (ok (conVersion (configuracionAJson guardada)))

  -- Horarios
  S.get "/horarios" $ do
    periodo <- S.queryParamMaybe "periodoId"
    estadoT <- S.queryParamMaybe "estado"
    atender $ \p -> do
      s <- sesion ent p
      estado <- traverse (\t -> maybe (throwE (solicitudInvalida "estado debe ser borrador o publicado.")) pure
        (estadoHorarioDeTexto t)) estadoT
      resumenes <- if esCoordinador s || estado == Just Publicado || estado == Nothing
        then admin (listarHorarios bd (PeriodoId <$> periodo) (if esCoordinador s then estado else Just Publicado))
        else pure []
      pure (ok (lista "horarios" (map resumenHorarioJson resumenes)))

  S.post "/horarios" $ atender $ \p -> do
    _ <- coordinador ent p
    periodo <- leerCuerpo periodoEntrada p
    detalle <- casoUso (crearHorarioVacio (repo ent) periodo)
    pure (creado (detalleHorarioJson detalle))

  S.post "/horarios/generar" $ atender $ \p -> do
    _ <- coordinador ent p
    GenerarEntrada periodo modo base politica maximo <- leerCuerpo generarEntrada p
    let solicitud = SolicitudTrabajo periodo modo base politica maximo
    case solicitudGeneracion solicitud of
      Left mensaje -> throwE (solicitudInvalida mensaje)
      Right _ -> pure ()
    identificador <- liftIO (crearTrabajo bd solicitud)
    liftIO (encolar bd (solverEntorno ent) (ejecutorEntorno ent) identificador)
    pure (Respuesta status202 (Just (object
      ["version" .= (1 :: Int), "jobId" .= identificador, "estado" .= estadoTrabajoTexto Pendiente])))

  S.get "/trabajos/:jobId" $ do
    i <- S.pathParam "jobId"
    atender $ \p -> do
      _ <- coordinador ent p
      trabajo <- liftIO (buscarTrabajo bd i)
      maybe (throwE (noEncontrado "trabajo")) (pure . ok . trabajoJson) trabajo

  S.get "/horarios/:id" $ do
    i <- S.pathParam "id"
    atender $ \p -> do
      s <- sesion ent p
      detalle <- casoUso (consultarHorario (repo ent) (HorarioId i))
      when (not (esCoordinador s) && estadoHorario (datosHorario (horarioDetallado detalle)) /= Publicado) $
        throwE (prohibido "Los borradores no son visibles para el rol profesor.")
      pure (ok (detalleHorarioJson detalle))

  S.post "/horarios/:id/cambios" $ do
    i <- S.pathParam "id"
    simular <- S.queryParamMaybe "simular"
    atender $ \p -> do
      _ <- coordinador ent p
      cambios <- leerCuerpo cambiosEntrada p
      let modo = if simular == Just True then Simular else Guardar
      detalle <- casoUso (editarHorario (repo ent) (HorarioId i) modo cambios)
      pure (ok (detalleHorarioJson detalle))

  S.post "/horarios/:id/publicar" $ do
    i <- S.pathParam "id"
    atender $ \p -> do
      _ <- coordinador ent p
      detalle <- casoUso (publicarHorario (repo ent) (HorarioId i))
      pure (ok (detalleHorarioJson detalle))

  -- Avisos
  S.get "/avisos" $ do
    periodo <- S.queryParamMaybe "periodoId"
    atender $ \p -> do
      s <- sesion ent p
      let filtro = if esCoordinador s then Nothing else profesorSesion s
      avisos <- admin (listarAvisos bd filtro (PeriodoId <$> periodo))
      pure (ok (lista "avisos" (map avisoRegistroJson avisos)))

  S.notFound $ enviarError (ErrorApi status404 "NO_ENCONTRADO" "La ruta no existe." [])

-- | El profesor solo accede a su propio recurso; el coordinador, a cualquiera.
propio :: Entorno -> SesionUsuario -> ProfesorId -> Api ()
propio _ s profesor =
  unless (esCoordinador s || profesorSesion s == Just profesor) $
    throwE (prohibido "Un profesor solo puede acceder a su propio recurso.")

detalleProfesor :: Entorno -> ProfesorId -> Maybe Int -> [AvisoDisponibilidad] -> Api Respuesta
detalleProfesor ent profesor periodoPedido avisos = do
  let bd = baseDatos ent
  registro <- admin (buscarProfesorRegistro bd profesor)
  periodo <- periodoOReciente ent periodoPedido
  disponibilidad <- maybe (pure Nothing) (admin . disponibilidadDe bd profesor) periodo
  propuestas <- admin (listarPropuestas bd (Just profesor) periodo Nothing)
  pure (ok (profesorDetalleJson registro periodo disponibilidad propuestas avisos))

trabajoJson :: Trabajo -> Value
trabajoJson t = object
  [ "version" .= (1 :: Int)
  , "jobId" .= idTrabajo t
  , "estado" .= estadoTrabajoTexto (estadoTrabajo t)
  , "solicitud" .= object
      [ "periodoId" .= periodoTrabajo s, "modo" .= modoTrabajo s, "baseHorarioId" .= baseTrabajo s
      , "politica" .= politicaTrabajo s, "maxVersiones" .= maxVersionesTrabajo s ]
  , "creadoEn" .= creadoEnTrabajo t
  , "actualizadoEn" .= actualizadoEnTrabajo t
  , "resultado" .= (resultadoJson t >>= decodificar)
  , "error" .= (errorJson t >>= decodificar)
  ]
  where
    s = solicitudTrabajo t
    decodificar :: Text -> Maybe Value
    decodificar = decodeStrict . TE.encodeUtf8
