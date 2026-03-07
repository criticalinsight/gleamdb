import aarondb/engine
import aarondb/fact
import aarondb/shared/types
import aarondb/storage
import aarondb/transactor
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None}
import gleeunit/should

pub fn art_benchmark_test() {
  let assert Ok(db) = transactor.start(storage.ephemeral())

  // 1. Insert 10000 strings
  let facts =
    int.range(from: 0, to: 10_000, with: [], run: fn(acc, i) {
      [
        #(
          fact.Uid(fact.EntityId(i)),
          "name",
          fact.Str("user_" <> int.to_string(i)),
        ),
        ..acc
      ]
    })

  let assert Ok(_) = transactor.transact(db, facts)
  let state = transactor.get_state(db)

  // 2. Measure ART Prefix Search
  let start_art = now()
  let query_art = [types.StartsWith("v", "user_99")]
  let results_art = engine.run(state, query_art, [], None, None)
  let end_art = now()

  io.println(
    "ART Search (user_99): " <> int.to_string(end_art - start_art) <> "ms",
  )
  list.length(results_art.rows) |> should.equal(111)
  // user_99, user_990..999, user_9900..9999

  // 3. Measure Linear Scan (Filter mode)
  let start_linear = now()
  let query_linear = [
    types.Positive(#(types.Var("e"), "name", types.Var("v"))),
    types.StartsWith("v", "user_99"),
  ]
  let results_linear = engine.run(state, query_linear, [], None, None)
  let end_linear = now()

  io.println(
    "Linear Search (user_99): "
    <> int.to_string(end_linear - start_linear)
    <> "ms",
  )
  list.length(results_linear.rows) |> should.equal(111)
}

@external(erlang, "erlang", "system_time")
fn now() -> Int
