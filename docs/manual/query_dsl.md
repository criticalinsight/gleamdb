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
