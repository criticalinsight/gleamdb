import aarondb/algo/aggregate
import aarondb/fact.{Float, Int}
import aarondb/shared/ast
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn sum_test() {
  let values = [Int(10), Int(20), Int(30)]
  let assert Ok(res) = aggregate.aggregate(values, ast.Sum)
  should.equal(res, Int(60))

  let floats = [Float(10.5), Float(20.5)]
  let assert Ok(res2) = aggregate.aggregate(floats, ast.Sum)
  should.equal(res2, Float(31.0))

  let mixed = [Int(10), Float(20.5)]
  let assert Ok(res3) = aggregate.aggregate(mixed, ast.Sum)
  should.equal(res3, Float(30.5))

  let empty = []
  let res4 = aggregate.aggregate(empty, ast.Sum)
  should.equal(res4, Ok(Int(0)))
}

pub fn count_test() {
  let values = [Int(10), Int(20), Int(30)]
  let assert Ok(res) = aggregate.aggregate(values, ast.Count)
  should.equal(res, Int(3))

  let empty: List(fact.Value) = []
  let assert Ok(res2) = aggregate.aggregate(empty, ast.Count)
  should.equal(res2, Int(0))
}

pub fn min_max_test() {
  let values = [Int(30), Int(10), Int(20)]
  let assert Ok(min_res) = aggregate.aggregate(values, ast.Min)
  should.equal(min_res, Int(10))

  let assert Ok(max_res) = aggregate.aggregate(values, ast.Max)
  should.equal(max_res, Int(30))

  let strings = [fact.Str("cat"), fact.Str("apple"), fact.Str("bat")]
  let assert Ok(min_s) = aggregate.aggregate(strings, ast.Min)
  should.equal(min_s, fact.Str("apple"))

  let assert Ok(max_s) = aggregate.aggregate(strings, ast.Max)
  should.equal(max_s, fact.Str("cat"))
}

pub fn avg_test() {
  let values = [Int(10), Int(20), Int(30)]
  let assert Ok(res) = aggregate.aggregate(values, ast.Avg)
  should.equal(res, Float(20.0))

  let floats = [Float(10.0), Float(20.0), Float(60.0)]
  let assert Ok(res2) = aggregate.aggregate(floats, ast.Avg)
  should.equal(res2, Float(30.0))
}

pub fn median_test() {
  let v1 = [Int(10), Int(30), Int(20)]
  let assert Ok(res1) = aggregate.aggregate(v1, ast.Median)
  should.equal(res1, Int(20))

  let v2 = [Int(10), Int(20), Int(30), Int(40)]
  // (20 + 30) / 2 = 25.0
  let assert Ok(res2) = aggregate.aggregate(v2, ast.Median)
  should.equal(res2, Float(25.0))
}
