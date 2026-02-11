import gleeunit/should
import gleam/dict
import gleamdb.{p}
import gleamdb/fact.{AttributeConfig, EntityId, Vec, Str}
import gleamdb/shared/types.{Similarity}

pub fn vector_sovereignty_test() {
  let db = gleamdb.new()
  
  // 1. Setup Schema
  let assert Ok(_) = gleamdb.set_schema(db, "doc/id", AttributeConfig(unique: True, component: False))
  let assert Ok(_) = gleamdb.set_schema(db, "doc/embedding", AttributeConfig(unique: False, component: False))
  
  // 2. Transact Docs with Embeddings
  // doc1: [1.0, 0.0] (e.g. "Science")
  // doc2: [0.0, 1.0] (e.g. "Art")
  // doc3: [0.9, 0.1] (e.g. "Space Science")
  let assert Ok(_) = gleamdb.transact(db, [
    #(EntityId(1), "doc/id", Str("science-1")),
    #(EntityId(1), "doc/embedding", Vec([1.0, 0.0])),
    
    #(EntityId(2), "doc/id", Str("art-1")),
    #(EntityId(2), "doc/embedding", Vec([0.0, 1.0])),
    
    #(EntityId(3), "doc/id", Str("space-1")),
    #(EntityId(3), "doc/embedding", Vec([0.9, 0.1]))
  ])
  
  // 3. Query for similar to "Science" [1.0, 0.0] with threshold 0.8
  let q = [
    p(#(types.Var("e"), "doc/id", types.Var("id"))),
    p(#(types.Var("e"), "doc/embedding", types.Var("v"))),
    Similarity("v", [1.0, 0.0], 0.8)
  ]
  
  let results = gleamdb.query(db, q)
  
  // Should find doc1 and doc3
  let ids = list_ids(results)
  should.be_true(list_contains(ids, "science-1"))
  should.be_true(list_contains(ids, "space-1"))
  should.be_false(list_contains(ids, "art-1"))
}

fn list_ids(results: types.QueryResult) -> List(String) {
  list_map(results, fn(r) {
    case dict.get(r, "id") {
      Ok(Str(s)) -> s
      _ -> ""
    }
  })
}

// Minimal helpers to avoid extra imports for simple test logic
fn list_map(l: List(a), f: fn(a) -> b) -> List(b) {
  case l {
    [] -> []
    [h, ..t] -> [f(h), ..list_map(t, f)]
  }
}

fn list_contains(l: List(String), target: String) -> Bool {
  case l {
    [] -> False
    [h, ..t] -> {
      case h == target {
        True -> True
        False -> list_contains(t, target)
      }
    }
  }
}
