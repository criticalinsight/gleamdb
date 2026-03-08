import aarondb
import aarondb/fact
import aarondb/shared/ast
import gleam/int
import gleam/io
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn benchmark_test() {
  let db = aarondb.new()

  // Insert 1000 facts
  let tx_data =
    list.repeat(Nil, 1000)
    |> list.index_map(fn(_, i) {
      #(
        fact.Uid(fact.EntityId(i + 1)),
        "name",
        fact.Str("user_" <> int.to_string(i + 1)),
      )
    })

  let start_tx = now()
  let assert Ok(_) = aarondb.transact(db, tx_data)
  let end_tx = now()
  io.println("Transaction Time: " <> int.to_string(end_tx - start_tx) <> "ms")

  // Benchmark basic query
  let query = [ast.Positive(#(ast.Var("e"), "name", ast.Var("v")))]

  let start_q = now()
  let result = aarondb.query(db, query)
  let end_q = now()
  io.println("Query Time: " <> int.to_string(end_q - start_q) <> "ms")

  should.equal(list.length(result.rows), 1000)

  // Benchmark ART optimized query (StartsWith)
  let query_art = [ast.StartsWith("v", "user_99")]
  // Prefix filter on unbound variable acts as generator
  let start_art = now()
  let result_art = aarondb.query(db, query_art)
  let end_art = now()
  io.println("ART Search Time: " <> int.to_string(end_art - start_art) <> "ms")

  // user_99, user_990..999 (should be 11 matches)
  should.equal(list.length(result_art.rows), 11)

  // Benchmark Combined
  let query_combined = [
    ast.Positive(#(ast.Var("e"), "name", ast.Var("v"))),
    ast.StartsWith("v", "user_99"),
  ]

  let start_comb = now()
  let result_comb = aarondb.query(db, query_combined)
  let end_comb = now()
  io.println(
    "Combined Search Time: " <> int.to_string(end_comb - start_comb) <> "ms",
  )

  should.equal(list.length(result_comb.rows), 11)
}

@external(erlang, "erlang", "system_time")
fn now() -> Int
