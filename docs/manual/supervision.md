# GleamDB Supervision & OTP 🛡️

> "Let it crash? No. Let it be supervised."

GleamDB is designed to be a good OTP citizen. In Phase 17, we standardized the supervision API to make embedding GleamDB into your application tree effortless.

## Architecture

GleamDB is not a single process; it is a **System of Actors**:

1.  **Transactor**: The "Writer". Serializes writes, manages the `DbState` value, and enforces schema guards.
2.  **Reactive Actor**: The "Listener". Manages subscriptions and broadcasts deltas to `Subscribe` callers.
3.  **Storage Engine**: (Optional) Mnesia or SQLite adapter process.

When you start GleamDB, you are starting a `supervisor` that manages these children.

## Key Functions

### `gleamdb.child_spec(adapter, timeout)`
Creates a standard OTP `ChildSpecification` for use in a supervisor's child list.

- **adapter**: `Option(StorageAdapter)`. Use `None` for generic Mnesia/RAM.
- **timeout**: `Int`. Time in milliseconds to wait for initialization.

**Usage:**
```gleam
import gleam/otp/supervision
import gleamdb
import gleam/option.{None}

pub fn start(path: String, _args: List(String)) {
  let children = [
    gleamdb.child_spec(None, 5000),
    // ... other workers
  ]
  
  supervision.start_link(children)
}
```

### `gleamdb.start_link(adapter, timeout)`
Starts the GleamDB process tree linked to the current process.
- **Returns**: `Result(Subject(gleamdb.Message), StartError)`
- **Use Case**: Manual starting or scripts (e.g., tests).

## Named Registration

To make GleamDB accessible globally (like a singleton database), you can register it:

```gleam
let assert Ok(db) = gleamdb.start_link(None, 1000)
let assert Ok(_) = gleamdb.register(db, "my_main_db")

// Later, in another process:
let assert Ok(db) = gleamdb.connect("my_main_db")
```

## Fault Tolerance
- **Crash**: If the Transactor crashes, the Supervisor restarts it.
- **State**: In-memory state is lost on crash unless a persistent adapter (SQLite/Mnesia) is used.
    - *Note*: Mnesia usage (default) persists across process restarts but not node restarts (unless configured for disc).

## Best Practices
1.  **Timeout**: Increase the timeout (>10s) if loading large datasets on startup (e.g., replaying a massive WAL).
2.  **One DB per App**: Usually sufficient. Multiple DBs are supported but rarely needed unless isolating domains strictly.
