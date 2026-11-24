# Solicitud de M5 a M3: corregir el comando del mock Prism

- Fecha y hora (UTC-5): 2026-11-24 14:03
- Bloqueante: no
- Afecta a: `docs/SETUP.md`, sección 5

## Qué necesito

Actualizar el comando de inicio del mock Prism en SETUP para que indique el ejecutable npm correcto.

## Por qué (referencia a la sección de docs/DISENO_v3.md)

La sección de entorno sin Docker del diseño y `docs/SETUP.md`, sección 5, requieren un mock de API para el trabajo paralelo de M4 y M5.

## Propuesta concreta (campos, firmas, ejemplo JSON)

En este entorno, `npx prism mock contracts/openapi.yaml` termina con `npm error could not determine executable to run`. En cambio, `npx @stoplight/prism-cli mock contracts/openapi.yaml` instala Prism CLI y escucha correctamente en `http://127.0.0.1:4010`. Propongo documentar este último comando y actualizar el atajo `make mock` si corresponde.

## Impacto en otras capas

No cambia el contrato ni el puerto. M4 y M5 podrán seguir usando el mock en el puerto 4010.
