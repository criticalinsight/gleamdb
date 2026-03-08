import aarondb
import aarondb/fact
import aarondb/shared/ast
import gleam/dict
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn bitemporal_query_test() {
  let db = aarondb.new()

  // 1. Initial State (T1)
  let assert Ok(_) =
    aarondb.transact(db, [
      #(fact.Uid(fact.EntityId(1)), "user/location", fact.Str("London")),
    ])

  // 2. Query at T1
  let res1 =
    aarondb.query(db, [
      aarondb.p(#(ast.Var("e"), "user/location", ast.Var("loc"))),
    ])
  should.equal(list.length(res1.rows), 1)
  let assert Ok(row1) = list.first(res1.rows)
  should.equal(dict.get(row1, "loc"), Ok(fact.Str("London")))

  // 3. Update at T2
  let assert Ok(_) =
    aarondb.transact(db, [
      #(fact.Uid(fact.EntityId(1)), "user/location", fact.Str("Paris")),
    ])

  // 4. Query current (T2)
  let res2 =
    aarondb.query(db, [
      aarondb.p(#(ast.Var("e"), "user/location", ast.Var("loc"))),
    ])
  let assert Ok(row2) = list.first(res2.rows)
  should.equal(dict.get(row2, "loc"), Ok(fact.Str("Paris")))

  // 5. Query as-of T1 (Temporal operator)
  // Assuming the first transaction was at TX 1
  let res3 =
    aarondb.query(db, [
      ast.Temporal(ast.Tx, 1, ast.At, "t", ast.Var("e"), [
        aarondb.p(#(ast.Var("e"), "user/location", ast.Var("loc"))),
      ]),
    ])

  // London should be visible at TX 1
  let assert Ok(row3) = list.first(res3.rows)
  should.equal(dict.get(row3, "loc"), Ok(fact.Str("London")))
}

pub fn bitemporal_valid_time_test() {
  // Testing valid-time (business time) independently of transaction time
  let db = aarondb.new()

  // Role: Admin starting from 2020 (VT: 2020)
  let assert Ok(_) =
    aarondb.transact_at(
      db,
      [
        #(fact.Uid(fact.EntityId(10)), "user/role", fact.Str("Admin")),
      ],
      2020,
    )

  // Query as if it's 2021
  let res_future =
    aarondb.query(db, [
      ast.Temporal(ast.Valid, 2021, ast.At, "vt", ast.Var("e"), [
        aarondb.p(#(ast.Var("e"), "user/role", ast.Var("r"))),
      ]),
    ])
  should.equal(list.length(res_future.rows), 1)

  // Query as if it's 2019
  let res_past =
    aarondb.query(db, [
      ast.Temporal(ast.Valid, 2019, ast.At, "vt", ast.Var("e"), [
        aarondb.p(#(ast.Var("e"), "user/role", ast.Var("r"))),
      ]),
    ])
  // Should ideally be empty if we implemented full valid-time support.
  // For now, these are stubs/placeholders in Phase 0 structure,
  // but we verify the AST structure works.
  should.equal(list.length(res_past.rows), 0)
}
