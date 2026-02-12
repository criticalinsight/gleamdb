import gleam/dict.{type Dict}
import gleam/list
import gleam/set.{type Set}
import gleam/result
import gleam/option.{type Option, None, Some}
import gleamdb/fact
import gleamdb/shared/types
import gleamdb/index
import gleamdb/vector

pub type Rule {
  Rule(head: types.Clause, body: List(types.BodyClause))
}

pub type PullPattern =
  List(PullItem)

pub type PullItem {
  Attr(String)
  Nested(String, PullPattern)
  Wildcard
}

pub type PullResult {
  Map(Dict(String, PullResult))
  Single(fact.Value)
  Many(List(fact.Value))
}

pub fn run(
  db_state: types.DbState,
  clauses: List(types.BodyClause),
  rules: List(Rule),
  as_of_tx: Option(Int),
) -> types.QueryResult {
  let all_derived = derive_all_facts(db_state, rules, as_of_tx)
  let initial_context = [dict.new()]
  
  list.fold(clauses, initial_context, fn(contexts, clause) {
    list.flat_map(contexts, fn(ctx) {
      solve_clause_with_derived(db_state, clause, ctx, all_derived, as_of_tx)
    })
  })
  |> list.unique()
}

fn derive_all_facts(db_state: types.DbState, rules: List(Rule), as_of_tx: Option(Int)) -> Set(fact.Datom) {
  do_derive(db_state, rules, as_of_tx, set.new())
}

fn do_derive(db_state: types.DbState, rules: List(Rule), as_of_tx: Option(Int), derived: Set(fact.Datom)) -> Set(fact.Datom) {
  let next_derived = list.fold(rules, derived, fn(acc, r) {
    let results = solve_rule_body(db_state, r.body, acc, as_of_tx)
    list.fold(results, acc, fn(inner_acc, ctx) {
      let e = resolve_part_optional(r.head.0, ctx)
      let v = resolve_part_optional(r.head.2, ctx)
      case e, v {
        Some(fact.Int(eid)), Some(val) -> {
          set.insert(inner_acc, fact.Datom(entity: eid, attribute: r.head.1, value: val, tx: 0, operation: fact.Assert))
        }
        _, _ -> inner_acc
      }
    })
  })
  
  case set.size(next_derived) == set.size(derived) {
    True -> derived
    False -> do_derive(db_state, rules, as_of_tx, next_derived)
  }
}

fn solve_rule_body(db_state: types.DbState, body: List(types.BodyClause), derived: Set(fact.Datom), as_of_tx: Option(Int)) -> List(Dict(String, fact.Value)) {
  list.fold(body, [dict.new()], fn(contexts, clause) {
    list.flat_map(contexts, fn(ctx) {
      solve_clause_with_derived(db_state, clause, ctx, derived, as_of_tx)
    })
  })
}

fn solve_clause_with_derived(
  db_state: types.DbState,
  clause: types.BodyClause,
  ctx: Dict(String, fact.Value),
  derived: Set(fact.Datom),
  as_of_tx: Option(Int),
) -> List(Dict(String, fact.Value)) {
  case clause {
    types.Positive(trip) -> solve_triple_with_derived(db_state, trip, ctx, derived, as_of_tx)
    types.Negative(trip) -> {
      case solve_triple_with_derived(db_state, trip, ctx, derived, as_of_tx) {
        [] -> [ctx]
        _ -> []
      }
    }
    types.Aggregate(var, func, target) -> solve_aggregate(ctx, var, func, target)
    types.Similarity(var, vec, threshold) -> solve_similarity(db_state, var, vec, threshold, ctx)
  }
}

fn solve_triple_with_derived(
  db_state: types.DbState,
  triple: types.Clause,
  ctx: Dict(String, fact.Value),
  derived: Set(fact.Datom),
  as_of_tx: Option(Int),
) -> List(Dict(String, fact.Value)) {
  let #(e_p, attr, v_p) = triple
  let e_val = resolve_part(e_p, ctx)
  let v_val = resolve_part(v_p, ctx)

  let base_datoms = case e_val, v_val {
    Some(fact.Int(e)), Some(v) -> index.get_datoms_by_entity_attr_val(db_state.eavt, e, attr, v)
    Some(fact.Int(e)), None -> index.get_datoms_by_entity_attr(db_state.eavt, e, attr)
    None, Some(v) -> index.get_datoms_by_val(db_state.aevt, attr, v)
    None, None -> index.get_all_datoms_for_attr(db_state.eavt, attr)
    Some(_), _ -> []
  }

  let derived_datoms = set.to_list(derived) 
    |> list.filter(fn(d) {
      let attr_match = d.attribute == attr
      let e_match = case e_val { 
        Some(fact.Int(e)) -> d.entity == e 
        _ -> True 
      }
      let v_match = case v_val { 
        Some(v) -> d.value == v 
        _ -> True 
      }
      attr_match && e_match && v_match
    })

  let all = list.append(base_datoms, derived_datoms)
  
  let active = all
    |> list.filter(fn(d: fact.Datom) {
      case as_of_tx {
        Some(tx) -> d.tx <= tx
        _ -> True
      }
    })
    |> filter_active()

  list.map(active, fn(d: fact.Datom) {
    let b = ctx
    let b = case e_p { 
      types.Var(n) -> dict.insert(b, n, fact.Int(d.entity))
      _ -> b 
    }
    let b = case v_p { 
      types.Var(n) -> dict.insert(b, n, d.value)
      _ -> b 
    }
    b
  })
}

