import gleam/list
import gleam/int
import gleam/result
import gleam/dict
import gleam/option.{type Option, None, Some}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/io
import gleam/order

@external(erlang, "gleamdb_telemetry_ffi", "system_time")
pub fn system_time() -> Int

import gleamdb/fact.{type Datom, type Value, Int, Vec, Datom, Assert}
import gleamdb/shared/types.{
  type BodyClause, type DbState, type QueryResult, Aggregate, Similarity,
  Val, Var,
}
pub fn var(name: String) { Var(name) }
pub fn val(value: fact.Value) { Val(value) }
import gleamdb/index
import gleamdb/storage
import gleamdb/vector

pub fn new() -> DbState {
  init_state()
}

pub fn init_state() -> DbState {
  types.DbState(
    adapter: storage.StorageAdapter(
      init: fn() { Nil },
      persist: fn(_) { Nil },
      persist_batch: fn(_) { Nil },
      recover: fn() { Ok([]) },
    ),
    eavt: dict.new(),
    aevt: dict.new(),
    latest_tx: 0,
    subscribers: [],
    schema: dict.new(),
    functions: dict.new(),
    composites: [],
    reactive_actor: process.new_subject(),
  )
}

pub type Rule {
  Rule(
    name: String,
    head: types.Clause,
    body: List(BodyClause),
  )
}

pub type PullPattern {
  AllAttributes
  AttributeList(List(String))
  Nested(String, PullPattern)
  Deep(List(PullPattern))
}

pub type PullResult = dict.Dict(String, PullValue)

pub type PullValue {
  Single(Value)
  Many(List(Value))
  Map(PullResult)
  Maps(List(PullResult))
}

pub type Message {
  Execute(reply_to: Subject(QueryResult))
  ExecuteWithRules(rules: List(Rule), reply_to: Subject(QueryResult))
  GetStatus(reply_to: Subject(String))
}

pub fn start_query(
  db_state: DbState,
  clauses: List(BodyClause),
  as_of_tx: Option(Int),
) -> Result(Subject(Message), actor.StartError) {
  actor.new(Nil)
  |> actor.on_message(fn(msg, state) {
    let msg: Message = coerce(msg)
    case msg {
      Execute(reply_to) -> {
        let result = do_execute_query(db_state, clauses, [], as_of_tx)
        process.send(reply_to, result)
        actor.continue(state)
      }
      ExecuteWithRules(rules, reply_to) -> {
        let result = do_execute_query(db_state, clauses, rules, as_of_tx)
        process.send(reply_to, result)
        actor.continue(state)
      }
      GetStatus(reply_to) -> {
        process.send(reply_to, "Running")
        actor.continue(state)
      }
    }
  })
  |> actor.start()
  |> result.map(fn(started) { started.pid |> coerce })
}

pub fn run(
  db_state: DbState,
  clauses: List(BodyClause),
  rules: List(Rule),
  as_of_tx: Option(Int),
) -> QueryResult {
  let start = system_time()
  let result = do_execute_query(db_state, clauses, rules, as_of_tx)
  let duration = system_time() - start
  io.println(
    "Query took "
    <> int.to_string(duration)
    <> "ms ("
    <> int.to_string(list.length(result))
    <> " results)",
  )
  result
}

fn do_execute_query(
  db_state: DbState,
  clauses: List(BodyClause),
  rules: List(Rule),
  as_of_tx: Option(Int),
) -> QueryResult {
  // Check for stratification if rules are present
  let is_stratified = check_stratification(rules)
  case is_stratified {
    False -> [] // Should probably return an error, but returning empty for now
    True -> {
      let derived_datoms = evaluate_rules(db_state, rules, as_of_tx)
      
      let world =
        db_state
      let world =
        types.DbState(
          ..world,
          eavt: list.fold(derived_datoms, world.eavt, index.insert_eavt),
          aevt: list.fold(derived_datoms, world.aevt, index.insert_aevt),
        )

      let bindings = execute_join_internal(world, clauses, as_of_tx)
      
      let final_bindings =
        list.fold(clauses, bindings, fn(acc_bindings, clause) {
          case clause {
            Aggregate(var, func, target) -> {
              apply_aggregation(acc_bindings, var, func, target)
            }
            Similarity(var, target_vec, threshold) -> {
              list.filter(acc_bindings, fn(b) { apply_similarity(b, var, target_vec, threshold) })
            }
            _ -> acc_bindings
          }
        })

      final_bindings
      |> list.unique()
    }
  }
}

