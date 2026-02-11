import gleam/list
import gleam/dict
import gleam/option.{None}
import gleeunit/should
import gleamdb/fact
import gleamdb/engine
import gleamdb/shared/types

pub fn engine_run_test() {
  let state = engine.new()
  let clauses = [
    types.Positive(#(types.Var("e"), "name", types.Var("n")))
  ]
  let result = engine.run(state, clauses, [], None)
  should.equal(list.length(result), 0)
}

pub fn pull_test() {
  let state = engine.new()
  let res = engine.pull(state, fact.EntityId(1), engine.AllAttributes)
  should.equal(dict.size(res), 0)
}
