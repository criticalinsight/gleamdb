import gleam/erlang/process
import gleam/otp/actor
import gleam/list
import gleam/dict
import gleam/result
import gleam/option.{type Option, None, Some}
import gleam/string
import gleamdb/fact
import gleamdb/shared/types
import gleamdb/engine
import gleamdb/index
import gleamdb/storage
import gleamdb/global
import gleamdb/reactive
import gleamdb/index/ets as ets_index

pub type Message {
  Transact(List(fact.Fact), process.Subject(Result(types.DbState, String)))
  Retract(List(fact.Fact), process.Subject(Result(types.DbState, String)))
  GetState(process.Subject(types.DbState))
  SetSchema(String, fact.AttributeConfig, process.Subject(Result(Nil, String)))
  RegisterFunction(String, fact.DbFunction(types.DbState), process.Subject(Nil))
  RegisterComposite(List(String), process.Subject(Nil))
  SetReactive(process.Subject(types.ReactiveMessage))
  Join(process.Pid)
  SyncDatoms(List(fact.Datom))
}

pub type Db =
  process.Subject(Message)

pub fn start(
  store: storage.StorageAdapter,
) -> Result(process.Subject(Message), actor.StartError) {
  start_with_timeout(store, 1000)
}

pub fn start_named(
  name: String,
  store: storage.StorageAdapter,
) -> Result(process.Subject(Message), actor.StartError) {
  // Start with distribution disabled by default for named databases
  // This enables ETS (Silicon Saturation) without forcing global consensus
  do_start_named(store, False, Some(name))
}

pub fn start_distributed(
  name: String,
  store: storage.StorageAdapter,
) -> Result(process.Subject(Message), actor.StartError) {
  // Start with distribution enabled
  let res = do_start_named(store, True, Some(name))
  case res {
    Ok(subject) -> {
      let pid = process_extra.subject_to_pid(subject)
      let _ = global.register("gleamdb_" <> name, pid)
      // Try to register as the primary leader if not exists
      case global.register("gleamdb_leader", pid) {
        Ok(_) -> Nil
        Error(_) -> {
          // If we are not the leader, tell the leader about us
          case global.whereis("gleamdb_leader") {
             Ok(leader_pid) -> {
               let leader_subject = process_extra.pid_to_subject(leader_pid)
               process.send(leader_subject, Join(pid))
             }
             Error(_) -> Nil
          }
        }
      }
      Ok(subject)
    }
    Error(err) -> Error(err)
  }
}

pub fn start_with_timeout(
  store: storage.StorageAdapter,
  _timeout_ms: Int,
) -> Result(process.Subject(Message), actor.StartError) {
  do_start_named(store, False, None)
}

fn do_start_named(store: storage.StorageAdapter, is_distributed: Bool, ets_name: Option(String)) -> Result(process.Subject(Message), actor.StartError) {
  store.init()
  let assert Ok(reactive_subject) = reactive.start_link()

  case ets_name {
    Some(name) -> ets_index.init_tables(name)
    None -> Nil
  }
  
  let base_state =
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
      reactive_actor: reactive_subject,
      followers: [],
      is_distributed: is_distributed,
      ets_name: ets_name,
    )

  let initial_state = recover_state(base_state)

  actor.new(initial_state)
  |> actor.on_message(handle_message)
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

