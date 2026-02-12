# Performance Sovereignty: Silicon Saturation ⚡️

GleamDB leverages Erlang Term Storage (ETS) to achieve lock-free, concurrent read performance and O(1) attribute lookups.

## The Silicon Saturation Principle

Traditional databases often bottleneck on the coordination between writers and readers. GleamDB saturates the CPU by moving core indices out of actor state and into ETS.

- **Concurrent Reads**: Multiple query processes can scan `EAVT`, `AEVT`, and `AVET` indices simultaneously without sending messages to the Transactor actor.
- **Lock-Free Lookups**: ETS `read_concurrency` ensures that readers do not block each other, even under heavy load.

## Benchmarks & Scaling

- **Read Latency**: O(1) for direct attribute lookups.
- **Join Performance**: Datalog joins leverage ETS `duplicate_bag` matching, providing near-native BEAM performance for complex queries.
- **Memory Efficiency**: GleamDB uses optimized tuple structures to minimize memory overhead while maintaining searchability.

## Configuration

To enable Silicon Saturation (ETS), simply start your database with a name:

```gleam
// Enables ETS indices automatically
let db = gleamdb.start_named("fast_db", storage.ephemeral())
```

When `ets_name` is present in the `DbState`, the Datalog engine (`engine.gleam`) automatically switches from `Dict` lookups to direct ETS scans.

## Advanced Patterns

### Parallel Querying

Since reads are lock-free, you can safely spawn multiple actors to perform parallel analytics:

```gleam
list.each(0..10, fn(_) {
  process.start(fn() {
    let results = engine.run(db, my_query, [], None)
    // Process results in parallel
  })
})
```

While reads are concurrent, writes remain serialized through the leader's Transactor. For maximum throughput, combine multiple facts into a single `transact` call to leverage batch persistence and replication.

## Memory Management: Fact Retention

High-frequency ingestion saturates memory quickly if history is infinite. Use **Retention Policies** to bound the growth:

```gleam
let config = fact.AttributeConfig(
  unique: False, 
  component: False, 
  retention: fact.LatestOnly
)
gleamdb.set_schema(db, "sensor/value", config)
```

Attributes with `LatestOnly` will prune their history during every transaction, ensuring O(1) memory for ephemeral streams while preserving permanent facts elsewhere.
