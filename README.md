# GleamDB 🧙🏾‍♂️

> "Simplicity is not about making things easy. It is about untangling complexity." — Rich Hickey

GleamDB is a high-performance, analytical Datalog engine built natively for the BEAM. It treats the database as an immutable value, preserves full transaction history, and leverages the BEAM's actor model for massive query concurrency.

## 🧬 Core Philosophy
1.  **Immutability**: The database is a value. A transaction produces a *new* database value.
2.  **Facts, not Objects**: Data is represented as atomic facts: `(Entity, Attribute, Value, Transaction, Operation)`.
3.  **Datalog Engine**: A semi-naive deductive logic engine supports recursive queries and graph traversals.
4.  **De-complecting Search**: Full-text search is delegated to native host capabilities (e.g., SQLite FTS5) while maintaining relational facts.
5.  **Pluggable Persistence**: Decoupled engine logic with adapters for Mnesia, SQLite, and in-memory storage.

## 🚀 Key Features
- **Silicon Saturation**: Lock-free, concurrent read indices via ETS (O(1) access).
- **Vector Sovereignty**: Native similarity search for semantic context and clustering.
- **Memory Safety**: Fact Retention Policies (`LatestOnly`, `Last(N)`) and subscriber scavenging.
- **Distributed Sovereign**: Multi-node replication and transaction forwarding via BEAM distribution.
- **OTP Native**: Queries are independent actors, allowing for introspection, suspension, and distribution.

## ⚡ Performance
> "Speed is a byproduct of correctness."

- **Concurrency**: Lock-free reads via Silicon Saturation (ETS), allowing linear scaling with CPU cores.
- **Throughput**: Capable of ingesting **~120,000 datoms/sec** (SQLite WAL mode).
- **Latency**: Sub-millisecond read access for single-entity lookups.

## 🛠️ Usage

### Installation & Initialization
Add `gleamdb` to your `gleam.toml`:
```toml
[dependencies]
gleamdb = { path = "../gleamdb" }
```

Initialize with **Silicon Saturation** (ETS-backed indices) for O(1) concurrent reads:
```gleam
import gleamdb
import gleamdb/storage

// Recommended for high performance
let assert Ok(db) = gleamdb.start_named("production", Some(storage.sqlite("data.db")))
```

### Basic Transaction
```gleam
import gleamdb
import gleamdb/fact.{Uid, EntityId, Str}

let assert Ok(state) = gleamdb.transact(db, [
  #(Uid(EntityId(101)), "user/name", Str("Alice")),
  #(Uid(EntityId(101)), "user/role", Str("Admin"))
])
```

### Datalog Query
Use the fluent `q` DSL:
```gleam
import gleamdb/q
import gleam/dict

let query = q.select(["name"])
  |> q.where(q.v("e"), "user/role", q.s("Admin"))
  |> q.where(q.v("e"), "user/name", q.v("name"))
  |> q.to_clauses()

let results = gleamdb.query(db, query)
// Returns list of bindings: [#("name", Str("Alice"))]
```

### Vector Similarity Search
```gleam
import gleamdb/shared/types.{Similarity, Val, Var}

let query = [
  Similarity(Var("market"), [0.1, 0.2, 0.3], 0.9)
]
let results = gleamdb.query(db, query)
```

### Memory Safety (Retention)
```gleam
let config = fact.AttributeConfig(unique: False, component: False, retention: fact.LatestOnly)
gleamdb.set_schema(db, "ticker/price", config)
```

## 📚 Documentation
- [Performance Guide (Silicon Saturation)](docs/performance_guide.md)
- [Distributed Guide (The Sovereign Fabric)](docs/distributed_guide.md)
- [Architecture Details](docs/architecture.md)
- [Datalog Specification](docs/specs/gleam_datalog.md)
- [The Completeness (Roadmap)](docs/specs/the_completeness.md)
- [Gap Analysis](docs/gap_analysis.md)

## 🤝 Contributing
GleamDB is built with the goal of providing a "Sovereign Knowledge Service" for autonomous agents like **Sly**. Contributions that respect the de-complecting philosophy are welcome.

---
*Built with ❤️ on the BEAM*
