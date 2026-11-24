:- use_module(library(http/json)).
:- initialization(main, main).

main :-
    findall(Sesion, sesion(Sesion), Sesiones),
    findall(_{id:Id, cursosAptos:Cursos},
            (between(1, 150, Id), findall(Curso, curso_profesor(Id, Curso), Cursos)),
            Profesores),
    findall(Franja, franja(Franja), Franjas),
    findall(Aula, aula(Aula), Aulas),
    Config = _{dias:[1,2,3,4,5], inicioDiaMin:480, finDiaMin:1230, turnoMin:50,
               recesos:[_{inicioMin:830, finMin:880}], timeoutSeg:10,
               toleranciaHuecoMin:0, consecutivoMaxMin:30,
               pesos:_{hueco:1, piso:2, edificio:10, estabilidad:5}},
    json_write_dict(current_output, _{version:1, config:Config, profesores:Profesores,
        disponibilidades:Franjas, aulas:Aulas, sesiones:Sesiones,
        fijas:[], previas:[], maxVersiones:2}, [width(0)]),
    nl.

sesion(_{id:Id, cursoId:Curso, seccionId:Seccion, duracionMin:Duracion,
         matriculados:Matriculados, tipoAula:Tipo, grupos:[Grupo]}) :-
    between(1, 400, Seccion),
    between(1, 2, Reunion),
    Id is (Seccion - 1) * 2 + Reunion,
    Curso is (Seccion - 1) mod 100 + 1,
    Grupo is (Seccion - 1) div 5 + 1,
    Matriculados is 18 + Seccion mod 31,
    Duracion is 50 + 50 * (Id mod 2),
    Tipo is 1 + Curso mod 4.

curso_profesor(Profesor, Curso) :-
    between(0, 2, Indice),
    Curso is ((Profesor - 1) * 7 + Indice * 13) mod 100 + 1.

franja(_{profesorId:Profesor, cursoId:Curso, dia:Dia, inicioMin:Inicio, finMin:Fin}) :-
    between(1, 150, Profesor),
    curso_profesor(Profesor, Curso),
    between(0, 2, Desplazamiento),
    Dia is (Profesor + Desplazamiento) mod 5 + 1,
    Inicio is 480 + 50 * (Profesor mod 7),
    Fin is min(1230, Inicio + 350).

aula(_{id:Id, capacidad:Capacidad, edificio:Edificio, piso:Piso, tipo:Tipo}) :-
    between(1, 60, Id),
    Capacidad is 24 + 8 * (Id mod 6),
    Edificio is (Id - 1) div 15 + 1,
    Piso is Id mod 4 + 1,
    Tipo is Id mod 4 + 1.
