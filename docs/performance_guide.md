# Performance Sovereignty: Silicon Saturation ⚡️

GleamDB leverages Erlang Term Storage (ETS) to achieve lock-free, concurrent read performance and O(1) attribute lookups.

## The Silicon Saturation Principle

Traditional databases often bottleneck on the coordination between writers and readers. GleamDB saturates the CPU by moving core indices out of actor state and into ETS.

- **Concurrent Reads**: Multiple query processes can scan `EAVT`, `AEVT`, and `AVET` indices simultaneously without sending messages to the Transactor actor.
- **Lock-Free Lookups**: ETS `read_concurrency` ensures that readers do not block each other, even under heavy load.

## Benchmarks & Scaling

- **Read Latency**: O(1) for direct attribute lookups via Silicon Saturation (ETS).
- **Ingestion Throughput**: 
    - **Durable Mnesia**: ~2,500 events/sec (single shard).
    - **Native Sharding**: >10,000 durable events/sec (8 shards on M3 Max).
    - **SQLite WAL**: ~120,000 datoms/sec.
- **Similarity Search**: O(log N) via NSW graph index (vs O(N) brute-force AVET scan).
- **Join Performance**: Datalog joins leverage ETS `duplicate_bag` matching, providing near-native BEAM performance for complex queries.
- **Memory Efficiency**: GleamDB uses optimized tuple structures to minimize memory overhead while maintaining searchability.

## Configuration

To enable Silicon Saturation (ETS), simply start your database with a name:

```gleam
// Enables ETS indices automatically
let db = gleamdb.start_named("fast_db", storage.ephemeral())
```

When `ets_name` is present in the `DbState`, the Datalog engine (`engine.gleam`) automatically switches from `Dict` lookups to direct ETS scans.

## NSW Vector Index

For similarity queries, GleamDB maintains a **Navigable Small-World (NSW) graph** alongside the standard EAVT/AEVT/AVET indices:

- **Auto-Indexing**: Vec values are automatically added to the NSW graph on assertion and removed on retraction.
- **Beam Search**: Greedy search with beam width 3 and configurable neighbor count (M=16).
- **Graph-Accelerated**: `solve_similarity` uses the NSW graph for unbound variables, falling back to AVET scan if the index is empty.

```gleam
// Similarity search uses NSW graph automatically
let query = [Similarity(Var("market"), [0.1, 0.2, 0.3], 0.9)]
let results = gleamdb.query(db, query)
```

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

### High-Frequency Tickers (The Gswarm Pattern)
In production scenarios like Gswarm (1000+ ticks/sec), combining `LatestOnly` with Mnesia's `persist_batch` is critical. This decouples the "current state" (held in lock-free ETS) from the "durability layer," allowing the system to maintain sub-millisecond responsiveness even under extreme write pressure.
