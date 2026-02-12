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
      [Int(eid), Str(attr), Int(amount)] -> {
        // Find current value using the provided state
        let datoms = index.filter_by_entity(state.eavt, eid)
          
        let current_val = list.fold(datoms, 0, fn(acc, d) {
          case d.attribute == attr {
            True -> case d.value { Int(v) -> v _ -> acc }
            False -> acc
          }
        })
        
        [
          #(fact.EntityId(eid), attr, Int(current_val + amount))
        ]
      }
      _ -> []
    }
  })
  
  // 2. Initial state
  let assert Ok(_) = gleamdb.transact(db, [#(fact.EntityId(1), "age", Int(30))])
  
  // 3. Trigger transaction function
  // We use the special :db/fn marker in a Lookup Ref
  // Using fact.List explicitly to avoid confusion with List type
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Lookup(#("db/fn", Str("inc"))), "call", fact.List([Int(1), Str("age"), Int(1)]))
  ])
  
  // 4. Verify result
  let res = gleamdb.pull(db, fact.EntityId(1), [Wildcard])
  let assert Map(d) = res
  should.equal(dict.get(d, "age"), Ok(Single(Int(31))))
}
