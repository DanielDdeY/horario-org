:- use_module(library(http/json)).
:- use_module(library(process)).
:- use_module(library(plunit)).

:- begin_tests(motor).

ejemplo(m2_versiones).
ejemplo(m1_fijas).
ejemplo(m1_previas).
ejemplo(m1_pendientes).

test(ejemplos, [forall(ejemplo(Nombre))]) :-
    format(atom(Entrada), 'contracts/ejemplos/~w_entrada.json', [Nombre]),
    format(atom(Esperada), 'contracts/ejemplos/~w_salida.json', [Nombre]),
    leer_json(Entrada, Solicitud),
    leer_json(Esperada, Esperado),
    ejecutar(Entrada, Respuesta),
    assertion(Respuesta.version == 1),
    assertion(Respuesta.estado == Esperado.estado),
    assertion(integer(Respuesta.tiempoMs)),
    assertion(Respuesta.tiempoMs >= 0),
    maplist(campos_solucion, Esperado.versiones, ResultadosEsperados),
    maplist(campos_solucion, Respuesta.versiones, Resultados),
    assertion(Resultados =@= ResultadosEsperados),
    validar(Solicitud, Respuesta.versiones).

test(cruces_independientes) :-
    Base = _{profesorId:1, aulaId:1, dia:1, inicioMin:480},
    Otra = _{profesorId:2, aulaId:2, dia:1, inicioMin:480},
    Sesion = _{seccionId:1, grupos:[7], duracionMin:60},
    Distinta = Sesion.put(_{seccionId:2, grupos:[8]}),
    assertion(compatibles(Base-Sesion, Otra-Distinta)),
    assertion(\+ compatibles(Base-Sesion, Otra.put(profesorId, 1)-Distinta)),
    assertion(\+ compatibles(Base-Sesion, Otra.put(aulaId, 1)-Distinta)),
    assertion(\+ compatibles(Base-Sesion, Otra-Distinta.put(grupos, [7]))),
    assertion(\+ compatibles(Base-Sesion, Otra.put(inicioMin, 540)-Sesion)),
    assertion(compatibles(Base-Sesion, Base.put(inicioMin, 540)-Distinta)).

test(cruces_del_motor, [forall(member(Regla, [h01,h02,h05,h09]))]) :-
    leer_json('contracts/ejemplos/m2_versiones_entrada.json', Base),
    Base.sesiones = [Sesion],
    Base.aulas = [Aula],
    Base.disponibilidades = [Franja],
    Primero = _{sesionId:5001, profesorId:1, aulaId:301, dia:1, inicioMin:480, obligatoria:true},
    Segundo = Primero.put(_{sesionId:5002, profesorId:2, aulaId:302}),
    Sesion2 = Sesion.put(_{id:5002, seccionId:901, grupos:[8]}),
    caso_cruce(Regla, Segundo, Sesion2, Fija, Modificada),
    Entrada = Base.put(_{sesiones:[Sesion,Modificada], fijas:[Primero,Fija],
        aulas:[Aula,Aula.put(id, 302)],
        profesores:[_{id:1,cursosAptos:[10]},_{id:2,cursosAptos:[10]}],
        disponibilidades:[Franja,Franja.put(profesorId, 2)]}),
    ejecutar_solicitud(Entrada, Respuesta),
    assertion(Respuesta.estado == "error"),
    assertion(string(Respuesta.mensaje)),
    assertion(integer(Respuesta.tiempoMs)).

test(filtros_del_motor, [forall(member(Regla, [h03,h04,h06,h07,h08]))]) :-
    leer_json('contracts/ejemplos/m2_versiones_entrada.json', Base),
    entrada_sin_candidatos(Regla, Base, Entrada),
    ejecutar_solicitud(Entrada, Respuesta),
    assertion(Respuesta.estado == "optimo"),
    Respuesta.versiones = [Solucion],
    assertion(Solucion.asignaciones == []),
    assertion(Solucion.sinAsignar == [5001]).

test(huecos_y_traslados_consecutivos) :-
    leer_json('contracts/ejemplos/m2_versiones_entrada.json', Base),
    Base.sesiones = [Sesion],
    Base.aulas = [Aula],
    Base.disponibilidades = [Franja],
    Config = Base.config.put(_{finDiaMin:720, toleranciaHuecoMin:10}),
    Fija = _{sesionId:5001, profesorId:1, aulaId:301, dia:1, inicioMin:480, obligatoria:true},
    Entrada = Base.put(_{
        config:Config, disponibilidades:[Franja.put(finMin, 720)],
        aulas:[Aula,Aula.put(_{id:302, edificio:2, piso:4})],
        sesiones:[Sesion,Sesion.put(_{id:5002, seccionId:901}),
                         Sesion.put(_{id:5003, seccionId:902})],
        fijas:[Fija,Fija.put(_{sesionId:5002, aulaId:302, inicioMin:540}),
                    Fija.put(_{sesionId:5003, inicioMin:660})]}),
    ejecutar_solicitud(Entrada, Respuesta),
    validar(Entrada, Respuesta.versiones),
    Respuesta.versiones = [Solucion],
    assertion(Solucion.costo =:= 62).

entrada_sin_candidatos(h03, Base, Entrada) :-
    Base.disponibilidades = [Franja],
    Entrada = Base.put(disponibilidades, [Franja.put(cursoId, 20)]).
entrada_sin_candidatos(h04, Base, Entrada) :-
    Base.aulas = [Aula],
    Entrada = Base.put(aulas, [Aula.put(capacidad, 30)]).
entrada_sin_candidatos(h06, Base, Entrada) :-
    Base.profesores = [Profesor],
    Entrada = Base.put(profesores, [Profesor.put(cursosAptos, [])]).
