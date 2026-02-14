# Learnings: Sovereign Intelligence (Phase 31) 🧙🏾‍♂️

## 1. The `gleam/otp/task` Gap
**Issue**: We initially planned to use `gleam/otp/task` for parallel execution, but discovered it was missing from our dependency version or environment.
**Solution**: We fell back to `gleam/erlang/process`, using `process.spawn` (linked) and `process.new_subject` to implement a manual concurrent scatter-gather pattern.
**Learning**: Core BEAM primitives (`spawn`, `send`, `receive`) are often more reliable and flexible than higher-level abstractions when working in a constraints-heavy environment. This "manual" approach gave us fine-grained control over process linkage and error propagation.

## 2. Pure Aggregation Reducers
**Issue**: How to implement aggregators (`Sum`, `Avg`) that work on infinite streams without loading all data into memory?
**Solution**: We implemented aggregators as pure functional reducers in `gleamdb/algo/aggregate.gleam`.
- `Sum`: Accumulates `Int` or `Float` values, preserving type precision.
- `Avg`: Maintains a running `(Sum, Count)` tuple.
- `Median`: Requires buffering, proving that not all aggregates can be strictly streaming O(1) space.
**Learning**: Separating the *logic* of aggregation from the *execution* (engine) allows for easier testing and future extensibility (e.g., user-defined aggregates).

## 3. Parallelism Thresholds
**Issue**: Spawning a process for every query chunk has overhead.
**Decision**: We set a hardcoded threshold of **500 items** in the intermediate context before triggering parallel execution.
**Future Work**: This threshold should be dynamic or configurable based on system load and query complexity (cost-based optimization integration).

## 4. `int.range` Versioning
**Issue**: `gleam/int`'s `range` function had a different signature than expected (reducer style vs list generator) in the installed stdlib version.
**Solution**: Implemented a local recursive `range` helper for tests.
**Learning**: Always verify standard library documentation for the *specific installed version*, as rapid ecosystem evolution can lead to API drift.
