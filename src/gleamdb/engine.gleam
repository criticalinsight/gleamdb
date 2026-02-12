import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleamdb/fact.{type Datom, type Value, Int, Datom}
import gleamdb/shared/types.{
  type BodyClause, type DbState, type QueryResult,
}
import gleamdb/index

pub type Rule {
  Rule(head: types.Clause, body: List(BodyClause))
}

pub type PullItem {
  Wildcard
  Attr(String)
  Nested(String, List(PullItem))
}

pub type PullPattern = List(PullItem)

pub type PullResult {
  Map(Dict(String, PullResult))
  Single(Value)
  Many(List(PullResult))
}

pub fn query(db_state: DbState, clauses: List(BodyClause)) -> QueryResult {
  execute_join(db_state, clauses, None)
}

pub fn run(
  db_state: DbState,
  clauses: List(BodyClause),
  _rules: List(Rule), // Rules simplified for now
  as_of_tx: Option(Int),
) -> QueryResult {
  execute_join(db_state, clauses, as_of_tx)
}

pub fn execute_join(
  db_state: DbState,
  body: List(BodyClause),
  as_of_tx: Option(Int),
) -> QueryResult {
  let bindings = execute_join_internal(db_state, body, as_of_tx)
  bindings
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

  case pattern {
    [Wildcard] -> {
      list.fold(datoms, dict.new(), fn(acc, d) {
        dict.insert(acc, d.attribute, Single(d.value))
      })
      |> Map
    }
    _ -> {
      list.fold(pattern, dict.new(), fn(acc, item) {
        case item {
          Attr(attr) -> {
            let matches = list.filter(datoms, fn(d) { d.attribute == attr })
            case matches {
              [] -> acc
              [d, ..] -> dict.insert(acc, attr, Single(d.value))
            }
          }
          Nested(attr, nested_pattern) -> {
            let relevant = list.filter(datoms, fn(d) { d.attribute == attr })
            list.fold(relevant, acc, fn(inner_acc, d: Datom) {
              case d.value {
                Int(target_eid) ->
                  case pull(db_state, fact.EntityId(target_eid), nested_pattern) {
                    Map(m) -> dict.insert(inner_acc, d.attribute, Map(m))
                    _ -> dict.insert(inner_acc, d.attribute, Single(d.value))
                  }
                _ -> dict.insert(inner_acc, d.attribute, Single(d.value))
              }
            })
          }
          _ -> acc
        }
      })
      |> Map
    }
  }
}

fn execute_join_internal(
  db_state: DbState,
  body: List(BodyClause),
  as_of_tx: Option(Int)
) -> List(dict.Dict(String, Value)) {
  let optimized_body = body
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

fn match_clause(
  db_state: DbState,
  clause: types.Clause,
  binding: dict.Dict(String, Value),
  as_of_tx: Option(Int),
) -> List(dict.Dict(String, Value)) {
  let #(e_part, attr, v_part) = clause
  
  let e_val = case e_part {
    types.Val(v) -> Some(v)
    types.Var(name) -> dict.get(binding, name) |> option.from_result
  }
  let v_val = case v_part {
    types.Val(v) -> Some(v)
    types.Var(name) -> dict.get(binding, name) |> option.from_result
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
    Some(tx) -> list.filter(datoms, fn(d) { d.tx <= tx })
    None -> datoms
  }
}

fn filter_latest(datoms: List(Datom)) -> List(Datom) {
  datoms
}
