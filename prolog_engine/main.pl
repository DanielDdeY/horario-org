:- use_module(library(http/json)).
:- use_module(motor).
:- initialization(main, main).

main :-
    set_stream(user_input, encoding(utf8)),
    set_stream(user_output, encoding(utf8)),
    get_time(Inicio),
    catch(
        ( json_read_dict(user_input, Entrada),
          read_string(user_input, _, Resto),
          normalize_space(string(""), Resto),
          resolver(Entrada, Resultado)
        -> true
        ;  throw(error(domain_error(solicitud_motor, entrada), _))
        ),
        Error,
        ( message_to_string(Error, Mensaje),
          Resultado = _{estado:error, mensaje:Mensaje}
        )),
    get_time(Fin),
    Ms is max(0, round((Fin-Inicio)*1000)),
    put_dict(_{version:1, tiempoMs:Ms}, Resultado, Salida),
    json_write_dict(user_output, Salida, [width(0)]),
    nl(user_output),
    flush_output(user_output).
