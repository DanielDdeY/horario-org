# Reporte de cambios: M5 · bootstrap frontend

- Fecha y hora (UTC-5): 2026-11-24 12:51
- Miembro: M5
- Rama y commits: `feat/m5-frontend-profesor` · sin commits
- Estado: Parcial

## Resumen

Se inicializó `frontend/` con React, TypeScript y Vite. Se instaló `openapi-typescript`, se generaron los tipos desde el contrato vigente y se configuró el proxy `/api` hacia el mock en `http://localhost:4010`.
El contrato no contempla H10 ni límites de carga; el alcance de profesor confirmado incluye autenticación, disponibilidad, cursos/propuestas y avisos.

## Archivos

| Ruta | Acción (creado / modificado) | Qué cambió | Por qué |
| --- | --- | --- | --- |
| `frontend/` | creado | Scaffold React + TypeScript + Vite, dependencias y lockfile | Base de la aplicación M5 |
| `frontend/package.json` | creado | Añade `openapi-typescript` y el comando `api:types`; TypeScript queda en 5.9.x por compatibilidad de peer dependency | Generar tipos de manera reproducible |
| `frontend/vite.config.ts` | creado | Reenvía `/api/*` a `http://localhost:4010`, quitando el prefijo `/api` | Consumir el mock sin cambiar las rutas del cliente |
| `frontend/src/api/schema.d.ts` | creado | Tipos OpenAPI generados, sin editar manualmente | Consumir tipos derivados del contrato |
| `docs/cambios/2026-11-24_1251_M5_bootstrap-frontend.md` | creado | Registro de este avance | Requisito de reporte M5 |

## Contratos e interfaces afectados

Ninguno. `contracts/openapi.yaml` solo se consumió para generar tipos.

## Cómo verificarlo

Desde `frontend/`:

- `npm run api:types`: correcto; `openapi-typescript 7.13.0` generó `src/api/schema.d.ts`.
- `npm run build`: correcto; `tsc -b` y `vite build` finalizaron sin errores.
- `git diff --check`: correcto, sin errores de whitespace.

## Supuestos y decisiones tomadas

- El scaffold de Vite instaló TypeScript 7.0.2, incompatible con el peer dependency `typescript@^5.x` de `openapi-typescript@7.13.0`. Se fijó la rama compatible 5.9.x en vez de ignorar el conflicto.
- El proxy usa `/api` como base de las llamadas del frontend y elimina ese prefijo antes de reenviar al mock.
- Se siguió `docs/ANTES_DE_DESARROLLAR.md` y el contrato vigente: H10 está retirado y no existe `limites`.

## Pendientes y bloqueos

- Pendiente implementar cliente tipado, autenticación/estado, router y pantallas del profesor.
- Alcance API/UI confirmado: `POST /auth/login`, `GET/PUT /profesores/{id}`, `POST /profesores/{id}/propuestas`, `GET /cursos` y `GET /avisos`.
- El profesor solo puede cambiar su disponibilidad; los cursos aptos y los avisos se consultan. La aprobación de propuestas pertenece al coordinador.
- La API permite al profesor consultar `GET /horarios` y `GET /horarios/{id}` para horarios publicados, pero las guías revisadas no asignan una pantalla de horario como entregable explícito de M5.
- Pendientes de M5: CI, QuickCheck, pruebas de integración y benchmark.

## Qué deben saber los otros agentes

- M1: nada.
- M2: nada.
- M3: los tipos ya se generan; el proxy apunta al mock `:4010` por la solicitud actual. Cambiar el destino a `:8080` al integrar la API real.
- M4: base Vite lista; no se modificaron sus rutas ni componentes.
- M5: continuar con el cliente, router y pantallas; no implementar límites/H10 según el contrato vigente.

## Archivos leídos como contexto

- `docs/ANTES_DE_DESARROLLAR.md`
- `docs/SETUP.md`
- `contracts/openapi.yaml`
- `docs/cambios/2026-11-23_0013_M2_dominio-y-reglas.md`
- `docs/cambios/2026-11-23_0040_M2_validador-y-casos-de-uso.md`
- `docs/cambios/2026-11-24_0345_M3_api-sqlite-y-trabajos.md`
- `docs/solicitudes/2026-11-23_0040_M2_a_M1_contrato-del-motor.md`
- `docs/solicitudes/2026-11-24_0345_M3_a_M2_integracion-repositorio.md`
- `docs/solicitudes/2026-11-24_0345_M3_a_M4_api-borrador.md`
- `docs/solicitudes/2026-11-24_0345_M3_a_M5_api-borrador-y-proxy.md`
- `C:\Users\milag\Desktop\Descargas\guias-ia\M5_frontend_profesor_qa.md`
- `DISENO_v3.md` (adjunto del coordinador, leído en la conversación)
