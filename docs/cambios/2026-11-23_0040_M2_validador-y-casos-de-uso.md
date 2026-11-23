# M2-B · Validador, casos de uso y adaptador de Prolog

- Fecha: 23 de noviembre de 2026, hora de Lima.
- Estado: núcleo implementado. Integración con el motor real pendiente.
- Contexto leído: `DISENO_v3.md`, `M2_nucleo_haskell.md`, el acuerdo de M2-A y los tipos y puertos del backend. Al empezar, el proyecto tenía el commit `f23014d` y no había contrato del motor ni reportes de M1.

## Entrega

| Archivo | Cambio |
| --- | --- |
| `backend/src/Domain/Disponibilidad.hs` | Fusiona franjas contiguas o superpuestas y obtiene franjas efectivas por profesor y curso. |
| `backend/src/Domain/Validador.hs` | Valida estructura y H01 a H09, calcula S01/S02/S07 y explica pendientes. |
| `backend/src/UseCases/Horarios.hs` | Crea, consulta, edita, simula y publica horarios. La consulta incluye las alertas vigentes. |
| `backend/src/UseCases/Generacion.hs` | Genera, regenera y completa a través del puerto. Verifica el lote y el costo antes de guardar los borradores juntos. |
| `backend/src/UseCases/Docentes.hs` | Registra disponibilidad con avisos, propone y aprueba franjas y solicita el cierre de sesiones. |
| `backend/src/UseCases/Errores.hs` | Define los errores de aplicación que M3 puede mapear a su API. |
| `backend/src/Adapters/Prolog/JSON.hs` y `Proceso.hs` | Codifican el contrato borrador, manejan la respuesta y controlan el proceso y su tiempo límite. |
| `backend/test/Dobles.hs` | Proporciona un repositorio en memoria y un solver falso para integración. |
| `contracts/reglas.md`, `contracts/motor.schema.json` y `contracts/ejemplos/m2_versiones_*.json` | Documentan el catálogo vigente, el borrador JSON y un ejemplo con dos versiones. |

El snapshot de Stack se fijó en LTS 24.40 con GHC 9.10.3. Incluye Aeson para JSON y async para leer las tuberías del proceso de forma concurrente. [Stackage LTS 24.40](https://www.stackage.org/lts-24.40)

## Decisiones de implementación

- La disponibilidad efectiva es la intersección de las franjas aprobadas del curso con las franjas generales del docente cuando existe un registro de estas últimas.
- Regenerar conservando cambios retiene las ubicaciones manuales y las explícitamente fijadas. Las movibles siguen siendo candidatas a S07. Si una fija completa entra en conflicto con otra, se devuelve un error con las sesiones involucradas antes de ejecutar el motor. Una restricción parcial permite que la sesión quede pendiente.
- La ubicación publicada se conserva tras un cambio de disponibilidad. El detalle del horario devuelve una alerta vigente mientras dure el conflicto. El repositorio recibe los avisos nuevos al guardar el cambio; M3 debe persistirlos y dirigirlos al profesor y al coordinador.
- Las siguientes alternativas se piden como un máximo de versiones dentro de una búsqueda. Se rechaza el lote completo si contiene duplicados, presenta costos fuera de orden o una versión ubica menos sesiones. Cuando aparece una solución `factible`, la cantidad máxima de sesiones todavía puede estar sin demostrar.
- Se añadieron los constructores `HorarioRegenerado` y `HorarioCompletado` para conservar la modalidad y recuperar el contexto de S07. Los tipos del motor y las firmas originales de ambos puertos siguen disponibles.

## Verificación

- Compilación con Stack 3.11.1 y GHC 9.10.3 mediante `stack --skip-msys --no-install-msys build --ghc-options=-Werror`.
- Verificación temporal con GHC `-threaded -Wall -Werror`, el repositorio en memoria y un proceso simulado. Se comprobaron la detección de H01 a H09, la atribución de S07, la simulación sin escritura, el rechazo atómico de alternativas duplicadas, las fijaciones, las alertas sobre clases publicadas, el cierre de sesiones, el JSON, stderr, el código de salida y el tiempo límite.
- Los dos ejemplos JSON se validaron contra el borrador del esquema con `Test-Json -SchemaFile contracts/motor.schema.json`.

## Integración pendiente

- **M1** debe confirmar el [contrato borrador y el comando de SWI-Prolog](../solicitudes/2026-11-23_0040_M2_a_M1_contrato-del-motor.md). El adaptador se verificó con un proceso simulado.
- **M3** debe implementar el repositorio SQLite y su atomicidad para borradores, disponibilidad y avisos, aprobación y cierre. API y trabajos invocan los casos de uso. M3 autentica el rol coordinador en las operaciones que le corresponden. El ejecutable que integra el adaptador debe enlazarse con `-threaded`.
- **M4 y M5** consumen los detalles, las alertas, los pendientes y la lista de versiones. La suite funcional del proyecto queda para la etapa acordada de pruebas.
