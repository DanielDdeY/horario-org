# Reporte de cambios: M3 · API, SQLite, autenticación y trabajos

- Fecha y hora (UTC-5): 2026-11-24 03:45
- Miembro: M3
- Rama y commits: `m3/api-sqlite` · `0f91aa8`, `ed2078d`, `0ef71dd`, `1d79c08`, `00f514d`, `0b1cd9c` y el commit de este reporte
- Estado: Parcial. La capa de M3 funciona y pasa sus pruebas. Falta la integración con el motor real de M1 y que M4 y M5 revisen el contrato.

## Resumen

El núcleo de M2 ya funciona como servicio:

- contrato `openapi.yaml` en borrador;
- esquema SQLite con WAL;
- repositorio SQLite que implementa el puerto `Repositorio` sin cambiarlo;
- CRUD administrativo;
- API Scotty con token y dos roles;
- trabajos asíncronos persistidos;
- `Makefile` y `SETUP.md`.

M4 y M5 ya pueden generar sus tipos y trabajar con el mock o con la API real. Se aplicaron los acuerdos de `docs/ANTES_DE_DESARROLLAR.md`, que tiene prioridad sobre el diseño: sin H10 ni `limites`, con categorías, propuestas, aprobaciones, avisos, versiones y cierre de sesiones.

## Archivos

| Ruta | Acción | Qué cambió | Por qué |
| --- | --- | --- | --- |
| `contracts/openapi.yaml` | creado | OpenAPI 3.0.3, `x-status: borrador`. Incluye rutas, esquemas en camelCase, error uniforme, bearer token y ejemplos | Entregable 1 de M3. M4 y M5 generan sus tipos con él |
| `backend/migrations/0001_esquema_inicial.sql` | creado | Tablas del dominio, usuarios, tokens, avisos y trabajos | Entregable 2 |
| `docs/db.md` | creado | Esquema, reglas de migración, WAL e integridad | Entregable 2 |
| `backend/src/Adapters/Sqlite/Conexion.hs` | creado | Conexión por operación, `foreign_keys`, `busy_timeout` y transacción `BEGIN IMMEDIATE` | Base del adaptador |
| `backend/src/Adapters/Sqlite/Migraciones.hs` | creado | Aplica `NNNN_*.sql` una sola vez, activa WAL y registra cada script en `schema_migraciones` | Entregable 2 |
| `backend/src/Adapters/Sqlite/Codificacion.hs` | creado | Traducciones explícitas entre el dominio y SQL o JSON (día, turno, origen, configuración), sin instancias huérfanas | Evita chocar con instancias futuras de M2 |
| `backend/src/Adapters/Sqlite/Repositorio.hs` | creado | `repositorioSqlite :: BaseDatos -> Repositorio IO` | Entregable 3 |
| `backend/src/Adapters/Sqlite/Administracion.hs` | creado | CRUD de categorías, profesores, aulas, cursos, secciones y sesiones; configuración; listados de horarios, propuestas y avisos | Reparto del CRUD de `ANTES_DE_DESARROLLAR.md` |
| `backend/src/Adapters/Sqlite/Usuarios.hs` | creado | Usuarios con hash bcrypt y tokens guardados como SHA-256 | Entregable 5 |
| `backend/src/Adapters/Sqlite/Trabajos.hs` | creado | Persistencia de trabajos y su máquina de estados | Entregable 6 |
| `backend/src/Adapters/Api/*.hs` | creado | `Servidor` (rutas), `Json`, `Errores`, `Autenticacion`, `Trabajos` (semáforo de concurrencia) y `Configuracion` (variables de entorno) | Entregables 4 a 7 |
| `backend/app/Main.hs` | creado | Ejecutable `horario-servidor`: migra, crea el coordinador inicial, reanuda trabajos y sirve con Warp | Entregable 8 |
| `backend/app/pruebas/PruebasM3.hs` | creado | Suite `pruebas-m3` (22 casos) | Entregable 9 |
| `backend/horario-org.cabal` | modificado (solo líneas añadidas) | Mis módulos y dependencias en la `library`, más el ejecutable `horario-servidor` y la suite `pruebas-m3`. Diff: 60 inserciones y 0 borrados | Archivo compartido con M2 |
| `Makefile` | creado | `dev`, `backend`, `backend-build`, `backend-test`, `mock` y `frontend` | Entregable 8 |
| `docs/SETUP.md` | creado | Herramientas, compilación, variables de entorno, arranque, mock y proxy | Entregable 8 |
| `docs/solicitudes/2026-11-24_0345_M3_a_M2_integracion-repositorio.md` | creado | Uso de `Dobles`, líneas del `.cabal` y paridad con memoria | Coordinación |
| `docs/solicitudes/2026-11-24_0345_M3_a_M4_api-borrador.md` | creado | Revisión del contrato y estados de los trabajos | Coordinación |
| `docs/solicitudes/2026-11-24_0345_M3_a_M5_api-borrador-y-proxy.md` | creado | Tipos generados, mock, proxy de Vite y job de CI | Coordinación |

