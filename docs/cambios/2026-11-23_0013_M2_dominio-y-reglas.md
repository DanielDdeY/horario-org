# M2-A · Dominio, puertos y reglas acordadas

- Fecha: 23 de noviembre de 2026, hora de Lima.
- Estado: M2-A completo. Las reglas de esta nota se deben aplicar en la implementación de los siguientes hitos.
- Referencias: `DISENO_v3.md`, `M2_nucleo_haskell.md` y las aclaraciones del coordinador del proyecto.

Esta nota actualiza los puntos del diseño v3 que se revisaron antes de programar. El resto del diseño sigue siendo la referencia del proyecto.

## Docentes, cursos y disponibilidad

- El coordinador crea los cursos, asigna una categoría a cada curso y designa una categoría para cada profesor.
- El profesor ve sus cursos asignados y puede ver otros cursos de su categoría. Para esos otros cursos puede proponer un horario. El coordinador aprueba la habilitación para dictar el curso y el horario propuesto. Una propuesta pendiente queda fuera de la generación.
- El organizador utiliza las franjas aprobadas para docentes habilitados en el curso. Si hay varios profesores elegibles, el algoritmo puede elegir entre ellos. La edición de asignaciones queda a cargo del coordinador.
- Se retira **H10**. El motor no aplica máximos diarios, máximos semanales ni descansos mínimos de carga docente. El profesor delimita su disponibilidad marcando su horario. Los límites de carga tampoco condicionan la edición del coordinador. El catálogo de reglas duras queda en H01 a H09 y se conserva su numeración.
- Los cambios de disponibilidad se guardan en la base de datos. Si una clase publicada queda fuera de la nueva disponibilidad, la clase se conserva. La interfaz muestra una alerta y se envía una notificación tanto al profesor afectado como al coordinador. La regla de disponibilidad sigue aplicándose a las nuevas asignaciones automáticas.
- Cerrar una sesión retira su asignación. Si la sesión ya figuraba en el horario publicado, se retira también de ese horario. Abrir una sesión la incorpora como pendiente para que el coordinador la asigne o el organizador la ubique con profesores y franjas aprobados.

## Regenerar, completar y editar

| Operación | Comportamiento acordado |
| --- | --- |
| Regenerar conservando cambios | Mantiene el profesor, el aula, el día y la hora de las asignaciones que creó o movió el coordinador. El motor organiza las demás sesiones alrededor de ellas. Las asignaciones retenidas no generan penalización de estabilidad. |
| Regenerar descartando cambios | Resuelve de nuevo sobre las sesiones del periodo. Ignora las asignaciones y fijaciones del horario base y crea un borrador nuevo con `fijada = false` en todas las asignaciones. |
| Completar | Conserva todas las asignaciones existentes y su valor original de `fijada`. El motor recibe sus ubicaciones como restricciones para resolver solo las pendientes. |
| Borrar una asignación | Deja la sesión pendiente y disponible para que el algoritmo la reubique. La sesión permanece abierta. |

`origenAsignacion` distingue una asignación automática de una manual. Una creación o un movimiento del coordinador deja la marca manual. `fijada` registra el bloqueo explícito. El borrador base se conserva al regenerar o completar.

## Puntaje, alternativas y sesiones pendientes

- **S02** se calcula para pares de sesiones consecutivas del mismo profesor y día, cuando su separación está dentro del umbral configurado.
- El motor maximiza primero la cantidad de sesiones asignadas y luego minimiza el costo blando. La versión 1 encabeza ese orden. El coordinador puede pedir hasta tres alternativas adicionales, distintas entre sí y de la primera, con la misma cantidad de sesiones asignadas. Se ordenan por costo blando y pueden tener un costo mayor que la versión 1. Si existen menos alternativas que las solicitadas, se devuelven las disponibles.
- Si una sesión con una restricción parcial no puede ubicarse junto con las demás, queda pendiente para el coordinador. El objetivo sigue siendo colocar el mayor número posible de sesiones.
- Para cada pendiente, el diagnóstico identifica la sesión, el curso, los profesores considerados y el motivo. Puede citar una regla dura si explica el resultado. Si había candidatos y la sesión quedó fuera al competir por recursos, el detalle explica esa situación.
- Los borradores pueden tener violaciones. Para publicar se requieren cero violaciones duras y cero sesiones pendientes. La alerta por un cambio posterior de disponibilidad se aplica sobre un horario que ya se publicó.

## Archivos e interfaces de M2-A

| Archivo | Contenido | Consumidores |
| --- | --- | --- |
| `stack.yaml` y `backend/horario-org.cabal` | Biblioteca Haskell con Stack y GHC 9.10.3. | Equipo |
| `backend/src/Domain/Tipos.hs` | Entidades, categorías, aprobación docente, estados, reglas, avisos, políticas y números de versión. | M2, M3 y M5 |
| `backend/src/UseCases/Repositorio.hs` | Puerto de lectura, persistencia de borradores, cambios de disponibilidad con avisos y cierre de sesión. | M2 y M3 |
| `backend/src/UseCases/Solver.hs` | Puerto del motor con franjas aprobadas por curso, asignaciones que se conservan, restricciones parciales, alternativas y estados de salida. | M1 y M2 |

## Verificación

Se compiló la biblioteca en una copia temporal con Stack 3.11.1, GHC 9.10.3 y el comando `stack --skip-msys --no-install-msys build --ghc-options=-Werror`, con un directorio temporal como `--stack-root`. La compilación y el registro de los tres módulos terminaron correctamente. Stack emitió un aviso por el espacio en la ruta de su caché de programas. También se verificaron los tres módulos con `ghc -fno-code -Wall -Werror -XGHC2021 -ibackend/src backend/src/Domain/Tipos.hs backend/src/UseCases/Repositorio.hs backend/src/UseCases/Solver.hs`. Las pruebas funcionales se dejan para un hito posterior.

## Integración pendiente

- **M1 y M2** deben reflejar las franjas aprobadas por curso, la retirada de H10, S02 y las alternativas en el contrato JSON del motor. El puerto Haskell admite el máximo de versiones solicitado. Falta implementar la búsqueda y acordar cómo se exponen las alternativas por contrato.
- **M3, M4 y M5** deben incorporar categorías, propuestas y aprobaciones, solicitudes de alternativas, avisos y actualización de horarios publicados al cerrar una sesión. Los roles separados de profesor y coordinador siguen vigentes.
- **M2-B** implementará el validador, los casos de uso y el adaptador. Si dos asignaciones que deben conservarse ya chocan entre sí, queda por cerrar cómo se presenta ese conflicto en la operación. La propuesta es señalar las dos asignaciones al coordinador para que corrija el borrador.
