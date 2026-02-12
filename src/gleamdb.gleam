import gleam/option.{type Option, None, Some}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result
import gleam/list
import gleamdb/transactor
import gleamdb/engine
import gleamdb/fact.{type AttributeConfig, type Fact}
import gleamdb/shared/types.{type BodyClause, type DbState, type QueryResult, Positive, Subscribe}
import gleamdb/index
import gleamdb/storage.{type StorageAdapter}
import gleamdb/global
import gleamdb/process_extra

pub type Db = transactor.Db
pub type PullResult = engine.PullResult
pub type PullPattern = engine.PullPattern

pub fn new() -> Db {
  new_with_adapter(None)
}

pub fn new_with_adapter(adapter: Option(StorageAdapter)) -> Db {
  new_with_adapter_and_timeout(adapter, 5000)
}

pub fn new_with_adapter_and_timeout(adapter: Option(StorageAdapter), timeout_ms: Int) -> Db {
  let assert Ok(db) = start_link(adapter, timeout_ms)
  db
}

pub fn start_link(
  adapter: Option(StorageAdapter),
  timeout_ms: Int,
) -> Result(Subject(transactor.Message), actor.StartError) {
  let store = case adapter {
    Some(s) -> s
    None -> storage.ephemeral()
  }
  
  transactor.start_with_timeout(store, timeout_ms)
}

pub fn start_named(
  name: String,
  adapter: Option(StorageAdapter),
) -> Result(Subject(transactor.Message), actor.StartError) {
  let store = case adapter {
    Some(s) -> s
    None -> storage.ephemeral()
  }
  transactor.start_named(name, store)
}

pub fn start_distributed(
  name: String,
  adapter: Option(StorageAdapter),
) -> Result(Subject(transactor.Message), actor.StartError) {
  let store = case adapter {
    Some(s) -> s
    None -> storage.ephemeral()
  }
  transactor.start_distributed(name, store)
}

pub fn connect(name: String) -> Result(Db, String) {
  case global.whereis("gleamdb_" <> name) {
    Ok(pid) -> Ok(process_extra.pid_to_subject(pid))
    Error(_) -> Error("Could not find database named " <> name)
  }
}

pub fn transact(db: Db, facts: List(Fact)) -> Result(DbState, String) {
  transactor.transact(db, facts)
}

pub fn transact_with_timeout(db: Db, facts: List(Fact), timeout_ms: Int) -> Result(DbState, String) {
  transactor.transact_with_timeout(db, facts, timeout_ms)
}

pub fn retract(db: Db, facts: List(Fact)) -> Result(DbState, String) {
  transactor.retract(db, facts)
}

pub fn set_schema(db: Db, attr: String, config: AttributeConfig) -> Result(Nil, String) {
  transactor.set_schema(db, attr, config)
}

pub fn set_schema_with_timeout(db: Db, attr: String, config: AttributeConfig, timeout_ms: Int) -> Result(Nil, String) {
  transactor.set_schema_with_timeout(db, attr, config, timeout_ms)
}

pub fn history(db: Db, eid: fact.Eid) -> List(fact.Datom) {
  let state = transactor.get_state(db)
  let id = case eid {
    fact.Uid(i) -> i
    fact.Lookup(#(a, v)) -> {
      index.get_entity_by_av(state.avet, a, v) |> result.unwrap(fact.EntityId(0))
    }
  }
  engine.entity_history(state, id)
}

pub fn pull(
  db: Db,
  eid: fact.Eid,
  pattern: PullPattern,
) -> engine.PullResult {
  let state = transactor.get_state(db)
  let id = case eid {
    fact.Uid(i) -> i
    fact.Lookup(#(a, v)) -> {
       index.get_entity_by_av(state.avet, a, v) |> result.unwrap(fact.EntityId(0))
    }
  }
  engine.pull(state, fact.Uid(id), pattern)
}

pub fn pull_all() -> PullPattern {
  [engine.Wildcard]
}

pub fn pull_attr(attr: String) -> PullPattern {
  [engine.Attr(attr)]
}

pub fn query(db: Db, q_clauses: List(BodyClause)) -> QueryResult {
  let state = transactor.get_state(db)
  engine.run(state, q_clauses, [], None)
}

pub fn query_with_rules(db: Db, q_clauses: List(BodyClause), rules: List(engine.Rule)) -> QueryResult {
  let state = transactor.get_state(db)
  engine.run(state, q_clauses, rules, None)
}

pub fn as_of(db: Db, tx: Int, q_clauses: List(BodyClause)) -> QueryResult {
  let state = transactor.get_state(db)
  engine.run(state, q_clauses, [], Some(tx))
}

pub fn p(triple: types.Clause) -> BodyClause {
  Positive(triple)
}

pub fn register_function(
  db: Db,
  name: String,
  func: fact.DbFunction(types.DbState),
) -> Nil {
  transactor.register_function(db, name, func)
}

pub fn register_composite(db: Db, attrs: List(String)) -> Nil {
  transactor.register_composite(db, attrs)
}

pub fn subscribe(
  db: Db,
  query: List(BodyClause),
  subscriber: Subject(types.ReactiveDelta),
) -> Nil {
  let state = transactor.get_state(db)
  let results = engine.run(state, query, [], None)
  
  let attrs = list.filter_map(query, fn(c) {
    case c {
      Positive(#(_, a, _)) -> Ok(a)
      types.Negative(#(_, a, _)) -> Ok(a)
      _ -> Error(Nil)
    }
  })

  let msg = Subscribe(query, attrs, subscriber, results)
  process.send(state.reactive_actor, msg)
  process.send(subscriber, types.Initial(results))
  Nil
}
