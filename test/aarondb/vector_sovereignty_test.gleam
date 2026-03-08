import aarondb
import aarondb/fact.{Str, Vec}
import aarondb/shared/ast
import gleam/dict
import gleam/list
import gleam/option.{None}
import gleeunit/should

pub fn vector_similarity_test() {
  let db = aarondb.new()

  // 1. Setup Data with Embeddings
  let assert Ok(_) =
    aarondb.transact(db, [
      #(fact.Uid(fact.EntityId(1)), "doc/id", Str("tech-1")),
      #(fact.Uid(fact.EntityId(1)), "doc/embedding", Vec([1.0, 0.0, 0.0])),
      #(fact.Uid(fact.EntityId(2)), "doc/id", Str("art-1")),
      #(fact.Uid(fact.EntityId(2)), "doc/embedding", Vec([0.0, 1.0, 0.0])),
      #(fact.Uid(fact.EntityId(3)), "doc/id", Str("space-1")),
      #(fact.Uid(fact.EntityId(3)), "doc/embedding", Vec([0.9, 0.1, 0.0])),
    ])

  // 2. Query for similar documents to [0.85, 0.15, 0.0]
  let query_vec = ast.Val(Vec([0.85, 0.15, 0.0]))
  let result =
    aarondb.query(db, [
      aarondb.p(#(ast.Var("e"), "doc/id", ast.Var("id"))),
      aarondb.p(#(ast.Var("e"), "doc/embedding", ast.Var("v"))),
      ast.Similarity("v", query_vec, 0.95),
    ])

  // Result should be space-1 and tech-1
  should.equal(list.length(result.rows), 2)

  let ids =
    list.map(result.rows, fn(row) {
      let assert Ok(Str(id)) = dict.get(row, "id")
      id
    })
  should.be_true(list.contains(ids, "tech-1"))
  should.be_true(list.contains(ids, "space-1"))
}

pub fn vector_retention_test() {
  let db = aarondb.new()

  // Setup with LatestOnly
  let _ =
    aarondb.set_schema(
      db,
      "v",
      fact.AttributeConfig(
        unique: False,
        component: False,
        retention: fact.LatestOnly,
        cardinality: fact.One,
        check: None,
        composite_group: None,
        layout: fact.Row,
        tier: fact.Memory,
        eviction: fact.AlwaysInMemory,
      ),
    )

  let eid = fact.EntityId(1)
  let _ = aarondb.transact(db, [#(fact.Uid(eid), "v", Vec([1.0, 0.0]))])
  let _ = aarondb.transact(db, [#(fact.Uid(eid), "v", Vec([0.0, 1.0]))])

  // Should only find the latest vector
  let res =
    aarondb.query(db, [
      ast.Similarity("v", ast.Val(Vec([0.9, 0.1])), 0.9),
      aarondb.p(#(ast.Var("e"), "v", ast.Var("v"))),
    ])

  list.length(res.rows) |> should.equal(0)
  // [0.9, 0.1] is not similar to [0.0, 1.0]
}