fn handle_message(state: types.DbState, msg: Message) -> actor.Next(types.DbState, Message) {
  case msg {
    Transact(facts, reply_to) -> {
      case is_leader(state) {
        True -> do_handle_transact(state, facts, fact.Assert, reply_to)
        False -> {
          // Forward to leader
          case global.whereis("gleamdb_leader") {
            Ok(leader_pid) -> {
              let leader_subject = process_extra.pid_to_subject(leader_pid)
              process.send(leader_subject, Transact(facts, reply_to))
              actor.continue(state)
            }
            Error(_) -> do_handle_transact(state, facts, fact.Assert, reply_to)
          }
        }
      }
    }
    Retract(facts, reply_to) -> {
       case is_leader(state) {
        True -> do_handle_transact(state, facts, fact.Retract, reply_to)
        False -> {
          case global.whereis("gleamdb_leader") {
            Ok(leader_pid) -> {
              let leader_subject = process_extra.pid_to_subject(leader_pid)
              process.send(leader_subject, Retract(facts, reply_to))
              actor.continue(state)
            }
            Error(_) -> do_handle_transact(state, facts, fact.Retract, reply_to)
          }
        }
      }
    }
    GetState(reply_to) -> {
      process.send(reply_to, state)
      actor.continue(state)
    }
    SetSchema(attr, config, reply_to) -> {
      let existing = index.get_all_datoms_for_attr(state.eavt, attr)
        |> filter_latest_per_entity_attr()
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
    Join(pid) -> {
      let new_followers = [pid, ..state.followers]
      actor.continue(types.DbState(..state, followers: new_followers))
    }
    SyncDatoms(datoms) -> {
      let new_state = list.fold(datoms, state, fn(acc, d) {
        apply_datom(acc, d)
      })
      
      let changed_attrs = list.map(datoms, fn(d) { d.attribute }) |> list.unique()
      process.send(state.reactive_actor, types.Notify(changed_attributes: changed_attrs, current_state: new_state))

      // Update latest_tx based on synced datoms
      let max_tx = list.fold(datoms, state.latest_tx, fn(acc, d) {
        case d.tx > acc { True -> d.tx False -> acc }
      })
      actor.continue(types.DbState(..new_state, latest_tx: max_tx))
    }
  }
}

fn is_leader(state: types.DbState) -> Bool {
  case state.is_distributed {
    False -> True
    True -> {
      let self_pid = process_extra.self()
      case global.whereis("gleamdb_leader") {
        Ok(leader_pid) -> leader_pid == self_pid
        Error(_) -> True // If no leader registered, we are the de-facto if we try
      }
    }
  }
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

pub fn retract_with_timeout(
  db: Db,
  facts: List(fact.Fact),
  timeout_ms: Int,
) -> Result(types.DbState, String) {
  let reply = process.new_subject()
  process.send(db, Retract(facts, reply))
  case process.receive(reply, timeout_ms) {
    Ok(res) -> res
    Error(_) -> Error("Timeout")
  }
}

pub fn get_state(db: Db) -> types.DbState {
  let reply = process.new_subject()
  process.send(db, GetState(reply))
  process.receive_forever(reply)
}

pub fn set_schema(db: Db, attr: String, config: fact.AttributeConfig) -> Result(Nil, String) {
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

fn do_handle_transact(state: types.DbState, facts: List(fact.Fact), op: fact.Operation, reply_to: process.Subject(Result(types.DbState, String))) -> actor.Next(types.DbState, Message) {
  case do_transact(state, facts, op) {
    Ok(#(new_state, datoms)) -> {
      process.send(reply_to, Ok(new_state))
      let changed_attrs = list.map(facts, fn(f) { f.1 }) |> list.unique()
      process.send(state.reactive_actor, types.Notify(changed_attributes: changed_attrs, current_state: new_state))
      
      // Broadcast to followers
      list.each(state.followers, fn(f_pid) {
        let f_subject = process_extra.pid_to_subject(f_pid)
        process.send(f_subject, SyncDatoms(datoms))
      })
      
      actor.continue(new_state)
    }
    Error(err) -> {
      process.send(reply_to, Error(err))
      actor.continue(state)
    }
  }
}

fn filter_latest_per_entity_attr(datoms: List(fact.Datom)) -> List(fact.Datom) {
  let latest_txs = list.fold(datoms, dict.new(), fn(acc, d) {
    let key = #(d.entity, d.attribute)
    case dict.get(acc, key) {
      Ok(tx) if tx > d.tx -> acc
      _ -> dict.insert(acc, key, d.tx)
    }
  })
  
  list.filter(datoms, fn(d) {
    let key = #(d.entity, d.attribute)
    case dict.get(latest_txs, key) {
      Ok(tx) -> tx == d.tx && d.operation == fact.Assert
      _ -> False
    }
  }) |> list.unique()
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

fn recover_state(state: types.DbState) -> types.DbState {
  case state.adapter.recover() {
    Ok(datoms) -> {
      // Re-apply all datoms to reconstruct indices
      let #(final_state, max_tx) = list.fold(datoms, #(state, 0), fn(acc, d) {
        let #(curr_state, curr_max) = acc
        let next_state = apply_datom(curr_state, d)
        let next_max = case d.tx > curr_max {
          True -> d.tx
          False -> curr_max
        }
        #(next_state, next_max)
      })
      types.DbState(..final_state, latest_tx: max_tx)
    }
    Error(_) -> state
  }
}

fn do_transact(state: types.DbState, facts: List(fact.Fact), op: fact.Operation) -> Result(#(types.DbState, List(fact.Datom)), String) {
  let tx_id = state.latest_tx + 1
  
  // 1. Resolve Transaction Functions (Recursive)
  let resolved_facts = resolve_transaction_functions(state, facts)
  
  // 2. Process Facts
  let result = list.fold_until(resolved_facts, Ok(#(state, [])), fn(acc_res, f) {
    let assert Ok(#(curr_state, acc_datoms)) = acc_res
    
    case resolve_eid(curr_state, f.0) {
      Some(id) -> {
        case op {
          fact.Assert -> {
            let config = dict.get(curr_state.schema, f.1) |> result.unwrap(fact.AttributeConfig(False, False, fact.All))
            
            // Cardinality One
            let #(sub_state, sub_datoms) = case config.unique {
              True -> {
                let existing = index.get_datoms_by_entity_attr(curr_state.eavt, id, f.1) |> filter_active()
                list.fold(existing, #(curr_state, []), fn(acc, d) {
                  let #(st, ds) = acc
                  let retract_datom = fact.Datom(..d, tx: tx_id, operation: fact.Retract)
                  #(apply_datom(st, retract_datom), [retract_datom, ..ds])
                })
              }
              False -> #(curr_state, [])
            }
            
            let datom = fact.Datom(entity: id, attribute: f.1, value: f.2, tx: tx_id, operation: fact.Assert)
            
            // Validation
            case check_constraints(sub_state, datom) {
              Ok(_) -> {
                case check_composite_uniqueness(sub_state, datom) {
                   Ok(_) -> list.Continue(Ok(#(apply_datom(sub_state, datom), [datom, ..list.append(sub_datoms, acc_datoms)])))
                   Error(e) -> list.Stop(Error(e))
                }
              }
              Error(e) -> list.Stop(Error(e))
            }
          }
          fact.Retract -> {
             let config = dict.get(curr_state.schema, f.1) |> result.unwrap(fact.AttributeConfig(False, False, fact.All))
             let #(sub_state, sub_datoms) = case config.component {
               True -> {
                 case f.2 {
                   fact.Int(sub_id) -> retract_recursive_collected(curr_state, fact.EntityId(sub_id), tx_id, [])
                   _ -> #(curr_state, [])
                 }
               }
               False -> #(curr_state, [])
             }
             let datom = fact.Datom(entity: id, attribute: f.1, value: f.2, tx: tx_id, operation: fact.Retract)
             list.Continue(Ok(#(apply_datom(sub_state, datom), [datom, ..list.append(sub_datoms, acc_datoms)])))
          }
        }
      }
      None -> {
        list.Continue(Ok(#(curr_state, acc_datoms)))
      }
    }
  })

  case result {
    Ok(#(final_state, all_datoms)) -> {
      let reversed = list.reverse(all_datoms)
      final_state.adapter.persist_batch(reversed)
      Ok(#(types.DbState(..final_state, latest_tx: tx_id), reversed) )
    }
    Error(e) -> Error(e)
  }
}

fn resolve_transaction_functions(state: types.DbState, facts: List(fact.Fact)) -> List(fact.Fact) {
  list.flat_map(facts, fn(f) {
    case f.0 {
      fact.Lookup(#("db/fn", fact.Str(fn_name))) -> {
        case dict.get(state.functions, fn_name) {
          Ok(func) -> {
            let args = case f.2 {
              fact.List(l) -> l
              _ -> [f.2]
            }
            let new_facts = func(state, args)
            resolve_transaction_functions(state, new_facts)
          }
          Error(_) -> [f] // Fallback, let down-stream handle error if needed
        }
      }
      _ -> [f]
    }
  })
}

fn check_composite_uniqueness(state: types.DbState, datom: fact.Datom) -> Result(Nil, String) {
  let composites = list.filter(state.composites, fn(c) { list.contains(c, datom.attribute) })
  
  list.fold_until(composites, Ok(Nil), fn(_, composite) {
    // For each composite that includes this attribute, find all entities that have all attributes in the composite
    // with these SAME values.
    
    // Construct query to find duplicates
    let clauses = list.map(composite, fn(attr) {
      let val = case attr == datom.attribute {
        True -> datom.value
        False -> {
          // Find current value for this attribute on this entity
          let existing = index.get_datoms_by_entity_attr(state.eavt, datom.entity, attr) |> filter_active()
          case list.first(existing) {
            Ok(d) -> d.value
            Error(_) -> fact.Str("__MISSING__")
          }
        }
      }
      types.Positive(#(types.Var("e"), attr, types.Val(val)))
    })
    
    // Run query
    let results = engine.run(state, clauses, [], None)
    
    // If any result is NOT our current entity, it's a violation
    let has_violation = list.any(results, fn(binding) {
      case dict.get(binding, "e") {
        Ok(fact.Int(eid)) -> fact.EntityId(eid) != datom.entity
        _ -> False
      }
    })
    
    case has_violation {
      True -> list.Stop(Error("Composite uniqueness violation: " <> string.inspect(composite)))
      False -> list.Continue(Ok(Nil))
    }
  })
}

pub fn transact(db: Db, facts: List(fact.Fact)) -> Result(types.DbState, String) {
  transact_with_timeout(db, facts, 5000)
}

fn retract_recursive_collected(state: types.DbState, eid: fact.EntityId, tx_id: Int, acc: List(fact.Datom)) -> #(types.DbState, List(fact.Datom)) {
  let children = index.filter_by_entity(state.eavt, eid) |> filter_active()
  list.fold(children, #(state, acc), fn(curr, d) {
    let #(curr_state, curr_acc) = curr
    let config = dict.get(curr_state.schema, d.attribute) |> result.unwrap(fact.AttributeConfig(False, False, fact.All))
    let #(sub_state, sub_acc) = case config.component {
      True -> {
        case d.value {
          fact.Int(sub_id) -> retract_recursive_collected(curr_state, fact.EntityId(sub_id), tx_id, curr_acc)
          _ -> #(curr_state, curr_acc)
        }
      }
      False -> #(curr_state, curr_acc)
    }
    let retract_datom = fact.Datom(..d, tx: tx_id, operation: fact.Retract)
    #(apply_datom(sub_state, retract_datom), [retract_datom, ..sub_acc])
  })
}

fn apply_datom(state: types.DbState, datom: fact.Datom) -> types.DbState {
  let config = dict.get(state.schema, datom.attribute) |> result.unwrap(fact.AttributeConfig(False, False, fact.All))
  let retention = config.retention

  case state.ets_name {
    Some(name) -> {
      case retention {
        fact.LatestOnly -> {
           ets_index.prune_historical(name <> "_eavt", datom.entity, datom.attribute)
           ets_index.prune_historical_aevt(name <> "_aevt", datom.attribute, datom.entity)
        }
        _ -> Nil
      }
      
      ets_index.insert_datom(name <> "_eavt", datom.entity, datom)
      ets_index.insert_datom(name <> "_aevt", datom.attribute, datom)
      case datom.operation {
        fact.Assert -> ets_index.insert_avet(name <> "_avet", #(datom.attribute, datom.value), datom.entity)
        fact.Retract -> ets_index.delete(name <> "_avet", #(datom.attribute, datom.value))
      }
    }
    None -> Nil
  }

  case datom.operation {
    fact.Assert -> {
      types.DbState(
        ..state,
        eavt: index.insert_eavt(state.eavt, datom, retention),
        aevt: index.insert_aevt(state.aevt, datom, retention),
        avet: index.insert_avet(state.avet, datom)
      )
    }
    fact.Retract -> {
      types.DbState(
        ..state,
        eavt: index.delete_eavt(state.eavt, datom),
        aevt: index.delete_aevt(state.aevt, datom),
        avet: index.delete_avet(state.avet, datom)
      )
    }
  }
}

pub fn retract(db: Db, facts: List(fact.Fact)) -> Result(types.DbState, String) {
  retract_with_timeout(db, facts, 5000)
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

fn resolve_eid(state: types.DbState, eid: fact.Eid) -> Option(fact.EntityId) {
  case eid {
    fact.Uid(id) -> Some(id)
    fact.Lookup(#(a, v)) -> index.get_entity_by_av(state.avet, a, v) |> option.from_result()
  }
}

fn check_constraints(state: types.DbState, datom: fact.Datom) -> Result(Nil, String) {
  let config = dict.get(state.schema, datom.attribute) |> result.unwrap(fact.AttributeConfig(False, False, fact.All))
  case config.unique {
    True -> {
      case index.get_entity_by_av(state.avet, datom.attribute, datom.value) {
        Ok(existing_id) if existing_id != datom.entity -> Error("Unique constraint violation on " <> datom.attribute)
        _ -> Ok(Nil)
      }
    }
    False -> Ok(Nil)
  }
}
