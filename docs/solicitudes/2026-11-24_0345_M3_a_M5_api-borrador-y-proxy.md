# Solicitud de M3 a M5: contrato de la API, mock y proxy de Vite

- Fecha y hora (UTC-5): 2026-11-24 03:45
- Bloqueante: no
- Afecta a: `contracts/openapi.yaml`, `frontend/vite.config.*`, `frontend/src/api/`, CI

## Qué necesito

1. Que generes los tipos de TypeScript desde el borrador de `contracts/openapi.yaml` (OpenAPI 3.0.3) y me avises por solicitud si algo no se genera bien o falta.
2. Un **proxy en Vite** hacia `http://localhost:8080` para las rutas de la API, porque la API no envía cabeceras CORS:
   `/auth`, `/profesores`, `/propuestas`, `/categorias`, `/aulas`, `/cursos`, `/sesiones`, `/configuracion`, `/horarios`, `/trabajos` y `/avisos`.
3. En CI, un job de Haskell que ejecute `stack test` (o `stack --skip-msys --no-install-msys test` en Windows). La suite `pruebas-m3` no necesita `swipl` porque usa los dobles de M2.

## Por qué (referencia a la sección de docs/DISENO_v3.md)

"API REST", "Entorno sin Docker" y "Plan de trabajo": M5 genera los tipos, mantiene el cliente de API y el CI.

## Propuesta concreta (campos, firmas, ejemplo JSON)

- **Mock:** `npx prism mock contracts/openapi.yaml`, en el puerto 4010. También está como `make mock`, documentado en `docs/SETUP.md`.
- **Autenticación:**
  - `POST /auth/login` con `{ usuario, contrasena }` devuelve `{ version, token, rol, profesorId, expiraEn }`;
  - el token va en `Authorization: Bearer <token>`;
  - los roles son `profesor` y `coordinador`.
- **Pantallas del profesor:**
  - `GET /profesores/{id}?periodoId=` devuelve `disponibilidad` (`null` si no la registró), `cursosAptos` y `propuestas`;
  - `PUT /profesores/{id}` con `{ periodoId, disponibilidad: [{ dia, inicioMin, finMin }] }` actualiza su disponibilidad. La respuesta trae las franjas ya fusionadas y `avisosGenerados`;
  - `POST /profesores/{id}/propuestas` envía una propuesta;
  - `GET /cursos` devuelve, para el profesor, solo los cursos de su categoría;
  - `GET /avisos` devuelve sus avisos.
- **H10 retirado:** no existen `limites` (`maxMinDia`, `maxMinSemana`, `descansoMinMin`), según `docs/ANTES_DE_DESARROLLAR.md`. La pantalla "mis límites" de tu instrucción original ya no aplica.
- **Estados de un trabajo** (supuesto de M3): `pendiente`, `ejecutando`, `terminado` y `error`.

## Impacto en otras capas

Ninguno en el backend. Para las pruebas de integración (`tests/`), el servidor se levanta con `cd backend && stack exec horario-servidor` y las variables descritas en `docs/SETUP.md`.
