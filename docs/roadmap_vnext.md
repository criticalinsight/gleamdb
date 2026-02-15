# Roadmap: The Sovereign Transition 🧙🏾‍♂️

GleamDB v1.3.0 was a milestone of recovery. Phases 21-23 represent **Resilient Maturity** — every critical gap from the original roadmap is now closed.

## [x] COMPLETED: The Sovereign Performance (Phase 18-20)
- **Batch Persistence**: Single I/O commit per transaction in `transactor.gleam`.
- **Silicon Saturation**: Concurrent read-concurrency via ETS indices.
- **Durable Fabric**: Mnesia substrate for BEAM-native persistence and distribution.
- **Set-based Diffing**: O(N) Reactive Datalog scaling.

## [x] COMPLETED: Resilient Maturity (Phase 21-23)

### [x] ID Sovereignty (Phase 21)
`fact.Ref(EntityId)` variant de-complects identity from data at the type level. Used across all 5 engine solver paths, Pull API, and transactor.

### [x] Raft Election Protocol (Phase 22)
Pure state machine (`raft.gleam`) with term-based voting, heartbeat liveness (50ms), randomized election timeout (150-300ms), majority quorum, automatic step-down. De-complected from replication.

### [x] NSW Vector Index (Phase 23)
`vec_index.gleam` provides O(log N) navigable small-world graph for similarity search. Transactor auto-indexes Vec values. Engine falls back to AVET scan if index is empty.

### [x] Vector Enrichment (Phase 23)
`vector.gleam` extended with `euclidean_distance`, `normalize`, `dimensions`.

### [x] Native Sharding (Phase 24)
Horizontal partitioning of facts across strictly isolated local shards (`gleamdb/sharded`). Linear scaling with logical cores on M2/M3 silicon (>10k durable writes/sec).

### [x] Deterministic Identity (Phase 25)
`fact.deterministic_uid` and `fact.phash2` ensure ID consistency across distributed nodes without coordination. Enables idempotent ingestion.

### [x] The Intelligent Engine (Phase 26)
Native **Graph Algorithms** (ShortestPath, PageRank), **Data Federation** (Virtual Predicates), and **Time Travel** (Diff API).

### [x] The Speculative Soul (Phase 27)
Frictionless "Database as a Value" with `with_facts`, recursive `pull`, and a navigational Entity API.

### [x] The Logical Navigator (Phase 28)
Cost-based query optimization and heuristic join reordering.

### [x] The Chronos Sovereign (Phase 29)
Bitemporal data model (Valid Time + System Time) and `as_of_valid` time travel.

### [x] The Completeness (Phase 30)
Atomic Transaction Functions and Composite Constraints for total integrity.

### [x] Sovereign Intelligence (Phase 31)
distributed Aggregates (`Sum`, `Count`, `Avg`, `Max`, `Min`, `Median`) and Parallel Query Execution.

### [x] Graph Algorithm Suite (Phase 32)
9 native graph predicates: `ShortestPath`, `PageRank`, etc.

### [x] HNSW Vector Indexing (Phase 44)
Hierarchical layers for true $O(\log N)$ scaling on 1M+ vector datasets. Replaced flat NSW with robust HNSW.

### [x] Advanced Join Optimization (ART) (Phase 45)
Adaptive Radix Tree integration for multi-way join optimization.

---

## Future Directions (v2.1.0+)

| Item | Description | Priority |
| :--- | :--- | :--- |
| **Persistent Pull Cache** | LRU cache for hot pull patterns | Low |
| **WAL Streaming** | Real-time transaction log streaming for external downstream consumers | Low |

---

## Current Status: Phase 45 (HNSW & ART) — v2.1.0
All original roadmap items, Sovereign Intelligence, Graph Algorithm Suite, HNSW, and ART are complete. The system is correct, durable, speculative, parallel, horizontally scalable, and graph-intelligent.

🧙🏾‍♂️: "A system that is correct, durable, sovereign, graph-intelligent, AND hierarchically scalable is no longer a foundation. It is a Citadel."