## Contratos e interfaces afectados

- **`contracts/openapi.yaml`:** nuevo y en borrador. Rutas:
  - `POST /auth/login`;
  - `GET/POST /profesores`, `GET/PUT/DELETE /profesores/{id}` y `POST /profesores/{id}/propuestas`;
  - `GET /propuestas` y `POST /propuestas/{id}/aprobar`;
  - `GET/POST /categorias` y `PUT/DELETE /categorias/{id}`;
  - `GET/POST /aulas` y `PUT/DELETE /aulas/{id}`;
  - `GET/POST /cursos`, `PUT/DELETE /cursos/{id}`, `GET/POST /cursos/{id}/secciones` y `PUT/DELETE /cursos/{id}/secciones/{seccionId}`;
  - `POST /sesiones/{id}/cerrar`;
  - `GET/PUT /configuracion`;
  - `GET/POST /horarios`, `GET /horarios/{id}`, `POST /horarios/generar`, `GET /trabajos/{jobId}`, `POST /horarios/{id}/cambios` (con `simular`) y `POST /horarios/{id}/publicar`;
  - `GET /avisos`.

  Deben enterarse M4 y M5 (ya tienen solicitud).
- **Puertos `Repositorio` y `Solver`:** sin cambios. Solo se implementa `Repositorio`.
- **`backend/horario-org.cabal`:** solo líneas añadidas (ver M2 abajo).
- **`stack.yaml`:** sin cambios. Todas las dependencias están en `lts-24.40`.

## Cómo verificarlo

En Windows, con GHC 9.10.3 y Stack 3.11.1 de GHCup en el `PATH`, desde la raíz:

```powershell
stack --skip-msys --no-install-msys build
stack --skip-msys --no-install-msys test
```

Resultado obtenido: `22 examples, 0 failures` y `Test suite pruebas-m3 passed`. La suite cubre:

- **Migraciones:** se aplican una sola vez.
- **Repositorio SQLite:**
  - carga el contexto y rechaza un período sin configuración (`RegistroNoEncontrado`);
  - guarda borradores y los relee iguales;
  - devuelve `CambioConcurrente` ante un cambio concurrente;
  - cierra sesiones y las retira de los horarios;
  - rechaza aprobar una propuesta que ya no está pendiente;
  - da la misma evaluación que `repositorioEnMemoria` de M2 en `crearHorarioVacio` más `editarHorario`.
- **Autenticación y roles:**
  - credenciales malas y token ausente o falso dan 401 con el error uniforme;
  - el profesor recibe 403 en el CRUD y en recursos ajenos;
  - el profesor no puede cambiar nombre ni cursos, y el coordinador no puede cambiar la disponibilidad;
  - ninguna respuesta expone la contraseña ni el hash.
- **CRUD:**
  - respuestas con `version` y 201 al crear;
  - 409 al borrar un curso en uso o repetir el código de un aula;
  - 400 `SOLICITUD_INVALIDA` ante un cuerpo incompleto.
- **Flujo docente:**
  - la disponibilidad se fusiona (480-600 más 600-720 da 480-720);
  - la propuesta aprobada aparece y habilita el curso;
  - el profesor ve solo los cursos de su categoría.
- **Horarios:**
  - `simular=true` marca H09 sin guardar;
  - el profesor no ve borradores;
  - publicar con pendientes da `409 PUBLICACION_INVALIDA`;
  - se guarda, se publica y el profesor ve el publicado;
  - un cambio de disponibilidad sobre una clase publicada genera avisos y alertas;
  - cerrar una sesión la saca del horario.
- **Generación con `solverFalso` de M2:**
  - responde 202 y el trabajo termina `terminado` con un borrador nuevo;
  - una salida del motor con una violación dura termina en `error SALIDA_MOTOR_INVALIDA` y no guarda nada;
  - `ErrorMotor` termina en `MOTOR_FALLO`;
  - `completar` sin base da 400;
  - un trabajo interrumpido por un reinicio queda en `TRABAJO_INTERRUMPIDO`.
