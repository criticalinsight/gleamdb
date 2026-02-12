import gleam/erlang/process.{type Pid, type Subject}

@external(erlang, "gleamdb_process_ffi", "subject_to_pid")
pub fn subject_to_pid(subject: Subject(a)) -> Pid

@external(erlang, "gleamdb_process_ffi", "pid_to_subject")
pub fn pid_to_subject(pid: Pid) -> Subject(a)

@external(erlang, "gleamdb_process_ffi", "self")
pub fn self() -> Pid
