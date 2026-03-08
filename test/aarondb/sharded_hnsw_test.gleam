import aarondb/fact
import aarondb/sharded
import aarondb/shared/ast as types
import aarondb/storage
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

pub fn sharded_hnsw_test() {
  // 1. Start sharded DB with 2 shards
  let assert Ok(db) =
    sharded.start_local_sharded("hnsw_cluster", 2, Some(storage.ephemeral()))

  // 2. Insert vectors into different shards using fact.Uid
  let facts = [
    #(fact.Uid(fact.EntityId(1)), "vec", fact.Vec([1.0, 0.0, 0.0])),
    #(fact.Uid(fact.EntityId(2)), "vec", fact.Vec([0.0, 1.0, 0.0])),
  ]

  let assert Ok(_) = sharded.transact(db, facts)

  // 3. Similarity Search across shards
  let query_clause =
    types.Similarity("v", types.Val(fact.Vec([0.9, 0.1, 0.0])), 0.8)
  let q =
    types.Query(
      find: ["v"],
      where: [query_clause],
      order_by: None,
      limit: None,
      offset: None,
    )
  let results = sharded.query(db, q)

  // Should find the vector [1.0, 0.0, 0.0]
  list.length(results.rows) |> should.equal(1)

  sharded.stop(db)
}