fn check_stratification(rules: List(Rule)) -> Bool {
  // Simple check: Rule R cannot use NOT P in its body if P is derived by R (directly or indirectly)
  // Build relationship graph: head_attr -> body_attr (weighted by negation)
  let head_attrs = list.map(rules, fn(r) { let #(_, a, _) = r.head a })
  
  list.all(rules, fn(r) {
    let #(_, head_attr, _) = r.head
    list.all(r.body, fn(clause) {
      case clause {
        types.Negative(#(_, body_attr, _)) -> {
          case list.contains(head_attrs, body_attr) {
            True -> !has_negative_path(body_attr, head_attr, rules, [], True)
            False -> True
          }
        }
        _ -> True
      }
    })
  })
}

fn has_negative_path(
  start: String,
  target: String,
  rules: List(Rule),
  visited: List(String),
  has_neg: Bool,
) -> Bool {
  case start == target {
    True -> has_neg
    False -> {
      let next_steps = list.filter_map(rules, fn(r) {
        let #(_, head, _) = r.head
        case head == start {
          True -> {
            let negs = list.filter_map(r.body, fn(c) {
              case c {
                types.Negative(#(_, a, _)) -> Ok(#(a, True))
                types.Positive(#(_, a, _)) -> Ok(#(a, False))
                _ -> Error(Nil)
              }
            })
            Ok(negs)
          }
          False -> Error(Nil)
        }
      }) |> list.flatten()

      list.any(next_steps, fn(step) {
        let #(next, is_neg) = step
        case list.contains(visited, next) {
          True -> next == target && { has_neg || is_neg }
          False -> has_negative_path(next, target, rules, [next, ..visited], has_neg || is_neg)
        }
      })
    }
  }
}

fn optimize_body_clauses(clauses: List(BodyClause)) -> List(BodyClause) {
  list.sort(clauses, fn(a, b) {
    let score_a = get_body_clause_score(a)
    let score_b = get_body_clause_score(b)
    case score_a > score_b {
      True -> order.Lt
      False -> order.Gt
    }
  })
}

fn get_body_clause_score(clause: BodyClause) -> Int {
  case clause {
    types.Positive(#(types.Val(_), _, types.Val(_))) -> 100
    types.Positive(#(types.Val(_), _, _)) -> 80
    types.Positive(#(_, _, types.Val(_))) -> 60
    types.Positive(_) -> 40
    types.Negative(_) -> 20
    _ -> 0
  }
}

fn apply_similarity(
  bindings: dict.Dict(String, Value),
  var_name: String,
  target_vec: List(Float),
  threshold: Float,
) -> Bool {
  case dict.get(bindings, var_name) {
    Ok(Vec(v)) -> {
       let sim = vector.cosine_similarity(v, target_vec)
       sim >=. threshold
    }
    _ -> False
  }
}

fn apply_aggregation(
  bindings: List(dict.Dict(String, Value)),
  var_name: String,
  func: types.AggFunc,
  target: String,
) -> List(dict.Dict(String, Value)) {
  let groups = list.fold(bindings, dict.new(), fn(acc, b) {
    let group_key = dict.delete(b, target) |> dict.delete(var_name)
    let group_values = dict.get(acc, group_key) |> result.unwrap([])
    let v = dict.get(b, target) |> result.unwrap(Int(-1))
    dict.insert(acc, group_key, [v, ..group_values])
  })

  dict.to_list(groups)
  |> list.map(fn(group) {
    let #(group_key, values) = group
    let agg_val = case func {
      types.Count -> Int(list.length(values))
      types.Sum -> Int(list.fold(values, 0, fn(acc, v) { 
        case v {
          Int(n) -> acc + n
          _ -> acc
        }
      }))
      types.Max -> list.fold(values, Int(-999_999_999), fn(acc, v) {
        case acc, v {
          Int(a), Int(b) -> case a > b { True -> Int(a) False -> Int(b) }
          _, _ -> acc
        }
      })
      types.Min -> list.fold(values, Int(999_999_999), fn(acc, v) {
        case acc, v {
          Int(a), Int(b) -> case a < b { True -> Int(a) False -> Int(b) }
          _, _ -> acc
        }
      })
    }
    dict.insert(group_key, var_name, agg_val)
  })
}

fn evaluate_rules(
  db_state: DbState,
  rules: List(Rule),
  as_of_tx: Option(Int),
) -> List(Datom) {
  case rules {
    [] -> []
    _ -> iterate_rules(db_state, rules, [], as_of_tx, 0)
  }
}

fn iterate_rules(
  db_state: DbState,
  rules: List(Rule),
  derived: List(Datom),
  as_of_tx: Option(Int),
  depth: Int,
) -> List(Datom) {
  case depth > 100 {
    True -> derived
    False -> {
      let world =
        db_state
      let world =
        types.DbState(
          ..world,
          eavt: list.fold(derived, world.eavt, index.insert_eavt),
          aevt: list.fold(derived, world.aevt, index.insert_aevt),
        )

      let new_derived = list.map(rules, fn(rule) {
        let bindings = execute_join_internal(world, rule.body, as_of_tx)
        list.map(bindings, fn(b) {
          let #(e_part, attr, v_part) = rule.head
          let e = case e_part {
            types.Val(Int(id)) -> id
            types.Var(name) -> case dict.get(b, name) { Ok(Int(id)) -> id _ -> -1 }
            _ -> -1
          }
          let v = case v_part {
            types.Val(val) -> val
            types.Var(name) -> dict.get(b, name) |> result.unwrap(Int(-1))
          }
          Datom(e, attr, v, 0, Assert)
        })
      }) |> list.flatten()

      let current_total = list.unique(list.append(derived, new_derived))
      let converged = list.length(current_total) == list.length(derived)
      
      case converged {
        True -> derived
        False -> iterate_rules(db_state, rules, current_total, as_of_tx, depth + 1)
      }
    }
  }
}

fn execute_join_internal(
  db_state: DbState,
  body: List(BodyClause),
  as_of_tx: Option(Int)
) -> List(dict.Dict(String, Value)) {
  let optimized_body = optimize_body_clauses(body)
  let initial_bindings = [dict.new()]

  list.fold(optimized_body, initial_bindings, fn(acc, clause) {
    case clause {
      types.Positive(c) -> {
        list.map(acc, fn(b) { match_clause(db_state, c, b, as_of_tx) }) |> list.flatten()
      }
      types.Negative(c) -> {
        list.filter(acc, fn(b) { 
          let results = match_clause(db_state, c, b, as_of_tx)
          results == []
        })
      }
      _ -> acc
    }
  })
}

fn to_option(res: Result(a, b)) -> Option(a) {
  case res {
    Ok(v) -> Some(v)
    Error(_) -> None
  }
}

fn match_clause(
  db_state: DbState,
  clause: types.Clause,
  binding: dict.Dict(String, Value),
  as_of_tx: Option(Int),
) -> List(dict.Dict(String, Value)) {
  let #(e_part, attr, v_part) = clause
  
  let e_val = case e_part {
    types.Val(v) -> Some(v)
    types.Var(name) -> dict.get(binding, name) |> to_option
  }
  let v_val = case v_part {
    types.Val(v) -> Some(v)
    types.Var(name) -> dict.get(binding, name) |> to_option
  }

  let datoms = case e_val, v_val {
    Some(Int(e)), Some(v) -> index.get_datoms_by_entity_attr_val(db_state.eavt, e, attr, v)
    Some(Int(e)), None -> index.get_datoms_by_entity_attr(db_state.eavt, e, attr)
    None, Some(v) -> index.get_datoms_by_val(db_state.aevt, attr, v)
    None, None -> index.get_all_datoms_for_attr(db_state.eavt, attr)
    _, _ -> []
  }

  let filtered = 
    filter_by_time(datoms, as_of_tx)
    |> filter_latest()

  list.filter_map(filtered, fn(d) {
    let b = binding
    let b = case e_part {
      types.Var(name) -> dict.insert(b, name, Int(d.entity))
      _ -> b
    }
    let b = case v_part {
      types.Var(name) -> dict.insert(b, name, d.value)
      _ -> b
    }
    
    // Final check that it matches constraints
    let match_e = case e_part {
      types.Val(Int(id)) -> id == d.entity
      types.Var(_) -> True
      _ -> False
    }
    let match_v = case v_part {
      types.Val(val) -> val == d.value
      types.Var(_) -> True
    }
    
    case match_e && match_v {
      True -> Ok(b)
      False -> Error(Nil)
    }
  })
}

fn filter_by_time(datoms: List(Datom), as_of_tx: Option(Int)) -> List(Datom) {
  case as_of_tx {
    Some(tx_id) -> list.filter(datoms, fn(d) { d.tx <= tx_id })
    None -> datoms
  }
}

fn filter_latest(datoms: List(Datom)) -> List(Datom) {
  list.fold(datoms, dict.new(), fn(acc, d) {
    let key = #(d.entity, d.attribute, d.value)
    case dict.get(acc, key) {
      Ok(existing_d) -> {
        let existing: Datom = existing_d
        case d.tx > existing.tx {
          True -> dict.insert(acc, key, d)
          False -> acc
        }
      }
      Error(_) -> dict.insert(acc, key, d)
    }
  }) |> dict.values() |> list.filter(fn(d) { d.operation == Assert })
}

pub fn pull(
  db_state: DbState,
  eid: fact.Eid,
  pattern: PullPattern,
) -> PullResult {
  let e = case eid {
    fact.EntityId(e) -> e
    _ -> -1
  }
  let datoms = index.filter_by_entity(db_state.eavt, e)
    |> filter_latest()

  do_pull(db_state, datoms, pattern)
}

fn do_pull(
  db_state: DbState,
  datoms: List(Datom),
  pattern: PullPattern,
) -> PullResult {
  case pattern {
    AllAttributes -> {
      list.fold(datoms, dict.new(), fn(acc, d) {
        let val = case dict.get(acc, d.attribute) {
          Ok(Single(v)) -> Many([v, d.value])
          Ok(Many(vs)) -> Many([d.value, ..vs])
          _ -> Single(d.value)
        }
        dict.insert(acc, d.attribute, val)
      })
    }
    AttributeList(attrs) -> {
      let filtered = list.filter(datoms, fn(d) { list.contains(attrs, d.attribute) })
      list.fold(filtered, dict.new(), fn(acc, d) {
        let val = case dict.get(acc, d.attribute) {
          Ok(Single(v)) -> Many([v, d.value])
          Ok(Many(vs)) -> Many([d.value, ..vs])
          _ -> Single(d.value)
        }
        dict.insert(acc, d.attribute, val)
      })
    }
    Nested(attr, nested_pattern) -> {
      let relevant = list.filter(datoms, fn(d) { d.attribute == attr })
      list.fold(relevant, dict.new(), fn(acc, d) {
        let val = 
          case d.value {
            Int(target_eid) -> Map(pull(db_state, fact.EntityId(target_eid), nested_pattern))
            _ -> Single(d.value)
          }
        dict.insert(acc, d.attribute, val)
      })
    }
    Deep(patterns) -> {
      list.fold(patterns, dict.new(), fn(acc, p) {
        dict.merge(acc, do_pull(db_state, datoms, p))
      })
    }
  }
}

@external(erlang, "gleam_erl_ffi", "coerce")
fn coerce(a: a) -> b
