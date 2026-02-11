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
- **Atomic Batch Ingestion**: Optimized `persist_batch` protocol for high-throughput symbol indexing (~55x speedup).
- **Native FTS5 Integration**: Sub-second semantic search via trigram indexing.
- **Bi-temporal Queries**: Query any entity `as_of` a specific transaction ID.
- **Recursive Rules**: Easily model hierarchical data (org charts, dependency graphs) with logical purity.
- **Pull API**: Declarative retrieval of nested entity skeletons.
- **Sovereign Fabric**: Reactive graph propagation and cross-actor state synchronization.
- **Surgically Clean**: 100% warning-free build, verified for correctness and utility.
- **OTP Native**: Queries are independent actors, allowing for introspection, suspension, and distribution.

## ⚡ Performance
> "Speed is a byproduct of correctness."

- **Throughput**: Capable of ingesting **~120,000 datoms/sec** (SQLite WAL mode).
- **Latency**: Sub-millisecond read access for single-entity lookups.
- **Tuning**:
    - **WAL Mode**: Essential for high-concurrency workloads.
    - **Timeouts**: Use `transact_with_timeout` for massive batches (>10k datoms).

## 🛠️ Usage

### Installation
Add `gleamdb` to your `gleam.toml`:
```toml
[dependencies]
gleamdb = { path = "../gleamdb" }
```

### Basic Transaction
```gleam
import gleamdb

let db = gleamdb.new()
let assert Ok(state) = gleamdb.transact(db, [
  #(fact.EntityId(101), "user/name", Str("Alice")),
  #(fact.EntityId(101), "user/role", Str("Admin"))
])
```

### Datalog Query
```gleam
let results = gleamdb.query(db, [
  schema.p(Var("e"), "user/role", Val(Str("Admin"))),
  schema.p(Var("e"), "user/name", Var("name"))
])
// Returns list of bindings: [#("e", Int(101)), #("name", Str("Alice"))]
```

## 📚 Documentation
- [Architecture Details](docs/architecture.md)
- [Datalog Specification](docs/specs/gleam_datalog.md)
- [The Completeness (Roadmap)](docs/specs/the_completeness.md)
- [Gap Analysis](docs/gap_analysis.md)

## 🤝 Contributing
GleamDB is built with the goal of providing a "Sovereign Knowledge Service" for autonomous agents like **Sly**. Contributions that respect the de-complecting philosophy are welcome.

---
*Built with ❤️ on the BEAM*
