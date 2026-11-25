:- module(motor, [resolver/2]).
:- use_module(library(assoc)).
:- use_module(library(clpfd)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).
:- use_module(library(time)).

resolver(Entrada, Resultado) :-
    Entrada.version == 1,
    Config = Entrada.config,
    Limite = Config.timeoutSeg,
    Max = Entrada.maxVersiones,
    must_be(positive_integer, Limite),
    between(1, 4, Max),
    setup_call_cleanup(
        nb_setval(motor_mejores, mejores([], pendiente)),
        ( catch((call_with_time_limit(Limite, buscar(Entrada)) -> Fin = completo
                ; Fin = incompatible),
                time_limit_exceeded, Fin = interrumpido),
          nb_getval(motor_mejores, mejores(Mejores, Cota)),
          respuesta(Fin, Mejores, Cota, Resultado)
        ),
        nb_delete(motor_mejores)).

buscar(Entrada) :-
    Config = Entrada.config,
    integer(Config.turnoMin),
    Config.turnoMin > 0,
    indice(id, Entrada.aulas, Aulas),
    indice(sesionId, Entrada.previas, Previas),
    indice(sesionId, Entrada.fijas, Fijas),
    indice(id, Entrada.profesores, Profesores),
    findall(Curso-Franja,
            (member(Franja, Entrada.disponibilidades), Curso = Franja.cursoId),
            FranjasPorCurso),
    keysort(FranjasPorCurso, FranjasOrdenadas),
    group_pairs_by_key(FranjasOrdenadas, GruposFranjas),
    list_to_assoc(GruposFranjas, Franjas),
    Contexto = datos(Config, Profesores, Franjas, Entrada.aulas, Fijas, Previas),
    maplist(preparar(Contexto), Entrada.sesiones, ConClave),
    keysort(ConClave, Ordenadas),
    pairs_values(Ordenadas, Filas),
    include(forzada_pendiente, Filas, Forzadas),
    length(Forzadas, MinPendientes),
    length(Filas, Total),
    multiplicador(Config, Entrada.aulas, Total, M),
    Cota is M*MinPendientes,
    nb_setval(motor_mejores, mejores([], Cota)),
    Busqueda = busqueda(Config, Aulas, Entrada.maxVersiones, M, MinPendientes),
    empty_assoc(Ocupacion),
    ( explorar(Filas, Busqueda, Ocupacion, [], [], 0)
    -> true
    ;  nb_getval(motor_mejores, mejores([_|_], _))
    ).

indice(Campo, Dicts, Indice) :-
    maplist(con_clave(Campo), Dicts, Pares),
    keysort(Pares, Ordenados),
    list_to_assoc(Ordenados, Indice).

con_clave(Campo, Dict, Clave-Dict) :- get_dict(Campo, Dict, Clave).

preparar(datos(C, Profesores, Franjas, Aulas, Fijas, Previas), S, Clave-Fila) :-
    Id = S.id,
    (get_assoc(Id, Fijas, Fija) -> true ; Fija = _{obligatoria:false}),
    Obligatoria = Fija.obligatoria,
    memberchk(Obligatoria, [true,false]),
    ( Obligatoria == true ->
        maplist(campo_entero(Fija), [profesorId,aulaId,dia,inicioMin])
    ; true ),
    ( Obligatoria == false, get_assoc(Id, Previas, Previa) ->
        TurnoPrevio is (Previa.inicioMin-C.inicioDiaMin) div C.turnoMin,
        Preferida = previa([Previa.dia,TurnoPrevio,Previa.profesorId],
                           Previa.aulaId, Previa.inicioMin)
    ; Preferida = ninguna ),
    findall(IdAula,
            ( member(Aula, Aulas), Aula.tipo =:= S.tipoAula,
              Aula.capacidad >= S.matriculados,
              IdAula = Aula.id, permite(Fija, aulaId, IdAula)
            ), Salas0),
    sort(Salas0, Salas),
    Curso = S.cursoId,
    (get_assoc(Curso, Franjas, DelCurso) -> true ; DelCurso = []),
    Duracion is S.duracionMin div C.turnoMin,
    findall([Dia,Turno,P],
            ( Salas \= [], S.duracionMin > 0, 0 is S.duracionMin mod C.turnoMin,
              member(F, DelCurso), P = F.profesorId, Dia = F.dia,
              get_assoc(P, Profesores, Profesor), memberchk(Curso, Profesor.cursosAptos),
              memberchk(Dia, C.dias), permite(Fija, profesorId, P),
              permite(Fija, dia, Dia),
              primer_y_ultimo(C, S, F, Primero, Ultimo),
              between(Primero, Ultimo, Turno),
              Inicio is C.inicioDiaMin + Turno*C.turnoMin,
              permite(Fija, inicioMin, Inicio),
              Fin is Inicio+S.duracionMin,
              \+ (member(R, C.recesos), Inicio < R.finMin, R.inicioMin < Fin)
            ), Horas0),
    sort(Horas0, Horas),
    ( Horas == [] ->
        Obligatoria == false,
        Fila = pendiente(Id),
        Clave = clave(1,0,Id)
    ; length(Horas, NH), length(Salas, NS), Opciones is NH*NS,
      (Obligatoria == true -> Prioridad = 0 ; Prioridad = 1),
      Clave = clave(Prioridad,Opciones,Id),
      Fila = fila(S, Obligatoria, Horas, Salas, Duracion, Preferida)
    ).

