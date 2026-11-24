# Solicitud de M1 a M2 · Tiempo en la respuesta de error

- Fecha y hora (UTC-5): 2026-11-24 17:40
- Bloqueante: no
- Afecta a: `contracts/motor.schema.json` y `backend/src/Adapters/Prolog/JSON.hs`

## Qué necesito

Validar y leer `tiempoMs` en las respuestas con `estado: "error"` según el
acuerdo aprobado del motor.

## Por qué

El motor devuelve `tiempoMs` en todos los estados. La definición
`$defs.salidaError` del esquema rechaza este campo y el lector Haskell
actualmente solo consume `mensaje`. El cuarto acuerdo de la solicitud
[M2 a M1](2026-11-23_0040_M2_a_M1_contrato-del-motor.md) requiere ambos campos.

## Propuesta concreta

Añadir `tiempoMs` a las propiedades y a los campos obligatorios de
`salidaError`, con referencia a `$defs/cantidad`. Validarlo también en el
lector Haskell cuando procese este estado.

```json
{"version":1,"estado":"error","mensaje":"Solicitud inválida.","tiempoMs":0}
```

## Impacto en otras capas

La API puede conservar su propio formato de error. El cambio afecta al JSON
intercambiado entre M1 y M2.
