import aarondb
import aarondb/fact
import aarondb/shared/types
import gleam/dict
import gleam/list
import gleam/option
import gleeunit/should

pub fn bitemporal_basic_test() {
  let db = aarondb.new()

  // 1. Assert fact for Valid Time 100
  let assert Ok(_) =
    aarondb.transact_at(
      db,
      [#(fact.Uid(fact.EntityId(1)), "user/location", fact.Str("London"))],
      100,
    )

  // 2. Query at Valid Time 50 (should be empty)
  let results_50 =
    aarondb.as_of_valid(db, 50, [
      aarondb.p(#(types.Var("e"), "user/location", types.Var("loc"))),
    ])
  should.equal(list.length(results_50.rows), 0)

  // 3. Query at Valid Time 100 (should have London)
  let results_100 =
    aarondb.as_of_valid(db, 100, [
      aarondb.p(#(types.Var("e"), "user/location", types.Var("loc"))),
    ])
  should.equal(list.length(results_100.rows), 1)
}

pub fn bitemporal_correction_test() {
  let db = aarondb.new()

  // 0. Set location to be unique (cardinality one)
  let assert Ok(_) =
    aarondb.set_schema(
      db,
      "user/location",
      fact.AttributeConfig(
        unique: True,
        component: False,
        retention: fact.All,
        cardinality: fact.One,
        check: option.None,
        composite_group: option.None,
        layout: fact.Row,
        tier: fact.Memory,
        eviction: fact.AlwaysInMemory,
      ),
    )

  // 1. We thought Rich was in London at VT=100
  let assert Ok(_) =
    aarondb.transact_at(
      db,
      [#(fact.Uid(fact.EntityId(1)), "user/location", fact.Str("London"))],
      100,
    )

  // 2. Later we discovered he was actually in Paris at VT=100
  let assert Ok(_) =
    aarondb.transact_at(
      db,
      [#(fact.Uid(fact.EntityId(1)), "user/location", fact.Str("Paris"))],
      100,
    )

  // 3. Query at latest TX, VT=100
  let results =
    aarondb.as_of_valid(db, 100, [
      aarondb.p(#(types.Var("e"), "user/location", types.Var("loc"))),
    ])

  should.equal(list.length(results.rows), 1)
  let assert [res] = results.rows
  should.equal(dict.get(res, "loc"), Ok(fact.Str("Paris")))
}

pub fn bitemporal_proactive_test() {
  let db = aarondb.new()

  // Assert a future promotion
  let assert Ok(_) =
    aarondb.transact_at(
      db,
      [#(fact.Uid(fact.EntityId(1)), "user/role", fact.Str("CEO"))],
      2_000_000_000,
    )
  // Far future

  // Query now (simulated current time < 2B)
  let results_now =
    aarondb.as_of_valid(db, 100, [
      aarondb.p(#(types.Var("e"), "user/role", types.Var("r"))),
    ])
  should.equal(list.length(results_now.rows), 0)

  // Query in future
  let results_future =
    aarondb.as_of_valid(db, 2_000_000_001, [
      aarondb.p(#(types.Var("e"), "user/role", types.Var("r"))),
    ])
  should.equal(list.length(results_future.rows), 1)
}
