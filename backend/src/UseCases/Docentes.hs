{-# LANGUAGE OverloadedStrings #-}

module UseCases.Docentes
  ( actualizarDisponibilidad
  , proponerHorario
  , aprobarPropuesta
  , cerrarSesionDelPeriodo
  ) where

import Control.Monad (unless, when)
import Control.Monad.Trans.Except (runExceptT, throwE)
import Data.List (find)
import Domain.Disponibilidad
import Domain.Tipos
import Domain.Validador
import UseCases.Errores
import UseCases.Horarios (avisosVigentes)
import UseCases.Repositorio

actualizarDisponibilidad
  :: Monad m => Repositorio m -> ProfesorId -> Disponibilidad -> m (Either ErrorCasoUso [AvisoDisponibilidad])
actualizarDisponibilidad repo actor nueva = runExceptT $ do
  unless (actor == profesorDisponible nueva) $
    throwE (OperacionInvalida "Solo el profesor puede cambiar su propia disponibilidad.")
  validarFranjas (franjasDisponibles nueva)
  contexto <- cargarContextoValidado repo periodo
  _ <- buscarProfesor contexto actor
  publicados <- desdeRepositorio (listarPublicados repo periodo)
  let normalizada = nueva { franjasDisponibles = normalizarFranjas (franjasDisponibles nueva) }
      mismo d = profesorDisponible d == actor && periodoDisponible d == periodo
      revisado = contexto { disponibilidades = normalizada : filter (not . mismo) (disponibilidades contexto) }
      avisos =
        [ aviso
        | horario <- publicados
        , let anteriores = avisosVigentes contexto horario
        , aviso <- avisosVigentes revisado horario
        , profesorAsignado (claseAfectada aviso) == actor
        , aviso `notElem` anteriores
        ]
  desdeRepositorio (guardarDisponibilidad repo normalizada avisos)
  pure avisos
  where
    periodo = periodoDisponible nueva

proponerHorario :: Monad m => Repositorio m -> ProfesorId -> HorarioDocente -> m (Either ErrorCasoUso ())
proponerHorario repo actor propuesta = runExceptT $ do
  unless (actor == profesorDelHorarioDocente propuesta) $
    throwE (OperacionInvalida "Solo el profesor puede proponer su propio horario.")
  contexto <- cargarContextoValidado repo (periodoDelHorarioDocente propuesta)
  comprobarPropuesta contexto propuesta
  desdeRepositorio (guardarHorarioDocente repo (normalizarPropuesta propuesta))

-- M3 invoca este caso de uso con el rol coordinador ya autenticado.
aprobarPropuesta :: Monad m => Repositorio m -> HorarioDocente -> m (Either ErrorCasoUso ())
aprobarPropuesta repo propuesta = runExceptT $ do
  contexto <- cargarContextoValidado repo (periodoDelHorarioDocente propuesta)
  comprobarPropuesta contexto propuesta
  let pendiente = normalizarPropuesta propuesta
  unless (pendiente `elem` horariosDocentes contexto) $
    throwE (OperacionInvalida "La propuesta pendiente no existe o cambió.")
  desdeRepositorio (aprobarHorarioDocente repo pendiente)

cerrarSesionDelPeriodo :: Monad m => Repositorio m -> PeriodoId -> SesionId -> m (Either ErrorCasoUso ())
cerrarSesionDelPeriodo repo periodo identificador = runExceptT $ do
  contexto <- cargarContextoValidado repo periodo
  unless (any ((== identificador) . sesionId . snd) (sesionesDelPeriodo contexto)) $
    throwE (OperacionInvalida "La sesión no pertenece al período solicitado.")
  desdeRepositorio (cerrarSesion repo periodo identificador)

normalizarPropuesta :: HorarioDocente -> HorarioDocente
normalizarPropuesta h = h
  { estadoAprobacion = Propuesto
  , franjasDelHorarioDocente = normalizarFranjas (franjasDelHorarioDocente h)
  }

comprobarPropuesta :: Monad m => ContextoHorario -> HorarioDocente -> ResultadoCasoUso m ()
comprobarPropuesta contexto h = do
  profesor <- buscarProfesor contexto (profesorDelHorarioDocente h)
  case find ((== cursoDelHorarioDocente h) . cursoId) (cursos contexto) of
    Nothing -> throwE (OperacionInvalida "El curso de la propuesta no existe.")
    Just curso -> unless (categoriaCurso curso == categoriaProfesor profesor) $
      throwE (OperacionInvalida "El curso pertenece a otra categoría.")
  when (null (franjasDelHorarioDocente h)) $
    throwE (OperacionInvalida "La propuesta necesita al menos una franja.")
  validarFranjas (franjasDelHorarioDocente h)

buscarProfesor :: Monad m => ContextoHorario -> ProfesorId -> ResultadoCasoUso m Profesor
buscarProfesor contexto identificador =
  case find ((== identificador) . profesorId) (profesores contexto) of
    Nothing -> throwE (OperacionInvalida "El profesor no existe.")
    Just profesor -> pure profesor

validarFranjas :: Monad m => [Franja] -> ResultadoCasoUso m ()
validarFranjas franjas =
  unless (all (intervaloValido . intervaloFranja) franjas) $
    throwE (EntradaInvalida [ProblemaHorario DisponibilidadInvalida "La franja horaria es inválida."])
