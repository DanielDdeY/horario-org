{-# LANGUAGE OverloadedStrings #-}

-- | Formato uniforme de error de la API (M3): @{ "codigo", "mensaje", "detalles" }@.
-- Traduce los errores de los casos de uso de M2 y del CRUD de M3 sin reinterpretar su lógica.
module Adapters.Api.Errores
  ( ErrorApi (..)
  , errorAJson
  , solicitudInvalida
  , noAutenticado
  , prohibido
  , noEncontrado
  , conflicto
  , errorInterno
  , desdeCasoUso
  , desdeAdmin
  , desdeRepositorio
  ) where

import Adapters.Sqlite.Administracion (ErrorAdmin (..))
import Data.Aeson
import Data.Text (Text)
import qualified Data.Text as Text
import Domain.Tipos
import Domain.Validador (CodigoProblema, ProblemaHorario (..))
import Network.HTTP.Types.Status
import UseCases.Errores (ErrorCasoUso (..))
import UseCases.Repositorio (ErrorRepositorio (..))

data ErrorApi = ErrorApi
  { estadoHttp :: Status
  , codigoError :: Text
  , mensajeError :: Text
  , detallesError :: [Value]
  }
  deriving (Eq, Show)

errorAJson :: ErrorApi -> Value
errorAJson e = object ["codigo" .= codigoError e, "mensaje" .= mensajeError e, "detalles" .= detallesError e]

solicitudInvalida :: Text -> ErrorApi
solicitudInvalida m = ErrorApi status400 "SOLICITUD_INVALIDA" m []

noAutenticado :: Text -> ErrorApi
noAutenticado m = ErrorApi status401 "NO_AUTENTICADO" m []

prohibido :: Text -> ErrorApi
prohibido m = ErrorApi status403 "PROHIBIDO" m []

noEncontrado :: Text -> ErrorApi
noEncontrado recurso = ErrorApi status404 "NO_ENCONTRADO" ("No existe el recurso: " <> recurso <> ".") []

conflicto :: Text -> ErrorApi
conflicto m = ErrorApi status409 "CONFLICTO" m []

errorInterno :: ErrorApi
errorInterno = ErrorApi status500 "ERROR_INTERNO" "Error interno del servidor." []

desdeRepositorio :: ErrorRepositorio -> ErrorApi
desdeRepositorio e = case e of
  RegistroNoEncontrado -> ErrorApi status404 "NO_ENCONTRADO" "El registro solicitado no existe." []
  CambioConcurrente ->
    ErrorApi status409 "CAMBIO_CONCURRENTE" "Otro cambio se guardó antes. Vuelve a consultar y reintenta." []
  FalloPersistencia detalle -> ErrorApi status500 "ERROR_INTERNO" "Falló la base de datos." [object ["detalle" .= detalle]]

desdeCasoUso :: ErrorCasoUso -> ErrorApi
desdeCasoUso e = case e of
  ErrorDeRepositorio r -> desdeRepositorio r
  EntradaInvalida problemas ->
    ErrorApi status422 "ENTRADA_INVALIDA" "Los datos del período o del horario no son válidos." (map problemaJson problemas)
  OperacionInvalida m -> ErrorApi status422 "OPERACION_INVALIDA" m []
  RestriccionesIncompatibles vs ->
    ErrorApi status409 "RESTRICCIONES_INCOMPATIBLES"
      "Las asignaciones que deben conservarse chocan entre sí. Corrige el horario base." (map violacionJson vs)
  PublicacionInvalida vs pendientes ->
    ErrorApi status409 "PUBLICACION_INVALIDA"
      "Solo se publica un borrador sin violaciones duras ni sesiones sin asignar."
      (map violacionJson vs ++ [object ["tipo" .= ("sinAsignar" :: Text), "sesionId" .= s] | SesionId s <- pendientes])
  MotorAgotoTiempo ms ->
    ErrorApi status504 "MOTOR_TIEMPO_AGOTADO" "El motor agotó el tiempo sin una solución." [object ["tiempoMs" .= ms]]
  MotorFallo m -> ErrorApi status502 "MOTOR_FALLO" m []
  SalidaMotorInvalida m vs -> ErrorApi status502 "SALIDA_MOTOR_INVALIDA" m (map violacionJson vs)

desdeAdmin :: ErrorAdmin -> ErrorApi
desdeAdmin e = case e of
  NoEncontrado recurso -> noEncontrado recurso
  Conflicto m -> conflicto m
  Invalido m -> ErrorApi status422 "ENTRADA_INVALIDA" m []
  FalloBase detalle -> ErrorApi status500 "ERROR_INTERNO" "Falló la base de datos." [object ["detalle" .= detalle]]

problemaJson :: ProblemaHorario -> Value
problemaJson (ProblemaHorario codigo detalle) =
  object ["tipo" .= ("problema" :: Text), "codigo" .= codigoTexto codigo, "detalle" .= detalle]

codigoTexto :: CodigoProblema -> Text
codigoTexto = Text.pack . show

violacionJson :: Violacion -> Value
violacionJson v = object
  [ "tipo" .= ("violacion" :: Text)
  , "codigo" .= Text.pack (show (reglaViolada v))
  , "sesiones" .= [s | SesionId s <- sesionesInvolucradas v]
  , "detalle" .= detalleViolacion v
  ]
