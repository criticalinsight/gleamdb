# Learnings from Achieving Test Coverage

This document outlines the philosophical learnings from achieving broader test coverage in the `aarondb` project, specifically applying the **Rich Hickey** methodology of simplicity and immutability.

## 1. Emphasize Data-Driven Structural Boundaries
When testing components like the `aarondb/q` query builder, it is critical not to test what the DSL does internally in ways that are brittle. **Simplicity** means checking that the pure transformation reliably produces the expected raw data (the AST clauses). A test should be a sequence of operations verified by pattern-matching the resulting list of AST structures.

## 2. Serialization is Value Reconstitution
For `aarondb/fact` and `aarondb/rule_serde`, serialization and persistence convey facts about the world. A Datom or a Rule isn't behavior; it's a value. Testing serialization (`encode_compact`, `decode_compact`) involved pure round-trip evaluation. We simply checked whether the value reconstituted on the other side retained its original identity.

## 3. Avoid Complecting the Environment
Testing the `aarondb/cache` module using the actor model required verifying eviction policies without standing up the overarching distributed transactional datastore. By injecting a dummy invalidation function and pumping pure data into the actor boundary, the caching logic was tested in isolation. We avoided complecting our local cache assertions with the rest of the database logic.

These principles ensure that our test coverage does not become a tightly-coupled burden, but rather a flexible verification of independent state transformations.