campo_entero(Dict, Campo) :-
    get_dict(Campo, Dict, Valor),
    must_be(integer, Valor).

permite(Fija, Campo, Valor) :-
    (get_dict(Campo, Fija, Fijo) -> Fijo =:= Valor ; true).

primer_y_ultimo(C, S, F, Primero, Ultimo) :-
    Base = C.inicioDiaMin,
    Paso = C.turnoMin,
    Primero is (max(Base,F.inicioMin)-Base+Paso-1) div Paso,
    Ultimo is (min(C.finDiaMin,F.finMin)-Base-S.duracionMin) div Paso.

forzada_pendiente(pendiente(_)).

% Every nonzero soft term comes from a session or a consecutive pair.
multiplicador(C, Aulas, Total, M) :-
    findall(Piso, (member(A, Aulas), Piso = A.piso), Pisos),
    ( Pisos == [] -> Distancia = 0
    ; min_list(Pisos, Min), max_list(Pisos, Max), Distancia is Max-Min ),
    P = C.pesos,
    maplist(peso_valido(P), [hueco,piso,edificio,estabilidad]),
    must_be(nonneg, C.toleranciaHuecoMin),
    C.finDiaMin > C.inicioDiaMin,
    M is 1 + Total*((C.finDiaMin-C.inicioDiaMin)*P.hueco
                     + Distancia*P.piso + P.edificio + P.estabilidad).

peso_valido(P, Campo) :-
    get_dict(Campo, P, Peso),
    must_be(nonneg, Peso).

% The incumbent list survives backtracking and the time-limit exception.
explorar([], B, _, Clases, Pendientes, N) :-
    registrar(B, Clases, Pendientes, N),
    cota_alcanzada(B).
explorar([pendiente(Id)|Filas], B, O, Clases, Pendientes, N) :-
    Siguiente is N+1,
    explorar(Filas, B, O, Clases, [Id|Pendientes], Siguiente).
explorar([fila(S, Obligatoria, Horas, Salas, Dur, Previa)|Filas],
         B, O, Clases, Pendientes, N) :-
    B = busqueda(C, _, Max, M, MinPendientes),
    ( puede_mejorar(Max, M, max(N,MinPendientes)),
      ubicar(Horas, Salas, Previa, C, S, Dur, O, NuevaO, Clase),
      explorar(Filas, B, NuevaO, [Clase|Clases], Pendientes, N)
    ; Obligatoria == false,
      Siguiente is N+1,
      puede_mejorar(Max, M, max(Siguiente,MinPendientes)),
      explorar(Filas, B, O, Clases, [S.id|Pendientes], Siguiente)
    ).

puede_mejorar(Max, M, Pendientes) :-
    nb_getval(motor_mejores, mejores(Mejores, _)),
    ( Mejores = [mejor(N,_,_)|_], Pendientes > N -> fail
    ; length(Mejores, Max), last(Mejores, mejor(_,Objetivo,_)) ->
        Pendientes*M < Objetivo
    ; true ).

ubicar(Horas, Salas, Previa, C, S, Dur, O, NuevaO, Clase) :-
    ( Previa = previa([D,T,P],R,I), memberchk([D,T,P], Horas), memberchk(R, Salas),
      I =:= C.inicioDiaMin+T*C.turnoMin,
      ocupar(O, S, Dur, D, T, P, ConDocente),
      ocupar_aula(ConDocente, Dur, D, T, R, NuevaO)
    ; tuples_in([[D,T,P]], Horas),
      labeling([], [D,T,P]),
      ocupar(O, S, Dur, D, T, P, ConDocente),
      list_to_fdset(Salas, DominioAula),
      R in_set DominioAula,
      labeling([], [R]),
      ocupar_aula(ConDocente, Dur, D, T, R, NuevaO),
      I is C.inicioDiaMin+T*C.turnoMin,
      Previa \== previa([D,T,P],R,I)
    ),
    Fin is I+S.duracionMin,
    ( Previa = previa(_,_,_), Previa \== previa([D,T,P],R,I) -> Cambio = 1
    ; Cambio = 0 ),
    Clase = clase(S.id,P,R,D,I,Fin,Cambio).

ocupar(O, S, Dur, D, T, P, NuevaO) :-
    reservar(seccion(S.seccionId,D), O, ConSeccion),
    Ultimo is T+Dur-1,
    findall(Clave,
            ( between(T, Ultimo, Turno),
              (Clave = profesor(P,D,Turno)
              ;member(G, S.grupos), Clave = grupo(G,D,Turno))
            ), Claves0),
    sort(Claves0, Claves),
    foldl(reservar, Claves, ConSeccion, NuevaO).

