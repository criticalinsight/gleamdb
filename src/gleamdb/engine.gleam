import gleam/dict.{type Dict}
import gleam/list
import gleam/set.{type Set}
import gleam/result
import gleam/option.{type Option, None, Some}
import gleam/int
import gleam/float
import gleam/string
import gleam/order
import gleamdb/fact
import gleamdb/shared/types
import gleamdb/index
import gleamdb/index/ets as ets_index
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

fn do_derive(
  db_state: types.DbState,
  rules: List(Rule),
  as_of_tx: Option(Int),
  derived: Set(fact.Datom),
) -> Set(fact.Datom) {
  let initial_new = derived
  do_derive_recursive(db_state, rules, as_of_tx, derived, initial_new)
}

fn do_derive_recursive(
  db_state: types.DbState,
  rules: List(Rule),
  as_of_tx: Option(Int),
  all_derived: Set(fact.Datom),
  last_new_derived: Set(fact.Datom),
) -> Set(fact.Datom) {
  case set.size(last_new_derived) == 0 && set.size(all_derived) > 0 {
    True -> all_derived
    False -> {
      let next_new = list.fold(rules, set.new(), fn(acc, r) {
        // Semi-Naive Evaluation:
        // For each rule, we only want results that involve at least one fact 
        // from 'last_new_derived'. This avoids re-discovering the same facts.
        let results = solve_rule_body_semi_naive(db_state, r.body, all_derived, last_new_derived, as_of_tx)
        
        list.fold(results, acc, fn(inner_acc, ctx) {
          let e = resolve_part_optional(r.head.0, ctx)
          let v = resolve_part_optional(r.head.2, ctx)
          case e, v {
            Some(fact.Ref(fact.EntityId(eid_val))), Some(val) -> {
              let d = fact.Datom(entity: fact.EntityId(eid_val), attribute: r.head.1, value: val, tx: 0, operation: fact.Assert)
              case set.contains(all_derived, d) {
                True -> inner_acc
                False -> set.insert(inner_acc, d)
              }
            }
            Some(fact.Int(eid_val)), Some(val) -> {
              let d = fact.Datom(entity: fact.EntityId(eid_val), attribute: r.head.1, value: val, tx: 0, operation: fact.Assert)
              case set.contains(all_derived, d) {
                True -> inner_acc
                False -> set.insert(inner_acc, d)
              }
            }
            _, _ -> inner_acc
          }
        })
      })

      case set.size(next_new) == 0 {
        True -> all_derived
        False -> {
          let next_all = set.union(all_derived, next_new)
          do_derive_recursive(db_state, rules, as_of_tx, next_all, next_new)
        }
      }
    }
  }
}

fn solve_rule_body_semi_naive(
  db_state: types.DbState,
  body: List(types.BodyClause),
  all_derived: Set(fact.Datom),
  delta: Set(fact.Datom),
  as_of_tx: Option(Int),
) -> List(Dict(String, fact.Value)) {
  // Semi-Naive correctly: SUM_{i=1 to n} (P1 & ... & delta(Pi) & ... & Pn)
  // We iterate through each clause Pi, treating it as the "pinned" delta clause.
  
  let results = list.index_map(body, fn(clause_i, i) {
    // For each clause Pi at index i:
    // Solve clauses P1...Pi-1 using 'all_derived'
    // Solve clause Pi using ONLY 'delta'
    // Solve clauses Pi+1...Pn using 'all_derived'
    
    let prefix = list.take(body, i)
    let suffix = list.drop(body, i + 1)
    
    let ctxs = [dict.new()]
    
    // 1. Solve prefix
    let ctxs = list.fold(prefix, ctxs, fn(acc, c) {
      list.flat_map(acc, fn(ctx) { solve_clause_with_derived(db_state, c, ctx, all_derived, as_of_tx) })
    })
    
    // 2. Solve delta(Pi) - ONLY use the new facts
    let ctxs = list.flat_map(ctxs, fn(ctx) {
      solve_clause_with_derived(db_state, clause_i, ctx, delta, as_of_tx)
    })
    
    // 3. Solve suffix
    let ctxs = list.fold(suffix, ctxs, fn(acc, c) {
      list.flat_map(acc, fn(ctx) { solve_clause_with_derived(db_state, c, ctx, all_derived, as_of_tx) })
    })
    
    ctxs
  })
  
  list.flatten(results) |> list.unique()
}

