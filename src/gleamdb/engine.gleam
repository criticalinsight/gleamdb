import gleam/list
import gleam/int
import gleam/result
import gleam/dict
import gleam/string
import gleam/order.{type Order}
import gleam/option.{type Option, None, Some}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/io

@external(erlang, "gleamdb_telemetry_ffi", "system_time")
pub fn system_time() -> Int

import gleamdb/fact.{type Value, type Datom, Int, Assert, Datom}
import gleamdb/transactor.{type DbState}
import gleamdb/index

pub type QueryPart {
  Var(String)
  Val(Value)
}

pub type Clause = #(QueryPart, String, QueryPart)

pub type AggFunc {
  Count
  Sum
  Min
  Max
}

pub type BodyClause {
  Positive(Clause)
  Negative(Clause)
  Aggregate(variable: String, func: AggFunc, target: String)
}

pub type Rule {
  Rule(
    name: String,
    head: Clause,
    body: List(BodyClause),
  )
}

pub type QueryResult = List(dict.Dict(String, Value))

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
  |> actor.on_message(fn(_state, msg) {
    case msg {
      Execute(reply_to) -> {
        let result = execute_query(db_state, clauses, [], as_of_tx)
        process.send(reply_to, result)
        actor.continue(Nil)
      }
      ExecuteWithRules(query_rules, reply_to) -> {
        let result = execute_query(db_state, clauses, query_rules, as_of_tx)
        process.send(reply_to, result)
        actor.continue(Nil)
      }
      GetStatus(reply_to) -> {
        process.send(reply_to, "Processing analytical query...")
        actor.continue(Nil)
      }
    }
  })
  |> actor.start()
  |> result.map(fn(started) { started.data })
}


fn execute_query(
  db_state: DbState,
  clauses: List(BodyClause),
  rules: List(Rule),
  as_of_tx: Option(Int)
) -> QueryResult {
  let start = system_time()
  let result = do_execute_query(db_state, clauses, rules, as_of_tx)
  let end = system_time()
  let duration = end - start
  
  io.println("[GleamDB] Query: " <> int.to_string(duration) <> "ms (" <> int.to_string(list.length(result)) <> " results)")
  result
}

