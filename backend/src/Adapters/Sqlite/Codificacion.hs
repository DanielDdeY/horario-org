{-# LANGUAGE OverloadedStrings #-}

-- | Traducciones entre los tipos del dominio de M2 y su forma en SQLite y JSON (M3).
-- Funciones explícitas, sin instancias huérfanas, para no chocar con instancias futuras de M2.
module Adapters.Sqlite.Codificacion
  ( diaAEntero
  , diaDeEntero
  , turnoAEntero
  , turnoDeEntero
  , estadoHorarioTexto
  , estadoHorarioDeTexto
  , origenAsignacionTexto
  , origenAsignacionDeTexto
  , politicaTexto
  , politicaDeTexto
  , numeroVersionAEntero
  , numeroVersionDeEntero
  , OrigenPlano (..)
  , origenAPlano
  , origenDePlano
  , estadoAprobacionTexto
  , estadoAprobacionDeTexto
  , configuracionAJson
  , configuracionDeJson
  , franjaAJson
  , franjaDeJson
  , intervaloAJson
  , intervaloDeJson
  ) where

import Data.Aeson
import Data.Aeson.Types (Parser)
import Data.Text (Text)
import Domain.Tipos

diaAEntero :: Dia -> Int
diaAEntero d = case d of
  Lunes -> 1
  Martes -> 2
  Miercoles -> 3
  Jueves -> 4
  Viernes -> 5
  Sabado -> 6
  Domingo -> 7

diaDeEntero :: Int -> Maybe Dia
diaDeEntero n = case n of
  1 -> Just Lunes
  2 -> Just Martes
  3 -> Just Miercoles
  4 -> Just Jueves
  5 -> Just Viernes
  6 -> Just Sabado
  7 -> Just Domingo
  _ -> Nothing

turnoAEntero :: Turno -> Int
turnoAEntero t = case t of
  Min45 -> 45
  Min50 -> 50
  Min60 -> 60
  Min90 -> 90

turnoDeEntero :: Int -> Maybe Turno
turnoDeEntero n = case n of
  45 -> Just Min45
  50 -> Just Min50
  60 -> Just Min60
  90 -> Just Min90
  _ -> Nothing

estadoHorarioTexto :: EstadoHorario -> Text
estadoHorarioTexto Borrador = "borrador"
estadoHorarioTexto Publicado = "publicado"

estadoHorarioDeTexto :: Text -> Maybe EstadoHorario
estadoHorarioDeTexto t = case t of
  "borrador" -> Just Borrador
  "publicado" -> Just Publicado
  _ -> Nothing

origenAsignacionTexto :: OrigenAsignacion -> Text
origenAsignacionTexto AsignacionManual = "manual"
origenAsignacionTexto AsignacionAutomatica = "automatica"

origenAsignacionDeTexto :: Text -> Maybe OrigenAsignacion
origenAsignacionDeTexto t = case t of
  "manual" -> Just AsignacionManual
  "automatica" -> Just AsignacionAutomatica
  _ -> Nothing

politicaTexto :: PoliticaCambios -> Text
politicaTexto ConservarCambios = "conservar"
politicaTexto DescartarCambios = "descartar"

politicaDeTexto :: Text -> Maybe PoliticaCambios
politicaDeTexto t = case t of
  "conservar" -> Just ConservarCambios
  "descartar" -> Just DescartarCambios
  _ -> Nothing

numeroVersionAEntero :: NumeroVersion -> Int
numeroVersionAEntero v = case v of
  Version1 -> 1
  Version2 -> 2
  Version3 -> 3
  Version4 -> 4

numeroVersionDeEntero :: Int -> Maybe NumeroVersion
numeroVersionDeEntero n = case n of
  1 -> Just Version1
  2 -> Just Version2
  3 -> Just Version3
  4 -> Just Version4
  _ -> Nothing

-- | Origen del horario en tres columnas: origen, número de versión y política.
data OrigenPlano = OrigenPlano
  { origenTexto :: Text
  , origenVersion :: Maybe Int
  , origenPolitica :: Maybe Text
  }
  deriving (Eq, Show)

origenAPlano :: OrigenHorario -> OrigenPlano
origenAPlano o = case o of
  HorarioManual -> OrigenPlano "manual" Nothing Nothing
  HorarioGenerado v -> OrigenPlano "generado" (Just (numeroVersionAEntero v)) Nothing
  HorarioRegenerado v p -> OrigenPlano "regenerado" (Just (numeroVersionAEntero v)) (Just (politicaTexto p))
  HorarioCompletado v -> OrigenPlano "completado" (Just (numeroVersionAEntero v)) Nothing

origenDePlano :: OrigenPlano -> Maybe OrigenHorario
origenDePlano (OrigenPlano texto version politica) = case texto of
  "manual" -> Just HorarioManual
  "generado" -> HorarioGenerado <$> numero
  "regenerado" -> HorarioRegenerado <$> numero <*> (politica >>= politicaDeTexto)
  "completado" -> HorarioCompletado <$> numero
  _ -> Nothing
  where
    numero = version >>= numeroVersionDeEntero

estadoAprobacionTexto :: EstadoAprobacion -> Text
estadoAprobacionTexto Propuesto = "propuesto"
estadoAprobacionTexto Aprobado = "aprobado"

estadoAprobacionDeTexto :: Text -> Maybe EstadoAprobacion
estadoAprobacionDeTexto t = case t of
  "propuesto" -> Just Propuesto
  "aprobado" -> Just Aprobado
  _ -> Nothing

intervaloAJson :: Intervalo -> Value
intervaloAJson (Intervalo i f) = object ["inicioMin" .= i, "finMin" .= f]

intervaloDeJson :: Value -> Parser Intervalo
intervaloDeJson = withObject "Intervalo" $ \o -> Intervalo <$> o .: "inicioMin" <*> o .: "finMin"

franjaAJson :: Franja -> Value
franjaAJson (Franja d (Intervalo i f)) = object ["dia" .= diaAEntero d, "inicioMin" .= i, "finMin" .= f]

franjaDeJson :: Value -> Parser Franja
franjaDeJson = withObject "Franja" $ \o ->
  Franja <$> (o .: "dia" >>= dia) <*> (Intervalo <$> o .: "inicioMin" <*> o .: "finMin")

dia :: Int -> Parser Dia
dia n = maybe (fail ("Día fuera de rango (1 a 7): " <> show n)) pure (diaDeEntero n)

-- | Configuración en el formato JSON del contrato (`Configuracion` en openapi.yaml).
configuracionAJson :: Configuracion -> Value
configuracionAJson c = object
  [ "periodoId" .= (let PeriodoId p = periodoConfiguracion c in p)
  , "diasActivos" .= map diaAEntero (diasActivos c)
  , "inicioDiaMin" .= inicioMin (jornada c)
  , "finDiaMin" .= finMin (jornada c)
  , "turnoMin" .= turnoAEntero (turno c)
  , "recesos" .= map intervaloAJson (recesos c)
  , "pesos" .= object
      [ "hueco" .= pesoHueco (pesos c)
      , "piso" .= pesoPiso (pesos c)
      , "edificio" .= pesoEdificio (pesos c)
      , "estabilidad" .= pesoEstabilidad (pesos c)
      ]
  , "toleranciaHuecoMin" .= toleranciaHuecoMin c
  , "consecutivoMaxMin" .= consecutivoMaxMin c
  , "timeoutSeg" .= timeoutSeg c
  ]

configuracionDeJson :: Value -> Parser Configuracion
configuracionDeJson = withObject "Configuracion" $ \o -> do
  periodo <- o .: "periodoId"
  dias <- o .: "diasActivos" >>= mapM dia
  inicio <- o .: "inicioDiaMin"
  fin <- o .: "finDiaMin"
  turnoN <- o .: "turnoMin"
  t <- maybe (fail "turnoMin debe ser 45, 50, 60 o 90.") pure (turnoDeEntero turnoN)
  rs <- o .: "recesos" >>= mapM intervaloDeJson
  ps <- o .: "pesos" >>= withObject "Pesos" (\p ->
    Pesos <$> p .: "hueco" <*> p .: "piso" <*> p .: "edificio" <*> p .: "estabilidad")
  tolerancia <- o .:? "toleranciaHuecoMin" .!= 0
  consecutivo <- o .:? "consecutivoMaxMin" .!= 30
  tiempo <- o .: "timeoutSeg"
  pure (Configuracion (PeriodoId periodo) dias (Intervalo inicio fin) t rs ps tolerancia consecutivo tiempo)
