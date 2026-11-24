# Qué leer antes de desarrollar

Los enlaces apuntan a archivos de `horario-org`. `DISENO_v3.md` sigue siendo la referencia del alcance general. Esta guía reúne las aclaraciones a las dudas y los puntos abiertos del diseño. Si un acuerdo posterior cambia lo que dice el diseño, los reportes o las guías de M1 y M2, aplica el acuerdo más reciente indicado aquí. Si una duda sigue abierta, documéntala en esta guía como pendiente de confirmación.

El trabajo actual de M2 se concentra en Haskell, incluido el adaptador que llama al motor. La implementación del motor en Prolog corresponde a otro desarrollador, **M1**.

## Orden de lectura para todos

1. Lee `DISENO_v3.md` para ubicar el alcance y esta guía para aplicar las aclaraciones posteriores, incluidas las decisiones del contrato y el reparto del CRUD.
2. Lee los [reportes de cambios](cambios/) en orden. El [reporte de M2-A](cambios/2026-11-23_0013_M2_dominio-y-reglas.md) recoge las decisiones sobre docentes, disponibilidad, regeneración y versiones. El [reporte de M2-B](cambios/2026-11-23_0040_M2_validador-y-casos-de-uso.md) indica qué cambió en el código, cómo se verificó y qué queda pendiente.
3. Consulta el [catálogo de reglas](../contracts/reglas.md) para H01 a H09, el puntaje y la validación estructural. Revisa también las [solicitudes de integración](solicitudes/) que afecten a tu tarea. Los reportes y las solicitudes anteriores conservan el contexto de su fecha.

