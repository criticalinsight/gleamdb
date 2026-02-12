import gleam/dict
import gleam/list
import gleamdb
import gleamdb/fact.{Int, Str}
import gleamdb/shared/types.{type DbState}
import gleamdb/engine.{Wildcard, Map, Single}
import gleeunit
import gleeunit/should
import gleamdb/index

pub fn main() {
  gleeunit.main()
}

pub fn transaction_function_test() {
  let db = gleamdb.new()
  
  // 1. Register an 'inc' function
  gleamdb.register_function(db, "inc", fn(state: DbState, args) {
    case args {
      [Int(eid_int), Str(attr), Int(amount)] -> {
        let eid = fact.EntityId(eid_int)
        // Find current value using the provided state
        let datoms = index.filter_by_entity(state.eavt, eid) |> list.filter(fn(d) { d.attribute == attr })
          
        let current_val = case list.first(datoms) {
          Ok(d) -> case d.value { Int(v) -> v _ -> 0 }
          _ -> 0
        }
        
        [
          #(fact.Uid(eid), attr, Int(current_val + amount))
        ]
      }
      _ -> []
    }
  })
  
  // 2. Initial state
  let assert Ok(_) = gleamdb.transact(db, [#(fact.Uid(fact.EntityId(1)), "age", Int(30))])
  
  // 3. Trigger transaction function
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Lookup(#("db/fn", Str("inc"))), "age", fact.List([Int(1), Str("age"), Int(1)]))
  ])
  
  // 4. Verify result
  let res = gleamdb.pull(db, fact.Uid(fact.EntityId(1)), [Wildcard])
  let assert Map(m) = res
  should.equal(dict.get(m, "age"), Ok(Single(Int(31))))
}
