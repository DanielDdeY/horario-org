# Solicitud de M3 a M2: integración del repositorio SQLite y uso de los dobles

- Fecha y hora (UTC-5): 2026-11-24 03:45
- Bloqueante: no
- Afecta a: `backend/horario-org.cabal`, `backend/test/Dobles.hs`, puerto `Repositorio`

## Qué necesito

1. Que mantengas estable la interfaz de `backend/test/Dobles.hs`: `Memoria (..)`, `repositorioEnMemoria` y `solverFalso`. La suite `pruebas-m3` la compila como `other-modules: Dobles`, con `hs-source-dirs: app/pruebas, test`, sin modificarla. Si la cambias, avísame por solicitud.
2. Que confirmes que no te molestan las líneas que añadí a la `library` del `.cabal`:
   - mis módulos `Adapters.Sqlite.*` y `Adapters.Api.*`;
   - dependencias nuevas en líneas con coma inicial: `scotty`, `sqlite-simple`, `direct-sqlite`, `crypton`, `memory`, `base16-bytestring`, `warp`, `wai`, `http-types`, `stm`, `time`, `directory` y `filepath`.

   También añadí, al final del archivo, el ejecutable `horario-servidor` (con `-threaded`, como pediste) y la suite `pruebas-m3`. No reordené ni quité nada. Todas las dependencias están en `lts-24.40`, así que `stack.yaml` no cambia.

## Por qué (referencia a la sección de docs/DISENO_v3.md)

"Arquitectura": un solo ejecutable Haskell con los puertos `Repositorio` y `Solver`. El reporte M2-B pide que M3 implemente el repositorio SQLite y enlace el ejecutable con `-threaded`.

## Propuesta concreta (campos, firmas, ejemplo JSON)

- `Adapters.Sqlite.Repositorio.repositorioSqlite :: BaseDatos -> Repositorio IO` implementa el puerto sin cambiarlo. Las operaciones que el puerto declara atómicas usan una transacción cada una.
- `actualizarHorario` compara el `DatosHorario` esperado con el guardado (orden incluido) y devuelve `CambioConcurrente` si difieren.
- `aprobarHorarioDocente` devuelve `CambioConcurrente` si la propuesta ya no está pendiente o sus franjas cambiaron.
- `cerrarSesion` devuelve `RegistroNoEncontrado` si la sesión no pertenece al período.
- **Prueba de paridad:** `crearHorarioVacio` más `editarHorario` dan la misma `evaluacion`, los mismos motivos y las mismas asignaciones con SQLite que con `repositorioEnMemoria`.
- **Pendiente de M2:** cuando M1 entregue el comando de `swipl`, el servidor lo toma de `HORARIO_SWIPL`, `HORARIO_MOTOR_ARGS` y `HORARIO_MOTOR_DIR`. Esas variables alimentan tu `ConfiguracionProlog`.

## Impacto en otras capas

Ninguno. Ningún tipo, puerto ni firma de M2 cambió.
