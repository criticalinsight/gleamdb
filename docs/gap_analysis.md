# Gap Analysis: GleamDB vs The Giants 🧙🏾‍♂️

As GleamDB reaches Phase 17, it is a robust engine, closing the gap on "quality of life" and structural features found in mature competitors like **Datomic**, **XTDB**, and **CozoDB**.

## Competitive Landscape

| Feature | GleamDB | Datomic | XTDB | CozoDB | Utility Value |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Simple Facts (EAV)** | ✅ | ✅ | ✅ | ✅ | Fundamental |
| **Datalog Engine** | ✅ | ✅ | ✅ | ✅ | High |
| **Recursion** | ✅ | ✅ | ✅ | ✅ | High |
| **Stratified Negation** | ✅ | ⚠️ | ✅ | ✅ | High |
| **Aggregation** | ✅ | ✅ | ✅ | ✅ | High |
| **Distribution (BEAM)** | ✅ | ❌ | ⚠️ | ⚠️ | Medium |
| **Pull API** | ✅ | ✅ | ✅ | ❌ | **CRITICAL** |
| **Bi-temporality** | ✅ | ❌ | ✅ | ✅ | High (Auditing) |
| **Unique Identity** | ✅ | ✅ | ✅ | ✅ | **CRITICAL** |
| **Component Cascades**| ✅ | ✅ | ❌ | ❌ | High (Cleanup) |
| **Vector Search** | ✅ | ❌ | ❌ | ✅ | High (AI) |
| **Durable Maturity** | ✅ | ✅ | ✅ | ✅ | **CRITICAL** |

---

## High-Utility Ideas for GleamDB

### 1. The Pull API (Inspired by Datomic)
**Status:** ✅ Implemented
**The Gap:** Currently, retrieving a complex entity (e.g., a "User" with their "Posts" and "Comments") requires manual Datalog joins or multiple queries.
**The Port:** Implement `gleamdb.pull(db, entity_id, pattern)`.
*   **Utility:** Transforms raw triples into nested Gleam `Dicts`. This is the "God Feature" for Frontend developers.
*   **Hickey Logic:** It separates the *Facts* from the *Shape* the consumer needs.

### 2. Unique Identity & Constraints (Inspired by Datomic/Cozo)
**Status:** ✅ Implemented
**The Gap:** GleamDB allows multiple facts with the same Attribute for an Entity. While flexible, it makes common constraints (e.g., "One email per User") hard to enforce.
**The Port:** Support **Identity Constraints**.
*   **Utility:** Ensures data integrity. Prevents "junk" facts from accumulating in the transactor.
*   **Hickey Logic:** Data should be *correct* by construction.

### 3. Component Attributes (Inspired by Datomic)
**Status:** ✅ Implemented
**The Gap:** Deleting a parent entity in a triple store often leaves "orphan" child entities.
**The Port:** Mark certain attributes as `:is_component`.
*   **Utility:** Retracting a `User` automatically retracts their `Profile`.
*   **Hickey Logic:** It provides *referential integrity* without the complexity of Foreign Keys.

### 4. Reactive Datalog (Inspired by Differential Dataflow)
**Status:** ✅ Implemented
**The Gap:** To update a UI, the user must re-run the query.
**The Port:** Leverage the `Subscribe` mechanism to provide **Incremental Updates**.
*   **Utility:** Replicas only compute the "delta" of a query instead of the full set.
*   **Hickey Logic:** Computation should be as immutable and composable as the data itself.

---

## Proposing: Phase 22 - The Distributed Sovereign 🧙🏾‍♂️
The next logical step for GleamDB is "Scale."

1.  **Raft Consensus**: Multi-node replication for high availability.
2.  **Streaming Transactions**: Handling high-throughput ingestion via GenStage.
3.  **Global Naming**: Connecting nodes via `Subject` registry.

---

## Proposing: Phase 23 - Performance Sovereignty (Silicon Saturation) ⚡️
Optimizing for high-core count, unified memory machines (M2 Pro).

1.  **EtS-backed Indices**: Concurrent read-concurrency with zero-copy semantics.
2.  **Parallel Datalog**: Spawning join-workers across all 12+ cores.
3.  **Epoch Pipelining**: Batching transactions into 10ms "trains" for high-throughput persistence.

*This moves the system from "Correct" to "Extreme Efficiency".*
