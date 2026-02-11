import gleam/list
import gleam/int
import gleam/string
import gleam/dict.{type Dict}
import gleam/result
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleamdb/fact.{type Fact, type Datom, Datom, Assert}
import gleamdb/index.{type Index, type AIndex}
import gleamdb/storage.{type StorageAdapter}
import gleam/io

@external(erlang, "gleamdb_telemetry_ffi", "system_time")
pub fn system_time() -> Int

pub type DbState {
  DbState(
    adapter: StorageAdapter,
    eavt: Index,
    aevt: AIndex,
    latest_tx: Int,
    subscribers: List(Subject(List(Datom))),
    schema: Dict(String, fact.AttributeConfig),
    functions: Dict(String, fact.DbFunction(DbState)),
    composites: List(List(String)),
  )
}

pub type Message {
  Transact(facts: List(Fact), reply_to: Subject(Result(DbState, String)))
  Retract(facts: List(Fact), reply_to: Subject(Result(DbState, String)))
  GetState(reply_to: Subject(DbState))
  Subscribe(pid: Subject(List(Datom)), reply_to: Subject(Nil))
  RemoteTransact(datoms: List(Datom), reply_to: Subject(DbState))
  SetSchema(
    attr: String,
    config: fact.AttributeConfig,
    reply_to: Subject(Result(Nil, String)),
  )
  RegisterFunction(name: String, func: fact.DbFunction(DbState), reply_to: Subject(Nil))
  RegisterComposite(attrs: List(String), reply_to: Subject(Nil))
}

pub type Db = Subject(Message)

