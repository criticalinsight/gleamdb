import gleam/dict.{type Dict}
import gleam/list
import gleam/float
import gleamdb/fact
import gleamdb/vector

/// A Navigable Small-World (NSW) graph for approximate nearest neighbor search.
/// Single-layer NSW — the Hickey-minimal approach that gives O(log N) search
/// without the complexity of hierarchical layers.
pub type VecIndex {
  VecIndex(
    nodes: Dict(fact.EntityId, List(Float)),
    edges: Dict(fact.EntityId, List(fact.EntityId)),
    max_neighbors: Int,
    entry_point: Result(fact.EntityId, Nil),
  )
}

/// A search result: entity ID + similarity score.
pub type SearchResult {
  SearchResult(entity: fact.EntityId, score: Float)
}

// --- Constructor ---

/// Create an empty vector index with default max_neighbors of 16.
pub fn new() -> VecIndex {
  VecIndex(
    nodes: dict.new(),
    edges: dict.new(),
    max_neighbors: 16,
    entry_point: Error(Nil),
  )
}

/// Create an empty vector index with custom max_neighbors.
pub fn new_with_m(m: Int) -> VecIndex {
  VecIndex(..new(), max_neighbors: m)
}

// --- Insert ---

/// Insert a vector into the NSW graph.
/// Greedy-links the new node to its nearest existing neighbors.
pub fn insert(
  idx: VecIndex,
  entity: fact.EntityId,
  vec: List(Float),
) -> VecIndex {
  // Store the vector
  let nodes = dict.insert(idx.nodes, entity, vec)
  
  case dict.size(idx.nodes) {
    0 -> {
      // First node — no edges needed, just set entry point
      VecIndex(
        ..idx,
        nodes: nodes,
        edges: dict.insert(idx.edges, entity, []),
        entry_point: Ok(entity),
      )
    }
    _ -> {
      // Find nearest neighbors by scanning existing nodes
      let neighbors = find_nearest_neighbors(idx, vec, idx.max_neighbors)
      let neighbor_ids = list.map(neighbors, fn(r) { r.entity })
      
      // Add bidirectional edges
      let edges_with_new = dict.insert(idx.edges, entity, neighbor_ids)
      let final_edges = list.fold(neighbor_ids, edges_with_new, fn(acc, n_id) {
        let existing = dict.get(acc, n_id) |> unwrap_list()
        let updated = prune_neighbors(idx, n_id, [entity, ..existing], nodes)
        dict.insert(acc, n_id, updated)
      })
      
      VecIndex(
        ..idx,
        nodes: nodes,
        edges: final_edges,
        entry_point: Ok(entity),
      )
    }
  }
}

// --- Search ---

/// Search for vectors similar to query within threshold, returning up to k results.
/// Uses greedy beam search through the NSW graph.
pub fn search(
  idx: VecIndex,
  query: List(Float),
  threshold: Float,
  k: Int,
) -> List(SearchResult) {
  case idx.entry_point {
    Error(Nil) -> []
    Ok(start) -> {
      // Greedy beam search
      let visited = dict.new()
      let results = do_search(idx, query, [start], visited, [], k * 2)
      
      // Filter by threshold and take top-k
      results
      |> list.filter(fn(r) { r.score >=. threshold })
      |> list.sort(fn(a, b) { float.compare(b.score, a.score) })
      |> list.take(k)
    }
  }
}

