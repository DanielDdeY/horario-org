:- begin_tests(motor).
:- use_module('../motor').
:- use_module(library(http/json)).
:- use_module(library(lists)).
:- use_module(library(pairs)).
:- use_module(library(process)).

ejemplo(Prefijo, Entrada, Dorado) :-
    atom_concat(Prefijo, '_entrada.json', NombreEntrada),
    atom_concat(Prefijo, '_salida.json', NombreSalida),
    directory_file_path('contracts/ejemplos', NombreEntrada, Entrada),
    directory_file_path('contracts/ejemplos', NombreSalida, Salida),
    leer_json(Salida, Dorado).

leer_json(Ruta, JSON) :-
    setup_call_cleanup(open(Ruta, read, Stream, [encoding(utf8)]),
                       json_read_dict(Stream, JSON), close(Stream)).

ejecutar(Texto, Salida) :-
    current_prolog_flag(executable, SWI),
    process_create(SWI, ['-q','-f',none,'-s','prolog_engine/main.pl'],
                   [stdin(pipe(In)), stdout(pipe(Out)), stderr(pipe(Err)), process(Pid)]),
    format(In, '~s', [Texto]),
    close(In),
    read_string(Out, _, Json),
    close(Out),
    read_string(Err, _, Stderr),
    close(Err),
    process_wait(Pid, Estado),
    assertion(Estado == exit(0)),
    assertion(Stderr == ""),
    atom_json_dict(Json, Salida, []).

test(dorados, [forall((expand_file_name('contracts/ejemplos/*_entrada.json', Rutas),
                       member(Ruta, Rutas)))]) :-
    file_base_name(Ruta, Nombre),
    atom_concat(Prefijo, '_entrada.json', Nombre),
    ejemplo(Prefijo, Ruta, Esperado),
    leer_json(Ruta, Entrada),
    read_file_to_string(Ruta, Texto, []),
    ejecutar(Texto, Salida),
    assertion(integer(Salida.tiempoMs)),
    assertion(Salida.tiempoMs >= 0),
    once(verificar_lote(Entrada, Salida)),
    put_dict(tiempoMs, Salida, 0, Normalizada),
    put_dict(tiempoMs, Esperado, 0, Esperada),
    assertion(Normalizada =@= Esperada).

test(json_roto) :-
    ejecutar("{", Salida),
    assertion(Salida.estado == "error"),
    assertion(string(Salida.mensaje)),
    assertion(Salida.tiempoMs >= 0).

test(json_adicional) :-
    ejecutar("{} {}", Salida),
    assertion(Salida.estado == "error").

test(obligatoria_incompatible, [throws(error(domain_error(asignaciones_obligatorias_compatibles,_),_))]) :-
    ejemplo(m1_restricciones, Ruta, _),
    leer_json(Ruta, E),
    E.fijas = [Fija|Resto],
    put_dict(inicioMin, Fija, 540, Incompatible),
    resolver(E.put(fijas,[Incompatible|Resto]), _).

test(seccion_y_solapes) :-
    ejemplo(m2_versiones, Ruta, _),
    leer_json(Ruta, E),
    E.sesiones = [A],
    B = A.put(id,5002),
    C = A.put(_{id:5003,seccionId:901}),
    Entrada = E.put(sesiones,[A,B,C]),
    resolver(Entrada, Salida),
    assertion(Salida.estado == optimo),
    once(verificar_lote(Entrada, Salida)),
    forall(member(V, Salida.versiones), assertion(length(V.sinAsignar, 1))).

