import gleeunit/should
import gleam/option.{None}
import gleam/dict
import gleam/list
import gleamdb/fact
import gleamdb/shared/types
import gleamdb/engine
import gleamdb/storage
import gleamdb/reactive
import gleamdb/raft
import gleamdb/vec_index

pub fn engine_run_test() {
  let assert Ok(reactive_subject) = reactive.start_link()
  let state =
    types.DbState(
      adapter: storage.ephemeral(),
      eavt: dict.new(),
      aevt: dict.new(),
      avet: dict.new(),
      latest_tx: 0,
      subscribers: [],
      schema: dict.new(),
      functions: dict.new(),
      composites: [],
      reactive_actor: reactive_subject,
      followers: [],
      is_distributed: False,
      ets_name: None,
      raft_state: raft.new([]),
      vec_index: vec_index.new(),
    )

  let query = [types.Positive(#(types.Var("e"), "name", types.Val(fact.Str("Alice"))))]
  let results = engine.run(state, query, [], None)
  should.equal(list.length(results), 0)
}

pub fn pull_test() {
  let assert Ok(reactive_subject) = reactive.start_link()
  let state =
    types.DbState(
      adapter: storage.ephemeral(),
      eavt: dict.new(),
      aevt: dict.new(),
      avet: dict.new(),
      latest_tx: 0,
      subscribers: [],
      schema: dict.new(),
      functions: dict.new(),
      composites: [],
      reactive_actor: reactive_subject,
      followers: [],
      is_distributed: False,
      ets_name: None,
      raft_state: raft.new([]),
      vec_index: vec_index.new(),
    )
  let res = engine.pull(state, fact.Uid(fact.EntityId(1)), [engine.Wildcard])
  let assert engine.Map(m) = res
  should.equal(dict.size(m), 0)
}
