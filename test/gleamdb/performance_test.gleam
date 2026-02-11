import gleam/list
import gleamdb
import gleamdb/fact.{Int}
import gleamdb/engine.{Val, Rule, Var}
import gleam/dict
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn join_optimization_test() {
  let db = gleamdb.new()
  
  // High cardinality data
  let facts = list.flat_map(list.range(1, 100), fn(i) {
    [#(fact.EntityId(i), "type", Int(0)), #(fact.EntityId(i), "val", Int(i))]
  })
  
  let assert Ok(_) = gleamdb.transact(db, facts)
  
  // Specific fact
  let assert Ok(_) = gleamdb.transact(db, [#(fact.EntityId(101), "type", Int(1)), #(fact.EntityId(101), "val", Int(999))])
  
  // Query: Find entity of type 1 that has val V
  // The optimizer should run the 'type' = 1 clause first because it is a Val-constant.
  let _start_time = 0 
  
  let result = gleamdb.query(db, [
    gleamdb.p(#(Var("e"), "type", Val(Int(1)))),
    gleamdb.p(#(Var("e"), "val", Var("v")))
  ])
  
  should.equal(result, [dict.from_list([#("e", Int(101)), #("v", Int(999))])])
}

pub fn large_recursion_benchmark_test() {
  let db = gleamdb.new()
  
  // Linear graph of 50 nodes
  let facts = list.map(list.range(1, 49), fn(i) {
    #(fact.EntityId(i), "parent", Int(i + 1))
  })
  
  let assert Ok(_) = gleamdb.transact(db, facts)
  
  let rules = [
    Rule("anc", #(Var("A"), "ancestor", Var("B")), [
      gleamdb.p(#(Var("A"), "parent", Var("B")))
    ]),
    Rule("anc_rec", #(Var("A"), "ancestor", Var("C")), [
      gleamdb.p(#(Var("A"), "parent", Var("B"))),
      gleamdb.p(#(Var("B"), "ancestor", Var("C")))
    ])
  ]
  
  // Find all ancestors of 50. Should be 1..49.
  let result = gleamdb.query_with_rules(db, [
    gleamdb.p(#(Var("a"), "ancestor", Val(Int(50))))
  ], rules)
  
  should.equal(list.length(result), 49)
}
