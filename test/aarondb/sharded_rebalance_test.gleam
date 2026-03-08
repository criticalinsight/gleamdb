import aarondb/fact.{EntityId, Str, Uid}
import aarondb/sharded
import aarondb/shared/ast as types
import gleam/list
import gleam/option.{None}
import gleeunit/should

pub fn rebalance_test() {
  // 1. Start a cluster with 2 shards
  let assert Ok(db) = sharded.start_local_sharded("test_cluster", 2, None)

  // 2. Ingest some facts
  let facts = [
    #(Uid(EntityId(1)), "user/name", Str("Alice")),
    #(Uid(EntityId(2)), "user/name", Str("Bob")),
    #(Uid(EntityId(3)), "user/name", Str("Charlie")),
  ]
  let assert Ok(_) = sharded.transact(db, facts)

  // 3. Add a new shard
  let assert Ok(db2) = sharded.add_shard(db, None)
  db2.shard_count |> should.equal(3)

  // 4. Verify all facts are still reachable
  let query =
    types.Query(
      find: ["e", "n"],
      where: [types.Positive(#(types.Var("e"), "user/name", types.Var("n")))],
      order_by: None,
      limit: None,
      offset: None,
    )
  let res = sharded.query(db2, query)
  list.length(res.rows) |> should.equal(3)

  sharded.stop(db2)
}
