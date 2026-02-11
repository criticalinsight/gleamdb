import gleam/list
import gleam/float

pub fn dot_product(v1: List(Float), v2: List(Float)) -> Float {
  list.zip(v1, v2)
  |> list.fold(0.0, fn(acc, pair) { acc +. { pair.0 *. pair.1 } })
}

pub fn magnitude(v: List(Float)) -> Float {
  let sum_sq = list.fold(v, 0.0, fn(acc, x) { acc +. { x *. x } })
  case float.square_root(sum_sq) {
    Ok(m) -> m
    Error(_) -> 0.0
  }
}

pub fn cosine_similarity(v1: List(Float), v2: List(Float)) -> Float {
  let mag1 = magnitude(v1)
  let mag2 = magnitude(v2)
  
  case mag1 == 0.0 || mag2 == 0.0 {
    True -> 0.0
    False -> dot_product(v1, v2) /. { mag1 *. mag2 }
  }
}
