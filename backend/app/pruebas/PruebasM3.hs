{-# LANGUAGE OverloadedStrings #-}
-- Los patrones parciales en las pruebas fallan la prueba si el dato no tiene la forma esperada.
{-# OPTIONS_GHC -Wno-incomplete-uni-patterns #-}

-- | Pruebas de la capa de M3: el repositorio SQLite cumple el puerto 'Repositorio' de M2
-- y la API responde según `contracts/openapi.yaml`. Usan los dobles de M2 (`backend/test/Dobles.hs`)
-- para trabajar sin `swipl`.
module Main (main) where

import Adapters.Api.Autenticacion (hashContrasena)
import Adapters.Api.Servidor
import Adapters.Api.Trabajos (nuevoEjecutor, reanudar)
import Adapters.Sqlite.Conexion (BaseDatos (..))
import Adapters.Sqlite.Migraciones (migrar)
import Adapters.Sqlite.Repositorio (repositorioSqlite)
import Adapters.Sqlite.Trabajos
import Adapters.Sqlite.Usuarios (crearCoordinador)
import Control.Concurrent (threadDelay)
import Control.Monad (forM_, when)
import Control.Monad.Trans.State.Strict (runState)
import Data.Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Lazy as BL
import Data.IORef
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TE
import qualified Data.Yaml as Yaml
import Dobles
import Domain.Tipos
import Network.HTTP.Types (Method, methodDelete, methodGet, methodPost, methodPut)
import Network.HTTP.Types.Status (statusCode)
import Network.Wai (Application, requestHeaders, requestMethod)
import Network.Wai.Test
import System.Directory (doesFileExist, getTemporaryDirectory, removeFile)
import System.FilePath ((</>))
import System.IO.Unsafe (unsafePerformIO)
import Test.Hspec
import UseCases.Horarios
import UseCases.Repositorio
import UseCases.Solver

-- Utilidades ----------------------------------------------------------------------------------

contador :: IORef Int
contador = unsafePerformIO (newIORef 0)
{-# NOINLINE contador #-}

-- | Base SQLite nueva y migrada en el directorio temporal.
baseNueva :: IO BaseDatos
baseNueva = do
  n <- atomicModifyIORef' contador (\x -> (x + 1, x + 1))
  tmp <- getTemporaryDirectory
  let archivo = tmp </> ("horario-m3-prueba-" <> show n <> ".db")
  forM_ ["", "-wal", "-shm"] $ \sufijo -> do
    existe <- doesFileExist (archivo <> sufijo)
    when existe (removeFile (archivo <> sufijo))
  let bd = BaseDatos archivo
  _ <- migrar bd "migrations"
  pure bd

entornoCon :: BaseDatos -> Solver IO -> IO Entorno
entornoCon bd motor = do
  ejecutor <- nuevoEjecutor 2
  pure (Entorno bd motor ejecutor 8 4)

data Resp = Resp {codigo :: Int, cuerpoJson :: Value}
  deriving (Show)

pedir :: Application -> Method -> BC.ByteString -> Maybe Text -> Maybe Value -> IO Resp
pedir app metodo destino token cuerpo = do
  let base = defaultRequest
        { requestMethod = metodo
        , requestHeaders =
            [("Content-Type", "application/json")] ++
            [("Authorization", "Bearer " <> TE.encodeUtf8 t) | Just t <- [token]]
        }
      req = setPath base destino
  r <- runSession (srequest (SRequest req (maybe "" encode cuerpo))) app
  let valor = if BL.null (simpleBody r) then Null else maybe (String (TE.decodeUtf8 (BL.toStrict (simpleBody r)))) id
                (decode (simpleBody r))
  pure (Resp (statusCode (simpleStatus r)) valor)

(.!) :: Value -> Text -> Value
(.!) (Object o) k = maybe Null id (KeyMap.lookup (Key.fromText k) o)
(.!) _ _ = Null

entero :: Value -> Int
entero (Number n) = round n
entero v = error ("No es número: " <> show v)

arreglo :: Value -> [Value]
arreglo (Array a) = foldr (:) [] a
arreglo v = error ("No es arreglo: " <> show v)

texto :: Value -> Text
texto (String t) = t
texto v = error ("No es texto: " <> show v)

esErrorUniforme :: Value -> Bool
esErrorUniforme (Object o) =
  all (`KeyMap.member` o) ["codigo", "mensaje", "detalles"] && KeyMap.size o == 3
esErrorUniforme _ = False

ruta :: String -> BC.ByteString
ruta = BC.pack

franja :: Int -> Int -> Int -> Value
franja d i f = object ["dia" .= d, "inicioMin" .= i, "finMin" .= f]

configuracionPrueba :: Value
configuracionPrueba = object
  [ "periodoId" .= (20261 :: Int), "diasActivos" .= [1, 2, 3, 4, 5 :: Int], "inicioDiaMin" .= (480 :: Int)
  , "finDiaMin" .= (1230 :: Int), "turnoMin" .= (50 :: Int), "recesos" .= ([] :: [Value])
  , "pesos" .= object ["hueco" .= (1 :: Int), "piso" .= (2 :: Int), "edificio" .= (10 :: Int), "estabilidad" .= (5 :: Int)]
  , "toleranciaHuecoMin" .= (0 :: Int), "consecutivoMaxMin" .= (30 :: Int), "timeoutSeg" .= (60 :: Int) ]

-- | Datos de un período con un curso, un aula, una sección con dos sesiones y una profesora habilitada.
data Escenario = Escenario
  { bdEsc :: BaseDatos
  , tokenCoord :: Text
  , tokenAna :: Text
  , profesorAna :: Int
  , profesorBeto :: Int
  , cursoEsc :: Int
  , aulaEsc :: Int
  , sesion1 :: Int
  , sesion2 :: Int
  }

prepararEscenario :: IO (Escenario, Application)
prepararEscenario = do
  bd <- baseNueva
  hash <- hashContrasena 4 "clave-coordinador"
  crearCoordinador bd "coordinador" hash
  app <- entornoCon bd (solverFalso (ErrorMotor "sin motor")) >>= aplicacion
  login <- pedir app methodPost "/auth/login" Nothing
    (Just (object ["usuario" .= ("coordinador" :: Text), "contrasena" .= ("clave-coordinador" :: Text)]))
  let tc = texto (cuerpoJson login .! "token")
      como = pedir app
  cat <- como methodPost "/categorias" (Just tc) (Just (object ["nombre" .= ("Ciencias" :: Text)]))
  let catId = entero (cuerpoJson cat .! "id")
  curso <- como methodPost "/cursos" (Just tc)
    (Just (object ["codigo" .= ("MAT101" :: Text), "nombre" .= ("Cálculo I" :: Text), "categoriaId" .= catId]))
  let cursoId = entero (cuerpoJson curso .! "id")
  aula <- como methodPost "/aulas" (Just tc) (Just (object
    [ "codigo" .= ("A-101" :: Text), "capacidad" .= (40 :: Int), "edificio" .= ("A" :: Text)
    , "piso" .= (1 :: Int), "tipo" .= ("teoria" :: Text) ]))
  ana <- como methodPost "/profesores" (Just tc) (Just (object
    [ "nombre" .= ("Ana" :: Text), "categoriaId" .= catId, "cursosAptos" .= [cursoId]
    , "usuario" .= ("ana" :: Text), "contrasena" .= ("clave-de-ana" :: Text) ]))
  beto <- como methodPost "/profesores" (Just tc) (Just (object ["nombre" .= ("Beto" :: Text), "categoriaId" .= catId]))
  _ <- como methodPut "/configuracion" (Just tc) (Just configuracionPrueba)
  seccion <- como methodPost (ruta ("/cursos/" <> show cursoId <> "/secciones")) (Just tc) (Just (object
    [ "periodoId" .= (20261 :: Int), "codigo" .= ("MAT101-A" :: Text), "matriculados" .= (30 :: Int)
    , "grupos" .= [1 :: Int]
    , "sesiones" .= [ object ["duracionMin" .= (100 :: Int), "tipoAula" .= ("teoria" :: Text)]
                    , object ["duracionMin" .= (100 :: Int), "tipoAula" .= ("teoria" :: Text)] ] ]))
  let [s1, s2] = map (entero . (.! "id")) (arreglo (cuerpoJson seccion .! "sesiones"))
  loginAna <- como methodPost "/auth/login" Nothing
    (Just (object ["usuario" .= ("ana" :: Text), "contrasena" .= ("clave-de-ana" :: Text)]))
  let ta = texto (cuerpoJson loginAna .! "token")
      anaId = entero (cuerpoJson ana .! "id")
  -- Ana propone sus franjas para el curso y el coordinador las aprueba.
  propuesta <- como methodPost (ruta ("/profesores/" <> show anaId <> "/propuestas")) (Just ta) (Just (object
    [ "cursoId" .= cursoId, "periodoId" .= (20261 :: Int), "franjas" .= [franja 1 480 720, franja 2 480 720] ]))
  _ <- como methodPost (ruta ("/propuestas/" <> show (entero (cuerpoJson propuesta .! "id")) <> "/aprobar")) (Just tc) Nothing
  pure ( Escenario bd tc ta anaId (entero (cuerpoJson beto .! "id")) cursoId (entero (cuerpoJson aula .! "id")) s1 s2
       , app )

esperarTrabajo :: Application -> Text -> Int -> IO Value
esperarTrabajo app token jobId = intentar (100 :: Int)
  where
    intentar 0 = error "El trabajo no terminó a tiempo."
    intentar n = do
      r <- pedir app methodGet (ruta ("/trabajos/" <> show jobId)) (Just token) Nothing
      let estado = texto (cuerpoJson r .! "estado")
      if estado `elem` ["terminado", "error"]
        then pure (cuerpoJson r)
        else threadDelay 50000 >> intentar (n - 1)

ubicar :: Escenario -> Int -> Dia -> Int -> UbicacionSesion
ubicar e s d i = UbicacionSesion (SesionId s) (ProfesorId (profesorAna e)) (AulaId (aulaEsc e)) d i

crearAsignacion :: Escenario -> Int -> Int -> Int -> Value
crearAsignacion e s d i = object
  [ "tipo" .= ("crear" :: Text), "sesionId" .= s, "profesorId" .= profesorAna e, "aulaId" .= aulaEsc e
  , "dia" .= d, "inicioMin" .= i ]

-- Pruebas -------------------------------------------------------------------------------------

main :: IO ()
main = hspec $ do
  describe "Migraciones" $ do
    it "se aplican una sola vez" $ do
      bd <- baseNueva
      otra <- migrar bd "migrations"
      otra `shouldBe` []

  describe "Repositorio SQLite (puerto de M2)" $ do
    it "carga el contexto del período y rechaza un período sin configuración" $ do
      (e, _) <- prepararEscenario
      let repo = repositorioSqlite (bdEsc e)
      Right contexto <- cargarContexto repo (PeriodoId 20261)
      map profesorId (profesores contexto) `shouldBe` [ProfesorId (profesorAna e), ProfesorId (profesorBeto e)]
      [sesionId s | sec <- secciones contexto, s <- sesiones sec] `shouldBe` [SesionId (sesion1 e), SesionId (sesion2 e)]
      map estadoAprobacion (horariosDocentes contexto) `shouldBe` [Aprobado]
      sinPeriodo <- cargarContexto repo (PeriodoId 999)
      sinPeriodo `shouldBe` Left RegistroNoEncontrado

    it "guarda borradores, los relee iguales y detecta cambios concurrentes" $ do
      (e, _) <- prepararEscenario
      let repo = repositorioSqlite (bdEsc e)
      Right contexto <- cargarContexto repo (PeriodoId 20261)
      let datos = DatosHorario (configuracion contexto) Borrador (HorarioGenerado Version2) Nothing
            [Asignacion (ubicar e (sesion1 e) Lunes 480) True AsignacionManual] [SesionId (sesion2 e)]
      Right (h :| []) <- guardarBorradores repo (datos :| [])
      releido <- buscarHorario repo (horarioId h)
      releido `shouldBe` Right h
      let nuevo = datos {asignaciones = []}
      conflicto <- actualizarHorario repo (horarioId h) nuevo nuevo
      conflicto `shouldBe` Left CambioConcurrente
      actualizado <- actualizarHorario repo (horarioId h) datos nuevo
      fmap datosHorario actualizado `shouldBe` Right nuevo

    it "cierra una sesión y la retira de los horarios" $ do
      (e, _) <- prepararEscenario
      let repo = repositorioSqlite (bdEsc e)
      Right contexto <- cargarContexto repo (PeriodoId 20261)
      let datos = DatosHorario (configuracion contexto) Borrador HorarioManual Nothing
            [Asignacion (ubicar e (sesion1 e) Lunes 480) False AsignacionManual] [SesionId (sesion2 e)]
      Right (h :| []) <- guardarBorradores repo (datos :| [])
      cerrado <- cerrarSesion repo (PeriodoId 20261) (SesionId (sesion1 e))
      cerrado `shouldBe` Right ()
      Right despues <- cargarContexto repo (PeriodoId 20261)
      [sesionId s | sec <- secciones despues, s <- sesiones sec] `shouldBe` [SesionId (sesion2 e)]
      Right releido <- buscarHorario repo (horarioId h)
      asignaciones (datosHorario releido) `shouldBe` []

    it "rechaza aprobar una propuesta que ya no está pendiente" $ do
      (e, _) <- prepararEscenario
      let repo = repositorioSqlite (bdEsc e)
          propuesta = HorarioDocente (ProfesorId (profesorAna e)) (CursoId (cursoEsc e)) (PeriodoId 20261)
            [Franja Lunes (Intervalo 480 720)] Propuesto
      r <- aprobarHorarioDocente repo propuesta
      r `shouldBe` Left CambioConcurrente

    it "da el mismo resultado que el repositorio en memoria de M2 al editar un horario" $ do
      (e, _) <- prepararEscenario
      let repo = repositorioSqlite (bdEsc e)
          cambios = CrearAsignacion (ubicar e (sesion1 e) Lunes 480) :| [CrearAsignacion (ubicar e (sesion2 e) Lunes 580)]
      Right contexto <- cargarContexto repo (PeriodoId 20261)
      Right vacioSql <- crearHorarioVacio repo (PeriodoId 20261)
      Right editadoSql <- editarHorario repo (horarioId (horarioDetallado vacioSql)) Simular cambios
      let memoria0 = Memoria (Map.singleton (PeriodoId 20261) contexto) Map.empty []
          (Right vacioMem, memoria1) = runState (crearHorarioVacio repositorioEnMemoria (PeriodoId 20261)) memoria0
          (Right editadoMem, _) =
            runState (editarHorario repositorioEnMemoria (horarioId (horarioDetallado vacioMem)) Simular cambios) memoria1
      evaluacion editadoSql `shouldBe` evaluacion editadoMem
      motivosPendientes editadoSql `shouldBe` motivosPendientes editadoMem
      asignaciones (datosHorario (horarioDetallado editadoSql))
        `shouldBe` asignaciones (datosHorario (horarioDetallado editadoMem))

  describe "API: autenticación y roles" $ do
    it "rechaza credenciales incorrectas y peticiones sin token con el error uniforme" $ do
      (_, app) <- prepararEscenario
      malo <- pedir app methodPost "/auth/login" Nothing
        (Just (object ["usuario" .= ("coordinador" :: Text), "contrasena" .= ("otra-clave" :: Text)]))
      codigo malo `shouldBe` 401
      cuerpoJson malo `shouldSatisfy` esErrorUniforme
      sinToken <- pedir app methodGet "/aulas" Nothing Nothing
      codigo sinToken `shouldBe` 401
      texto (cuerpoJson sinToken .! "codigo") `shouldBe` "NO_AUTENTICADO"
      invalido <- pedir app methodGet "/aulas" (Just "token-falso") Nothing
      codigo invalido `shouldBe` 401

    it "reserva el CRUD al coordinador y limita al profesor a su propio recurso" $ do
      (e, app) <- prepararEscenario
      aulas <- pedir app methodGet "/aulas" (Just (tokenAna e)) Nothing
      codigo aulas `shouldBe` 403
      texto (cuerpoJson aulas .! "codigo") `shouldBe` "PROHIBIDO"
      propio <- pedir app methodGet (ruta ("/profesores/" <> show (profesorAna e))) (Just (tokenAna e)) Nothing
      codigo propio `shouldBe` 200
      ajeno <- pedir app methodGet (ruta ("/profesores/" <> show (profesorBeto e))) (Just (tokenAna e)) Nothing
      codigo ajeno `shouldBe` 403
      renombrar <- pedir app methodPut (ruta ("/profesores/" <> show (profesorAna e))) (Just (tokenAna e))
        (Just (object ["nombre" .= ("Ana B." :: Text)]))
      codigo renombrar `shouldBe` 403
      dispCoord <- pedir app methodPut (ruta ("/profesores/" <> show (profesorAna e))) (Just (tokenCoord e))
        (Just (object ["periodoId" .= (20261 :: Int), "disponibilidad" .= [franja 1 480 720]]))
      codigo dispCoord `shouldBe` 403

    it "no expone la contraseña ni el hash en las respuestas" $ do
      (e, app) <- prepararEscenario
      r <- pedir app methodGet "/profesores" (Just (tokenCoord e)) Nothing
      codigo r `shouldBe` 200
      let crudo = Text.pack (show (cuerpoJson r))
      crudo `shouldNotSatisfy` Text.isInfixOf "clave-de-ana"
      crudo `shouldNotSatisfy` Text.isInfixOf "$2b$"

  describe "API: CRUD y flujo docente" $ do
    it "responde con version, 201 al crear y 409 al borrar algo en uso" $ do
      (e, app) <- prepararEscenario
      lista <- pedir app methodGet "/cursos" (Just (tokenCoord e)) Nothing
      entero (cuerpoJson lista .! "version") `shouldBe` 1
      length (arreglo (cuerpoJson lista .! "cursos")) `shouldBe` 1
      borrar <- pedir app methodDelete (ruta ("/cursos/" <> show (cursoEsc e))) (Just (tokenCoord e)) Nothing
      codigo borrar `shouldBe` 409
      cuerpoJson borrar `shouldSatisfy` esErrorUniforme
      repetida <- pedir app methodPost "/aulas" (Just (tokenCoord e)) (Just (object
        [ "codigo" .= ("A-101" :: Text), "capacidad" .= (10 :: Int), "edificio" .= ("B" :: Text)
        , "piso" .= (2 :: Int), "tipo" .= ("teoria" :: Text) ]))
      codigo repetida `shouldBe` 409
      malformado <- pedir app methodPost "/aulas" (Just (tokenCoord e)) (Just (object ["codigo" .= ("X" :: Text)]))
      codigo malformado `shouldBe` 400
      texto (cuerpoJson malformado .! "codigo") `shouldBe` "SOLICITUD_INVALIDA"

    it "normaliza la disponibilidad del profesor y muestra la propuesta aprobada" $ do
      (e, app) <- prepararEscenario
      r <- pedir app methodPut (ruta ("/profesores/" <> show (profesorAna e))) (Just (tokenAna e)) (Just (object
        [ "periodoId" .= (20261 :: Int)
        , "disponibilidad" .= [franja 1 480 600, franja 1 600 720, franja 2 480 720] ]))
      codigo r `shouldBe` 200
      cuerpoJson r .! "disponibilidad" `shouldBe` toJSON [franja 1 480 720, franja 2 480 720]
      map (texto . (.! "estado")) (arreglo (cuerpoJson r .! "propuestas")) `shouldBe` ["aprobado"]
      map entero (arreglo (cuerpoJson r .! "cursosAptos")) `shouldBe` [cursoEsc e]

    it "permite al profesor ver solo los cursos de su categoría" $ do
      (e, app) <- prepararEscenario
      r <- pedir app methodGet "/cursos" (Just (tokenAna e)) Nothing
      codigo r `shouldBe` 200
      map (entero . (.! "id")) (arreglo (cuerpoJson r .! "cursos")) `shouldBe` [cursoEsc e]

  describe "API: horarios, edición y publicación" $ do
    it "simula sin guardar, guarda, publica y oculta borradores al profesor" $ do
      (e, app) <- prepararEscenario
      let tc = Just (tokenCoord e)
      vacio <- pedir app methodPost "/horarios" tc (Just (object ["periodoId" .= (20261 :: Int)]))
      codigo vacio `shouldBe` 201
      let h = entero (cuerpoJson vacio .! "id")
          rutaH = "/horarios/" <> show h
      map entero (arreglo (cuerpoJson vacio .! "sinAsignar")) `shouldBe` [sesion1 e, sesion2 e]
      simulado <- pedir app methodPost (ruta (rutaH <> "/cambios?simular=true")) tc (Just (object
        ["cambios" .= [crearAsignacion e (sesion1 e) 1 480, crearAsignacion e (sesion2 e) 1 580]]))
      codigo simulado `shouldBe` 200
      map (texto . (.! "codigo")) (arreglo (cuerpoJson simulado .! "violaciones")) `shouldSatisfy` elem "H09"
      sinCambios <- pedir app methodGet (ruta rutaH) tc Nothing
      arreglo (cuerpoJson sinCambios .! "asignaciones") `shouldBe` []
      oculto <- pedir app methodGet (ruta rutaH) (Just (tokenAna e)) Nothing
      codigo oculto `shouldBe` 403
      pendiente <- pedir app methodPost (ruta (rutaH <> "/publicar")) tc Nothing
      codigo pendiente `shouldBe` 409
      texto (cuerpoJson pendiente .! "codigo") `shouldBe` "PUBLICACION_INVALIDA"
      guardado <- pedir app methodPost (ruta (rutaH <> "/cambios")) tc (Just (object
        ["cambios" .= [crearAsignacion e (sesion1 e) 1 480, crearAsignacion e (sesion2 e) 2 480]]))
      codigo guardado `shouldBe` 200
      arreglo (cuerpoJson guardado .! "violaciones") `shouldBe` []
      arreglo (cuerpoJson guardado .! "sinAsignar") `shouldBe` []
      entero (cuerpoJson guardado .! "puntaje" .! "total") `shouldBe` 0
      publicado <- pedir app methodPost (ruta (rutaH <> "/publicar")) tc Nothing
      codigo publicado `shouldBe` 200
      texto (cuerpoJson publicado .! "estado") `shouldBe` "publicado"
      visibles <- pedir app methodGet "/horarios" (Just (tokenAna e)) Nothing
      map (entero . (.! "id")) (arreglo (cuerpoJson visibles .! "horarios")) `shouldBe` [h]
      -- Un cambio de disponibilidad que deja fuera una clase publicada genera avisos.
      cambio <- pedir app methodPut (ruta ("/profesores/" <> show (profesorAna e))) (Just (tokenAna e)) (Just (object
        ["periodoId" .= (20261 :: Int), "disponibilidad" .= [franja 1 600 720, franja 2 480 720]]))
      codigo cambio `shouldBe` 200
      map (entero . (.! "sesionId")) (arreglo (cuerpoJson cambio .! "avisosGenerados")) `shouldBe` [sesion1 e]
      avisosAna <- pedir app methodGet "/avisos" (Just (tokenAna e)) Nothing
      length (arreglo (cuerpoJson avisosAna .! "avisos")) `shouldBe` 1
      detalle <- pedir app methodGet (ruta rutaH) tc Nothing
      length (arreglo (cuerpoJson detalle .! "alertas")) `shouldBe` 1

    it "cierra una sesión y la saca del horario" $ do
      (e, app) <- prepararEscenario
      let tc = Just (tokenCoord e)
      vacio <- pedir app methodPost "/horarios" tc (Just (object ["periodoId" .= (20261 :: Int)]))
      let h = entero (cuerpoJson vacio .! "id")
      cerrar <- pedir app methodPost (ruta ("/sesiones/" <> show (sesion2 e) <> "/cerrar")) tc Nothing
      codigo cerrar `shouldBe` 204
      detalle <- pedir app methodGet (ruta ("/horarios/" <> show h)) tc Nothing
      map entero (arreglo (cuerpoJson detalle .! "sinAsignar")) `shouldBe` [sesion1 e]

  describe "API: generación asíncrona" $ do
    it "responde 202, termina el trabajo y guarda un borrador nuevo" $ do
      (e, _) <- prepararEscenario
      let solucion = SolucionSolver Optimo 0 [ubicar e (sesion1 e) Lunes 480, ubicar e (sesion2 e) Martes 480] []
      app <- entornoCon (bdEsc e) (solverFalso (SolucionesEncontradas (solucion :| []) 15)) >>= aplicacion
      r <- pedir app methodPost "/horarios/generar" (Just (tokenCoord e))
        (Just (object ["periodoId" .= (20261 :: Int), "modo" .= ("generar" :: Text)]))
      codigo r `shouldBe` 202
      trabajo <- esperarTrabajo app (tokenCoord e) (entero (cuerpoJson r .! "jobId"))
      texto (trabajo .! "estado") `shouldBe` "terminado"
      let [version1] = arreglo (trabajo .! "resultado" .! "versiones")
      texto (version1 .! "estadoMotor") `shouldBe` "optimo"
      detalle <- pedir app methodGet (ruta ("/horarios/" <> show (entero (version1 .! "horarioId")))) (Just (tokenCoord e)) Nothing
      texto (cuerpoJson detalle .! "origen") `shouldBe` "generado"
      texto (cuerpoJson detalle .! "estado") `shouldBe` "borrador"
      arreglo (cuerpoJson detalle .! "violaciones") `shouldBe` []

    it "termina en error y no guarda nada si la salida del motor viola una regla dura" $ do
      (e, _) <- prepararEscenario
      let solucion = SolucionSolver Optimo 0 [ubicar e (sesion1 e) Lunes 480, ubicar e (sesion2 e) Lunes 580] []
      app <- entornoCon (bdEsc e) (solverFalso (SolucionesEncontradas (solucion :| []) 15)) >>= aplicacion
      antes <- pedir app methodGet "/horarios" (Just (tokenCoord e)) Nothing
      r <- pedir app methodPost "/horarios/generar" (Just (tokenCoord e)) (Just (object ["periodoId" .= (20261 :: Int)]))
      trabajo <- esperarTrabajo app (tokenCoord e) (entero (cuerpoJson r .! "jobId"))
      texto (trabajo .! "estado") `shouldBe` "error"
      texto (trabajo .! "error" .! "codigo") `shouldBe` "SALIDA_MOTOR_INVALIDA"
      despues <- pedir app methodGet "/horarios" (Just (tokenCoord e)) Nothing
      arreglo (cuerpoJson despues .! "horarios") `shouldBe` arreglo (cuerpoJson antes .! "horarios")

    it "informa el fallo del motor y valida la solicitud antes de encolar" $ do
      (e, app) <- prepararEscenario
      r <- pedir app methodPost "/horarios/generar" (Just (tokenCoord e)) (Just (object ["periodoId" .= (20261 :: Int)]))
      trabajo <- esperarTrabajo app (tokenCoord e) (entero (cuerpoJson r .! "jobId"))
      texto (trabajo .! "error" .! "codigo") `shouldBe` "MOTOR_FALLO"
      sinBase <- pedir app methodPost "/horarios/generar" (Just (tokenCoord e))
        (Just (object ["periodoId" .= (20261 :: Int), "modo" .= ("completar" :: Text)]))
      codigo sinBase `shouldBe` 400

    it "marca como error los trabajos interrumpidos por un reinicio" $ do
      bd <- baseNueva
      i <- crearTrabajo bd (SolicitudTrabajo 20261 "generar" Nothing Nothing 1)
      _ <- marcarEjecutando bd i
      ejecutor <- nuevoEjecutor 1
      reanudar bd (solverFalso (ErrorMotor "no se usa")) ejecutor
      Just t <- buscarTrabajo bd i
      estadoTrabajo t `shouldBe` ConError
      fmap (Text.isInfixOf "TRABAJO_INTERRUMPIDO") (errorJson t) `shouldBe` Just True

  describe "API: rutas desconocidas" $
    it "responden 404 con el error uniforme" $ do
      (_, app) <- prepararEscenario
      r <- pedir app methodGet "/no-existe" Nothing Nothing
      codigo r `shouldBe` 404
      cuerpoJson r `shouldSatisfy` esErrorUniforme

  describe "Contrato contracts/openapi.yaml" $ do
    it "es YAML válido, está en borrador y todas sus referencias existen" $ do
      contrato <- leerContrato
      texto (contrato .! "info" .! "x-status") `shouldBe` "borrador"
      let componentes = contrato .! "components"
          rotas = [r | r <- referencias contrato, not (existeReferencia componentes r)]
      rotas `shouldBe` []

    it "declara exactamente las rutas que implementa el servidor" $ do
      contrato <- leerContrato
      operacionesDe contrato `shouldBe` Set.fromList rutasImplementadas

    it "cada operación del contrato está implementada (no responde 'La ruta no existe')" $ do
      (_, app) <- prepararEscenario
      forM_ rutasImplementadas $ \(camino, metodo) -> do
        let concreta = Text.replace "{seccionId}" "1" (Text.replace "{jobId}" "1" (Text.replace "{id}" "1" camino))
        r <- pedir app (TE.encodeUtf8 (Text.toUpper metodo)) (TE.encodeUtf8 concreta) Nothing Nothing
        (camino, metodo, cuerpoJson r .! "mensaje") `shouldNotBe` (camino, metodo, String "La ruta no existe.")

leerContrato :: IO Value
leerContrato = do
  r <- Yaml.decodeFileEither "../contracts/openapi.yaml"
  either (\e -> error ("openapi.yaml no es YAML válido: " <> show e)) pure r

operacionesDe :: Value -> Set.Set (Text, Text)
operacionesDe contrato = case contrato .! "paths" of
  Object rutas -> Set.fromList
    [ (Key.toText camino, Key.toText metodo)
    | (camino, Object operaciones) <- KeyMap.toList rutas
    , metodo <- KeyMap.keys operaciones
    , Key.toText metodo `elem` ["get", "post", "put", "delete", "patch"] ]
  _ -> Set.empty

referencias :: Value -> [Text]
referencias v = case v of
  Object o -> [r | Just (String r) <- [KeyMap.lookup "$ref" o]] ++ concatMap referencias (KeyMap.elems o)
  Array a -> concatMap referencias (foldr (:) [] a)
  _ -> []

existeReferencia :: Value -> Text -> Bool
existeReferencia componentes r = case Text.splitOn "/" r of
  ["#", "components", seccion, nombre] -> componentes .! seccion .! nombre /= Null
  _ -> False

rutasImplementadas :: [(Text, Text)]
rutasImplementadas =
  [ ("/auth/login", "post")
  , ("/profesores", "get"), ("/profesores", "post")
  , ("/profesores/{id}", "get"), ("/profesores/{id}", "put"), ("/profesores/{id}", "delete")
  , ("/profesores/{id}/propuestas", "post")
  , ("/propuestas", "get"), ("/propuestas/{id}/aprobar", "post")
  , ("/categorias", "get"), ("/categorias", "post"), ("/categorias/{id}", "put"), ("/categorias/{id}", "delete")
  , ("/aulas", "get"), ("/aulas", "post"), ("/aulas/{id}", "put"), ("/aulas/{id}", "delete")
  , ("/cursos", "get"), ("/cursos", "post"), ("/cursos/{id}", "put"), ("/cursos/{id}", "delete")
  , ("/cursos/{id}/secciones", "get"), ("/cursos/{id}/secciones", "post")
  , ("/cursos/{id}/secciones/{seccionId}", "put"), ("/cursos/{id}/secciones/{seccionId}", "delete")
  , ("/sesiones/{id}/cerrar", "post")
  , ("/configuracion", "get"), ("/configuracion", "put")
  , ("/horarios", "get"), ("/horarios", "post"), ("/horarios/{id}", "get")
  , ("/horarios/generar", "post"), ("/trabajos/{jobId}", "get")
  , ("/horarios/{id}/cambios", "post"), ("/horarios/{id}/publicar", "post")
  , ("/avisos", "get")
  ]