fn do_execute_query(
  db_state: DbState,
  clauses: List(BodyClause),
  rules: List(Rule),
  as_of_tx: Option(Int)
) -> QueryResult {
  // Check for stratification if rules are present
  let is_stratified = check_stratification(rules)
  case is_stratified {
    False -> [] // Should probably return an error, but returning empty for now
    True -> {
      let derived_datoms = evaluate_rules(db_state, rules, as_of_tx)
      
      let world = transactor.DbState(
        ..db_state,
        eavt: list.fold(derived_datoms, db_state.eavt, index.insert_eavt),
        aevt: list.fold(derived_datoms, db_state.aevt, index.insert_aevt)
      )

      let optimized_clauses = optimize_body_clauses(clauses)
      let initial_bindings = [dict.new()]
      let final_bindings = list.fold(optimized_clauses, initial_bindings, fn(bindings, body_clause) {
        case body_clause {
          Positive(clause) -> {
            list.flat_map(bindings, fn(binding) {
              match_clause(world, clause, binding, as_of_tx)
            })
          }
          Negative(clause) -> {
            list.filter(bindings, fn(binding) {
              list.is_empty(match_clause(world, clause, binding, as_of_tx))
            })
          }
          Aggregate(var, func, target) -> {
            apply_aggregation(bindings, var, func, target)
          }
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
  let edges = list.flat_map(rules, fn(r) {
    let #(_, head_attr, _) = r.head
    list.filter_map(r.body, fn(bc) {
      case bc {
        Positive(#(_, attr, _)) -> Ok(#(head_attr, attr, False))
        Negative(#(_, attr, _)) -> Ok(#(head_attr, attr, True))
        _ -> Error(Nil)
      }
    })
  })

  // Check for negative cycles
  !list.any(rules, fn(r) {
    let #(_, head_attr, _) = r.head
    has_negative_path(head_attr, head_attr, edges, [], False)
  })
}

fn has_negative_path(
  start: String,
  target: String,
  edges: List(#(String, String, Bool)),
  visited: List(String),
  has_neg: Bool
) -> Bool {
  case start == target && { has_neg && !list.is_empty(visited) } {
    True -> True
    False -> {
      let neighbors = list.filter(edges, fn(e) { e.0 == start })
      list.any(neighbors, fn(n) {
        let #(_, next, is_neg) = n
        case list.contains(visited, next) {
          True -> next == target && { has_neg || is_neg }
          False -> has_negative_path(next, target, edges, [next, ..visited], has_neg || is_neg)
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
      False -> case score_a < score_b {
        True -> order.Gt
        False -> order.Eq
      }
    }
  })
}

fn get_body_clause_score(clause: BodyClause) -> Int {
  case clause {
    Positive(#(e, _, v)) -> {
      let e_score = case e { Val(_) -> 1 Var(_) -> 0 }
      let v_score = case v { Val(_) -> 1 Var(_) -> 0 }
      10 + e_score + v_score
    }
    Negative(_) -> 5
    Aggregate(_, _, _) -> 0
  }
}

fn apply_aggregation(
  bindings: List(dict.Dict(String, Value)),
  var_name: String,
  func: AggFunc,
  target: String
) -> List(dict.Dict(String, Value)) {
  let groups = list.fold(bindings, dict.new(), fn(acc, b) {
    let group_key = dict.delete(b, target) |> dict.delete(var_name)
    let group_values = dict.get(acc, group_key) |> result.unwrap([])
    let val = dict.get(b, target)
    case val {
      Ok(v) -> dict.insert(acc, group_key, [v, ..group_values])
      Error(_) -> acc
    }
  })

  dict.to_list(groups)
  |> list.map(fn(pair) {
    let #(group_key, values) = pair
    let agg_val = case func {
      Count -> Int(list.length(values))
      Sum -> Int(list.fold(values, 0, fn(acc, v) {
        case v { Int(i) -> acc + i _ -> acc }
      }))
      Min -> Int(list.fold(values, 1_000_000_000, fn(acc, v) {
        case v { Int(i) -> case i < acc { True -> i False -> acc } _ -> acc }
      }))
      Max -> Int(list.fold(values, -1_000_000_000, fn(acc, v) {
        case v { Int(i) -> case i > acc { True -> i False -> acc } _ -> acc }
      }))
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
      let world = transactor.DbState(
        ..db_state,
        eavt: list.fold(derived, db_state.eavt, index.insert_eavt),
        aevt: list.fold(derived, db_state.aevt, index.insert_aevt)
      )

      let newly_derived = list.flat_map(rules, fn(r) {
        let bindings = execute_join_internal(world, r.body, as_of_tx)
        list.map(bindings, fn(b) {
          let #(h_e, h_a, h_v) = r.head
          let e = case h_e {
            Val(Int(i)) -> i
            Var(name) -> {
              case dict.get(b, name) {
                Ok(Int(i)) -> i
                _ -> 0
              }
            }
            _ -> 0
          }
          let v = case h_v {
            Val(val) -> val
            Var(name) -> {
              case dict.get(b, name) {
                Ok(val) -> val
                _ -> Int(0)
              }
            }
          }
          Datom(e, h_a, v, db_state.latest_tx + 1, Assert)
        })
      })

      let current_total = list.append(derived, newly_derived) |> list.unique()
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
  list.fold(optimized_body, initial_bindings, fn(bindings, body_clause) {
    case body_clause {
      Positive(clause) -> {
        list.flat_map(bindings, fn(binding) {
          match_clause(db_state, clause, binding, as_of_tx)
        })
      }
      Negative(clause) -> {
        list.filter(bindings, fn(binding) {
          list.is_empty(match_clause(db_state, clause, binding, as_of_tx))
        })
      }
      Aggregate(var, func, target) -> {
        apply_aggregation(bindings, var, func, target)
      }
    }
  })
}

fn string_compare(a: String, b: String) -> Order {
  string.compare(a, b)
}

fn get_body_vars(clause: BodyClause) -> List(String) {
  case clause {
    Positive(c) | Negative(c) -> get_vars(c)
    Aggregate(v, _, t) -> [v, t]
  }
}

fn get_vars(clause: Clause) -> List(String) {
  let #(e, _, v) = clause
  let vars = []
  let vars = case e {
    Var(name) -> [name, ..vars]
    _ -> vars
  }
  case v {
    Var(name) -> [name, ..vars]
    _ -> vars
  }
}

fn to_option(res: Result(a, b)) -> Option(a) {
  case res {
    Ok(v) -> Some(v)
    Error(_) -> None
  }
}

fn match_clause(
  db_state: DbState,
  clause: Clause,
  binding: dict.Dict(String, Value),
  as_of_tx: Option(Int),
) -> List(dict.Dict(String, Value)) {
  let #(e_part, attr, v_part) = clause
  
  let e_val = case e_part {
    Val(v) -> Some(v)
    Var(name) -> dict.get(binding, name) |> to_option
  }
  let v_val = case v_part {
    Val(v) -> Some(v)
    Var(name) -> dict.get(binding, name) |> to_option
  }

  let datoms = case e_val, v_val {
    Some(Int(ent_int)), _ -> index.filter_by_entity(db_state.eavt, ent_int)
    _, _ -> index.filter_by_attribute(db_state.aevt, attr)
  }

  datoms
  |> filter_by_time(as_of_tx)
  |> filter_latest()
  |> list.filter_map(fn(d) {
    let e_match = case e_val {
      Some(v) -> v == Int(d.entity)
      None -> True
    }
    let v_match = case v_val {
      Some(v) -> v == d.value
      None -> True
    }
    let a_match = d.attribute == attr

    case e_match && v_match && a_match {
      True -> {
        let b = binding
        let b = case e_part {
          Var(name) -> dict.insert(b, name, Int(d.entity))
          _ -> b
        }
        let b = case v_part {
          Var(name) -> dict.insert(b, name, d.value)
          _ -> b
        }
        Ok(b)
      }
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
  })
  |> dict.values()
  |> list.filter(fn(d) { d.operation == Assert })
}

pub fn pull(
  db_state: DbState,
  eid: Int,
  pattern: PullPattern,
) -> PullResult {
  let datoms = index.filter_by_entity(db_state.eavt, eid)
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
      let pull_val = case relevant {
        [] -> Many([])
        [d] -> {
          case d.value {
            Int(target_eid) -> Map(pull(db_state, target_eid, nested_pattern))
            _ -> Single(d.value)
          }
        }
        ds -> {
          let results = list.map(ds, fn(d) {
            case d.value {
              Int(target_eid) -> Ok(pull(db_state, target_eid, nested_pattern))
              _ -> Error(Nil)
            }
          })
          let maps = list.filter_map(results, fn(r) { r })
          case maps {
            [] -> Many(list.map(ds, fn(d) { d.value }))
            ms -> Maps(ms)
          }
        }
      }
      dict.new() |> dict.insert(attr, pull_val)
    }
    Deep(patterns) -> {
      list.fold(patterns, dict.new(), fn(acc, p) {
        dict.merge(acc, do_pull(db_state, datoms, p))
      })
    }
  }
}

pub fn run(
  db_state: DbState,
  clauses: List(BodyClause),
  rules: List(Rule),
  as_of_tx: Option(Int),
) -> QueryResult {
  let assert Ok(query_pid) = start_query(db_state, clauses, as_of_tx)
  process.call(query_pid, 5000, fn(reply_to) {
     case rules {
       [] -> Execute(reply_to)
       _ -> ExecuteWithRules(rules, reply_to)
     }
  })
}
