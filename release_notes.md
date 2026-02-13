# 🚀 Temporal Intelligence v1.6.0

This release introduces **Phase 23: Time Series & Analytics**, transforming GleamDB from a purely logical engine into a high-performance analytical store for time-series data.

## ✨ Key Features

### ⏳ Time Series Primitives
- **`Temporal` Clause**: Native support for time-range queries on integer timestamps.
- **`OrderBy` / `Limit` / `Offset`**: Push-down predicates allow efficient pagination and sorting at the database level.
- **`Aggregate`**: Compute `Avg`, `Sum`, `Count`, `Min`, `Max` directly in the query engine.

### 🆔 Deterministic Identity
- **`phash2` Integration**: Standardized on Erlang's portable hash for generating deterministic Entity IDs from unique keys (e.g., Market IDs).
- Solves indexing consistency issues in distributed setups.

## 📦 Install
```toml
gleamdb = "1.6.0"
```

---

# 🚀 Resilient Maturity v1.5.0

This release marks the completion of the "Sovereign Transition" roadmap. GleamDB is now a robust, distributed, and AI-native Datalog engine.

## ✨ Key Features

### 🆔 ID Sovereignty (Phase 21)
- De-complected identity from data at the type level using `fact.Ref(EntityId)`.
- Eliminates class of bugs where integers were mistaken for IDs.
- Permeates the entire engine: solver, pull API, and transactor.

### 🗳️ Raft Consensus (Phase 22)
- **Zero-Downtime Failover**: Pure Raft state machine (`raft.gleam`) manages leader election.
- **Split-Brain Protection**: Term-based voting and majority quorums.
- **Autonomous Recovery**: Followers automatically promote themselves if the leader fails.

### 🧭 NSW Vector Index (Phase 23)
- **O(log N) Similarity**: Replaced O(N) brute-force scan with a Navigable Small-World graph.
- **Auto-Indexing**: `Vec` values are automatically indexed on assert/retract.
- **Graph-Accelerated**: `solve_similarity` uses the graph index for unbound variable searches.
- **Enriched Vectors**: Added `euclidean_distance`, `normalize`, and `dimensions` to `vector.gleam`.

## 📚 Documentation
- Updated `distributed_guide.md` with Raft protocols.
- Updated `performance_guide.md` with NSW benchmarks.
- Closed all gaps in `gap_analysis.md`.

## 📦 Install
```toml
gleamdb = "1.5.0"
```

*Built with ❤️ on the BEAM.*
