import gleam/option.{None, Some}
import gleam/result
import gleam/erlang/process
import gleamdb/fact
import gleamdb/transactor
import gleamdb/global
import gleamdb/engine.{type BodyClause, Positive}
import gleamdb/storage/mnesia
import gleamdb/storage

pub type Db = transactor.Db
pub type DbState = transactor.DbState
pub type Fact = fact.Fact
pub type Value = fact.Value

pub fn new() -> Db {
  new_with_adapter(None)
}

pub fn new_with_adapter(adapter: option.Option(storage.StorageAdapter)) -> Db {
  let store = case adapter {
    Some(s) -> s
    None -> mnesia.adapter()
  }
  let assert Ok(db) = transactor.start_link(store)
  db
}

pub fn register(db: Db, name: String) -> Result(Nil, Nil) {
  process.subject_owner(db)
  |> result.try(fn(pid) { global.register(name, pid) })
}

pub fn connect(name: String) -> Result(Db, Nil) {
  global.whereis(name)
  |> result.map(fn(pid) { cast_pid_to_subject(pid) })
}

@external(erlang, "gleam_erlang_ffi", "from_pid")
fn cast_pid_to_subject(pid: process.Pid) -> process.Subject(a)

pub fn transact(db: Db, facts: List(Fact)) -> Result(DbState, String) {
  transactor.transact(db, facts)
}

pub fn set_schema(
  db: Db,
  attr: String,
  config: fact.AttributeConfig,
) -> Result(Nil, String) {
  transactor.set_schema(db, attr, config)
}

pub fn retract(db: Db, facts: List(Fact)) -> Result(DbState, String) {
  transactor.retract(db, facts)
}

pub fn register_function(
  db: Db,
  name: String,
  func: fact.DbFunction(transactor.DbState),
) -> Nil {
  process.call(db, 5000, transactor.RegisterFunction(name, func, _))
}

pub fn register_composite(db: Db, attrs: List(String)) -> Nil {
  process.call(db, 5000, transactor.RegisterComposite(attrs, _))
}

pub fn query(db: Db, clauses: List(BodyClause)) -> engine.QueryResult {
  let state = transactor.get_state(db)
  engine.run(state, clauses, [], None)
}

pub fn query_with_rules(
  db: Db,
  clauses: List(BodyClause),
  rules: List(engine.Rule),
) -> engine.QueryResult {
  let state = transactor.get_state(db)
  engine.run(state, clauses, rules, None)
}

pub fn as_of(db: Db, tx: Int, clauses: List(BodyClause)) -> engine.QueryResult {
  let state = transactor.get_state(db)
  engine.run(state, clauses, [], Some(tx))
}

pub fn pull(
  db: Db,
  eid: Int,
  pattern: engine.PullPattern,
) -> engine.PullResult {
  let state = transactor.get_state(db)
  engine.pull(state, eid, pattern)
}

// Convenience helpers
pub fn p(clause: engine.Clause) -> BodyClause {
  Positive(clause)
}