entrada_sin_candidatos(h07, Base, Entrada) :-
    Base.aulas = [Aula],
    Entrada = Base.put(aulas, [Aula.put(tipo, 2)]).
entrada_sin_candidatos(h08, Base, Entrada) :-
    Config = Base.config.put(recesos, [_{inicioMin:480, finMin:600}]),
    Entrada = Base.put(config, Config).

ejecutar_solicitud(Entrada, Respuesta) :-
    tmp_file_stream(text, Ruta, Flujo),
    setup_call_cleanup(
        true,
        ( setup_call_cleanup(true, json_write_dict(Flujo, Entrada), close(Flujo)),
          ejecutar(Ruta, Respuesta)
        ),
        delete_file(Ruta)).

caso_cruce(h01, F, S, R, S) :- R = F.put(profesorId, 1).
caso_cruce(h02, F, S, R, S) :- R = F.put(aulaId, 301).
caso_cruce(h05, F, S, F, R) :- R = S.put(grupos, [7]).
caso_cruce(h09, F, S, R, T) :- R = F.put(inicioMin, 540), T = S.put(seccionId, 900).

leer_json(Ruta, JSON) :-
    setup_call_cleanup(open(Ruta, read, Flujo, [encoding(utf8)]),
                       json_read_dict(Flujo, JSON), close(Flujo)).

ejecutar(Entrada, Respuesta) :-
    current_prolog_flag(executable, Ejecutable),
    setup_call_cleanup(open(Entrada, read, Fuente, [type(binary)]),
        ( process_create(Ejecutable, ['-q', '-s', 'prolog_engine/main.pl'],
                         [stdin(stream(Fuente)), stdout(pipe(Salida)), process(Pid)]),
          setup_call_cleanup(true,
              ( json_read_dict(Salida, Respuesta),
                read_string(Salida, _, Resto),
                normalize_space(string(""), Resto)
              ), close(Salida)),
          process_wait(Pid, exit(0))
        ),
        close(Fuente)).

campos_solucion(Version, Costo-Asignaciones-Pendientes) :-
    Costo = Version.costo,
    assertion(integer(Costo)),
    assertion(Costo >= 0),
    Asignaciones = Version.asignaciones,
    Pendientes = Version.sinAsignar.

% Verificador independiente de las reglas y de la partición del lote.
validar(Solicitud, Versiones) :-
    Versiones = [Primera|_],
    length(Versiones, Total),
    Total =< Solicitud.maxVersiones,
    length(Primera.asignaciones, Cantidad),
    maplist(validar_version(Solicitud, Cantidad), Versiones),
    maplist(campos_solucion, Versiones, Resultados),
    keysort(Resultados, Resultados),
    findall(A, (member(V, Versiones), A = V.asignaciones), Firmas),
    sort(Firmas, FirmasUnicas),
    same_length(Firmas, FirmasUnicas).

validar_version(Solicitud, Cantidad, Version) :-
    length(Version.asignaciones, Cantidad),
    findall(Id, (member(S, Solicitud.sesiones), Id = S.id), Esperados),
    findall(Id, (member(A, Version.asignaciones), Id = A.sesionId), Ubicados),
    append(Ubicados, Version.sinAsignar, Todos),
    msort(Esperados, Canonicos),
    msort(Todos, Canonicos),
    maplist(clase_valida(Solicitud), Version.asignaciones, Clases),
    forall(select(A, Clases, Otras), forall(member(B, Otras), compatibles(A, B))),
    forall(member(Fija, Solicitud.fijas), verificar_fija(Fija, Version.asignaciones)).

clase_valida(Solicitud, A, A-S) :-
    once((member(S, Solicitud.sesiones), S.id =:= A.sesionId)),
    once((member(P, Solicitud.profesores), P.id =:= A.profesorId)),
    once((member(R, Solicitud.aulas), R.id =:= A.aulaId)),
    memberchk(S.cursoId, P.cursosAptos),
    R.capacidad >= S.matriculados,
    R.tipo =:= S.tipoAula,
    C = Solicitud.config,
    I = A.inicioMin,
    F is I + S.duracionMin,
    memberchk(A.dia, C.dias),
    I >= C.inicioDiaMin,
    F =< C.finDiaMin,
    0 is (I - C.inicioDiaMin) mod C.turnoMin,
    0 is S.duracionMin mod C.turnoMin,
    forall(member(Receso, C.recesos), (F =< Receso.inicioMin ; I >= Receso.finMin)),
    once((member(Franja, Solicitud.disponibilidades),
          Franja.profesorId =:= A.profesorId, Franja.cursoId =:= S.cursoId,
          Franja.dia =:= A.dia, Franja.inicioMin =< I, Franja.finMin >= F)).

compatibles(A-S, B-T) :-
    ( A.dia =\= B.dia -> true
    ; S.seccionId =\= T.seccionId,
      ( A.inicioMin + S.duracionMin =< B.inicioMin -> true
      ; B.inicioMin + T.duracionMin =< A.inicioMin -> true
      ; A.profesorId =\= B.profesorId, A.aulaId =\= B.aulaId,
        \+ (member(G, S.grupos), memberchk(G, T.grupos))
      )
    ).

verificar_fija(Fija, Asignaciones) :-
    ( member(A, Asignaciones), A.sesionId =:= Fija.sesionId ->
        forall((member(Campo, [profesorId,aulaId,dia,inicioMin]), get_dict(Campo, Fija, V)),
               get_dict(Campo, A, V))
    ; Fija.obligatoria == false
    ).

:- end_tests(motor).
