import gleam/list
import gleam/result
import gleamdb
import gleamdb/fact.{Int}
import gleamdb/engine.{Rule}
import gleam/dict
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn recursive_ancestor_test() {
  let db = gleamdb.new()
  
  // Facts: 1 parent 2, 2 parent 3 (1 -> 2 -> 3)
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.EntityId(1), "parent", Int(2)),
    #(fact.EntityId(2), "parent", Int(3)),
  ])

  // Rules:
  // 1. ancestor(X, Y) :- parent(X, Y)
  // 2. ancestor(X, Z) :- parent(X, Y), ancestor(Y, Z)
  let rules = [
    Rule(
      name: "ancestor_base",
      head: #(engine.Var("x"), "ancestor", engine.Var("y")),
      body: [gleamdb.p(#(engine.Var("x"), "parent", engine.Var("y")))]
    ),
    Rule(
      name: "ancestor_recursive",
      head: #(engine.Var("x"), "ancestor", engine.Var("z")),
      body: [
        gleamdb.p(#(engine.Var("x"), "parent", engine.Var("y"))),
        gleamdb.p(#(engine.Var("y"), "ancestor", engine.Var("z")))
      ]
    )
  ]

  // Query: Find all ancestors of 1
  let result = gleamdb.query_with_rules(db, [
    gleamdb.p(#(engine.Val(Int(1)), "ancestor", engine.Var("anc")))
  ], rules)
  
  // Should find 2 and 3
  // Should find 2 and 3
  should.equal(list.length(result), 2)
  let expected = [
    dict.from_list([#("anc", Int(2))]),
    dict.from_list([#("anc", Int(3))])
  ]
  // Ordering might vary
  should.be_true(list.contains(expected, list.first(result) |> result.unwrap(dict.new())))
  should.be_true(list.contains(expected, list.last(result) |> result.unwrap(dict.new())))
}
