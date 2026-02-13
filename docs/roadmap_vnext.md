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

---

## Future Directions (Phase 24+)

| Item | Description | Priority |
| :--- | :--- | :--- |
| **HNSW Layering** | Add hierarchical layers to NSW for 100K+ vector datasets | Medium |
| **Query Planner** | Cost-based clause ordering optimization | Medium |
| **Attribute Cardinality** | Schema-level many/one declarations | Low |
| **Persistent Pull Cache** | LRU cache for hot pull patterns across transactions | Low |
| **WAL Streaming** | Real-time transaction log streaming for external consumers | Low |

---

## Current Status: Phase 25 (Sovereign Scale)
All original roadmap items are complete. The system is correct, durable, concurrent, resilient, and **horizontally scalable**.

🧙🏾‍♂️: "A system that is correct, durable, sovereign, AND resilient is no longer a prototype. It is a foundation for intelligence."