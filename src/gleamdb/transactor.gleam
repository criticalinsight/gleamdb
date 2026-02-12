import gleam/erlang/process
import gleam/otp/actor
import gleam/list
import gleam/dict
import gleam/result
import gleam/option.{type Option, None, Some}
import gleamdb/fact
import gleamdb/shared/types
import gleamdb/index
import gleamdb/storage

pub type Message {
  Transact(List(fact.Fact), process.Subject(Result(types.DbState, String)))
  Retract(List(fact.Fact), process.Subject(Result(types.DbState, String)))
  GetState(process.Subject(types.DbState))
  SetSchema(String, fact.AttributeConfig, process.Subject(Result(Nil, String)))
  RegisterFunction(String, fact.DbFunction(types.DbState), process.Subject(Nil))
  RegisterComposite(List(String), process.Subject(Nil))
  SetReactive(process.Subject(types.ReactiveMessage))
}

pub type Db =
  process.Subject(Message)

pub fn start(
  store: storage.StorageAdapter,
) -> Result(process.Subject(Message), actor.StartError) {
  start_with_timeout(store, 1000)
}

pub fn start_with_timeout(
  store: storage.StorageAdapter,
  _timeout_ms: Int,
) -> Result(process.Subject(Message), actor.StartError) {
  let initial_state =
    types.DbState(
      adapter: store,
      eavt: index.new_index(),
      aevt: index.new_aindex(),
      avet: index.new_avindex(),
      latest_tx: 0,
      subscribers: [],
      schema: dict.new(),
      functions: dict.new(),
      composites: [],
      reactive_actor: process.new_subject(),
    )

  actor.new(initial_state)
  |> actor.on_message(handle_message)
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

fn handle_message(state: types.DbState, msg: Message) -> actor.Next(types.DbState, Message) {
  case msg {
    Transact(facts, reply_to) -> {
      case do_transact(state, facts, fact.Assert) {
        Ok(new_state) -> {
          process.send(reply_to, Ok(new_state))
          let changed_attrs = list.map(facts, fn(f) { f.1 }) |> list.unique()
          process.send(state.reactive_actor, types.Notify(changed_attrs, new_state))
          actor.continue(new_state)
        }
        Error(err) -> {
          process.send(reply_to, Error(err))
          actor.continue(state)
        }
      }
    }
    Retract(facts, reply_to) -> {
      case do_transact(state, facts, fact.Retract) {
        Ok(new_state) -> {
          process.send(reply_to, Ok(new_state))
          let changed_attrs = list.map(facts, fn(f) { f.1 }) |> list.unique()
          process.send(state.reactive_actor, types.Notify(changed_attrs, new_state))
          actor.continue(new_state)
        }
        Error(err) -> {
          process.send(reply_to, Error(err))
          actor.continue(state)
        }
      }
    }
    GetState(reply_to) -> {
      process.send(reply_to, state)
      actor.continue(state)
    }
    SetSchema(attr, config, reply_to) -> {
      let existing = index.get_all_datoms_for_attr(state.eavt, attr)
        |> filter_active()
      let values = list.map(existing, fn(d) { d.value })
      let has_dupes = list.unique(values) |> list.length() != list.length(values)
      case config.unique && has_dupes {
        True -> {
          process.send(reply_to, Error("Cannot make non-unique attribute unique"))
          actor.continue(state)
        }
        False -> {
          let new_schema = dict.insert(state.schema, attr, config)
          let new_state = types.DbState(..state, schema: new_schema)
          process.send(reply_to, Ok(Nil))
          actor.continue(new_state)
        }
      }
    }
    RegisterFunction(name, func, reply_to) -> {
      let new_functions = dict.insert(state.functions, name, func)
      let new_state = types.DbState(..state, functions: new_functions)
      process.send(reply_to, Nil)
      actor.continue(new_state)
    }
    RegisterComposite(attrs, reply_to) -> {
      let new_composites = [attrs, ..state.composites]
      let new_state = types.DbState(..state, composites: new_composites)
      process.send(reply_to, Nil)
      actor.continue(new_state)
    }
    SetReactive(subject) -> {
      actor.continue(types.DbState(..state, reactive_actor: subject))
    }
  }
}

fn filter_active(datoms: List(fact.Datom)) -> List(fact.Datom) {
  let latest = list.fold(datoms, dict.new(), fn(acc, d) {
    let key = #(d.entity, d.attribute, d.value)
    case dict.get(acc, key) {
      Ok(#(tx, _op)) if tx > d.tx -> acc
      _ -> dict.insert(acc, key, #(d.tx, d.operation))
    }
  })
  list.filter(datoms, fn(d) {
    let key = #(d.entity, d.attribute, d.value)
    case dict.get(latest, key) {
      Ok(#(tx, op)) -> tx == d.tx && op == fact.Assert
      _ -> False
    }
  }) |> list.unique()
}

fn do_transact(state: types.DbState, facts: List(fact.Fact), op: fact.Operation) -> Result(types.DbState, String) {
  let resolved_facts = resolve_facts(state, facts)
  let tx_id = state.latest_tx + 1
  
  let result = list.fold_until(resolved_facts, Ok(state), fn(res_state, f) {
    let assert Ok(curr_state) = res_state
    
    case resolve_eid(curr_state, f.0) {
      Some(id) -> {
        case op {
          fact.Assert -> {
            let config = dict.get(curr_state.schema, f.1) |> result.unwrap(fact.AttributeConfig(False, False))
            
            // Cardinality One
            let sub_state = case config.unique {
              True -> {
                let existing = index.get_datoms_by_entity_attr(curr_state.eavt, id, f.1) |> filter_active()
                list.fold(existing, curr_state, fn(acc, d) {
                  apply_datom(acc, fact.Datom(..d, tx: tx_id, operation: fact.Retract))
                })
              }
              False -> curr_state
            }
            
            let datom = fact.Datom(entity: id, attribute: f.1, value: f.2, tx: tx_id, operation: fact.Assert)
            case check_constraints(sub_state, datom) {
              Ok(_) -> list.Continue(Ok(apply_datom(sub_state, datom)))
              Error(e) -> list.Stop(Error(e))
            }
          }
          fact.Retract -> {
             let config = dict.get(curr_state.schema, f.1) |> result.unwrap(fact.AttributeConfig(False, False))
             let sub_state = case config.component {
               True -> {
                 case f.2 {
                   fact.Int(sub_id) -> retract_recursive(curr_state, sub_id, tx_id)
                   _ -> curr_state
                 }
               }
               False -> curr_state
             }
             let datom = fact.Datom(entity: id, attribute: f.1, value: f.2, tx: tx_id, operation: fact.Retract)
             list.Continue(Ok(apply_datom(sub_state, datom)))
          }
        }
      }
      None -> {
        // Fail if it's still a db/fn call that wasn't resolved
        case f.0 {
          fact.Lookup(#(a, _)) if a == "db/fn" -> list.Stop(Error("Failed to resolve transaction function: " <> f.1))
          _ -> list.Continue(Ok(curr_state))
        }
      }
    }
  })

  case result {
    Ok(final_state) -> Ok(types.DbState(..final_state, latest_tx: tx_id))
    Error(e) -> Error(e)
  }
}

fn retract_recursive(state: types.DbState, eid: Int, tx_id: Int) -> types.DbState {
  let datoms = index.filter_by_entity(state.eavt, eid) |> filter_active()
  list.fold(datoms, state, fn(curr_state, d) {
    let config = dict.get(curr_state.schema, d.attribute) |> result.unwrap(fact.AttributeConfig(False, False))
    let sub_state = case config.component {
      True -> {
        case d.value {
          fact.Int(sub_id) -> retract_recursive(curr_state, sub_id, tx_id)
          _ -> curr_state
        }
      }
      False -> curr_state
    }
    let retract_datom = fact.Datom(..d, tx: tx_id, operation: fact.Retract)
    apply_datom(sub_state, retract_datom)
  })
}

fn apply_datom(state: types.DbState, datom: fact.Datom) -> types.DbState {
  state.adapter.persist_batch([datom])
  case datom.operation {
    fact.Assert -> {
      types.DbState(
        ..state,
        eavt: index.insert_eavt(state.eavt, datom),
        aevt: index.insert_aevt(state.aevt, datom),
        avet: index.insert_avet(state.avet, datom)
      )
    }
    fact.Retract -> {
       types.DbState(
        ..state,
        eavt: index.insert_eavt(state.eavt, datom),
        aevt: index.insert_aevt(state.aevt, datom),
        avet: index.delete_avet(state.avet, datom)
      )
    }
  }
}

fn resolve_facts(state: types.DbState, facts: List(fact.Fact)) -> List(fact.Fact) {
  list.flat_map(facts, fn(f) {
    case f.0 {
      fact.Lookup(#(attr, val)) if attr == "db/fn" -> {
        let name = case val {
           fact.Str(s) -> s
           _ -> ""
        }
        case dict.get(state.functions, name) {
          Ok(func) -> {
            let args = case f.2 {
              fact.List(l) -> l
              _ -> [f.2]
            }
            let new_facts = func(state, args)
            resolve_facts(state, new_facts)
          }
          Error(_) -> [f]
        }
      }
      _ -> [f]
    }
  })
}

fn resolve_eid(state: types.DbState, eid: fact.Eid) -> Option(Int) {
  case eid {
    fact.EntityId(id) -> Some(id)
    fact.Lookup(#(attr, val)) -> {
      case index.get_entity_by_av(state.avet, attr, val) {
        Ok(id) -> Some(id)
        Error(_) -> None
      }
    }
  }
}

fn check_constraints(state: types.DbState, datom: fact.Datom) -> Result(Nil, String) {
  let config = dict.get(state.schema, datom.attribute) |> result.unwrap(fact.AttributeConfig(False, False))
  let res_unique = case config.unique {
    True -> {
      case index.get_entity_by_av(state.avet, datom.attribute, datom.value) {
        Ok(existing_id) if existing_id != datom.entity -> Error("Uniqueness violation")
        _ -> Ok(Nil)
      }
    }
    False -> Ok(Nil)
  }
  
  result.try(res_unique, fn(_) {
    let composite = list.find(state.composites, fn(group) { list.contains(group, datom.attribute) })
    case composite {
      Ok(attrs) -> {
        let datoms = index.filter_by_entity(state.eavt, datom.entity) |> filter_active()
        let current_vals = list.fold(attrs, dict.new(), fn(acc, a) {
          case a == datom.attribute {
            True -> dict.insert(acc, a, datom.value)
            False -> {
              case list.find(datoms, fn(d) { d.attribute == a }) {
                Ok(d) -> dict.insert(acc, a, d.value)
                Error(_) -> acc
              }
            }
          }
        })
        case dict.size(current_vals) == list.length(attrs) {
          True -> {
             let all_entities = dict.keys(state.eavt)
             let violation = list.any(all_entities, fn(e) {
               e != datom.entity && {
                 let e_datoms = index.filter_by_entity(state.eavt, e) |> filter_active()
                 list.all(attrs, fn(a) {
                    let val = dict.get(current_vals, a) |> result.unwrap(fact.Int(0))
                    list.any(e_datoms, fn(d) { d.attribute == a && d.value == val })
                 })
               }
             })
             case violation {
               True -> Error("Composite uniqueness violation")
               False -> Ok(Nil)
             }
          }
          False -> Ok(Nil)
        }
      }
      Error(_) -> Ok(Nil)
    }
  })
}

pub fn transact(db: Db, facts: List(fact.Fact)) -> Result(types.DbState, String) {
  transact_with_timeout(db, facts, 5000)
}

pub fn transact_with_timeout(
  db: Db,
  facts: List(fact.Fact),
  timeout_ms: Int,
) -> Result(types.DbState, String) {
  let reply = process.new_subject()
  process.send(db, Transact(facts, reply))
  case process.receive(reply, timeout_ms) {
    Ok(res) -> res
    Error(_) -> Error("Timeout")
  }
}

pub fn retract(db: Db, facts: List(fact.Fact)) -> Result(types.DbState, String) {
  let reply = process.new_subject()
  process.send(db, Retract(facts, reply))
  case process.receive(reply, 5000) {
    Ok(res) -> res
    Error(_) -> Error("Timeout")
  }
}

pub fn get_state(db: Db) -> types.DbState {
  let reply = process.new_subject()
  process.send(db, GetState(reply))
  let assert Ok(res) = process.receive(reply, 5000)
  res
}

pub fn set_schema(
  db: Db,
  attr: String,
  config: fact.AttributeConfig,
) -> Result(Nil, String) {
  set_schema_with_timeout(db, attr, config, 5000)
}

pub fn set_schema_with_timeout(
  db: Db,
  attr: String,
  config: fact.AttributeConfig,
  timeout_ms: Int,
) -> Result(Nil, String) {
  let reply = process.new_subject()
  process.send(db, SetSchema(attr, config, reply))
  case process.receive(reply, timeout_ms) {
    Ok(res) -> res
    Error(_) -> Error("Timeout")
  }
}

pub fn register_function(
  db: Db,
  name: String,
  func: fact.DbFunction(types.DbState),
) -> Nil {
  let reply = process.new_subject()
  process.send(db, RegisterFunction(name, func, reply))
  let _ = process.receive(reply, 5000)
  Nil
}

pub fn register_composite(db: Db, attrs: List(String)) -> Nil {
  let reply = process.new_subject()
  process.send(db, RegisterComposite(attrs, reply))
  let _ = process.receive(reply, 5000)
  Nil
}
