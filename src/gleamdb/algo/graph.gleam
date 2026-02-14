import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}
import gleam/int
import gleam/result
import gleamdb/fact.{type EntityId, Ref}
import gleamdb/index
import gleamdb/shared/types.{type DbState}

// A simple queue implementation using two lists
type Queue(a) {
  Queue(in: List(a), out: List(a))
}

fn new_queue() -> Queue(a) {
  Queue([], [])
}

fn push_queue(q: Queue(a), item: a) -> Queue(a) {
  Queue([item, ..q.in], q.out)
}

fn pop_queue(q: Queue(a)) -> Result(#(a, Queue(a)), Nil) {
  case q.out {
    [head, ..tail] -> Ok(#(head, Queue(q.in, tail)))
    [] -> case list.reverse(q.in) {
      [] -> Error(Nil)
      [head, ..tail] -> Ok(#(head, Queue([], tail)))
    }
  }
}

pub fn shortest_path(
  state: DbState,
  from: EntityId,
  to: EntityId,
  edge_attr: String,
) -> Option(List(EntityId)) {
  bfs(state, edge_attr, to, new_queue() |> push_queue(from), set.new(), dict.new())
}

fn bfs(
  state: DbState,
  attr: String,
  target: EntityId,
  q: Queue(EntityId),
  visited: Set(EntityId),
  parents: Dict(EntityId, EntityId),
) -> Option(List(EntityId)) {
  case pop_queue(q) {
    Error(_) -> None // Queue empty, not found
    Ok(#(current, new_q)) -> {
      case current == target {
        True -> Some(reconstruct_path(target, parents, []))
        False -> {
          // Get neighbors
          let neighbors = get_neighbors(state, current, attr)
          
          // Filter unvisited
          let new_neighbors = list.filter(neighbors, fn(n) { !set.contains(visited, n) })
          
          // Update visited and parents
          let new_visited = list.fold(new_neighbors, visited, fn(s, n) { set.insert(s, n) })
          let new_parents = list.fold(new_neighbors, parents, fn(p, n) { dict.insert(p, n, current) })
          
          // Enqueue
          let next_q = list.fold(new_neighbors, new_q, fn(q_acc, n) { push_queue(q_acc, n) })
          
          bfs(state, attr, target, next_q, new_visited, new_parents)
        }
      }
    }
  }
}

fn get_neighbors(state: DbState, entity: EntityId, attr: String) -> List(EntityId) {
  // Look up outgoing edges: entity -[attr]-> value (must be Ref)
  index.get_datoms_by_entity_attr(state.eavt, entity, attr)
  |> list.filter_map(fn(d) {
    case d.value {
      Ref(id) -> Ok(id)
      _ -> Error(Nil)
    }
  })
}

fn reconstruct_path(
  current: EntityId,
  parents: Dict(EntityId, EntityId),
  acc: List(EntityId),
) -> List(EntityId) {
  let new_acc = [current, ..acc]
  case dict.get(parents, current) {
    Ok(parent) -> reconstruct_path(parent, parents, new_acc)
    Error(_) -> new_acc
  }
}

pub fn pagerank(
  state: DbState,
  attr: String,
  damping: Float,
  iterations: Int,
) -> Dict(EntityId, Float) {
  // 1. Build the graph adjacency list
  // We scan the entire AEVT index for this attribute? 
  // Optimization: Just scan EAVT would be slow if we need all edges.
  // Actually, we can just iterate over all Datoms in EAVT that match the attribute?
  // Index usually provides range scan.
  // For now, let's assume we can get all edges efficiently. 
  // Since we don't have a direct "get all for attr" API exposed from Index usually (it's internal),
  // we might need to rely on the engine or specific index function.
  // Let's assume we build it:
  
  let edges = build_graph(state, attr)
  let nodes = get_all_nodes(edges)
  let n = int.to_float(set.size(nodes))
  let initial_rank = 1.0 /. n
  
  // Initialize ranks
  let ranks = list.fold(set.to_list(nodes), dict.new(), fn(acc, node) {
    dict.insert(acc, node, initial_rank)
  })
  
  let #(incoming, out_degree) = preprocess_graph(edges, nodes)
  pagerank_iter(nodes, incoming, out_degree, ranks, damping, iterations, n)
}

// Graph: Node -> List(Neighbor)
type Graph = Dict(EntityId, List(EntityId))

fn build_graph(state: DbState, attr: String) -> Graph {
  index.filter_by_attribute(state.aevt, attr)
  |> list.fold(dict.new(), fn(graph, d) {
    case d.value {
      Ref(target) -> {
        let source = d.entity
        let current_outgoing = dict.get(graph, source) |> result.unwrap([])
        dict.insert(graph, source, [target, ..current_outgoing])
      }
      _ -> graph
    }
  })
}

fn get_all_nodes(graph: Graph) -> Set(EntityId) {
  dict.fold(graph, set.new(), fn(nodes, source, targets) {
    let nodes = set.insert(nodes, source)
    list.fold(targets, nodes, set.insert)
  })
}

fn pagerank_iter(
  nodes: Set(EntityId),
  incoming: Dict(EntityId, List(EntityId)),
  out_degree: Dict(EntityId, Int),
  ranks: Dict(EntityId, Float),
  d: Float,
  iter: Int,
  n: Float,
) -> Dict(EntityId, Float) {
  case iter {
    0 -> ranks
    _ -> {
      let node_list = set.to_list(nodes)
      
      let next_ranks = list.fold(node_list, dict.new(), fn(acc, u) {
        let incoming_nodes = dict.get(incoming, u) |> result.unwrap([])
        let sum = list.fold(incoming_nodes, 0.0, fn(s, v) {
          let rank_v = dict.get(ranks, v) |> result.unwrap(0.0)
          let degree_v = dict.get(out_degree, v) |> result.unwrap(1) |> int.to_float
          s +. { rank_v /. degree_v }
        })
        let new_rank = { 1.0 -. d } /. n +. { d *. sum }
        dict.insert(acc, u, new_rank)
      })
      
      pagerank_iter(nodes, incoming, out_degree, next_ranks, d, iter - 1, n)
    }
  }
}

fn preprocess_graph(edges: Graph, _nodes: Set(fact.EntityId)) -> #(Dict(fact.EntityId, List(fact.EntityId)), Dict(fact.EntityId, Int)) {
  let out_degree = dict.map_values(edges, fn(_, targets) { list.length(targets) })
  let incoming = dict.fold(edges, dict.new(), fn(acc, source, targets) {
    list.fold(targets, acc, fn(inner_acc, target) {
      let current = dict.get(inner_acc, target) |> result.unwrap([])
      dict.insert(inner_acc, target, [source, ..current])
    })
  })
  #(incoming, out_degree)
}
