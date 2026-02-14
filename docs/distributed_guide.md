# Distributed GleamDB: The Sovereign Fabric 🌐

GleamDB supports a leader-follower distribution model powered by the BEAM's native distribution primitives and a **Raft-inspired election protocol** for zero-downtime failover.

## Architecture

The fabric uses a **Democratic Partitioning** model. The keyspace is divided into `N` shards, and each shard operates as an independent Raft cluster.

- **Leader Election**: Raft-inspired state machine (`raft.gleam`) handles term-based voting, heartbeat liveness, and majority quorum. De-complected from replication.
- **Forwarding**: Any transaction arriving at a follower is automatically forwarded to the current leader.
- **Replication**: Committed datom batches are broadcast from the leader to all connected followers via `SyncDatoms`.

## Usage

### Starting a Distributed Leader

To enable the Sovereign Fabric (consensus-based transaction forwarding), use `start_distributed`:

```gleam
import gleamdb
import gleamdb/storage

// On Node A (Leader)
let assert Ok(db) = gleamdb.start_distributed("production_db", Some(storage.sqlite("data.db")))
```

### Connecting from a Follower

Followers can connect to the shared namespace to receive real-time updates:

```gleam
// On Node B (Follower)
let assert Ok(db) = gleamdb.connect("production_db")
```

> [!NOTE]
> `start_named` enables local high-performance ETS indices but DOES NOT force global registration. Use `start_distributed` only when multi-node consensus is required.

### Transaction Semantics

Transactions on any node are ACID-guaranteed by the leader:

```gleam
gleamdb.transact(db, [
  p("user/1", "status", "active")
])
```

The leader will process the transaction, persist it, and then broadcast the resulting datoms to Node B, which will trigger local reactive updates.

## Raft Election Protocol (Phase 22)

GleamDB uses a **pure Raft state machine** for leader election:

- **Pure Core**: `raft.gleam` returns `#(RaftState, List(RaftEffect))` — zero side effects in the logic.
- **Election Timeout**: Randomized 150-300ms. On timeout, a follower becomes a candidate and requests votes.
- **Heartbeat**: Leaders send heartbeats every 50ms. Followers reset their election timer on receipt.
- **Term Monotonicity**: Any node seeing a higher term steps down to follower and updates its term.
- **Majority Quorum**: A candidate needs `(N/2 + 1)` votes to become leader.

### Split-Brain Prevention

The Raft protocol prevents split-brain by:
1. **Term-based voting**: Only one vote per term per node.
2. **Majority quorum**: A leader must win a majority — impossible for two leaders in the same term.
3. **Automatic step-down**: A leader receiving a higher-term heartbeat immediately steps down.

## Reliability

- **Network Partition**: If a follower loses connection, it remains readable (local cache) but cannot perform transactions until reconnected.
- **Autonomous Failover**: On leader failure, the Raft election protocol triggers automatic re-election. The first candidate to win a majority quorum becomes the new leader.
- **Zero-Downtime Promotion**: The new leader registers via `global:register_name` and begins accepting transactions immediately.

## Distributed Intelligent Engine

### Federation Localism
Virtual predicates are **resolved locally** on the node where the query is executing.
- **Requirement**: Adapters must be registered on every node in the cluster that will perform federated queries.
- **Logic**: This prevents massive data transfer overhead by allowing nodes to join their own local context with shared facts.

### Time Travel Consistency
The `diff(tx1, tx2)` operation is consistent across the cluster.
- **Shared History**: Since the `SyncDatoms` protocol replicates history to all participants, any follower can compute a local diff and reach the same conclusion as the leader.
- **Audit Anywhere**: You can perform temporal auditing on dedicated "Analysis Nodes" (followers) without impacting the throughput of the "Write Leader."
