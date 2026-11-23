{-# LANGUAGE OverloadedStrings #-}

module Adapters.Prolog.JSON (codificarSolicitud, leerRespuesta) where

import Control.Monad (unless, when)
import Data.Aeson
import Data.Aeson.Types (Pair, Parser, parseEither)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as Lazy
import qualified Data.List.NonEmpty as NE
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import Domain.Tipos
import UseCases.Solver

codificarSolicitud :: SolicitudSolver -> BS.ByteString
codificarSolicitud solicitud = Lazy.toStrict $ encode $ object
  [ "version" .= (1 :: Int)
  , "config" .= object
    [ "dias" .= map numeroDia (diasActivos config)
    , "inicioDiaMin" .= inicioMin (jornada config)
    , "finDiaMin" .= finMin (jornada config)
    , "turnoMin" .= case turno config of
        Min45 -> 45 :: Int
        Min50 -> 50
        Min60 -> 60
        Min90 -> 90
    , "recesos" .= map intervalo (recesos config)
    , "pesos" .= object
      [ "hueco" .= pesoHueco p, "piso" .= pesoPiso p
      , "edificio" .= pesoEdificio p, "estabilidad" .= pesoEstabilidad p ]
    , "toleranciaHuecoMin" .= toleranciaHuecoMin config
    , "consecutivoMaxMin" .= consecutivoMaxMin config
    , "timeoutSeg" .= timeoutSeg config
    ]
  , "profesores" .=
    [ object ["id" .= idProfesor docente, "cursosAptos" .= map idCurso (Set.toAscList materias)]
    | (docente, materias) <- Map.toAscList cursosPorProfesor ]
  , "disponibilidades" .=
    [ object (["profesorId" .= idProfesor docente, "cursoId" .= idCurso materia, "dia" .= numeroDia dia] ++ extremos minutos)
    | DisponibilidadAprobada docente materia franjas <- aprobadas, Franja dia minutos <- franjas ]
  , "aulas" .=
    [ object [ "id" .= idAula (aulaId aula), "capacidad" .= capacidad aula
             , "edificio" .= (edificios Map.! edificio aula), "piso" .= piso aula
             , "tipo" .= (tipos Map.! tipoAula aula) ]
    | aula <- salas ]
  , "sesiones" .=
    [ object [ "id" .= idSesion (sesionId sesion), "cursoId" .= idCurso (cursoSeccion seccion)
             , "seccionId" .= iSeccion, "duracionMin" .= duracionMin sesion, "matriculados" .= matriculados seccion
             , "tipoAula" .= (tipos Map.! tipoAulaRequerida sesion)
             , "grupos" .= [i | GrupoId i <- grupos seccion] ]
    | seccion <- seccionesSolver solicitud, let SeccionId iSeccion = seccionId seccion, sesion <- sesiones seccion ]
  , "fijas" .= (map (object . (("obligatoria" .= True) :) . ubicacionJSON) (asignacionesConservadas solicitud)
      ++ map restriccionJSON (restriccionesParciales solicitud))
  , "previas" .= map (object . ubicacionJSON) (asignacionesPrevias solicitud)
  , "maxVersiones" .= length (takeWhile (<= hastaVersionSolver solicitud) [Version1, Version2, Version3, Version4])
  ]
  where
    config = configuracionSolver solicitud
    p = pesos config
    salas = aulasSolver solicitud
    aprobadas = disponibilidadesAprobadas solicitud
    cursosPorProfesor = Map.fromListWith Set.union
      [(profesorHabilitado d, Set.singleton (cursoHabilitado d)) | d <- aprobadas]
    edificios = diccionario (map edificio salas)
    tipos = diccionario (map tipoAula salas ++
      [tipoAulaRequerida sesion | seccion <- seccionesSolver solicitud, sesion <- sesiones seccion])
    diccionario valores = Map.fromList (zip (Set.toAscList (Set.fromList valores)) [1 :: Int ..])
    intervalo = object . extremos
    extremos minutos = ["inicioMin" .= inicioMin minutos, "finMin" .= finMin minutos]

idProfesor :: ProfesorId -> Int
idProfesor (ProfesorId i) = i

idAula :: AulaId -> Int
idAula (AulaId i) = i

idSesion :: SesionId -> Int
idSesion (SesionId i) = i

idCurso :: CursoId -> Int
idCurso (CursoId i) = i

numeroDia :: Dia -> Int
numeroDia dia = case dia of
  Lunes -> 1
  Martes -> 2
  Miercoles -> 3
  Jueves -> 4
  Viernes -> 5
  Sabado -> 6
  Domingo -> 7

ubicacionJSON :: UbicacionSesion -> [Pair]
ubicacionJSON u =
  [ "sesionId" .= idSesion (sesionUbicada u), "profesorId" .= idProfesor (profesorAsignado u)
  , "aulaId" .= idAula (aulaAsignada u), "dia" .= numeroDia (diaAsignado u)
  , "inicioMin" .= inicioAsignadoMin u
  ]

restriccionJSON :: RestriccionAsignacion -> Value
restriccionJSON r = object $
  ["sesionId" .= idSesion (sesionRestringida r), "obligatoria" .= False] ++
  ["profesorId" .= idProfesor p | Just p <- [profesorRestringido r]] ++
  ["aulaId" .= idAula a | Just a <- [aulaRestringida r]] ++
  ["dia" .= numeroDia d | Just d <- [diaRestringido r]] ++
  ["inicioMin" .= inicio | Just inicio <- [inicioRestringidoMin r]]

leerRespuesta :: BS.ByteString -> Either Text ResultadoSolver
leerRespuesta salida =
  case eitherDecodeStrict' salida >>= parseEither (withObject "respuesta del motor" leer) of
    Left problema -> Left (Text.pack problema)
    Right resultado -> Right resultado
  where
    leer o = do
      version <- o .: "version"
      unless (version == (1 :: Int)) (fail "Versión de JSON del motor no soportada.")
      estado <- o .: "estado"
      case estado :: Text of
        "timeout" -> TiempoAgotado <$> tiempo o
        "error" -> ErrorMotor <$> o .: "mensaje"
        _ -> do
          inicial <- leerEstado estado
          ms <- tiempo o
          lote <- o .:? "versiones"
          versiones <- case lote of
            Nothing -> NE.singleton <$> leerSolucion inicial o
            Just entradas -> do
              when (length entradas > 4) (fail "El motor devolvió más de cuatro versiones.")
              lista <- traverse (withObject "versión de horario" (leerSolucion inicial)) entradas
              maybe (fail "El lote exitoso de versiones está vacío.") pure (NE.nonEmpty lista)
          pure (SolucionesEncontradas versiones ms)
    tiempo o = do
      ms <- o .: "tiempoMs"
      when (ms < 0) (fail "El tiempo del motor no puede ser negativo.")
      pure ms

leerEstado :: Text -> Parser EstadoSolucion
leerEstado "optimo" = pure Optimo
leerEstado "factible" = pure Factible
leerEstado _ = fail "Estado del motor desconocido."

leerSolucion :: EstadoSolucion -> Object -> Parser SolucionSolver
leerSolucion porDefecto o = do
  estado <- o .:? "estado"
  calidad <- maybe (pure porDefecto) leerEstado estado
  costo <- o .: "costo"
  when (costo < 0) (fail "El costo del motor no puede ser negativo.")
  asignadas <- o .: "asignaciones" >>= traverse (withObject "asignación" leerUbicacion)
  pendientes <- o .: "sinAsignar" >>= traverse (positivo "ID de sesión pendiente")
  pure (SolucionSolver calidad costo asignadas (map SesionId pendientes))

leerUbicacion :: Object -> Parser UbicacionSesion
leerUbicacion o = do
  sesion <- o .: "sesionId" >>= positivo "ID de sesión"
  profesor <- o .: "profesorId" >>= positivo "ID de profesor"
  aula <- o .: "aulaId" >>= positivo "ID de aula"
  dia <- o .: "dia" >>= leerDia
  inicio <- o .: "inicioMin"
  unless (inicio >= 0 && inicio < 1440) (fail "Inicio de asignación fuera del día.")
  pure (UbicacionSesion (SesionId sesion) (ProfesorId profesor) (AulaId aula) dia inicio)

positivo :: String -> Int -> Parser Int
positivo etiqueta i
  | i > 0 = pure i
  | otherwise = fail (etiqueta ++ " debe ser positivo.")

leerDia :: Int -> Parser Dia
leerDia n = case lookup n (zip [1 ..] [Lunes, Martes, Miercoles, Jueves, Viernes, Sabado, Domingo]) of
  Just dia -> pure dia
  Nothing -> fail "Día del motor fuera del rango 1 a 7."
