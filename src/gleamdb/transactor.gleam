import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/list
import gleam/dict
import gleam/result
import gleam/option.{None, Some}
import gleamdb/fact.{type Datom, type Entity, type Attribute, type Value, Assert, Datom}
import gleamdb/shared/types.{type DbState, DbState, type ReactiveMessage}
import gleamdb/index
import gleamdb/storage

pub type Db = Subject(Message)

pub type Message {
  Transact(facts: List(fact.Fact), reply_to: Subject(Result(DbState, String)))
  Retract(facts: List(fact.Fact), reply_to: Subject(Result(DbState, String)))
  GetState(reply_to: Subject(DbState))
  Subscribe(pid: Subject(List(Datom)), reply_to: Subject(Nil))
  SetSchema(attr: String, config: fact.AttributeConfig, reply_to: Subject(Result(Nil, String)))
  RemoteTransact(datoms: List(Datom), reply_to: Subject(DbState))
  SetReactive(actor: Subject(ReactiveMessage))
  RegisterFunction(name: String, func: fact.DbFunction(DbState), reply_to: Subject(Nil))
  RegisterComposite(attrs: List(String), reply_to: Subject(Nil))
}

pub fn start_with_timeout(adapter: storage.StorageAdapter, _timeout_ms: Int) -> Result(Db, String) {
  let initial_state = DbState(
    adapter: adapter,
    eavt: index.new_index(),
    aevt: index.new_aindex(),
    avet: index.new_avindex(),
    latest_tx: 0,
    subscribers: [],
    schema: dict.new(),
    functions: dict.new(),
    composites: [],
    reactive_actor: coerce(process.new_subject()),
  )
  
  actor.new(initial_state)
  |> actor.on_message(handle_message)
  |> actor.start()
  |> result.map(fn(started) { started.data })
  |> result.map_error(fn(_) { "Failed to start transactor" })
}

pub fn handle_message(state: DbState, message: Message) -> actor.Next(DbState, Message) {
  case message {
    GetState(reply_to) -> {
      process.send(reply_to, state)
      actor.continue(state)
    }
    
    Transact(facts, reply_to) -> {
      let next_tx = state.latest_tx + 1
      let res = list.fold(facts, Ok([]), fn(acc_res, f) {
        case acc_res {
          Error(e) -> Error(e)
          Ok(acc) -> {
            let #(eid, a, v) = f
            case resolve_eid(state, eid) {
              Ok(e) -> Ok([Datom(e, a, v, next_tx, Assert), ..acc])
              Error(err) -> Error(err)
            }
          }
        }
      })

      case res {
        Error(err) -> {
          process.send(reply_to, Error(err))
          actor.continue(state)
        }
        Ok(datoms) -> {
          state.adapter.persist_batch(datoms)
          let new_eavt = list.fold(datoms, state.eavt, index.insert_eavt)
          let new_aevt = list.fold(datoms, state.aevt, index.insert_aevt)
          let new_state = DbState(..state, eavt: new_eavt, aevt: new_aevt, latest_tx: next_tx)
          process.send(reply_to, Ok(new_state))
          actor.continue(new_state)
        }
      }
    }

    SetReactive(react) -> {
      actor.continue(DbState(..state, reactive_actor: react))
    }
    
    RegisterFunction(name, func, reply_to) -> {
      let new_state = DbState(..state, functions: dict.insert(state.functions, name, func))
      process.send(reply_to, Nil)
      actor.continue(new_state)
    }

    RegisterComposite(attrs, reply_to) -> {
      let new_state = DbState(..state, composites: [attrs, ..state.composites])
      process.send(reply_to, Nil)
      actor.continue(new_state)
    }

    SetSchema(attr, config, reply_to) -> {
      let new_state = DbState(..state, schema: dict.insert(state.schema, attr, config))
      process.send(reply_to, Ok(Nil))
      actor.continue(new_state)
    }
    
    _ -> actor.continue(state)
  }
}

fn resolve_eid(state: DbState, eid: fact.Eid) -> Result(Entity, String) {
  case eid {
    fact.EntityId(e) -> Ok(e)
    fact.Lookup(#(a, v)) -> {
       case index.get_entity_by_av(state.avet, a, v) {
         Ok(e) -> Ok(e)
         Error(_) -> Error("Lookup failed")
       }
    }
  }
}

pub fn transact(db: Db, facts: List(fact.Fact)) -> Result(DbState, String) {
  process.call(db, 5000, Transact(facts, _))
}

pub fn transact_with_timeout(db: Db, facts: List(fact.Fact), timeout: Int) -> Result(DbState, String) {
  process.call(db, timeout, Transact(facts, _))
}

pub fn set_schema(db: Db, attr: String, config: fact.AttributeConfig) -> Result(Nil, String) {
  process.call(db, 5000, SetSchema(attr, config, _))
}

pub fn set_schema_with_timeout(db: Db, attr: String, config: fact.AttributeConfig, timeout: Int) -> Result(Nil, String) {
  process.call(db, timeout, SetSchema(attr, config, _))
}

pub fn retract(db: Db, facts: List(fact.Fact)) -> Result(DbState, String) {
  process.call(db, 5000, Retract(facts, _))
}

pub fn get_state(db: Db) -> DbState {
  process.call(db, 5000, GetState(_))
}

@external(erlang, "gleam_erl_ffi", "coerce")
fn coerce(a: a) -> b
