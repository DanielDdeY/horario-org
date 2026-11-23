module Domain.Disponibilidad
  ( normalizarFranjas
  , intervaloValido
  , cubreFranja
  , disponibilidadesPorCurso
  ) where

import Data.List (sortOn)
import Domain.Tipos

intervaloValido :: Intervalo -> Bool
intervaloValido (Intervalo inicio fin) = 0 <= inicio && inicio < fin && fin <= 1440

normalizarFranjas :: [Franja] -> [Franja]
normalizarFranjas = foldr fusionar [] . sortOn (\f -> (diaFranja f, inicioMin (intervaloFranja f)))
  where
    fusionar actual (siguiente : resto)
      | diaFranja actual == diaFranja siguiente
      , finMin (intervaloFranja actual) >= inicioMin (intervaloFranja siguiente) =
          fusionar (actual { intervaloFranja = Intervalo
            (inicioMin (intervaloFranja actual))
            (max (finMin (intervaloFranja actual)) (finMin (intervaloFranja siguiente))) }) resto
    fusionar actual resto = actual : resto

cubreFranja :: [Franja] -> Franja -> Bool
cubreFranja franjas (Franja dia (Intervalo inicio fin)) =
  any cubre franjas
  where
    cubre (Franja otroDia (Intervalo desde hasta)) =
      dia == otroDia && desde <= inicio && fin <= hasta

-- Las franjas aprobadas se acotan por la disponibilidad general vigente,
-- cuando el profesor ha registrado una para este período.
disponibilidadesPorCurso :: ContextoHorario -> [(ProfesorId, CursoId, [Franja])]
disponibilidadesPorCurso contexto =
  [ (profesorId profesor, curso, franjas profesor curso)
  | profesor <- profesores contexto
  , curso <- cursosAprobados profesor
  ]
  where
    periodo = periodoConfiguracion (configuracion contexto)
    franjas profesor curso =
      case generales profesor of
        [] -> aprobadas profesor curso
        registros -> normalizarFranjas
          [ Franja (diaFranja aprobada) interseccion
          | aprobada <- aprobadas profesor curso
          , disponible <- concatMap franjasDisponibles registros
          , diaFranja aprobada == diaFranja disponible
          , let a = intervaloFranja aprobada
                b = intervaloFranja disponible
                interseccion = Intervalo (max (inicioMin a) (inicioMin b)) (min (finMin a) (finMin b))
          , intervaloValido interseccion
          ]
    generales profesor =
      [ d | d <- disponibilidades contexto
          , profesorDisponible d == profesorId profesor
          , periodoDisponible d == periodo
      ]
    aprobadas profesor curso = normalizarFranjas
      [ franja
      | h <- horariosDocentes contexto
      , profesorDelHorarioDocente h == profesorId profesor
      , cursoDelHorarioDocente h == curso
      , periodoDelHorarioDocente h == periodo
      , estadoAprobacion h == Aprobado
      , franja <- franjasDelHorarioDocente h
      ]
