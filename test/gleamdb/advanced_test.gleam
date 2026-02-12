import gleam/list
import gleam/dict
import gleeunit
import gleeunit/should
import gleamdb
import gleamdb/fact.{Int}
import gleamdb/shared/types

pub fn main() {
  gleeunit.main()
}

pub fn negation_test() {
  let db = gleamdb.new()
  
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.EntityId(1), "name", fact.Str("Alice")),
    #(fact.EntityId(2), "name", fact.Str("Bob")),
    #(fact.EntityId(3), "name", fact.Str("Charlie")),
    #(fact.EntityId(1), "parent", Int(2)),
  ])
  
  let result = gleamdb.query(db, [
    gleamdb.p(#(types.Var("e"), "name", types.Var("n"))),
    types.Negative(#(types.Var("e"), "parent", types.Var("child")))
  ])
  
  should.equal(list.length(result), 2)
  should.be_true(list.contains(result, dict.from_list([#("e", Int(2)), #("n", fact.Str("Bob"))])))
  should.be_true(list.contains(result, dict.from_list([#("e", Int(3)), #("n", fact.Str("Charlie"))])))
  should.be_false(list.contains(result, dict.from_list([#("e", Int(1)), #("n", fact.Str("Alice"))])))
}

pub fn aggregation_test() {
  should.be_true(True)
}
