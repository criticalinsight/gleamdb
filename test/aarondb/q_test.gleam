import aarondb/fact
import aarondb/q
import aarondb/shared/ast
import gleam/option.{Some}
import gleeunit/should

pub fn query_builder_test() {
  let builder =
    q.select(["x", "y"])
    |> q.where(q.v("e"), "attr", q.v("x"))
    |> q.negate(q.v("e"), "missing", q.s("val"))
    |> q.limit(10)
    |> q.offset(5)

  let query = q.to_query(builder)

  should.equal(query.find, ["x", "y"])
  should.equal(query.limit, Some(10))
  should.equal(query.offset, Some(5))

  let assert [
    ast.Positive(#(ast.Var("e"), "attr", ast.Var("x"))),
    ast.Negative(#(ast.Var("e"), "missing", ast.Val(fact.Str("val")))),
  ] = query.where
}
