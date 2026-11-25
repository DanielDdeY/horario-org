"""Emite una instancia sintética reproducible para medir el motor por stdin."""

import argparse
import json


def instancia(sesiones_por_seccion, tiempo):
    profesores = [{"id": p, "cursosAptos": [(p - 1) % 50 + 1]}
                  for p in range(1, 151)]
    franjas = [
        {"profesorId": p["id"], "cursoId": p["cursosAptos"][0], "dia": dia,
         "inicioMin": 480 + 50 * ((p["id"] + dia) % 5),
         "finMin": 980 + 50 * ((p["id"] + dia) % 5)}
        for p in profesores for dia in range(1, 6)
    ]
    return {
        "version": 1,
        "maxVersiones": 4,
        "config": {
            "dias": [1, 2, 3, 4, 5], "inicioDiaMin": 480, "finDiaMin": 1230,
            "turnoMin": 50, "recesos": [{"inicioMin": 830, "finMin": 880}],
            "pesos": {"hueco": 1, "piso": 2, "edificio": 10, "estabilidad": 5},
            "toleranciaHuecoMin": 0, "consecutivoMaxMin": 30, "timeoutSeg": tiempo,
        },
        "profesores": profesores,
        "disponibilidades": franjas,
        "aulas": [
            {"id": a, "capacidad": 25 + (a % 6) * 10,
             "edificio": 1 + a % 4, "piso": a % 5, "tipo": 1 + int(a % 5 == 0)}
            for a in range(1, 61)
        ],
        "sesiones": [
            {"id": (s - 1) * sesiones_por_seccion + n, "cursoId": (s - 1) % 50 + 1,
             "seccionId": s, "duracionMin": 50 if (s + n) % 3 == 0 else 100,
             "matriculados": 20 + s % 46, "tipoAula": 1 + int((s + n) % 5 == 0),
             "grupos": [1 + (s - 1) % 50]}
            for s in range(1, 401) for n in range(1, sesiones_por_seccion + 1)
        ],
        "fijas": [],
        "previas": [],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sesiones-por-seccion", type=int, choices=(1, 2), default=1)
    parser.add_argument("--timeout", type=int, default=5)
    args = parser.parse_args()
    print(json.dumps(instancia(args.sesiones_por_seccion, args.timeout)))
