# Base de datos SQLite

Dueño: M3. El esquema vive en `backend/migrations/` como scripts numerados (`0001_...sql`, `0002_...sql`).

## Reglas de las migraciones

- El servidor las aplica al arrancar, en orden, cada una dentro de una transacción. Registra las aplicadas en `schema_migraciones (nombre, aplicada_en)`.
- **Una migración aplicada nunca se edita.** Cualquier cambio va en un archivo nuevo con el siguiente número.
- Solo M3 escribe en `backend/migrations/`. Si otra capa necesita un cambio de esquema, lo pide por solicitud.

## Configuración de cada conexión

- `PRAGMA journal_mode = WAL`: se activa al migrar y es persistente. La API y los trabajos de generación escriben a la vez.
- `PRAGMA foreign_keys = ON` y `PRAGMA busy_timeout = 5000` en cada conexión.
- Una conexión por operación. Las operaciones que el puerto `Repositorio` declara atómicas usan una sola transacción `BEGIN IMMEDIATE`.
- El archivo de la base se indica con `HORARIO_BD` (por defecto `horario.db`). **No se commitea** ningún `*.db`, `*.db-wal` ni `*.db-shm`.

## Convenciones

Los tiempos van en minutos desde medianoche, con intervalos `[inicio, fin)`. Los días van de 1 (lunes) a 7 (domingo). Los IDs son enteros `INTEGER PRIMARY KEY`. Las fechas de auditoría son texto ISO 8601 en UTC.

Las columnas `orden` conservan el orden de las listas del dominio (días activos, recesos, franjas, asignaciones y sin asignar). Así un horario se relee exactamente igual a como se guardó, lo que permite el control de cambios concurrentes de `actualizarHorario`.

## Tablas (migración `0001_esquema_inicial.sql`)

| Tabla | Contenido | Notas |
| --- | --- | --- |
| `categorias` | `id`, `nombre` (único) | Las define el coordinador. |
| `profesores` | `id`, `nombre`, `categoria_id` | Sin `limites`: H10 está retirado. |
| `cursos` | `id`, `codigo` (único), `nombre`, `categoria_id` | |
| `profesor_cursos` | `profesor_id`, `curso_id` | Habilitación del profesor (`cursosAptos`). |
| `aulas` | `id`, `codigo` (único), `capacidad`, `edificio` (texto), `piso`, `tipo` (texto) | El adaptador de Prolog de M2 traduce los textos a enteros. |
| `configuraciones` | Una fila por `periodo_id`: jornada, turno, pesos, tolerancia, consecutivo y `timeout_seg` | `turno_min` ∈ {45, 50, 60, 90}. |
| `configuracion_dias` / `configuracion_recesos` | Días activos y recesos del período | |
| `disponibilidades` | Cabecera `(profesor_id, periodo_id)` | Distingue "registró una disponibilidad vacía" de "no registró". |
| `disponibilidad_franjas` | Franjas ya normalizadas (fusionadas) | Las normaliza M2 antes de guardar. |
| `horarios_docentes` | Propuestas (`propuesto`) y horarios aprobados (`aprobado`) por profesor, curso y período | Como máximo uno de cada estado por clave. Al aprobar, la fila conserva su `id`. |
| `horario_docente_franjas` | Franjas de cada propuesta u horario aprobado | |
| `secciones` | `id`, `curso_id`, `periodo_id`, `codigo`, `matriculados` | `codigo` es único por período. |
| `seccion_grupos` | Cohortes de la sección (H05) | |
| `sesiones` | `id`, `seccion_id`, `orden`, `duracion_min`, `tipo_aula`, `cerrada` | Una sesión cerrada se excluye del contexto y de los horarios, pero no se borra. |
| `horarios` | `estado`, `origen`, `numero_version`, `politica`, `base_horario_id`, `configuracion_json` | `configuracion_json` es la copia de la configuración con la que se creó el horario. Nunca se sobrescribe un horario con otro: cada generación inserta borradores nuevos. |
| `asignaciones` | Ubicación, `fijada` y `origen` (`manual` o `automatica`) por horario y sesión | Restricción única `(horario_id, sesion_id)`. |
| `horario_sin_asignar` | Sesiones pendientes por horario | |
| `avisos` | Clase publicada que quedó fuera de la nueva disponibilidad | Un aviso tiene dos destinatarios: el profesor y el coordinador. Se consultan con `GET /avisos`. |
| `usuarios` | `usuario` (único), `hash_contrasena` (bcrypt con sal), `rol`, `profesor_id` | Un usuario `profesor` siempre apunta a su profesor. |
| `tokens` | SHA-256 del token, usuario y vencimiento | El token en claro nunca se guarda. |
| `trabajos` | Estado (`pendiente`, `ejecutando`, `terminado`, `error`), solicitud, resultado o error en JSON | Persisten para sobrevivir a un reinicio. |

## Integridad referencial

- Borrar un profesor, un aula o una sesión que usa algún horario falla (`RESTRICT`) y la API responde `409 CONFLICTO`.
- Borrar un profesor elimina en cascada su usuario, sus tokens, su disponibilidad y sus propuestas.
- Cerrar una sesión la marca como `cerrada` y borra sus filas en `asignaciones` y `horario_sin_asignar` de todos los horarios, incluido el publicado. Todo ocurre en una transacción.
- Al arrancar, un trabajo que quedó en `ejecutando` pasa a `error` con el código `TRABAJO_INTERRUMPIDO`. Los `pendiente` se vuelven a encolar.
