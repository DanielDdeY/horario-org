:- use_module(library(http/json)).
:- use_module(library(pairs)).
:- use_module(library(time)).
:- initialization(main, main).

main :-
    set_stream(user_input, encoding(utf8)),
    set_stream(user_output, encoding(utf8)),
    get_time(Inicio),
    catch(
        ( leer_y_resolver(Respuesta) -> true
        ; Respuesta = _{estado:error, mensaje:"Solicitud inválida o sin solución compatible con las fijas obligatorias."}
        ),
        Error,
        ( message_to_string(Error, Mensaje),
          Respuesta = _{estado:error, mensaje:Mensaje}
        )
    ),
    get_time(Fin),
    Ms is max(0, round((Fin - Inicio) * 1000)),
    Salida = Respuesta.put(_{version:1, tiempoMs:Ms}),
    json_write_dict(user_output, Salida, [width(0)]),
    nl.

leer_y_resolver(Respuesta) :-
    json_read_dict(user_input, Entrada),
    Entrada.version == 1,
    Limite = Entrada.maxVersiones,
    integer(Limite),
    between(1, 4, Limite),
    Config = Entrada.config,
    integer(Config.timeoutSeg),
    Config.timeoutSeg > 0,
    nb_setval(mejores, []),
    nb_setval(cota_sesiones, -1),
    catch(
        ( call_with_time_limit(Config.timeoutSeg, resolver(Entrada, Limite)),
          Completo = true
        ),
        time_limit_exceeded,
        Completo = false
    ),
    nb_getval(mejores, Mejores),
    respuesta(Completo, Mejores, Respuesta).

resolver(Entrada, Limite) :-
    Config = Entrada.config,
    memberchk(Config.turnoMin, [45,50,60,90]),
    between(0, 1439, Config.inicioDiaMin),
    between(1, 1440, Config.finDiaMin),
    Config.inicioDiaMin < Config.finDiaMin,
    Config.dias = [_|_],
    maplist(between(1, 7), Config.dias),
    maplist(intervalo_valido, Config.recesos),
    maplist(no_negativo, [Config.pesos.hueco, Config.pesos.piso,
        Config.pesos.edificio, Config.pesos.estabilidad,
        Config.toleranciaHuecoMin, Config.consecutivoMaxMin]),
    maplist(is_list, [Entrada.sesiones, Entrada.aulas, Entrada.profesores,
        Entrada.disponibilidades, Entrada.fijas, Entrada.previas]),
    maplist(id_unico, [Entrada.sesiones, Entrada.aulas, Entrada.profesores]),
    maplist(sesion_valida, Entrada.sesiones),
    maplist(aula_valida, Entrada.aulas),
    maplist(profesor_valido, Entrada.profesores),
    maplist(franja_valida, Entrada.disponibilidades),
    maplist(fija_valida(Entrada.sesiones), Entrada.fijas),
    maplist(ubicacion_valida, Entrada.previas),
    maplist(dominio(Entrada), Entrada.sesiones, Dominios),
    keysort(Dominios, Ordenados),
    pairs_values(Ordenados, Tareas),
    include(con_candidatos, Tareas, Ubicables),
    length(Ubicables, Maximo),
    nb_setval(cota_sesiones, Maximo),
    ( buscar(Tareas, Config, Limite, Maximo, 0, 0, [], []), fail
    ; true
    ).

no_negativo(Valor) :- integer(Valor), Valor >= 0.
positivo(Valor) :- integer(Valor), Valor > 0.

id_unico(Filas) :-
    maplist(id_fila, Filas, Ids),
    sort(Ids, Unicos),
    same_length(Ids, Unicos).

id_fila(Fila, Id) :- Id = Fila.id, positivo(Id).

sesion_valida(Sesion) :-
    positivo(Sesion.cursoId),
    positivo(Sesion.seccionId),
    between(1, 1440, Sesion.duracionMin),
    no_negativo(Sesion.matriculados),
    positivo(Sesion.tipoAula),
    maplist(positivo, Sesion.grupos).

aula_valida(Aula) :-
    no_negativo(Aula.capacidad),
    positivo(Aula.edificio),
    integer(Aula.piso),
    positivo(Aula.tipo).

profesor_valido(Profesor) :- maplist(positivo, Profesor.cursosAptos).

intervalo_valido(Fila) :-
    between(0, 1439, Fila.inicioMin),
    between(1, 1440, Fila.finMin),
    Fila.inicioMin < Fila.finMin.

franja_valida(Franja) :-
    positivo(Franja.profesorId),
    positivo(Franja.cursoId),
    between(1, 7, Franja.dia),
    intervalo_valido(Franja).

fija_valida(Sesiones, Fija) :-
    memberchk(Fija.obligatoria, [true,false]),
    once((member(Sesion, Sesiones), Sesion.id == Fija.sesionId)),
    ( Fija.obligatoria == true -> ubicacion_valida(Fija)
    ; forall((campo_ubicacion(Campo), get_dict(Campo, Fija, Valor)),
             valor_ubicacion(Campo, Valor))
    ).

