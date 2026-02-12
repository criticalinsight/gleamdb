# Distributed GleamDB: The Sovereign Fabric 🌐

GleamDB supports a leader-follower distribution model powered by the BEAM's native distribution primitives.

## Architecture

The fabric uses a single leader for all transactions, while followers maintain real-time replicas for local-first reads and reactive updates.

- **Leader Election**: Uses Erlang's `global` module to register `gleamdb_leader`.
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

## Reliability

- **Network Partition**: If a follower loses connection to the leader, it remains readable (local cache) but cannot perform transactions until the connection is restored.
- **Autonomous Failover**: GleamDB leverages the BEAM's process monitoring for auto-healing. As demonstrated in the **Gswarm Fabric**, followers can monitor the leader's PID and trigger `node.promote_to_leader` if the link is severed.

### Failover Pattern (The Fabric Protocol)
When a follower detects a leader DOWN signal:
1.  Verify if the node should become the new leader (e.g., using `global:register_name`).
2.  Promote the local database context using `node.promote_to_leader`.
3.  Resume high-frequency ingestion and reactive reflexes locally.

This pattern ensures that the Sovereign Fabric remains resilient to single-node failures while maintaining linearizable consistency through a single active leader.
