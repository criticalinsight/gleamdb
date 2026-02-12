# Roadmap: The Final Frontier - Vector Sovereignty 🧙🏾‍♂️

GleamDB has evolved from a simple triple-store into a robust de-complected information system. However, in the age of AI, "Information" is no longer just atoms; it is **Vectors**.

## Missing Features (The "Hickey Gaps")

### 1. Vector Search (Phase 15)
- **Problem**: Current search is textual (FTS5) or exact (EAV). We cannot query by "meaning" or "similarity."
- **Hickey Solution**: Do not build a new vector DB. Instead, de-complect the index. Treat a vector as a specialized **Value Type** and implement HNSW navigation within the Beam processes or via SQLite `vec0` extension.

### 2. Multi-Store Sovereignty (Storage Protocols v2)
- **Problem**: Large vectors in Mnesia will bloat RAM.
- **Hickey Solution**: Implement **Pluggable Indexing**. Store the Facts in SQLite but keep the HNSW Vector Index in a specialized BEAM actor for sub-millisecond similarity traversal.

### 3. Reactive Datalog (Phase 16)
- **Problem**: To see changes, you must query.
- **Hickey Solution**: Incremental view maintenance. Consumers subscribe to a *Query*, and receive *Deltas* as transactions occur.

### 4. Developer Experience & Supervision (Phase 17)
- **Problem**: `gleamdb` is hard to supervise, queries are verbose, and types leak.
- **Hickey Solution**:
    - **Supervisor-First API**: Expose standard `child_spec` / `start_link`.
    - **Fluent Query DSL**: `q.select(...) |> q.where(...)`.
    - **Public Types**: Re-export core types for ergonomic use.
    - **Reactive Bindings**: Formalize `ReactiveResult` as a first-class citizen.
    - **Type-Safe IDs**: Re-introduce a lightweight wrapper for IDs.

---

## The Next PRD: Phase 15 - Vector Sovereignty

| Feature | Description | Status |
| :--- | :--- | :--- |
| **fact.Vector** | New value type for float arrays. | Completed |
| **Similarity Query** | `q([p(#(e, "embedding", v)), similarity(v, [0.1, 0.2], 0.8)])` | Completed |
| **SQLite vec0** | Leveraging specialized FFI for vector math. | Deferred |

## The Next PRD: Phase 16 - Reactive Datalog
| Feature | Description | Status |
| :--- | :--- | :--- |
| **ReactiveDelta** | `Initial` / `Delta` types for subscription updates. | Completed |
| **Diff Engine** | Actor-based diffing of query results. | Completed |
| **API Update** | `subscribe` returns `Subject(ReactiveDelta)`. | Completed |

## The Next PRD: Phase 17 - Developer Experience
| Feature | Description | Status |
| :--- | :--- | :--- |
| **Supervisor API** | `gleamdb.child_spec` for OTP trees. | Completed |
| **Query DSL** | Fluent builder for clauses. | Completed |
| **Public Types** | Ergonomic exports for end-users. | Completed |
| **Reactive Bindings** | Formalized result types for subscriptions. | Completed |
| **Type-Safe IDs** | Wrapper types for Entity IDs. | Completed |

RichHickey = "🧙🏾‍♂️: Your data has shape. Your data has history. Now, your data must have direction. A vector is just a fact with a compass."