fn solve_clause(
  db_state: types.DbState,
  clause: types.BodyClause,
  ctx: Dict(String, fact.Value),
  rules: List(Rule),
  as_of_tx: Option(Int),
) -> List(Dict(String, fact.Value)) {
  case clause {
    types.Positive(c) -> solve_positive(db_state, c, ctx)
    types.Negative(c) -> solve_negative(db_state, c, ctx)
    types.Aggregate(var, func, target, filter_clauses) -> {
      solve_aggregate(ctx, var, func, target, db_state, filter_clauses, rules, as_of_tx)
    }
    types.Similarity(variable: var, vector: vec, threshold: threshold) -> solve_similarity(db_state, var, vec, threshold, ctx)
    types.Filter(f) -> {
      case f(ctx) {
        True -> [ctx]
        False -> []
      }
    }
    types.Bind(var, f) -> {
      let val = f(ctx)
      [dict.insert(ctx, var, val)]
    }
  }
}

fn solve_positive(
  db_state: types.DbState,
  triple: types.Clause,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  let #(e_p, attr, v_p) = triple
  let e_val = resolve_part(e_p, ctx)
  let v_val = resolve_part(v_p, ctx)

  let base_datoms = case e_val, v_val {
    Some(fact.Ref(fact.EntityId(e))), Some(v) -> index.get_datoms_by_entity_attr_val(db_state.eavt, fact.EntityId(e), attr, v)
    Some(fact.Ref(fact.EntityId(e))), None -> index.get_datoms_by_entity_attr(db_state.eavt, fact.EntityId(e), attr)
    Some(fact.Int(e)), Some(v) -> index.get_datoms_by_entity_attr_val(db_state.eavt, fact.EntityId(e), attr, v)
    Some(fact.Int(e)), None -> index.get_datoms_by_entity_attr(db_state.eavt, fact.EntityId(e), attr)
    None, Some(v) -> index.get_datoms_by_val(db_state.aevt, attr, v)
    None, None -> index.get_all_datoms_for_attr(db_state.eavt, attr)
    Some(_), _ -> []
  }

  let active = base_datoms |> filter_active()

  list.map(active, fn(d: fact.Datom) {
    let b = ctx
    let b = case e_p { 
      types.Var(n) -> {
        let id_val = fact.Ref(d.entity)
        dict.insert(b, n, id_val)
      }
      _ -> b 
    }
    let b = case v_p { 
      types.Var(n) -> dict.insert(b, n, d.value)
      _ -> b 
    }
    b
  })
}

fn solve_negative(
  db_state: types.DbState,
  triple: types.Clause,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  case solve_positive(db_state, triple, ctx) {
    [] -> [ctx]
    _ -> []
  }
}

