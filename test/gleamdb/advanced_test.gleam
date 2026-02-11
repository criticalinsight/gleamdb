import gleam/list
import gleamdb
import gleamdb/fact.{Int}
import gleamdb/engine.{Var, Negative, Aggregate, Count}
import gleam/dict
import gleeunit
import gleeunit/should

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
    gleamdb.p(#(Var("e"), "name", Var("n"))),
    Negative(#(Var("e"), "parent", Var("child")))
  ])
  
  // Variables: ["child", "e", "n"] (sorted)
  // Bob: [Int(-1), Int(2), fact.Str("Bob")]
  // Charlie: [Int(-1), Int(3), fact.Str("Charlie")]
  should.equal(list.length(result), 2)
  should.equal(list.length(result), 2)
  should.be_true(list.contains(result, dict.from_list([#("e", Int(2)), #("n", fact.Str("Bob"))])))
  should.be_true(list.contains(result, dict.from_list([#("e", Int(3)), #("n", fact.Str("Charlie"))])))
  should.be_false(list.contains(result, dict.from_list([#("e", Int(1)), #("n", fact.Str("Alice"))])))
}

pub fn aggregation_test() {
  let db = gleamdb.new()
  
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.EntityId(1), "name", fact.Str("Alice")),
    #(fact.EntityId(2), "name", fact.Str("Bob")),
    #(fact.EntityId(3), "name", fact.Str("Charlie")),
    #(fact.EntityId(4), "name", fact.Str("Dave")),
    #(fact.EntityId(5), "name", fact.Str("Eve")),
    #(fact.EntityId(1), "parent", Int(2)),
    #(fact.EntityId(1), "parent", Int(3)),
    #(fact.EntityId(4), "parent", Int(5)),
  ])
  
  let result = gleamdb.query(db, [
    gleamdb.p(#(Var("p"), "name", Var("n"))),
    gleamdb.p(#(Var("p"), "parent", Var("child"))),
    Aggregate("c", Count, "child")
  ])
  
  // Variables: ["c", "child", "n", "p"] (sorted)
  // Alice: [Int(2), Int(-1), fact.Str("Alice"), Int(1)]
  // Dave: [Int(1), Int(-1), fact.Str("Dave"), Int(4)]
  
  should.equal(list.length(result), 2)
  should.be_true(list.contains(result, dict.from_list([#("c", Int(2)), #("n", fact.Str("Alice")), #("p", Int(1))])))
  should.be_true(list.contains(result, dict.from_list([#("c", Int(1)), #("n", fact.Str("Dave")), #("p", Int(4))])))
}