Para consultar el alcance completo, usa el `DISENO_v3.md` entregado por el coordinador. Los originales `DISENO_v3.md`, `M1_motor_prolog.md` y `M2_nucleo_haskell.md` están en `C:\Users\Windows 10\Desktop\Uni\Ciclo 7\Lengua\`, fuera de `horario-org`. Si trabajas en otra máquina, usa los adjuntos que te compartió el coordinador.

## Lectura por agente

| Agente | Archivos | Qué revisar |
| --- | --- | --- |
| **M1 · Motor Prolog** | [Decisiones aprobadas](#decisiones-aprobadas-del-contrato-del-motor), [solicitud de M2](solicitudes/2026-11-23_0040_M2_a_M1_contrato-del-motor.md), [esquema JSON](../contracts/motor.schema.json), [entrada de ejemplo](../contracts/ejemplos/m2_versiones_entrada.json) y [salida de ejemplo](../contracts/ejemplos/m2_versiones_salida.json). | El [motor](../motor/main.pl) se ejecuta con `swipl -q -s motor/main.pl` desde la raíz de `horario-org`. Consulta la [configuración y la prueba local](SETUP.md#3-variables-de-entorno-del-servidor). |
| **M2 · Núcleo Haskell** | [Tipos](../backend/src/Domain/Tipos.hs), [validador](../backend/src/Domain/Validador.hs), [generación](../backend/src/UseCases/Generacion.hs), [adaptador del proceso](../backend/src/Adapters/Prolog/Proceso.hs), [lector JSON](../backend/src/Adapters/Prolog/JSON.hs) y [dobles](../backend/test/Dobles.hs). | Alinear el esquema y el adaptador Haskell con los acuerdos aprobados y verificar la integración cuando M1 entregue el motor. |
| **M3 · API y SQLite** | [Reparto del CRUD](#reparto-del-crud), [puerto Repositorio](../backend/src/UseCases/Repositorio.hs), [horarios](../backend/src/UseCases/Horarios.hs), [docentes](../backend/src/UseCases/Docentes.hs), [generación](../backend/src/UseCases/Generacion.hs) y [errores](../backend/src/UseCases/Errores.hs). | Implementar CRUD administrativo, persistencia, roles y trabajos. Reutilizar la lógica existente de horarios y docentes. El contrato OpenAPI sigue pendiente. |
| **M4 · Interfaz del coordinador** | [Acuerdos de M2-A](cambios/2026-11-23_0013_M2_dominio-y-reglas.md), [detalle de horario](../backend/src/UseCases/Horarios.hs) y [resultado de generación](../backend/src/UseCases/Generacion.hs). | Preparar aprobaciones, edición, pendientes, alertas y selección de versiones. Coordinar los campos HTTP con M3. |
| **M5 · Interfaz del profesor y QA** | [Flujo docente](../backend/src/UseCases/Docentes.hs), [catálogo de reglas](../contracts/reglas.md), [validador](../backend/src/Domain/Validador.hs) y [dobles](../backend/test/Dobles.hs). | Preparar disponibilidad, propuestas y alertas. Para QA, usar el validador para contrastar las salidas del motor cuando se integre. |

## Decisiones aprobadas del contrato del motor

1. **Formato de salida.** M1 emite siempre un arreglo `versiones` en una respuesta exitosa, aunque solo encuentre una versión. `maxVersiones` indica el total de versiones solicitadas y admite valores de 1 a 4. El adaptador Haskell mantiene la lectura del formato individual durante la transición.
2. **Asignaciones completas incompatibles.** Al regenerar conservando cambios o al completar, Haskell devuelve el conflicto antes de llamar al motor. Las asignaciones retenidas se conservan hasta que el coordinador decida qué corregir. La opción de regenerar descartando cambios sigue disponible y empieza con todas las fijaciones desactivadas.
3. **Tiempo límite y alternativas.** Si vence el tiempo y hay una solución válida, se devuelven las versiones distintas encontradas que igualen la cantidad de sesiones asignadas por la primera, ordenadas por costo blando. El lote queda en `factible`. Una versión cuyo resultado óptimo ya se demostró conserva su estado `optimo`. Se devuelve `timeout` cuando vence el tiempo y el motor aún carece de una solución válida.
4. **Ejecución y errores.** El motor recibe un JSON UTF-8 por `stdin` y responde con un JSON por `stdout`. Con código de salida 0, el JSON válido se acepta y los mensajes de `stderr` se conservan como diagnóstico. Un código distinto de 0 indica un fallo de ejecución. Una respuesta JSON con `estado: "error"` incluye `mensaje` y `tiempoMs`. M1 debe indicar el comando exacto de `swipl` y su directorio de trabajo.
5. **Campos obligatorios de entrada.** Cada franja aprobada incluye `cursoId`, cada fija incluye `obligatoria` y cada solicitud incluye `maxVersiones`. Una fija con `obligatoria: true` debe incluir profesor, aula, día e inicio, además de la sesión. Con `obligatoria: false` se respetan los campos informados si la sesión se ubica. Si esa restricción parcial resulta incompatible con el resto, la sesión puede quedar pendiente.

Estas decisiones están aprobadas. El [esquema JSON](../contracts/motor.schema.json) aún está marcado como borrador. Queda reflejar los acuerdos en el esquema y en Haskell, en particular el manejo de `stderr` y `tiempoMs` en las respuestas de error, y comprobarlos con el motor real de M1.

## Reparto del CRUD

- **M3 · API y SQLite.** Implementa las rutas HTTP y la persistencia del CRUD de profesores, aulas, categorías, cursos, secciones y sesiones. También le corresponde consultar y actualizar la configuración, listar los horarios y conectar la entrega de notificaciones.
- **M2 · Lógica de horarios.** Ya permite crear borradores, consultar su detalle, crear, mover, borrar y fijar asignaciones, simular cambios, generar, completar y publicar. Borrar una asignación deja pendiente la sesión. El diseño vigente contempla esa operación dentro del borrador. Borrar un horario completo queda fuera del alcance actual.
- **M2 · Lógica docente.** Ya valida y normaliza la disponibilidad, gestiona propuestas y aprobaciones de franjas, prepara avisos y aplica la lógica de cierre de sesiones mediante el puerto. M3 invoca estos casos de uso desde la API e implementa las operaciones del repositorio en SQLite.

## Qué se cambió

- Se retiró H10. Las franjas aprobadas para cada curso y profesor gobiernan la generación. Si hay varios docentes habilitados, el motor puede elegir.
- El coordinador define las categorías y aprueba las propuestas. Un cambio de disponibilidad conserva la clase publicada y avisa al profesor y al coordinador. Cerrar una sesión la retira del horario publicado.
- Las asignaciones distinguen su origen manual o automático. Regenerar puede conservar los cambios manuales y las fijaciones explícitas, o empezar de nuevo con todas las fijaciones desactivadas. Completar solo ubica pendientes y conserva las fijaciones originales. Borrar una asignación permite que el motor vuelva a ubicar la sesión.
- S02 cuenta pares consecutivos. Las alternativas se ordenan por costo y mantienen la cantidad de sesiones asignadas de la primera versión, con un máximo de cuatro versiones en total.
- El núcleo Haskell y el adaptador compilan con Stack. La comunicación se verificó con un proceso simulado. Los acuerdos del contrato se aprobaron después de esa verificación. Quedan pendientes su implementación completa y la integración con el motor real, SQLite y la API.