fn solve_clause_with_derived(
  db_state: types.DbState,
  clause: types.BodyClause,
  ctx: Dict(String, fact.Value),
  derived: Set(fact.Datom),
  as_of_tx: Option(Int),
) -> List(Dict(String, fact.Value)) {
  case clause {
    types.Positive(trip) -> {
      let #(e_p, attr, v_p) = trip
      let e_val = resolve_part(e_p, ctx)
      let v_val = resolve_part(v_p, ctx)

      let base_datoms = case db_state.ets_name {
        Some(name) -> {
          case e_val, v_val {
            Some(fact.Ref(fact.EntityId(e))), Some(v) -> {
              ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
              |> list.filter(fn(d: fact.Datom) { d.attribute == attr && d.value == v })
            }
            Some(fact.Ref(fact.EntityId(e))), None -> {
              ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
              |> list.filter(fn(d: fact.Datom) { d.attribute == attr })
            }
            Some(fact.Int(e)), Some(v) -> {
              ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
              |> list.filter(fn(d: fact.Datom) { d.attribute == attr && d.value == v })
            }
            Some(fact.Int(e)), None -> {
              ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
              |> list.filter(fn(d: fact.Datom) { d.attribute == attr })
            }
            None, Some(v) -> {
              ets_index.lookup_datoms(name <> "_aevt", attr)
              |> list.filter(fn(d: fact.Datom) { d.value == v })
            }
            None, None -> {
              ets_index.lookup_datoms(name <> "_aevt", attr)
            }
            Some(_), _ -> []
          }
        }
        None -> {
          case e_val, v_val {
            Some(fact.Ref(fact.EntityId(e))), Some(v) -> index.get_datoms_by_entity_attr_val(db_state.eavt, fact.EntityId(e), attr, v)
            Some(fact.Ref(fact.EntityId(e))), None -> index.get_datoms_by_entity_attr(db_state.eavt, fact.EntityId(e), attr)
            Some(fact.Int(e)), Some(v) -> index.get_datoms_by_entity_attr_val(db_state.eavt, fact.EntityId(e), attr, v)
            Some(fact.Int(e)), None -> index.get_datoms_by_entity_attr(db_state.eavt, fact.EntityId(e), attr)
            None, Some(v) -> index.get_datoms_by_val(db_state.aevt, attr, v)
            None, None -> index.get_all_datoms_for_attr(db_state.eavt, attr)
            Some(_), _ -> []
          }
        }
      }

      let derived_datoms = set.to_list(derived) 
        |> list.filter(fn(d) {
          let attr_match = d.attribute == attr
          let e_match = case e_val { 
            Some(fact.Ref(fact.EntityId(e))) -> {
              let fact.EntityId(eid_int) = d.entity
              eid_int == e
            }
            Some(fact.Int(e)) -> {
              let fact.EntityId(eid_int) = d.entity
              eid_int == e
            }
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
          types.Var(n) -> {
            let id_val = fact.Ref(d.entity)
            dict.insert(b, n, id_val)
          }
          _ -> b 
        }
        let b = case v_p { 
          types.Var(n) -> dict.insert(b, n, d.value)
          _ -> b 
        }
        b
      })
    }
    types.Negative(trip) -> {
      case solve_triple_with_derived(db_state, trip, ctx, derived, as_of_tx) {
        [] -> [ctx]
        _ -> []
      }
    }
    types.Aggregate(var, func, target, filter_clauses) -> {
      solve_aggregate(ctx, var, func, target, db_state, filter_clauses, [], as_of_tx)
    }
    types.Similarity(variable: var, vector: vec, threshold: threshold) -> solve_similarity(db_state, var, vec, threshold, ctx)
    types.Filter(f) -> {
      case f(ctx) {
        True -> [ctx]
        False -> []
      }
    }
    types.Bind(var, f) -> {
      let val = f(ctx)
      [dict.insert(ctx, var, val)]
    }
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
    Some(fact.Ref(fact.EntityId(e))), Some(v) -> index.get_datoms_by_entity_attr_val(db_state.eavt, fact.EntityId(e), attr, v)
    Some(fact.Ref(fact.EntityId(e))), None -> index.get_datoms_by_entity_attr(db_state.eavt, fact.EntityId(e), attr)
    Some(fact.Int(e)), Some(v) -> index.get_datoms_by_entity_attr_val(db_state.eavt, fact.EntityId(e), attr, v)
    Some(fact.Int(e)), None -> index.get_datoms_by_entity_attr(db_state.eavt, fact.EntityId(e), attr)
    None, Some(v) -> index.get_datoms_by_val(db_state.aevt, attr, v)
    None, None -> index.get_all_datoms_for_attr(db_state.eavt, attr)
    Some(_), _ -> []
  }

  let derived_datoms = set.to_list(derived) 
    |> list.filter(fn(d) {
      let attr_match = d.attribute == attr
      let e_match = case e_val { 
        Some(fact.Ref(fact.EntityId(e))) -> {
          let fact.EntityId(eid_int) = d.entity
          eid_int == e
        }
        Some(fact.Int(e)) -> {
          let fact.EntityId(eid_int) = d.entity
          eid_int == e
        }
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
      types.Var(n) -> {
        let id_val = fact.Ref(d.entity)
        dict.insert(b, n, id_val)
      }
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

fn do_solve_clauses(
  db_state: types.DbState,
  clauses: List(types.BodyClause),
  rules: List(Rule),
  as_of_tx: Option(Int),
  contexts: List(Dict(String, fact.Value)),
) -> List(Dict(String, fact.Value)) {
  case clauses {
    [] -> contexts
    [first, ..rest] -> {
      let next_contexts =
        list.flat_map(contexts, fn(ctx) {
          solve_clause(db_state, first, ctx, rules, as_of_tx)
        })
      do_solve_clauses(db_state, rest, rules, as_of_tx, next_contexts)
    }
  }
}

fn solve_aggregate(
  ctx: Dict(String, fact.Value),
  var: String,
  func: types.AggFunc,
  target_var: String,
  db_state: types.DbState,
  clauses: List(types.BodyClause),
  rules: List(Rule),
  as_of_tx: Option(Int),
) -> List(Dict(String, fact.Value)) {
  // 1. Resolve sub-results
  let sub_results = case clauses {
    [] -> [ctx]
    _ -> do_solve_clauses(db_state, clauses, rules, as_of_tx, [ctx])
  }
  
  let target_values = list.filter_map(sub_results, fn(res) {
    dict.get(res, target_var)
  })
  
  case target_values {
    [] -> [ctx]
    _ -> {
      let result_val = case func {
        types.Count -> fact.Int(list.length(target_values))
        types.Sum -> {
          let sum = list.fold(target_values, 0.0, fn(acc, v) {
            case v {
              fact.Int(i) -> acc +. int.to_float(i)
              fact.Float(v) -> acc +. v
              _ -> acc
            }
          })
          fact.Float(sum)
        }
        types.Min -> {
          let sorted = list.sort(target_values, compare_values)
          list.first(sorted) |> result.unwrap(fact.Int(0))
        }
        types.Max -> {
          let sorted = list.sort(target_values, compare_values) |> list.reverse
          list.first(sorted) |> result.unwrap(fact.Int(0))
        }
        types.Avg -> {
          let #(sum, count) = list.fold(target_values, #(0.0, 0), fn(acc, v) {
            case v {
              fact.Int(i) -> #(acc.0 +. int.to_float(i), acc.1 + 1)
              fact.Float(v) -> #(acc.0 +. v, acc.1 + 1)
              _ -> acc
            }
          })
          case count {
            0 -> fact.Float(0.0)
            _ -> fact.Float(sum /. int.to_float(count))
          }
        }
        types.Median -> {
          let sorted = list.sort(target_values, compare_values)
          let len = list.length(sorted)
          case len {
            0 -> fact.Int(0)
            _ if len % 2 == 1 -> {
              let idx = len / 2
              list.drop(sorted, idx) |> list.first() |> result.unwrap(fact.Int(0))
            }
            _ -> {
              let idx2 = len / 2
              let idx1 = idx2 - 1
              let v1 = list.drop(sorted, idx1) |> list.first() |> result.unwrap(fact.Int(0))
              let v2 = list.drop(sorted, idx2) |> list.first() |> result.unwrap(fact.Int(0))
              case v1, v2 {
                fact.Int(i1), fact.Int(i2) -> fact.Float(int.to_float(i1 + i2) /. 2.0)
                fact.Float(f1), fact.Float(f2) -> fact.Float({f1 +. f2} /. 2.0)
                fact.Int(i), fact.Float(f) -> fact.Float({int.to_float(i) +. f} /. 2.0)
                fact.Float(f), fact.Int(i) -> fact.Float({f +. int.to_float(i)} /. 2.0)
                _, _ -> v1
              }
            }
          }
        }
      }
      [dict.insert(ctx, var, result_val)]
    }
  }
}

fn compare_values(a: fact.Value, b: fact.Value) -> order.Order {
  case a, b {
    fact.Int(i1), fact.Int(i2) -> int.compare(i1, i2)
    fact.Float(f1), fact.Float(f2) -> float.compare(f1, f2)
    fact.Str(s1), fact.Str(s2) -> string.compare(s1, s2)
    fact.Int(i), fact.Float(f) -> float.compare(int.to_float(i), f)
    fact.Float(f), fact.Int(i) -> float.compare(f, int.to_float(i))
    _, _ -> order.Eq
  }
}

fn solve_similarity(
  db_state: types.DbState,
  var: String,
  vec: List(Float),
  threshold: Float,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  case dict.get(ctx, var) {
    Ok(fact.Vec(v)) -> {
      let dist = vector.cosine_similarity(vec, v)
      case dist >=. threshold {
        True -> [ctx]
        False -> []
      }
    }
    // If bound but NOT a vector, it can't match.
    Ok(_) -> []
    // Similarity as a SOURCE clause (Unbound variable)
    Error(Nil) -> {
      let matching_datoms = index.get_all_datoms_avet(db_state.avet)
        |> list.filter_map(fn(d: fact.Datom) {
          case d.value {
            fact.Vec(v) -> {
              let dist = vector.cosine_similarity(vec, v)
              case dist >=. threshold {
                True -> Ok(d)
                False -> Error(Nil)
              }
            }
            _ -> Error(Nil)
          }
        })
      
      list.map(matching_datoms, fn(d: fact.Datom) {
        dict.insert(ctx, var, d.value)
      })
    }
  }
}

pub fn entity_history(db_state: types.DbState, eid: fact.EntityId) -> List(fact.Datom) {
  dict.get(db_state.eavt, eid)
  |> result.unwrap([])
  |> list.sort(fn(a, b) {
    case int.compare(a.tx, b.tx) {
      order.Eq -> {
        case a.operation, b.operation {
          fact.Retract, fact.Assert -> order.Lt
          fact.Assert, fact.Retract -> order.Gt
          _, _ -> order.Eq
        }
      }
      other -> other
    }
  })
}

pub fn pull(
  db_state: types.DbState,
  eid: fact.Eid,
  pattern: PullPattern,
) -> PullResult {
  let id = case eid {
    fact.Uid(fact.EntityId(i)) -> fact.EntityId(i)
    fact.Lookup(#(a, v)) -> {
       index.get_entity_by_av(db_state.avet, a, v) |> result.unwrap(fact.EntityId(0))
    }
  }
  
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
          [fact.Ref(eid)] -> {
            let res = pull(db_state, fact.Uid(eid), sub_pattern)
            dict.insert(acc, name, res)
          }
          [fact.Int(sub_id)] -> {
            let res = pull(db_state, fact.Uid(fact.EntityId(sub_id)), sub_pattern)
            dict.insert(acc, name, res)
          }
          [_, ..] -> {
            let res_list = list.map(values, fn(v) {
              case v {
                fact.Ref(eid) -> pull(db_state, fact.Uid(eid), sub_pattern)
                fact.Int(sub_id) -> pull(db_state, fact.Uid(fact.EntityId(sub_id)), sub_pattern)
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
