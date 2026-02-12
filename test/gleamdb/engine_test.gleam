import gleam/list
import gleam/dict
import gleam/option.{None}
import gleam/erlang/process
import gleeunit/should
import gleamdb/fact
import gleamdb/engine
import gleamdb/shared/types
import gleamdb/index
import gleamdb/storage/mnesia

pub fn engine_run_test() {
  let state = types.DbState(
    adapter: mnesia.adapter(),
    eavt: index.new_index(),
    aevt: index.new_aindex(),
    avet: index.new_avindex(),
    latest_tx: 0,
    subscribers: [],
    schema: dict.new(),
    functions: dict.new(),
    composites: [],
    reactive_actor: coerce(process.new_subject()),
  )
  let clauses = [
    types.Positive(#(types.Var("e"), "name", types.Var("n")))
  ]
  let result = engine.run(state, clauses, [], None)
  should.equal(list.length(result), 0)
}

pub fn pull_test() {
  let state = types.DbState(
    adapter: mnesia.adapter(),
    eavt: index.new_index(),
    aevt: index.new_aindex(),
    avet: index.new_avindex(),
    latest_tx: 0,
    subscribers: [],
    schema: dict.new(),
    functions: dict.new(),
    composites: [],
    reactive_actor: coerce(process.new_subject()),
  )
  let res = engine.pull(state, fact.EntityId(1), [engine.Wildcard])
  let assert engine.Map(m) = res
  should.equal(dict.size(m), 0)
}

@external(erlang, "gleam_erl_ffi", "coerce")
fn coerce(a: a) -> b
