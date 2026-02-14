# GleamDB: Development History & Architectural Journey 🧙🏾‍♂️

GleamDB was conceived as a "Rich Hickey-inspired" analytical database: a system that prioritizes the **Information Model** (Facts) over the **Data Model** (Tables), leverages the BEAM's actor model for concurrency, and maintains logical purity through Datalog. It follows the **Rama Pattern**: a write-optimized transaction log coupled with read-optimized indices (Silicon Saturation).

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

### Phase 18: Vector Sovereignty (Context)
*   **The Problem:** Analytical agents need to reason about *similarity*, not just equality. 
*   **The Solution:** Integrated **Vector Similarity** into the Datalog engine using Cosine Similarity over `fact.Vec` data.
*   **Innovation:** Semantic queries now live alongside logical ones in the same DSL.

### Phase 19: The Saturation Paradox (Memory Safety)
*   **The Problem:** Silicon Saturation's throughput (~1M ops/sec theoretical) exceeded the physical memory bounds when combined with infinite history.
*   **The Solution:**
    1.  **Retention Policies:** Implemented `LatestOnly` and `Last(N)` pruning in indices and ETS.
    2.  **Subscriber Scavenging:** Reactive nervous system now auto-prunes dead listener subjects.
*   **Result:** Indefinite high-frequency ingestion stability.

### Phase 20: The Durable Fabric (Mnesia Substrate)
*   **The Problem:** SQLite persistence, while solid, introduced coordination overhead for leader-follower replication and lacked BEAM-native distribution.
*   **The Solution:** Integrated **Mnesia** as a durable substrate. 
*   **Innovation:** We used `disc_copies` and `dirty_write` for high-throughput durable ingestion (~2500 events/sec) while maintaining record-level compatibility with Gleam types.
*   **Result:** A truly durable Sovereign Fabric that survives node restarts without sacrificing relational integrity.

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
| **Memory Exhaustion**| High-frequency infinite history | Fact Retention Policies (`LatestOnly`) + Scavenging. |
| **Context Gap** | Pure logical equality | Vector Sovereignty (Similarity queries in Datalog). |
| **Leader Down** | Static registration | Autonomous Failover (Process Monitoring + Promotion). |
| **Split-Brain** | Concurrent leaders | Raft Election Protocol (Term-based voting + majority quorum). |

### Phase 22: Raft Election Protocol (Consensus)
*   **The Problem:** The Sovereign Fabric relied on static `global:register_name` for leader election — no term-based voting, no split-brain prevention.
*   **The Solution:** Implemented a **pure Raft state machine** (`raft.gleam`) for leader election, de-complected from replication (handled by Mnesia + SyncDatoms).
*   **Innovation:** The state machine is pure — it returns `#(RaftState, List(RaftEffect))`. The transactor interprets the effects (send heartbeats, register leader, manage timers). This separates the election *logic* from the *mechanism*.
*   **Result:** Term-based voting, heartbeat-driven liveness, majority quorum for leader promotion, and automatic step-down on higher terms.

### Phase 23: Time Series & Analytics (Push-Down Predicates)
*   **The Problem:** Analytical queries (e.g., "last 100 ticks", "average price") required fetching *all* data to the client for filtering/sorting, causing massive O(N) serialization overhead.
*   **The Solution:** Implemented **Push-Down Predicates** in the query engine.
    1.  **`OrderBy` & `Limit`**: Sorting and pagination happen *during* the query plan execution, minimizing data transfer.
    2.  **`Aggregate`**: Server-side calculation of Sum, Avg, Min, Max, Count.
    3.  **`Temporal`**: Native range queries on integer timestamps.
*   **Result:** O(Limit) data transfer instead of O(Total). Gswarm enables "Entity-per-Tick" modeling without performance penalty.

*   **Result:** O(Limit) data transfer instead of O(Total). Gswarm enables "Entity-per-Tick" modeling without performance penalty.

### Phase 24: Native Sharding (Horizontal Partitioning)
*   **The Problem:** While Silicon Saturation handled reads, *Write Throughput* was bound by the single Raft leader (Global Lock). Multi-core CPUs (M2/M3) were underutilized.
*   **The Solution:** Implemented **Native Sharding** (`gleamdb/sharded`).
    1.  **Logical Partitioning:** The keyspace is divided into `N` shards (Actors).
    2.  **Deterministic Routing:** `bloom.shard_key` ensures facts about the same entity always land on the same shard.
    3.  **Local Consensus:** Each shard runs its own Raft instance (Democratic Partitioning).
*   **Innovation:** We treat each shard as a "City State" — fully autonomous but federated. This allows linear write scaling with core count.
*   **Result:** Saturation of M3 Max hardware, pushing ingestion from ~2.5k to >10k durable events/sec.

### Phase 26: The Intelligent Engine (Federation & Graph)
*   **The Problem:** Analytical agents need to traverse complex networks (e.g., knowledge graphs) and access data residing outside the database (CSV, APIs).
*   **The Solution:** 
    1.  **Native Graph Predicates:** Implemented `ShortestPath` and `PageRank` as "Magic Predicates". PageRank pre-computes the graph structure before iterating to maximize BEAM performance.
    2.  **Virtual Predicates (Federation):** Enabled runtime registration of external data adapters. The query engine delegates to these adapters, allowing seamless joins between internal facts and external worlds.
    3.  **Time Travel (Diff API):** Exposed the ability to compute the exact set of datom-level changes (Assertions and Retractions) between any two transaction IDs.
*   **Result:** GleamDB is no longer just a store; it is a unified knowledge service capable of complex reasoning and deep introspection.

### Phase 32: Graph Algorithm Suite (9 Native Predicates)
*   **The Problem:** ShortestPath and PageRank alone were insufficient for real-world graph intelligence — trading ring detection, dependency resolution, and broker identification required a comprehensive analytical stack.
*   **The Solution:** Expanded from 2 to **9 native graph predicates**, all implemented as pure, immutable algorithms in `algo/graph.gleam` (~700 lines):
    1.  **Reachable** — Transitive closure via BFS flood
    2.  **ConnectedComponents** — Undirected cluster labeling
    3.  **Neighbors** — Bounded K-hop exploration
    4.  **CycleDetect** — DFS back-edge detection for circular patterns
    5.  **BetweennessCentrality** — Brandes' algorithm for gatekeeper identification
    6.  **TopologicalSort** — Kahn's algorithm for dependency ordering
    7.  **StronglyConnectedComponents** — Tarjan's algorithm for directed mutual-reachability clusters
*   **Innovation:** Every predicate composes freely with Datalog joins, filters, and aggregates via the fluent `q` DSL. All algorithms share `build_graph` infrastructure over AEVT indices.
*   **Result:** A complete graph intelligence stack for Gswarm (trading analysis) and Sly (code dependency analysis).

---
*GleamDB is now a complete expression of analytical intent.* 🧙🏾‍♂️
