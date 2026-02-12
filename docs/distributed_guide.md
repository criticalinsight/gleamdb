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
- **Leader Failure**: In the current version, leader failover requires manual intervention or a global name reset. Future versions will support Raft-based automated failover.