- **Contrato:**
  - `openapi.yaml` es YAML válido, está en borrador y todas sus `$ref` existen;
  - las operaciones del contrato coinciden exactamente con las implementadas y todas responden (ninguna da "La ruta no existe").

Además:

- **Compilación estricta:** `stack exec -- ghc -fno-code -Wall -Werror ...` sobre `backend/app/Main.hs` y sobre la suite: sin avisos.
- **Prueba manual:** se levantó `horario-servidor` con una base temporal y se probó con `curl`. Funcionaron las migraciones, el coordinador inicial, `POST /auth/login`, `POST /categorias` y `POST /cursos`.
- **Detalle técnico:** Stack necesitó ejecutarse fuera del sandbox del agente para crear su base de paquetes. No se instaló ninguna herramienta global; GHC y Stack los instaló el humano.

## Supuestos y decisiones tomadas

1. **Fuente prioritaria.** `docs/ANTES_DE_DESARROLLAR.md`, por indicación humana. Por eso no hay `limites` ni H10, aunque la instrucción original de M3 los pedía.
2. **Rutas nuevas que no están en la tabla del diseño.** Las exigen los flujos aprobados en la guía:
   - `POST /profesores/{id}/propuestas`, `GET /propuestas` y `POST /propuestas/{id}/aprobar`;
   - `/categorias`;
   - `POST /sesiones/{id}/cerrar`;
   - `GET /avisos`, para la entrega de notificaciones;
   - `PUT/DELETE` sobre `/{id}` en aulas, cursos y secciones.

   Alternativa descartada: meter acciones en rutas existentes con un campo `accion`.
3. **Estados de un trabajo.** `pendiente`, `ejecutando`, `terminado` y `error`; el diseño no los define. Un trabajo que estaba `ejecutando` al reiniciar pasa a `error` (`TRABAJO_INTERRUMPIDO`) y los `pendiente` se vuelven a encolar. Descartado: reintentar automáticamente, porque podría duplicar borradores.
4. **`version: 1` en las respuestas exitosas.** Las listas van envueltas (`{version, aulas: [...]}`). El error mantiene exactamente `{codigo, mensaje, detalles}`, como dice el diseño.
5. **`periodoId` omitido.** En `GET /configuracion` y `GET /profesores/{id}` se usa el mayor período con configuración. En los listados no se filtra.
6. **`GET /configuracion?periodoId=` y `PUT /configuracion`** guardan una configuración por período. Cada horario guarda su copia en `configuracion_json`.
7. **Usuarios.**
   - El primer coordinador se crea con `HORARIO_COORDINADOR_USUARIO` y `HORARIO_COORDINADOR_CONTRASENA`; no hay secretos en el repositorio.
   - El usuario de un profesor se crea en `POST /profesores` (`usuario` y `contrasena`, mínimo 8 caracteres).
   - Solo el coordinador cambia contraseñas, y al hacerlo se invalidan los tokens de ese profesor.
   - No hay `logout`: no está en el diseño.
8. **Tokens.** Opacos, 32 bytes aleatorios en hexadecimal. Se guarda su SHA-256 y expiran a las 8 h (configurable). Bcrypt con costo 10 (configurable). Ni tokens ni contraseñas se escriben en logs. Los errores 500 se registran en stderr y llegan al cliente sin detalles.
9. **Permisos de edición.**
   - `PUT /profesores/{id}`: el coordinador cambia nombre, categoría, cursos aptos y contraseña; solo el propio profesor cambia su disponibilidad. Así lo exige `actualizarDisponibilidad` de M2, y la guía descarta que el coordinador edite la disponibilidad.
   - `GET /cursos` lo puede usar el profesor, pero solo ve los cursos de su categoría, según la guía.
   - `GET /horarios` y `GET /horarios/{id}` también los usa el profesor, solo para horarios publicados.
10. **Sesiones.**
    - Una sesión cerrada no se borra: queda `cerrada = 1`.
    - En `PUT /cursos/{id}/secciones/{seccionId}`, una sesión sin `id` se crea; una existente que no se envía se borra solo si ningún horario la usa (si no, 409).
    - No hay ruta para reabrir una sesión: para "abrirla" se crea una nueva.
11. **Horarios.**
    - Borrar un horario completo queda fuera de alcance, según la guía.
    - El detalle de las asignaciones no trae `finMin`; se calcula con la duración de la sesión.
