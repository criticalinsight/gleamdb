# GleamDB Query DSL (`gleamdb/q`) 🎨

> "Querying should feel like drawing, not assembling furniture."

The `gleamdb/q` module provides a fluent, type-safe builder for constructing Datalog queries. It replaces the verbose tuple construction with a pipeline-friendly API.

## Core Concepts

### 1. Values vs Variables
Datalog logic distinguishes between fixed values (`Val`) and logical variables (`Var`).
- Use `q.v("name")` to create a **Variable** (e.g., `?name`).
- Use `q.s("string")` or `q.i(42)` to create a **Value**.

### 2. The Pipeline
Queries start with `q.select` and flow through a series of `where` (and `negate`) clauses.

## API Reference

### `q.select(vars: List(String))`
Starts a new query builder.
- **vars**: Currently implicit, but reserved for projected variables in future versions.
- **Returns**: A fresh `QueryBuilder`.

```gleam
let query = q.select(["e", "name"])
```

### `q.where(entity, attribute, value)`
Adds a **Positive** clause. Matches facts that *exist* in the database.
- **entity**: `q.v("e")` or `q.i(101)`
- **attribute**: String (e.g., `"user/email"`)
- **value**: `q.v("email")` or `q.s("alice@example.com")`

```gleam
q.where(q.v("e"), "user/role", q.s("Admin"))
```

### `q.negate(entity, attribute, value)`
Adds a **Negative** clause. Matches only if the fact does *not* exist.
- **Constraint**: All variables in a negative clause must be bound in a positive clause elsewhere in the query (Safety).

```gleam
// Find users who are NOT admins
|> q.where(q.v("e"), "user/name", q.v("name"))
|> q.negate(q.v("e"), "user/role", q.s("Admin"))
```

### 5. Advanced Predicates (Graph & Federation)
Native logic for complex traversals and external data:

- `q.shortest_path(from, to, edge, path_var)`: BFS pathfinding.
- `q.pagerank(entity_var, edge, rank_var)`: PageRank node importance.
- `q.virtual(predicate, args, outputs)`: Federated data access.

```gleam
let query = q.new()
  |> q.shortest_path(q.v("a"), q.v("b"), "route/to", "path")
  |> q.virtual("external_api", [q.v("path")], ["status"])
```

### 6. Aggregates
GleamDB supports nested aggregate clauses. These take a target variable, a filter sub-query, and an output variable.
- `q.count(into, target, filter)`
- `q.sum(into, target, filter)`
- `q.avg(into, target, filter)`
- `q.min(into, target, filter)`
- `q.max(into, target, filter)`

```gleam
let query = q.select(["count"])
  |> q.count("count", "e", [
      q.where(q.v("e"), "user/status", q.s("active"))
  ])
  |> q.to_clauses()
```

### Helpers
- `q.v(name)`: Creates a Variable (`Var`).
- `q.s(val)`: Creates a String Value (`Val(Str)`).
- `q.i(val)`: Creates an Int Value (`Val(Int)`).
- `q.to_clauses(builder)`: Finalizes the builder into a `List(BodyClause)` for `gleamdb.query`.

## Full Example

```gleam
import gleamdb
import gleamdb/q

pub fn find_active_admins(db: gleamdb.Db) {
  let query = q.select(["name"])
    |> q.where(q.v("e"), "user/role", q.s("Admin"))
    |> q.where(q.v("e"), "user/status", q.s("Active"))
    |> q.where(q.v("e"), "user/name", q.v("name"))
    |> q.to_clauses()

  gleamdb.query(db, query)
}
```
