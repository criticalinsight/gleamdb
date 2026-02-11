import gleam/list
import gleamdb
import gleamdb/fact.{Str, Int}
import gleamdb/engine
import gleam/dict
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn actor_transaction_test() {
  let db = gleamdb.new()
  
  let facts = [
    #(fact.EntityId(1), "name", Str("Alice")),
    #(fact.EntityId(1), "role", Str("Admin")),
  ]

  let assert Ok(state) = gleamdb.transact(db, facts)
  should.equal(state.latest_tx, 1)

  // Query: Find name of entity 1
  let result = gleamdb.query(db, [
    gleamdb.p(#(engine.Val(Int(1)), "name", engine.Var("n")))
  ])
  
  should.equal(result, [dict.from_list([#("n", Str("Alice"))])])
}

pub fn time_travel_test() {
  let db = gleamdb.new()
  
  // T1: Initial state
  let assert Ok(_) = gleamdb.transact(db, [#(fact.EntityId(1), "v", Int(10))])
  
  // T2: Update state (Correct Datom model: retract old, assert new)
  let assert Ok(_) = gleamdb.retract(db, [#(fact.EntityId(1), "v", Int(10))])
  let assert Ok(_) = gleamdb.transact(db, [#(fact.EntityId(1), "v", Int(20))])

  // Current query (T3 actually, but latest state)
  let res_now = gleamdb.query(db, [gleamdb.p(#(engine.Val(Int(1)), "v", engine.Var("v")))])
  should.equal(res_now, [dict.from_list([#("v", Int(20))])])

  // Historical query (T1)
  let res_then = gleamdb.as_of(db, 1, [gleamdb.p(#(engine.Val(Int(1)), "v", engine.Var("v")))])
  should.equal(res_then, [dict.from_list([#("v", Int(10))])])
}

pub fn index_performance_simulation_test() {
  let db = gleamdb.new()
  // Transact multiple facts
  let assert Ok(_) = gleamdb.transact(db, [#(fact.EntityId(1), "type", Str("user")), #(fact.EntityId(2), "type", Str("bot"))])
  
  // AEVT search
  let result = gleamdb.query(db, [gleamdb.p(#(engine.Var("e"), "type", engine.Val(Str("user"))))])
  should.equal(list.length(result), 1)
  should.equal(result, [dict.from_list([#("e", Int(1))])])
}
