# GleamDB: Development History & Architectural Journey 🧙🏾‍♂️

GleamDB was conceived as a "Rich Hickey-inspired" analytical database: a system that prioritizes the **Information Model** (Facts) over the **Data Model** (Tables), leverage the BEAM's actor model for concurrency, and maintains logical purity through Datalog.

## The Journey of the Conductor

The development followed seven distinct phases, each layering complexity only when the utility outweighed the cost.

### Phase 1: The Atomic Fact (MVP)
*   **The Problem:** How to represent truth without the rigidity of tables?
*   **The Solution:** We started with the `Datom`: `(Entity, Attribute, Value, Transaction, Operation)`.
*   **Hurdle:** Initial queries were O(N) scans.
*   **Architectural Decision:** We embraced the **Triple Store** model, ensuring that every piece of information is a discrete, immutable assertion.

### Phase 2: Query-as-Process (Actor Model)
*   **The Problem:** Large analytical queries could block the database transactor.
*   **The Solution:** We decoupled the **Transactor** (Single Writer) from **Queries** (Ephemeral Actors). Each query spawns its own process, ensuring that long-running joins don't latency-spike the transaction log.
*   **Innovation:** Implementation of `as_of` queries. By keeping the transaction ID in the Datom, we can "time travel" simply by filtering the view.

### Phase 3 & 4: Deductive Logic & Recursion
*   **The Problem:** Traditional relational joins are "flat". We needed to express hierarchies (Ancestry, Network Topologies).
*   **The Solution:** Implementation of a **Semi-Naive Datalog Engine**. 
*   **Hurdle:** Managing state convergence in recursive loops.
*   **Solution:** We used a fixed-point iteration strategy where the engine continues deriving new facts until no more "novel" facts appear.

### Phase 5: The Performance Wall (Indexing)
*   **The Problem:** As the dataset grew, `list.filter` became a bottleneck.
*   **The Solution:** We refactored the internal indices from flat lists to **Bucketed Dicts** (`EAVT` and `AEVT`). 
*   **Result:** O(1) attribute and entity lookups transformed the engine from an experimental toy into a high-utility analytical tool.

### Phase 6: The Paradox of Negation
*   **The Problem:** Negation in Datalog leads to paradoxes (e.g., "A is true if A is not true").
*   **The Solution:** **Stratified Evaluation**. We implemented a dependency graph checker that ensures no "Negative Cycles" exist in the rules. We group rules into strata and evaluate them in order.

### Phase 7: Cluster-Awareness (Distribution)
*   **The Problem:** Local-first is great, but the BEAM is designed for clusters.
*   **Hurdle:** Async races. Replicas would "miss" facts if they weren't subscribed before the first transaction.
*   **Solution:** 
    1.  **Global Registry FFI:** Bridged Gleam to Erlang's `global` module for cross-node discovery.
    2.  **Synchronous Subscriptions:** Changed `Subscribe` from a cast to a call, forcing the system to wait until the "bridge" was physically established.
    3.  **Forwarder Actors:** Created owned subjects to manage message flow without violating Gleam/OTP's ownership rules.

### Phase 8: Scaling & Search (Performance)
*   **The Problem:** High-frequency ingestion (e.g., codebase scans) caused IO bottleneck. relational Datalog is poor for substring search.
*   **The Solution:**
    1.  **Atomic Batch Protocol:** Introduced `persist_batch` to the `StorageAdapter`, collapsing transactions and yielding a **~55x speedup**.
    2.  **Native Search Integration:** Instead of complecting the relational engine with search, we delegate to host-native capabilities (e.g., **SQLite FTS5**).
*   **Hickey Principle:** De-complect Search from Relational Storage. Facts are for relations; indices are for retrieval.

### Phase 13: The Performance Ceiling (Monitoring)
*   **The Problem:** Under massive concurrent load (e.g., Amkabot stress test), actor mailboxes overflowed, and transactions timed out (>5000ms).
*   **The Solution:**
    1.  **WAL Mode:** Enabled SQLite Write-Ahead Logging to allow non-blocking concurrent reads/writes.
    2.  **Configurable Timeouts:** Implemented `transact_with_timeout` to allow large batches to complete without crashing the calling process.
*   **Result:** Stable ingestion of ~120k datoms/sec.

### Phase 17: Developer Experience (Ergonomics)
*   **The Problem:** Writing raw tuples for queries was error-prone, and manual supervision was tedious.
*   **The Solution:**
    1.  **Fluent DSL:** `gleamdb/q` provides a type-safe builder for `BodyClause` construction.
    2.  **Standard OTP API:** `start_link` and `child_spec` allow `gleamdb` to sit naturally in a supervision tree.
*   **Result:** A library that feels "native" to the Gleam ecosystem.

## Core Philosophy: What Would Rich Hickey Do?

Throughout development, we asked: *Is the increased complexity worth the utility?*

*   **Immutability:** Every fact is permanent. "Deletions" are just Retraction assertions (Tombstones).
*   **Declassification:** We separated the *Identity* (Entity ID) from the *State* (Value).
*   **Simplicity:** The engine is under 2000 lines of Gleam. It does one thing: manages the lifecycle of facts.

## Technical Blockers & Solutions Summary

| Problem | Root Cause | Solution |
| :--- | :--- | :--- |
| **O(N) Queries** | Flat list storage | Bucketed `Dict` indexing (EAVT/AEVT). |
| **Negative Cycles** | Recursive negation | Stratification graph analysis. |
| **Mnesia Interop** | Gleam types vs Erlang | Specialized FFI wrappers for record handling. |
| **Async Races** | Non-blocking subscriptions | Synchronous `process.call` for registration signals. |
| **Recursive Types** | Anonymous loop functions | Named recursive functions with explicit signatures. |
| **Ingestion Latency** | Sequential IO (N writes) | Atomic `persist_batch` protocol (~55x faster). |
| **Substring Search** | Relational Datalog bottleneck | De-complected native FTS5 integration. |
| **Actor Timeouts** | Sync calls on massive batches | SQLite WAL Mode + Configurable `transact_with_timeout`. |

---
*GleamDB is now a complete expression of analytical intent.* 🧙🏾‍♂️