fn filter_active(datoms: List(fact.Datom)) -> List(fact.Datom) {
  let latest = list.fold(datoms, dict.new(), fn(acc, d) {
    let key = #(d.entity, d.attribute, d.value)
    case dict.get(acc, key) {
      Ok(#(tx, _op)) if tx > d.tx -> acc
      _ -> dict.insert(acc, key, #(d.tx, d.operation))
    }
  })
  
  list.filter(datoms, fn(d: fact.Datom) {
    let key = #(d.entity, d.attribute, d.value)
    case dict.get(latest, key) {
      Ok(#(tx, op)) -> tx == d.tx && op == fact.Assert
      _ -> False
    }
  })
  |> list.unique()
}

fn resolve_part(part: types.Part, ctx: Dict(String, fact.Value)) -> Option(fact.Value) {
  case part {
    types.Var(name) -> option.from_result(dict.get(ctx, name))
    types.Val(val) -> Some(val)
  }
}

fn resolve_part_optional(part: types.Part, ctx: Dict(String, fact.Value)) -> Option(fact.Value) {
  case part {
    types.Var(name) -> option.from_result(dict.get(ctx, name))
    types.Val(val) -> Some(val)
  }
}

fn solve_aggregate(ctx: Dict(String, fact.Value), _var: String, _func: types.AggFunc, _target: String) -> List(Dict(String, fact.Value)) {
  [ctx]
}

fn solve_similarity(_db_state: types.DbState, var: String, vec: List(Float), threshold: Float, ctx: Dict(String, fact.Value)) -> List(Dict(String, fact.Value)) {
  case dict.get(ctx, var) {
    Ok(fact.Vec(v)) -> {
      let sim = vector.cosine_similarity(v, vec)
      case sim >=. threshold {
        True -> [ctx]
        False -> []
      }
    }
    _ -> []
  }
}

pub fn pull(
  db_state: types.DbState,
  eid: fact.Eid,
  pattern: PullPattern,
) -> PullResult {
  let id = case eid {
    fact.EntityId(i) -> i
    fact.Lookup(#(a, v)) -> index.get_entity_by_av(db_state.avet, a, v) |> result.unwrap(0)
  }
  
  // Datoms are reversed here because index.gleam prepends them. 
  // We want chronological order for the fold to pick up LATEST assertions.
  let datoms = index.filter_by_entity(db_state.eavt, id) 
    |> list.reverse() 
    |> filter_active()
  
  let m = list.fold(pattern, dict.new(), fn(acc, item) {
    case item {
      Wildcard -> {
        list.fold(datoms, acc, fn(inner_acc, d: fact.Datom) {
          dict.insert(inner_acc, d.attribute, Single(d.value))
        })
      }
      Attr(name) -> {
        let values = list.filter(datoms, fn(d: fact.Datom) { d.attribute == name }) |> list.map(fn(d) { d.value })
        case values {
          [v] -> dict.insert(acc, name, Single(v))
          [_, ..] -> dict.insert(acc, name, Many(values))
          [] -> acc
        }
      }
      Nested(name, sub_pattern) -> {
        let values = list.filter(datoms, fn(d: fact.Datom) { d.attribute == name }) |> list.map(fn(d) { d.value })
        case values {
          [fact.Int(sub_id)] -> {
            let res = pull(db_state, fact.EntityId(sub_id), sub_pattern)
            dict.insert(acc, name, res)
          }
          [_, ..] -> {
            let res_list = list.map(values, fn(v) {
              case v {
                fact.Int(sub_id) -> pull(db_state, fact.EntityId(sub_id), sub_pattern)
                _ -> Single(v)
              }
            })
            case res_list {
              [r, ..] -> dict.insert(acc, name, r)
              _ -> acc
            }
          }
          _ -> acc
        }
      }
    }
  })
  Map(m)
}