ubicacion_valida(Ubicacion) :-
    positivo(Ubicacion.sesionId),
    forall(campo_ubicacion(Campo),
           (get_dict(Campo, Ubicacion, Valor), valor_ubicacion(Campo, Valor))).

campo_ubicacion(profesorId).
campo_ubicacion(aulaId).
campo_ubicacion(dia).
campo_ubicacion(inicioMin).

valor_ubicacion(profesorId, Valor) :- positivo(Valor).
valor_ubicacion(aulaId, Valor) :- positivo(Valor).
valor_ubicacion(dia, Valor) :- between(1, 7, Valor).
valor_ubicacion(inicioMin, Valor) :- between(0, 1439, Valor).

dominio(Entrada, Sesion, Prioridad-tarea(Id, Obligatoria, Candidatos)) :-
    Id = Sesion.id,
    include(de_sesion(Id), Entrada.fijas, Fijas),
    ( member(Fija, Fijas), Fija.obligatoria == true -> Obligatoria = true
    ; Obligatoria = false
    ),
    findall(Costo-Clase,
            ( candidato(Entrada, Sesion, Fijas, Clase),
              estabilidad(Entrada, Obligatoria, Clase, Costo)
            ),
            Opciones),
    sort(Opciones, Candidatos),
    length(Candidatos, Cantidad),
    ( Obligatoria == true -> Prioridad = 0-Cantidad
    ; Prioridad = 1-Cantidad
    ).

de_sesion(Id, Fila) :- Fila.sesionId == Id.

con_candidatos(tarea(_, _, [_|_])).

candidato(Entrada, Sesion, Fijas, Clase) :-
    Config = Entrada.config,
    Duracion = Sesion.duracionMin,
    positivo(Duracion),
    0 is Duracion mod Config.turnoMin,
    member(Profesor, Entrada.profesores),
    memberchk(Sesion.cursoId, Profesor.cursosAptos),
    member(Franja, Entrada.disponibilidades),
    Franja.profesorId == Profesor.id,
    Franja.cursoId == Sesion.cursoId,
    Dia = Franja.dia,
    memberchk(Dia, Config.dias),
    Jornada = Config.inicioDiaMin,
    Turno = Config.turnoMin,
    PrimerTurno is max(0, (Franja.inicioMin - Jornada + Turno - 1) div Turno),
    UltimoTurno is (min(Config.finDiaMin, Franja.finMin) - Duracion - Jornada) div Turno,
    between(PrimerTurno, UltimoTurno, Paso),
    Inicio is Jornada + Paso * Turno,
    Fin is Inicio + Duracion,
    \+ (member(Receso, Config.recesos), solapan(Inicio, Fin, Receso.inicioMin, Receso.finMin)),
    member(Aula, Entrada.aulas),
    Aula.capacidad >= Sesion.matriculados,
    Aula.tipo == Sesion.tipoAula,
    Ubicacion = ubicacion(Sesion.id, Profesor.id, Aula.id, Dia, Inicio),
    maplist(respeta(Ubicacion), Fijas),
    Clase = clase(Ubicacion, Fin, Sesion.seccionId, Sesion.grupos, Aula.edificio, Aula.piso).

respeta(ubicacion(_, Profesor, Aula, Dia, Inicio), Fija) :-
    maplist(coincide_si_presente(Fija),
            [profesorId-Profesor, aulaId-Aula, dia-Dia, inicioMin-Inicio]).

coincide_si_presente(Fija, Campo-Valor) :-
    ( get_dict(Campo, Fija, Fijado) -> Fijado == Valor ; true ).

estabilidad(Entrada, false, clase(Ubicacion, _, _, _, _, _), Costo) :-
    Ubicacion = ubicacion(Id, _, _, _, _),
    once((member(Previa, Entrada.previas), de_sesion(Id, Previa))),
    \+ respeta(Ubicacion, Previa),
    !,
    Costo = Entrada.config.pesos.estabilidad.
estabilidad(_, _, _, 0).

solapan(Inicio1, Fin1, Inicio2, Fin2) :- Inicio1 < Fin2, Inicio2 < Fin1.

conflicto(clase(ubicacion(_, P1, A1, Dia, I1), F1, S1, G1, _, _),
          clase(ubicacion(_, P2, A2, Dia, I2), F2, S2, G2, _, _)) :-
    ( S1 == S2
    ; solapan(I1, F1, I2, F2),
      ( P1 == P2 ; A1 == A2 ; member(Grupo, G1), memberchk(Grupo, G2) )
    ).

% La cantidad ubicable y el costo acumulado de S07 acotan cada rama.
% S01 y S02 se calculan al final porque una clase puede cambiar los pares consecutivos.
buscar([], Config, Limite, Cota, Cantidad, Estabilidad, Clases, Pendientes) :-
    puede_mejorar(Cota, Estabilidad, Limite),
    costo_agenda(Config, Clases, Agenda),
    Costo is Estabilidad + Agenda,
    NegCantidad is -Cantidad,
    guardar(Limite, (NegCantidad-Costo)-solucion(Clases, Pendientes)).
