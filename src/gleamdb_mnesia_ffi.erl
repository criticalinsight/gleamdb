-module(gleamdb_mnesia_ffi).
-export([init/0, persist/1, persist_batch/1, recover/0]).

init() ->
    mnesia:start(),
    mnesia:create_table(datoms, [
        {record_name, datom},
        {attributes, [entity, attribute, value, tx, operation]}
    ]).

persist(Datom) ->
    mnesia:dirty_write(datoms, Datom),
    nil.

persist_batch(Datoms) ->
    F = fun() ->
        lists:foreach(fun(D) -> mnesia:write(datoms, D, write) end, Datoms)
    end,
    mnesia:transaction(F),
    nil.

recover() ->
    {ok, []}.
