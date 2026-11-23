# Reglas del horario

Estado: borrador. Derivado de `DISENO_v3.md` y de las [reglas acordadas para M2](../docs/cambios/2026-11-23_0013_M2_dominio-y-reglas.md).

Los horarios usan minutos desde medianoche e intervalos semiabiertos `[inicio, fin)`. Los días se numeran del 1 (lunes) al 7 (domingo). Toda clase empieza en la grilla que parte del inicio de la jornada.

## Reglas duras

| Código | Regla |
| --- | --- |
| H01 | Un profesor dicta como máximo una sesión en cada instante. |
| H02 | En cada instante se utiliza un aula para una sola sesión. |
| H03 | La sesión cabe completa en una franja aprobada para el profesor, curso y día. Si el profesor ya registró su disponibilidad general, la franja se acota por ella. Un cambio posterior de disponibilidad en una clase publicada genera una alerta y avisos a ambas partes. |
| H04 | El número de matriculados cabe en el aula. |
| H05 | Las sesiones de un mismo grupo no se solapan. |
| H06 | El coordinador habilitó al profesor para dictar el curso. |
| H07 | El tipo del aula coincide con el requerido por la sesión. |
| H08 | La sesión cae en un día activo, empieza en la grilla, dura un múltiplo positivo del turno, cabe en la jornada y no pisa recesos. |
| H09 | Las sesiones de una misma sección se asignan a días distintos. |

H10 está retirado. El profesor define su disponibilidad y los límites de carga quedan fuera de la edición manual y de la generación. Los borradores permiten violaciones duras. Publicar exige cero violaciones y cero sesiones pendientes.

## Reglas blandas

- **S01** suma `pesoHueco × max(0, huecoMin − toleranciaHuecoMin)` por cada par de clases consecutivas del profesor en el día.
- **S02** considera cada par consecutivo del profesor en el día con un hueco dentro de `consecutivoMaxMin`. Suma `pesoPiso × diferenciaAbsolutaDePisos` más `pesoEdificio` si cambia el edificio.
- **S07** compara las asignaciones movibles de la base en una regeneración que conserva cambios. Si la nueva ubicación cambia de profesor, aula, día u hora, suma `pesoEstabilidad` una vez al profesor de la nueva ubicación. S07 vale cero para las ubicaciones retenidas y las sesiones pendientes. También vale cero cuando se genera desde cero, se descartan los cambios o se completa un horario.

El objetivo maximiza primero las sesiones ubicadas y luego minimiza la suma de S01, S02 y S07. Las alternativas se ordenan por ese costo y mantienen la cantidad de sesiones ubicadas de la primera versión. Una restricción parcial incompatible puede quedar pendiente. Las asignaciones que se conservaron completas son obligatorias.

## Validación estructural

M2 distingue `ConfiguracionInvalida`, `IdentificadorInvalido`, `IdentificadorDuplicado`, `ReferenciaInvalida`, `DuracionInvalida` y `DisponibilidadInvalida` de las violaciones H01 a H09. Un horario generado contabiliza cada sesión exactamente una vez, como asignada o pendiente. Los diagnósticos de pendientes citan una regla cuando explica la situación y describen los demás casos con el contexto del curso y los profesores elegibles.
