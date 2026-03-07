import aarondb
import aarondb/fact.{Int, Str}
import aarondb/shared/types
import gleam/dict
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn join_test() {
  let db = aarondb.new()

  // Alice is 30, and Alice lives in Nairobi
  let assert Ok(_) =
    aarondb.transact(db, [
      #(fact.Uid(fact.EntityId(1)), "name", Str("Alice")),
      #(fact.Uid(fact.EntityId(1)), "age", Int(30)),
      #(fact.Uid(fact.EntityId(1)), "location", Str("Nairobi")),
    ])

  // Query: Find entity e and age a where e has name "Alice" AND e has age a
  let result =
    aarondb.query(db, [
      aarondb.p(#(types.Var("e"), "name", types.Val(Str("Alice")))),
      aarondb.p(#(types.Var("e"), "age", types.Var("a"))),
    ])

  // all_vars: ["a", "e"] (sorted alphabetic)
  // Our get_vars returns values in that order.
  should.equal(list.length(result.rows), 1)
  should.equal(result.rows, [
    dict.from_list([#("a", Int(30)), #("e", fact.Ref(fact.EntityId(1)))]),
  ])
}

pub fn retraction_test() {
  let db = aarondb.new()

  let assert Ok(_) =
    aarondb.transact(db, [
      #(fact.Uid(fact.EntityId(1)), "status", Str("active")),
    ])

  // Verify it exists
  let res1 =
    aarondb.query(db, [
      aarondb.p(#(types.Val(Int(1)), "status", types.Var("s"))),
    ])
  should.equal(res1.rows, [dict.from_list([#("s", Str("active"))])])

  // Retract it
  let assert Ok(_) =
    aarondb.retract(db, [#(fact.Uid(fact.EntityId(1)), "status", Str("active"))])

  // Verify it's gone
  let res2 =
    aarondb.query(db, [
      aarondb.p(#(types.Val(Int(1)), "status", types.Var("s"))),
    ])
  should.equal(res2.rows, [])

  // Verify it STILL exists in the past (Time Travel)
  let res_past =
    aarondb.as_of(db, 1, [
      aarondb.p(#(types.Val(Int(1)), "status", types.Var("s"))),
    ])
  should.equal(res_past.rows, [dict.from_list([#("s", Str("active"))])])
}