12. **Pruebas de M3 en `backend/app/pruebas/`.** `backend/test/` es de M2, y la ruta queda dentro del territorio de M3 (`backend/app/**`). La suite compila `backend/test/Dobles.hs` sin modificarlo.
13. **Sin CORS.** En desarrollo se usa un proxy de Vite, que se pidió a M5. Descartado: añadir `wai-cors` y abrir orígenes en el servidor.
14. **Comando del motor configurable.** `HORARIO_SWIPL`, `HORARIO_MOTOR_ARGS`, `HORARIO_MOTOR_DIR`, `HORARIO_MAX_TIMEOUT_SEG` y `HORARIO_MARGEN_TIMEOUT_MS`, hasta que M1 publique el comando exacto.

## Pendientes y bloqueos

- **M1:** comando exacto de `swipl` y su directorio de trabajo (ya lo pidió M2 en `docs/solicitudes/2026-11-23_0040_M2_a_M1_contrato-del-motor.md`). Sin eso, los trabajos reales terminan en `MOTOR_FALLO`. Las pruebas usan el solver falso.
- **M4 y M5:** revisar el contrato. Solicitudes `docs/solicitudes/2026-11-24_0345_M3_a_M4_api-borrador.md` y `..._M3_a_M5_api-borrador-y-proxy.md`.
- **M2:** confirmar las líneas del `.cabal` y la estabilidad de `Dobles` (`docs/solicitudes/2026-11-24_0345_M3_a_M2_integracion-repositorio.md`).
- **Humanos:**
  - congelar `openapi.yaml` cuando M4 y M5 lo validen;
  - decidir un `.gitignore` en la raíz, que no tiene dueño en el mapa. Hoy `.stack-work/` y `backend/.stack-work/` aparecen sin seguimiento; M3 no los commitea.
- **Sin verificar:** `make dev` no se ejecutó porque esta máquina Windows no tiene `make` ni WSL. Los comandos equivalentes de PowerShell en `docs/SETUP.md` sí se probaron. El contrato se validó como YAML y por referencias, pero no con Prism ni `openapi-typescript`, que requieren descargar paquetes npm.

## Qué deben saber los otros agentes

- **M1:** nada directo. El servidor ejecuta tu motor con las variables `HORARIO_SWIPL`, `HORARIO_MOTOR_ARGS` y `HORARIO_MOTOR_DIR`.
- **M2:**
  - `repositorioSqlite` implementa tu puerto tal cual;
  - la API mapea `ErrorCasoUso` a HTTP: `EntradaInvalida` y `OperacionInvalida` dan 422; `RestriccionesIncompatibles`, `PublicacionInvalida` y `CambioConcurrente` dan 409; `RegistroNoEncontrado` da 404; los errores del motor quedan como error del trabajo;
  - en el `.cabal` solo añadí líneas;
  - la suite usa tu `Dobles.hs` sin tocarlo.
- **M3:** siguiente paso, integrar con el motor real cuando M1 publique el comando, y atender las solicitudes de M4 y M5.
- **M4:**
  - contrato en `contracts/openapi.yaml` y mock con `npx prism mock contracts/openapi.yaml`;
  - no hay `limites`;
  - la generación admite `modo`, `politica` y `maxVersiones`;
  - el detalle del horario trae `motivosSinAsignar`, `violaciones`, `puntaje` y `alertas`.
- **M5:**
  - generar los tipos desde el borrador;
  - proxy de Vite hacia `:8080`;
  - job de CI con `stack test`;
  - las pantallas del profesor usan `GET/PUT /profesores/{id}`, `POST /profesores/{id}/propuestas`, `GET /cursos` y `GET /avisos`;
  - "mis límites" ya no aplica.

## Archivos leídos como contexto

- `D:\Descargas\DISENO_v3.md` y su PDF. No existe `docs/DISENO_v3.md` en el repositorio.
- `docs/ANTES_DE_DESARROLLAR.md`, que es la fuente prioritaria.
- `D:\Descargas\M3_infraestructura.md`, más `M1`, `M2`, `M4` y `M5_*.md`.
- `contracts/reglas.md`, `contracts/motor.schema.json` y `contracts/ejemplos/m2_versiones_*.json`. `contracts/openapi.yaml` no existía al empezar.
- `docs/cambios/2026-11-23_0013_M2_dominio-y-reglas.md` y `docs/cambios/2026-11-23_0040_M2_validador-y-casos-de-uso.md`.
- `docs/solicitudes/2026-11-23_0040_M2_a_M1_contrato-del-motor.md`.
- Código de M2: `Domain/*`, `UseCases/*`, `Adapters/Prolog/*` y `backend/test/Dobles.hs`.
- Estado del repositorio: `git status`, `git log` y `git branch -a` en `main` (`14f9166`), sin cambios ajenos pendientes.