fn do_search(
  idx: VecIndex,
  query: List(Float),
  candidates: List(fact.EntityId),
  visited: Dict(fact.EntityId, Bool),
  results: List(SearchResult),
  budget: Int,
) -> List(SearchResult) {
  case budget <= 0 || list.is_empty(candidates) {
    True -> results
    False -> {
      // Score all unvisited candidates
      let scored = list.filter_map(candidates, fn(eid) {
        case dict.has_key(visited, eid) {
          True -> Error(Nil)
          False -> {
            case dict.get(idx.nodes, eid) {
              Ok(vec) -> {
                let score = vector.cosine_similarity(query, vec)
                Ok(SearchResult(entity: eid, score: score))
              }
              Error(Nil) -> Error(Nil)
            }
          }
        }
      })
      
      // Mark candidates as visited
      let new_visited = list.fold(candidates, visited, fn(acc, eid) {
        dict.insert(acc, eid, True)
      })
      
      // Merge results
      let new_results = list.append(results, scored)
      
      // Get the best unvisited neighbor of the best candidate
      let next_candidates = scored
        |> list.sort(fn(a, b) { float.compare(b.score, a.score) })
        |> list.take(3)  // Beam width of 3
        |> list.flat_map(fn(r) {
          dict.get(idx.edges, r.entity) |> unwrap_list()
        })
        |> list.filter(fn(eid) { !dict.has_key(new_visited, eid) })
        |> list.unique()
      
      do_search(idx, query, next_candidates, new_visited, new_results, budget - 1)
    }
  }
}

// --- Delete ---

/// Remove a node from the index and repair edges.
pub fn delete(idx: VecIndex, entity: fact.EntityId) -> VecIndex {
  let nodes = dict.delete(idx.nodes, entity)
  
  // Get neighbors of deleted node
  let neighbors = dict.get(idx.edges, entity) |> unwrap_list()
  
  // Remove edges to/from deleted node
  let edges = dict.delete(idx.edges, entity)
  let repaired_edges = list.fold(neighbors, edges, fn(acc, n_id) {
    let existing = dict.get(acc, n_id) |> unwrap_list()
    let filtered = list.filter(existing, fn(e) { e != entity })
    dict.insert(acc, n_id, filtered)
  })
  
  // Update entry point if necessary
  let new_entry = case idx.entry_point {
    Ok(ep) if ep == entity -> {
      case list.first(neighbors) {
        Ok(n) -> Ok(n)
        Error(Nil) -> {
          // Pick any remaining node
          case dict.keys(nodes) |> list.first() {
            Ok(k) -> Ok(k)
            Error(Nil) -> Error(Nil)
          }
        }
      }
    }
    other -> other
  }
  
  VecIndex(..idx, nodes: nodes, edges: repaired_edges, entry_point: new_entry)
}

// --- Helpers ---

/// Find the nearest neighbors to a query vector by brute-force scan of the index.
/// Used during insertion to connect new nodes.
fn find_nearest_neighbors(
  idx: VecIndex,
  query: List(Float),
  k: Int,
) -> List(SearchResult) {
  dict.to_list(idx.nodes)
  |> list.map(fn(pair) {
    let #(eid, vec) = pair
    let score = vector.cosine_similarity(query, vec)
    SearchResult(entity: eid, score: score)
  })
  |> list.sort(fn(a, b) { float.compare(b.score, a.score) })
  |> list.take(k)
}

/// Prune a neighbor list to max_neighbors, keeping the most similar.
fn prune_neighbors(
  idx: VecIndex,
  node_id: fact.EntityId,
  candidates: List(fact.EntityId),
  nodes: Dict(fact.EntityId, List(Float)),
) -> List(fact.EntityId) {
  case dict.get(nodes, node_id) {
    Error(Nil) -> list.take(list.unique(candidates), idx.max_neighbors)
    Ok(node_vec) -> {
      list.unique(candidates)
      |> list.filter_map(fn(c) {
        case dict.get(nodes, c) {
          Ok(v) -> Ok(#(c, vector.cosine_similarity(node_vec, v)))
          Error(Nil) -> Error(Nil)
        }
      })
      |> list.sort(fn(a, b) { float.compare(b.1, a.1) })
      |> list.take(idx.max_neighbors)
      |> list.map(fn(pair) { pair.0 })
    }
  }
}

fn unwrap_list(res: Result(List(a), Nil)) -> List(a) {
  case res {
    Ok(l) -> l
    Error(Nil) -> []
  }
}

/// Get the number of vectors in the index.
pub fn size(idx: VecIndex) -> Int {
  dict.size(idx.nodes)
}

/// Check if the index contains a given entity.
pub fn contains(idx: VecIndex, entity: fact.EntityId) -> Bool {
  dict.has_key(idx.nodes, entity)
}
