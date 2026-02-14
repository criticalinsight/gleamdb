# Graph Algorithms (Native Predicates)

GleamDB provides native graph algorithms implemented as "Magic Predicates" within the Datalog engine. This allows for complex network analysis without leaving the logic paradigm.

## Implementation Pattern: De-complected Traversals
Following the philosophy of Rich Hickey, we de-complect the graph traversal from the query planning.

1.  **Uniformity**: Graph algorithms are exposed as standard `BodyClause` types.
2.  **High Performance**: PageRank pre-computes the graph structure (adjacency lists and out-degrees) before iterating, ensuring that the iterative power method is efficient.
3.  **Correctness by Construction**: BFS (Shortest Path) ensures the most optimal route is found in O(V + E) time.

## Usage

### Shortest Path
Find the shortest sequence of entities between two nodes via a specific edge attribute.

```gleam
import gleamdb/q

// Find the path from London to Paris
let query = q.new()
  |> q.where(q.v("start"), "city/name", q.s("London"))
  |> q.where(q.v("end"), "city/name", q.s("Paris"))
  |> q.shortest_path(q.v("start"), q.v("end"), "route/to", "path")
  |> q.to_clauses()
```

### PageRank
Compute the relative importance of nodes in a directed graph.

```gleam
import gleamdb/q

// Calculate ranks for all nodes connected by "link"
let query = q.new()
  |> q.pagerank("node", "link", "rank")
  |> q.order_by("rank", Desc)
  |> q.limit(10)
  |> q.to_clauses()
```

## Technical Details
- **Shortest Path**: Uses a standard Breadth-First Search (BFS).
- **PageRank**: Implements the iterative power method with a default damping factor of 0.85 and 20 iterations.
- **Index Usage**: Algorithms directly query the `EAVT` and `AEVT` indices for high-speed edge lookups.
