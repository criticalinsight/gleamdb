import gleeunit/should
import gleam/option.{None, Some}
import gleam/result
import gleam/dict
import gleam/list
import gleamdb
import gleamdb/index
import gleamdb/raft
import gleamdb/vec_index
import gleam/erlang/process
import gleamdb/fact.{Uid, EntityId, Str, Int, Ref}
import gleamdb/shared/types
import gleamdb/storage
import gleamdb/algo/graph
import gleamdb/q
import gleamdb/engine

pub fn shortest_path_test() {
  let db_state = types.DbState(
    adapter: storage.ephemeral(),
    eavt: dict.new(),
    aevt: dict.new(),
    avet: dict.new(),
    latest_tx: 0,
    subscribers: [],
    schema: dict.new(),
    functions: dict.new(),
    composites: [],
    reactive_actor: process.new_subject(), // Placeholder
    followers: [],
    is_distributed: False,
    ets_name: None,
    raft_state: raft.new([]),
    vec_index: vec_index.new(),
    predicates: dict.new(),
    stored_rules: [],
    virtual_predicates: dict.new(),
    config: types.Config(parallel_threshold: 500, batch_size: 100),
  )

  // A -> B -> C
  let a = EntityId(1)
  let b = EntityId(2)
  let c = EntityId(3)
  
  let facts = [
    fact.Datom(entity: a, attribute: "connected", value: Ref(b), tx: 1, valid_time: 0, operation: fact.Assert),
    fact.Datom(entity: b, attribute: "connected", value: Ref(c), tx: 1, valid_time: 0, operation: fact.Assert),
  ]
  
  // Populate index manually for unit test
  let eavt = list.fold(facts, dict.new(), fn(idx, d) {
    index.insert_eavt(idx, d, fact.All)
  })
  let db_state = types.DbState(..db_state, eavt: eavt)
  
  // Test shortest_path
  let path = graph.shortest_path(db_state, a, c, "connected")
  should.equal(path, Some([a, b, c]))
  
  let no_path = graph.shortest_path(db_state, c, a, "connected")
  should.equal(no_path, None)
}

pub fn pagerank_test() {
  let db_state = types.DbState(
    adapter: storage.ephemeral(),
    eavt: dict.new(),
    aevt: dict.new(),
    avet: dict.new(),
    latest_tx: 0,
    subscribers: [],
    schema: dict.new(),
    functions: dict.new(),
    composites: [],
    reactive_actor: process.new_subject(),
    followers: [],
    is_distributed: False,
    ets_name: None,
    raft_state: raft.new([]),
    vec_index: vec_index.new(),
    predicates: dict.new(),
    stored_rules: [],
    virtual_predicates: dict.new(),
    config: types.Config(parallel_threshold: 500, batch_size: 100),
  )
  
  // A -> B
  // B -> A
  // C -> A
  let a = EntityId(1)
  let b = EntityId(2)
  let c = EntityId(3)
  
  let facts = [
    fact.Datom(entity: a, attribute: "link", value: Ref(b), tx: 1, valid_time: 0, operation: fact.Assert),
    fact.Datom(entity: b, attribute: "link", value: Ref(a), tx: 1, valid_time: 0, operation: fact.Assert),
    fact.Datom(entity: c, attribute: "link", value: Ref(a), tx: 1, valid_time: 0, operation: fact.Assert),
  ]
  
  // Populate AEVT index (required by PageRank)
  let aevt = list.fold(facts, dict.new(), fn(idx, d) {
    index.insert_aevt(idx, d, fact.All)
  })
  let eavt = list.fold(facts, dict.new(), fn(idx, d) {
    index.insert_eavt(idx, d, fact.All)
  })
  
  let db_state = types.DbState(..db_state, aevt: aevt, eavt: eavt)
  
  // Test pagerank
  let ranks = graph.pagerank(db_state, "link", 0.85, 20)
  
  // A should have highest rank (in-degree 2)
  let rank_a = dict.get(ranks, a) |> result.unwrap(0.0)
  let rank_b = dict.get(ranks, b) |> result.unwrap(0.0)
  let rank_c = dict.get(ranks, c) |> result.unwrap(0.0)
  
  should.be_true(rank_a >. rank_b)
  should.be_true(rank_a >. rank_c)
}

pub fn graph_query_test() {
  let db_actor = gleamdb.new()
  
  // Create graph in DB
  // A -> B -> C
  // B -> D
  let assert Ok(state) = gleamdb.transact(db_actor, [
    #(fact.Uid(fact.EntityId(1)), "name", Str("A")),
    #(fact.Uid(fact.EntityId(1)), "link", Ref(EntityId(2))),
    #(fact.Uid(fact.EntityId(2)), "name", Str("B")),
    #(fact.Uid(fact.EntityId(2)), "link", Ref(EntityId(3))),
    #(fact.Uid(fact.EntityId(2)), "link", Ref(EntityId(4))),
    #(fact.Uid(fact.EntityId(3)), "name", Str("C")),
    #(fact.Uid(fact.EntityId(4)), "name", Str("D")),
  ])
  
  // 1. Shortest Path Query
  // Find path from A to C
  // Using q builder:
  let clauses = q.new()
    |> q.where(q.v("a"), "name", q.s("A"))
    |> q.where(q.v("c"), "name", q.s("C"))
    |> q.shortest_path(q.v("a"), q.v("c"), "link", "p")
    |> q.to_clauses()

  let results = engine.run(state, clauses, [], None, None)
  should.equal(list.length(results), 1)
  let assert [row] = results
  let assert Ok(fact.List(path)) = dict.get(row, "p")
  should.equal(list.length(path), 3)
  
  // 2. PageRank Query
  let clauses = q.new()
    |> q.pagerank("node", "link", "rank")
    |> q.to_clauses()
    
  let results = engine.run(state, clauses, [], None, None)
  // Should have 4 results (A, B, C, D)
  should.equal(list.length(results), 4)
}