test(conflictos_independientes, [forall(member(Regla,[h01,h02,h05,compatible]))]) :-
    ejemplo(m2_versiones, Ruta, _),
    leer_json(Ruta, E),
    E.sesiones = [S],
    E.aulas = [R],
    S2 = S.put(_{id:5002,seccionId:901,cursoId:11}),
    R2 = R.put(id,302),
    (Regla == h01 -> Docente = 1 ; Docente = 2),
    (Regla == h02 -> Aula = 301 ; Aula = 302),
    (Regla == h05 -> Grupos = [7] ; Grupos = [8]),
    Entrada = E.put(_{
        sesiones:[S,S2.put(grupos,Grupos)],
        aulas:[R,R2],
        profesores:[_{id:1,cursosAptos:[10,11]}, _{id:2,cursosAptos:[11]}],
        disponibilidades:[
            _{profesorId:1,cursoId:10,dia:1,inicioMin:480,finMin:540},
            _{profesorId:Docente,cursoId:11,dia:1,inicioMin:480,finMin:540}],
        fijas:[
            _{sesionId:5001,profesorId:1,aulaId:301,dia:1,inicioMin:480,obligatoria:true},
            _{sesionId:5002,aulaId:Aula,obligatoria:false}]
    }),
    resolver(Entrada, Salida),
    once(verificar_lote(Entrada, Salida)),
    Salida.versiones = [V],
    (Regla == compatible -> Esperadas = [] ; Esperadas = [5002]),
    assertion(V.sinAsignar == Esperadas).

test(mejora_la_primera_solucion) :-
    ejemplo(m2_versiones, Ruta, _),
    leer_json(Ruta, E),
    E.sesiones = [S],
    E.disponibilidades = [F],
    Entrada = E.put(_{
        config:E.config.put(finDiaMin,660), maxVersiones:2,
        sesiones:[S,S.put(_{id:5002,seccionId:901})],
        disponibilidades:[F.put(finMin,660)],
        fijas:[_{sesionId:5001,profesorId:1,aulaId:301,dia:1,inicioMin:600,obligatoria:true}]
    }),
    resolver(Entrada, Salida),
    assertion(Salida.estado == optimo),
    once(verificar_lote(Entrada, Salida)),
    Salida.versiones = [Mejor,Alterna],
    assertion(Mejor.costo == 0),
    assertion(Alterna.costo == 60).

test(conserva_previa_factible) :-
    ejemplo(m2_versiones, Ruta, _),
    leer_json(Ruta, E),
    Previa = _{sesionId:5001,profesorId:1,aulaId:301,dia:1,inicioMin:540},
    Entrada = E.put(previas,[Previa]),
    resolver(Entrada, Salida),
    once(verificar_lote(Entrada, Salida)),
    Salida.versiones = [Mejor,Alterna],
    assertion(Mejor.asignaciones =@= [Previa]),
    assertion(Mejor.costo == 0),
    assertion(Alterna.costo == 5).

test(prueba_de_cota_con_tiempo_agotado) :-
    motor:respuesta(interrumpido, [mejor(1,10,_{costo:0}),mejor(1,15,_{costo:5})],
                    10, Respuesta),
    assertion(Respuesta.estado == factible),
    Respuesta.versiones = [Optima, Factible],
    assertion(Optima.estado == optimo),
    assertion(\+ get_dict(estado, Factible, _)).

test(tiempo_agotado_sin_incumbente) :-
    motor:respuesta(interrumpido, [], pendiente, Respuesta),
    assertion(Respuesta.estado == timeout).

verificar_lote(E, Salida) :-
    Salida.versiones = [Primera|_],
    length(Salida.versiones, N), between(1, E.maxVersiones, N),
    findall(Costo, (member(V, Salida.versiones), Costo = V.costo), Costos),
    msort(Costos, Costos),
    findall(Ubicaciones, (member(V, Salida.versiones), Ubicaciones = V.asignaciones), Lotes),
    sort(Lotes, Distintos), length(Distintos, N),
    length(Primera.sinAsignar, Faltantes),
    forall(member(V, Salida.versiones),
           (length(V.sinAsignar, Faltantes), verificar(E, V))).

