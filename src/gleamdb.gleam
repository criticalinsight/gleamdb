import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/erlang/process.{type Subject}
import gleamdb/fact.{type AttributeConfig, type Fact}
import gleamdb/engine
import gleamdb/shared/types.{type BodyClause, type DbState, type QueryResult}
import gleamdb/transactor.{SetReactive}
pub type Db = transactor.Db
import gleamdb/reactive
import gleamdb/storage/mnesia
import gleamdb/storage.{type StorageAdapter}
import gleamdb/global

pub fn new() -> Db {
  new_with_adapter(None)
}

pub fn new_with_adapter(adapter: Option(StorageAdapter)) -> Db {
  let store = case adapter {
    Some(s) -> s
    None -> mnesia.adapter()
  }
  let assert Ok(db) = transactor.start_link(store)
  let assert Ok(react) = reactive.start_link()
  process.send(db, SetReactive(react))
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

pub fn transact_with_timeout(
  db: Db,
  facts: List(Fact),
  timeout: Int,
) -> Result(DbState, String) {
  transactor.transact_with_timeout(db, facts, timeout)
}

pub fn set_schema(
  db: Db,
  attr: String,
  config: AttributeConfig,
) -> Result(Nil, String) {
  transactor.set_schema(db, attr, config)
}

pub fn retract(db: Db, facts: List(Fact)) -> Result(DbState, String) {
  transactor.retract(db, facts)
}

pub fn register_function(
  db: Db,
  name: String,
  func: fact.DbFunction(DbState),
) -> Nil {
  process.send(db, transactor.RegisterFunction(name, func, process.new_subject()))
}

pub fn register_composite(db: Db, attrs: List(String)) -> Nil {
  process.send(db, transactor.RegisterComposite(attrs, process.new_subject()))
}

pub fn query(db: Db, clauses: List(BodyClause)) -> QueryResult {
  let state = transactor.get_state(db)
  engine.run(state, clauses, [], None)
}

pub fn query_with_rules(
  db: Db,
  clauses: List(BodyClause),
  rules: List(engine.Rule),
) -> QueryResult {
  let state = transactor.get_state(db)
  engine.run(state, clauses, rules, None)
}

pub fn as_of(db: Db, tx: Int, clauses: List(BodyClause)) -> QueryResult {
  let state = transactor.get_state(db)
  engine.run(state, clauses, [], Some(tx))
}

pub fn pull(db: Db, eid: fact.Eid, pattern: engine.PullPattern) -> engine.PullResult {
  let state = transactor.get_state(db)
  let assert fact.EntityId(id) = eid
  engine.pull(state, fact.EntityId(id), pattern)
}

pub fn subscribe(db: Db, query: List(BodyClause), subscriber: Subject(QueryResult)) -> Nil {
  let state = transactor.get_state(db)
  
  // Extract attributes from query to optimize notifications
  let attrs = list.filter_map(query, fn(q) {
    case q {
      types.Positive(clause) | types.Negative(clause) -> {
        let #(_, a, _) = clause
        Ok(a)
      }
      _ -> Error(Nil)
    }
  })
  
  process.send(state.reactive_actor, coerce(reactive.Subscribe(query, attrs, subscriber)))
}

pub fn p(clause: types.Clause) -> BodyClause {
  types.Positive(clause)
}

@external(erlang, "gleam_erl_ffi", "coerce")
fn coerce(a: a) -> b
