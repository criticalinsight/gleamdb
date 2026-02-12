-module(gleamdb_ets_ffi).
-export([init_table/2, insert/2, lookup/2, delete/2]).

init_table(Name, Type) ->
    TableName = binary_to_atom(Name, utf8),
    EtsType = case Type of
        set -> set;
        ordered_set -> ordered_set;
        bag -> bag;
        duplicate_bag -> duplicate_bag
    end,
    case ets:whereis(TableName) of
        undefined ->
            ets:new(TableName, [EtsType, public, named_table, {read_concurrency, true}]);
        _ ->
            ok
    end,
    ok.

insert(Table, Object) ->
    TableName = binary_to_atom(Table, utf8),
    ets:insert(TableName, Object),
    ok.

lookup(Table, Key) ->
    TableName = binary_to_atom(Table, utf8),
    ets:lookup(TableName, Key).

delete(Table, Key) ->
    TableName = binary_to_atom(Table, utf8),
    ets:delete(TableName, Key),
    ok.