% Verificador independiente en minutos, sin dominios ni índice de ocupación.
verificar(E, V) :-
    findall(Id, (member(S, E.sesiones), Id = S.id), Ids),
    msort(Ids, Esperados),
    findall(Id, (member(A, V.asignaciones), Id = A.sesionId), Ubicados),
    append(Ubicados, V.sinAsignar, Todos),
    msort(Todos, Esperados),
    maplist(verificar_fija(V.asignaciones), E.fijas),
    maplist(verificar_clase(E), V.asignaciones, Clases),
    forall(select(A, Clases, Otras), forall(member(B, Otras), validar_par(A,B))),
    puntaje_independiente(E, Clases, Costo),
    Costo =:= V.costo.

verificar_fija(Ubicaciones, F) :-
    ( member(A, Ubicaciones), A.sesionId =:= F.sesionId ->
        forall((member(K, [profesorId,aulaId,dia,inicioMin]), get_dict(K,F,X)),
               get_dict(K,A,X))
    ; F.obligatoria == false ).

verificar_clase(E, A, clase(A,S,R,Fin)) :-
    member(S, E.sesiones), A.sesionId =:= S.id,
    member(P, E.profesores), A.profesorId =:= P.id,
    memberchk(S.cursoId, P.cursosAptos),
    member(R, E.aulas), A.aulaId =:= R.id,
    R.capacidad >= S.matriculados, R.tipo =:= S.tipoAula,
    C = E.config,
    Fin is A.inicioMin+S.duracionMin,
    memberchk(A.dia, C.dias), A.inicioMin >= C.inicioDiaMin, Fin =< C.finDiaMin,
    0 is (A.inicioMin-C.inicioDiaMin) mod C.turnoMin,
    S.duracionMin > 0, 0 is S.duracionMin mod C.turnoMin,
    forall(member(Receso,C.recesos), (Fin =< Receso.inicioMin ; A.inicioMin >= Receso.finMin)),
    member(F,E.disponibilidades),
    F.profesorId =:= P.id, F.cursoId =:= S.cursoId, F.dia =:= A.dia,
    F.inicioMin =< A.inicioMin, Fin =< F.finMin,
    !.

validar_par(clase(A,S,_,Fin), clase(B,T,_,OtroFin)) :-
    ( A.dia =:= B.dia ->
        S.seccionId =\= T.seccionId,
        ( A.inicioMin < OtroFin, B.inicioMin < Fin ->
            A.profesorId =\= B.profesorId, A.aulaId =\= B.aulaId,
            \+ (member(G,S.grupos), memberchk(G,T.grupos))
        ; true )
    ; true ).

puntaje_independiente(E, Clases, Costo) :-
    C = E.config,
    W = C.pesos,
    findall(Puntos,
            ( member(clase(A,_,R,Fin), Clases), member(clase(B,_,T,_), Clases),
              misma_agenda(A,B), B.inicioMin >= Fin,
              \+ (member(clase(M,_,_,_), Clases), misma_agenda(A,M),
                  M.inicioMin >= Fin, M.inicioMin < B.inicioMin),
              H is B.inicioMin-Fin,
              ( H =< C.consecutivoMaxMin ->
                  (R.edificio =:= T.edificio -> Edi = 0 ; Edi = W.edificio),
                  Viaje is W.piso*abs(R.piso-T.piso)+Edi
              ; Viaje = 0 ),
              Puntos is Viaje+W.hueco*max(0,H-C.toleranciaHuecoMin)
            ), Costos),
    findall(1,
            ( member(clase(A,_,_,_), Clases), member(P, E.previas),
              A.sesionId =:= P.sesionId,
              \+ (member(F,E.fijas), F.obligatoria == true, F.sesionId =:= A.sesionId),
              once((member(K,[profesorId,aulaId,dia,inicioMin]),
                    get_dict(K,P,Antes), get_dict(K,A,Ahora), Antes =\= Ahora))
            ), Cambios),
    sum_list(Costos, Pares), length(Cambios, N),
    Costo is Pares+N*W.estabilidad.

misma_agenda(A,B) :- A.profesorId =:= B.profesorId, A.dia =:= B.dia.

:- end_tests(motor).