buscar([tarea(Id, Obligatoria, Opciones)|Resto], Config, Limite, Cota,
       Cantidad, Estabilidad, Clases, Pendientes) :-
    puede_mejorar(Cota, Estabilidad, Limite),
    ( member(Costo-Clase, Opciones),
      \+ (member(Otra, Clases), conflicto(Clase, Otra)),
      Asignadas is Cantidad + 1,
      Acumulado is Estabilidad + Costo,
      buscar(Resto, Config, Limite, Cota, Asignadas, Acumulado, [Clase|Clases], Pendientes)
    ; Obligatoria == false,
      ( Opciones == [] -> CotaPendiente = Cota ; CotaPendiente is Cota - 1 ),
      buscar(Resto, Config, Limite, CotaPendiente, Cantidad, Estabilidad, Clases, [Id|Pendientes])
    ).

puede_mejorar(Cota, Estabilidad, Limite) :-
    nb_getval(mejores, Mejores),
    ( Mejores = [(NegMejor-_)-_|_] ->
        ( Cota > -NegMejor
        ; Cota =:= -NegMejor,
          ( length(Mejores, Total), Total < Limite
          ; last(Mejores, (_-PeorCosto)-_), Estabilidad < PeorCosto
          )
        )
    ; true
    ).

guardar(Limite, (Cantidad-Costo)-Solucion) :-
    nb_getval(mejores, Mejores),
    append(Mejores, [(Cantidad-Costo)-Solucion], Resultados),
    keysort(Resultados, Ordenados),
    Ordenados = [(MejorCantidad-_)-_|_],
    include(misma_cantidad(MejorCantidad), Ordenados, Comparables),
    ( length(Prefijo, Limite), append(Prefijo, _, Comparables) ->
        nb_setval(mejores, Prefijo)
    ; nb_setval(mejores, Comparables)
    ).

misma_cantidad(Cantidad, (Cantidad-_)-_).

costo_agenda(Config, Clases, Costo) :-
    maplist(clave_agenda, Clases, Agenda),
    keysort(Agenda, Orden),
    pairs_values(Orden, Ordenadas),
    costo_pares(Ordenadas, Config, 0, Costo).

clave_agenda(Clase, (Profesor-Dia-Inicio)-Clase) :-
    Clase = clase(ubicacion(_, Profesor, _, Dia, Inicio), _, _, _, _, _).

costo_pares([A,B|Resto], Config, Acumulado, Costo) :-
    !,
    costo_par(A, B, Config, Par),
    Suma is Acumulado + Par,
    costo_pares([B|Resto], Config, Suma, Costo).
costo_pares(_, _, Costo, Costo).

costo_par(clase(ubicacion(_, Profesor, _, Dia, _), Fin, _, _, E1, P1),
          clase(ubicacion(_, Profesor, _, Dia, Inicio), _, _, _, E2, P2), Config, Costo) :-
    !,
    Hueco is Inicio - Fin,
    Pesos = Config.pesos,
    S01 is Pesos.hueco * max(0, Hueco - Config.toleranciaHuecoMin),
    ( Hueco =< Config.consecutivoMaxMin ->
        ( E1 == E2 -> Edificio = 0 ; Edificio = Pesos.edificio ),
        S02 is Pesos.piso * abs(P1 - P2) + Edificio
    ; S02 = 0
    ),
    Costo is S01 + S02.
costo_par(_, _, _, 0).

respuesta(false, [], _{estado:timeout}) :- !.
respuesta(Completo, Mejores, _{estado:Estado, versiones:Versiones}) :-
    Mejores = [(Cantidad-MejorCosto)-_|_],
    nb_getval(cota_sesiones, Maximo),
    ( Completo == true -> Estado = optimo, CostoProbado = MejorCosto
    ; Estado = factible,
      ( Cantidad =:= -Maximo, MejorCosto =:= 0 -> CostoProbado = 0 ; CostoProbado = -1 )
    ),
    maplist(version_json(CostoProbado), Mejores, Versiones).

version_json(CostoProbado, (_-Costo)-solucion(Clases, Pendientes), Version) :-
    maplist(asignacion_json, Clases, Pares),
    keysort(Pares, Ordenados),
    pairs_values(Ordenados, Asignaciones),
    msort(Pendientes, SinAsignar),
    ( Costo =:= CostoProbado -> Estado = optimo ; Estado = factible ),
    Version = _{estado:Estado, costo:Costo, asignaciones:Asignaciones, sinAsignar:SinAsignar}.

asignacion_json(clase(ubicacion(Id, Profesor, Aula, Dia, Inicio), _, _, _, _, _),
                Id-_{sesionId:Id, profesorId:Profesor, aulaId:Aula, dia:Dia, inicioMin:Inicio}).
