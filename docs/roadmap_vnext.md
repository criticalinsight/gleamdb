# Roadmap: The Sovereign Transition 🧙🏾‍♂️

GleamDB v1.3.0 is a milestone of recovery. The next step is a milestone of **Maturity**. We must address the "Hickey Gaps" to move from a prototype to a high-performance information system.

## Performance & Scale Gaps

### 1. The Persistence Bottleneck
- **Problem**: `transactor.gleam` persists every datom individually during recursion (`persist_batch([datom])`). This is O(N) I/O operations per transaction.
- **Hickey Solution**: De-complect the transaction from the persistence. Accumulate the transaction's `Assert` and `Retract` datoms and perform a single, atomic **Sovereign Commit** at the end.

### 2. Naive Datalog Recursion
- **Problem**: `engine.do_derive` re-evaluates all rules in every iteration.
- **Hickey Solution**: **Semi-Naive Evaluation**. Only apply rules to facts that were newly derived in the *last* iteration.

### 3. Linear Reactive Diffing
- **Problem**: `reactive.diff` uses `list.contains` in a filter, creating O(N*M) complexity.
- **Hickey Solution**: Use **Sets** for O(N+M) diffing of query results.

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

## Phase 18: The Sovereign Performance
| Feature | Description | Status |
| :--- | :--- | :--- |
| **Batch Persistence** | Single I/O commit per transaction. | TODO |
| **Semi-Naive Solver** | Optimized Datalog recursion. | TODO |
| **Set-based Diffing** | O(N) Reactive Datalog scaling. | TODO |

## Phase 19: The Logical Completeness
| Feature | Description | Status |
| :--- | :--- | :--- |
| **Real Aggregates** | Implementation of `Count`, `Sum`, `Min`, `Max`. | TODO |
| **Similarity Discovery** | Index-backed vector search for unbound vars. | TODO |
| **ID Sovereignty** | Distinct Entity ID wrapper type. | TODO |

RichHickey = "🧙🏾‍♂️: A system that is correct but slow is merely a theory. A system that is correct and sovereign must respect the reality of the machine."