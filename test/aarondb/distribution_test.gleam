import aarondb
import aarondb/fact
import aarondb/shared/types
import gleam/list
import gleeunit/should

pub fn distribution_test() {
  let db = aarondb.new()

  // 1. Transaction on local db
  let assert Ok(_) =
    aarondb.transact(db, [
      #(fact.Uid(fact.EntityId(1)), "name", fact.Str("Alice")),
      #(fact.Uid(fact.EntityId(1)), "age", fact.Int(30)),
    ])

  // 2. Simple query
  let result =
    aarondb.query(db, [aarondb.p(#(types.Var("e"), "name", types.Var("n")))])

  should.equal(list.length(result.rows), 1)
}