pub fn start_link(adapter: StorageAdapter) -> Result(Db, actor.StartError) {
  adapter.init()
  let recovered_datoms = case adapter.recover() {
    Ok(ds) -> ds
    Error(_) -> []
  }

  let eavt = list.fold(recovered_datoms, index.new_index(), index.insert_eavt)
  let aevt = list.fold(recovered_datoms, index.new_aindex(), index.insert_aevt)
  let latest_tx = list.fold(recovered_datoms, 0, fn(acc, d) {
    case d.tx > acc {
      True -> d.tx
      False -> acc
    }
  })
  
  actor.new(DbState(
    adapter: adapter,
    eavt: eavt,
    aevt: aevt,
    latest_tx: latest_tx,
    subscribers: [],
    schema: dict.new(),
    functions: dict.new(),
    composites: [],
  ))
  |> actor.on_message(fn(state: DbState, msg: Message) {
    case msg {
      Transact(facts, reply_to) -> {
        let validation = validate_uniqueness(state, facts)
        case validation {
          Error(err) -> {
            process.send(reply_to, Error(err))
            actor.continue(state)
          }
          Ok(_) -> {
            case validate_composite_uniqueness(state, facts) {
              Error(err) -> {
                process.send(reply_to, Error(err))
                actor.continue(state)
              }
              Ok(_) -> {
                let next_tx = state.latest_tx + 1
                let expanded_facts = expand_functions(state, facts)
                let result = list.fold(expanded_facts, Ok([]), fn(acc, f) {
                  case acc {
                    Error(e) -> Error(e)
                    Ok(ds) -> {
                      let #(eid, a, v) = f
                      case resolve_eid(state, eid) {
                        Ok(e) -> {
                          // Find existing datoms for this (e, a) to retract them (Cardinality One)
                          let existing =
                            index.filter_by_entity(state.eavt, e)
                            |> list.filter(fn(d) { d.attribute == a })
                          let retractions =
                            list.map(existing, fn(ed) {
                              Datom(
                                ed.entity,
                                ed.attribute,
                                ed.value,
                                next_tx,
                                fact.Retract,
                              )
                            })

                          let d = Datom(e, a, v, next_tx, Assert)
                          Ok(list.flatten([[d, ..retractions], ds]))
                        }
                        Error(err) -> Error(err)
                      }
                    }
                  }
                })

                case result {
                  Error(err) -> {
                    process.send(reply_to, Error(err))
                    actor.continue(state)
                  }
                  Ok(datoms) -> {
                    let start = system_time()
                    state.adapter.persist_batch(datoms)
                    let end = system_time()
                    let duration = end - start
                    
                    io.println("[GleamDB] Transact: " <> int.to_string(duration) <> "ms (batch: " <> int.to_string(list.length(datoms)) <> ")")
                    
                    // Notify subscribers
                    list.each(state.subscribers, fn(sub) {
                      process.send(sub, datoms)
                    })

                    let new_state =
                      DbState(
                        ..state,
                        eavt: list.fold(datoms, state.eavt, index.insert_eavt),
                        aevt: list.fold(datoms, state.aevt, index.insert_aevt),
                        latest_tx: next_tx,
                      )
                    process.send(reply_to, Ok(new_state))
                    actor.continue(new_state)
                  }
                }
              }
            }
          }
        }
      }
      Retract(facts, reply_to) -> {
        let next_tx = state.latest_tx + 1
        let result = list.fold(facts, Ok([]), fn(acc, f) {
          case acc {
            Error(e) -> Error(e)
            Ok(ds) -> {
              let #(eid, a, v) = f
              case resolve_eid(state, eid) {
                Ok(e) -> {
                  let d = Datom(e, a, v, next_tx, fact.Retract)
                  Ok([d, ..ds])
                }
                Error(err) -> Error(err)
              }
            }
          }
        })

        case result {
          Error(err) -> {
            process.send(reply_to, Error(err))
            actor.continue(state)
          }
          Ok(datoms) -> {
            let start = system_time()
            let expanded_datoms = expand_cascades(state, datoms, next_tx)
            state.adapter.persist_batch(expanded_datoms)
            let end = system_time()
            let duration = end - start
            
            io.println("[GleamDB] Retract: " <> int.to_string(duration) <> "ms (batch: " <> int.to_string(list.length(expanded_datoms)) <> ")")
            
            // Notify subscribers
            list.each(state.subscribers, fn(sub) { process.send(sub, expanded_datoms) })

            let new_state = DbState(
              ..state,
              eavt: list.fold(expanded_datoms, state.eavt, index.insert_eavt),
              aevt: list.fold(expanded_datoms, state.aevt, index.insert_aevt),
              latest_tx: next_tx
            )
            process.send(reply_to, Ok(new_state))
            actor.continue(new_state)
          }
        }
      }
      RemoteTransact(datoms, reply_to) -> {
        let new_eavt = list.fold(datoms, state.eavt, index.insert_eavt)
        let new_aevt = list.fold(datoms, state.aevt, index.insert_aevt)
        let max_tx = list.fold(datoms, state.latest_tx, fn(acc, d) {
          let d: Datom = d
          case d.tx > acc { True -> d.tx False -> acc }
        })
        let new_state = DbState(
          ..state,
          eavt: new_eavt,
          aevt: new_aevt,
          latest_tx: max_tx
        )
        process.send(reply_to, new_state)
        actor.continue(new_state)
      }
      Subscribe(pid, reply_to) -> {
        process.send(reply_to, Nil)
        actor.continue(DbState(..state, subscribers: [pid, ..state.subscribers]))
      }
      GetState(reply_to) -> {
        process.send(reply_to, state)
        actor.continue(state)
      }
      SetSchema(attr, config, reply_to) -> {
        // Schema Guard: If making unique, check for existing duplicates
        let valid = case config.unique {
          True -> {
            let active_values = index.filter_by_attribute(state.aevt, attr)
              |> list.sort(fn(a, b) { int.compare(a.tx, b.tx) })
              |> list.fold(dict.new(), fn(acc, d) {
                case d.operation {
                  fact.Assert -> dict.insert(acc, d.entity, d.value)
                  fact.Retract -> dict.delete(acc, d.entity)
                }
              })
              |> dict.values()
            
            let unique_values = list.unique(active_values)
            list.length(active_values) == list.length(unique_values)
          }
          False -> True
        }

        case valid {
          True -> {
            let new_state = DbState(..state, schema: dict.insert(state.schema, attr, config))
            process.send(reply_to, Ok(Nil))
            actor.continue(new_state)
          }
          False -> {
            // How to reply error? SetSchema reply_to is Subject(Nil) in current definition.
            // We need to change Message definition to Subject(Result(Nil, String))
            // For now, let's crash or ignore? 
            // Better: Update Message type.
            process.send(reply_to, Error("Schema Guard: Attribute has duplicates"))
            actor.continue(state)
          }
        }
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
    }
  })
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

fn expand_cascades(state: DbState, datoms: List(Datom), tx: Int) -> List(Datom) {
  list.fold(datoms, [], fn(acc, d) {
    let acc = [d, ..acc]
    case d.operation {
      fact.Retract -> {
        case dict.get(state.schema, d.attribute) {
          Ok(fact.AttributeConfig(component: True, ..)) -> {
            case d.value {
              fact.Int(sub_eid) -> {
                let sub_datoms = index.filter_by_entity(state.eavt, sub_eid)
                let sub_retractions = list.map(sub_datoms, fn(sd) {
                  Datom(sd.entity, sd.attribute, sd.value, tx, fact.Retract)
                })
                let recursively_expanded = expand_cascades(state, sub_retractions, tx)
                list.flatten([recursively_expanded, acc])
              }
              _ -> acc
            }
          }
          _ -> acc
        }
      }
      _ -> acc
    }
  })
  |> list.unique()
}

fn expand_functions(state: DbState, facts: List(Fact)) -> List(Fact) {
  list.flat_map(facts, fn(f) {
    case f {
      #(fact.Lookup(#(attr, fact.Str(fn_name))), _a, fact.List(args)) if attr == "db/fn" -> {
        case dict.get(state.functions, fn_name) {
          Ok(func) -> {
            let result_facts = func(state, args)
            expand_functions(state, result_facts)
          }
          Error(_) -> [f]
        }
      }
      _ -> [f]
    }
  })
}

fn resolve_eid(state: DbState, eid: fact.Eid) -> Result(fact.Entity, String) {
  case eid {
    fact.EntityId(e) -> Ok(e)
    fact.Lookup(#(a, v)) -> {
      let datoms = index.filter_by_attribute(state.aevt, a)
      let found = list.find(datoms, fn(d) { d.value == v })
      case found {
        Ok(d) -> Ok(d.entity)
        Error(_) -> Error("Lookup failed for entity: " <> a)
      }
    }
  }
}

fn validate_uniqueness(state: DbState, facts: List(Fact)) -> Result(Nil, String) {
  list.fold_until(facts, Ok(Nil), fn(_acc, f) {
    let #(_, a, v) = f
    case dict.get(state.schema, a) {
      Ok(fact.AttributeConfig(unique: True, ..)) -> {
        let existing = index.filter_by_attribute(state.aevt, a)
        let conflict = list.find(existing, fn(d) { d.value == v })
        case conflict {
          Ok(_) -> list.Stop(Error("Unique constraint violation for attribute: " <> a))
          Error(_) -> list.Continue(Ok(Nil))
        }
      }
      _ -> list.Continue(Ok(Nil))
    }
  })
}

fn validate_composite_uniqueness(state: DbState, facts: List(Fact)) -> Result(Nil, String) {
  list.fold_until(state.composites, Ok(Nil), fn(_acc, attrs) {
    // For each defined composite constraint, check if the transaction violates it
    case check_composite(state, facts, attrs) {
      Ok(_) -> list.Continue(Ok(Nil))
      Error(e) -> list.Stop(Error(e))
    }
  })
}

fn check_composite(state: DbState, facts: List(Fact), attrs: List(String)) -> Result(Nil, String) {
  // 1. Group facts by Entity
  let facts_by_entity = list.fold(facts, dict.new(), fn(acc, f) {
    let #(eid, a, v) = f
    // Only resolve EntityId for now, Lookup refs in facts might be tricky here without full resolution
    // but for the sake of the constraint check, we group by the *input* eid. 
    // If the user mixes EntityId(1) and Lookup(attr, val) that resolve to 1, this check might be partial 
    // without a pre-resolution step. For Phase 9 MVP, assuming consistent usage or pre-resolution.
    // Actually, expand_functions happens before this, but resolve_eid happens *after*. 
    // Ideally validation should happen on resolved entities. 
    // Let's assume EntityId for simpler grouping or we'd need to map.
    let key = case eid { fact.EntityId(e) -> e _ -> -1 } 
    case list.contains(attrs, a) {
      True -> {
         let current = case dict.get(acc, key) { Ok(vals) -> vals Error(_) -> [] }
         dict.insert(acc, key, [#(a, v), ..current])
      }
      False -> acc
    }
  })

  // 2. For each entity involved, check if it forms a complete composite tuple
  dict.fold(facts_by_entity, Ok(Nil), fn(acc, _eid, entity_facts) {
    case acc {
      Error(_) -> acc // already failed
      Ok(_) -> {
        // If the entity has ALL attributes of the composite
        let has_all = list.all(attrs, fn(required_attr) {
          list.any(entity_facts, fn(ef) { let #(a, _) = ef a == required_attr })
        })
        
        case has_all {
          True -> {
            // 3. Check if this tuple already exists in DB
            // We need to find if ANY other entity has this exact combination
            // This is an expensive check: O(Entities * Attrs). 
            // Optimization: Filter by the first attribute's value, then narrow down.
            
            // Get value of first attribute
            let first_attr = case attrs { [h, ..] -> h [] -> "" }
            let first_val_opt = list.find_map(entity_facts, fn(ef) { 
              let #(a, v) = ef 
              case a == first_attr { True -> Ok(v) False -> Error(Nil) } 
            })
            
            case first_val_opt {
              Ok(v) -> {
                 // Candidates: Entities having first_attr == v
                 let candidates = index.filter_by_attribute(state.aevt, first_attr)
                   |> list.filter(fn(d) { d.value == v })
                   |> list.map(fn(d) { d.entity })
                 
                 // For each candidate, check if they match ALL other attributes
                 let conflict = list.any(candidates, fn(cand_eid) {
                   list.all(entity_facts, fn(ef) {
                     let #(a, target_v) = ef
                     // We check DB for (cand_eid, a) == target_v
                     let existing_datoms = index.filter_by_entity(state.eavt, cand_eid)
                     list.any(existing_datoms, fn(existing_d) { 
                        existing_d.attribute == a && existing_d.value == target_v
                     })
                   })
                 })
                 
                 case conflict {
                   True -> Error("Composite uniqueness violation: " <> string.join(attrs, ", "))
                   False -> Ok(Nil)
                 }
              }
              Error(_) -> Ok(Nil) // Should not happen given has_all check
            }
          }
          False -> Ok(Nil) // Partial update, assume valid (or handle partial checks if strict)
        }
      }
    }
  })
}

pub fn transact(db: Db, facts: List(Fact)) -> Result(DbState, String) {
  process.call(db, 5000, Transact(facts, _))
}

pub fn transact_with_timeout(
  db: Db,
  facts: List(Fact),
  timeout: Int,
) -> Result(DbState, String) {
  process.call(db, timeout, Transact(facts, _))
}

pub fn retract(db: Db, facts: List(Fact)) -> Result(DbState, String) {
  process.call(db, 5000, Retract(facts, _))
}

pub fn get_state(db: Db) -> DbState {
  process.call(db, 5000, GetState(_))
}

pub fn subscribe(db: Db, pid: Subject(List(Datom))) -> Nil {
  process.call(db, 5000, Subscribe(pid, _))
}

pub fn remote_transact(db: Db, datoms: List(Datom)) -> DbState {
  process.call(db, 5000, RemoteTransact(datoms, _))
}

pub fn set_schema(
  db: Db,
  attr: String,
  config: fact.AttributeConfig,
) -> Result(Nil, String) {
  process.call(db, 5000, SetSchema(attr, config, _))
}
