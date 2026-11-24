{-# LANGUAGE OverloadedStrings #-}

-- | Traducción entre los tipos de M2/M3 y el JSON de `contracts/openapi.yaml` (M3).
-- Funciones explícitas en lugar de instancias, para no crear instancias huérfanas sobre tipos de M2.
module Adapters.Api.Json
  ( -- * Utilidades
    conVersion
  , lista
  , versionValida
    -- * Salidas
  , categoriaJson
  , aulaJson
  , cursoJson
  , seccionJson
  , profesorJson
  , profesorDetalleJson
  , propuestaJson
  , avisoJson
  , avisoRegistroJson
  , resumenHorarioJson
  , detalleHorarioJson
  , puntajeJson
    -- * Entradas
  , ProfesorEntrada (..)
  , profesorEntrada
  , ProfesorActualizacion (..)
  , profesorActualizacion
  , PropuestaEntrada (..)
  , propuestaEntrada
  , nombreEntrada
  , aulaEntrada
  , cursoEntrada
  , seccionEntrada
  , configuracionEntrada
  , periodoEntrada
  , GenerarEntrada (..)
  , generarEntrada
  , cambiosEntrada
  , LoginEntrada (..)
  , loginEntrada
  ) where

import Adapters.Sqlite.Administracion
import Adapters.Sqlite.Codificacion
import Data.Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Aeson.Types (Parser)
import Data.List.NonEmpty (NonEmpty)
import qualified Data.List.NonEmpty as NE
import Data.Text (Text)
import qualified Data.Text as Text
import Domain.Tipos
import Domain.Validador
import UseCases.Horarios (CambioHorario (..), DetalleHorario (..))

-- Utilidades ----------------------------------------------------------------------------------

-- | Añade @version: 1@ a un objeto de respuesta.
conVersion :: Value -> Value
conVersion (Object o) = Object (KeyMap.insert "version" (Number 1) o)
conVersion otro = object ["version" .= (1 :: Int), "valor" .= otro]

-- | Respuesta de lista: @{ version: 1, <nombre>: [...] }@.
lista :: Text -> [Value] -> Value
lista nombre elementos = object ["version" .= (1 :: Int), Key.fromText nombre .= elementos]

-- | En las entradas @version@ es opcional; si viene, debe valer 1.
versionValida :: Object -> Parser ()
versionValida o = do
  v <- o .:? "version"
  case v :: Maybe Int of
    Nothing -> pure ()
    Just 1 -> pure ()
    Just otra -> fail ("version no soportada: " <> show otra)


idProfesor :: ProfesorId -> Int
idProfesor (ProfesorId i) = i

idCurso :: CursoId -> Int
idCurso (CursoId i) = i

idPeriodo :: PeriodoId -> Int
idPeriodo (PeriodoId i) = i

idHorario :: HorarioId -> Int
idHorario (HorarioId i) = i

idSesion :: SesionId -> Int
idSesion (SesionId i) = i

idAula :: AulaId -> Int
idAula (AulaId i) = i

idCategoria :: CategoriaId -> Int
idCategoria (CategoriaId i) = i

-- Salidas -------------------------------------------------------------------------------------

categoriaJson :: Categoria -> Value
categoriaJson (Categoria i n) = object ["id" .= idCategoria i, "nombre" .= n]

aulaJson :: Aula -> Value
aulaJson a = object
  [ "id" .= idAula (aulaId a), "codigo" .= codigoAula a, "capacidad" .= capacidad a
  , "edificio" .= edificio a, "piso" .= piso a, "tipo" .= tipoAula a ]

cursoJson :: Curso -> Value
cursoJson c = object
  [ "id" .= idCurso (cursoId c), "codigo" .= codigoCurso c, "nombre" .= nombreCurso c
  , "categoriaId" .= idCategoria (categoriaCurso c) ]

seccionJson :: SeccionRegistro -> Value
seccionJson s = object
  [ "id" .= (let SeccionId i = idSeccion s in i)
  , "cursoId" .= idCurso (cursoDeSeccion s)
  , "periodoId" .= idPeriodo (periodoDeSeccion s)
  , "codigo" .= codigoDeSeccion s
  , "matriculados" .= matriculadosDeSeccion s
  , "grupos" .= [g | GrupoId g <- gruposDeSeccion s]
  , "sesiones" .=
      [ object [ "id" .= idSesion (sesionId se), "duracionMin" .= duracionMin se
               , "tipoAula" .= tipoAulaRequerida se, "cerrada" .= cerrada ]
      | SesionRegistro se cerrada <- sesionesDeSeccion s ]
  ]

profesorJson :: ProfesorRegistro -> Value
profesorJson (ProfesorRegistro p u) = object
  [ "id" .= idProfesor (profesorId p), "nombre" .= nombreProfesor p
  , "categoriaId" .= idCategoria (categoriaProfesor p)
  , "cursosAptos" .= map idCurso (cursosAprobados p), "usuario" .= u ]

profesorDetalleJson
  :: ProfesorRegistro -> Maybe PeriodoId -> Maybe [Franja] -> [PropuestaRegistro] -> [AvisoDisponibilidad] -> Value
profesorDetalleJson registro periodo disponibilidad propuestas avisos =
  conVersion (agregar (profesorJson registro)
    [ "periodoId" .= fmap idPeriodo periodo
    , "disponibilidad" .= fmap (map franjaAJson) disponibilidad
    , "propuestas" .= map propuestaJson propuestas
    , "avisosGenerados" .= map (avisoJson Nothing Nothing) avisos
    ])

agregar :: Value -> [(Key.Key, Value)] -> Value
agregar (Object o) pares = Object (foldr (uncurry KeyMap.insert) o pares)
agregar otro _ = otro

propuestaJson :: PropuestaRegistro -> Value
propuestaJson (PropuestaRegistro i h) = object
  [ "id" .= i
  , "profesorId" .= idProfesor (profesorDelHorarioDocente h)
  , "cursoId" .= idCurso (cursoDelHorarioDocente h)
  , "periodoId" .= idPeriodo (periodoDelHorarioDocente h)
  , "estado" .= estadoAprobacionTexto (estadoAprobacion h)
  , "franjas" .= map franjaAJson (franjasDelHorarioDocente h)
  ]

avisoJson :: Maybe Int -> Maybe Text -> AvisoDisponibilidad -> Value
avisoJson i creado (AvisoDisponibilidad h u) = object
  [ "id" .= i
  , "horarioId" .= idHorario h
  , "sesionId" .= idSesion (sesionUbicada u)
  , "profesorId" .= idProfesor (profesorAsignado u)
  , "aulaId" .= idAula (aulaAsignada u)
  , "dia" .= diaAEntero (diaAsignado u)
  , "inicioMin" .= inicioAsignadoMin u
  , "creadoEn" .= creado
  ]

avisoRegistroJson :: AvisoRegistro -> Value
avisoRegistroJson a =
  avisoJson (Just (idAviso a)) (Just (avisoCreadoEn a)) (AvisoDisponibilidad (avisoHorario a) (avisoClase a))

resumenHorarioJson :: ResumenHorario -> Value
resumenHorarioJson r = object
  [ "id" .= idHorario (idResumen r)
  , "periodoId" .= idPeriodo (periodoResumen r)
  , "estado" .= estadoResumen r
  , "origen" .= origenResumen r
  , "numeroVersion" .= versionResumen r
  , "politica" .= politicaResumen r
  , "baseHorarioId" .= fmap idHorario (baseResumen r)
  , "cantidadAsignaciones" .= cantidadAsignacionesResumen r
  , "cantidadSinAsignar" .= cantidadSinAsignarResumen r
  , "creadoEn" .= creadoEnResumen r
  ]

detalleHorarioJson :: DetalleHorario -> Value
detalleHorarioJson d = object
  [ "version" .= (1 :: Int)
  , "id" .= idHorario (horarioId horario)
  , "periodoId" .= idPeriodo (periodoConfiguracion (configuracionHorario datos))
  , "estado" .= estadoHorarioTexto (estadoHorario datos)
  , "origen" .= origenTexto plano
  , "numeroVersion" .= origenVersion plano
  , "politica" .= origenPolitica plano
  , "baseHorarioId" .= fmap idHorario (baseHorarioId datos)
  , "configuracion" .= configuracionAJson (configuracionHorario datos)
  , "asignaciones" .= map asignacionJson (asignaciones datos)
  , "sinAsignar" .= map idSesion (sinAsignar datos)
  , "motivosSinAsignar" .= map motivoJson (motivosPendientes d)
  , "violaciones" .= map violacionJson (violacionesDuras resultado)
  , "problemas" .= map problemaJson (problemasEstructurales resultado)
  , "puntaje" .= puntajeJson (puntajeHorario resultado)
  , "alertas" .= map (avisoJson Nothing Nothing) (alertasDisponibilidad d)
  ]
  where
    horario = horarioDetallado d
    datos = datosHorario horario
    resultado = evaluacion d
    plano = origenAPlano (origenHorario datos)

asignacionJson :: Asignacion -> Value
asignacionJson (Asignacion u fij origen) = object
  [ "sesionId" .= idSesion (sesionUbicada u)
  , "profesorId" .= idProfesor (profesorAsignado u)
  , "aulaId" .= idAula (aulaAsignada u)
  , "dia" .= diaAEntero (diaAsignado u)
  , "inicioMin" .= inicioAsignadoMin u
  , "fijada" .= fij
  , "origen" .= origenAsignacionTexto origen
  ]

motivoJson :: MotivoSinAsignar -> Value
motivoJson m = object
  [ "sesionId" .= idSesion (sesionPendiente m)
  , "cursoId" .= idCurso (cursoPendiente m)
  , "profesoresConsiderados" .= map idProfesor (profesoresConsiderados m)
  , "codigo" .= fmap (Text.pack . show) (reglaDelMotivo m)
  , "detalle" .= detalleMotivo m
  ]

violacionJson :: Violacion -> Value
violacionJson v = object
  [ "codigo" .= Text.pack (show (reglaViolada v))
  , "sesiones" .= map idSesion (sesionesInvolucradas v)
  , "detalle" .= detalleViolacion v
  ]

problemaJson :: ProblemaHorario -> Value
problemaJson p = object ["codigo" .= Text.pack (show (codigoProblema p)), "detalle" .= detalleProblema p]

puntajeJson :: Puntaje -> Value
puntajeJson p = object
  [ "total" .= totalBlando p
  , "sinAsignar" .= cantidadSinAsignar p
  , "porRegla" .= [object ["codigo" .= Text.pack (show r), "costo" .= c] | (r, c) <- costoPorRegla p]
  , "porProfesor" .=
      [ object (("profesorId" .= idProfesor (profesorDelCosto c)) :
                [Key.fromString (show r) .= v | (r, v) <- costoPorReglaDelProfesor c])
      | c <- costoPorProfesor p ]
  ]

-- Entradas ------------------------------------------------------------------------------------

objeto :: String -> (Object -> Parser a) -> Value -> Parser a
objeto nombre f = withObject nombre (\o -> versionValida o >> f o)

noVacio :: Text -> Text -> Parser Text
noVacio campo t
  | Text.null (Text.strip t) = fail (Text.unpack campo <> " no puede estar vacío.")
  | otherwise = pure t

positivo :: String -> Int -> Parser Int
positivo campo n
  | n > 0 = pure n
  | otherwise = fail (campo <> " debe ser un entero positivo.")

data LoginEntrada = LoginEntrada {usuarioLogin :: Text, contrasenaLogin :: Text}

loginEntrada :: Value -> Parser LoginEntrada
loginEntrada = objeto "LoginSolicitud" $ \o -> LoginEntrada <$> o .: "usuario" <*> o .: "contrasena"

nombreEntrada :: Value -> Parser Text
nombreEntrada = objeto "CategoriaEntrada" $ \o -> o .: "nombre" >>= noVacio "nombre"

aulaEntrada :: Value -> Parser DatosAula
aulaEntrada = objeto "AulaEntrada" $ \o -> do
  cap <- o .: "capacidad"
  if cap < 0 then fail "capacidad no puede ser negativa." else pure ()
  DatosAula <$> (o .: "codigo" >>= noVacio "codigo") <*> pure cap <*> (o .: "edificio" >>= noVacio "edificio")
    <*> o .: "piso" <*> (o .: "tipo" >>= noVacio "tipo")

cursoEntrada :: Value -> Parser DatosCurso
cursoEntrada = objeto "CursoEntrada" $ \o ->
  DatosCurso <$> (o .: "codigo" >>= noVacio "codigo") <*> (o .: "nombre" >>= noVacio "nombre")
    <*> (CategoriaId <$> (o .: "categoriaId" >>= positivo "categoriaId"))

seccionEntrada :: Value -> Parser DatosSeccion
seccionEntrada = objeto "SeccionEntrada" $ \o -> do
  periodo <- o .: "periodoId" >>= positivo "periodoId"
  codigo <- o .: "codigo" >>= noVacio "codigo"
  mat <- o .: "matriculados"
  if mat < 0 then fail "matriculados no puede ser negativo." else pure ()
  grupos <- o .: "grupos" >>= mapM (positivo "grupos")
  sesionesEntrada <- o .: "sesiones" >>= mapM (withObject "SesionEntrada" $ \s ->
    DatosSesion <$> (fmap SesionId <$> s .:? "id") <*> s .: "duracionMin" <*> (s .: "tipoAula" >>= noVacio "tipoAula"))
  pure (DatosSeccion (PeriodoId periodo) codigo mat (map GrupoId grupos) sesionesEntrada)

configuracionEntrada :: Value -> Parser Configuracion
configuracionEntrada v = objeto "Configuracion" (const (configuracionDeJson v)) v

periodoEntrada :: Value -> Parser PeriodoId
periodoEntrada = objeto "HorarioVacioEntrada" $ \o -> PeriodoId <$> (o .: "periodoId" >>= positivo "periodoId")

data ProfesorEntrada = ProfesorEntrada
  { nombreProfesorEntrada :: Text
  , categoriaProfesorEntrada :: CategoriaId
  , cursosProfesorEntrada :: [CursoId]
  , usuarioProfesorEntrada :: Maybe Text
  , contrasenaProfesorEntrada :: Maybe Text
  }

profesorEntrada :: Value -> Parser ProfesorEntrada
profesorEntrada = objeto "ProfesorEntrada" $ \o -> do
  usuario <- o .:? "usuario"
  contrasena <- o .:? "contrasena"
  case (usuario, contrasena) of
    (Just _, Nothing) -> fail "contrasena es obligatoria cuando se envía usuario."
    (Nothing, Just _) -> fail "contrasena solo se acepta junto con usuario."
    _ -> pure ()
  mapM_ contrasenaValida contrasena
  ProfesorEntrada <$> (o .: "nombre" >>= noVacio "nombre")
    <*> (CategoriaId <$> (o .: "categoriaId" >>= positivo "categoriaId"))
    <*> (map CursoId <$> (o .:? "cursosAptos" .!= [] >>= mapM (positivo "cursosAptos")))
    <*> traverse (noVacio "usuario") usuario
    <*> pure contrasena

contrasenaValida :: Text -> Parser ()
contrasenaValida t
  | Text.length t >= 8 = pure ()
  | otherwise = fail "contrasena debe tener al menos 8 caracteres."

data ProfesorActualizacion = ProfesorActualizacion
  { nombreActualizado :: Maybe Text
  , categoriaActualizada :: Maybe CategoriaId
  , cursosActualizados :: Maybe [CursoId]
  , contrasenaActualizada :: Maybe Text
  , periodoActualizado :: Maybe PeriodoId
  , disponibilidadActualizada :: Maybe [Franja]
  }

profesorActualizacion :: Value -> Parser ProfesorActualizacion
profesorActualizacion = objeto "ProfesorActualizacion" $ \o -> do
  contrasena <- o .:? "contrasena"
  mapM_ contrasenaValida contrasena
  disponibilidad <- o .:? "disponibilidad" >>= traverse (mapM franjaDeJson)
  periodo <- o .:? "periodoId" >>= traverse (positivo "periodoId")
  case (disponibilidad, periodo) of
    (Just _, Nothing) -> fail "periodoId es obligatorio cuando se envía disponibilidad."
    _ -> pure ()
  ProfesorActualizacion
    <$> (o .:? "nombre" >>= traverse (noVacio "nombre"))
    <*> (fmap CategoriaId <$> (o .:? "categoriaId" >>= traverse (positivo "categoriaId")))
    <*> (fmap (map CursoId) <$> (o .:? "cursosAptos" >>= traverse (mapM (positivo "cursosAptos"))))
    <*> pure contrasena
    <*> pure (PeriodoId <$> periodo)
    <*> pure disponibilidad

data PropuestaEntrada = PropuestaEntrada
  { cursoPropuesta :: CursoId
  , periodoPropuesta :: PeriodoId
  , franjasPropuesta :: [Franja]
  }

propuestaEntrada :: Value -> Parser PropuestaEntrada
propuestaEntrada = objeto "PropuestaEntrada" $ \o ->
  PropuestaEntrada <$> (CursoId <$> (o .: "cursoId" >>= positivo "cursoId"))
    <*> (PeriodoId <$> (o .: "periodoId" >>= positivo "periodoId"))
    <*> (o .: "franjas" >>= mapM franjaDeJson)

data GenerarEntrada = GenerarEntrada
  { periodoGenerar :: Int
  , modoGenerar :: Text
  , baseGenerar :: Maybe Int
  , politicaGenerar :: Maybe Text
  , maxVersionesGenerar :: Int
  }

generarEntrada :: Value -> Parser GenerarEntrada
generarEntrada = objeto "GenerarEntrada" $ \o -> do
  periodo <- o .: "periodoId" >>= positivo "periodoId"
  modo <- o .:? "modo" .!= "generar"
  base <- o .:? "baseHorarioId" >>= traverse (positivo "baseHorarioId")
  politica <- o .:? "politica"
  maximo <- o .:? "maxVersiones" .!= 1
  if modo `notElem` ["generar", "completar"] then fail "modo debe ser generar o completar." else pure ()
  if maximo < 1 || maximo > 4 then fail "maxVersiones debe estar entre 1 y 4." else pure ()
  case politica of
    Nothing -> pure ()
    Just p
      | p `notElem` ["conservar", "descartar"] -> fail "politica debe ser conservar o descartar."
      | modo /= "generar" || base == Nothing -> fail "politica solo aplica a modo generar con baseHorarioId."
      | otherwise -> pure ()
  if modo == "completar" && base == Nothing then fail "El modo completar exige baseHorarioId." else pure ()
  let politicaEfectiva = case (modo, base, politica) of
        ("generar", Just _, Nothing) -> Just "conservar"
        _ -> politica
  pure (GenerarEntrada periodo modo base politicaEfectiva maximo)

cambiosEntrada :: Value -> Parser (NonEmpty CambioHorario)
cambiosEntrada = objeto "CambiosEntrada" $ \o -> do
  cambios <- o .: "cambios" >>= mapM cambio
  maybe (fail "cambios debe tener al menos un elemento.") pure (NE.nonEmpty cambios)
  where
    cambio = withObject "CambioAsignacion" $ \o -> do
      tipo <- o .: "tipo"
      sesion <- SesionId <$> (o .: "sesionId" >>= positivo "sesionId")
      let ubicacionDe = do
            profesor <- o .: "profesorId" >>= positivo "profesorId"
            aula <- o .: "aulaId" >>= positivo "aulaId"
            diaN <- o .: "dia"
            d <- maybe (fail "dia debe estar entre 1 y 7.") pure (diaDeEntero diaN)
            inicio <- o .: "inicioMin"
            pure (UbicacionSesion sesion (ProfesorId profesor) (AulaId aula) d inicio)
      case tipo :: Text of
        "crear" -> CrearAsignacion <$> ubicacionDe
        "mover" -> MoverAsignacion <$> ubicacionDe
        "borrar" -> pure (BorrarAsignacion sesion)
        "fijar" -> FijarAsignacion sesion <$> o .: "fijada"
        _ -> fail "tipo debe ser crear, mover, borrar o fijar."

