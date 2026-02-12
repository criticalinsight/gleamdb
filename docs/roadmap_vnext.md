# Roadmap: The Sovereign Transition 🧙🏾‍♂️

GleamDB v1.3.0 is a milestone of recovery. The next step is a milestone of **Maturity**. We must address the "Hickey Gaps" to move from a prototype to a high-performance information system.

## [x] COMPLETED: The Sovereign Performance (Phase 18-20)
- **Batch Persistence**: Single I/O commit per transaction implemented in `transactor.gleam`.
- **Silicon Saturation**: Concurrent read-concurrency via ETS indices.
- **Durable Fabric**: Mnesia substrate for BEAM-native persistence and distribution.
- **Set-based Diffing**: O(N) Reactive Datalog scaling.

## Performance & Scale Roadmap (Phase 21+)

## Functional & Architectural Gaps

### 4. The Aggregate Skeleton
- **Problem**: `engine.solve_aggregate` is a placeholder. No `Count`, `Sum`, or grouping.
- **Hickey Solution**: Implement a proper aggregation pass that operates on unified result sets.

### 5. Similarity Discovery
- **Problem**: `solve_similarity` only filters bound variables. It cannot find similar items if the variable is unbound (no index scan).
- **Hickey Solution**: Integrate with `AVET` or specialized Vector Indexes to allow similarity search to act as a **Source Clause** (generating entities from search).

### 6. Value-Level Type Safety
- **Problem**: Entity IDs are raw `Int` types, leading to confusion between IDs and data.
- **Hickey Solution**: Re-introduce a distinct **ID type** that is not implicitly convertible to an integer at the type system level.

---

### 7. Raft-based Consensus
- **Problem**: The current Sovereign Fabric uses a single leader without automated election for failover.
- **Hickey Solution**: Implement a Raft-based consensus module for zero-downtime leader promotion.

### 8. Optimized Pull API
- **Problem**: Large nested pulls can be expensive if not properly indexed.
- **Hickey Solution**: Specialized `Pull` indices that pre-cache common nesting patterns.

---

## Current Status: Phase 20 (Durable Sovereign)
The system is now correct, durable, and concurrent. We are entering the stage of **Resilient Maturity**.

RichHickey = "🧙🏾‍♂️: A system that is correct but slow is merely a theory. A system that is correct, durable, and sovereign is a foundation. Now, we build for resilience."