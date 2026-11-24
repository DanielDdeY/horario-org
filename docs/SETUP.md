# Puesta en marcha local

Dueño: M3. Otros miembros piden cambios a este archivo por solicitud.

El proyecto no usa Docker. SQLite es un archivo y no necesita servidor.

## 1. Herramientas

| Herramienta | Versión | Para qué |
| --- | --- | --- |
| GHCup con GHC y Stack | GHC 9.10.3, Stack 3.x | Backend Haskell (snapshot `lts-24.40`, ver `stack.yaml`) |
| SWI-Prolog | 9.x | Motor de M1 (`swipl`) |
| Node.js | 20 o superior | Frontend y mock de la API |
| make | cualquiera | Atajos del `Makefile` (opcional) |

En Windows el diseño recomienda WSL2. Si trabajas en Windows nativo, ejecuta los comandos de las secciones 3 a 5 a mano en PowerShell, porque `make` no viene instalado.

`stack.yaml` usa `system-ghc: true`: Stack toma el GHC 9.10.3 que esté en el `PATH`. Con GHCup en Windows, normalmente es `C:\ghcup\bin` o la carpeta que elegiste al instalar.

## 2. Compilar y probar el backend

Desde la raíz del repositorio:

```bash
stack build
stack test
```

En Windows con un MSYS2 propio, si Stack intenta instalar el suyo, añade `--skip-msys --no-install-msys`:

```powershell
stack --skip-msys --no-install-msys build
stack --skip-msys --no-install-msys test
```

`stack test` ejecuta la suite `pruebas-m3`, que no necesita `swipl` porque usa los dobles de M2. Cubre el repositorio SQLite, la API y el contrato `openapi.yaml`.

## 3. Variables de entorno del servidor

Todas son opcionales salvo las del coordinador inicial, que se necesitan la primera vez. **No guardes contraseñas en el repositorio.**

| Variable | Por defecto | Uso |
| --- | --- | --- |
| `HORARIO_PUERTO` | `8080` | Puerto HTTP |
| `HORARIO_BD` | `horario.db` | Archivo SQLite, relativo a `backend/` |
| `HORARIO_MIGRACIONES` | `migrations` | Carpeta de migraciones, relativa a `backend/` |
| `HORARIO_COORDINADOR_USUARIO`, `HORARIO_COORDINADOR_CONTRASENA` | sin valor | Crean el primer coordinador si la base no tiene ninguno |
| `HORARIO_TOKEN_HORAS` | `8` | Vigencia de los tokens |
| `HORARIO_BCRYPT_COSTO` | `10` | Costo de bcrypt |
| `HORARIO_MAX_TRABAJOS` | `2` | Trabajos de generación concurrentes |
| `HORARIO_SWIPL` | `swipl` | Ejecutable de SWI-Prolog |
| `HORARIO_MOTOR_ARGS` | vacío | Para el motor de M1, usar `-q -s motor/main.pl` |
| `HORARIO_MOTOR_DIR` | directorio actual | Para esos argumentos, usar la ruta absoluta a la raíz de `horario-org` |
| `HORARIO_MAX_TIMEOUT_SEG` | `300` | Tope de `timeoutSeg` que se envía al motor |
| `HORARIO_MARGEN_TIMEOUT_MS` | `2000` | Margen antes de matar `swipl` |

Desde la raíz del repositorio, puedes probar el motor en PowerShell con el
ejemplo del contrato. El proceso lee un JSON por stdin y devuelve otro por stdout.

```powershell
Get-Content -Raw contracts/ejemplos/m2_versiones_entrada.json | swipl -q -s motor/main.pl
```

## 4. Levantar la API

```bash
export HORARIO_COORDINADOR_USUARIO=coordinador
export HORARIO_COORDINADOR_CONTRASENA='elige-una-clave'
make backend          # o: stack build && cd backend && stack exec horario-servidor
```

En PowerShell:

```powershell
$env:HORARIO_COORDINADOR_USUARIO = 'coordinador'
$env:HORARIO_COORDINADOR_CONTRASENA = 'elige-una-clave'
stack --skip-msys --no-install-msys build
cd backend; stack --skip-msys --no-install-msys exec horario-servidor
```

Al arrancar, el servidor:

1. aplica las migraciones pendientes;
2. crea el coordinador inicial si hace falta;
3. marca como error los trabajos interrumpidos y vuelve a encolar los pendientes;
4. escucha en `http://localhost:8080`.

Prueba rápida:

```bash
curl -s -X POST localhost:8080/auth/login -H 'Content-Type: application/json' \
  -d '{"usuario":"coordinador","contrasena":"elige-una-clave"}'
```

Las demás rutas requieren `Authorization: Bearer <token>`. El contrato completo está en `contracts/openapi.yaml`.

## 5. Mock de la API sin backend

```bash
npx prism mock contracts/openapi.yaml     # o: make mock  (puerto 4010)
```

Responde con los ejemplos del contrato. Así M4 y M5 trabajan sin el backend real.

## 6. Todo junto

```bash
make dev
```

Compila el backend, levanta la API y, si existe `frontend/package.json`, el servidor de Vite. El motor Prolog no es un servicio: la API ejecuta `swipl` en cada trabajo de generación.

## 7. Frontend contra la API real

La API no envía cabeceras CORS. En desarrollo, Vite debe reenviar las rutas de la API a `http://localhost:8080` con un proxy. Ese ajuste corresponde a M5 en `frontend/vite.config.*`.
