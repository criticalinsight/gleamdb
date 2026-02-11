# PRD: Phase 9 - The Completeness

**Status**: Draft
**Priority**: P0
**Owner**: Rich Hickey 🧙🏾‍♂️

## Overview
GleamDB has achieved Entity Purity, but it lacks the primitives for **Atomic Logic** (Transaction Functions) and **Rich Integrity** (Composite Constraints). This phase completes the engine's journey from a "Triple Store" to a "Durable System of Record."

## User Stories
- **As a Developer**, I want to run logic within the transactor (e.g., `increment`) so that I avoid race conditions during read-modify-update cycles.
- **As a System Architect**, I want to define composite unique constraints (e.g., `user/first-name` and `user/last-name`) so that I can enforce business-level entity integrity.
- **As an SRE**, I want the database to reject transactions that violate schema invariants (Schema Guards), ensuring the data is correct by construction.

## Acceptance Criteria
### Transaction Functions
- [ ] GIVEN a registered function `inc`
- [ ] WHEN I transact `[:db/fn "inc" [entity "age" 1]]`
- [ ] THEN the transactor resolves the current value, computes the increment, and persists the new fact atomically.
- [ ] FAILURE: If the function crashes, the entire transaction is rolled back (Mnesia transaction).

### Composite Uniqueness
- [ ] GIVEN a schema defining a unique composite `[attr-a, attr-b]`
- [ ] WHEN I transact facts that would create a duplicate pair
- [ ] THEN the transaction is rejected with a descriptive error.

### Schema Guards
- [ ] GIVEN an existing dataset
- [ ] WHEN I attempt to apply a schema change that contradicts existing data (e.g., making a non-unique attribute unique)
- [ ] THEN the schema update is rejected.

## Technical Implementation

### Database Schema Changes
- `DbState` will now store a `functions: Dict(String, fn(DbState, List(Value)) -> List(Fact))`.
- `CompositeConstraints: List(List(String))`.

### API
- `gleamdb.register_fn(db, name, func)`
- `gleamdb.transact_with_fn(db, name, args)`

### Visual Architecture (Mermaid)
```mermaid
sequence_diagram
    participant Client
    participant Transactor
    participant Registry
    participant Mnesia
    
    Client->>Transactor: Transact([:db/fn "inc" [1 "age"]])
    Transactor->>Registry: Lookup "inc"
    Registry-->>Transactor: FunctionPtr
    Transactor->>Transactor: Run(FunctionPtr, State, [1 "age"])
    Transactor->>Mnesia: Persist [[:db/add 1 "age" 31]]
    Mnesia-->>Transactor: Ok
    Transactor-->>Client: NewState
```

## Pre-Mortem Analysis
**Why will this fail?**
1. **Blocking the Writer**: If a transaction function performs heavy computation, it blocks all other writers (single-process transactor). 
   - *Mitigation*: Strictly enforce that transaction functions must be pure and "fast." No I/O allowed inside the function.
2. **Non-Determinism**: If a function uses `Now()` or `Random()`, replicas might drift.
   - *Mitigation*: Functions only receive the `DbState` and `Args`. Replicas receive the *resulting* datoms, not the function call itself.

## Phase 4: Autonomous Handoff
PRD Drafted. Initiate the Autonomous Pipeline: /proceed docs/specs/the_completeness.md -> /test -> /refactor -> /test
