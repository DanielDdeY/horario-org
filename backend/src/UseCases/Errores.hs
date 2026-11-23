{-# LANGUAGE OverloadedStrings #-}

module UseCases.Errores
  ( ErrorCasoUso (..)
  , ResultadoCasoUso
  , desdeRepositorio
  , cargarContextoValidado
  ) where

import Control.Monad.Trans.Except (ExceptT (..), throwE)
import Data.Bifunctor (first)
import Data.Text (Text)
import Domain.Tipos
import Domain.Validador
import UseCases.Repositorio

data ErrorCasoUso
  = ErrorDeRepositorio ErrorRepositorio
  | EntradaInvalida [ProblemaHorario]
  | OperacionInvalida Text
  | RestriccionesIncompatibles [Violacion]
  | PublicacionInvalida [Violacion] [SesionId]
  | MotorAgotoTiempo Int
  | MotorFallo Text
  | SalidaMotorInvalida Text [Violacion]
  deriving (Eq, Show)

type ResultadoCasoUso m = ExceptT ErrorCasoUso m

desdeRepositorio :: Functor m => m (Either ErrorRepositorio a) -> ResultadoCasoUso m a
desdeRepositorio = ExceptT . fmap (first ErrorDeRepositorio)

cargarContextoValidado :: Monad m => Repositorio m -> PeriodoId -> ResultadoCasoUso m ContextoHorario
cargarContextoValidado repo periodo = do
  contexto <- desdeRepositorio (cargarContexto repo periodo)
  if periodoConfiguracion (configuracion contexto) /= periodo
    then throwE (OperacionInvalida "La configuración no corresponde al período solicitado.")
    else case validarContexto contexto of
      [] -> pure contexto
      problemas -> throwE (EntradaInvalida problemas)
