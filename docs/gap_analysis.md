# Gap Analysis: GleamDB vs The Giants 🧙🏾‍♂️

As GleamDB reaches Phase 7, it is a robust engine, but it lacks some of the "quality of life" and structural features found in mature competitors like **Datomic**, **XTDB**, and **CozoDB**.

## Competitive Landscape

| Feature | GleamDB | Datomic | XTDB | CozoDB | Utility Value |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Simple Facts (EAV)** | ✅ | ✅ | ✅ | ✅ | Fundamental |
| **Datalog Engine** | ✅ | ✅ | ✅ | ✅ | High |
| **Recursion** | ✅ | ✅ | ✅ | ✅ | High |
| **Stratified Negation** | ✅ | ⚠️ | ✅ | ✅ | High |
| **Aggregation** | ✅ | ✅ | ✅ | ✅ | High |
| **Distribution (BEAM)** | ✅ | ❌ | ⚠️ | ⚠️ | Medium |
| **Pull API** | ❌ | ✅ | ✅ | ❌ | **CRITICAL** |
| **Bi-temporality** | ❌ | ❌ | ✅ | ✅ | High (Auditing) |
| **Unique Identity** | ❌ | ✅ | ✅ | ✅ | **CRITICAL** |
| **Component Cascades**| ❌ | ✅ | ❌ | ❌ | High (Cleanup) |
| **Vector Search** | ❌ | ❌ | ❌ | ✅ | High (AI) |

---

## High-Utility Ideas for GleamDB

### 1. The Pull API (Inspired by Datomic)
**The Gap:** Currently, retrieving a complex entity (e.g., a "User" with their "Posts" and "Comments") requires manual Datalog joins or multiple queries.
**The Port:** Implement `gleamdb.pull(db, entity_id, pattern)`.
*   **Utility:** Transforms raw triples into nested Gleam `Dicts`. This is the "God Feature" for Frontend developers.
*   **Hickey Logic:** It separates the *Facts* from the *Shape* the consumer needs.

### 2. Unique Identity & Constraints (Inspired by Datomic/Cozo)
**The Gap:** GleamDB allows multiple facts with the same Attribute for an Entity. While flexible, it makes common constraints (e.g., "One email per User") hard to enforce.
**The Port:** Support **Identity Constraints**.
*   **Utility:** Ensures data integrity. Prevents "junk" facts from accumulating in the transactor.
*   **Hickey Logic:** Data should be *correct* by construction.

### 3. Component Attributes (Inspired by Datomic)
**The Gap:** Deleting a parent entity in a triple store often leaves "orphan" child entities.
**The Port:** Mark certain attributes as `:is_component`.
*   **Utility:** Retracting a `User` automatically retracts their `Profile`.
*   **Hickey Logic:** It provides *referential integrity* without the complexity of Foreign Keys.

### 4. Reactive Datalog (Inspired by Differential Dataflow)
**The Gap:** To update a UI, the user must re-run the query.
**The Port:** Leverage the `Subscribe` mechanism to provide **Incremental Updates**.
*   **Utility:** Replicas only compute the "delta" of a query instead of the full set.
*   **Hickey Logic:** Computation should be as immutable and composable as the data itself.

---

## Proposing: Phase 8 - Entity Purity 🧙🏾‍♂️
The next logical step for GleamDB is not "more speed," but "more structure." 

1.  **Unique Constraints**: Error on transaction if a unique attribute is violated.
2.  **Pull API**: A recursion-aware mapper from EAV to Dict.
3.  **RefID Lookup**: Finding an entity by its unique attribute (e.g., `[:user/email "rich@hickey.com"]`).

*This refines the raw energy of the facts into the stable architecture of a production-grade information system.*