ocupar_aula(O, Dur, D, T, R, NuevaO) :-
    Ultimo is T+Dur-1,
    findall(aula(R,D,Turno), between(T, Ultimo, Turno), Claves),
    foldl(reservar, Claves, O, NuevaO).

reservar(Clave, O, NuevaO) :-
    \+ get_assoc(Clave, O, _),
    put_assoc(Clave, O, true, NuevaO).

registrar(busqueda(C,Aulas,Max,M,_), Clases, Pendientes, N) :-
    nb_getval(motor_mejores, mejores(Mejores, Cota)),
    ( Mejores = [mejor(MejorN,_,_)|_] -> N =< MejorN ; true ),
    puntaje(C, Aulas, Clases, Costo),
    Objetivo is M*N+Costo,
    ( Mejores = [mejor(MejorN,_,_)|_], N =:= MejorN -> Anteriores = Mejores
    ; Anteriores = [] ),
    maplist(asignacion, Clases, Asignaciones0),
    keysort(Asignaciones0, PorId),
    pairs_values(PorId, Asignaciones),
    msort(Pendientes, SinAsignar),
    Solucion = _{costo:Costo, asignaciones:Asignaciones, sinAsignar:SinAsignar},
    insertar(mejor(N,Objetivo,Solucion), Anteriores, Ordenadas),
    length(Prefijo, Max),
    (append(Prefijo, _, Ordenadas) -> Seleccion = Prefijo ; Seleccion = Ordenadas),
    nb_setval(motor_mejores, mejores(Seleccion, Cota)).

insertar(Mejor, [], [Mejor]).
insertar(mejor(N,O,S), [mejor(N,Otro,A)|Resto], Ordenadas) :-
    ( O < Otro -> Ordenadas = [mejor(N,O,S),mejor(N,Otro,A)|Resto]
    ; Ordenadas = [mejor(N,Otro,A)|Cola],
      insertar(mejor(N,O,S), Resto, Cola)
    ).

cota_alcanzada(busqueda(_,_,Max,M,MinN)) :-
    nb_getval(motor_mejores, mejores(Mejores, _)),
    length(Mejores, Max),
    last(Mejores, mejor(_,Objetivo,_)),
    Objetivo =:= M*MinN.

asignacion(clase(Id,P,R,D,I,_,_), Id-Asignacion) :-
    Asignacion = _{sesionId:Id, profesorId:P, aulaId:R, dia:D, inicioMin:I}.

puntaje(C, Aulas, Clases, Costo) :-
    maplist(clave_clase, Clases, Pares),
    keysort(Pares, Ordenadas),
    pairs_values(Ordenadas, Agenda),
    costo_agenda(Agenda, C, Aulas, Costo).

clave_clase(Clase, clave(P,D,I)-Clase) :- Clase = clase(_,P,_,D,I,_,_).

costo_agenda([], _, _, 0).
costo_agenda([A|Resto], C, Aulas, Total) :-
    A = clase(_,_,_,_,_,_,Cambio),
    ( Resto = [B|_] -> costo_par(A, B, C, Aulas, Par) ; Par = 0 ),
    costo_agenda(Resto, C, Aulas, Cola),
    Total is Cambio*C.pesos.estabilidad + Par + Cola.

costo_par(clase(_,P,A,D,_,Fin,_), clase(_,Q,B,E,Inicio,_,_), C, Aulas, Costo) :-
    ( P =:= Q, D =:= E ->
        Hueco is Inicio-Fin,
        ( Hueco =< C.consecutivoMaxMin ->
            get_assoc(A, Aulas, SalaA), get_assoc(B, Aulas, SalaB),
            (SalaA.edificio =:= SalaB.edificio -> Edificio = 0 ; Edificio = C.pesos.edificio),
            Traslado is C.pesos.piso*abs(SalaA.piso-SalaB.piso)+Edificio
        ; Traslado = 0 ),
        Costo is C.pesos.hueco*max(0,Hueco-C.toleranciaHuecoMin)+Traslado
    ; Costo = 0 ).

respuesta(incompatible, _, _, _) :-
    throw(error(domain_error(asignaciones_obligatorias_compatibles, entrada), _)).
respuesta(interrumpido, [], _, _{estado:timeout}) :- !.
respuesta(Fin, [Primera|Resto], Cota, _{estado:Estado, versiones:Versiones}) :-
    (Fin == completo -> Estado = optimo ; Estado = factible),
    maplist(version(Estado,Cota), [Primera|Resto], Versiones).

version(optimo, _, mejor(_,_,Solucion), Solucion).
version(factible, Cota, mejor(_,Objetivo,Solucion), Version) :-
    ( Objetivo =:= Cota -> put_dict(estado, Solucion, optimo, Version)
    ; Version = Solucion ).
