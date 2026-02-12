-module(gleamdb_process_ffi).
-export([subject_to_pid/1, pid_to_subject/1, self/0]).

subject_to_pid(Subject) ->
    element(2, Subject).

pid_to_subject(Pid) ->
    {subject, Pid}.

self() ->
    self().
